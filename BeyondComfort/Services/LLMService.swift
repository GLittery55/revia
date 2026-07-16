import Foundation

protocol LLMService: Sendable {
    var providerName: String { get }
    func respond(stage: ReflectionStage, canvas: ContextCanvas, dialogue: [ChatMessage], card: ReflectionCard?, interpretation: String) async throws -> LLMResponse
}

struct MockLLMService: LLMService {
    let providerName = "Mock（未调用 DeepSeek）"
    func respond(stage: ReflectionStage, canvas: ContextCanvas, dialogue: [ChatMessage], card: ReflectionCard?, interpretation: String) async throws -> LLMResponse {
        try await Task.sleep(for: .milliseconds(450))
        switch stage {
        case .tenderGrounding:
            return .init(reflectiveSummary: "先不用急着把一切想明白。可以给这份难受一点空间，同时记得：一次不如意并不能定义你。", uncertaintyStatement: "我们只在你愿意触碰的范围里慢慢来。", question: "此刻，你更需要被安抚、被理解，还是先喘一口气？", hypotheses: [], actionSuggestions: [])
        case .tenderExploration:
            return .init(reflectiveSummary: "可以轻轻地停在这幅画带来的感受旁边，不必马上得到答案。", uncertaintyStatement: "卡片没有固定含义；若它不贴合，也完全可以放下。", question: "从这里看，你内在有什么需要被理解、照顾或保护？", hypotheses: [], actionSuggestions: [])
        case .candidInquiry:
            return .init(reflectiveSummary: "温柔并不要求回避真实；我们可以在不责罚自己的前提下，看看什么值得被保护或改变。", uncertaintyStatement: "下面只是一种可能，你可以保留、修订或放下。", question: "哪一小部分是你此刻有力量诚实面对的？", hypotheses: ["也许这里既需要照顾已经承受的痛，也需要更清楚地保护一个边界，或承担一小部分能够改变的责任。"], actionSuggestions: [])
        case .actionComposer:
            return .init(
                reflectiveSummary: "行动不需要很大，也不必用惩罚来证明认真。可以先选一个最能照顾当下承受力的方向。",
                uncertaintyStatement: "这些只是邀请，不是处方；暂时不决定同样是完整的选择。",
                question: "哪一个建议更接近你此刻愿意迈出的一小步？",
                hypotheses: [],
                actionSuggestions: [
                    .init(type: "care", text: "今天留出十分钟，让身体安静下来，不在这段时间里解决问题。", rationale: "先提供一点恢复空间，减少在疲惫中逼迫自己。"),
                    .init(type: "protection", text: "写下一条目前最需要守住的边界，暂时不必向任何人宣布。", rationale: "先为自己厘清保护范围，再决定是否行动。"),
                    .init(type: "change", text: "选一个完全由自己掌控、十五分钟内能开始的小调整。", rationale: "把改变缩小到可承受、非惩罚的尺度。")
                ]
            )
        default:
            return .init(reflectiveSummary: "不用催促自己，我们可以按你此刻的承受力继续。", uncertaintyStatement: "我的理解可能有偏差，你始终可以停下或改方向。", question: "现在怎样继续会让你更安心一点？", hypotheses: [], actionSuggestions: [])
        }
    }
}

struct DeepSeekLLMService: LLMService {
    let apiKey: String
    let model: String
    var providerName: String { "DeepSeek · \(model)" }

    func respond(stage: ReflectionStage, canvas: ContextCanvas, dialogue: [ChatMessage], card: ReflectionCard?, interpretation: String) async throws -> LLMResponse {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload: [String: Any] = [
            "model": model, "max_tokens": 700, "temperature": 0.2,
            "thinking": ["type": "disabled"],
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": StagePrompts.prompt(for: stage)],
                ["role": "user", "content": input(stage: stage, canvas: canvas, dialogue: dialogue, card: card, interpretation: interpretation)]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw LLMError.requestFailed(statusCode: http.statusCode) }
        let envelope = try JSONDecoder().decode(DeepSeekEnvelope.self, from: data)
        guard let text = envelope.choices.first?.message.content, let json = text.data(using: .utf8) else { throw LLMError.malformedResponse }
        return try JSONDecoder().decode(LLMResponse.self, from: json)
    }

