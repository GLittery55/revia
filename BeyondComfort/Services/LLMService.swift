import Foundation
import os

struct LLMPrompt: Equatable {
    let system: String
    let user: String
}

enum DialogueNarrativeMode: String, Codable, Sendable {
    case standard
    /// Generate only what the card phase added after the disclosure/tracking synthesis was locked.
    case cardDerivedDelta
}

/// Typed workflow evidence for dialogue generation. Keeping this separate from
/// `nextQuestionGoal` makes the baseline/delta boundary machine-readable instead of relying on a
/// long natural-language instruction embedded in a fallback goal.
struct DialoguePromptEvidence: Codable, Equatable, Sendable {
    var narrativeMode: DialogueNarrativeMode = .standard
    /// Locally validated semantic plan for this one visible turn. The Writer may phrase it
    /// naturally but may not change its function, evidence, or permissions.
    var responsePlan: ResponsePlan?
    var lockedBaselineNarrative: String?
    var cardDerivedDeltaNarrative: String?
    var matchedImageRelation: String?
    var matchedRealityRelation: String?
    var confirmedCardMapping: String?
    var tenderResponse: String?
    var meaningShiftResponse: String?
    var fierceResponse: String?
    var pendingAction: String?
    var cardPhaseStartedAt: Date?
    /// A measurement-free, non-diagnostic hypothesis produced locally from several tracking
    /// domains. Specific measurements and emotion labels never cross this interface.
    var contextualLoadCue: DialogueContextCue?

    static let standard = DialoguePromptEvidence()
}

protocol ReflectionPromptBuilding: Sendable {
    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) -> LLMPrompt

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt

    func questionRewritePrompt(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt
}

extension ReflectionPromptBuilding {
    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage]
    ) -> LLMPrompt {
        analyzerPrompt(
            context: context,
            messages: messages,
            planningContext: nil
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: recentMessages
        )
    }
}

struct ReflectionPromptFactory: ReflectionPromptBuilding {
    /// A prompt-only projection. Raw tracking values, provenance, record identifiers, rejected
    /// interpretations, and unconfirmed observations never cross the LLM boundary.
    private struct PromptReflectionContext: Encodable {
        let eventDescription: String?
        let emotions: [String]
        let bodilyResponses: [String]
        let selfJudgment: String?
        let personalMeaning: String?
        let contextualConstraints: [String]
        let personalContributions: [String]
        let uncertainties: [String]
        let pastControllability: ControllabilityLevel
        let presentAgency: AgencyLevel
        let possibleImpactOnOthers: [String]
        let possibleBoundaryConcerns: [String]
        let unmetNeeds: [String]
        let repeatingPatterns: [String]
        let cardInterpretation: String?
        let selectedAction: CompassionateAction?

        init(
            _ context: ReflectionContext,
            promptEvidence: DialoguePromptEvidence = .standard
        ) {
            let deltaOnly = promptEvidence.narrativeMode == .cardDerivedDelta
            eventDescription = deltaOnly ? nil : context.eventDescription
            let judgment = Self.comparable(context.selfJudgment ?? "")
            emotions = deltaOnly ? [] : context.emotions.filter { value in
                let clean = Self.comparable(value)
                return !clean.isEmpty && clean.count <= 24 &&
                    (judgment.isEmpty || (!judgment.contains(clean) && !clean.contains(judgment)))
            }
            let emotionValues = emotions.map(Self.comparable)
            bodilyResponses = deltaOnly ? [] : context.bodilyResponses.filter { value in
                let clean = Self.comparable(value)
                guard !clean.isEmpty, clean.count <= 40 else { return false }
                return !emotionValues.contains {
                    $0.contains(clean) || clean.contains($0)
                }
            }
            selfJudgment = deltaOnly ? nil : context.selfJudgment
            personalMeaning = deltaOnly ? nil : context.personalMeaning
            contextualConstraints = deltaOnly ? [] : context.contextualConstraints
            personalContributions = deltaOnly ? [] : context.personalContributions
            uncertainties = deltaOnly ? [] : context.uncertainties
            pastControllability = deltaOnly ? .unknown : context.pastControllability
            presentAgency = deltaOnly ? .unknown : context.presentAgency
            possibleImpactOnOthers = deltaOnly ? [] : context.possibleImpactOnOthers
            possibleBoundaryConcerns = deltaOnly ? [] : context.possibleBoundaryConcerns
            unmetNeeds = deltaOnly ? [] : context.unmetNeeds
            repeatingPatterns = deltaOnly ? [] : context.repeatingPatterns
            cardInterpretation = deltaOnly ? nil : context.cardInterpretation
            selectedAction = context.selectedAction
        }

        private static func comparable(_ value: String) -> String {
            value.filter { $0.isLetter || $0.isNumber }
        }
    }

