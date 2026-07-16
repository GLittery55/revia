import Foundation
import Combine

@MainActor
final class ReflectionViewModel: ObservableObject {
    @Published var session = ReflectionSession()
    @Published var draft = ""
    @Published var isTyping = false
    @Published var contextDataStatus = "正在请求健康与日历访问权限…"
    @Published var affirmed = false
    @Published var ready = false
    @Published var isPaused = false
    @Published var saveNotice = ""
    @Published private(set) var llmStatus = ""
    @Published var exportURL: URL?

    private let llm: any LLMService
    private let cards = CardService()
    private let safety = SafetyService()
    private let store = SessionStore()
    private let health = HealthKitService()
    private let calendar = CalendarService()
    private var contextIndex = 0
    private var didRequestContextData = false

    let contextQuestions = [
        "发生了什么？请只描述一个有边界的具体片段。",
        "当时有哪些情绪或身体感受？",
        "这件事对你意味着什么？",
        "当时有哪些现实限制或背景？",
        "哪些部分是你能影响的，哪些仍不确定？",
        "你希望这次反思为你带来什么？"
    ]

    init(llm: (any LLMService)? = nil) {
        self.llm = llm ?? LLMFactory.make()
        self.llmStatus = self.llm.providerName
        session.messages = [.init(role: .assistant, content: "欢迎来到 Beyond Comfort。这里的卡片没有固定含义，AI 也可能理解错；抽卡不意味着你必须深入。App 会请求健康与日历读取权限，并把获得的数据作为谨慎理解状态的线索，而不是诊断或定论。你可以随时跳过、暂停或结束。")]
        session.studyEvents = [.init(stage: .orient, action: "session_started")]
    }

    func begin() {
        transition(to: .contextGathering, action: "reflection_started")
        addAssistant(contextQuestions[0] + " 我这样问，是为了让反思停留在一个可承受的范围内。")
    }

    func prepareRequiredContextData() async {
        guard !didRequestContextData else { return }
        didRequestContextData = true
        // System permission sheets must be presented serially. Presenting HealthKit and
        // EventKit authorization at the same time can leave one sheet waiting behind the
        // other and make the app appear unresponsive.
        contextDataStatus = "正在请求健康读取权限…"
        await health.requestAuthorization()

        contextDataStatus = "正在请求日历读取权限…"
        await calendar.requestAuthorization()
        await refreshContextData()
    }

    func refreshContextData() async {
        contextDataStatus = "正在读取事件时间附近的数据，并与个人基线比较…"
        async let healthCues = health.fetch(referenceDate: session.canvas.eventDate)
        async let calendarCues = calendar.fetch(referenceDate: session.canvas.eventDate)
        session.trackingCues = await healthCues + calendarCues
        updateFactors()
        if session.trackingCues.isEmpty {
            contextDataStatus = "未读取到数据。请检查系统授权、Apple Watch 数据和日历内容；反思仍可继续。"
        } else {
            let hasSleep = session.trackingCues.contains { $0.source == .healthSleep }
            let sleepStatus = hasSleep ? "已找到睡眠记录。" : "没有找到最近 30 天的睡眠记录，请检查健康权限和睡眠追踪。"
            contextDataStatus = "已读取 \(session.trackingCues.count) 条情境线索。\(sleepStatus)它们只用于谨慎推测状态，不作为诊断或因果证据。"
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        addUser(text)
        if safety.requiresInterrupt(text) { interruptForSafety(); return }

        switch session.stage {
        case .contextGathering: captureContext(text)
        case .tenderGrounding:
            transition(to: session.condition == .cardMediated ? .cardDraw : .candidInquiry, action: "tender_need_identified")
            if session.condition == .cardMediated { addAssistant("谢谢你指出需要被照顾的部分。准备好时，可以抽取一张没有固定答案的卡片。") }
            else { Task { await generate(for: .candidInquiry) } }
        case .cardInterpretation:
            session.cardInterpretation = text
            transition(to: .tenderExploration, action: "card_interpreted_by_user")
            Task { await generate(for: .tenderExploration) }
        case .tenderExploration:
            transition(to: .affirmationReadiness, action: "tender_exploration_answered")
            addAssistant("请明确选择：这个理解是否贴合，以及你是否愿意继续坦诚探索。任何一个答案是否定，都可以在这里平稳结束。")
        case .candidInquiry:
            Task { await generate(for: .candidInquiry) }
        default: break
        }
    }

    func skipContext() {
        guard session.stage == .contextGathering else { return }
        addUser("跳过这一项")
        advanceContext()
    }

    func confirmCanvas() {
        transition(to: .tenderGrounding, action: "context_confirmed")
        Task { await generate(for: .tenderGrounding) }
    }

    func drawCard() {
        guard session.stage == .cardDraw else { return }
        session.card = cards.draw()
        transition(to: .cardInterpretation, action: "card_drawn_uniform_random")
        addAssistant("先由你来解释：你最先注意到什么？它可能为你的处境带来什么——如果有的话？")
    }

    func resolveGate() {
        guard session.stage == .affirmationReadiness else { return }
        if affirmed && ready {
            transition(to: .candidInquiry, action: "affirmed_and_ready")
            Task { await generate(for: .candidInquiry) }
        } else { close(message: "我们可以停在已经得到的理解上，不需要勉强深入。") }
    }

    func setHypothesis(_ id: UUID, status: HypothesisStatus) {
        guard let index = session.hypotheses.firstIndex(where: { $0.id == id }) else { return }
        session.hypotheses[index].status = status
    }

    func proceedToAction() {
        transition(to: .actionComposer, action: "candid_inquiry_completed")
        Task { await generate(for: .actionComposer) }
    }
    func chooseAction(_ suggestion: ActionSuggestion) {
        session.action = ReflectionAction(type: suggestion.type, text: suggestion.text, feasibility: suggestion.rationale)
        review()
    }
    func chooseNotReady() {
        session.action = ReflectionAction(type: .notReady, text: "此刻暂不决定", feasibility: "允许答案晚一点出现")
        review()
    }
    func review() { transition(to: .reviewClose, action: "action_selected"); addAssistant("下面是本次记录。你的文字与模型提出的可能性会分开显示。是否保存完全由你决定。") }
    func close(message: String = "这次反思到这里结束。你可以保存或删除记录。") { transition(to: .reviewClose, action: "session_closed"); addAssistant(message) }
    func pause() { isPaused.toggle() }
    func end() { close() }
    func restart() { session = ReflectionSession(); contextIndex = 0; affirmed = false; ready = false; saveNotice = ""; session.messages = [.init(role: .assistant, content: "这是一次新的反思。你仍可随时跳过、暂停或结束。")]; session.studyEvents = [.init(stage: .orient, action: "session_started")] }

    func save() { Task { do { try await store.save(session); saveNotice = "已保存在本机" } catch { saveNotice = "保存失败" } } }
    func delete() { let id = session.id; Task { try? await store.delete(id: id); saveNotice = "本机记录已删除" } }
    func prepareExport() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeyondComfort-\(session.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(session).write(to: url, options: .atomic)
            exportURL = url
            saveNotice = "去标识化研究记录已准备好；自由文本仍可能包含个人信息，请导出前确认"
        } catch { saveNotice = "导出准备失败" }
    }

