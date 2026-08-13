import SwiftUI
import UIKit
import Charts

struct ContentView: View {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var model = ReflectionViewModel()
    @StateObject private var studyAdministration = StudyAdministrationViewModel()

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView(auth: auth, model: model, studyAdministration: studyAdministration)
            } else {
                AccountGateView(auth: auth)
            }
        }
        .tint(Color(red: 0.34, green: 0.28, blue: 0.72))
        .task { await auth.restoreSession() }
        .onChange(of: auth.isAuthenticated, initial: true) { _, authenticated in
            model.setCloudSyncEnabled(authenticated)
            if authenticated {
                Task {
                    await model.configureStudy()
                    await model.prepareRequiredContextData()
                    await studyAdministration.refresh()
                }
            }
        }
    }
}

private struct MainTabView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var model: ReflectionViewModel
    @ObservedObject var studyAdministration: StudyAdministrationViewModel
    @State private var showingReturnHomeConfirmation = false

    var body: some View {
        TabView {
            NavigationStack {
                ChatView(model: model)
                    .navigationTitle("Beyond Comfort")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismissKeyboard()
                                if model.session.stage == .completed {
                                    Task { await model.returnHomeAfterCompletion() }
                                } else if model.session.stage != .welcome {
                                    showingReturnHomeConfirmation = true
                                }
                            } label: {
                                Label("返回首页", systemImage: "house")
                            }
                            .accessibilityHint("收起键盘并返回反思首页")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("暂停并保存") {
                                    dismissKeyboard()
                                    Task { await model.pauseAndReturnHome() }
                                }
                                .disabled(model.session.stage == .welcome || model.session.stage == .completed || model.isTyping)
                                Button("结束并查看记录") { dismissKeyboard(); model.end() }
                                Button("删除并重新开始", role: .destructive) {
                                    dismissKeyboard()
                                    model.delete()
                                }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        }
                    }
                    .confirmationDialog("返回首页？", isPresented: $showingReturnHomeConfirmation, titleVisibility: .visible) {
                        Button("保留当前记录并返回首页") {
                            dismissKeyboard()
                            Task { await model.pauseAndReturnHome() }
                        }
                        Button("继续当前对话", role: .cancel) {}
                    } message: {
                        Text("当前进度会暂停保存。之后可以继续上一次，也可以开始新的反思。")
                    }
                    .overlay { if model.isPaused { PauseOverlay { model.pause() } } }
                    .sheet(isPresented: $model.isResumeChoicePresented) {
                        if let candidate = model.resumeCandidate {
                            ResumeChoiceView(model: model, candidate: candidate)
                        }
                    }
            }
            .tabItem { Label("对话", systemImage: "ellipsis.message.fill") }

            NavigationStack { ReflectionHistoryView(model: model) }
                .tabItem { Label("反思记录", systemImage: "text.book.closed") }

            NavigationStack { ProfileView(auth: auth, model: model, studyAdministration: studyAdministration) }
                .tabItem { Label("我的", systemImage: "person.fill") }
        }
    }
}

private struct ResumeChoiceView: View {
    @ObservedObject var model: ReflectionViewModel
    let candidate: ResumableReflection

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.indigo)
                Text("你有一段未完成的反思")
                    .font(.title2.bold())
                Text("上次的内容更新于 \(candidate.updatedAt.formatted(date: .abbreviated, time: .shortened))。")
                    .foregroundStyle(.secondary)
                Text(lastUserMessage)
                    .lineLimit(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
                Button("继续上一次") { model.resume(candidate) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("开始新的反思") { model.startNewInsteadOfResuming() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("稍后再说") { model.dismissResumeChoice() }
                    .frame(maxWidth: .infinity)
                Text("开始新的反思不会删除上一次记录，你仍可在“反思记录”中查看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .navigationTitle("继续反思")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { model.dismissResumeChoice() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var lastUserMessage: String {
        candidate.session.messages.last(where: { $0.role == .user })?.content ?? "上一次反思已暂停保存。"
    }

}

private struct AccountGateView: View {
    @ObservedObject var auth: AuthViewModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white, Color(red: 0.95, green: 0.94, blue: 1), Color(red: 0.98, green: 0.96, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 38)
                    BrandMark()
                    VStack(spacing: 7) {
                        Text("Beyond Comfort").font(.largeTitle.bold()).foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.67))
                        Text("在舒适之外，遇见更真实的自己").foregroundStyle(.secondary)
                    }
                    VStack(spacing: 16) {
                        Picker("账户方式", selection: $auth.isRegistering) {
                            Text("注册").tag(true)
                            Text("登录").tag(false)
                        }.pickerStyle(.segmented)
                        TextField("用户名（3–40 位字母、数字或 _ -）", text: $auth.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                            .padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                        SecureField("密码（至少 10 位）", text: $auth.password)
                            .textContentType(auth.isRegistering ? .newPassword : .password)
                            .padding(14).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                        if auth.isRegistering {
                            Toggle(isOn: $auth.consentAccepted) {
                                Text("我同意将对话、卡片解释、自我追踪摘要和反思结果加密上传到研究数据库。自由文本可能包含个人信息。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.toggleStyle(.switch)
                        }
                        if !auth.errorMessage.isEmpty {
                            Text(auth.errorMessage).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button { Task { await auth.submit() } } label: {
                            HStack { if auth.isWorking { ProgressView().tint(.white) }; Text(auth.isRegistering ? "同意并创建账户" : "登录") }
                                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).disabled(auth.isWorking)
                        Text("你可随时暂停、删除一次反思，或在“我的”中退出账户。")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 24)
                }.padding(.bottom, 30)
            }
        }
    }
}