    private let dialogueInstruction = """
    You are a Chinese self-compassion reflection facilitator. Swift exclusively owns workflow
    state, card selection, local actions, persistence, and completion. Follow the supplied typed
    response purpose without advancing or redesigning the protocol.

    Build every sentence from user-supported evidence. Keep reported facts, self-evaluation,
    possible contributors, contextual constraints, controllable parts, impacts, and uncertainty
    distinct. Do not infer a cause, motive, emotion, trait, capacity, responsibility, need, or
    readiness. Tender acknowledges difficulty and limits while preserving supported conduct or
    impact; it limits whole-person judgment without denying what happened. Candid reflection is
    optional and requires concrete evidence.

    Contextual data is only a tentative background cue. Preserve its exact scope and use it only
    after the person confirms how it relates to the episode. Never expose measurements or make the
    cue causal, diagnostic, moral, or exculpatory. A card is a projective object: the person develops
    the image relation before any life relation, and only their accepted or revised mapping may
    enter later synthesis. An image cannot prove anything about the person.

    Write concise, natural spoken Chinese addressed as “你”. Respond to the latest meaning before
    asking at most one open question. Do not repeat an answered function, stitch fields, use
    internal terminology, give premature advice, force insight, or require agreement. Respect
    correction, refusal, no change, and uncertainty.

    Return exactly one JSON object:
    {"reflection":"","question":"","actionOptions":[]}
    Across reflection and question use at most one question. actionOptions is empty unless Swift
    explicitly authorizes action selection; then return at most two evidence-grounded, optional
    objects with category, description, timing, and rationale.
    """