    func updateCue(_ cue: TrackingCue, included: Bool) {
        if let i = session.trackingCues.firstIndex(where: { $0.id == cue.id }) { session.trackingCues[i].included = included; updateFactors() }
    }

    private func captureContext(_ text: String) {
        switch contextIndex {
        case 0: session.canvas.event = text
        case 1: session.canvas.experience = text
        case 2: session.canvas.meaning = text
        case 3: session.canvas.constraints = text
        case 4: session.canvas.agencyAndUncertainty = text
        default: session.canvas.reflectiveIntention = text
        }
        advanceContext()
    }

    private func advanceContext() {
        contextIndex += 1
        if contextIndex < contextQuestions.count { addAssistant(contextQuestions[contextIndex] + " 这有助于把处境、感受与责任区分开。") }
        else { transition(to: .contextConfirmation, action: "context_gathering_completed"); addAssistant("请检查并编辑下面三个分开的区域。确认后我们才继续。") }
    }

    private func generate(for stage: ReflectionStage) async {
        isTyping = true
        defer { isTyping = false }
        do {
            let result = try await llm.respond(stage: stage, canvas: session.canvas, dialogue: session.messages, card: session.card, interpretation: session.cardInterpretation)
            addAssistant([result.reflectiveSummary, result.uncertaintyStatement, result.question].filter { !$0.isEmpty }.joined(separator: "\n\n"))
            if stage == .candidInquiry { session.hypotheses = result.hypotheses.prefix(2).map { Hypothesis(text: "一种可能性值得考虑：" + $0) } }
            if stage == .actionComposer {
                session.actionSuggestions = result.actionSuggestions.prefix(4).compactMap { item in
                    guard let type = ActionType(rawValue: item.type), type != .notReady else { return nil }
                    return ActionSuggestion(type: type, text: item.text, rationale: item.rationale)
                }
            }
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            addAssistant("DeepSeek 调用未成功：\(detail)。你仍可以继续、跳过或结束；这不会改变你已经写下的内容。")
        }
    }

    private func updateFactors() { session.canvas.contextualFactors = session.trackingCues.filter(\.included).map(\.observation).joined(separator: "\n") }
    private func addUser(_ text: String) { session.messages.append(.init(role: .user, content: text)) }
    private func addAssistant(_ text: String) { session.messages.append(.init(role: .assistant, content: text)) }
    private func transition(to stage: ReflectionStage, action: String) {
        session.stage = stage
        session.studyEvents.append(.init(stage: stage, action: action))
    }
    private func interruptForSafety() { transition(to: .safetyInterrupt, action: "safety_signal_detected"); addAssistant("我很在意你刚才提到的安全风险。这个应用不能提供危机干预，请立即联系当地急救服务或可信任的人。在中国大陆可拨打 120/110；若身处其他地区，请联系当地紧急服务。我们不会继续抽卡或坦诚探索。") }
}
