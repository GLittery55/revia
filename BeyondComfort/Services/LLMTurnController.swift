import Foundation
import os

enum LLMTurnTrigger: String, Codable {
    case sessionStarted
    case userMessage
    case cardDisplayed
    case cardGuidanceAvailable
    /// Application event emitted after a confirmation-only protocol transaction commits. It asks
    /// for the first visible turn in the newly entered stage without consuming the user reply twice.
    case protocolContinuation
    case protocolCorrection
}

struct LLMTurnTrackingCandidate: Codable, Equatable {
    let id: String
    /// A deterministic summary calculated by the app. Never a raw HealthKit/EventKit sample.
    let observation: String
}

struct LLMTurnTrackingPresentationContext: Codable, Equatable {
    let id: String
    let cueIDs: [String]
}

/// Application-supplied scope for card-to-reality work. Every value is projected from the
/// already committed focal episode; it is not a new interpretation and never contains another
/// life story invented for the card. The model still chooses how to compare the image with this
/// episode, while Swift guarantees which episode remains in scope.
struct LLMTurnCardRealityAnchor: Codable, Equatable, Sendable {
    let concreteFacts: [String]
    let eventProcess: [String]
    let impacts: [String]

    var hasContent: Bool {
        [concreteFacts, eventProcess, impacts].contains { values in
            values.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}

struct LLMTurnCardContext: Codable, Equatable {
    let imageIsDisplayed: Bool
    /// Application-owned protocol counters. They describe only which card capabilities have
    /// already been used; they do not classify the person's words.
    let imageDevelopmentTurnCount: Int
    let connectionAttemptCount: Int
    let connectionScaffoldUsed: Bool
    let connectionUnavailable: Bool
    /// The one current episode that every pre-guidance reality connection must remain inside.
    /// Nil means the app has no committed event basis and the model may not search for a
    /// substitute example elsewhere in the person's life.
    let realityAnchor: LLMTurnCardRealityAnchor?
    /// Questions must use only visual
    /// elements the person has already mentioned.
    let visualScaffolds: [CardVisualScaffold]
    /// System-wide response methods become available only after a user-authored image-to-life
    /// mapping is confirmed. They respond to that interpretation and never define the card.
    let reflectionApproaches: SystemReflectionApproaches?
    /// Card-specific reference relationships are nil before the image-to-life mapping boundary.
    /// Even when present, they are question lenses whose use requires joint user evidence—not
    /// stored interpretations or answers.
    let referenceGuidance: CardReferenceGuidance?
    let prohibitedClaims: [String]

    init(
        imageIsDisplayed: Bool,
        imageDevelopmentTurnCount: Int = 0,
        connectionAttemptCount: Int = 0,
        connectionScaffoldUsed: Bool = false,
        connectionUnavailable: Bool = false,
        realityAnchor: LLMTurnCardRealityAnchor? = nil,
        visualScaffolds: [CardVisualScaffold],
        reflectionApproaches: SystemReflectionApproaches?,
        referenceGuidance: CardReferenceGuidance? = nil,
        prohibitedClaims: [String]
    ) {
        self.imageIsDisplayed = imageIsDisplayed
        self.imageDevelopmentTurnCount = imageDevelopmentTurnCount
        self.connectionAttemptCount = connectionAttemptCount
        self.connectionScaffoldUsed = connectionScaffoldUsed
        self.connectionUnavailable = connectionUnavailable
        self.realityAnchor = realityAnchor
        self.visualScaffolds = visualScaffolds
        self.reflectionApproaches = reflectionApproaches
        self.referenceGuidance = referenceGuidance
        self.prohibitedClaims = prohibitedClaims
    }

    private enum CodingKeys: String, CodingKey {
        case imageIsDisplayed, imageDevelopmentTurnCount, connectionAttemptCount
        case connectionScaffoldUsed
        case connectionUnavailable, realityAnchor, visualScaffolds, reflectionApproaches
        case prohibitedClaims
        case referenceGuidance
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        imageIsDisplayed = try box.decode(Bool.self, forKey: .imageIsDisplayed)
        imageDevelopmentTurnCount =
            (try? box.decode(Int.self, forKey: .imageDevelopmentTurnCount)) ?? 0
        connectionAttemptCount =
            (try? box.decode(Int.self, forKey: .connectionAttemptCount)) ?? 0
        connectionScaffoldUsed =
            (try? box.decode(Bool.self, forKey: .connectionScaffoldUsed)) ?? false
        connectionUnavailable =
            (try? box.decode(Bool.self, forKey: .connectionUnavailable)) ?? false
        realityAnchor =
            try? box.decodeIfPresent(LLMTurnCardRealityAnchor.self, forKey: .realityAnchor)
        visualScaffolds =
            (try? box.decode([CardVisualScaffold].self, forKey: .visualScaffolds)) ?? []
        reflectionApproaches =
            try? box.decodeIfPresent(SystemReflectionApproaches.self, forKey: .reflectionApproaches)
        referenceGuidance =
            try? box.decodeIfPresent(CardReferenceGuidance.self, forKey: .referenceGuidance)
        prohibitedClaims =
            (try? box.decode([String].self, forKey: .prohibitedClaims)) ?? []
    }
}

struct LLMTurnTranscriptItem: Codable, Equatable {
    let role: MessageRole
    let content: String
}

struct LLMTurnControllerRequest: Codable, Equatable {
    let trigger: LLMTurnTrigger
    /// Selects an immutable server prompt contract. Older in-progress sessions continue using the
    /// v1 registry entry after an app update; only current sessions opt into the v2 interaction.
    let protocolVersion: Int
    let protocolStage: ReflectionProtocolStage
    let condition: ExperimentalCondition
    let permissions: ReflectionProtocolPermissions
    let recentMessages: [LLMTurnTranscriptItem]
    let semanticMemory: TurnSemanticMemory
    /// Unused cues that may still be selected by the presentTrackingCue local action.
    let trackingCandidates: [LLMTurnTrackingCandidate]
    /// One local, measurement-free hypothesis. Current sessions may use it in one ordinary
    /// functional-relationship question; only the person's typed interpretation can enter later
    /// reflection. Legacy sessions may still fold it into their visible Tender synthesis.
    let contextualLoadCue: DialogueContextCue?
    /// Cues already shown to the person. Their exact opaque IDs are the only IDs permitted in a
    /// later trackingAssessment; keeping this list separate prevents a presented cue from being
    /// selected again as a new local action.
    let presentedTrackingCues: [LLMTurnTrackingCandidate]
    /// Current application-owned batch awaiting a relationship decision, if one exists.
    let activeTrackingPresentation: LLMTurnTrackingPresentationContext?
    /// Application-owned confirmation state. `cardNegotiatedMeaning` may also hold a pending
    /// candidate while this is false, so the model must not infer confirmation from text presence.
    let cardMappingConfirmed: Bool
    let card: LLMTurnCardContext?
    /// Populated only for the single protocol-regeneration attempt. It contains no reflection
    /// content and tells the model only which protocol boundary was invalid.
    let protocolCorrection: String?

    init(
        trigger: LLMTurnTrigger,
        protocolVersion: Int = ReflectionSession.currentProtocolVersion,
        protocolStage: ReflectionProtocolStage,
        condition: ExperimentalCondition,
        permissions: ReflectionProtocolPermissions,
        recentMessages: [LLMTurnTranscriptItem],
        semanticMemory: TurnSemanticMemory,
        trackingCandidates: [LLMTurnTrackingCandidate],
        contextualLoadCue: DialogueContextCue? = nil,
        presentedTrackingCues: [LLMTurnTrackingCandidate] = [],
        activeTrackingPresentation: LLMTurnTrackingPresentationContext? = nil,
        cardMappingConfirmed: Bool = false,
        card: LLMTurnCardContext?,
        protocolCorrection: String?
    ) {
        self.trigger = trigger
        self.protocolVersion = protocolVersion
        self.protocolStage = protocolStage
        self.condition = condition
        self.permissions = permissions
        self.recentMessages = recentMessages
        self.semanticMemory = semanticMemory
        self.trackingCandidates = trackingCandidates
        self.contextualLoadCue = contextualLoadCue
        self.presentedTrackingCues = presentedTrackingCues
        self.activeTrackingPresentation = activeTrackingPresentation
        self.cardMappingConfirmed = cardMappingConfirmed
        self.card = card
        self.protocolCorrection = protocolCorrection
    }
}

protocol LLMTurnPlanning: Sendable {
    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan
}

protocol LLMTurnWriting: Sendable {
    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse
}

protocol LLMTurnCritiquing: Sendable {
    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse
}

protocol LLMTurnPlanCritiquing: Sendable {
    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse
}

protocol ReflectionTurnControlling: Sendable {
    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan
    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse
}

struct TurnPlannerDecodingDiagnostic: Equatable, Sendable {
    let kind: String
    let keyPath: String
    let invalidTrackingRelevance: String?
    let invalidReplyIntent: String?
    let invalidConfirmationTarget: String?
    let invalidNextPromptKind: String?
    let invalidConfirmationDecision: String?
    let invalidPracticeKind: String?
    let invalidNoActionReason: String?

    init(
        kind: String,
        keyPath: String,
        invalidTrackingRelevance: String? = nil,
        invalidReplyIntent: String? = nil,
        invalidConfirmationTarget: String? = nil,
        invalidNextPromptKind: String? = nil,
        invalidConfirmationDecision: String? = nil,
        invalidPracticeKind: String? = nil,
        invalidNoActionReason: String? = nil
    ) {
        self.kind = kind
        self.keyPath = keyPath
        self.invalidTrackingRelevance = invalidTrackingRelevance
        self.invalidReplyIntent = invalidReplyIntent
        self.invalidConfirmationTarget = invalidConfirmationTarget
        self.invalidNextPromptKind = invalidNextPromptKind
        self.invalidConfirmationDecision = invalidConfirmationDecision
        self.invalidPracticeKind = invalidPracticeKind
        self.invalidNoActionReason = invalidNoActionReason
    }

    static func make(error: Error, content: String) -> TurnPlannerDecodingDiagnostic {
        let kind: String
        let codingPath: [any CodingKey]
        switch error {
        case DecodingError.typeMismatch(_, let context):
            kind = "type_mismatch"
            codingPath = context.codingPath
        case DecodingError.valueNotFound(_, let context):
            kind = "value_not_found"
            codingPath = context.codingPath
        case DecodingError.keyNotFound(let key, let context):
            kind = "key_not_found"
            codingPath = context.codingPath + [key]
        case DecodingError.dataCorrupted(let context):
            kind = "data_corrupted"
            codingPath = context.codingPath
        default:
            kind = "unknown"
            codingPath = []
        }

        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return TurnPlannerDecodingDiagnostic(
            kind: kind,
            keyPath: path.isEmpty ? "root" : String(path.prefix(180)),
            invalidTrackingRelevance: invalidTrackingRelevance(in: content),
            invalidReplyIntent: invalidReplyIntent(in: content),
            invalidConfirmationTarget: invalidConfirmationTarget(in: content),
            invalidNextPromptKind: invalidNextPromptKind(in: content),
            invalidConfirmationDecision: invalidConfirmationDecision(in: content),
            invalidPracticeKind: invalidPracticeKind(in: content),
            invalidNoActionReason: invalidNoActionReason(in: content)
        )
    }

    private static func invalidTrackingRelevance(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memory = root["memoryUpdate"] as? [String: Any],
              let assessments = memory["trackingAssessments"] as? [[String: Any]] else {
            return nil
        }
        let allowed = Set(["related", "partlyRelated", "unrelated", "uncertain"])
        guard let raw = assessments
            .compactMap({ $0["relevance"] as? String })
            .first(where: { !allowed.contains($0) }) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidReplyIntent(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["replyIntent"] as? String,
              !Set(TurnReplyIntent.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidConfirmationTarget(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = (
                  (root["resolvedConfirmation"] as? [String: Any])?["target"]
                  ?? (root["nextPrompt"] as? [String: Any])?["target"]
                  ?? (root["memoryUpdate"] as? [String: Any])?["pendingConfirmationTarget"]
              ) as? String,
              !Set(TurnConfirmationTarget.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidNextPromptKind(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nextPrompt = root["nextPrompt"] as? [String: Any],
              let raw = nextPrompt["kind"] as? String,
              !Set(TurnNextPromptKind.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidConfirmationDecision(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resolved = root["resolvedConfirmation"] as? [String: Any],
              let raw = resolved["decision"] as? String,
              !Set(TurnConfirmationDecision.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidPracticeKind(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memory = root["memoryUpdate"] as? [String: Any],
              let raw = memory["practiceKind"] as? String,
              !Set(TurnPracticeKind.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidNoActionReason(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["noActionReason"] as? String,
              !Set(TurnNoActionReason.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func safeEnumValue(_ raw: String) -> String {
        let safeASCII = raw.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
        return safeASCII ? String(raw.prefix(40)) : "non_contract_value"
    }
}

enum LLMTurnControllerClientError: Error {
    case plannerDecoding(TurnPlannerDecodingDiagnostic)
}

enum LLMTurnCriticVerdict: String, Codable, Sendable {
    case pass
    case reviseWriter
}

enum LLMTurnPlanCriticVerdict: String, Codable, Sendable {
    case pass
    case revisePlanner
}

struct LLMTurnPlanCriticResponse: Codable, Equatable, Sendable {
    let verdict: LLMTurnPlanCriticVerdict
    let reasonCodes: [String]
    let revisionGuidance: String?
}

struct LLMTurnCriticResponse: Codable, Equatable, Sendable {
    let verdict: LLMTurnCriticVerdict
    let reasonCodes: [String]
    let revisionGuidance: String?
}

enum ServerTurnPrompt {
    /// Immutable server registry key. A prompt update must introduce a new value rather than
    /// changing the meaning of this version for an in-progress research session.
    static let version = "turn-v4-server-v34"

    static func version(for _: Int) -> String {
        version
    }

    enum Task: String {
        case planner
        case planCritic = "plan_critic"
        case writer
        case writerCritic = "writer_critic"
        case writerRevision = "writer_revision"
    }
}

private struct PlannerPromptPayload: Encodable {
    let request: LLMTurnControllerRequest
}

private struct PlanCriticPromptPayload: Encodable {
    let request: LLMTurnControllerRequest
    let plan: LLMTurnResponsePlan
}

private struct WriterPromptPayload: Encodable {
    let request: LLMTurnControllerRequest
    let plan: LLMTurnResponsePlan
}

private struct WriterCriticPromptPayload: Encodable {
    let request: LLMTurnControllerRequest
    let plan: LLMTurnResponsePlan
    let draft: LLMTurnWriterResponse
}

private struct WriterRevisionPromptPayload: Encodable {
    let request: LLMTurnControllerRequest
    let plan: LLMTurnResponsePlan
    let draft: LLMTurnWriterResponse
    let critique: LLMTurnCriticResponse
}

struct RemoteLLMTurnPlanner: LLMTurnPlanning {
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "TurnController")

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: ServerTurnPrompt.Task.planner.rawValue,
            promptVersion: ServerTurnPrompt.version(for: request.protocolVersion),
            payload: PlannerPromptPayload(request: request),
            maxTokens: 1_600,
            temperature: 0.28
        )
        guard let data = content.data(using: .utf8) else { throw LLMError.malformedResponse }
        do {
            return try JSONDecoder().decode(LLMTurnResponsePlan.self, from: data)
        } catch {
            let diagnostic = TurnPlannerDecodingDiagnostic.make(
                error: error,
                content: content
            )
            let invalidRelevance = diagnostic.invalidTrackingRelevance ?? "none"
            let invalidIntent = diagnostic.invalidReplyIntent ?? "none"
            let invalidConfirmation = diagnostic.invalidConfirmationTarget ?? "none"
            let invalidPromptKind = diagnostic.invalidNextPromptKind ?? "none"
            let invalidDecision = diagnostic.invalidConfirmationDecision ?? "none"
            let invalidPractice = diagnostic.invalidPracticeKind ?? "none"
            let invalidNoActionReason = diagnostic.invalidNoActionReason ?? "none"
            logger.error(
                "TurnPlanner JSON invalid kind=\(diagnostic.kind, privacy: .public) key_path=\(diagnostic.keyPath, privacy: .public) invalid_tracking_relevance=\(invalidRelevance, privacy: .public) invalid_reply_intent=\(invalidIntent, privacy: .public) invalid_confirmation_target=\(invalidConfirmation, privacy: .public) invalid_next_prompt_kind=\(invalidPromptKind, privacy: .public) invalid_confirmation_decision=\(invalidDecision, privacy: .public) invalid_practice_kind=\(invalidPractice, privacy: .public) invalid_no_action_reason=\(invalidNoActionReason, privacy: .public)"
            )
            throw LLMTurnControllerClientError.plannerDecoding(diagnostic)
        }
    }
}

struct RemoteLLMTurnWriter: LLMTurnWriting {
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "TurnWriter")

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: ServerTurnPrompt.Task.writer.rawValue,
            promptVersion: ServerTurnPrompt.version(for: request.protocolVersion),
            payload: WriterPromptPayload(request: request, plan: plan),
            maxTokens: 700,
            temperature: 0.42
        )
        guard let data = content.data(using: .utf8) else { throw LLMError.malformedResponse }
        do {
            return try JSONDecoder().decode(LLMTurnWriterResponse.self, from: data)
        } catch {
            logger.error(
                "TurnWriter JSON invalid. Error type: \(String(describing: type(of: error)), privacy: .public)"
            )
            throw LLMError.malformedResponse
        }
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: ServerTurnPrompt.Task.writerRevision.rawValue,
            promptVersion: ServerTurnPrompt.version(for: request.protocolVersion),
            payload: WriterRevisionPromptPayload(
                request: request,
                plan: plan,
                draft: draft,
                critique: critique
            ),
            maxTokens: 700,
            temperature: 0.32
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnWriterResponse.self,
                  from: data
              ) else {
            logger.error("TurnWriter revision JSON invalid")
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteLLMTurnPlanCritic: LLMTurnPlanCritiquing {
    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: ServerTurnPrompt.Task.planCritic.rawValue,
            promptVersion: ServerTurnPrompt.version(for: request.protocolVersion),
            payload: PlanCriticPromptPayload(request: request, plan: plan),
            maxTokens: 320,
            temperature: 0.0
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnPlanCriticResponse.self,
                  from: data
              ) else {
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteLLMTurnCritic: LLMTurnCritiquing {
    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse {
        let content = try await RemoteAPIService.shared.completeTurnJSON(
            task: ServerTurnPrompt.Task.writerCritic.rawValue,
            promptVersion: ServerTurnPrompt.version(for: request.protocolVersion),
            payload: WriterCriticPromptPayload(request: request, plan: plan, draft: draft),
            maxTokens: 320,
            temperature: 0.0
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnCriticResponse.self,
                  from: data
              ) else {
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteReflectionTurnController: ReflectionTurnControlling {
    private let planner: any LLMTurnPlanning
    private let planCritic: any LLMTurnPlanCritiquing
    private let writer: any LLMTurnWriting
    private let critic: any LLMTurnCritiquing
    private let protocolController = ReflectionProtocolController()
    private let logger = Logger(
        subsystem: "com.wj.BeyondComfort",
        category: "TurnController"
    )

    init(
        planner: any LLMTurnPlanning = RemoteLLMTurnPlanner(),
        planCritic: any LLMTurnPlanCritiquing = RemoteLLMTurnPlanCritic(),
        writer: any LLMTurnWriting = RemoteLLMTurnWriter(),
        critic: any LLMTurnCritiquing = RemoteLLMTurnCritic()
    ) {
        self.planner = planner
        self.planCritic = planCritic
        self.writer = writer
        self.critic = critic
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        let initial = normalizeApplicationEventPlan(
            try await planner.planTurn(request),
            request: request
        )
        var candidate = initial

        // Repair a small set of content-free protocol-shape defects before the semantic Critic.
        // This audit never decides whether the story is complete or what the person means. It
        // only prevents a Planner from requesting a capability absent from CURRENT PERMISSIONS,
        // or from presenting an object it omitted from the same atomic plan.
        var structuralRevisionCount = 0
        while structuralRevisionCount < 2,
              let structuralCritique = deterministicPlanCritique(
                  candidate,
                  request: request
              ) {
            do {
                let revisedRequest = requestWithPlanCorrection(
                    request,
                    critique: structuralCritique
                )
                candidate = normalizeApplicationEventPlan(
                    try await planner.planTurn(revisedRequest),
                    request: request
                )
                structuralRevisionCount += 1
            } catch {
                logger.warning("turn_planner_structural_revision_unavailable")
                return candidate
            }
        }

        guard requiresSemanticPlanCritic(candidate, request: request) else {
            return candidate
        }

        // A Swift-authored protocol correction is already a narrowed repair contract. Running a
        // semantic Critic around that repair can re-open the forbidden choice and previously
        // expanded one failed disclosure turn into Planner-Critic-Planner-Critic twice. Let Swift
        // validate the one repaired candidate directly.
        guard request.trigger != .protocolCorrection else {
            return candidate
        }

        // Semantic progression remains LLM-owned. Swift only invokes one bounded plan audit and
        // carries its content-free correction back to the Planner; it does not decide whether the
        // user's answer is emotionally complete or which topic should come next.
        do {
            let firstCritique = try await planCritic.critiquePlan(
                request: request,
                plan: candidate
            )
            guard firstCritique.verdict == .revisePlanner else {
                return candidate
            }
            let revisedRequest = requestWithPlanCorrection(
                request,
                critique: firstCritique
            )
            let revised = normalizeApplicationEventPlan(
                try await planner.planTurn(revisedRequest),
                request: request
            )
            if !requiresSemanticPlanCritic(revised, request: request) {
                return revised
            }
            let finalCritique = try await planCritic.critiquePlan(
                request: request,
                plan: revised
            )
            if finalCritique.verdict != .pass {
                logger.warning(
                    "turn_planner_semantic_quality_unresolved reason_count=\(finalCritique.reasonCodes.count, privacy: .public)"
                )
                if revised.cardReferenceSelection != nil,
                   finalCritique.reasonCodes.contains(
                       "unsupported_card_reference_selection"
                   ) {
                    // The LLM Critic—not Swift—made the evidence judgment. Removing this optional
                    // lens is a safe enforcement of that judgment: the conversational operation,
                    // memory patch, and question purpose remain unchanged.
                    return removingCardReferenceSelection(from: revised)
                }
                let fallbackPermissions = narrowedDisclosurePermissions(
                    request.permissions,
                    rejecting: revised,
                    reasonCodes: finalCritique.reasonCodes
                )
                let fallbackRequest = requestWithPlanCorrection(
                    request,
                    critique: finalCritique,
                    permissions: fallbackPermissions
                )
                do {
                    let fallback = normalizeApplicationEventPlan(
                        try await planner.planTurn(fallbackRequest),
                        request: fallbackRequest
                    )
                    if deterministicPlanCritique(fallback, request: fallbackRequest) == nil {
                        let fallbackCritique = try await planCritic.critiquePlan(
                            request: fallbackRequest,
                            plan: fallback
                        )
                        if fallbackCritique.verdict == .pass {
                            logger.notice("turn_planner_bounded_fallback result=semantic_pass")
                            return fallback
                        }
                    }
                } catch {
                    logger.warning("turn_planner_bounded_fallback result=unavailable")
                }
                logger.notice("turn_planner_bounded_fallback result=typed_safe_plan")
                return boundedDisclosureFallbackPlan(
                    request: fallbackRequest,
                    rejected: revised,
                    reasonCodes: finalCritique.reasonCodes
                )
            }
            return revised
        } catch {
            logger.warning("turn_planner_semantic_critic_unavailable")
            if request.protocolStage == .contextualDisclosure {
                return boundedDisclosureFallbackPlan(
                    request: request,
                    rejected: candidate,
                    reasonCodes: ["semantic_critic_unavailable"]
                )
            }
            return candidate
        }
    }

    /// Returns a content-free revision request for defects that can be established solely from
    /// the typed request and plan. Conversation meaning remains entirely with the Planner.
    private func deterministicPlanCritique(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> LLMTurnPlanCriticResponse? {
        let isDerivedGuidanceSuccessor = isDeterministicGuidanceSuccessor(
            plan,
            request: request
        )
        if !request.permissions.allowedOperations.isEmpty,
           !isDerivedGuidanceSuccessor {
            let selected = TurnProtocolOperation(
                requestedStage: plan.requestedStage,
                replyIntent: plan.replyIntent,
                localAction: plan.localAction.kind
            )
            if !request.permissions.allowedOperations.contains(selected) {
                return LLMTurnPlanCriticResponse(
                    verdict: .revisePlanner,
                    reasonCodes: ["permission_operation_invalid"],
                    revisionGuidance: "Select one complete requestedStage, replyIntent, and localAction tuple exactly as listed in CURRENT ALLOWED OPERATIONS. Never combine fields from different tuples."
                )
            }
        }
        if !request.permissions.allowedReplyIntents.contains(plan.replyIntent),
           !isDerivedGuidanceSuccessor {
            return LLMTurnPlanCriticResponse(
                verdict: .revisePlanner,
                reasonCodes: ["permission_contract_invalid"],
                revisionGuidance: "Use exactly one replyIntent from CURRENT PERMISSIONS. Do not use a legacy tracking intent unless the request exposes it."
            )
        }
        if !request.permissions.allowedActions.contains(plan.localAction.kind),
           !isDerivedGuidanceSuccessor {
            return LLMTurnPlanCriticResponse(
                verdict: .revisePlanner,
                reasonCodes: ["permission_contract_invalid"],
                revisionGuidance: "Use exactly one localAction from CURRENT PERMISSIONS and keep trackingCueIDs empty for kind none."
            )
        }

        if let selection = plan.cardReferenceSelection {
            let relationCount = request.card?.referenceGuidance?.relations.count ?? 0
            let isPermittedQuestion =
                (plan.replyIntent == .presentCardReading
                    && plan.nextPrompt?.kind == .confirmationRequest
                    && plan.nextPrompt?.target == .cardMapping)
                || (plan.replyIntent == .directCandidReflection
                    && plan.nextPrompt?.kind == .openQuestion)
            if relationCount == 0
                || !(0..<relationCount).contains(selection.relationIndex)
                || !isPermittedQuestion {
                return LLMTurnPlanCriticResponse(
                    verdict: .revisePlanner,
                    reasonCodes: ["card_reference_permission_invalid"],
                    revisionGuidance: "Remove cardReferenceSelection unless the current request supplies referenceGuidance and the selected zero-based index shapes one permitted post-mapping question."
                )
            }
        }

        if request.protocolVersion >= ReflectionSession.currentProtocolVersion,
           request.protocolStage == .cardReflection,
           [.developCardImage, .inviteCardConnection].contains(plan.replyIntent),
           plan.nextPrompt?.kind != .openQuestion,
           !(plan.replyIntent == .inviteCardConnection
                && plan.memoryUpdate.pendingCardRealityConnection?.isStructurallyComplete == true
                && plan.nextPrompt?.kind == .confirmationRequest
                && plan.nextPrompt?.target == .cardRealityConnection) {
            return LLMTurnPlanCriticResponse(
                verdict: .revisePlanner,
                reasonCodes: ["card_connection_question_missing"],
                revisionGuidance: "A card-image development or image-to-life connection operation must leave one concrete open question. Keep the same stage and choose an allowed operation with nextPrompt.kind=openQuestion; do not replace it with an event recap or a questionless acknowledgement."
            )
        }

        if plan.replyIntent == .integrateTrackingAndPresentTenderSummary {
            let currentPrompt = request.semanticMemory.nextPrompt
            let pendingTarget = currentPrompt?.target
                ?? request.semanticMemory.pendingConfirmationTarget
            let hasPendingTrackingConfirmation =
                pendingTarget == .trackingRelationship
                && (
                    request.activeTrackingPresentation != nil
                    || !request.presentedTrackingCues.isEmpty
                )
            let resolvesTracking =
                plan.resolvedConfirmation?.target == .trackingRelationship
            if !hasPendingTrackingConfirmation || !resolvesTracking {
                return LLMTurnPlanCriticResponse(
                    verdict: .revisePlanner,
                    reasonCodes: ["tracking_boundary_ignored"],
                    revisionGuidance: "Do not use integrateTrackingAndPresentTenderSummary without a pending trackingRelationship confirmation. Use an allowed ordinary context or Tender intent."
                )
            }
        }

        return nil
    }

    private func isDeterministicGuidanceSuccessor(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> Bool {
        request.protocolVersion >= ReflectionSession.currentProtocolVersion
            && request.protocolStage == .cardReflection
            && request.card?.imageIsDisplayed == true
            && request.card?.connectionUnavailable == false
            && request.card?.reflectionApproaches == nil
            && plan.requestedStage == .cardReflection
            && plan.replyIntent == .authorizeCardGuidance
            && plan.localAction.kind == .shareCardGuidance
            && plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil
    }

    /// Card display and guidance availability are application events. They carry the previous
    /// user turn for conversational context, but that turn's confirmation was already consumed by
    /// the local action that produced this event. Removing an echoed resolution is protocol
    /// normalization, not semantic interpretation, and prevents a stale “好/贴切” from being
    /// applied twice.
    private func normalizeApplicationEventPlan(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> LLMTurnResponsePlan {
        var normalized = plan
        if [.cardDisplayed, .cardGuidanceAvailable, .protocolContinuation]
            .contains(request.trigger),
           plan.resolvedConfirmation != nil {
            normalized = LLMTurnResponsePlan(
                requestedStage: plan.requestedStage,
                localAction: plan.localAction,
                memoryUpdate: plan.memoryUpdate,
                resolvedConfirmation: nil,
                nextPrompt: plan.nextPrompt,
                replyIntent: plan.replyIntent,
                noActionReason: plan.noActionReason,
                replyGuidance: plan.replyGuidance,
                cardReferenceSelection: plan.cardReferenceSelection
            )
        }

        if normalized.resolvedConfirmation?.target == .cardRealityConnection,
           let promoted = TurnCardRealityConnectionResolver.effective(
               memory: request.semanticMemory,
               update: normalized.memoryUpdate,
               resolution: normalized.resolvedConfirmation
           ) {
            var promotedMemory = normalized.memoryUpdate
            promotedMemory.cardRealityConnection = promoted
            promotedMemory.clearPendingCardRealityConnection = true
            promotedMemory.cardConnectionOutcome = .connectionConfirmed
            normalized = LLMTurnResponsePlan(
                requestedStage: normalized.requestedStage,
                localAction: normalized.localAction,
                memoryUpdate: promotedMemory,
                resolvedConfirmation: normalized.resolvedConfirmation,
                nextPrompt: normalized.nextPrompt,
                replyIntent: normalized.replyIntent,
                noActionReason: normalized.noActionReason,
                replyGuidance: normalized.replyGuidance,
                cardReferenceSelection: normalized.cardReferenceSelection
            )
        }

        guard request.protocolVersion >= ReflectionSession.currentProtocolVersion,
              request.protocolStage == .cardReflection,
              request.card?.imageIsDisplayed == true,
              request.card?.connectionUnavailable == false,
              request.card?.reflectionApproaches == nil,
              normalized.memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil else {
            return normalized
        }

        // Once the Planner has emitted the typed user-authored reality mapping, every remaining
        // field of this transition is application mechanics. Canonicalize it before a second LLM
        // audit can turn a valid connection into another visible question or an invalid mixed
        // operation. Swift does not inspect the person's words or create the mapping.
        var evidenceOnlyMemory = normalized.memoryUpdate
        evidenceOnlyMemory.cardConnectionOutcome = .connectionConfirmed
        evidenceOnlyMemory.clearPendingCardRealityConnection = true
        evidenceOnlyMemory.cardNegotiatedMeaning = nil
        evidenceOnlyMemory.contextCueOffered = nil
        evidenceOnlyMemory.candidUnderstanding = nil
        evidenceOnlyMemory.fierceUnderstanding = nil
        evidenceOnlyMemory.finalNarrative = nil
        evidenceOnlyMemory.practiceOptions = nil
        evidenceOnlyMemory.practiceKind = nil
        evidenceOnlyMemory.selectedPractice = nil
        return LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: evidenceOnlyMemory,
            resolvedConfirmation: normalized.resolvedConfirmation,
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .authorizeCardGuidance,
            noActionReason: nil,
            replyGuidance: "Commit the typed user-authored image-to-life mapping and silently authorize one candidate reading."
        )
    }

    private func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func removingCardReferenceSelection(
        from plan: LLMTurnResponsePlan
    ) -> LLMTurnResponsePlan {
        LLMTurnResponsePlan(
            requestedStage: plan.requestedStage,
            localAction: plan.localAction,
            memoryUpdate: plan.memoryUpdate,
            resolvedConfirmation: plan.resolvedConfirmation,
            nextPrompt: plan.nextPrompt,
            replyIntent: plan.replyIntent,
            noActionReason: plan.noActionReason,
            replyGuidance: plan.replyGuidance,
            cardReferenceSelection: nil
        )
    }

    private func requiresSemanticPlanCritic(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> Bool {
        switch request.protocolStage {
        case .contextualDisclosure:
            // The Planner and semantic Critic—not Swift—decide whether another event question adds
            // value or whether the scene-plus-behavior story is ready for Tender grounding.
            return plan.replyIntent != .safetySupport
        case .cardConsent:
            return true
        case .cardReflection:
            if plan.replyIntent == .authorizeCardGuidance,
               plan.localAction.kind == .shareCardGuidance,
               plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil {
                // The Planner has already made the semantic extraction. The authorization is a
                // silent local capability transaction, so another semantic audit adds no user-
                // facing judgment and used to be a frequent interruption point.
                return false
            }
            return [
                .inviteCardObservation,
                .developCardImage,
                .inviteCardConnection,
                .deepenCardConnection,
                .authorizeCardGuidance,
                .presentCardReading,
                .directCandidReflection,
                .presentFinalNarrative,
            ].contains(plan.replyIntent)
        case .directReflection:
            return [.directCandidReflection, .presentFinalNarrative].contains(plan.replyIntent)
        case .narrativeConfirmation:
            return plan.replyIntent == .completeConversation
                || plan.replyIntent == .suggestPractice
        case .optionalAction:
            return [.suggestPractice, .revisePractice, .completeConversation]
                .contains(plan.replyIntent)
        default:
            return false
        }
    }

    private func requestWithPlanCorrection(
        _ request: LLMTurnControllerRequest,
        critique: LLMTurnPlanCriticResponse,
        permissions: ReflectionProtocolPermissions? = nil
    ) -> LLMTurnControllerRequest {
        let reasons = critique.reasonCodes
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .joined(separator: ",")
        let guidance = critique.revisionGuidance?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240) ?? ""
        let correction = """
        Semantic plan audit requested one bounded revision.
        reasonCodes=\(reasons.isEmpty ? "semantic_progression" : reasons)
        revisionGuidance=\(guidance.isEmpty ? "Remove the duplicated function or use an allowed Tender summary when ready." : String(guidance))
        Preserve permissions, confirmed relationships, tracking dispositions, and the latest answer.
        """
        return LLMTurnControllerRequest(
            trigger: .protocolCorrection,
            protocolVersion: request.protocolVersion,
            protocolStage: request.protocolStage,
            condition: request.condition,
            permissions: permissions ?? request.permissions,
            recentMessages: request.recentMessages,
            semanticMemory: request.semanticMemory,
            trackingCandidates: request.trackingCandidates,
            contextualLoadCue: request.contextualLoadCue,
            presentedTrackingCues: request.presentedTrackingCues,
            activeTrackingPresentation: request.activeTrackingPresentation,
            cardMappingConfirmed: request.cardMappingConfirmed,
            card: request.card,
            protocolCorrection: correction
        )
    }

    private func narrowedDisclosurePermissions(
        _ permissions: ReflectionProtocolPermissions,
        rejecting plan: LLMTurnResponsePlan,
        reasonCodes: [String]
    ) -> ReflectionProtocolPermissions {
        guard plan.replyIntent == .exploreContext,
              let rejectedPurpose = plan.nextPrompt?.disclosurePurpose,
              let rejectedTarget = plan.nextPrompt?.disclosureTarget,
              !Set(reasonCodes).isDisjoint(with: Set([
                  "duplicate_question_function",
                  "resolved_relation_reopened",
                  "latest_answer_ignored",
                  "unnecessary_event_detail",
              ])) else {
            return permissions
        }
        return ReflectionProtocolPermissions(
            currentStage: permissions.currentStage,
            allowedStages: permissions.allowedStages,
            allowedActions: permissions.allowedActions,
            allowedReplyIntents: permissions.allowedReplyIntents,
            allowedDisclosurePurposes: permissions.allowedDisclosurePurposes.filter {
                $0 != rejectedPurpose
            },
            allowedDisclosureTargets: permissions.allowedDisclosureTargets.filter {
                $0 != rejectedTarget
            },
            allowedOperations: permissions.allowedOperations
        )
    }

    /// Last semantic-resilience boundary for disclosure only. It chooses from typed state and
    /// capabilities after two Critic failures; it never reads Chinese or invents episode content.
    private func boundedDisclosureFallbackPlan(
        request: LLMTurnControllerRequest,
        rejected: LLMTurnResponsePlan,
        reasonCodes: [String]
    ) -> LLMTurnResponsePlan {
        guard request.protocolStage == .contextualDisclosure else { return rejected }
        let distrustsPatch = !Set(reasonCodes).isDisjoint(with: Set([
            "latest_answer_not_committed",
            "episode_structure_misclassified",
            "unsupported_memory_inference",
            "manufactured_global_self_judgment",
        ]))
        var update = distrustsPatch ? TurnSemanticMemoryUpdate() : rejected.memoryUpdate
        let disclosureState = EffectiveEventDisclosureState(
            memory: request.semanticMemory,
            update: update
        )
        let effective = disclosureState.memory

        let canInvite = request.condition.usesCard
            && isEventDisclosureCoreComplete(disclosureState)
            && request.permissions.allowedReplyIntents.contains(.inviteCardConsent)
        if canInvite {
            update.eventDisclosureOutcome = .readyForTenderOrCard
            switch effective.reflectionFocusKind {
            case .explicitGlobalSelfJudgment:
                update.tenderGroundingKind = .globalJudgmentDistinction
            case .specificSelfCriticism, .eventTension:
                update.tenderGroundingKind = .specificEventGrounding
            case .unclearFocus:
                update.tenderGroundingKind = TurnTenderGroundingKind.none
            }
            return LLMTurnResponsePlan(
                requestedStage: .cardConsent,
                localAction: .none,
                memoryUpdate: update,
                nextPrompt: .confirmationRequest(target: .cardConsent),
                replyIntent: .inviteCardConsent,
                replyGuidance: "Use only the confirmed typed episode and reflection focus for one brief grounding, then invite one optional random reflection card."
            )
        }

        let purpose = request.permissions.allowedDisclosurePurposes.first
            ?? TurnDisclosureQuestionPurpose.identifyConcreteEpisode
        return LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: update,
            nextPrompt: .openQuestion(
                purpose: purpose.rawValue,
                focus: "the one unresolved typed disclosure relationship",
                disclosurePurpose: purpose,
                disclosureTarget: purpose.target
            ),
            replyIntent: .exploreContext,
            replyGuidance: "Ask one direct, low-burden question for only the supplied typed disclosure purpose. Do not add a decision, stopping-awareness, emotion, responsibility, or action premise."
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        var draft = try await writer.writeTurn(
            request: request,
            plan: validatedPlan
        )

        // Swift checks only deterministic response shape. Semantic language quality is handled
        // below by the Writer Critic so synonymous or novel wording is judged in context rather
        // than against a phrase list. Neither path may change the validated Planner decision.
        let qualityIssues = protocolController.writerQualityIssues(
            draft,
            for: validatedPlan
        )
        var writerRevisionWasUsed = false
        if !qualityIssues.isEmpty {
            logger.warning(
                "turn_writer_soft_quality_warning issue_count=\(qualityIssues.count, privacy: .public)"
            )
            let critique = LLMTurnCriticResponse(
                verdict: .reviseWriter,
                reasonCodes: qualityIssues.map(\.rawValue),
                revisionGuidance: softWriterRevisionGuidance(
                    issues: qualityIssues,
                    plan: validatedPlan
                )
            )
            do {
                draft = try await writer.reviseTurn(
                    request: request,
                    plan: validatedPlan,
                    draft: draft,
                    critique: critique
                )
                writerRevisionWasUsed = true
            } catch {
                logger.warning(
                    "turn_writer_soft_revision_unavailable issue_count=\(qualityIssues.count, privacy: .public)"
                )
                // A wording-only repair is best-effort. The original draft realizes the validated
                // intent, so display it rather than attempting another rewrite path or involving
                // the Planner again.
                return draft
            }
        }

        guard requiresSemanticCritic(validatedPlan.replyIntent, request: request) else {
            return draft
        }

        // The Critic is an advisory quality pass, not a second workflow controller. If it is
        // unavailable, or still recommends polishing after one revision, keep the legal
        // Planner turn instead of converting a semantic quality concern into a protocol failure.
        var semanticCandidate = draft
        do {
            let firstCritique = try await critic.critiqueTurn(
                request: request,
                plan: validatedPlan,
                draft: draft
            )
            guard firstCritique.verdict == .reviseWriter else {
                return draft
            }
            if writerRevisionWasUsed {
                logger.warning(
                    "turn_writer_semantic_quality_unresolved reason_count=\(firstCritique.reasonCodes.count, privacy: .public)"
                )
                do {
                    let bounded = try await writer.reviseTurn(
                        request: request,
                        plan: validatedPlan,
                        draft: draft,
                        critique: boundedFallbackCritique(
                            firstCritique,
                            request: request,
                            plan: validatedPlan
                        )
                    )
                    logger.notice("bounded_fallback_used result=success")
                    return bounded
                } catch {
                    logger.warning("bounded_fallback_used result=unavailable")
                    return draft
                }
            }
            let revised = try await writer.reviseTurn(
                request: request,
                plan: validatedPlan,
                draft: draft,
                critique: firstCritique
            )
            semanticCandidate = revised
            let finalCritique = try await critic.critiqueTurn(
                request: request,
                plan: validatedPlan,
                draft: revised
            )
            if finalCritique.verdict != .pass {
                logger.warning(
                    "turn_writer_semantic_quality_unresolved reason_count=\(finalCritique.reasonCodes.count, privacy: .public)"
                )
                do {
                    let bounded = try await writer.reviseTurn(
                        request: request,
                        plan: validatedPlan,
                        draft: revised,
                        critique: boundedFallbackCritique(
                            finalCritique,
                            request: request,
                            plan: validatedPlan
                        )
                    )
                    logger.notice("bounded_fallback_used result=success")
                    return bounded
                } catch {
                    logger.warning("bounded_fallback_used result=unavailable")
                }
            }
            return revised
        } catch {
            logger.warning("turn_writer_semantic_critic_unavailable")
            return semanticCandidate
        }
    }

    /// One final LLM wording pass after two semantic boundary failures. The immutable typed plan
    /// remains the complete capability set; this instruction only removes unsupported material
    /// and cannot choose another question, stage, action, evidence source, or workflow branch.
    private func boundedFallbackCritique(
        _ critique: LLMTurnCriticResponse,
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) -> LLMTurnCriticResponse {
        let allowedEvidence = [
            "the current focal episode and request.card.realityAnchor",
            "the confirmed cardRealityConnection when present",
            "the validated replyIntent and nextPrompt purpose",
        ].joined(separator: "; ")
        return LLMTurnCriticResponse(
            verdict: .reviseWriter,
            reasonCodes: Array(critique.reasonCodes.prefix(6)),
            revisionGuidance: """
            Bounded final wording repair for currentStage=\(request.protocolStage.rawValue). \
            Preserve requestedStage=\(plan.requestedStage.rawValue), \
            replyIntent=\(plan.replyIntent.rawValue), localAction=\(plan.localAction.kind.rawValue), \
            and the exact question purpose/count. Use only: \(allowedEvidence). Do not use \
            unconfirmed tracking, an unselected reference relation, another life episode, or any \
            new motive, trait, diagnosis, need, cause, responsibility, or card meaning. Return one \
            natural Chinese reply and no protocol fields beyond the Writer schema.
            """
        )
    }

    private func softWriterRevisionGuidance(
        issues: [TurnWriterQualityIssue],
        plan: LLMTurnResponsePlan
    ) -> String {
        var guidance: [String] = [
            "Keep the validated Planner meaning, stage, and replyIntent unchanged.",
            "Revise only the visible Chinese wording.",
        ]
        if issues.contains(.realizedIntentMismatch) {
            guidance.append(
                "Return realizedIntent exactly \(plan.replyIntent.rawValue) and remove any later-stage function."
            )
        }
        if issues.contains(.expectedSingleQuestion) {
            guidance.append(
                "Express one natural primary question. Avoid stacked questions; punctuation is a wording preference, not a new semantic purpose."
            )
        }
        if issues.contains(.expectedNoQuestion) {
            guidance.append(
                "This turn establishes no next question. Rewrite it as a brief acknowledgement without asking anything."
            )
        }
        return guidance.joined(separator: " ")
    }

    private func requiresSemanticCritic(
        _ intent: TurnReplyIntent,
        request: LLMTurnControllerRequest
    ) -> Bool {
        switch intent {
        case .checkTrackingRelationship:
            return true
        case .exploreContext:
            // Disclosure wording is intentionally free of recap templates and stays within the
            // event-story scope. The semantic Critic may request one wording-only revision while
            // the validated Planner operation and question function remain immutable.
            return request.protocolStage == .contextualDisclosure
        case .directCandidReflection,
             .inviteCardConsent,
             .inviteCardObservation,
             .developCardImage,
             .inviteCardConnection,
             .deepenCardConnection,
             .presentTrackingContext,
             .integrateTrackingAndPresentTenderSummary,
             .presentTenderSummary,
             .requestTenderConfirmation,
             .reviseTenderSummary,
             .presentCardReading,
             .presentFinalNarrative,
             .requestNarrativeConfirmation,
             .reviseFinalNarrative,
             .suggestPractice,
             .revisePractice:
            return true
        default:
            return false
        }
    }
}