    private let analyzerInstruction = """
    You are the private ContextAnalyzer. Extract a domain-neutral semantic structure from the
    person's words; do not write dialogue or control workflow. Missing evidence remains null,
    empty, unknown, or tentative. Never diagnose, infer hidden causes or motives, assign
    responsibility, or turn contextual data or an image into psychological evidence.

    Separate observable episode facts, experience, self-evaluation, constraints, user-acknowledged
    conduct, possible impact, boundary or need, controllable parts, and uncertainty. Evidence arrays
    contain only short literal fragments from user messages. A relation is grounded only when its
    source, relation, and target are all supported. The supplied planning boundary limits the
    responsePlan; it does not determine what the person means.

    Return exactly one JSON object with this shape:
    {"safetyOverride":false,"distressLevel":0,"selfAttackLevel":0,
    "reflectiveCapacity":1,"behaviorIdentitySeparation":0,
    "multipleExplanationsCapacity":0,"consentToCandor":"unknown",
    "eventType":"unclear","taskProgressStatus":"notApplicable",
    "userAdmittedBehavior":false,"confirmedBehavior":null,"behaviorEvidence":[],
    "eventDescription":null,"emotions":[],"bodilyResponses":[],"selfJudgment":null,
    "contextualConstraints":[],"personalContributions":[],"possibleImpactOnOthers":[],
    "possibleBoundaryConcerns":[],"possibleUnmetNeeds":[],"possibleRepeatingPatterns":[],
    "uncertainties":[],"pastControllability":"unknown","presentAgency":"unknown",
    "recommendedRoute":"explore","secondaryRoutes":[],"reasonCodes":[],
    "missingInformation":[],"nextQuestionGoal":"",
    "semanticRelations":[{"kind":"uncertainty","source":"","relation":"","target":"",
    "concepts":[],"evidence":[],"status":"tentative","confidence":0.0}],
    "responsePlan":{"function":"exploreLivedExperience","focus":"","evidence":[],
    "relationKinds":[],"questionIntent":"","shouldAskQuestion":true,"confidence":0.0},
    "confidence":0.0}

    Keep legacy classification fields at the fixed neutral values shown above. semanticRelations
    may use only the typed relation kinds supported by the supplied schema. responsePlan must use
    one allowed function from the planning boundary and at least one latest-message evidence
    fragment; otherwise return it as null. Numeric levels use 0...3 and confidence uses 0...1.
    """

    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext? = nil
    ) -> LLMPrompt {
        LLMPrompt(
            system: analyzerInstruction,
            user: """
            Swift planning boundary:
            \(encoded(planningContext?.validated))

            Confirmed reflection context:
            \(encoded(PromptReflectionContext(context)))

            Recent conversation:
            \(transcript(messages))
            """
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: .standard,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: recentMessages
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues _: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        var safeEvidence = promptEvidence
        if state == .cardInterpretation {
            safeEvidence.contextualLoadCue = nil
        }
        let deltaOnly = safeEvidence.narrativeMode == .cardDerivedDelta
        let boundedMessages: [ChatMessage]
        if deltaOnly, let startedAt = safeEvidence.cardPhaseStartedAt {
            boundedMessages = recentMessages.filter { $0.createdAt >= startedAt }
        } else {
            boundedMessages = recentMessages
        }
        let cardBoundary: String
        if card == nil {
            cardBoundary = "No card is available in this turn."
        } else if context.cardInterpretation?.isEmpty == false {
            cardBoundary = "A card is visible and the person's image account is available."
        } else {
            cardBoundary = "A card is visible but has not yet been interpreted by the person."
        }

        return LLMPrompt(
            system: dialogueInstruction,
            user: """
            Application-owned state: \(state.rawValue)
            Internal route: \(route.rawValue)
            Required one-turn purpose: \(nextQuestionGoal)

            Confirmed context:
            \(encoded(PromptReflectionContext(context, promptEvidence: safeEvidence)))

            Typed evidence and narrative boundary:
            \(encoded(safeEvidence))

            Analyzer evidence:
            \(encoded(analysis))

            Card boundary:
            \(cardBoundary)

            Recent conversation:
            \(transcript(boundedMessages))
            """
        )
    }

    func questionRewritePrompt(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        LLMPrompt(
            system: """
            Edit only the dialogue question. Return exactly one JSON object:
            {"reflection":"","question":"","actionOptions":[]}
            Write one concise, natural Chinese question that follows the supplied purpose and latest
            user meaning. Reuse only supported details. Add no interpretation, advice, menu, second
            question, or workflow language.
            """,
            user: """
            Application-owned state: \(state.rawValue)
            Required purpose: \(nextQuestionGoal)
            Draft: \(encoded(draft))
            Recent conversation:
            \(transcript(Array(recentMessages.suffix(4))))
            """
        )
    }

    private func transcript(_ messages: [ChatMessage]) -> String {
        messages.suffix(12).map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }

    private func encoded<T: Encodable>(_ value: T?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

struct SimpleGentleReflectionReply: Codable, Equatable, Sendable {
    let reply: String
    let generationAttempts: Int

    init(reply: String, generationAttempts: Int = 1) {
        self.reply = reply
        self.generationAttempts = max(1, generationAttempts)
    }

    private enum CodingKeys: String, CodingKey {
        case reply
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        generationAttempts = 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
    }
}

enum SimpleGentleReflectionViolation: String, Error, Equatable, Sendable {
    case invalidJSON = "invalid_json"
    case emptyReply = "empty_reply"
    case replyTooLong = "reply_too_long"
    case multipleQuestions = "multiple_questions"
}

struct SimpleGentleReflectionReplyValidator: Sendable {
    func validate(_ reply: String) throws -> String {
        let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw SimpleGentleReflectionViolation.emptyReply
        }
        guard clean.count <= 600 else {
            throw SimpleGentleReflectionViolation.replyTooLong
        }

        let questionCount = clean.filter { $0 == "？" || $0 == "?" }.count
        if questionCount > 1 {
            throw SimpleGentleReflectionViolation.multipleQuestions
        }
        return clean
    }
}

protocol SimpleGentleReflectionPromptBuilding: Sendable {
    func simpleGentleReflectionPrompt(
        recentMessages: [ChatMessage],
        correction: SimpleGentleReflectionViolation?
    ) -> LLMPrompt
}

protocol SimpleGentleReflectionGenerating: Sendable {
    func generate(recentMessages: [ChatMessage]) async throws -> SimpleGentleReflectionReply
}

enum SimpleGentleReflectionError: Error {
    case invalidReply(SimpleGentleReflectionViolation)
}

extension ReflectionPromptFactory: SimpleGentleReflectionPromptBuilding {
    /// Active-control prompt: deliberately short and independent from the card protocol,
    /// contextual analysis, tracking cues, Tender/Fierce routing, and staged interventions.
    func simpleGentleReflectionPrompt(
        recentMessages: [ChatMessage],
        correction: SimpleGentleReflectionViolation?
    ) -> LLMPrompt {
        let correctionInstruction = correction.map {
            """
            The previous candidate was rejected by a local rule: \($0.rawValue).
            Produce a fresh response that corrects that issue. Do not mention the rejection.
            """
        } ?? ""
        return LLMPrompt(
            system: """
            You are a gentle Chinese reflection chatbot. Respond warmly and without judgment.
            First respond naturally to what the user just said; do not mechanically paraphrase it.
            Keep the response concise, normally two to four sentences. You may ask at most one
            open-ended question that follows the user's lead.
            Do not ask the user to rate, approve, verify, or edit your understanding, summary, or
            wording. If you offer a tentative understanding, continue with one meaningful question
            about the user's experience; they may correct it naturally in their answer.
            Do not use cards, tracking or personal-data observations, diagnosis, causal claims,
            hidden-motive claims, responsibility verdicts, named reflection frameworks, staged
            exercises, or unsolicited advice. Respect uncertainty and a wish not to continue.
            \(correctionInstruction)

            Return strict JSON only: {"reply":"one natural conversational response"}
            """,
            user: """
            Recent conversation:
            \(transcript(recentMessages))
            """
        )
    }
}

struct RemoteSimpleGentleReflectionGenerator: SimpleGentleReflectionGenerating {
    private let prompts: any SimpleGentleReflectionPromptBuilding
    private let validator = SimpleGentleReflectionReplyValidator()

    init(
        prompts: any SimpleGentleReflectionPromptBuilding = ReflectionPromptFactory()
    ) {
        self.prompts = prompts
    }

    func generate(
        recentMessages: [ChatMessage]
    ) async throws -> SimpleGentleReflectionReply {
        var correction: SimpleGentleReflectionViolation?
        for attempt in 1...2 {
            let prompt = prompts.simpleGentleReflectionPrompt(
                recentMessages: Array(recentMessages.suffix(12)),
                correction: correction
            )
            let text = try await RemoteAPIService.shared.completeJSON(
                system: prompt.system,
                user: prompt.user,
                maxTokens: 420,
                temperature: 0.45,
                agentMode: "fast"
            )
            do {
                let decoded = try JSONDecoder().decode(
                    SimpleGentleReflectionReply.self,
                    from: Data(text.utf8)
                )
                let clean = try validator.validate(decoded.reply)
                return SimpleGentleReflectionReply(
                    reply: clean,
                    generationAttempts: attempt
                )
            } catch let violation as SimpleGentleReflectionViolation {
                correction = violation
            } catch {
                correction = .invalidJSON
            }
        }
        throw SimpleGentleReflectionError.invalidReply(correction ?? .invalidJSON)
    }
}

protocol ContextAnalyzing: Sendable {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis
}

extension ContextAnalyzing {
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis {
        await analyze(context: context, messages: messages)
    }
}

protocol DialogueGenerating: Sendable {
    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn

    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn
}

extension DialogueGenerating {
    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        try await generate(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            nextQuestionGoal: nextQuestionGoal,
            messages: messages
        )
    }
}