private struct BrandMark: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.purple.opacity(0.45), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 52, height: 52).offset(x: -14)
            Circle().fill(LinearGradient(colors: [.indigo.opacity(0.85), .purple.opacity(0.25)], startPoint: .bottomLeading, endPoint: .topTrailing)).frame(width: 52, height: 52).offset(x: 14)
        }.frame(width: 90, height: 60)
    }
}

private struct ReflectionHistoryView: View {
    @ObservedObject var model: ReflectionViewModel
    @State private var remoteSessions: [RemoteSessionSummary] = []
    @State private var loadError = ""
    @State private var isLoading = false

    var body: some View {
        List {
            Section("当前反思") {
                LabeledContent("状态", value: reflectionDisplayStatus(model.session.stage))
                LabeledContent("对话条数", value: "\(model.session.messages.count)")
                Text(model.cloudStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("云端反思记录") {
                if isLoading && remoteSessions.isEmpty {
                    HStack { Spacer(); ProgressView("正在读取记录…"); Spacer() }
                }
                ForEach(remoteSessions) { item in
                    NavigationLink {
                        ReflectionHistoryDetailView(summary: item)
                    } label: {
                        ReflectionHistoryRow(summary: item)
                    }
                }
                if !isLoading && remoteSessions.isEmpty && loadError.isEmpty {
                    ContentUnavailableView(
                        "还没有历史对话",
                        systemImage: "text.book.closed",
                        description: Text("暂停或结束一次反思后，可以在这里查看完整对话。")
                    )
                }
                if !loadError.isEmpty { Text(loadError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("反思记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(isLoading)
                    .accessibilityLabel("刷新历史记录")
            }
        }
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            remoteSessions = try await RemoteAPIService.shared.listReflectionSessions()
            loadError = ""
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ReflectionHistoryRow: View {
    let summary: RemoteSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .fontWeight(.semibold)
                Spacer()
                Text(reflection?.stage == .completed ? "已结束" : "未完成")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reflection?.stage == .completed ? Color.secondary : Color.indigo)
            }
            Text(historyStageName(reflection?.stage, fallback: summary.stage))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastUserMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var reflection: ReflectionSession? { decodeHistorySession(summary) }
    private var lastUserMessage: String {
        reflection?.messages.last(where: {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content ?? "打开查看这次反思的内容"
    }
}

private struct ReflectionHistoryDetailView: View {
    let summary: RemoteSessionSummary

    var body: some View {
        Group {
            if let reflection {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        historyHeader(reflection)

                        Text("完整对话")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let visibleMessages = reflection.messages.filter {
                            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                        if visibleMessages.isEmpty {
                            Text("这次记录中没有已保存的对话内容。")
                                .foregroundStyle(.secondary)
                                .cardStyle()
                        } else {
                            ForEach(visibleMessages) { message in
                                MessageBubble(message: message)
                            }
                        }

                        if let card = reflection.card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Reflection Card").font(.headline)
                                CardView(card: card)
                                if let interpretation = reflection.context.cardInterpretation, !interpretation.isEmpty {
                                    Text("你的解释").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(interpretation)
                                }
                            }
                            .cardStyle()
                        }

                        if let action = reflection.context.selectedAction, action.acceptedByUser {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("自我关怀实践").font(.headline)
                                Label(action.category.title, systemImage: "heart.text.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.indigo)
                                Text(action.description)
                                if let timing = action.timing, !timing.isEmpty {
                                    Text(timing)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .cardStyle()
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "暂时无法打开这条记录",
                    systemImage: "exclamationmark.bubble",
                    description: Text("这条会话尚未完成首次同步，或来自不兼容的旧版本。")
                )
            }
        }
        .navigationTitle(summary.createdAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reflection: ReflectionSession? { decodeHistorySession(summary) }

    @ViewBuilder
    private func historyHeader(_ reflection: ReflectionSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    reflection.stage == .completed ? "已结束" : "未完成",
                    systemImage: reflection.stage == .completed ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reflection.stage == .completed ? Color.secondary : Color.indigo)
                Spacer()
                Text("只读记录").font(.caption).foregroundStyle(.secondary)
            }
            Text("创建于 \(summary.createdAt.formatted(date: .long, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("状态：\(reflectionDisplayStatus(reflection.stage))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private func decodeHistorySession(_ summary: RemoteSessionSummary) -> ReflectionSession? {
    guard let data = try? JSONEncoder().encode(summary.payload) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(ReflectionSession.self, from: data)
}

private func reflectionDisplayStatus(_ stage: ReflectionStage?) -> String {
    stage == .completed ? "已结束" : "进行中"
}

private func historyStageName(_ stage: ReflectionStage?, fallback: String) -> String {
    if let stage { return reflectionDisplayStatus(stage) }
    return fallback == ReflectionState.completed.rawValue ? "已结束" : "进行中"
}

private struct ProfileView: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var model: ReflectionViewModel
    @ObservedObject var studyAdministration: StudyAdministrationViewModel
    var body: some View {
        Form {
            Section("账户") {
                LabeledContent("用户名", value: auth.user?.username ?? "")
                LabeledContent("数据同意版本", value: auth.user?.consentVersion ?? "")
            }
            Section("同步") { Text(model.cloudStatus) }
            Section("数据说明") {
                Text("对话内容、卡片解释、你确认相关的背景记录与反思结果会保存到该账户的云端会话中。")
            }
            Section("本机数据") {
                Button("删除全部本机反思数据", role: .destructive) {
                    model.deleteAllLocalReflectionData()
                }
            }
            if studyAdministration.isAdministrator {
                Section("研究管理") {
                    NavigationLink("管理参与者的体验安排") {
                        StudyAdministrationView(model: studyAdministration)
                    }
                }
            }
            Button("退出登录", role: .destructive) { Task { await auth.logout() } }
        }.navigationTitle("我的")
    }
}

private struct StudyAdministrationView: View {
    @ObservedObject var model: StudyAdministrationViewModel

    var body: some View {
        List {
            Section {
                Text("设置体验顺序、两期开放时间，或暂停某位参与者。参与者只能在管理员开放的时间开始当前版本。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = nonEmptyError {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("参与者") {
                if model.isLoading {
                    ProgressView("正在读取安排…")
                } else if model.participants.isEmpty {
                    Text("暂时没有可管理的参与者。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.participants) { participant in
                        NavigationLink {
                            StudyScheduleEditor(
                                participant: participant,
                                existingSchedule: model.schedule(for: participant),
                                model: model
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(participant.username)
                                Text(scheduleSummary(for: participant))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("研究管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") { Task { await model.refresh() } }
                    .disabled(model.isLoading)
            }
        }
        .task { await model.refresh() }
    }

    private var nonEmptyError: String? {
        model.errorMessage.isEmpty ? nil : model.errorMessage
    }

    private func scheduleSummary(for participant: StudyParticipant) -> String {
        guard let schedule = model.schedule(for: participant) else { return "尚未安排" }
        guard schedule.enabled else { return "已暂停" }
        guard let firstStart = schedule.periodOneStartsAt else { return "等待设置第一期时间" }
        return "第一期：\(firstStart.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct StudyScheduleEditor: View {
    let participant: StudyParticipant
    let existingSchedule: StudySchedule?
    @ObservedObject var model: StudyAdministrationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sequence: StudySequence
    @State private var firstPeriodIsScheduled: Bool
    @State private var firstPeriodStart: Date
    @State private var secondPeriodIsScheduled: Bool
    @State private var secondPeriodStart: Date
    @State private var enabled: Bool
    @State private var isSaving = false

    init(participant: StudyParticipant, existingSchedule: StudySchedule?, model: StudyAdministrationViewModel) {
        self.participant = participant
        self.existingSchedule = existingSchedule
        self.model = model
        let defaultStart = Date()
        _sequence = State(initialValue: existingSchedule?.sequence ?? .cardFirst)
        _firstPeriodIsScheduled = State(initialValue: existingSchedule?.periodOneStartsAt != nil)
        _firstPeriodStart = State(initialValue: existingSchedule?.periodOneStartsAt ?? defaultStart)
        _secondPeriodIsScheduled = State(initialValue: existingSchedule?.periodTwoStartsAt != nil)
        _secondPeriodStart = State(
            initialValue: existingSchedule?.periodTwoStartsAt
                ?? Calendar.current.date(byAdding: .day, value: 7, to: defaultStart)!
        )
        _enabled = State(initialValue: existingSchedule?.enabled ?? true)
    }

    var body: some View {
        Form {
            Section("参与者") { Text(participant.username) }
            Section("体验顺序") {
                Picker("顺序", selection: $sequence) {
                    Text("卡牌版先，直接版后").tag(StudySequence.cardFirst)
                    Text("直接版先，卡牌版后").tag(StudySequence.directFirst)
                }
            }
            Section("第一期") {
                Toggle("开放第一期", isOn: $firstPeriodIsScheduled)
                if firstPeriodIsScheduled {
                    DatePicker("开始时间", selection: $firstPeriodStart)
                }
            }
            Section("第二期") {
                Toggle("安排第二期", isOn: $secondPeriodIsScheduled)
                if secondPeriodIsScheduled {
                    DatePicker("切换时间", selection: $secondPeriodStart)
                }
            }
            Section("状态") {
                Toggle("允许参与者开始体验", isOn: $enabled)
            }
            if !model.errorMessage.isEmpty {
                Section { Text(model.errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("安排体验")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .disabled(isSaving || !hasValidDates)
            }
        }
    }

    private var hasValidDates: Bool {
        !secondPeriodIsScheduled || !firstPeriodIsScheduled || secondPeriodStart > firstPeriodStart
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await model.save(
                participant: participant,
                sequence: sequence,
                periodOneStartsAt: firstPeriodIsScheduled ? firstPeriodStart : nil,
                periodTwoStartsAt: secondPeriodIsScheduled ? secondPeriodStart : nil,
                enabled: enabled
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct ChatView: View {
    @ObservedObject var model: ReflectionViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversationItems) { item in
                            switch item {
                            case .message(let message):
                                MessageBubble(message: message).id(message.id)
                            case .card(let card, _):
                                CardMessageBubble(
                                    card: card,
                                    onImageReady: { model.cardDidDisplay(cardID: card.id) },
                                    onImageFailure: { model.cardDisplayDidFail(cardID: card.id) }
                                )
                                .id("card-message-\(card.id)-\(model.session.cardDisplayReloadNonce)")
                            }
                        }
                        if model.isTyping && !model.isStreamingResponse { TypingIndicator() }
                        StagePanel(model: model).id("stage-panel")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
                .onChange(of: model.session.messages.count) { _, _ in
                    scrollToLatestMessage(proxy, animated: true)
                }
                .onChange(of: model.session.stage) { _, stage in
                    Task { @MainActor in
                        await Task.yield()
                        scrollForStage(stage, proxy: proxy, animated: true)
                    }
                }
                .onChange(of: model.streamRevision) { _, _ in
                    scrollToLatestMessage(proxy, animated: false)
                }
                .onChange(of: model.canCompleteSimpleGentleControl) { _, available in
                    guard available else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("stage-panel", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: model.hasReachedSimpleGentleControlSoftBoundary) { _, reached in
                    guard reached else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("stage-panel", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: inputFocused) { _, focused in
                    guard focused else { return }
                    Task { @MainActor in
                        await Task.yield()
                        scrollToLatestMessage(proxy, animated: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                    guard inputFocused else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard inputFocused else { return }
                        scrollToLatestMessage(proxy, animated: true)
                    }
                }
                .task(id: model.session.id) {
                    await Task.yield()
                    scrollForStage(model.session.stage, proxy: proxy, animated: false)
                }
            }
            .id(model.session.id)
            if acceptsText {
                Divider()
                HStack(alignment: .bottom) {
                    PasteButton(payloadType: String.self) { strings in
                        guard let pasted = strings.first, !pasted.isEmpty else { return }
                        model.draft += model.draft.isEmpty ? pasted : "\n" + pasted
                        Task { @MainActor in
                            inputFocused = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("粘贴")
                    TextField("写下你的回应…", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                    Button(action: model.send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(
                            model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || model.isTyping
                                || model.isStreamingResponse
                                || model.isOpeningTrackingReview
                        )
                }.padding(12)
            }
        }
        .background(LinearGradient(colors: [Color(.systemGroupedBackground), Color.purple.opacity(0.045)], startPoint: .top, endPoint: .bottom))
    }

    private var acceptsText: Bool {
        [
            .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
            .contextDisclosure, .tenderGrounding, .tenderExploration, .cardInterpretation,
            .trackingReview, .readinessCheck, .attributionReflection, .actionSelection,
        ].contains(model.session.stage)
    }

    private var conversationItems: [ConversationItem] {
        var items = model.session.messages.compactMap { message -> ConversationItem? in
            guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return .message(message)
        }
        if let card = model.session.card {
            let drawnAt = model.session.cardDrawRecord?.drawnAt
                ?? model.session.messages.last?.createdAt
                ?? model.session.createdAt
            items.append(.card(card, drawnAt: drawnAt))
        }
        return items.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.order < rhs.order
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var latestVisibleMessageID: UUID? {
        model.session.messages.last {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, animated: Bool) {
        if model.canCompleteSimpleGentleControl {
            let action = { proxy.scrollTo("stage-panel", anchor: .bottom) }
            if animated {
                withAnimation(.easeOut(duration: 0.2), action)
            } else {
                action()
            }
            return
        }
        guard let messageID = latestVisibleMessageID else {
            scrollForStage(model.session.stage, proxy: proxy, animated: animated)
            return
        }
        let action = { proxy.scrollTo(messageID, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    private func scrollForStage(
        _ stage: ReflectionState,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action: () -> Void
        switch stage {
        case .welcome:
            action = { proxy.scrollTo("stage-panel", anchor: .top) }
        case .cardIntroduction, .cardInterpretation, .summary, .completed, .safetySupport:
            action = { proxy.scrollTo("stage-panel", anchor: .bottom) }
        default:
            guard let messageID = latestVisibleMessageID else { return }
            action = { proxy.scrollTo(messageID, anchor: .bottom) }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }
}

private enum ConversationItem: Identifiable {
    case message(ChatMessage)
    case card(ReflectionCard, drawnAt: Date)

    var id: String {
        switch self {
        case .message(let message): "message-\(message.id.uuidString)"
        case .card(let card, _): "card-\(card.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt
        case .card(_, let drawnAt): drawnAt
        }
    }

    var order: Int {
        switch self {
        case .message: 0
        case .card: 1
        }
    }
}

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 54) }
            if message.role != .user {
                Image(systemName: "face.smiling.inverse")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [.purple.opacity(0.65), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .accessibilityHidden(true)
            }
            Text(message.content).font(.body).foregroundStyle(message.role == .user ? .white : .primary).padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.role == .user ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: RoundedRectangle(cornerRadius: 18))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
            if message.role != .user { Spacer(minLength: 54) }
        }
    }
}

private struct CardMessageBubble: View {
    let card: ReflectionCard
    var onImageReady: (() -> Void)? = nil
    var onImageFailure: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "face.smiling.inverse")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [.purple.opacity(0.65), .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .accessibilityHidden(true)

            CardView(
                card: card,
                onImageReady: onImageReady,
                onImageFailure: onImageFailure
            )
            .frame(maxWidth: 360)

            Spacer(minLength: 24)
        }
    }
}

private struct StagePanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        Group {
            switch model.session.stage {
            case .welcome: OrientPanel(model: model)
            case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure:
                if model.canCompleteSimpleGentleControl {
                    VStack(spacing: 8) {
                        if model.hasReachedSimpleGentleControlSoftBoundary {
                            Text("如果还有想谈的内容，可以继续；也可以在这里结束本次反思。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("结束本次反思", action: model.finishSimpleGentleControl)
                            .buttonStyle(.bordered)
                            .disabled(model.isTyping || model.isStreamingResponse)
                    }
                } else if !model.session.usesLLMTurnController {
                    Button("这一项暂不确定", action: model.skipCurrentDisclosure).buttonStyle(.bordered)
                }
            case .trackingPermission, .trackingReview, .readinessCheck:
                EmptyView()
            case .cardIntroduction:
                if model.session.cardDisplayState == .loadFailed {
                    Text("卡片图片没有成功显示。可以重新加载刚才抽到的这张卡；图片出现前不用解读。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("重新加载这张卡", action: model.retryCardDisplay)
                        .buttonStyle(.borderedProminent)
                } else {
                    if model.session.card == nil {
                        ProgressView("正在抽取卡片…")
                    }
                }
            case .cardInterpretation, .attributionReflection:
                EmptyView()
            case .actionSelection: EmptyView()
            case .summary, .completed: ReviewPanel(model: model)
            case .safetySupport: Button("结束本次流程", action: model.end).buttonStyle(.borderedProminent)
            case .tenderGrounding, .tenderExploration: EmptyView()
            }
            if model.canRetry {
                Button("重试", action: model.retryLastRequest)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OrientPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let candidate = model.resumeCandidate {
                Button {
                    model.presentResumeChoice()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("继续未完成的反思")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("暂停于 \(candidate.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            if model.session.condition.usesCard {
                SelfTrackingDashboard(model: model)
            }
            Button("开始一次反思") { Task { await model.refreshStudyAccessAndBegin() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!model.canBeginStudy)
            Text(model.studyAvailabilityMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !model.canBeginStudy {
                Button("检查最新安排") { Task { await model.configureStudy() } }
                    .buttonStyle(.bordered)
            }
        }.cardStyle()
    }
}

private struct SelfTrackingDashboard: View {
    @ObservedObject var model: ReflectionViewModel
    private let sources: [TrackingSource] = [.healthSleep, .healthHeartRate, .healthHRV, .healthSteps, .calendarLoad]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近 7 天数据概览").font(.headline)
                    Text(dateRange).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refreshContextData() }
                } label: {
                    if model.isLoadingContextData || model.isPreparingContextData {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.isLoadingContextData || model.isPreparingContextData)
                .accessibilityLabel("重新读取最近七天数据")
            }

            Text(model.contextDataStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let refreshedAt = model.contextDataRefreshedAt {
                Label("更新于 \(refreshedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(sources, id: \.rawValue) { source in
                TrackingMetricCard(
                    source: source,
                    cue: model.session.trackingCues.first { $0.source == source && $0.insight?.metric != .sleepTiming },
                    sleepDetailCues: source == .healthSleep
                        ? model.session.trackingCues.filter {
                            guard let metric = $0.insight?.metric else { return false }
                            return metric == .sleepTiming || metric == .sleepWakeTime || metric == .sleepContinuity
                        }
                        : nil
                )
            }

            Label("这些图表只用于核对读取结果。开始聊天后，对话会把有足够记录支持的睡眠、日程、活动和心率差异分开列为背景，请你判断哪些贴近；没有得到你确认的记录不会用于后续解释，也不会被当作原因或责任证据。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dateRange: String {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: model.session.context.eventDate)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        return "\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
    }
}

private struct TrackingMetricCard: View {
    let source: TrackingSource
    let cue: TrackingCue?
    let sleepDetailCues: [TrackingCue]?
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(cue?.metrics == nil ? "未读取" : "已读取")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cue?.metrics == nil ? Color.secondary : Color.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((cue?.metrics == nil ? Color.secondary : Color.green).opacity(0.1), in: Capsule())
            }

            if let cue, let metrics = cue.metrics {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(summaryValue(metrics))
                        .font(.title2.bold())
                    Text(summaryCaption(metrics))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                metricChart(metrics)

                Text(coverageText(metrics))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if source == .healthSleep {
                    SleepDetails(insights: sleepDetailCues?.compactMap(\.insight) ?? [])
                }

                if let insight = cue.insight {
                    TrackingInsightSummary(insight: insight)
                }

                DisclosureGroup("查看每日明细", isExpanded: $showsDetails) {
                    VStack(spacing: 7) {
                        ForEach(metrics.daily) { point in
                            HStack {
                                Text(point.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                                Spacer()
                                Text(pointText(point, metrics: metrics))
                                    .foregroundStyle(point.value == nil ? .secondary : .primary)
                            }
                            .font(.caption)
                        }
                        Divider()
                        Text(cue.observation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.medium))
            } else {
                Text(missingMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(13)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.13)))
    }

    @ViewBuilder
    private func metricChart(_ metrics: TrackingMetrics) -> some View {
        Chart {
            ForEach(metrics.daily) { point in
                if let value = point.value {
                    if source == .healthSleep || source == .calendarLoad {
                        BarMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value(metrics.unit, value)
                        )
                        .foregroundStyle(tint.gradient)
                        .cornerRadius(4)
                    } else {
                        LineMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value(metrics.unit, value)
                        )
                        .foregroundStyle(tint)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value(metrics.unit, value)
                        )
                        .foregroundStyle(tint)
                    }
                }
            }
        }
        .chartXScale(domain: chartDomain(metrics))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: 125)
        .accessibilityLabel("\(title)最近七天图表")
    }

    private func chartDomain(_ metrics: TrackingMetrics) -> ClosedRange<Date> {
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: metrics.periodEnd) ?? metrics.periodEnd
        return metrics.periodStart...upper
    }

    private func summaryValue(_ metrics: TrackingMetrics) -> String {
        guard let value = metrics.summaryValue else { return "—" }
        switch source {
        case .healthSleep, .calendarLoad: return String(format: "%.1f", value)
        case .healthHeartRate, .healthHRV, .healthSteps: return "\(Int(value.rounded()))"
        }
    }

    private func summaryCaption(_ metrics: TrackingMetrics) -> String {
        switch source {
        case .healthSleep: "\(metrics.unit)中位数"
        case .healthHeartRate, .healthHRV, .healthSteps: "\(metrics.unit) · 7 天中位数"
        case .calendarLoad: "\(metrics.unit) · 定时日程合计"
        }
    }

    private func coverageText(_ metrics: TrackingMetrics) -> String {
        let recordedDays = metrics.daily.filter { $0.value != nil && ($0.count > 0 || source == .calendarLoad) }.count
        switch source {
        case .healthSleep: return "\(recordedDays)/7 晚有记录 · \(metrics.sampleCount) 条睡眠分段"
        case .healthHeartRate, .healthHRV, .healthSteps: return "\(recordedDays)/7 天有记录 · \(metrics.sampleCount) 条样本"
        case .calendarLoad: return "\(metrics.sampleCount) 个日程 · 只读取时间，不读取标题和内容"
        }
    }

    private func pointText(_ point: TrackingDataPoint, metrics: TrackingMetrics) -> String {
        guard let value = point.value else { return "无记录" }
        switch source {
        case .healthSleep:
            return "\(String(format: "%.1f", value)) 小时 · \(point.count) 条分段"
        case .healthHeartRate, .healthHRV, .healthSteps:
            return "\(Int(value.rounded())) \(metrics.unit) · \(point.count) 条"
        case .calendarLoad:
            return "\(String(format: "%.1f", value)) 小时 · \(point.count) 个日程"
        }
    }

    private var title: String {
        switch source {
        case .healthSleep: "睡眠"
        case .healthHeartRate: "静息心率"
        case .healthHRV: "HRV（SDNN）"
        case .healthSteps: "步数"
        case .calendarLoad: "日程负荷"
        }
    }

    private var icon: String {
        switch source {
        case .healthSleep: "bed.double.fill"
        case .healthHeartRate: "heart.fill"
        case .healthHRV: "waveform.path.ecg"
        case .healthSteps: "figure.walk"
        case .calendarLoad: "calendar"
        }
    }

    private var tint: Color {
        switch source {
        case .healthSleep: .indigo
        case .healthHeartRate: .red
        case .healthHRV: .purple
        case .healthSteps: .green
        case .calendarLoad: .orange
        }
    }

    private var missingMessage: String {
        switch source {
        case .calendarLoad:
            "未读取到日程。请检查日历完整访问权限；如果权限正常，也可能是这 7 天没有日程。"
        default:
            "HealthKit 未返回这项记录。可能是没有数据、Apple Watch 尚未同步，或读取权限未开放。"
        }
    }
}

private struct SleepDetails: View {
    let insights: [TrackingInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("作息与记录连续性", systemImage: "moon.stars.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("HealthKit 不提供主观睡眠质量评分；这里展示的是作息和设备记录区间的连续程度，需要由你自己判断它是否反映了睡得好不好。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.indigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private var details: [String] {
        insights.compactMap { insight in
            guard let recent = insight.recentMedian else { return nil }
            switch insight.metric {
            case .sleepTiming:
                var text = "入睡时间中位数约为 \(clockTime(recent))"
                if let difference = insight.absoluteDifference {
                    text += "；比个人近期水平约\(Int((abs(difference) * 60).rounded()))分钟\(difference >= 0 ? "更晚" : "更早")"
                }
                if let spread = insight.interquartileRange {
                    text += "；有记录夜晚的波动范围约 \(String(format: "%.1f", spread)) 小时"
                }
                return text + "。"
            case .sleepWakeTime:
                var text = "醒来时间中位数约为 \(clockTime(recent))"
                if let difference = insight.absoluteDifference {
                    text += "；比个人近期水平约\(Int((abs(difference) * 60).rounded()))分钟\(difference >= 0 ? "更晚" : "更早")"
                }
                return text + "。"
            case .sleepContinuity:
                var text = "设备记录的睡眠区间连续程度约为 \(Int((recent * 100).rounded()))%"
                if let difference = insight.absoluteDifference {
                    text += "；比个人近期水平约\(Int((abs(difference) * 100).rounded()))个百分点\(difference >= 0 ? "更高" : "更低")"
                }
                return text + "。"
            default:
                return nil
            }
        }
    }

    private func clockTime(_ value: Double) -> String {
        let minutes = Int((value * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", max(minutes, 0) / 60, max(minutes, 0) % 60)
    }
}

private struct TrackingInsightSummary: View {
    let insight: TrackingInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(strengthText, systemImage: "chart.line.text.clipboard")
                Text("·")
                Text(insight.coverageDescription)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.indigo)

            if let baseline = insight.baselineDescription {
                Text(baseline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(insight.limitations.prefix(2)), id: \.self) { limitation in
                Label(limitation, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("这是一条中性背景记录，不证明原因、压力或责任。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(Color.indigo.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var strengthText: String {
        switch insight.strength {
        case .descriptiveOnly: "仅描述记录"
        case .baselineComparison: "已与个人基线比较"
        case .persistentPattern: "连续多日出现的记录变化"
        }
    }
}

private struct CardView: View {
    let card: ReflectionCard
    var onImageReady: (() -> Void)? = nil
    var onImageFailure: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ReflectionCardImage(imageName: card.imageName) { loaded in
                if loaded { onImageReady?() } else { onImageFailure?() }
            }
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .accessibilityLabel("反思卡画面")
            Text("没有固定含义 · 以你的解读为准").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
    }
}

private struct ReflectionCardImage: View {
    let imageName: String
    let onLoad: (Bool) -> Void

    var body: some View {
        Group {
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView(
                    "卡片图片无法加载",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("暂时无法显示这张卡的画面")
                )
                .frame(height: 280)
            }
        }
        .onAppear { onLoad(croppedImage != nil) }
    }

    private var croppedImage: UIImage? {
        // The projective-card images already contain their full visual composition and no printed
        // tarot title band. Preserve the complete image rather than cropping away visual details.
        let url = Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "Resources/card")
            ?? Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "card")
            ?? Bundle.main.url(forResource: imageName, withExtension: "png")
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct ReviewPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.session.stage == .summary {
                Text("这次反思").font(.headline)
                Text(model.session.context.eventDescription ?? "未记录具体事件")
                if !model.session.context.emotions.isEmpty {
                    Label(model.session.context.emotions.joined(separator: "、"), systemImage: "heart")
                }
                if let interpretation = model.session.context.cardInterpretation, !interpretation.isEmpty {
                    Label(interpretation, systemImage: "person.fill")
                }
                if let action = model.session.context.selectedAction, action.acceptedByUser {
                    Divider()
                    Text("你确认的下一步").font(.headline)
                    Text(action.description)
                    if let timing = action.timing, !timing.isEmpty {
                        Text(timing).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
            HStack { Button("保存在本机", action: model.save).buttonStyle(.borderedProminent); Button("删除记录", role: .destructive, action: model.delete).buttonStyle(.bordered) }
            if !model.saveNotice.isEmpty { Text(model.saveNotice).font(.caption).foregroundStyle(.secondary) }
            if model.session.stage == .summary {
                if let exportURL = model.exportURL {
                    ShareLink(item: exportURL) { Label("导出研究 JSON", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                } else {
                    Button("准备去标识化研究导出", action: model.prepareExport).buttonStyle(.bordered)
                }
                Button("完成这次反思", action: model.finishSummary)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("开始新的反思", action: model.restart).frame(maxWidth: .infinity)
            } else if model.session.stage == .completed {
                Button("返回首页") {
                    Task { await model.returnHomeAfterCompletion() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("开始新的反思", action: model.restart).frame(maxWidth: .infinity)
            }
        }.cardStyle()
    }
}

private struct TypingIndicator: View {
    var body: some View { HStack { ProgressView().controlSize(.small); Text("正在组织回应…").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal) }
}

private struct PauseOverlay: View {
    let resume: () -> Void
    var body: some View { ZStack { Color.black.opacity(0.35).ignoresSafeArea(); VStack(spacing: 16) { Image(systemName: "pause.circle.fill").font(.largeTitle); Text("反思已暂停").font(.headline); Button("继续", action: resume).buttonStyle(.borderedProminent) }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)) } }
}

private extension View {
    func cardStyle() -> some View { padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.04), radius: 8, y: 3) }
}