    private func input(stage: ReflectionStage, canvas: ContextCanvas, dialogue: [ChatMessage], card: ReflectionCard?, interpretation: String) -> String {
        let recent = dialogue.suffix(8).map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        let eventDate = ISO8601DateFormatter().string(from: canvas.eventDate)
        var result = "Stage: \(stage.rawValue)\nEvent date: \(eventDate)\nConfirmed context:\n\(canvas.reported)\nContextual factors compared with personal baseline:\n\(canvas.contextualFactors)\nUncertain:\n\(canvas.uncertainty)\nDialogue:\n\(recent)"
        if card != nil { result += "\nA uniformly chance-drawn ambiguous visual card was shown. Do not infer its identity or conventional symbolism.\nUser interpretation: \(interpretation)" }
        return result
    }
}

private struct DeepSeekEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

enum LLMError: LocalizedError {
    case requestFailed(statusCode: Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode): "DeepSeek 请求失败（HTTP \(statusCode)）"
        case .malformedResponse: "DeepSeek 返回了无法解析的内容"
        }
    }
}

enum LLMFactory {
    static func make() -> any LLMService {
        let key = Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_API_KEY") as? String ?? ""
        let model = Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_MODEL") as? String ?? "deepseek-v4-flash"
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = trimmed == "YOUR_DEEPSEEK_API_KEY" || trimmed.contains("xxxxxxxx")
        return trimmed.isEmpty || isPlaceholder ? MockLLMService() : DeepSeekLLMService(apiKey: trimmed, model: model)
    }
}

enum StagePrompts {
    static func prompt(for stage: ReflectionStage) -> String {
        """
        You support a self-compassion reflection within stage \(stage.rawValue). Return JSON only:
        {"reflectiveSummary":"","uncertaintyStatement":"","question":"","hypotheses":[],"actionSuggestions":[]}
        Use a warm, steady, spacious, therapist-informed voice, while never claiming to be a therapist or presenting this as treatment. Ground tender self-compassion in mindful balanced awareness, self-kindness rather than self-judgment, and common humanity rather than isolation. Ground fierce self-compassion in protecting boundaries, providing for needs, honest responsibility, and motivating non-punitive change. Tender presence must come before fierce inquiry.
        The Swift state machine alone controls transitions. Do not quote, restate, summarize, or paraphrase the user's latest response back to them; acknowledge briefly and add only genuinely new reflective value or the next question. Analyze available sleep, resting-heart-rate, HRV, and calendar-load observations as contextual clues. You may cautiously suggest a possible state such as reduced recovery, strain, activation, or overload, but must use uncertainty language ("may", "might", "one clue") and mention plausible alternatives or missing personal baseline. Never diagnose, adjudicate responsibility, claim tracking data caused the event, instruct confrontation, or assign canonical card meaning. Data frames questions; it is not evidence of blame. The user interprets the card first. Mark hypotheses uncertain; hypotheses are allowed only in candidInquiry. Ask one gentle question. Avoid generic praise and premature reframing.
        \(stageGuidance(for: stage))
        actionSuggestions are allowed only in actionComposer. In that stage provide 2–4 distinct, small, feasible, non-punitive suggestions selected from care, repair, protection, or change. Each item is {"type":"care|repair|protection|change","text":"a concrete step","rationale":"a brief compassionate reason"}. Ground every option only in user-confirmed material. Offer options; do not prescribe or predict. In all other stages return an empty actionSuggestions array.
        """
    }

    private static func stageGuidance(for stage: ReflectionStage) -> String {
        switch stage {
        case .tenderGrounding:
            return "TENDER GOAL: acknowledge pain without echoing wording; separate the bounded event from global self-judgment; support balanced awareness, kindness, and non-isolation. Do not introduce responsibility or positive reframing yet."
        case .tenderExploration:
            return "PROJECTIVE TENDER GOAL: explore only around the user's own visual interpretation—what may need understanding, care, or protection. Never add conventional tarot symbolism or a model-authored card meaning."
        case .candidInquiry:
            return "FIERCE GOAL: ask-confirm-deepen around exactly one of responsibility, boundary, or change. Weigh constraints, uncertainty, and agency before any attribution. Any hypothesis begins as one possibility and cannot exceed the disclosed evidence."
        case .actionComposer:
            return "INTEGRATION GOAL: offer at least one tender option (care/provision) and one fierce option (repair/protection/change), each small, feasible, and non-punitive. Never tell the user to confront someone."
        default:
            return "Stay within the current stage and do not advance the flow."
        }
    }
}