protocol DialogueQuestionRewriting: Sendable {
    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn
}

struct RemoteDialogueQuestionRewriter: DialogueQuestionRewriting {
    private let prompts: any ReflectionPromptBuilding

    init(prompts: any ReflectionPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        let prompt = prompts.questionRewritePrompt(
            state: state,
            nextQuestionGoal: nextQuestionGoal,
            draft: draft,
            recentMessages: messages
        )
        let text = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 180,
            temperature: 0.1,
            agentMode: "fast"
        )
        return try DialogueTurnParser.parse(text)
    }
}

struct RemoteContextAnalyzer: ContextAnalyzing {
    private let prompts: any ReflectionPromptBuilding
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "ContextAnalyzer")

    init(prompts: any ReflectionPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        await analyze(
            context: context,
            messages: messages,
            planningContext: nil
        )
    }

    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis {
        let prompt = prompts.analyzerPrompt(
            context: context,
            messages: messages,
            planningContext: planningContext
        )
        do {
            let text = try await RemoteAPIService.shared.completeJSON(
                system: prompt.system,
                user: prompt.user,
                maxTokens: 1_200,
                temperature: 0.05,
                agentMode: "fast"
            )
            return try ContextAnalysisParser.parse(text)
        } catch {
            logger.error("Analyzer unavailable or invalid; preserving uncertainty. Error type: \(String(describing: type(of: error)), privacy: .public)")
            return .fallback()
        }
    }
}

struct RemoteDialogueGenerator: DialogueGenerating {
    private let prompts: any ReflectionPromptBuilding
    private let questionRewriter: any DialogueQuestionRewriting
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "DialogueGenerator")

    init(
        prompts: any ReflectionPromptBuilding = ReflectionPromptFactory(),
        questionRewriter: (any DialogueQuestionRewriting)? = nil
    ) {
        self.prompts = prompts
        self.questionRewriter = questionRewriter ?? RemoteDialogueQuestionRewriter(prompts: prompts)
    }

    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        try await generate(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: .standard,
            nextQuestionGoal: nextQuestionGoal,
            messages: messages
        )
    }

    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        let prompt = prompts.dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: promptEvidence,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: messages
        )
        let text = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 1_000,
            temperature: 0.32,
            // The retired server-side generic Planner/Critic wrappers no longer exist. Historical
            // dialogue requests keep their caller-owned contract and use one direct completion.
            agentMode: "fast"
        )
        do {
            var turn = try DialogueTurnParser.parse(text)
            turn.actionOptions = Array(turn.actionOptions.prefix(2))
            if let boundaryTurn = cardBoundaryTurn(
                for: state,
                nextQuestionGoal: nextQuestionGoal,
                messages: messages,
                cardInterpretation: context.cardInterpretation
            ) {
                return boundaryTurn
            }
            turn = await normalizedQuestionTurn(
                in: turn,
                state: state,
                nextQuestionGoal: nextQuestionGoal,
                context: context,
                messages: messages,
                responsePlan: promptEvidence.responsePlan
            )
            guard !turn.visibleText.isEmpty || (state == .actionSelection && !turn.actionOptions.isEmpty) else {
                throw LLMError.malformedResponse
            }
            if route == .repair {
                turn.question = concreteRepairQuestion(rewriting: turn.question, context: context)
            }
            return turn
        } catch {
            logger.error("Dialogue JSON invalid. Error type: \(String(describing: type(of: error)), privacy: .public)")
            throw LLMError.malformedResponse
        }
    }

    func emergencyFallbackQuestion(
        for state: ReflectionState,
        nextQuestionGoal: String = "",
        context: ReflectionContext = .init(),
        messages: [ChatMessage] = [],
        responsePlan: ResponsePlan? = nil
    ) -> String {
        if let responsePlan, responsePlan.shouldAskQuestion {
            switch responsePlan.function {
            case .exploreLivedExperience:
                return "顺着你刚才说的这段经历，现在最难受的部分是什么？"
            case .clarifyPersonalMeaning:
                return "你开始这样看自己时，最担心接下来会发生什么？"
            case .clarifyCircumstances:
                return "除了眼前的结果，当时还有什么现实情况也让这件事更难处理？"
            default:
                break
            }
        }
        switch state {
        case .eventDisclosure:
            return "你愿意从最近一次发生的情况说起吗？"
        case .emotionDisclosure:
            if context.selfJudgment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return "那件事让你开始这样看自己。那时你最担心它说明什么？"
            }
            return "这件事发生时，你当时最明显的感受是什么？"
        case .bodilyResponse:
            return "想到这件事时，你现在有什么感受？没有特别明显的感觉也可以。"
        case .selfJudgment:
            return "这件事让你开始怎样看自己，或者最担心它说明什么？"
        case .contextDisclosure:
            return "那段时间，除了这件事，还有什么现实情况也在同时发生？"
        case .trackingReview:
            return "这些变化在刚才那件事里实际参与了哪一部分？如果没有也可以说。"
        case .cardInterpretation:
            return "沿着你刚才的说法，画面接下来可能会发生什么？"
        case .attributionReflection:
            let goal = nextQuestionGoal
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            if goal.contains("cardconnection") {
                return "按你刚才对画面的描述，它和这件事里的哪一部分有一点像吗？没有也可以。"
            }
            if goal.contains("cardmeaningshift") || goal.contains("perspective") {
                return "把这个画面和刚才的事放在一起后，你现在会怎样理解那件事？没有变化也可以。"
            }
            if goal.contains("candidcircumstances") || goal.contains("circumstance") {
                return "这件事里，有哪些现实困难也需要一起看见？"
            }
            if goal.contains("candidagency") || goal.contains("agency") {
                return "只看你能够决定的部分，你觉得哪一步最值得调整？暂时没有也可以。"
            }
            return "顺着刚才的整理，哪一部分最值得继续说？也可以直接换个方向。"
        case .readinessCheck:
            return "把这段整理放回当时，哪一部分最需要继续说？"
        case .tenderGrounding:
            return "沿着刚才的理解，你现在最想补充的是哪一部分？"
        case .tenderExploration:
            return "这个问题先放下，不用勉强找答案。你还有哪部分想接着说？"
        case .welcome, .trackingPermission, .cardIntroduction, .actionSelection,
             .summary, .completed, .safetySupport:
            return ""
        }
    }

    func stateRequiresQuestion(_ state: ReflectionState) -> Bool {
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure, .trackingReview, .tenderGrounding, .readinessCheck,
             .tenderExploration, .cardInterpretation, .attributionReflection:
            return true
        case .welcome, .trackingPermission, .cardIntroduction, .actionSelection,
             .summary, .completed, .safetySupport:
            return false
        }
    }

    func bestQuestion(
        in turn: DialogueTurn,
        state: ReflectionState,
        nextQuestionGoal: String
    ) -> String? {
        let candidates =
            questionClauses(in: turn.question).map { ($0, true) }
            + questionClauses(in: turn.reflection).map { ($0, false) }
        let ranked = candidates.compactMap { candidate, fromQuestionField -> (String, Int, Bool)? in
            guard isUsableQuestion(candidate) else { return nil }
            let score = questionRelevanceScore(
                candidate,
                state: state,
                nextQuestionGoal: nextQuestionGoal
            )
            guard score > 0 else { return nil }
            return (candidate, score, fromQuestionField)
        }
        return ranked.max {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.2 != $1.2 { return !$0.2 && $1.2 }
            return $0.0.count > $1.0.count
        }?.0
    }

    func normalizedQuestionTurn(
        in original: DialogueTurn,
        state: ReflectionState,
        nextQuestionGoal: String,
        context: ReflectionContext,
        messages: [ChatMessage],
        responsePlan: ResponsePlan? = nil
    ) async -> DialogueTurn {
        var turn = original
        guard stateRequiresQuestion(state) else {
            turn.reflection = [
                removingQuestionClauses(from: turn.reflection),
                removingQuestionClauses(from: turn.question),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            turn.question = ""
            return turn
        }

        turn.reflection = removingQuestionClauses(from: turn.reflection)
        if let selected = bestQuestion(
            in: original,
            state: state,
            nextQuestionGoal: nextQuestionGoal
        ) {
            turn.question = selected
            return turn
        }

        do {
            let rewritten = try await questionRewriter.rewriteQuestion(
                state: state,
                nextQuestionGoal: nextQuestionGoal,
                draft: original,
                messages: messages
            )
            let rewrittenCandidates =
                questionClauses(in: rewritten.question)
                + questionClauses(in: rewritten.reflection)
            if rewrittenCandidates.count == 1,
               let question = rewrittenCandidates.first,
               isUsableQuestion(question) {
                turn.question = question
                return turn
            }
            logger.error("Question rewrite returned no single usable question; using emergency fallback.")
        } catch {
            logger.error("Question rewrite unavailable; using emergency fallback. Error type: \(String(describing: type(of: error)), privacy: .public)")
        }

        turn.question = emergencyFallbackQuestion(
            for: state,
            nextQuestionGoal: nextQuestionGoal,
            context: context,
            messages: messages,
            responsePlan: responsePlan
        )
        return turn
    }

    private func latestUserText(from messages: [ChatMessage]) -> String {
        messages.last(where: { $0.role == .user })?.content ?? ""
    }

    private func questionClauses(in text: String) -> [String] {
        var questions: [String] = []
        var clause = ""
        for character in text {
            clause.append(character)
            if "。！？?!\n".contains(character) {
                let value = clause.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.contains("？") || value.contains("?") {
                    questions.append(value)
                }
                clause = ""
            }
        }
        let tail = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.contains("？") || tail.contains("?") {
            questions.append(tail)
        }
        return questions
    }

    private func isUsableQuestion(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.count <= 140,
              clean.filter({ $0 == "？" || $0 == "?" }).count == 1 else {
            return false
        }
        let prohibited = [
            "workflow", "阶段", "规则", "不重复追问", "nextquestiongoal",
            "作为模型", "作为助手", "内部",
        ]
        return !prohibited.contains {
            clean.localizedCaseInsensitiveContains($0)
        }
    }

    private func questionRelevanceScore(
        _ question: String,
        state: ReflectionState,
        nextQuestionGoal: String
    ) -> Int {
        let normalizedQuestion = question.lowercased()
        let normalizedGoal = nextQuestionGoal.lowercased()
        let stateMarkers: [String]
        switch state {
        case .eventDisclosure:
            stateMarkers = ["发生", "情况", "那件事", "什么时候", "最近一次"]
        case .emotionDisclosure:
            stateMarkers = ["感受", "感觉", "难受", "担心", "害怕", "在意"]
        case .bodilyResponse:
            if ["身体哪里", "身体哪个", "哪个部位", "哪里最明显"].contains(where: {
                normalizedQuestion.contains($0)
            }) {
                return 0
            }
            stateMarkers = ["感受", "感觉", "想到", "现在"]
        case .selfJudgment:
            stateMarkers = ["自己", "担心", "说明", "意味着", "评价", "结论"]
        case .contextDisclosure:
            stateMarkers = ["同时", "当时", "现实", "情况", "难处", "限制", "精力"]
        case .trackingReview:
            stateMarkers = ["最近", "变化", "对得上", "贴近", "感受", "状态"]
        case .tenderGrounding, .readinessCheck:
            stateMarkers = ["贴近", "符合", "准确", "哪里不对", "需要改", "理解"]
        case .tenderExploration:
            stateMarkers = ["感受", "想说", "接着", "在意", "需要"]
        case .cardInterpretation:
            stateMarkers = ["画面", "接下来", "发生", "这个人", "这个"]
        case .attributionReflection:
            stateMarkers = ["这件事", "画面", "想到", "理解", "变化", "困难", "限制", "具体", "改变"]
        default:
            stateMarkers = []
        }

        var score = stateMarkers.reduce(into: 0) { value, marker in
            if normalizedQuestion.contains(marker) { value += 2 }
        }
        let goalMarkerGroups: [([String], [String])] = [
            (["felt", "emotion"], ["感受", "感觉", "难受", "担心", "在意"]),
            (["task-progress", "stalled"], ["开始", "推进", "卡住", "进展"]),
            (["accuracy", "correct", "summary"], ["贴近", "准确", "符合", "哪里不对", "需要改"]),
            (["cardconnection", "card connection"], ["画面", "想到", "像", "联系"]),
            (["perspective", "meaning shift"], ["理解", "看见", "变化", "现在"]),
            (["circumstance", "constraint"], ["情况", "困难", "限制", "影响"]),
            (["agency", "change"], ["具体", "改变", "调整", "下一步", "能做"]),
            (["action"], ["下一步", "愿意", "试试", "做"]),
        ]
        for (goalMarkers, questionMarkers) in goalMarkerGroups
        where goalMarkers.contains(where: { normalizedGoal.contains($0) }) {
            score += questionMarkers.reduce(into: 0) { value, marker in
                if normalizedQuestion.contains(marker) { value += 3 }
            }
        }
        return score
    }

    private func removingQuestionClauses(from text: String) -> String {
        var kept: [String] = []
        var clause = ""
        for character in text {
            clause.append(character)
            if "。！？?!".contains(character) {
                if !clause.contains("？") && !clause.contains("?") {
                    kept.append(clause)
                }
                clause = ""
            }
        }
        if !clause.contains("？") && !clause.contains("?") {
            kept.append(clause)
        }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func concreteRepairQuestion(rewriting question: String, context: ReflectionContext) -> String {
        let abstractPhrases = [
            "有什么需要修复", "需要修复", "哪段关系", "关系需要重新说清楚", "重新说清楚",
            "该承担什么", "承担什么", "承担哪", "责任是什么", "该负什么责任", "怎么负责", "如何负责",
            "怎么修复", "如何修复", "做什么弥补", "怎么弥补",
        ]
        guard abstractPhrases.contains(where: { question.contains($0) }) else { return question }

        if let contribution = context.personalContributions.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contribution.isEmpty {
            let concrete = String(contribution.prefix(28))
            return "关于“\(concrete)”这件事，你觉得对方当时最需要先知道什么？"
        }
        return "这件事里，你确认是自己做过或没做到的是哪一步？"
    }

    func cardBoundaryTurn(
        for state: ReflectionState,
        nextQuestionGoal: String = "",
        messages: [ChatMessage],
        cardInterpretation: String? = nil
    ) -> DialogueTurn? {
        guard state == .cardInterpretation || state == .attributionReflection,
              let latestMessage = messages.last(where: { $0.role == .user }) else { return nil }
        // `attributionReflection` is a legacy broad state reused by the finer Swift-owned
        // connection, candid, action, and narrative phases. A short answer such as “没有” is a
        // card boundary only while Swift explicitly says it is asking for card connection. In a
        // candid or action phase the same word is a substantive answer and must not be swallowed.
        if state == .attributionReflection {
            let normalizedGoal = nextQuestionGoal
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard normalizedGoal.contains("workflowphase:cardconnection") else { return nil }
            // Swift permits one final, explicitly optional scaffold after the first soft
            // “想不到”. Make that invitation deterministic so a writer cannot accidentally
            // return a terminal sentence while the state machine is still awaiting the bounded
            // second answer.
            if normalizedGoal.contains("onefinal") || normalizedGoal.contains("最后一次") {
                let anchor = cardInterpretation?
                    .split(separator: "；", omittingEmptySubsequences: true)
                    .last
                    .map { String($0.prefix(26)) }
                let question = anchor.map {
                    "只看你刚才说的“\($0)”，它和刚才那件事里的哪一部分有一点像吗？如果没有，直接说没有就可以。"
                } ?? "只看你刚才描述的那个动作或关系，它和刚才那件事里的哪一部分有一点像吗？如果没有，直接说没有就可以。"
                return DialogueTurn(
                    reflection: "先不用找一个完整的解释。",
                    question: question,
                    actionOptions: []
                )
            }
        }
        // A “没有了” submitted while describing the picture may legitimately move the app into
        // attribution and receive one optional reality invitation. Only treat it as a connection
        // boundary when it was answered inside the current card phase (legacy nil states remain safe).
        if state == .attributionReflection,
           let messageState = latestMessage.state,
           messageState != .attributionReflection {
            return nil
        }
        let latest = latestMessage.content
        let clean = latest
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "")
        let exactBoundaries = ["没有", "没有了", "没了", "想不到", "没想到什么"]
        let phraseBoundaries = ["有点难想到", "不太想得到", "好像没有了", "没什么能联系的"]
        guard exactBoundaries.contains(clean) || phraseBoundaries.contains(where: { clean.contains($0) }) else {
            return nil
        }
        return DialogueTurn(
            reflection: "好，不用勉强把画面和现实连起来。就先停在这里。",
            question: "",
            actionOptions: []
        )
    }
}

enum ContextAnalysisParser {
    static func parse(_ text: String) throws -> ContextAnalysis {
        try JSONDecoder()
            .decode(PartialContextAnalysis.self, from: Data(text.utf8))
            .materialized
            .validated
    }
}

enum DialogueTurnParser {
    static func parse(_ text: String) throws -> DialogueTurn {
        try JSONDecoder()
            .decode(PartialDialogueTurn.self, from: Data(text.utf8))
            .materialized
    }
}

private struct PartialDialogueTurn: Decodable {
    var reflection: String
    var question: String
    var actionOptions: [DialogueActionOption]

    private enum CodingKeys: String, CodingKey {
        case reflection, question, actionOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reflection = (try? container.decode(String.self, forKey: .reflection)) ?? ""
        question = (try? container.decode(String.self, forKey: .question)) ?? ""
        actionOptions = (try? container.decode([DialogueActionOption].self, forKey: .actionOptions)) ?? []
    }

    var materialized: DialogueTurn {
        DialogueTurn(reflection: reflection, question: question, actionOptions: actionOptions)
    }
}

struct PartialContextAnalysis: Decodable {
    var safetyOverride: Bool?
    var distressLevel: Int?
    var selfAttackLevel: Int?
    var reflectiveCapacity: Int?
    var behaviorIdentitySeparation: Int?
    var multipleExplanationsCapacity: Int?
    var consentToCandor: ConsentState?
    var eventType: ReflectionEventType?
    var taskProgressStatus: TaskProgressStatus?
    var userAdmittedBehavior: Bool?
    var confirmedBehavior: String?
    var behaviorEvidence: [String]?
    var eventDescription: String?
    var emotions: [String]?
    var bodilyResponses: [String]?
    var selfJudgment: String?
    var contextualConstraints: [String]?
    var personalContributions: [String]?
    var possibleImpactOnOthers: [String]?
    var possibleBoundaryConcerns: [String]?
    var possibleUnmetNeeds: [String]?
    var possibleRepeatingPatterns: [String]?
    var uncertainties: [String]?
    var pastControllability: ControllabilityLevel?
    var presentAgency: AgencyLevel?
    var recommendedRoute: CompassionRoute?
    var secondaryRoutes: [CompassionRoute]?
    var reasonCodes: [String]?
    var missingInformation: [String]?
    var nextQuestionGoal: String?
    var semanticRelations: [SemanticRelation]?
    var responsePlan: ResponsePlan?
    var confidence: Double?

    var materialized: ContextAnalysis {
        ContextAnalysis(
            safetyOverride: safetyOverride ?? false,
            distressLevel: distressLevel ?? 0,
            selfAttackLevel: selfAttackLevel ?? 0,
            reflectiveCapacity: reflectiveCapacity ?? 1,
            behaviorIdentitySeparation: behaviorIdentitySeparation ?? 0,
            multipleExplanationsCapacity: multipleExplanationsCapacity ?? 0,
            consentToCandor: consentToCandor ?? .unknown,
            eventType: eventType ?? .unclear,
            taskProgressStatus: taskProgressStatus ?? .notApplicable,
            userAdmittedBehavior: userAdmittedBehavior ?? false,
            confirmedBehavior: confirmedBehavior,
            behaviorEvidence: behaviorEvidence ?? [],
            eventDescription: eventDescription,
            emotions: emotions ?? [],
            bodilyResponses: bodilyResponses ?? [],
            selfJudgment: selfJudgment,
            contextualConstraints: contextualConstraints ?? [],
            personalContributions: personalContributions ?? [],
            possibleImpactOnOthers: possibleImpactOnOthers ?? [],
            possibleBoundaryConcerns: possibleBoundaryConcerns ?? [],
            possibleUnmetNeeds: possibleUnmetNeeds ?? [],
            possibleRepeatingPatterns: possibleRepeatingPatterns ?? [],
            uncertainties: uncertainties ?? [],
            pastControllability: pastControllability ?? .unknown,
            presentAgency: presentAgency ?? .unknown,
            recommendedRoute: recommendedRoute ?? .explore,
            secondaryRoutes: secondaryRoutes ?? [],
            reasonCodes: reasonCodes ?? [],
            missingInformation: missingInformation ?? [],
            nextQuestionGoal: nextQuestionGoal ?? "invite one concrete detail",
            semanticRelations: semanticRelations ?? [],
            responsePlan: responsePlan,
            confidence: confidence ?? 0
        )
    }
}

extension ReflectionPromptFactory {
    static let pendingCardMappingProtocolCorrection = """
    A substantive Card Reading is already visible and the current application-owned prompt is \
    cardMapping. Interpret the latest user reply functionally against that exact pending \
    confirmation: continuing or elaborating within the proposed relation without correction is \
    accepted; directly changing it is revised; contradicting or rejecting it is rejected; only \
    genuine uncertainty or ambiguity is unclear. No approval word is required, and an ordinary \
    answer to the reading's content-forward question is a valid confirmation response. If it \
    accepts, revises, or rejects the reading, preserve that decision and referenceID, use \
    replyIntent=directCandidReflection, move to requestedStage=directReflection, and set \
    nextPrompt=none. This transaction only commits the old confirmation; Swift will request the \
    first directReflection reply in a fresh protocolContinuation turn. Do not draft that question \
    now, do not use presentCardReading, and do not ask for the mapping again. For a revision or \
    rejection, the latest user correction replaces only the post-guidance candidate: atomically recompose \
    episodeStructure and replace situationUnderstanding without reusing the rejected cause or \
    motive. Replace optional tenderUnderstanding only when the correction itself supports an \
    event-versus-whole-person distinction. Preserve the confirmed cardRealityConnection unchanged; \
    do not return or modify cardRealityConnection in this repair. A revision may replace the \
    post-guidance cardInterpretiveTension and must replace cardNegotiatedMeaning; a rejection \
    withdraws only those candidate interpretation fields. Only if the latest \
    reply is genuinely unclear may you resolve it as unclear, stay in \
    cardReflection, use presentCardReading with an updated non-empty cardNegotiatedMeaning, and \
    establish a new cardMapping confirmationRequest.
    """

    static let finalNarrativeObjectProtocolCorrection = """
    The reflection is already narrative-ready. Do not return to directCandidReflection or ask \
    another question. Keep replyIntent=presentFinalNarrative, requestedStage=narrativeConfirmation, \
    localAction=none, store the complete non-empty candidate in memoryUpdate.finalNarrative, and \
    create a finalNarrative confirmationRequest. Rewrite confirmed relations into one natural \
    narrative; do not concatenate the tracking baseline, card dialogue, and individual answers.
    """
}

enum LLMError: LocalizedError {
    case malformedResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "AI 服务返回了无法解析的内容"
        case .unavailable: "AI 服务暂时不可用"
        }
    }
}
