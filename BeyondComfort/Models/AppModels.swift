import Foundation

struct AccountUser: Codable, Equatable {
    let id: String
    let username: String
    let consentVersion: String
    let consentedAt: Date
}

/// Server-authoritative study availability. The app uses it only to construct a local session;
/// it never infers a condition from completion history or chooses a version itself.
struct StudyAccess: Codable, Equatable {
    let status: String
    let isAvailable: Bool
    let sequence: StudySequence?
    let period: Int?
    let condition: ExperimentalCondition?
    let availableAt: Date?
}

struct StudyParticipant: Codable, Identifiable, Equatable {
    let id: String
    let username: String
}

struct StudySchedule: Codable, Identifiable, Equatable {
    let userId: String
    let username: String
    let sequence: StudySequence?
    let periodOneStartsAt: Date?
    let periodTwoStartsAt: Date?
    let enabled: Bool

    var id: String { userId }
}

struct StudyScheduleUpdate: Encodable {
    let sequence: StudySequence
    let periodOneStartsAt: Date?
    let periodTwoStartsAt: Date?
    let enabled: Bool
}

struct RemoteSessionSummary: Codable, Identifiable {
    let id: String
    let stage: String
    let createdAt: Date
    let updatedAt: Date
    let payload: [String: JSONValue]
}

struct ResumableReflection: Identifiable {
    let id: String
    let remoteID: String?
    let session: ReflectionSession
    let updatedAt: Date
}

enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

enum ReflectionState: String, Codable, CaseIterable, Sendable {
    case welcome
    case eventDisclosure
    case emotionDisclosure
    case bodilyResponse
    case selfJudgment
    case contextDisclosure
    case trackingPermission
    case trackingReview
    case tenderGrounding
    case readinessCheck
    case tenderExploration
    case cardIntroduction
    case cardInterpretation
    case attributionReflection
    case actionSelection
    case summary
    case completed
    case safetySupport

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if let state = Self(rawValue: value) {
            self = state
            return
        }
        // Migrate locally/cloud-persisted sessions from the earlier prototype state names.
        switch value {
        case "orient": self = .welcome
        case "contextGathering": self = .eventDisclosure
        case "contextConfirmation": self = .trackingPermission
        case "tenderGrounding": self = .tenderGrounding
        case "cardDraw": self = .cardIntroduction
        case "cardInterpretation": self = .cardInterpretation
        case "tenderExploration": self = .tenderExploration
        case "candidInquiry": self = .attributionReflection
        case "affirmationReadiness": self = .readinessCheck
        case "actionComposer": self = .actionSelection
        case "reviewClose": self = .summary
        case "safetyInterrupt": self = .safetySupport
        default: self = .welcome
        }
    }
}

typealias ReflectionStage = ReflectionState

/// Version 2 conversations deliberately keep only study-protocol boundaries in Swift. The LLM
/// decides the semantic purpose of each ordinary turn; this enum controls only which protocol
/// boundary and local capabilities are currently available.
enum ReflectionProtocolStage: String, Codable, CaseIterable, Sendable {
    case contextualDisclosure
    case cardConsent
    case cardReflection
    case directReflection
    case narrativeConfirmation
    case optionalAction
    case complete
    case safetySupport

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // LEGACY_DECODE_ONLY — an old pre-card Tender checkpoint resumes at the current
        // disclosure boundary. Canonical episode evidence then determines whether to invite the
        // card; no Tender confirmation object is recreated.
        if raw == "tenderConfirmation" {
            self = .contextualDisclosure
        } else if let value = Self(rawValue: raw) {
            self = value
        } else {
            self = .contextualDisclosure
        }
    }
}

/// Turn-local recovery contract selected from Swift-owned protocol state. This is never
/// persisted and never advances the workflow; it only tells the server which already-permitted
/// operation must be reconstructed after an invalid Planner object.
enum TurnRecoveryOperation: String, Codable, CaseIterable, Sendable {
    case eventDisclosure
    case cardConsent
    case cardOpenExploration
    case cardCandidateResolution
    case legacyCardReading
    case currentCardGuidance
    case directReflection
    case directSynthesis
    case optionalAction
    case finalNarrative
    case complete
    case safety
}

/// Coarse readiness is an application-owned progress lock, not a psychological judgment. The LLM
/// requests the transition by selecting reflection or final-narrative intent; Swift persists it
/// so a formatting repair cannot send an already-ready conversation back into more questioning.
enum ReflectionReadiness: String, Codable, Sendable {
    case needsTender
    /// Post-connection reflection is open. Tender is the semantic default; Fierce is an optional,
    /// evidence-bounded mode inside the same stage rather than a required later checkpoint.
    case reflectionOpen
    /// Legacy persisted value. New sessions use `reflectionOpen`; keeping this case preserves
    /// older research sessions without turning their stored label into a compulsory Fierce turn.
    case needsFierce
    case narrativeReady
}

enum TurnLocalActionKind: String, Codable, CaseIterable, Sendable {
    case none
    /// Marks a context-sized bundle of cleaned, application-supplied observations as presented.
    /// The planner may select one or several complementary observations from the bounded
    /// candidates Swift supplied; it never receives raw HealthKit or EventKit records.
    case presentTrackingCue
    /// Requests the application-owned uniform random draw. The model cannot provide a card ID.
    case drawRandomCard
    /// After the person has described an image relationship and connected it with a real
    /// relationship, authorizes use of that user-grounded relation for a tentative, correctable
    /// reading. No catalogue meaning enters the prompt or UI.
    case shareCardGuidance
    case completeSession
}

struct TurnLocalActionRequest: Codable, Equatable, Sendable {
    var kind: TurnLocalActionKind = .none
    var trackingCueIDs: [String] = []

    static let none = TurnLocalActionRequest()
}

enum TurnTrackingRelevance: String, Codable, CaseIterable, Sendable {
    case related, partlyRelated, unrelated, uncertain
}

/// Whether the person has actually expressed a self-critical proposition. Keeping absence and
/// uncertainty explicit prevents a reflection model from inventing self-criticism merely to move
/// the study workflow forward.
enum TurnSelfCriticismStatus: String, Codable, CaseIterable, Sendable {
    case unresolved
    case present
    case absent
    case uncertain
}

/// Deterministic readiness projection for the current Event Disclosure. The Planner may emit the
/// field for readability, but Swift canonicalizes it from the effective typed episode before
/// validation so it cannot become a second completion gate.
enum TurnEventDisclosureOutcome: String, Codable, CaseIterable, Sendable {
    case needsConcreteEpisode
    case needsBehaviorOrProcess
    case readyForTenderOrCard

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // LEGACY_DECODE_ONLY — the retired focus gate maps to a non-authoritative summary;
        // canonical Event Disclosure evidence still decides whether progression is legal.
        self = raw == "needsReflectionFocus"
            ? .readyForTenderOrCard
            : (Self(rawValue: raw) ?? .needsConcreteEpisode)
    }
}

enum TurnDisclosureReopenReason: String, Codable, CaseIterable, Sendable {
    case userCorrectedPreviousFact
    case userWithdrewPreviousAnswer
    case newContradictionDetected
}

/// Canonical current-protocol question functions. The legacy free-text purpose remains available
/// for saved-session export, but repetition and repair boundaries use this closed value.
enum TurnDisclosureQuestionPurpose: String, Codable, CaseIterable, Sendable {
    case identifyConcreteEpisode
    case clarifyBehavior
    case clarifyEventProcess

    var target: TurnDisclosureQuestionTarget {
        switch self {
        case .identifyConcreteEpisode: return .focalEvent
        case .clarifyBehavior: return .behavior
        case .clarifyEventProcess: return .eventProcess
        }
    }
}

/// A contextual cue becomes usable reflective background only through the person's own account
/// of whether and how it participated in the concrete situation. This aggregate relationship is
/// deliberately separate from legacy cue-level tracking assessments.
struct TurnContextRelationship: Codable, Equatable, Sendable {
    let relevance: TurnTrackingRelevance
    let userInterpretation: String?
}

/// Whether the disclosed facts currently support a concrete behavioral proposition or impact.
/// This is deliberately not a moral verdict: `present` means only that the person supplied
/// observable evidence, while `uncertain` preserves an unresolved distinction.
enum TurnEpisodeEvidenceStatus: String, Codable, CaseIterable, Sendable {
    case unresolved
    case present
    case absent
    case mixed
    case uncertain
}

/// Compact, cumulative structure built through natural disclosure. A single user answer may fill
/// several relationships; these fields must never become a checklist of mandatory visible
/// questions. They let later Tender and candid reflection distinguish facts from a global label
/// and preserve an unknown cause instead of filling it with a comforting explanation.
struct TurnEpisodeStructure: Codable, Equatable, Sendable {
    var concreteFacts: [String] = []
    var behaviorEvidenceStatus: TurnEpisodeEvidenceStatus = .unresolved
    var behaviorEvidence: [String] = []
    /// Whether the person has described how the focal event developed. A resolved value does not
    /// require a definite cause: `uncertain` preserves an explicit inability or refusal to know,
    /// while `absent` preserves a user-grounded account that no additional process is available.
    var eventProcessStatus: TurnEpisodeEvidenceStatus = .unresolved
    /// Grounded sequence or development of the focal event. This is distinct from what the user
    /// did: one answer may supply both, but each relation has one content source of its own.
    var eventProcess: [String] = []
    var possibleContributors: [String] = []
    var contextualConstraints: [String] = []
    var controllableParts: [String] = []
    var impactStatus: TurnEpisodeEvidenceStatus = .unresolved
    var impacts: [String] = []
    var keyUncertainty: String?

    /// Tracks which fields were actually present in an LLM-authored patch. Persisted semantic
    /// memory still encodes the complete structure, while a partial Planner update can now be
    /// merged without resetting previously confirmed facts to Codable defaults.
    private var providedFields: Set<CodingKeys> = Set(CodingKeys.allCases)

    init(
        concreteFacts: [String] = [],
        behaviorEvidenceStatus: TurnEpisodeEvidenceStatus = .unresolved,
        behaviorEvidence: [String] = [],
        eventProcessStatus: TurnEpisodeEvidenceStatus = .unresolved,
        eventProcess: [String] = [],
        possibleContributors: [String] = [],
        contextualConstraints: [String] = [],
        controllableParts: [String] = [],
        impactStatus: TurnEpisodeEvidenceStatus = .unresolved,
        impacts: [String] = [],
        keyUncertainty: String? = nil
    ) {
        self.concreteFacts = concreteFacts
        self.behaviorEvidenceStatus = behaviorEvidenceStatus
        self.behaviorEvidence = behaviorEvidence
        self.eventProcessStatus = eventProcessStatus
        self.eventProcess = eventProcess
        self.possibleContributors = possibleContributors
        self.contextualConstraints = contextualConstraints
        self.controllableParts = controllableParts
        self.impactStatus = impactStatus
        self.impacts = impacts
        self.keyUncertainty = keyUncertainty
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case concreteFacts, behaviorEvidenceStatus, behaviorEvidence, eventProcessStatus, eventProcess
        case possibleContributors
        case contextualConstraints, controllableParts, impactStatus, impacts, keyUncertainty
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        providedFields = Set(CodingKeys.allCases.filter { box.contains($0) })
        concreteFacts = (try? box.decode([String].self, forKey: .concreteFacts)) ?? []
        behaviorEvidenceStatus =
            (try? box.decode(TurnEpisodeEvidenceStatus.self, forKey: .behaviorEvidenceStatus))
            ?? .unresolved
        behaviorEvidence = (try? box.decode([String].self, forKey: .behaviorEvidence)) ?? []
        eventProcessStatus =
            (try? box.decode(TurnEpisodeEvidenceStatus.self, forKey: .eventProcessStatus))
            ?? .unresolved
        eventProcess = (try? box.decode([String].self, forKey: .eventProcess)) ?? []
        possibleContributors =
            (try? box.decode([String].self, forKey: .possibleContributors)) ?? []
        contextualConstraints =
            (try? box.decode([String].self, forKey: .contextualConstraints)) ?? []
        controllableParts =
            (try? box.decode([String].self, forKey: .controllableParts)) ?? []
        impactStatus =
            (try? box.decode(TurnEpisodeEvidenceStatus.self, forKey: .impactStatus))
            ?? .unresolved
        impacts = (try? box.decode([String].self, forKey: .impacts)) ?? []
        keyUncertainty = try? box.decodeIfPresent(String.self, forKey: .keyUncertainty)
    }

    /// Applies only fields explicitly supplied by the latest Planner. Event evidence is cumulative:
    /// a sparse turn patch contributes grounded items and cannot replace the focal event with a
    /// later detail. An explicit `absent` status is the only representation that clears a resolved
    /// relation. This is the single merge boundary for both persisted memory and candidate state.
    func merging(_ patch: TurnEpisodeStructure) -> TurnEpisodeStructure {
        var merged = self
        if patch.providedFields.contains(.concreteFacts) {
            merged.concreteFacts = Self.accumulating(
                existing: concreteFacts,
                additions: patch.concreteFacts
            )
        }
        if patch.providedFields.contains(.behaviorEvidenceStatus) {
            merged.behaviorEvidenceStatus = patch.behaviorEvidenceStatus
            if patch.behaviorEvidenceStatus == .absent {
                merged.behaviorEvidence = []
            }
        }
        if patch.providedFields.contains(.behaviorEvidence) {
            if patch.providedFields.contains(.behaviorEvidenceStatus),
               patch.behaviorEvidenceStatus == .absent {
                merged.behaviorEvidence = []
            } else {
                merged.behaviorEvidence = Self.accumulating(
                    existing: behaviorEvidence,
                    additions: patch.behaviorEvidence
                )
            }
        }
        if patch.providedFields.contains(.eventProcessStatus) {
            merged.eventProcessStatus = patch.eventProcessStatus
            if patch.eventProcessStatus == .absent {
                merged.eventProcess = []
            }
        }
        if patch.providedFields.contains(.eventProcess) {
            if patch.providedFields.contains(.eventProcessStatus),
               patch.eventProcessStatus == .absent {
                merged.eventProcess = []
            } else {
                merged.eventProcess = Self.accumulating(
                    existing: eventProcess,
                    additions: patch.eventProcess
                )
            }
        }
        if patch.providedFields.contains(.possibleContributors) {
            merged.possibleContributors = Self.accumulating(
                existing: possibleContributors,
                additions: patch.possibleContributors
            )
        }
        if patch.providedFields.contains(.contextualConstraints) {
            merged.contextualConstraints = Self.accumulating(
                existing: contextualConstraints,
                additions: patch.contextualConstraints
            )
        }
        if patch.providedFields.contains(.controllableParts) {
            merged.controllableParts = Self.accumulating(
                existing: controllableParts,
                additions: patch.controllableParts
            )
        }
        if patch.providedFields.contains(.impactStatus) {
            merged.impactStatus = patch.impactStatus
            if patch.impactStatus == .absent {
                merged.impacts = []
            }
        }
        if patch.providedFields.contains(.impacts) {
            if patch.providedFields.contains(.impactStatus),
               patch.impactStatus == .absent {
                merged.impacts = []
            } else {
                merged.impacts = Self.accumulating(
                    existing: impacts,
                    additions: patch.impacts
                )
            }
        }
        if patch.providedFields.contains(.keyUncertainty) {
            merged.keyUncertainty = patch.keyUncertainty
        }

        return merged.normalizingGroundedPresence()
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func accumulating(
        existing: [String],
        additions: [String]
    ) -> [String] {
        var seen = Set<String>()
        return (existing + additions).compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted else { return nil }
            return clean
        }
    }

    var hasBehaviorEvidenceContent: Bool {
        behaviorEvidence.contains(where: Self.nonempty)
    }

    var hasEventProcessContent: Bool {
        eventProcess.contains(where: Self.nonempty)
    }

    var hasImpactContent: Bool {
        impacts.contains(where: Self.nonempty)
    }

    /// Presence is redundant with grounded content and is therefore canonicalized before full
    /// protocol validation. Absence/uncertainty remain semantic claims and are never inferred.
    /// In particular, this function does not invent evidence or turn an empty `present` status
    /// into content.
    func normalizingGroundedPresence() -> TurnEpisodeStructure {
        var normalized = self
        if normalized.hasBehaviorEvidenceContent,
           normalized.behaviorEvidenceStatus == .unresolved {
            normalized.behaviorEvidenceStatus = .present
        }
        if normalized.hasEventProcessContent,
           normalized.eventProcessStatus == .unresolved {
            normalized.eventProcessStatus = .present
        }
        if normalized.hasImpactContent,
           normalized.impactStatus == .unresolved {
            normalized.impactStatus = .present
        }
        normalized.providedFields = Set(CodingKeys.allCases)
        return normalized
    }

    /// Saved sessions created before `eventProcess` had its own content field used the other
    /// episode arrays as the only process representation. Migrate that representation only at the
    /// persisted-session decode boundary; Planner patches never call this compatibility path.
    mutating func migrateLegacyEventProcessContentIfNeeded() {
        guard !providedFields.contains(.eventProcess),
              [.present, .mixed].contains(eventProcessStatus),
              !hasEventProcessContent else { return }
        let legacyContent = possibleContributors
            + contextualConstraints
            + controllableParts
            + behaviorEvidence
        eventProcess = legacyContent.filter(Self.nonempty)
        providedFields.insert(.eventProcess)
    }

    /// Field names only, for privacy-preserving protocol diagnostics and repair contracts.
    var explicitlyProvidedFieldNames: [String] {
        providedFields.map(\.rawValue).sorted()
    }

    static func == (lhs: TurnEpisodeStructure, rhs: TurnEpisodeStructure) -> Bool {
        lhs.concreteFacts == rhs.concreteFacts
            && lhs.behaviorEvidenceStatus == rhs.behaviorEvidenceStatus
            && lhs.behaviorEvidence == rhs.behaviorEvidence
            && lhs.eventProcessStatus == rhs.eventProcessStatus
            && lhs.eventProcess == rhs.eventProcess
            && lhs.possibleContributors == rhs.possibleContributors
            && lhs.contextualConstraints == rhs.contextualConstraints
            && lhs.controllableParts == rhs.controllableParts
            && lhs.impactStatus == rhs.impactStatus
            && lhs.impacts == rhs.impacts
            && lhs.keyUncertainty == rhs.keyUncertainty
    }
}

enum TurnPracticeKind: String, Codable, CaseIterable, Sendable {
    case care
    case repair
    case protect
    case change
    case noAction
}

enum TurnPracticeProposalStatus: String, Codable, Sendable {
    case pendingConfirmation
    case confirmed
}

enum TurnPracticeProposalSource: String, Codable, Sendable {
    case assistantProposed
    case userRevised
}

/// The only current representation of an actionable Optional Action proposal. Required fields
/// are deliberately non-optional so a partial proposal cannot enter current session memory.
struct TurnPracticeProposal: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: TurnPracticeKind
    let content: String
    let basis: String
    let status: TurnPracticeProposalStatus
    let source: TurnPracticeProposalSource

    init(
        id: String,
        kind: TurnPracticeKind,
        content: String,
        basis: String,
        status: TurnPracticeProposalStatus,
        source: TurnPracticeProposalSource = .assistantProposed
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.basis = basis
        self.status = status
        self.source = source
    }
}

/// One application-owned transaction from reflection (or a legacy accepted narrative) to either
/// one proposal or noAction.
/// `proposal == nil && noActionReason == nil` is the durable awaiting-proposal state.
struct TurnPracticeTransition: Codable, Equatable, Sendable {
    let transactionID: String
    let narrativeReferenceID: String?
    var proposal: TurnPracticeProposal?
    var noActionReason: TurnNoActionReason?
}

/// LEGACY_DECODE_ONLY — MUST NOT PARTICIPATE IN CURRENT PRACTICE PROTOCOL.
/// Historical sessions stored a selectable array whose evidence basis was optional.
struct LegacyPracticeOptionDTO: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: TurnPracticeKind
    let title: String
    let instruction: String
    let rationale: String
    let basis: String?
}

/// `noAction` is an evidence-bounded practice outcome, not a convenient way for the Planner to
/// skip proposing support. Swift validates this closed reason code while the semantic Critic
/// checks whether the conversation actually supports it.
enum TurnNoActionReason: String, Codable, CaseIterable, Sendable {
    case userDeclined
    case userNotReady
    case insufficientSupportedMaterial
}

/// The protocol-visible purpose of one assistant reply. Unlike the free-form writer guidance,
/// this value is deliberately small and closed so Swift can prevent a later workflow function
/// (for example practice or completion) from leaking into an earlier stage.
enum TurnReplyIntent: String, Codable, CaseIterable, Sendable {
    case exploreContext
    case presentTrackingContext
    case checkTrackingRelationship
    case inviteCardConsent
    case acknowledgeCardConsent
    case acknowledgeCardDecline
    case inviteCardObservation
    case developCardImage
    case inviteCardConnection
    /// Deepens a concrete image-to-life mapping until it contains one user-authored tension,
    /// evaluative standard, contrast, or uncertainty. This is not a second observation scaffold.
    case deepenCardConnection
    case authorizeCardGuidance
    case presentCardReading
    case directCandidReflection
    case presentFinalNarrative
    case requestNarrativeConfirmation
    case reviseFinalNarrative
    case suggestPractice
    case revisePractice
    case completeConversation
    case safetySupport
}

/// “Yes” is meaningful only in relation to the immediately pending confirmation. Keeping that
/// target typed prevents a tracking-related confirmation from being treated as acceptance of a
/// Tender summary, card mapping, final narrative, or practice.
enum TurnConfirmationTarget: String, Codable, CaseIterable, Sendable {
    case trackingRelationship
    case cardConsent
    /// A pre-guidance candidate that can become a complete userAccepted/userRevised connection.
    /// This is deliberately distinct from `cardMapping`, which negotiates the later card reading.
    case cardRealityConnection
    case cardMapping
    case finalNarrative
    case practice
}

/// What the latest user reply did to the confirmation request that was already visible. This is
/// deliberately separate from `TurnNextPrompt`, which describes what the new assistant reply will
/// ask next.
enum TurnConfirmationDecision: String, Codable, CaseIterable, Sendable {
    case related, partlyRelated, unrelated, uncertain
    case accepted, revised, rejected, unclear, declined
}

struct TurnResolvedConfirmation: Codable, Equatable, Sendable {
    let target: TurnConfirmationTarget
    let decision: TurnConfirmationDecision
    /// Opaque application-owned reference copied from the currently pending confirmation.
    /// Legacy sessions may have no reference ID, so this remains optional during migration.
    let referenceID: String?

    init(
        target: TurnConfirmationTarget,
        decision: TurnConfirmationDecision,
        referenceID: String? = nil
    ) {
        self.target = target
        self.decision = decision
        self.referenceID = referenceID
    }
}

enum TurnNextPromptKind: String, Codable, CaseIterable, Sendable {
    case none
    case openQuestion
    case confirmationRequest
}

/// The single semantic relationship an ordinary contextual-disclosure question is allowed to
/// clarify. This remains separate from free-form wording so Swift can prevent a completed event
/// process from being reopened under a newly phrased purpose.
enum TurnDisclosureQuestionTarget: String, Codable, CaseIterable, Sendable {
    case focalEvent
    case behavior
    case eventProcess
    case contextRelationship
}

/// The interaction the newly generated assistant reply establishes for the following user turn.
/// Swift validates only this structural contract; the LLM owns the semantic purpose and focus.
struct TurnNextPrompt: Codable, Equatable, Sendable {
    let kind: TurnNextPromptKind
    let purpose: String?
    let focus: String?
    let disclosurePurpose: TurnDisclosureQuestionPurpose?
    let disclosureTarget: TurnDisclosureQuestionTarget?
    let disclosureReopenReason: TurnDisclosureReopenReason?
    let target: TurnConfirmationTarget?
    /// Assigned by Swift when a new confirmation request is committed. A Planner must copy the
    /// current value when resolving it, but does not invent an ID for a new prompt.
    let referenceID: String?

    init(
        kind: TurnNextPromptKind,
        purpose: String?,
        focus: String?,
        disclosurePurpose: TurnDisclosureQuestionPurpose? = nil,
        disclosureTarget: TurnDisclosureQuestionTarget? = nil,
        disclosureReopenReason: TurnDisclosureReopenReason? = nil,
        target: TurnConfirmationTarget?,
        referenceID: String?
    ) {
        self.kind = kind
        self.purpose = purpose
        self.focus = focus
        self.disclosurePurpose = disclosurePurpose
        self.disclosureTarget = disclosureTarget
        self.disclosureReopenReason = disclosureReopenReason
        self.target = target
        self.referenceID = referenceID
    }

    private enum CodingKeys: String, CodingKey {
        case kind, purpose, focus, disclosurePurpose, disclosureTarget
        case disclosureReopenReason, target, referenceID
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = try box.decode(TurnNextPromptKind.self, forKey: .kind)
        purpose = try box.decodeIfPresent(String.self, forKey: .purpose)
        focus = try box.decodeIfPresent(String.self, forKey: .focus)
        disclosurePurpose = try? box.decodeIfPresent(
            TurnDisclosureQuestionPurpose.self,
            forKey: .disclosurePurpose
        )
        disclosureReopenReason = try? box.decodeIfPresent(
            TurnDisclosureReopenReason.self,
            forKey: .disclosureReopenReason
        )
        target = try box.decodeIfPresent(TurnConfirmationTarget.self, forKey: .target)
        referenceID = try box.decodeIfPresent(String.self, forKey: .referenceID)
        do {
            disclosureTarget = try box.decodeIfPresent(
                TurnDisclosureQuestionTarget.self,
                forKey: .disclosureTarget
            )
        } catch {
            // `disclosureTarget` is an optional refinement used only by contextual disclosure.
            // A stray value in a card/direct turn must not make the whole Planner object
            // undecodable. In contextual disclosure this becomes nil and the typed validator
            // still requests the exact required target, preserving the hard progression rule.
            disclosureTarget = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind, forKey: .kind)
        // Preserve the existing wire shape: Planner contracts carry explicit nulls for fields
        // outside the active tagged shape.
        try box.encode(purpose, forKey: .purpose)
        try box.encode(focus, forKey: .focus)
        try box.encode(disclosurePurpose, forKey: .disclosurePurpose)
        try box.encode(disclosureTarget, forKey: .disclosureTarget)
        try box.encode(disclosureReopenReason, forKey: .disclosureReopenReason)
        try box.encode(target, forKey: .target)
        try box.encode(referenceID, forKey: .referenceID)
    }

    static let none = TurnNextPrompt(
        kind: .none,
        purpose: nil,
        focus: nil,
        disclosurePurpose: nil,
        disclosureTarget: nil,
        disclosureReopenReason: nil,
        target: nil,
        referenceID: nil
    )

    static func openQuestion(
        purpose: String,
        focus: String,
        disclosurePurpose: TurnDisclosureQuestionPurpose? = nil,
        disclosureTarget: TurnDisclosureQuestionTarget? = nil,
        disclosureReopenReason: TurnDisclosureReopenReason? = nil
    ) -> TurnNextPrompt {
        TurnNextPrompt(
            kind: .openQuestion,
            purpose: purpose,
            focus: focus,
            disclosurePurpose: disclosurePurpose,
            disclosureTarget: disclosureTarget,
            disclosureReopenReason: disclosureReopenReason,
            target: nil,
            referenceID: nil
        )
    }

    static func confirmationRequest(
        target: TurnConfirmationTarget,
        referenceID: String? = nil
    ) -> TurnNextPrompt {
        TurnNextPrompt(
            kind: .confirmationRequest,
            purpose: nil,
            focus: nil,
            disclosurePurpose: nil,
            disclosureTarget: nil,
            disclosureReopenReason: nil,
            target: target,
            referenceID: referenceID
        )
    }

    func assigningReferenceID(_ value: String) -> TurnNextPrompt {
        TurnNextPrompt(
            kind: kind,
            purpose: purpose,
            focus: focus,
            disclosurePurpose: disclosurePurpose,
            disclosureTarget: disclosureTarget,
            disclosureReopenReason: disclosureReopenReason,
            target: target,
            referenceID: value
        )
    }
}

struct TurnTrackingAssessment: Codable, Equatable, Sendable {
    let cueID: String
    let relevance: TurnTrackingRelevance
    /// This is the person's model-extracted interpretation, not a causal conclusion.
    let userInterpretation: String?
}

/// Provenance of the final user-grounded image-to-reality mapping. The model chooses this typed
/// value from the latest response; Swift never infers it from words or from a candidate reading.
enum TurnCardRealityMappingSource: String, Codable, CaseIterable, Sendable {
    case userAuthored
    case userAccepted
    case userRevised
}

/// The persisted card-connection interaction boundary supplied to the Planner. It is derived
/// from the current session's pending candidate and confirmation prompt; the Planner cannot select
/// or rewrite it.
enum CardConnectionInteractionState: String, Codable, CaseIterable, Sendable {
    case openExploration
    case awaitingCandidateResolution
}

enum TurnCardRealityConnectionStatus: String, Codable, CaseIterable, Sendable {
    case confirmed
}

/// The sole authoritative image-to-reality connection for current protocol sessions. A connection
/// is either absent or complete; the legacy scalar fields below are compatibility mirrors only.
struct TurnCardRealityConnection: Codable, Equatable, Sendable {
    let imageRelation: String
    let realityMapping: String
    let source: TurnCardRealityMappingSource
    let status: TurnCardRealityConnectionStatus

    init(
        imageRelation: String,
        realityMapping: String,
        source: TurnCardRealityMappingSource,
        status: TurnCardRealityConnectionStatus = .confirmed
    ) {
        self.imageRelation = imageRelation
        self.realityMapping = realityMapping
        self.source = source
        self.status = status
    }

    var normalizedConfirmed: TurnCardRealityConnection? {
        let image = imageRelation.trimmingCharacters(in: .whitespacesAndNewlines)
        let reality = realityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == .confirmed, !image.isEmpty, !reality.isEmpty else { return nil }
        return TurnCardRealityConnection(
            imageRelation: image,
            realityMapping: reality,
            source: source,
            status: .confirmed
        )
    }
}

/// Mutually exclusive Planner outcomes for one card-reality turn. Connection objects are carried
/// only by the two outcomes that create or revise a canonical user-grounded mapping. Candidate
/// acceptance/rejection is resolved deterministically from persisted pending state.
enum CardConnectionTurnOutcomeKind: String, Codable, CaseIterable, Sendable {
    case userAuthoredConnection
    case connectionStillUnclear
    case candidateAccepted
    case candidateRevised
    case candidateRejected
}

struct CardConnectionTurnOutcome: Codable, Equatable, Sendable {
    let kind: CardConnectionTurnOutcomeKind
    let connection: TurnCardRealityConnection?

    init(
        kind: CardConnectionTurnOutcomeKind,
        connection: TurnCardRealityConnection? = nil
    ) throws {
        self.kind = kind
        self.connection = connection
        try Self.validate(kind: kind, connection: connection)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case connection
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try box.decode(CardConnectionTurnOutcomeKind.self, forKey: .kind)
        let connection = try box.decodeIfPresent(
            TurnCardRealityConnection.self,
            forKey: .connection
        )
        try Self.validate(kind: kind, connection: connection)
        self.kind = kind
        self.connection = connection
    }

    private static func validate(
        kind: CardConnectionTurnOutcomeKind,
        connection: TurnCardRealityConnection?
    ) throws {
        switch kind {
        case .userAuthoredConnection:
            guard connection?.normalizedConfirmed?.source == .userAuthored else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: "userAuthoredConnection requires userAuthored connection"
                    )
                )
            }
        case .candidateRevised:
            guard connection?.normalizedConfirmed?.source == .userRevised else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: "candidateRevised requires userRevised connection"
                    )
                )
            }
        case .connectionStillUnclear, .candidateAccepted, .candidateRejected:
            guard connection == nil else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: [],
                        debugDescription: "this card connection outcome cannot carry a connection"
                    )
                )
            }
        }
    }
}

/// A bounded, pre-guidance candidate. It is not user evidence and never unlocks guidance until a
/// typed acceptance or revision promotes it into `TurnCardRealityConnection`.
struct PendingCardRealityConnection: Codable, Equatable, Sendable {
    let id: UUID
    let imageRelation: String
    let candidateRealityMapping: String

    init(
        id: UUID = UUID(),
        imageRelation: String,
        candidateRealityMapping: String
    ) {
        self.id = id
        self.imageRelation = imageRelation
        self.candidateRealityMapping = candidateRealityMapping
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case imageRelation
        case candidateRealityMapping
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        // Candidate identity is application-owned. Older responses may still carry an ID, but a
        // current Planner only needs to provide the two semantic strings.
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imageRelation = try box.decode(String.self, forKey: .imageRelation)
        candidateRealityMapping = try box.decode(
            String.self,
            forKey: .candidateRealityMapping
        )
    }

    var isStructurallyComplete: Bool {
        !imageRelation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidateRealityMapping.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Planner-owned semantic outcome. Swift updates the attempt counter from this closed result and
/// never derives it from Chinese wording or from how many questions the assistant happened to ask.
enum TurnCardConnectionOutcome: String, Codable, CaseIterable, Sendable {
    case connectionConfirmed
    case partialConnection
    case noConnectionFound
    case candidateRejected
    case userRequestedSkip
}

/// The functional emphasis of post-connection reflection. Tender is the safe default; Fierce is
/// available only when the Planner can point to user-grounded conduct, impact, and a bounded
/// caring direction. These values are private protocol metadata and never user-visible labels.
enum TurnReflectionMode: String, Codable, CaseIterable, Sendable {
    case tender
    case fierce
}

/// The single persisted semantic phase inside the existing `directReflection` workflow boundary.
/// Swift writes this value from the authorized semantic operation; `nextPrompt` remains a Writer
/// contract and never participates in phase selection.
enum TurnReflectionPhase: String, Codable, CaseIterable, Sendable {
    case exploratory
    case tender
    case fierce
    case synthesis
}

/// The one typed semantic operation performed by a reflection turn. Free-form question purposes
/// may help the Writer phrase the turn, but only this closed value participates in capability
/// validation. The catalogue is intentionally small: four Tender-only operations, five bounded
/// Fierce operations, and one shared synthesis operation.
enum TurnReflectionAction: String, Codable, CaseIterable, Sendable {
    case acknowledgeExperience
    case distinguishFactFromPrediction
    case softenGlobalSelfJudgment
    case connectCommonHumanity
    case acknowledgeBehaviorImpact
    case clarifyBoundaryOrNeed
    case identifyRepairDirection
    case identifyProtectionDirection
    case identifyChangeDirection
    case synthesizeUnderstanding

    var isTenderCompatible: Bool {
        switch self {
        case .acknowledgeExperience,
             .distinguishFactFromPrediction,
             .softenGlobalSelfJudgment,
             .connectCommonHumanity,
             .synthesizeUnderstanding:
            return true
        case .acknowledgeBehaviorImpact,
             .clarifyBoundaryOrNeed,
             .identifyRepairDirection,
             .identifyProtectionDirection,
             .identifyChangeDirection:
            return false
        }
    }

    var requiredFierceDirection: TurnFierceDirection? {
        switch self {
        case .identifyRepairDirection:
            return .repair
        case .identifyProtectionDirection:
            return .protect
        case .identifyChangeDirection:
            return .change
        default:
            return nil
        }
    }
}

/// Self-compassion dimensions are selectable lenses, not sequential stages or questionnaire
/// slots. A reflection uses only the one or two dimensions that add meaning to this episode.
enum TurnSelfCompassionDimension: String, Codable, CaseIterable, Hashable, Sendable {
    case selfKindness
    case commonHumanity
    case mindfulness
}

/// A Fierce direction is motivated by care for the person, another person, or the relationship.
/// It never represents punishment, a global character judgment, or evidence inferred from a card.
enum TurnFierceDirection: String, Codable, CaseIterable, Sendable {
    case repair
    case protect
    case change
}

/// Typed provenance lets Swift enforce that a card connection cannot be the sole basis for
/// responsibility. It does not ask Swift to interpret the evidence text.
enum TurnReflectionEvidenceSource: String, Codable, CaseIterable, Sendable {
    case episode
    case latestUserAnswer
    case cardRealityConnection
    case confirmedContext
}

struct TurnReflectionEvidence: Codable, Equatable, Sendable {
    let source: TurnReflectionEvidenceSource
    let content: String
}

struct TurnFierceEvidence: Codable, Equatable, Sendable {
    let behavior: String
    let impact: String
    let direction: TurnFierceDirection

    /// Compatibility predicate for legacy protocols that stored Fierce grounding inside these two
    /// fields. Current-v5 instead validates the Planner direction together with the canonical
    /// `TurnReflectionFrame.evidenceBasis`; it does not require current-turn history duplication.
    var hasGroundedBehaviorOrImpact: Bool {
        !behavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !impact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Legacy protocol validation still expects both fields. Current v5 uses the narrower
    /// provenance boundary above rather than treating completeness as semantic sufficiency.
    var isStructurallyComplete: Bool {
        !behavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !impact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The sole current-protocol truth source for the mode and semantic delta of post-connection
/// reflection. `replyIntent` and `nextPrompt` continue to describe whether this turn asks a
/// question or advances; duplicating that move here would create a second workflow authority.
struct TurnReflectionFrame: Codable, Equatable, Sendable {
    let mode: TurnReflectionMode
    let action: TurnReflectionAction
    let evidenceBasis: [TurnReflectionEvidence]
    let dimensions: [TurnSelfCompassionDimension]
    let reflectionDelta: String
    let fierceEvidence: TurnFierceEvidence?
    /// Decode provenance only. Protocol-4 sessions predate `action`; mapping them to synthesis
    /// keeps their saved understanding readable. A current Planner payload using that omission is
    /// rejected, so this flag never becomes a second semantic truth source.
    let actionWasInferredForLegacyDecode: Bool

    init(
        mode: TurnReflectionMode,
        action: TurnReflectionAction,
        evidenceBasis: [TurnReflectionEvidence],
        dimensions: [TurnSelfCompassionDimension],
        reflectionDelta: String,
        fierceEvidence: TurnFierceEvidence?
    ) {
        self.mode = mode
        self.action = action
        self.evidenceBasis = evidenceBasis
        self.dimensions = dimensions
        self.reflectionDelta = reflectionDelta
        self.fierceEvidence = fierceEvidence
        actionWasInferredForLegacyDecode = false
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case action
        case evidenceBasis
        case dimensions
        case reflectionDelta
        case fierceEvidence
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        mode = try box.decode(TurnReflectionMode.self, forKey: .mode)
        if let decodedAction = try box.decodeIfPresent(
            TurnReflectionAction.self,
            forKey: .action
        ) {
            action = decodedAction
            actionWasInferredForLegacyDecode = false
        } else {
            action = .synthesizeUnderstanding
            actionWasInferredForLegacyDecode = true
        }
        // Current-v5 may omit Planner-redundant provenance at the transport boundary. Swift
        // deterministically restores already committed lineage before authorization; semantic
        // frame fields such as action and reflectionDelta remain required above and below.
        evidenceBasis = try box.decodeIfPresent(
            [TurnReflectionEvidence].self,
            forKey: .evidenceBasis
        ) ?? []
        dimensions = try box.decode(
            [TurnSelfCompassionDimension].self,
            forKey: .dimensions
        )
        reflectionDelta = try box.decode(String.self, forKey: .reflectionDelta)
        fierceEvidence = try box.decodeIfPresent(TurnFierceEvidence.self, forKey: .fierceEvidence)
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(mode, forKey: .mode)
        try box.encode(action, forKey: .action)
        try box.encode(evidenceBasis, forKey: .evidenceBasis)
        try box.encode(dimensions, forKey: .dimensions)
        try box.encode(reflectionDelta, forKey: .reflectionDelta)
        try box.encodeIfPresent(fierceEvidence, forKey: .fierceEvidence)
    }

    var hasNonemptyEvidence: Bool {
        evidenceBasis.contains {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var hasRealityEvidence: Bool {
        evidenceBasis.contains {
            [.episode, .latestUserAnswer].contains($0.source)
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var hasUsableDimensions: Bool {
        (1...2).contains(Set(dimensions).count)
            && Set(dimensions).count == dimensions.count
    }

    var hasReflectionDelta: Bool {
        !reflectionDelta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LegacySavedCardRealityConnectionMigration: Equatable, Sendable {
    case none
    case migrated
    case incomplete
    case canonicalConflictIgnored
}

/// One shared resolver used by normalization, validation, capabilities, recovery, and card-context
/// projection. It combines typed state only and never interprets the person's language.
enum TurnCardRealityConnectionResolver {
    static func effective(
        memory: TurnSemanticMemory,
        update: TurnSemanticMemoryUpdate? = nil,
        resolution: TurnResolvedConfirmation? = nil
    ) -> TurnCardRealityConnection? {
        if update?.clearCardRealityConnection == true { return nil }

        if let proposed = update?.cardRealityConnection {
            return proposed.normalizedConfirmed
        }

        if let resolution,
           resolution.target == .cardRealityConnection,
           memory.nextPrompt?.kind == .confirmationRequest,
           memory.nextPrompt?.target == .cardRealityConnection,
           let pending = memory.pendingCardRealityConnection,
           pending.isStructurallyComplete,
           (memory.nextPrompt?.referenceID == nil
            || memory.nextPrompt?.referenceID == pending.id.uuidString) {
            switch resolution.decision {
            case .accepted:
                return TurnCardRealityConnection(
                    imageRelation: pending.imageRelation,
                    realityMapping: pending.candidateRealityMapping,
                    source: .userAccepted
                ).normalizedConfirmed
            case .revised:
                return update?.cardRealityConnection?.normalizedConfirmed
            case .rejected, .declined, .unclear, .related, .partlyRelated, .unrelated, .uncertain:
                return nil
            }
        }

        return memory.cardRealityConnection?.normalizedConfirmed
    }
}

/// Typed evidence that the person has described visible content in the card image.
/// Populated by the Planner from the person's answer; Swift reads it, never interprets it.
struct CardObservationEvidence: Codable, Equatable, Sendable {
    /// User-described visible elements, people, objects, or scene components.
    var userDescribedElements: [String] = []

    var hasContent: Bool {
        userDescribedElements.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Typed evidence that the person has described a development relation in the image:
/// what may happen next, how roles may act, what choice or change is anticipated.
/// Populated by the Planner; Swift reads it, never interprets it.
struct CardDevelopmentEvidence: Codable, Equatable, Sendable {
    var actorsOrElements: [String] = []
    /// The element, uncertainty, tension, or choice the person themselves selected as worth
    /// staying with. This is a semantic judgment from the Planner, never a keyword match.
    var projectiveFocus: String?
    var relationOrAction: String?
    var anticipatedChangeOrChoice: String?

    init(
        actorsOrElements: [String] = [],
        projectiveFocus: String? = nil,
        relationOrAction: String? = nil,
        anticipatedChangeOrChoice: String? = nil
    ) {
        self.actorsOrElements = actorsOrElements
        self.projectiveFocus = projectiveFocus
        self.relationOrAction = relationOrAction
        self.anticipatedChangeOrChoice = anticipatedChangeOrChoice
    }

    private enum CodingKeys: String, CodingKey {
        case actorsOrElements
        case projectiveFocus
        case relationOrAction
        case anticipatedChangeOrChoice
    }

    /// Planner development evidence is a sparse cross-turn patch. Missing actors mean "reuse the
    /// already committed actors", not an invalid payload or a request to clear them.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        actorsOrElements = try box.decodeIfPresent(
            [String].self,
            forKey: .actorsOrElements
        ) ?? []
        projectiveFocus = try box.decodeIfPresent(String.self, forKey: .projectiveFocus)
        relationOrAction = try box.decodeIfPresent(String.self, forKey: .relationOrAction)
        anticipatedChangeOrChoice = try box.decodeIfPresent(
            String.self,
            forKey: .anticipatedChangeOrChoice
        )
    }

    var hasContent: Bool {
        actorsOrElements.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || projectiveFocus?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || relationOrAction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || anticipatedChangeOrChoice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Development evidence may arrive across two natural turns. Preserve a user-authored
    /// relationship while adding its later continuation, without creating a parallel lifecycle.
    func merging(_ patch: CardDevelopmentEvidence) -> CardDevelopmentEvidence {
        func nonempty(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        var merged = self
        for element in patch.actorsOrElements {
            let clean = element.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !merged.actorsOrElements.contains(clean) {
                merged.actorsOrElements.append(clean)
            }
        }
        if let relation = nonempty(patch.relationOrAction) {
            merged.relationOrAction = relation
        }
        if let focus = nonempty(patch.projectiveFocus) {
            merged.projectiveFocus = focus
        }
        if let continuation = nonempty(patch.anticipatedChangeOrChoice) {
            merged.anticipatedChangeOrChoice = continuation
        }
        return merged
    }
}

/// LLM-owned conversational memory. It records what has been understood and which question
/// functions have already been completed, while protocol state and local permissions remain
/// outside this structure.
struct TurnSemanticMemory: Codable, Equatable, Sendable {
    var situationUnderstanding = ""
    var answeredQuestionPurposes: [String] = []
    var receivedDisclosureQuestionPurposes: [TurnDisclosureQuestionPurpose] = []
    var eventDisclosureOutcome: TurnEventDisclosureOutcome = .needsConcreteEpisode
    var selfCriticismStatus: TurnSelfCriticismStatus = .unresolved
    /// The person's proposition in compact form, not a clinician- or model-authored label.
    var selfCriticalStatement: String?
    /// The user-grounded relationship between reported reality and the self-evaluation. This is
    /// the actual reflection object: it records how a fact is being taken to mean something about
    /// the self, or that this connection remains uncertain, without supplying a hidden motive.
    var selfCriticismLink: String?
    /// Evidence structure underlying the self-evaluation. It contains only user-authored facts,
    /// constraints, possibilities, controllable parts, impacts, and explicit uncertainty.
    var episodeStructure: TurnEpisodeStructure?
    /// The person's assessment of whether and how the optional contextual cue mattered.
    var contextRelationship: TurnContextRelationship?
    /// The single current representation of a pending conversational interaction.
    var nextPrompt: TurnNextPrompt?
    var trackingAssessments: [TurnTrackingAssessment] = []
    var cardRealityConnection: TurnCardRealityConnection?
    var pendingCardRealityConnection: PendingCardRealityConnection?
    var cardImageRelation: String?
    var cardRealityMapping: String?
    var cardRealityMappingSource: TurnCardRealityMappingSource?
    /// The user-authored or user-confirmed distinction that makes the mapping interpretively
    /// richer than a surface similarity. Catalogue meanings never enter this field.
    var cardInterpretiveTension: String?
    var cardNegotiatedMeaning: String?
    /// Typed evidence that the person described visible content in the card image.
    /// Nil for old sessions; populated by current-protocol Planner semantic patches.
    var cardObservationEvidence: CardObservationEvidence?
    /// Typed evidence that the person described a development relation in the image.
    /// Nil for old sessions; populated by current-protocol Planner semantic patches.
    var cardDevelopmentEvidence: CardDevelopmentEvidence?
    /// Set to a timestamp when a candidate bridge was resolved (accepted, revised, or rejected).
    /// Nil before the first candidate resolution. Used to derive `candidateBridgeOfferedOrResolved`.
    var candidateBridgeResolvedAt: Date?
    /// Canonical Tender/Fierce/synthesis content. It remains nil throughout Exploration; absence
    /// never asks Swift to search the dialogue for responsibility or compassion keywords.
    var reflectionFrame: TurnReflectionFrame?
    /// Canonical current-protocol substate within `directReflection`. Current turns update this
    /// only through the Swift projector. Older saved sessions infer it once while decoding.
    var reflectionPhase: TurnReflectionPhase
    /// User-explicit corrections of assistant interpretations. These are semantic propositions,
    /// not keywords; later Planner turns must treat them as unavailable evidence.
    var invalidatedInterpretations: [String]
    /// LEGACY_DECODE_ONLY — retained so earlier research sessions remain readable. Current prompts,
    /// capability decisions, and stage validation never read or write these as truth sources.
    var candidUnderstanding: String?
    var fierceUnderstanding: String?
    var finalNarrative: String?
    /// The sole current Optional Action truth source.
    var practiceTransition: TurnPracticeTransition?

    var effectiveReflectionMode: TurnReflectionMode {
        reflectionFrame?.mode ?? .tender
    }

    init(
        situationUnderstanding: String = "",
        answeredQuestionPurposes: [String] = [],
        receivedDisclosureQuestionPurposes: [TurnDisclosureQuestionPurpose] = [],
        eventDisclosureOutcome: TurnEventDisclosureOutcome = .needsConcreteEpisode,
        selfCriticismStatus: TurnSelfCriticismStatus = .unresolved,
        selfCriticalStatement: String? = nil,
        selfCriticismLink: String? = nil,
        episodeStructure: TurnEpisodeStructure? = nil,
        contextRelationship: TurnContextRelationship? = nil,
        nextPrompt: TurnNextPrompt? = nil,
        trackingAssessments: [TurnTrackingAssessment] = [],
        cardRealityConnection: TurnCardRealityConnection? = nil,
        pendingCardRealityConnection: PendingCardRealityConnection? = nil,
        cardImageRelation: String? = nil,
        cardRealityMapping: String? = nil,
        cardRealityMappingSource: TurnCardRealityMappingSource? = nil,
        cardInterpretiveTension: String? = nil,
        cardNegotiatedMeaning: String? = nil,
        reflectionFrame: TurnReflectionFrame? = nil,
        reflectionPhase: TurnReflectionPhase? = nil,
        invalidatedInterpretations: [String] = [],
        candidUnderstanding: String? = nil,
        fierceUnderstanding: String? = nil,
        finalNarrative: String? = nil,
        practiceTransition: TurnPracticeTransition? = nil
    ) {
        self.situationUnderstanding = situationUnderstanding
        self.answeredQuestionPurposes = answeredQuestionPurposes
        self.receivedDisclosureQuestionPurposes = receivedDisclosureQuestionPurposes
        self.eventDisclosureOutcome = eventDisclosureOutcome
        self.selfCriticismStatus = selfCriticismStatus
        self.selfCriticalStatement = selfCriticalStatement
        self.selfCriticismLink = selfCriticismLink
        self.episodeStructure = episodeStructure?.normalizingGroundedPresence()
        self.contextRelationship = contextRelationship
        self.nextPrompt = nextPrompt
        self.trackingAssessments = trackingAssessments
        let canonical = cardRealityConnection?.normalizedConfirmed
        self.cardRealityConnection = canonical
        self.pendingCardRealityConnection = pendingCardRealityConnection
        self.cardImageRelation = canonical?.imageRelation ?? cardImageRelation
        self.cardRealityMapping = canonical?.realityMapping ?? cardRealityMapping
        self.cardRealityMappingSource = canonical?.source ?? cardRealityMappingSource
        self.cardInterpretiveTension = cardInterpretiveTension
        self.cardNegotiatedMeaning = cardNegotiatedMeaning
        self.reflectionFrame = reflectionFrame
        self.reflectionPhase = reflectionPhase ?? Self.inferredReflectionPhase(from: reflectionFrame)
        self.invalidatedInterpretations = invalidatedInterpretations
        self.candidUnderstanding = candidUnderstanding
        self.fierceUnderstanding = fierceUnderstanding
        self.finalNarrative = finalNarrative
        self.practiceTransition = practiceTransition
    }

    private enum CodingKeys: String, CodingKey {
        case situationUnderstanding
        case answeredQuestionPurposes
        case receivedDisclosureQuestionPurposes
        case eventDisclosureOutcome
        case selfCriticismStatus
        case selfCriticalStatement
        case selfCriticismLink
        case episodeStructure
        case contextRelationship
        case nextPrompt
        case trackingAssessments
        case cardRealityConnection
        case pendingCardRealityConnection
        case cardImageRelation
        case cardRealityMapping
        case cardRealityMappingSource
        case cardInterpretiveTension
        case cardNegotiatedMeaning
        case cardObservationEvidence
        case cardDevelopmentEvidence
        case candidateBridgeResolvedAt
        case reflectionFrame
        case reflectionPhase
        case invalidatedInterpretations
        case candidUnderstanding
        case fierceUnderstanding
        case finalNarrative
        case practiceTransition
    }

    /// LEGACY_DECODE_ONLY — MUST NOT PARTICIPATE IN CURRENT PROTOCOL.
    /// These keys existed before `nextPrompt` became the canonical interaction object. They are
    /// read once while restoring a saved session and are never stored in current semantic memory.
    private enum LegacyInteractionCodingKeys: String, CodingKey {
        case pendingQuestionPurpose
        case pendingConfirmationTarget
    }

    /// LEGACY_DECODE_ONLY — MUST NOT PARTICIPATE IN CURRENT PRACTICE PROTOCOL.
    private enum LegacyPracticeCodingKeys: String, CodingKey {
        case practiceOptions
        case practiceKind
        case selectedPractice
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        situationUnderstanding =
            (try? box.decode(String.self, forKey: .situationUnderstanding)) ?? ""
        answeredQuestionPurposes =
            (try? box.decode([String].self, forKey: .answeredQuestionPurposes)) ?? []
        receivedDisclosureQuestionPurposes =
            (try? box.decode(
                [TurnDisclosureQuestionPurpose].self,
                forKey: .receivedDisclosureQuestionPurposes
            )) ?? []
        eventDisclosureOutcome =
            (try? box.decode(
                TurnEventDisclosureOutcome.self,
                forKey: .eventDisclosureOutcome
            )) ?? .needsConcreteEpisode
        selfCriticismStatus =
            (try? box.decode(TurnSelfCriticismStatus.self, forKey: .selfCriticismStatus))
            ?? .unresolved
        selfCriticalStatement =
            try? box.decodeIfPresent(String.self, forKey: .selfCriticalStatement)
        selfCriticismLink =
            try? box.decodeIfPresent(String.self, forKey: .selfCriticismLink)
        episodeStructure = (
            try? box.decodeIfPresent(TurnEpisodeStructure.self, forKey: .episodeStructure)
        )?.normalizingGroundedPresence()
        contextRelationship =
            try? box.decodeIfPresent(TurnContextRelationship.self, forKey: .contextRelationship)
        nextPrompt = try? box.decodeIfPresent(TurnNextPrompt.self, forKey: .nextPrompt)
        if nextPrompt == nil {
            let legacy = try decoder.container(keyedBy: LegacyInteractionCodingKeys.self)
            let target = try? legacy.decodeIfPresent(
                TurnConfirmationTarget.self,
                forKey: .pendingConfirmationTarget
            )
            let purpose = try? legacy.decodeIfPresent(
                String.self,
                forKey: .pendingQuestionPurpose
            )
            if let target {
                nextPrompt = .confirmationRequest(target: target)
            } else if let purpose,
                      !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nextPrompt = .openQuestion(purpose: purpose, focus: purpose)
            }
        }
        trackingAssessments =
            (try? box.decode([TurnTrackingAssessment].self, forKey: .trackingAssessments)) ?? []
        let decodedCanonical = try? box.decodeIfPresent(
            TurnCardRealityConnection.self,
            forKey: .cardRealityConnection
        )
        pendingCardRealityConnection = try? box.decodeIfPresent(
            PendingCardRealityConnection.self,
            forKey: .pendingCardRealityConnection
        )
        cardImageRelation =
            try? box.decodeIfPresent(String.self, forKey: .cardImageRelation)
        cardRealityMapping =
            try? box.decodeIfPresent(String.self, forKey: .cardRealityMapping)
        cardRealityMappingSource =
            try? box.decodeIfPresent(
                TurnCardRealityMappingSource.self,
                forKey: .cardRealityMappingSource
            )
        cardRealityConnection = decodedCanonical?.normalizedConfirmed
        cardInterpretiveTension =
            try? box.decodeIfPresent(String.self, forKey: .cardInterpretiveTension)
        cardNegotiatedMeaning =
            try? box.decodeIfPresent(String.self, forKey: .cardNegotiatedMeaning)
        cardObservationEvidence =
            try? box.decodeIfPresent(CardObservationEvidence.self, forKey: .cardObservationEvidence)
        cardDevelopmentEvidence =
            try? box.decodeIfPresent(CardDevelopmentEvidence.self, forKey: .cardDevelopmentEvidence)
        candidateBridgeResolvedAt =
            try? box.decodeIfPresent(Date.self, forKey: .candidateBridgeResolvedAt)
        reflectionFrame =
            try? box.decodeIfPresent(TurnReflectionFrame.self, forKey: .reflectionFrame)
        reflectionPhase =
            (try? box.decode(TurnReflectionPhase.self, forKey: .reflectionPhase))
            ?? Self.inferredReflectionPhase(from: reflectionFrame)
        invalidatedInterpretations =
            (try? box.decode([String].self, forKey: .invalidatedInterpretations)) ?? []
        candidUnderstanding =
            try? box.decodeIfPresent(String.self, forKey: .candidUnderstanding)
        fierceUnderstanding =
            try? box.decodeIfPresent(String.self, forKey: .fierceUnderstanding)
        finalNarrative =
            try? box.decodeIfPresent(String.self, forKey: .finalNarrative)
        practiceTransition = try? box.decodeIfPresent(
            TurnPracticeTransition.self,
            forKey: .practiceTransition
        )
        if practiceTransition == nil {
            let legacy = try decoder.container(keyedBy: LegacyPracticeCodingKeys.self)
            let options = (try? legacy.decode(
                [LegacyPracticeOptionDTO].self,
                forKey: .practiceOptions
            )) ?? []
            let selected = try? legacy.decodeIfPresent(
                String.self,
                forKey: .selectedPractice
            )
            let selectedOption = selected.flatMap { content in
                options.first { $0.instruction == content }
            }
            let pendingOption = selectedOption ?? (options.count == 1 ? options.first : nil)
            if let legacyOption = pendingOption,
               legacyOption.kind != .noAction,
               let basis = legacyOption.basis?.trimmingCharacters(in: .whitespacesAndNewlines),
               !basis.isEmpty,
               !legacyOption.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let legacyID = legacyOption.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let migratedID = legacyID.isEmpty ? "legacy-practice-0" : legacyID
                let proposal = TurnPracticeProposal(
                    id: migratedID,
                    kind: legacyOption.kind,
                    content: legacyOption.instruction,
                    basis: basis,
                    status: selectedOption == nil ? .pendingConfirmation : .confirmed,
                    source: .assistantProposed
                )
                practiceTransition = TurnPracticeTransition(
                    transactionID: proposal.id,
                    narrativeReferenceID: nil,
                    proposal: proposal,
                    noActionReason: nil
                )
            }
        }
    }

    /// LEGACY_DECODE_ONLY — current turns persist `reflectionPhase` directly. This migration keeps
    /// an older saved Tender/Fierce/synthesis frame in its existing semantic position after reload.
    private static func inferredReflectionPhase(
        from frame: TurnReflectionFrame?
    ) -> TurnReflectionPhase {
        guard let frame else { return .exploratory }
        if frame.action == .synthesizeUnderstanding { return .synthesis }
        return frame.mode == .fierce ? .fierce : .tender
    }

    /// The sole legacy scalar-to-canonical migration entry. It is called only while decoding a
    /// saved `ReflectionSession`; runtime Planner patches never invoke it.
    mutating func migrateLegacySavedCardRealityConnection()
        -> LegacySavedCardRealityConnectionMigration {
        let legacyImage = cardImageRelation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyMapping = cardRealityMapping?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLegacyPayload = cardRealityMappingSource != nil
            || legacyImage?.isEmpty == false
            || legacyMapping?.isEmpty == false

        if let canonical = cardRealityConnection?.normalizedConfirmed {
            let legacyCandidate: TurnCardRealityConnection?
            if let legacyImage, !legacyImage.isEmpty,
               let legacyMapping, !legacyMapping.isEmpty,
               let legacySource = cardRealityMappingSource {
                legacyCandidate = TurnCardRealityConnection(
                    imageRelation: legacyImage,
                    realityMapping: legacyMapping,
                    source: legacySource
                ).normalizedConfirmed
            } else {
                legacyCandidate = nil
            }
            let conflict = hasLegacyPayload
                && (legacyCandidate == nil || legacyCandidate != canonical)
            cardRealityConnection = canonical
            cardImageRelation = canonical.imageRelation
            cardRealityMapping = canonical.realityMapping
            cardRealityMappingSource = canonical.source
            return conflict ? .canonicalConflictIgnored : .none
        }

        guard hasLegacyPayload else { return .none }
        guard let legacyImage, !legacyImage.isEmpty,
              let legacyMapping, !legacyMapping.isEmpty,
              let legacySource = cardRealityMappingSource,
              let migrated = TurnCardRealityConnection(
                  imageRelation: legacyImage,
                  realityMapping: legacyMapping,
                  source: legacySource
              ).normalizedConfirmed else {
            // Historical relation/mapping text remains exportable. An orphan source is removed so
            // it cannot masquerade as a confirmed runtime connection after restoration.
            cardRealityConnection = nil
            cardRealityMappingSource = nil
            return .incomplete
        }

        cardRealityConnection = migrated
        cardImageRelation = migrated.imageRelation
        cardRealityMapping = migrated.realityMapping
        cardRealityMappingSource = migrated.source
        return .migrated
    }

    mutating func apply(
        _ update: TurnSemanticMemoryUpdate,
        committedNextPrompt: TurnNextPrompt? = nil
    ) {
        if let value = update.situationUnderstanding {
            situationUnderstanding = value
        }
        if let values = update.answeredQuestionPurposes {
            answeredQuestionPurposes = Array(
                Set(answeredQuestionPurposes + values)
            ).sorted()
        }
        if let values = update.receivedDisclosureQuestionPurposes {
            receivedDisclosureQuestionPurposes = Array(
                Set(receivedDisclosureQuestionPurposes + values)
            ).sorted { $0.rawValue < $1.rawValue }
        }
        if let value = update.eventDisclosureOutcome { eventDisclosureOutcome = value }
        if let value = update.selfCriticismStatus { selfCriticismStatus = value }
        if let value = update.selfCriticalStatement { selfCriticalStatement = value }
        if let value = update.selfCriticismLink { selfCriticismLink = value }
        if let value = update.episodeStructure {
            episodeStructure = (
                episodeStructure?.merging(value) ?? value
            ).normalizingGroundedPresence()
        }
        if let value = update.contextRelationship { contextRelationship = value }
        if let committedNextPrompt {
            nextPrompt = committedNextPrompt
        }
        if let assessments = update.trackingAssessments {
            var indexed = Dictionary(uniqueKeysWithValues: trackingAssessments.map { ($0.cueID, $0) })
            assessments.forEach { indexed[$0.cueID] = $0 }
            trackingAssessments = indexed.values.sorted { $0.cueID < $1.cueID }
        }
        if update.clearPendingCardRealityConnection == true {
            // Recording the resolution timestamp makes candidateBridgeOfferedOrResolved
            // durable even after the pending candidate is cleared.
            if pendingCardRealityConnection != nil {
                candidateBridgeResolvedAt = update.candidateBridgeResolvedAt ?? Date()
            }
            pendingCardRealityConnection = nil
        }
        if let pending = update.pendingCardRealityConnection,
           pending.isStructurallyComplete {
            pendingCardRealityConnection = pending
        }
        if update.clearCardRealityConnection == true {
            cardRealityConnection = nil
            cardImageRelation = nil
            cardRealityMapping = nil
            cardRealityMappingSource = nil
        } else if let canonical = update.cardRealityConnection?.normalizedConfirmed {
            cardRealityConnection = canonical
            cardImageRelation = canonical.imageRelation
            cardRealityMapping = canonical.realityMapping
            cardRealityMappingSource = canonical.source
        } else {
            // Legacy runtime branches may still update their export mirrors, but these fields can
            // never construct or change the canonical connection during a current turn.
            if let value = update.cardImageRelation { cardImageRelation = value }
            if let value = update.cardRealityMapping { cardRealityMapping = value }
            if let value = update.cardRealityMappingSource { cardRealityMappingSource = value }
        }
        if let value = update.cardInterpretiveTension { cardInterpretiveTension = value }
        if let value = update.cardNegotiatedMeaning { cardNegotiatedMeaning = value }
        if let value = update.cardObservationEvidence { cardObservationEvidence = value }
        if let value = update.cardDevelopmentEvidence {
            cardDevelopmentEvidence = cardDevelopmentEvidence?.merging(value) ?? value
        }
        if let value = update.candidateBridgeResolvedAt { candidateBridgeResolvedAt = value }
        if let value = update.reflectionFrame { reflectionFrame = value }
        if let value = update.reflectionPhase { reflectionPhase = value }
        if let values = update.invalidatedInterpretations {
            for value in values {
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty, !invalidatedInterpretations.contains(clean) {
                    invalidatedInterpretations.append(clean)
                }
            }
        }
        if let value = update.candidUnderstanding { candidUnderstanding = value }
        if let value = update.fierceUnderstanding { fierceUnderstanding = value }
        if let value = update.finalNarrative { finalNarrative = value }
        if let value = update.practiceTransition { practiceTransition = value }
    }
}

/// Optional patch fields let the controller update only the semantic relationship established by
/// the latest turn. Empty strings are meaningful corrections and therefore are not discarded.
struct TurnSemanticMemoryUpdate: Codable, Equatable, Sendable {
    var situationUnderstanding: String?
    var answeredQuestionPurposes: [String]?
    var receivedDisclosureQuestionPurposes: [TurnDisclosureQuestionPurpose]?
    var eventDisclosureOutcome: TurnEventDisclosureOutcome?
    var selfCriticismStatus: TurnSelfCriticismStatus?
    var selfCriticalStatement: String?
    var selfCriticismLink: String?
    var episodeStructure: TurnEpisodeStructure?
    var contextRelationship: TurnContextRelationship?
    /// Transient protocol signal: the visible reply actually juxtaposes the optional contextual
    /// cue after a user-authored card-to-reality mapping. Persistence lives in the local inference
    /// relevance state (`offered`), not in semantic narrative memory.
    var contextCueOffered: Bool?
    var trackingAssessments: [TurnTrackingAssessment]?
    /// Atomic current-protocol connection. Legacy scalar fields below are decode/input
    /// compatibility only and cannot independently authorize card guidance.
    var cardRealityConnection: TurnCardRealityConnection?
    /// A system-proposed mapping awaiting a typed pre-guidance confirmation.
    var pendingCardRealityConnection: PendingCardRealityConnection?
    var clearCardRealityConnection: Bool?
    var clearPendingCardRealityConnection: Bool?
    /// Semantic outcome used only for the bounded connection-attempt policy.
    var cardConnectionOutcome: TurnCardConnectionOutcome?
    var cardImageRelation: String?
    var cardRealityMapping: String?
    var cardRealityMappingSource: TurnCardRealityMappingSource?
    /// Decode-boundary metadata. `true` means at least one retired scalar key appeared in the
    /// Planner payload, including an explicit JSON null. It is not encoded or persisted.
    var legacyConnectionFieldsPresentInPayload = false
    var cardInterpretiveTension: String?
    var cardNegotiatedMeaning: String?
    /// Typed observation evidence from the Planner's semantic patch.
    var cardObservationEvidence: CardObservationEvidence?
    /// Typed development evidence from the Planner's semantic patch.
    var cardDevelopmentEvidence: CardDevelopmentEvidence?
    /// Set by Swift when a candidate bridge resolution is committed.
    var candidateBridgeResolvedAt: Date?
    var reflectionFrame: TurnReflectionFrame?
    /// Swift-owned transition output. Current Planner prompts never request this field; the gate
    /// clears any supplied value and writes the phase implied by the authorized operation.
    var reflectionPhase: TurnReflectionPhase?
    /// User-explicitly rejected assistant interpretations supplied as semantic propositions.
    var invalidatedInterpretations: [String]?
    /// LEGACY_DECODE_ONLY — current Planner output must use `reflectionFrame`.
    var candidUnderstanding: String?
    var fierceUnderstanding: String?
    var finalNarrative: String?
    var practiceTransition: TurnPracticeTransition?

    init(
        situationUnderstanding: String? = nil,
        answeredQuestionPurposes: [String]? = nil,
        receivedDisclosureQuestionPurposes: [TurnDisclosureQuestionPurpose]? = nil,
        eventDisclosureOutcome: TurnEventDisclosureOutcome? = nil,
        selfCriticismStatus: TurnSelfCriticismStatus? = nil,
        selfCriticalStatement: String? = nil,
        selfCriticismLink: String? = nil,
        episodeStructure: TurnEpisodeStructure? = nil,
        contextRelationship: TurnContextRelationship? = nil,
        contextCueOffered: Bool? = nil,
        trackingAssessments: [TurnTrackingAssessment]? = nil,
        cardRealityConnection: TurnCardRealityConnection? = nil,
        pendingCardRealityConnection: PendingCardRealityConnection? = nil,
        clearCardRealityConnection: Bool? = nil,
        clearPendingCardRealityConnection: Bool? = nil,
        cardConnectionOutcome: TurnCardConnectionOutcome? = nil,
        cardImageRelation: String? = nil,
        cardRealityMapping: String? = nil,
        cardRealityMappingSource: TurnCardRealityMappingSource? = nil,
        cardInterpretiveTension: String? = nil,
        cardNegotiatedMeaning: String? = nil,
        cardObservationEvidence: CardObservationEvidence? = nil,
        cardDevelopmentEvidence: CardDevelopmentEvidence? = nil,
        candidateBridgeResolvedAt: Date? = nil,
        reflectionFrame: TurnReflectionFrame? = nil,
        reflectionPhase: TurnReflectionPhase? = nil,
        invalidatedInterpretations: [String]? = nil,
        candidUnderstanding: String? = nil,
        fierceUnderstanding: String? = nil,
        finalNarrative: String? = nil,
        practiceTransition: TurnPracticeTransition? = nil
    ) {
        self.situationUnderstanding = situationUnderstanding
        self.answeredQuestionPurposes = answeredQuestionPurposes
        self.receivedDisclosureQuestionPurposes = receivedDisclosureQuestionPurposes
        self.eventDisclosureOutcome = eventDisclosureOutcome
        self.selfCriticismStatus = selfCriticismStatus
        self.selfCriticalStatement = selfCriticalStatement
        self.selfCriticismLink = selfCriticismLink
        self.episodeStructure = episodeStructure
        self.contextRelationship = contextRelationship
        self.contextCueOffered = contextCueOffered
        self.trackingAssessments = trackingAssessments
        self.cardRealityConnection = cardRealityConnection
        self.pendingCardRealityConnection = pendingCardRealityConnection
        self.clearCardRealityConnection = clearCardRealityConnection
        self.clearPendingCardRealityConnection = clearPendingCardRealityConnection
        self.cardConnectionOutcome = cardConnectionOutcome
        self.cardImageRelation = cardImageRelation
        self.cardRealityMapping = cardRealityMapping
        self.cardRealityMappingSource = cardRealityMappingSource
        self.legacyConnectionFieldsPresentInPayload = cardImageRelation != nil
            || cardRealityMapping != nil
            || cardRealityMappingSource != nil
        self.cardInterpretiveTension = cardInterpretiveTension
        self.cardNegotiatedMeaning = cardNegotiatedMeaning
        self.cardObservationEvidence = cardObservationEvidence
        self.cardDevelopmentEvidence = cardDevelopmentEvidence
        self.candidateBridgeResolvedAt = candidateBridgeResolvedAt
        self.reflectionFrame = reflectionFrame
        self.reflectionPhase = reflectionPhase
        self.invalidatedInterpretations = invalidatedInterpretations
        self.candidUnderstanding = candidUnderstanding
        self.fierceUnderstanding = fierceUnderstanding
        self.finalNarrative = finalNarrative
        self.practiceTransition = practiceTransition
    }

    private enum CodingKeys: String, CodingKey {
        case situationUnderstanding
        case answeredQuestionPurposes
        case receivedDisclosureQuestionPurposes
        case eventDisclosureOutcome
        case selfCriticismStatus
        case selfCriticalStatement
        case selfCriticismLink
        case episodeStructure
        case contextRelationship
        case contextCueOffered
        case trackingAssessments
        case cardRealityConnection
        case pendingCardRealityConnection
        case clearCardRealityConnection
        case clearPendingCardRealityConnection
        case cardConnectionOutcome
        case cardImageRelation
        case cardRealityMapping
        case cardRealityMappingSource
        case cardInterpretiveTension
        case cardNegotiatedMeaning
        case cardObservationEvidence
        case cardDevelopmentEvidence
        case candidateBridgeResolvedAt
        case reflectionFrame
        case reflectionPhase
        case invalidatedInterpretations
        case candidUnderstanding
        case fierceUnderstanding
        case finalNarrative
        case practiceTransition
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        // Semantic-memory fields are patches, not capability requests. A malformed optional patch
        // must not make an otherwise decodable Planner response disappear. Required narrative
        // content is still enforced later by the protocol controller for the intent that needs it.
        situationUnderstanding = try? box.decode(
            String.self,
            forKey: .situationUnderstanding
        )
        receivedDisclosureQuestionPurposes = try? box.decode(
            [TurnDisclosureQuestionPurpose].self,
            forKey: .receivedDisclosureQuestionPurposes
        )
        eventDisclosureOutcome = try? box.decode(
            TurnEventDisclosureOutcome.self,
            forKey: .eventDisclosureOutcome
        )
        selfCriticismStatus = try? box.decode(
            TurnSelfCriticismStatus.self,
            forKey: .selfCriticismStatus
        )
        selfCriticalStatement = try? box.decode(
            String.self,
            forKey: .selfCriticalStatement
        )
        selfCriticismLink = try? box.decode(
            String.self,
            forKey: .selfCriticismLink
        )
        episodeStructure = try? box.decode(
            TurnEpisodeStructure.self,
            forKey: .episodeStructure
        )
        contextRelationship = try? box.decode(
            TurnContextRelationship.self,
            forKey: .contextRelationship
        )
        contextCueOffered = try? Self.decodeOptionalProtocolBool(
            from: box,
            forKey: .contextCueOffered
        )
        if let values = try? box.decode(
            [String].self,
            forKey: .answeredQuestionPurposes
        ) {
            answeredQuestionPurposes = values
        } else if let value = try? box.decode(
            String.self,
            forKey: .answeredQuestionPurposes
        ) {
            answeredQuestionPurposes = [value]
        } else {
            answeredQuestionPurposes = nil
        }
        trackingAssessments = try? box.decode(
            [TurnTrackingAssessment].self,
            forKey: .trackingAssessments
        )
        cardRealityConnection = try? box.decode(
            TurnCardRealityConnection.self,
            forKey: .cardRealityConnection
        )
        pendingCardRealityConnection = try? box.decode(
            PendingCardRealityConnection.self,
            forKey: .pendingCardRealityConnection
        )
        clearCardRealityConnection = try? Self.decodeOptionalProtocolBool(
            from: box,
            forKey: .clearCardRealityConnection
        )
        clearPendingCardRealityConnection = try? Self.decodeOptionalProtocolBool(
            from: box,
            forKey: .clearPendingCardRealityConnection
        )
        cardConnectionOutcome = try? box.decode(
            TurnCardConnectionOutcome.self,
            forKey: .cardConnectionOutcome
        )
        cardImageRelation = try? box.decode(
            String.self,
            forKey: .cardImageRelation
        )
        cardRealityMapping = try? box.decode(
            String.self,
            forKey: .cardRealityMapping
        )
        cardRealityMappingSource = try? box.decode(
            TurnCardRealityMappingSource.self,
            forKey: .cardRealityMappingSource
        )
        legacyConnectionFieldsPresentInPayload = box.contains(.cardImageRelation)
            || box.contains(.cardRealityMapping)
            || box.contains(.cardRealityMappingSource)
        cardInterpretiveTension = try? box.decode(
            String.self,
            forKey: .cardInterpretiveTension
        )
        cardNegotiatedMeaning = try? box.decode(
            String.self,
            forKey: .cardNegotiatedMeaning
        )
        cardObservationEvidence = try? box.decode(
            CardObservationEvidence.self,
            forKey: .cardObservationEvidence
        )
        cardDevelopmentEvidence = try? box.decode(
            CardDevelopmentEvidence.self,
            forKey: .cardDevelopmentEvidence
        )
        candidateBridgeResolvedAt = try? box.decode(
            Date.self,
            forKey: .candidateBridgeResolvedAt
        )
        reflectionFrame = try? box.decode(
            TurnReflectionFrame.self,
            forKey: .reflectionFrame
        )
        reflectionPhase = try? box.decode(
            TurnReflectionPhase.self,
            forKey: .reflectionPhase
        )
        invalidatedInterpretations = try? box.decode(
            [String].self,
            forKey: .invalidatedInterpretations
        )
        candidUnderstanding = try? box.decode(
            String.self,
            forKey: .candidUnderstanding
        )
        fierceUnderstanding = try? box.decode(
            String.self,
            forKey: .fierceUnderstanding
        )
        finalNarrative = try? box.decode(
            String.self,
            forKey: .finalNarrative
        )
        practiceTransition = try? box.decode(
            TurnPracticeTransition.self,
            forKey: .practiceTransition
        )
    }

    private static func decodeOptionalProtocolBool(
        from box: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Bool? {
        guard box.contains(key), try !box.decodeNil(forKey: key) else { return nil }
        if let value = try? box.decode(Bool.self, forKey: key) {
            return value
        }
        if let raw = try? box.decode(String.self, forKey: key) {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                break
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            .init(
                codingPath: box.codingPath + [key],
                debugDescription: "Expected a JSON boolean, null, or the exact string true/false."
            )
        )
    }
}

/// The one cumulative disclosure projection used by current capabilities, validation, recovery,
/// and bounded planning. Applying the Planner patch here prevents each reader from inventing its
/// own `patch ?? stored` interpretation.
struct EffectiveEventDisclosureState: Equatable, Sendable {
    let memory: TurnSemanticMemory

    init(
        memory: TurnSemanticMemory,
        update: TurnSemanticMemoryUpdate? = nil
    ) {
        var projected = memory
        if let update {
            projected.apply(update)
        }
        self.memory = projected
    }

    var episode: TurnEpisodeStructure? {
        memory.episodeStructure?.normalizingGroundedPresence()
    }

    var hasConcreteFocalEvent: Bool {
        episode?.concreteFacts.contains(where: Self.nonempty) == true
    }

    var hasEventProcess: Bool {
        guard let episode else { return false }
        switch episode.eventProcessStatus {
        case .unresolved:
            return false
        case .present, .mixed:
            return episode.hasEventProcessContent
        case .absent:
            return !episode.hasEventProcessContent
        case .uncertain:
            return episode.hasEventProcessContent
                || Self.nonempty(episode.keyUncertainty ?? "")
        }
    }

    var hasUserBehaviorOrOmission: Bool {
        [.present, .mixed].contains(episode?.behaviorEvidenceStatus ?? .unresolved)
            && episode?.behaviorEvidence.contains(where: Self.nonempty) == true
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The sole current-protocol completion rule for Event Disclosure.
func isEventDisclosureCoreComplete(
    _ state: EffectiveEventDisclosureState
) -> Bool {
    state.hasConcreteFocalEvent
        && state.hasEventProcess
        && state.hasUserBehaviorOrOmission
}

/// The semantic planner can recommend protocol movement and describe the communicative purpose
/// of the next reply, but it does not write text shown to the person.
struct CardReferenceSelection: Codable, Equatable, Sendable {
    /// Index into the selected card's application-supplied `referenceGuidance.relations` array.
    /// Using an index keeps the Planner from inventing or rewriting a private source relation.
    let relationIndex: Int
}

struct LLMTurnResponsePlan: Codable, Equatable, Sendable {
    /// Planner-authored semantic choice. Current protocol normal and recovery turns require this
    /// closed value; only legacy responses may decode it as nil.
    let semanticOperation: PlannerSemanticOperation?
    /// Runtime-only provenance for a plan deterministically produced by the Swift projector.
    /// It is deliberately excluded from Codable. The adapter is the only producer and it records
    /// the operation actually used by the projector, independently of legacy Planner fields.
    let projectedOperation: PlannerSemanticOperation?
    let requestedStage: ReflectionProtocolStage
    let localAction: TurnLocalActionRequest
    let memoryUpdate: TurnSemanticMemoryUpdate
    /// Current card-reality Planner output. For protocol v5 this is the only direct card
    /// connection decision; Swift maps it against persisted interaction state and creates any
    /// confirmation resolution deterministically.
    let cardConnectionTurnOutcome: CardConnectionTurnOutcome?
    /// Resolution of the prompt visible before this turn. Missing only for legacy responses.
    let resolvedConfirmation: TurnResolvedConfirmation?
    /// Prompt established by the new visible reply. Missing only for legacy responses.
    let nextPrompt: TurnNextPrompt?
    let replyIntent: TurnReplyIntent
    /// Natural-language details grounded in the latest turn. This can describe what to acknowledge
    /// but cannot change the typed intent or authorize a workflow function.
    let replyGuidance: String
    /// An optional, turn-local question lens. It is never persisted as semantic memory and never
    /// represents the person's interpretation or answer.
    let cardReferenceSelection: CardReferenceSelection?

    init(
        semanticOperation: PlannerSemanticOperation? = nil,
        projectedOperation: PlannerSemanticOperation? = nil,
        requestedStage: ReflectionProtocolStage,
        localAction: TurnLocalActionRequest,
        memoryUpdate: TurnSemanticMemoryUpdate,
        cardConnectionTurnOutcome: CardConnectionTurnOutcome? = nil,
        resolvedConfirmation: TurnResolvedConfirmation? = nil,
        nextPrompt: TurnNextPrompt? = nil,
        replyIntent: TurnReplyIntent,
        replyGuidance: String,
        cardReferenceSelection: CardReferenceSelection? = nil
    ) {
        self.semanticOperation = semanticOperation
        self.projectedOperation = projectedOperation
        self.requestedStage = requestedStage
        self.localAction = localAction
        self.memoryUpdate = memoryUpdate
        self.cardConnectionTurnOutcome = cardConnectionTurnOutcome
        self.resolvedConfirmation = resolvedConfirmation
        self.nextPrompt = nextPrompt
        self.replyIntent = replyIntent
        self.replyGuidance = replyGuidance
        self.cardReferenceSelection = cardReferenceSelection
    }

    private enum CodingKeys: String, CodingKey {
        case semanticOperation
        case requestedStage, localAction, memoryUpdate, cardConnectionTurnOutcome
        case resolvedConfirmation, nextPrompt
        case replyIntent, replyGuidance, cardReferenceSelection
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        semanticOperation = try box.decodeIfPresent(
            PlannerSemanticOperation.self,
            forKey: .semanticOperation
        )
        projectedOperation = nil
        requestedStage = try box.decode(ReflectionProtocolStage.self, forKey: .requestedStage)
        localAction = try box.decode(TurnLocalActionRequest.self, forKey: .localAction)
        memoryUpdate = try box.decode(TurnSemanticMemoryUpdate.self, forKey: .memoryUpdate)
        cardConnectionTurnOutcome = try box.decodeIfPresent(
            CardConnectionTurnOutcome.self,
            forKey: .cardConnectionTurnOutcome
        )
        resolvedConfirmation = try box.decodeIfPresent(
            TurnResolvedConfirmation.self,
            forKey: .resolvedConfirmation
        )
        nextPrompt = try box.decodeIfPresent(TurnNextPrompt.self, forKey: .nextPrompt)
        replyIntent = try box.decode(TurnReplyIntent.self, forKey: .replyIntent)
        // Silent local transactions never call the Writer. Treat an omitted private writing hint
        // as empty and let the protocol validator require it only for genuinely visible turns.
        replyGuidance =
            (try? box.decode(String.self, forKey: .replyGuidance)) ?? ""
        cardReferenceSelection = try box.decodeIfPresent(
            CardReferenceSelection.self,
            forKey: .cardReferenceSelection
        )
    }
}

/// The Writer has one job: express an already planned turn naturally. It cannot request stages,
/// local capabilities, tracking access, or memory changes.
struct LLMTurnWriterResponse: Codable, Equatable, Sendable {
    let realizedIntent: TurnReplyIntent
    let reply: String
}

struct LLMTurnControllerResponse: Codable, Equatable, Sendable {
    let requestedStage: ReflectionProtocolStage
    let localAction: TurnLocalActionRequest
    let memoryUpdate: TurnSemanticMemoryUpdate
    let cardConnectionTurnOutcome: CardConnectionTurnOutcome?
    let resolvedConfirmation: TurnResolvedConfirmation?
    let nextPrompt: TurnNextPrompt?
    let replyIntent: TurnReplyIntent
    let reply: String

    init(
        requestedStage: ReflectionProtocolStage,
        localAction: TurnLocalActionRequest,
        memoryUpdate: TurnSemanticMemoryUpdate,
        cardConnectionTurnOutcome: CardConnectionTurnOutcome? = nil,
        resolvedConfirmation: TurnResolvedConfirmation? = nil,
        nextPrompt: TurnNextPrompt? = nil,
        replyIntent: TurnReplyIntent,
        reply: String
    ) {
        self.requestedStage = requestedStage
        self.localAction = localAction
        self.memoryUpdate = memoryUpdate
        self.cardConnectionTurnOutcome = cardConnectionTurnOutcome
        self.resolvedConfirmation = resolvedConfirmation
        self.nextPrompt = nextPrompt
        self.replyIntent = replyIntent
        self.reply = reply
    }
}

// MARK: - Semantic Operation (non-persisted internal classification)

/// Each case has exactly one business meaning. Unlike `TurnReplyIntent`, a semantic operation is
/// never also a stage transition, a reply form, a legacy compatibility label, or a recovery hint.
/// It classifies only the Planner's intended conversational action from typed state evidence.
enum PlannerSemanticOperation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    // MARK: - Event Disclosure
    /// Continue gathering a missing event-structure relation (focal event, process, or behavior).
    case clarifyEvent
    /// The disclosure core is complete; transition to card-consent invitation.
    case advanceToCardConsent

    // MARK: - Card Consent
    /// Continue inviting the person to consent to the optional card draw.
    case inviteCardConsent
    /// Person accepted; Swift draws the card and displays it locally.
    case acknowledgeCardConsent
    /// Person declined the card; proceed without it.
    case declineCardConsent

    // MARK: - Card Observation / Development
    /// Continue inviting the person to describe what is visibly happening in the image.
    case continueCardObservation
    /// Continue developing the image—ask about what may happen/change next.
    case continueCardDevelopment
    /// The image relation is ready; invite the person to connect it to their real episode.
    case inviteRealityConnection

    // MARK: - Card Reality Connection
    /// Continue an open-ended image-to-reality exploration turn.
    case continueOpenCardConnection
    /// Offer one scaffold/narrowing question that helps the person form a connection
    /// without proposing a candidate. Only legal in openExploration after first difficulty.
    case offerCardConnectionScaffold
    /// Offer one system-proposed candidate mapping and ask the person to accept, revise, or reject.
    case offerCardConnectionCandidate
    /// Person spontaneously authored a complete image-to-reality mapping,
    /// bypassing the candidate path. Canonical connection is created directly.
    case establishUserAuthoredCardConnection
    /// Person accepted the pending candidate; promote it to a canonical connection.
    case acceptCardConnectionCandidate
    /// Person revised the pending candidate; save the user-supplied mapping.
    case reviseCardConnectionCandidate
    /// Person rejected the pending candidate; clear it without a new mapping.
    case rejectCardConnectionCandidate

    // MARK: - Explicit Card Bypass
    /// The person cannot or does not want a card–reality connection. Leave the card stage and
    /// enter Direct Reflection. This is only legal when the connection is typed as unavailable,
    /// the person has requested a skip, or the current protocol allows bypass.
    case bypassCardConnectionToDirectReflection

    // MARK: - Card Canonical Connection (post-guidance)
    /// v5: silently authorize card guidance and enter Direct Reflection.
    case authorizeCardGuidance
    /// v4: present the legacy negotiated card reading.
    case presentLegacyCardReading

    // MARK: - Direct Reflection
    /// Continue from the established reality connection without interpreting it yet. The question
    /// seeks one concrete experience, behavior, tension, expectation, constraint, or choice.
    case continueExploratoryReflection
    /// Continue Tender reflection with one grounded distinction.
    case continueTenderReflection
    /// Continue Fierce reflection grounded in Tender, with behavior/impact/caring-direction evidence.
    case continueTenderGroundedFierceReflection
    /// Synthesize the reflection. A later proposePractice turn owns the optional action.
    case synthesizeDirectReflection

    // MARK: - Optional Action
    /// Propose one new practice (care/repair/protect/change/noAction).
    case proposePractice
    /// Resolve a pending practice proposal (accept, revise, decline, or reject).
    case resolvePractice

    // MARK: - Narrative
    /// Present or confirm the final narrative.
    case confirmNarrative
    /// Revise the final narrative.
    case reviseNarrative

    // MARK: - Completion
    /// Complete the conversation.
    case completeConversation

    // MARK: - Safety
    /// Provide immediate safety support.
    case provideSafetySupport
}

/// The minimal non-persisted semantic payload produced by classifying a Planner turn.
/// It carries only the operation and its evidence patch; stage transitions, nextPrompt,
/// confirmations, and outcome projections belong to a separate projector.
struct PlannerSemanticDecision: Equatable, Sendable {
    let operation: PlannerSemanticOperation
    let memoryUpdate: TurnSemanticMemoryUpdate
    /// What the visible response should express (derived from replyGuidance).
    let responseFocus: String?
    /// What question the turn should clarify, when the operation asks a question.
    let clarificationFocus: String?
}

/// Typed substate for the card-reflection stage. This mirrors the server-side `_card_substate`
/// classification but is computed deterministically from persisted session state.
enum CardSemanticSubstate: String, Equatable, Sendable {
    case none
    case observation
    case development
    case openExploration
    case awaitingCandidateResolution
    case guidance
}

/// Thrown when a Planner `replyIntent` + current state combination cannot be classified into
/// exactly one semantic operation.
enum SemanticMappingViolation: Error, Equatable {
    case missingSemanticOperation
    case unknownSemanticOperation(String)
    case semanticOperationPayloadMismatch(PlannerSemanticOperation, String)
    case semanticOperationNotAllowed(PlannerSemanticOperation, ReflectionProtocolStage)
    case legacyOperationInferenceUsedInCurrentProtocol
    case explicitLegacyOperationDivergence(
        explicit: PlannerSemanticOperation,
        legacy: PlannerSemanticOperation
    )
    case ambiguousReplyIntent(TurnReplyIntent, ReflectionProtocolStage)
    case cardSubstateMismatch(TurnReplyIntent, CardSemanticSubstate)
    case missingRequiredOutcome(TurnReplyIntent)
    case unclassifiablePlan(String)
}

/// Thrown when a valid semantic operation cannot be projected into an executable turn
/// because required typed preconditions are not satisfied.
enum ProjectionViolation: Error, Equatable {
    case illegalOperationForStage(PlannerSemanticOperation, ReflectionProtocolStage)
    case illegalOperationForCardSubstate(PlannerSemanticOperation, CardSemanticSubstate)
    case missingTypedPrecondition(PlannerSemanticOperation, String)
    case capabilityNotAvailable(PlannerSemanticOperation, String)
    case structuralInvariant(PlannerSemanticOperation, String)
}

// MARK: - Projected Executable Turn Plan

/// Deterministically projected from a semantic operation and typed state.
/// Contains no Planner-authored protocol fields (no `requestedStage`, `nextPrompt`,
/// `confirmation`, or `outcome` from the old LLM output). Non-Codable, non-persisted.
struct ProjectedExecutableTurnPlan: Equatable, Sendable {
    let semanticDecision: PlannerSemanticDecision

    let sourceStage: ReflectionProtocolStage
    let requestedStage: ReflectionProtocolStage
    let replyIntent: TurnReplyIntent
    let localAction: TurnLocalActionRequest

    let nextPrompt: TurnNextPrompt
    let resolvedConfirmation: TurnResolvedConfirmation?

    let memoryUpdate: TurnSemanticMemoryUpdate
    let responseFocus: String?

    init(
        semanticDecision: PlannerSemanticDecision,
        sourceStage: ReflectionProtocolStage,
        requestedStage: ReflectionProtocolStage,
        replyIntent: TurnReplyIntent,
        localAction: TurnLocalActionRequest,
        nextPrompt: TurnNextPrompt,
        resolvedConfirmation: TurnResolvedConfirmation?,
        memoryUpdate: TurnSemanticMemoryUpdate,
        responseFocus: String?
    ) {
        self.semanticDecision = semanticDecision
        self.sourceStage = sourceStage
        self.requestedStage = requestedStage
        self.replyIntent = replyIntent
        self.localAction = localAction
        self.nextPrompt = nextPrompt
        self.resolvedConfirmation = resolvedConfirmation
        self.memoryUpdate = memoryUpdate
        self.responseFocus = responseFocus
    }
}

// MARK: - Legacy workflow phase (unchanged)

/// A persisted, research-facing workflow phase that is intentionally finer grained than the
/// legacy UI/LLM `ReflectionState`. Keeping the two separate lets Swift own the fixed study
/// sequence without exposing new internal route names in the interface or breaking older prompt
/// and view switches. New cases are additive and older sessions infer a safe phase from `stage`.
enum ReflectionWorkflowPhase: String, Codable, CaseIterable, Sendable {
    case opening
    case structuredDisclosure
    case tenderGroundingConfirmation
    case trackingReview
    /// After the person says the records resemble their recent state, ask once whether that
    /// state mattered in the concrete event. This keeps tracking from jumping directly to a
    /// synthesis or card invitation, while preserving "no effect" as a complete answer.
    case trackingContextLink
    case contextConfirmation
    case cardSelection
    case cardDisplay
    case cardObservation
    case cardAssociation
    /// Legacy resume-only phase retained for sessions saved before the normal card path was
    /// shortened to two image turns. New sessions use an image-only scaffold only after the
    /// first life-connection invitation proves difficult.
    case cardNarrativeDeepening
    case cardConnection
    /// The app presents one explicitly tentative mapping between a relationship the person
    /// described in the image and the already confirmed real situation. It may only be used
    /// later if the person accepts or revises it.
    case cardMappingConfirmation
    /// The user, not the model, says whether the card changed or sharpened how they understand
    /// the original situation after the concrete circumstances have been named and before agency.
    case cardMeaningShift
    case candidCircumstances
    case candidAgency
    case reflectionNarrativeConfirmation
    case optionalAction
    case actionConfirmation
    case narrativeConfirmation
    case complete
    case safetySupport
}

struct ReflectionWorkflowStateMachine {
    func canTransition(from: ReflectionWorkflowPhase, to: ReflectionWorkflowPhase) -> Bool {
        if to == .safetySupport { return from != .complete }
        if from == to { return true }
        let allowed: [ReflectionWorkflowPhase: Set<ReflectionWorkflowPhase>] = [
            .opening: [.structuredDisclosure],
            .structuredDisclosure: [.tenderGroundingConfirmation],
            .tenderGroundingConfirmation: [.trackingReview],
            .trackingReview: [.trackingContextLink, .contextConfirmation],
            .trackingContextLink: [.contextConfirmation],
            // A resumed direct-condition session may have an old confirmation but no completed
            // tracking review. It must return to the shared tracking gate before candid reflection.
            .contextConfirmation: [.cardSelection, .candidCircumstances, .trackingReview],
            .cardSelection: [.cardDisplay],
            .cardDisplay: [.cardSelection, .cardObservation],
            .cardObservation: [.cardAssociation, .candidCircumstances],
            // New reflections move from the second image turn directly to the first optional
            // life-connection invitation. `cardNarrativeDeepening` remains as a resume-only
            // legacy phase for sessions saved by earlier builds.
            .cardAssociation: [.cardConnection, .cardNarrativeDeepening, .candidCircumstances],
            .cardNarrativeDeepening: [.cardConnection, .candidCircumstances],
            // A card-to-life connection is only a bridge. Even when the person authors a complete
            // mapping themselves, the app first makes room for the real conditions around it.
            // Keeping this edge strict prevents restored sessions and fallback paths from
            // bypassing the Tender circumstances turn.
            .cardConnection: [.cardMappingConfirmation, .candidCircumstances],
            .cardMappingConfirmation: [.candidCircumstances],
            // The direct condition has no card meaning-shift turn, so it may enter a concrete
            // fierce question directly from circumstances. In either condition, when the user
            // has supplied no behaviour/consequence/boundary that warrants fierce compassion,
            // the app may retain tender understanding and continue to the narrative instead.
            .candidCircumstances: [.cardMeaningShift, .candidAgency, .reflectionNarrativeConfirmation],
            .cardMeaningShift: [.candidAgency, .reflectionNarrativeConfirmation],
            .candidAgency: [.reflectionNarrativeConfirmation],
            .reflectionNarrativeConfirmation: [.optionalAction],
            .optionalAction: [.actionConfirmation, .narrativeConfirmation],
            .actionConfirmation: [.narrativeConfirmation],
            // A person may ask for a practice after first choosing to keep only the narrative.
            // This late return is user-initiated; it does not reopen attribution or assign a
            // responsibility direction.
            .narrativeConfirmation: [.optionalAction, .complete],
            .complete: [],
            .safetySupport: [.complete],
        ]
        return allowed[from, default: []].contains(to)
    }
}

enum CompassionRoute: String, Codable, CaseIterable {
    case tenderStabilize, protect, provide, repair, change, explore
}

enum ConsentState: String, Codable { case unknown, yes, no }
enum ControllabilityLevel: String, Codable { case unknown, low, mixed, high }
enum AgencyLevel: String, Codable { case unknown, low, medium, high }

/// Private semantic candidates from the ContextAnalyzer. They describe the current disclosure,
/// never assign fault or advance the reflection workflow on their own.
enum ReflectionEventType: String, Codable {
    case taskProgress
    case criticism
    case interpersonalConflict
    case relationalHurt
    case failure
    case boundary
    case externalUnfairness
    case unclear
}

enum TaskProgressStatus: String, Codable {
    case notApplicable
    case unclear
    case notStarted
    case startedButStalled
    case activelyWorkingButIneffective
    case completedButDisappointed
}

enum ExperimentalCondition: String, Codable, CaseIterable {
    case cardMediated
    /// Retains the existing persisted/server value for backward-compatible research records.
    case directLLM = "modelAsserted"

    var usesCard: Bool { self == .cardMediated }
    var usesSimpleGentleReflection: Bool { self == .directLLM }
}

/// Counterbalanced order for the two-session crossover. Swift owns use of this value; the model
/// never receives it or decides a participant's condition.
enum StudySequence: String, Codable, CaseIterable {
    case cardFirst, directFirst

    func condition(for period: Int) -> ExperimentalCondition? {
        switch (self, period) {
        case (.cardFirst, 1), (.directFirst, 2): return .cardMediated
        case (.directFirst, 1), (.cardFirst, 2): return .directLLM
        default: return nil
        }
    }
}

enum MessageRole: String, Codable { case assistant, user, system }

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let createdAt: Date
    let state: ReflectionState?
    /// Persisted turn linkage makes retries and resumed sessions idempotent: one typed user turn
    /// may own at most one visible assistant message.
    let replyToMessageID: UUID?
    let assistantGenerationID: UUID?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        state: ReflectionState? = nil,
        replyToMessageID: UUID? = nil,
        assistantGenerationID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.state = state
        self.replyToMessageID = replyToMessageID
        self.assistantGenerationID = assistantGenerationID
    }
}

enum ReflectionDimension: String, Codable, CaseIterable {
    case event, emotion, body, selfJudgment, personalMeaning, context, uncertainty, agency, readiness, cardNarrative
}

enum QuestionGoal: String, Codable, CaseIterable {
    case specificEvent, emotionalMeaning, bodilyExperience, selfTalk, contextualPressure
    case uncertainty, pastChoice, presentAgency, preferredDirection
    /// `cardNarrative` is retained for previously saved sessions. New sessions distinguish the
    /// observable-picture turn from the dynamic-picture turn.
    case cardNarrative, cardObservation, cardDevelopment, cardConnection
    case trackingRelevance, trackingImpact, perspectiveShift, compassionateAction
}

/// One semantic purpose for the next visible response. The Analyzer proposes this plan from the
/// latest user turn; Swift validates its literal evidence and phase permissions before the Writer
/// can see it. These are dialogue functions, not topics, diagnoses, or workflow transitions.
enum ResponseFunction: String, Codable, CaseIterable, Sendable {
    case exploreLivedExperience
    case clarifyPersonalMeaning
    case clarifyCircumstances
    case synthesizeTenderUnderstanding
    case contextualizeTracking
    case developImageRelation
    case connectImageToReality
    case deepenTenderUnderstanding
    case explorePerspectiveShift
    case exploreAgencyBoundaryOrChange
    case synthesizeNarrative
    case proposePractice
    case confirmUnderstanding
    case closeWithoutQuestion
}

struct ResponsePlan: Codable, Equatable, Sendable {
    var function: ResponseFunction
    /// A compact semantic focus for the Writer. It is internal and must not be copied verbatim.
    var focus: String
    /// Short literal fragments copied from user messages. Swift verifies every fragment.
    var evidence: [String]
    /// Relation functions the plan claims to use. Swift requires locally grounded matches.
    var relationKinds: [SemanticRelationKind]
    /// What the one optional question should accomplish, not the wording of the question.
    var questionIntent: String
    var shouldAskQuestion: Bool
    var confidence: Double

    var validated: ResponsePlan {
        var copy = self
        copy.focus = String(focus.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        copy.evidence = Array(
            evidence
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 120 }
                .prefix(4)
        )
        copy.relationKinds = Array(Set(relationKinds).prefix(5))
        copy.questionIntent = String(
            questionIntent.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220)
        )
        copy.confidence = min(max(confidence, 0), 1)
        return copy
    }
}

/// Swift supplies this boundary only for a turn whose wording needs to understand the latest
/// user message. It does not authorize a transition or expose internal workflow names to the UI.
/// Fixed system notices, safety handling, experimental-condition gates, tracking confirmation,
/// and state progression do not use this planning context.
struct ResponsePlanningContext: Codable, Equatable, Sendable {
    var state: ReflectionState
    var workflowPhase: ReflectionWorkflowPhase
    var allowedFunctions: [ResponseFunction]
    var shouldAskQuestion: Bool?

    var validated: ResponsePlanningContext {
        var copy = self
        copy.allowedFunctions = Array(Set(allowedFunctions)).sorted { $0.rawValue < $1.rawValue }
        return copy
    }
}

enum CardPreference: String, Codable {
    case available, deferred, declined, completed
}

enum CardDisplayState: String, Codable {
    case none, selected, displayed, loadFailed
}

struct DialogueProgress: Codable, Equatable {
    var currentState: ReflectionState = .welcome
    var completedDimensions: Set<ReflectionDimension> = []
    var unresolvedDimensions: Set<ReflectionDimension> = Set(ReflectionDimension.allCases)
    var recentQuestionGoals: [QuestionGoal] = []
    /// Optional for additive decoding of sessions saved before cumulative function tracking.
    var askedQuestionGoals: Set<QuestionGoal>?
    var lastAssistantQuestion: String?
    var nextQuestionGoal: QuestionGoal?
    var forbiddenNextGoals: Set<QuestionGoal> = []
    var cardPreference: CardPreference = .available
    var continueConversation = true

    mutating func record(questionGoal: QuestionGoal?, question: String?) {
        if let questionGoal {
            recentQuestionGoals.append(questionGoal)
            recentQuestionGoals = Array(recentQuestionGoals.suffix(3))
            var asked = askedQuestionGoals
                ?? forbiddenNextGoals.union(Set(recentQuestionGoals))
            asked.insert(questionGoal)
            askedQuestionGoals = asked
            forbiddenNextGoals = asked
            nextQuestionGoal = nil
        }
        if let question, !question.isEmpty { lastAssistantQuestion = question }
    }

    mutating func complete(_ dimension: ReflectionDimension) {
        completedDimensions.insert(dimension)
        unresolvedDimensions.remove(dimension)
    }
}

struct ContextCanvas: Codable, Equatable {
    var narrative = ""
    var eventDate = Date()
    var event = ""
    var experience = ""
    var meaning = ""
    var constraints = ""
    var agencyAndUncertainty = ""
    var reflectiveIntention = ""
    var contextualFactors = ""

    var reported: String {
        [narrative, event, experience, meaning, constraints, agencyAndUncertainty, reflectiveIntention]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    var uncertainty: String { agencyAndUncertainty }
}

struct ReflectionContext: Codable, Equatable {
    var eventDescription: String?
    var eventDate = Date()
    var emotions: [String] = []
    var bodilyResponses: [String] = []
    var selfJudgment: String?
    /// User-authored personal meaning is separate from a global self-label so later summaries can
    /// keep the concern while translating identity judgments into situation-specific language.
    var personalMeaning: String?
    var contextualConstraints: [String] = []
    var personalContributions: [String] = []
    var uncertainties: [String] = []
    var pastControllability: ControllabilityLevel = .unknown
    var presentAgency: AgencyLevel = .unknown
    var possibleImpactOnOthers: [String] = []
    var possibleBoundaryConcerns: [String] = []
    var unmetNeeds: [String] = []
    var repeatingPatterns: [String] = []
    var confirmedTrackingCues: [TrackingCue] = []
    var rejectedTrackingCueIDs: Set<String> = []
    var confirmedTrackingInsights: [ConfirmedTrackingContext]?
    var selectedCardID: String?
    var cardInterpretation: String?
    var selectedAction: CompassionateAction?

    var narrativeSummary: String {
        var parts: [String] = []
        if let eventDescription, !eventDescription.isEmpty { parts.append(eventDescription) }
        if !emotions.isEmpty { parts.append("感受：" + emotions.joined(separator: "、")) }
        if !bodilyResponses.isEmpty { parts.append("身体反应：" + bodilyResponses.joined(separator: "、")) }
        if let selfJudgment, !selfJudgment.isEmpty { parts.append("当时对自己的判断：" + selfJudgment) }
        if let personalMeaning, !personalMeaning.isEmpty { parts.append("这件事对自己的意义：" + personalMeaning) }
        if !contextualConstraints.isEmpty { parts.append("情境限制：" + contextualConstraints.joined(separator: "、")) }
        if !uncertainties.isEmpty { parts.append("仍不确定：" + uncertainties.joined(separator: "、")) }
        return parts.joined(separator: "\n")
    }

    init() {}

    init(legacy: ContextCanvas) {
        eventDescription = legacy.event.isEmpty ? (legacy.narrative.isEmpty ? nil : legacy.narrative) : legacy.event
        eventDate = legacy.eventDate
        emotions = legacy.experience.isEmpty ? [] : [legacy.experience]
        bodilyResponses = []
        selfJudgment = legacy.meaning.isEmpty ? nil : legacy.meaning
        personalMeaning = nil
        contextualConstraints = legacy.constraints.isEmpty ? [] : [legacy.constraints]
        personalContributions = []
        uncertainties = legacy.agencyAndUncertainty.isEmpty ? [] : [legacy.agencyAndUncertainty]
        pastControllability = .unknown
        presentAgency = .unknown
        possibleImpactOnOthers = []
        possibleBoundaryConcerns = []
        unmetNeeds = legacy.reflectiveIntention.isEmpty ? [] : [legacy.reflectiveIntention]
        repeatingPatterns = []
        confirmedTrackingCues = []
        rejectedTrackingCueIDs = []
        cardInterpretation = nil
        selectedAction = nil
    }
}

enum TrackingSource: String, Codable {
    case healthSleep, healthHeartRate, healthHRV, healthSteps, calendarLoad
}

enum TrackingMetric: String, Codable, CaseIterable {
    case sleepDuration, sleepTiming, sleepWakeTime, sleepContinuity
    case restingHeartRate, heartRateVariability, steps
    case calendarLoad, screenTime, weather
}

enum TrackingInsightStrength: String, Codable {
    case descriptiveOnly, baselineComparison, persistentPattern
}

enum TrackingInsightConfidence: String, Codable {
    case low, moderate, high
}

struct TrackingProvenance: Codable, Equatable {
    var sampleType: String
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var sourceVersion: String?
    var deviceName: String?
    var startDate: Date?
    var endDate: Date?
    var timeZoneIdentifier: String
    var sampleCount: Int
    var authorizationStatus: String
}

enum TrackingCueRelevance: String, Codable, CaseIterable, Sendable {
    /// The cue was made available in dialogue but the person has not related it to the event.
    /// It remains ineligible for the final narrative.
    case notReviewed, offered, reviewedNotUsed, relevant, irrelevant, uncertain
}

/// Exact identity of the one compact Tracking metric actually presented in current-v5 dialogue.
/// It contains no values or interpretation; it binds the later user relationship to the same cue.
struct ContextualTrackingMetricIdentity: Codable, Equatable, Hashable, Sendable {
    let profileID: String
    let metric: String
}

/// A deliberately coarse interpretation of several tracking deviations. It is not a measured
/// psychological stress level and is never used to name a specific emotion.
enum ContextualLoadState: String, Codable, Sendable {
    /// Current-v5 lifecycle holder only: no local contextual interpretation was performed.
    case notAssessed
    case insufficientEvidence
    case usualRange
    case recordedScheduleContext
    case possibleReducedRecovery
    case possiblyElevated
    case elevated
}

enum ContextualLoadConfidence: String, Codable, Sendable {
    /// Current-v5 does not assign confidence to a contextual interpretation.
    case notAssessed
    case low
    case moderate
    case high
}

enum ContextualActivationState: String, Codable, Sendable {
    case unknown
    case possiblyElevated
}

enum ContextualEnergyState: String, Codable, Sendable {
    case unknown
    case possiblyReduced
}

/// Legacy research/debug representation retained for saved-session compatibility. Current-v5 does
/// not use `dialogueHypothesis`: it sends cleaned aggregates and their limitations to the Planner,
/// which decides whether they add useful context and leaves the Writer to phrase any reveal.
/// Valence and emotion labels are intentionally absent: sleep, activity, heart rate and HRV cannot
/// distinguish anxiety, sadness, anger, excitement, or another specific feeling.
struct ContextualLoadInference: Codable, Equatable {
    let state: ContextualLoadState
    let confidence: ContextualLoadConfidence
    let activation: ContextualActivationState
    let energy: ContextualEnergyState
    let observationWindow: DateInterval?
    let supportingInsightIDs: [UUID]
    let supportingMetrics: [TrackingMetric]
    let alternativeExplanations: [String]
    let dialogueHypothesis: String?
    var relevance: TrackingCueRelevance
    /// Additive current-v5 provenance. Eligibility classifications remain turn-local; only the
    /// identity of the metric that was actually shown survives for the following relation turn.
    var presentedMetricIdentity: ContextualTrackingMetricIdentity? = nil

    var hasDialogueCue: Bool {
        guard ![.notAssessed, .low].contains(confidence),
              let dialogueHypothesis else { return false }
        return !dialogueHypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Legacy-only typed interface retained for saved-session dialogue compatibility. Current-v5 does
/// not construct this cue or grant its locally authored hypothesis any Planner/Writer authority.
struct DialogueContextCue: Codable, Equatable, Sendable {
    let hypothesis: String
    let confidence: ContextualLoadConfidence
    let relevance: TrackingCueRelevance
    let usageBoundary: String
}

struct TrackingDataPoint: Identifiable, Codable, Equatable {
    let date: Date
    let value: Double?
    let count: Int

    var id: Date { date }
}

struct TrackingInsight: Identifiable, Codable, Equatable {
    let id: UUID
    let metric: TrackingMetric
    let observationWindow: DateInterval
    let validSampleCount: Int
    let expectedSampleCount: Int
    let coverageDescription: String
    let neutralObservation: String
    let baselineWindow: DateInterval?
    let baselineDescription: String?
    let absoluteDifference: Double?
    let relativeDifference: Double?
    let strength: TrackingInsightStrength
    let confidence: TrackingInsightConfidence
    let limitations: [String]
    let possibleConfounders: [String]
    let suggestedReflectionQuestion: String
    let provenance: [TrackingProvenance]
    let recentMedian: Double?
    /// Direct recent-window totals. They are currently populated for calendar occupancy so that
    /// a schedule can be described from its own count and duration instead of a personal baseline.
    /// Optional defaults keep previously stored insights decodable.
    var recentTotal: Double? = nil
    var recentRecordCount: Int? = nil
    let baselineMedian: Double?
    let medianAbsoluteDeviation: Double?
    let interquartileRange: Double?
    let longestConsecutiveRun: Int
    var userRelevance: TrackingCueRelevance
    /// Additive factual snapshots used by the current-v5 input projection. These are cleaned
    /// daily aggregates, never raw HealthKit/EventKit samples. Optional defaults keep sessions
    /// saved before temporal profiles were introduced decodable.
    var recentDailyPoints: [TrackingDataPoint]? = nil
    var factualBaselineMedian: Double? = nil
    var baselineObservedDays: Int? = nil
    var baselineExpectedDays: Int? = nil
}

struct ConfirmedTrackingContext: Codable, Equatable {
    let insightID: UUID
    let observation: String
    let userInterpretation: String?
    let relevance: TrackingCueRelevance
}

struct PatternCandidate: Identifiable, Codable, Equatable {
    let id: UUID
    let observedFeatures: [String]
    let observationWindows: [DateInterval]
    let coverage: [String]
    let limitations: [String]
    let alternativeExplanations: [String]
    let suggestedReflectionQuestion: String
}

struct SelfTrackingDataset: Codable, Equatable {
    var dailyMetrics: [TrackingMetric: [TrackingDataPoint]]
    var provenance: [TrackingMetric: [TrackingProvenance]]
}

struct SelfTrackingAnalysis: Codable, Equatable {
    var insights: [TrackingInsight]
    var patternCandidates: [PatternCandidate]
}

struct TrackingMetrics: Codable, Equatable {
    let periodStart: Date
    let periodEnd: Date
    let summaryValue: Double?
    let unit: String
    let sampleCount: Int
    let daily: [TrackingDataPoint]
    /// Optional factual dimensions derived from the same cleaned source. Current-v5 can expose
    /// them as separate temporal series without sending titles, samples, or a quality judgment.
    var supplementalSeries: [TrackingSupplementalSeries]? = nil
}

struct TrackingSupplementalSeries: Codable, Equatable {
    let metric: String
    let unit: String
    let daily: [TrackingDataPoint]
}

struct TrackingCue: Identifiable, Codable, Equatable {
    let id: String
    let source: TrackingSource
    let neutralDescription: String
    let startDate: Date?
    let endDate: Date?
    var relevance: TrackingCueRelevance
    var metrics: TrackingMetrics?
    var insight: TrackingInsight?

    init(
        id: String = UUID().uuidString,
        source: TrackingSource,
        observation: String,
        included: Bool = false,
        metrics: TrackingMetrics? = nil,
        insight: TrackingInsight? = nil
    ) {
        self.id = id
        self.source = source
        neutralDescription = observation
        startDate = metrics?.periodStart ?? insight?.observationWindow.start
        endDate = metrics?.periodEnd ?? insight?.observationWindow.end
        relevance = included ? .relevant : .notReviewed
        self.metrics = metrics
        self.insight = insight
    }

    var observation: String { neutralDescription }
    var included: Bool {
        get { relevance == .relevant }
        set { relevance = newValue ? .relevant : .irrelevant }
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, neutralDescription, observation, startDate, endDate, relevance, included, metrics, insight
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decode(String.self, forKey: .id)) ?? UUID().uuidString
        source = try box.decode(TrackingSource.self, forKey: .source)
        neutralDescription = (try? box.decode(String.self, forKey: .neutralDescription))
            ?? (try? box.decode(String.self, forKey: .observation))
            ?? "未命名记录"
        metrics = try? box.decodeIfPresent(TrackingMetrics.self, forKey: .metrics)
        insight = try? box.decodeIfPresent(TrackingInsight.self, forKey: .insight)
        startDate = (try? box.decodeIfPresent(Date.self, forKey: .startDate)) ?? metrics?.periodStart
        endDate = (try? box.decodeIfPresent(Date.self, forKey: .endDate)) ?? metrics?.periodEnd
        if let decoded = try? box.decode(TrackingCueRelevance.self, forKey: .relevance) {
            relevance = decoded
        } else {
            relevance = (try? box.decode(Bool.self, forKey: .included)) == true ? .relevant : .notReviewed
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(source, forKey: .source)
        try box.encode(neutralDescription, forKey: .neutralDescription)
        try box.encodeIfPresent(startDate, forKey: .startDate)
        try box.encodeIfPresent(endDate, forKey: .endDate)
        try box.encode(relevance, forKey: .relevance)
        try box.encodeIfPresent(metrics, forKey: .metrics)
        try box.encodeIfPresent(insight, forKey: .insight)
    }
}

/// One application-owned bundle of cleaned cues shown together in a single assistant reply.
/// The LLM may resolve the bundle as a whole; Swift binds that decision to these exact cue IDs.
struct TurnTrackingPresentation: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let cueIDs: [String]
    let presentedAtUserTurnID: UUID?
    var resolution: TurnConfirmationDecision?

    init(
        id: String = UUID().uuidString,
        cueIDs: [String],
        presentedAtUserTurnID: UUID?,
        resolution: TurnConfirmationDecision? = nil
    ) {
        self.id = id
        self.cueIDs = cueIDs
        self.presentedAtUserTurnID = presentedAtUserTurnID
        self.resolution = resolution
    }
}

/// An image-only prompt that may help when the person has described a card but cannot yet
/// connect it with their life. Every anchor group must be present in the person's own picture
/// narrative before the question can be shown. This deliberately keeps card semantics out of
/// the visible prompt.
struct CardVisualScaffold: Codable, Equatable, Hashable, Sendable {
    let requiredAnchorGroups: [[String]]
    let question: String
}

/// Card-owned metadata stops at visible composition. `observableRelation` records what the
/// designer can point to in the picture; it is never a psychological target interpretation.
struct CardVisualGuidance: Codable, Equatable {
    let observableRelation: String
    let visualAnchors: [String]
    let prohibitedClaims: [String]
    let visualScaffolds: [CardVisualScaffold]

    init(
        observableRelation: String,
        visualAnchors: [String],
        prohibitedClaims: [String],
        visualScaffolds: [CardVisualScaffold] = []
    ) {
        self.observableRelation = observableRelation
        self.visualAnchors = visualAnchors
        self.prohibitedClaims = prohibitedClaims
        self.visualScaffolds = visualScaffolds
    }
}

/// A small set of reality-translated Major Arcana relationships. These are closed reference
/// lenses, not default card meanings or user facts. The app withholds this object until the
/// person has established an image relation and an image-to-life mapping. It is available only as
/// an Exploratory Planner question lens when Card development, the canonical connection, and the
/// current episode support the same relationship. It is never grounded evidence, Writer content,
/// a Tender/Fierce premise, synthesis material, final narrative content, or an action source.
struct CardReferenceGuidance: Codable, Equatable, Sendable {
    let relations: [String]
    let activationBoundary: String
    let prohibitedClaims: [String]
}

/// Tender and Fierce are system-wide response methods. They operate on the person's own
/// interpretation and confirmed evidence; no card selects a private Tender or Fierce meaning.
struct SystemReflectionApproaches: Codable, Equatable {
    let tender: String
    let fierce: String

    static let standard = SystemReflectionApproaches(
        tender: "从用户已经确认的画面解释和现实描述出发，更具体、更少评判地理解处境、感受、限制和需要；不补充牌义。",
        fierce: "仅在用户愿意且已有事实支持时，邀请进一步观察选择、影响、责任、边界或行动；不把画面当成这些判断的证据。"
    )
}

/// A deterministic, locally-computed grounding between the person's image relation and confirmed
/// reality relation. It records user evidence only and contains no designer meaning or card lens.
struct CardGroundingMatch: Codable, Equatable {
    let matchedVisualAnchors: [String]
    let imageRelation: String?
    let realityRelation: String?
    let matchedConcepts: [SemanticConcept]?

    init(
        matchedVisualAnchors: [String],
        imageRelation: String? = nil,
        realityRelation: String? = nil,
        matchedConcepts: [SemanticConcept]? = nil
    ) {
        self.matchedVisualAnchors = matchedVisualAnchors
        self.imageRelation = imageRelation
        self.realityRelation = realityRelation
        self.matchedConcepts = matchedConcepts
    }
}

/// Decode only the visually safe subset of sessions written before card meaning and visual
/// composition were separated. Legacy core/tender/fierce fields are intentionally ignored.
private struct LegacyCardReflectionGuidance: Decodable {
    let visualAnchors: [String]
    let prohibitedClaims: [String]
    let visualScaffolds: [CardVisualScaffold]?
}

struct ReflectionCard: Identifiable, Codable, Equatable {
    let id: Int
    /// Kept neutral for model prompts so a title cannot become an explanation before the user
    /// describes the image.
    let neutralLabel: String
    /// User-visible card name. Older saved sessions safely fall back to their neutral label.
    let title: String
    let imageName: String
    /// Retained only so stored research sessions continue to round-trip. Runtime prompts never
    /// read this former theme field.
    let reflectiveThemes: String
    let visualGuidance: CardVisualGuidance?
    let referenceGuidance: CardReferenceGuidance?

    init(
        id: Int,
        neutralLabel: String,
        title: String? = nil,
        imageName: String,
        reflectiveThemes: String = "",
        visualGuidance: CardVisualGuidance? = nil,
        referenceGuidance: CardReferenceGuidance? = nil
    ) {
        self.id = id
        self.neutralLabel = neutralLabel
        self.title = title ?? neutralLabel
        self.imageName = imageName
        self.reflectiveThemes = reflectiveThemes
        self.visualGuidance = visualGuidance
        self.referenceGuidance = referenceGuidance
    }

    enum CodingKeys: String, CodingKey {
        case id, neutralLabel, title, imageName, reflectiveThemes, visualGuidance
        case referenceGuidance
        case internalGuidance
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(Int.self, forKey: .id)
        neutralLabel = try box.decode(String.self, forKey: .neutralLabel)
        title = (try? box.decode(String.self, forKey: .title)) ?? neutralLabel
        let decodedImageName = try box.decode(String.self, forKey: .imageName)
        // Sessions created before the revised artwork used the provisional resource name.
        // Keep those sessions intact while showing the current card image after restoration.
        imageName = decodedImageName == "旧模与新形" ? "传下来的图样" : decodedImageName
        reflectiveThemes = (try? box.decode(String.self, forKey: .reflectiveThemes)) ?? ""
        if let current = try? box.decodeIfPresent(CardVisualGuidance.self, forKey: .visualGuidance) {
            visualGuidance = current
        } else if let legacy = try? box.decodeIfPresent(
            LegacyCardReflectionGuidance.self,
            forKey: .internalGuidance
        ) {
            visualGuidance = CardVisualGuidance(
                observableRelation: "",
                visualAnchors: legacy.visualAnchors,
                prohibitedClaims: legacy.prohibitedClaims,
                visualScaffolds: legacy.visualScaffolds ?? []
            )
        } else {
            visualGuidance = nil
        }
        referenceGuidance = try? box.decodeIfPresent(
            CardReferenceGuidance.self,
            forKey: .referenceGuidance
        )
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(neutralLabel, forKey: .neutralLabel)
        try box.encode(title, forKey: .title)
        try box.encode(imageName, forKey: .imageName)
        try box.encode(reflectiveThemes, forKey: .reflectiveThemes)
        try box.encodeIfPresent(visualGuidance, forKey: .visualGuidance)
        try box.encodeIfPresent(referenceGuidance, forKey: .referenceGuidance)
    }
}

struct CardDrawRecord: Codable, Equatable {
    let sessionID: UUID
    let cardID: String
    let drawnAt: Date
    let routeBeforeDraw: CompassionRoute
}

struct StudyEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let stage: ReflectionStage
    let action: String

    init(id: UUID = UUID(), timestamp: Date = .now, stage: ReflectionStage, action: String) {
        self.id = id; self.timestamp = timestamp; self.stage = stage; self.action = action
    }
}

struct StudyMeasures: Codable, Equatable {
    var feltUnderstood = 4.0
    var compassionateCandor = 4.0
    var reactance = 4.0
    var responsibilityClarity = 4.0
    var interpretationOwnership = 4.0
    var cardFamiliarity = 1.0
}

enum HypothesisStatus: String, Codable { case pending, kept, revised, setAside }

struct Hypothesis: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var status: HypothesisStatus

    init(id: UUID = UUID(), text: String, status: HypothesisStatus = .pending) {
        self.id = id; self.text = text; self.status = status
    }
}

enum CompassionateActionCategory: String, Codable, CaseIterable {
    case care, protect, provide, repair, change

    var title: String {
        switch self {
        case .care: "先照顾自己"
        case .protect: "保护一点边界"
        case .provide: "补一点支持"
        case .repair: "修复一次沟通"
        case .change: "试一个小改变"
        }
    }
}

/// Internal support direction selected by Swift after semantic evidence has been validated.
/// `noAction` is a valid outcome and is intentionally not persisted as a user action.
enum CompassionatePracticeDirection: String, Equatable {
    case care
    case repair
    case protection
    case change
    case noAction

    var actionCategory: CompassionateActionCategory? {
        switch self {
        case .care: return .care
        case .repair: return .repair
        case .protection: return .protect
        case .change: return .change
        case .noAction: return nil
        }
    }
}

struct CompassionateAction: Codable, Equatable {
    var category: CompassionateActionCategory
    var description: String
    var timing: String?
    var acceptedByUser: Bool
}

struct ActionSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let category: CompassionateActionCategory
    let description: String
    let timing: String?
    let rationale: String

    init(
        id: UUID = UUID(),
        category: CompassionateActionCategory,
        description: String,
        timing: String? = nil,
        rationale: String
    ) {
        self.id = id
        self.category = category
        self.description = description
        self.timing = timing
        self.rationale = rationale
    }
}

/// A domain-neutral relation extracted from the person's own words. These values describe how
/// already supplied pieces of evidence relate; they never authorize a workflow transition by
/// themselves. Swift validates the literal evidence before using a relation at a later gate.
enum SemanticRelationKind: String, Codable, CaseIterable, Sendable {
    case eventExperience
    case conditionCapacity
    case behaviorImpact
    case selfEvaluation
    case boundaryNeed
    case controllablePart
    case uncertainty
    case imageStructure
    case realityStructure
    case imageRealityMapping
    case meaningShift
    case sharedHumanity
    case unmetNeed
}

enum SemanticEvidenceStatus: String, Codable {
    case userStated
    case userConfirmed
    case tentative
    case rejected
}

/// A small shared ontology lets the Analyzer describe a relation without classifying the user into
/// a scenario such as “paper”, “family”, or “breakup”. Card metadata may intersect these concepts
/// only after a user-grounded image-to-reality mapping has been confirmed.
enum SemanticConcept: String, Codable, CaseIterable {
    case uncertainty
    case action
    case avoidance
    case preparation
    case rest
    case recovery
    case stagnation
    case responsibility
    case boundary
    case sharing
    case support
    case constraint
    case protection
    case control
    case shame
    case repair
    case communication
    case pattern
    case change
    case safety
    case lettingGo
    case loss
    case choice
    case ability
    case perfectionism
    case problemSolving
    case resources
    case overload
    case relationship
    case judgment
    case selfEvaluation
    case facts
    case commonHumanity
    case connection
    case isolation
    case autonomy
    case planning
    case priority
    case flexibility
}

struct SemanticRelation: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: SemanticRelationKind
    var source: String
    var relation: String
    var target: String
    var concepts: [SemanticConcept] = []
    var evidence: [String] = []
    var status: SemanticEvidenceStatus = .tentative
    var confidence = 0.0

    private enum CodingKeys: String, CodingKey {
        case id, kind, source, relation, target, concepts, evidence, status, confidence
    }

    init(
        id: UUID = UUID(),
        kind: SemanticRelationKind,
        source: String,
        relation: String,
        target: String,
        concepts: [SemanticConcept] = [],
        evidence: [String] = [],
        status: SemanticEvidenceStatus = .tentative,
        confidence: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.relation = relation
        self.target = target
        self.concepts = concepts
        self.evidence = evidence
        self.status = status
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = try box.decode(SemanticRelationKind.self, forKey: .kind)
        source = (try? box.decode(String.self, forKey: .source)) ?? ""
        relation = (try? box.decode(String.self, forKey: .relation)) ?? ""
        target = (try? box.decode(String.self, forKey: .target)) ?? ""
        concepts = (try? box.decode([SemanticConcept].self, forKey: .concepts)) ?? []
        evidence = (try? box.decode([String].self, forKey: .evidence)) ?? []
        status = (try? box.decode(SemanticEvidenceStatus.self, forKey: .status)) ?? .tentative
        confidence = (try? box.decode(Double.self, forKey: .confidence)) ?? 0
    }
}

struct ContextAnalysis: Codable, Equatable {
    var safetyOverride = false
    var distressLevel = 0
    var selfAttackLevel = 0
    var reflectiveCapacity = 1
    var behaviorIdentitySeparation = 0
    var multipleExplanationsCapacity = 0
    var consentToCandor: ConsentState = .unknown
    var eventType: ReflectionEventType = .unclear
    var taskProgressStatus: TaskProgressStatus = .notApplicable
    /// True only when the person themselves has named a concrete action, omission, impact, or
    /// boundary—not when the analyzer merely sees distress or a global self-label.
    var userAdmittedBehavior = false
    var confirmedBehavior: String?
    /// Short literal fragments from the user message(s) that support the semantic candidates.
    /// Swift verifies them against the transcript before using them for a fierce invitation.
    var behaviorEvidence: [String] = []
    var eventDescription: String?
    var emotions: [String] = []
    var bodilyResponses: [String] = []
    var selfJudgment: String?
    var contextualConstraints: [String] = []
    var personalContributions: [String] = []
    var possibleImpactOnOthers: [String] = []
    var possibleBoundaryConcerns: [String] = []
    var possibleUnmetNeeds: [String] = []
    var possibleRepeatingPatterns: [String] = []
    var uncertainties: [String] = []
    var pastControllability: ControllabilityLevel = .unknown
    var presentAgency: AgencyLevel = .unknown
    var recommendedRoute: CompassionRoute = .explore
    var secondaryRoutes: [CompassionRoute] = []
    var reasonCodes: [String] = []
    var missingInformation: [String] = []
    var nextQuestionGoal = "invite one concrete detail"
    /// Optional on disk so reflection sessions saved before semantic relations were introduced
    /// continue to decode. Runtime code should consume `resolvedSemanticRelations`.
    var semanticRelations: [SemanticRelation]?
    /// Optional for additive compatibility with analyses saved before typed response planning.
    /// A plan is never trusted directly; Swift validates it against the transcript and phase.
    var responsePlan: ResponsePlan?
    var confidence = 0.0

    var resolvedSemanticRelations: [SemanticRelation] {
        semanticRelations ?? []
    }

    var validated: ContextAnalysis {
        var copy = self
        copy.distressLevel = min(max(distressLevel, 0), 3)
        copy.selfAttackLevel = min(max(selfAttackLevel, 0), 3)
        copy.reflectiveCapacity = min(max(reflectiveCapacity, 0), 3)
        copy.behaviorIdentitySeparation = min(max(behaviorIdentitySeparation, 0), 3)
        copy.multipleExplanationsCapacity = min(max(multipleExplanationsCapacity, 0), 3)
        copy.confidence = min(max(confidence, 0), 1)
        copy.secondaryRoutes = Array(secondaryRoutes.prefix(3))
        copy.reasonCodes = Array(reasonCodes.prefix(8))
        copy.missingInformation = Array(missingInformation.prefix(8))
        copy.semanticRelations = Array(
            resolvedSemanticRelations.compactMap { relation -> SemanticRelation? in
                var value = relation
                value.source = value.source.trimmingCharacters(in: .whitespacesAndNewlines)
                value.relation = value.relation.trimmingCharacters(in: .whitespacesAndNewlines)
                value.target = value.target.trimmingCharacters(in: .whitespacesAndNewlines)
                value.evidence = Array(
                    value.evidence
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0.count <= 120 }
                        .prefix(3)
                )
                value.concepts = Array(Set(value.concepts).prefix(6))
                value.confidence = min(max(value.confidence, 0), 1)
                guard !value.source.isEmpty,
                      !value.relation.isEmpty,
                      !value.target.isEmpty else { return nil }
                return value
            }.prefix(16)
        )
        copy.responsePlan = responsePlan?.validated
        copy.confirmedBehavior = copy.confirmedBehavior?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.confirmedBehavior?.isEmpty == true { copy.confirmedBehavior = nil }
        copy.behaviorEvidence = Array(
            behaviorEvidence
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 120 }
                .prefix(3)
        )
        // A recommendation without a literal user-supported fragment remains only an uncertain
        // analyzer hypothesis; it cannot unlock a candid responsibility/change question.
        if copy.userAdmittedBehavior && copy.behaviorEvidence.isEmpty {
            copy.userAdmittedBehavior = false
            copy.confirmedBehavior = nil
        }
        return copy
    }

    static func fallback(safetyOverride: Bool = false) -> ContextAnalysis {
        var result = ContextAnalysis()
        result.safetyOverride = safetyOverride
        result.recommendedRoute = safetyOverride ? .tenderStabilize : .explore
        result.uncertainties = ["模型分析暂时不可用，保留当前信息的不确定性"]
        result.nextQuestionGoal = "invite one concrete, easy-to-answer detail"
        return result
    }
}

struct CompassionRouteResolver {
    func resolve(from analysis: ContextAnalysis) -> CompassionRoute {
        let value = analysis.validated
        if value.safetyOverride { return .tenderStabilize }
        if value.consentToCandor != .yes { return .tenderStabilize }
        if value.distressLevel >= 2 && value.selfAttackLevel >= 2 { return .tenderStabilize }
        if value.reflectiveCapacity <= 1 { return .tenderStabilize }

        // Route only from evidence-bearing, domain-neutral relations. Legacy summary arrays remain
        // available for old sessions and prompt context, but cannot independently assign a route.
        let relations = value.resolvedSemanticRelations.filter {
            [.userStated, .userConfirmed].contains($0.status) &&
            $0.confidence >= 0.6 &&
            !$0.evidence.isEmpty
        }
        if relations.contains(where: { $0.kind == .boundaryNeed }) { return .protect }
        if relations.contains(where: {
            $0.kind == .behaviorImpact &&
            ($0.concepts.contains(.repair) || $0.concepts.contains(.responsibility))
        }) {
            return .repair
        }
        if relations.contains(where: { $0.kind == .unmetNeed }) { return .provide }
        if relations.contains(where: {
            $0.kind == .controllablePart ||
            ($0.kind == .behaviorImpact && $0.concepts.contains(.change))
        }) {
            return .change
        }
        return .explore
    }
}

struct ReflectionStateMachine {
    func canTransition(from: ReflectionState, to: ReflectionState) -> Bool {
        if to == .safetySupport { return from != .completed }
        let allowed: [ReflectionState: Set<ReflectionState>] = [
            .welcome: [.eventDisclosure],
            .eventDisclosure: [.emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure, .tenderGrounding, .trackingPermission, .summary],
            .emotionDisclosure: [.bodilyResponse, .selfJudgment, .contextDisclosure, .tenderGrounding, .trackingPermission, .summary],
            .bodilyResponse: [.selfJudgment, .contextDisclosure, .tenderGrounding, .trackingPermission, .summary],
            // `.bodilyResponse` is a recovery edge for legacy sessions saved after self-talk but
            // before the new body-depth gate existed. New sessions still reach body first.
            .selfJudgment: [.bodilyResponse, .contextDisclosure, .tenderGrounding, .trackingPermission, .summary],
            // Recovery edges let an additive schema migration deepen an older session that had
            // already reached context before the body/personal-meaning layers were introduced.
            // New sessions still follow the forward-only disclosure order above.
            .contextDisclosure: [.bodilyResponse, .selfJudgment, .tenderGrounding, .trackingPermission, .summary],
            .trackingPermission: [.trackingReview, .tenderGrounding, .readinessCheck, .summary],
            .trackingReview: [.tenderGrounding, .readinessCheck, .summary],
            .tenderGrounding: [.trackingPermission, .trackingReview, .readinessCheck, .summary],
            .readinessCheck: [.tenderGrounding, .tenderExploration, .trackingReview, .cardIntroduction, .attributionReflection, .summary],
            .tenderExploration: [.readinessCheck, .summary],
            .cardIntroduction: [.cardInterpretation, .summary],
            .cardInterpretation: [.attributionReflection, .tenderExploration, .summary],
            .attributionReflection: [.tenderExploration, .actionSelection, .summary],
            .actionSelection: [.summary],
            .summary: [.completed],
            .completed: [],
            .safetySupport: [.completed],
        ]
        return allowed[from, default: []].contains(to)
    }

    func nextDisclosureState(after state: ReflectionState) -> ReflectionState? {
        switch state {
        case .eventDisclosure: .emotionDisclosure
        case .emotionDisclosure: .bodilyResponse
        case .bodilyResponse: .selfJudgment
        case .selfJudgment: .contextDisclosure
        case .contextDisclosure: .trackingPermission
        default: nil
        }
    }
}

struct AdaptiveDisclosureResolver {
    func nextState(after state: ReflectionState, context: ReflectionContext) -> ReflectionState? {
        switch state {
        case .eventDisclosure:
            // Tracking should not enter merely because one opening message happens to contain a
            // judgment and a practical constraint. First make sure the person's lived experience
            // is clear enough in their own words; if it already is, skip only that redundant layer.
            if context.emotions.isEmpty { return .emotionDisclosure }
            if context.bodilyResponses.isEmpty { return .bodilyResponse }
            if context.personalMeaning?.isEmpty != false { return .selfJudgment }
            return context.contextualConstraints.isEmpty ? .contextDisclosure : .trackingPermission
        case .emotionDisclosure:
            if context.bodilyResponses.isEmpty { return .bodilyResponse }
            if context.personalMeaning?.isEmpty != false { return .selfJudgment }
            return context.contextualConstraints.isEmpty ? .contextDisclosure : .trackingPermission
        case .bodilyResponse:
            if context.personalMeaning?.isEmpty != false { return .selfJudgment }
            return context.contextualConstraints.isEmpty ? .contextDisclosure : .trackingPermission
        case .selfJudgment:
            return context.contextualConstraints.isEmpty ? .contextDisclosure : .trackingPermission
        case .contextDisclosure:
            return .trackingPermission
        default:
            return nil
        }
    }
}

struct ReflectionSession: Identifiable, Codable {
    /// Protocol 3 introduced the typed interaction contract used by later card and practice
    /// operations. Protocol 4 consolidated the TurnController runtime. Protocol 5 adds the typed
    /// reflection action and makes the existing optional-action node precede the final narrative.
    static let structuredTurnProtocolVersion = 3
    static let consolidatedTurnProtocolVersion = 4
    static let actionFirstReflectionProtocolVersion = 5
    static let currentProtocolVersion = actionFirstReflectionProtocolVersion
    static let simpleGentleControlProtocolVersion = 3

    var id = UUID()
    var createdAt = Date()
    var stage: ReflectionState = .welcome
    /// New sessions use the coarse LLM TurnController protocol. A decoded value of 1 preserves the
    /// exact behavior of older in-progress sessions instead of migrating their meaning mid-turn.
    var protocolVersion = 1
    var protocolStage: ReflectionProtocolStage = .contextualDisclosure
    var reflectionReadiness: ReflectionReadiness = .needsTender
    var semanticMemory = TurnSemanticMemory()
    var presentedTrackingCueIDs: Set<String> = []
    var trackingPresentations: [TurnTrackingPresentation] = []
    var activeTrackingPresentationID: String?
    var cardGuidanceShared = false
    /// Persisted between the silent mapping/guidance transaction and its one visible successor.
    /// If the app is suspended in that narrow window, resume restarts only the visible turn and
    /// never repeats the mapping patch or local capability operation.
    var pendingCardGuidanceTurn = false
    /// Stable idempotency key for the last committed card-guidance authorization. It is derived
    /// from the persisted user-message ID, never from reflection text.
    var cardGuidanceTransactionID: String?
    var condition: ExperimentalCondition = .cardMediated
    /// Nil marks a pre-study/ordinary reflection. These additive fields distinguish deliberate
    /// crossover periods from historical card-mediated sessions.
    var studySequence: StudySequence?
    var studyPeriod: Int?
    /// `eventDate` is only treated as an event-time tracking anchor when the person explicitly
    /// supplied a date or relative day. Otherwise it remains the session reference and visible
    /// language stays at “最近 / 这段时间”.
    var eventDateIsUserSpecified = false
    var messages: [ChatMessage] = []
    /// Assistant interpretations that the person rejected or replaced remain in the persisted
    /// transcript for research audit, but are excluded from all later model evidence. This is an
    /// application-owned provenance boundary, not an LLM judgment about conversational meaning.
    var supersededAssistantMessageIDs: Set<UUID> = []
    var context = ReflectionContext()
    var trackingCues: [TrackingCue] = []
    var contextualLoadInference: ContextualLoadInference?
    var trackingUseDeclined = false
    var pendingTrackingCueID: String?
    /// A review can contain several cleaned cues from distinct domains. The singular field stays
    /// for migration and mirrors the first pending cue in new sessions.
    var pendingTrackingCueIDs: [String] = []
    var card: ReflectionCard?
    var cardDrawRecord: CardDrawRecord?
    var cardWasSetAside = false
    var cardDisplayState: CardDisplayState = .none
    var cardDisplayReloadNonce = 0
    var workflowPhase: ReflectionWorkflowPhase = .opening
    /// Number of assistant turns that invited or continued structured disclosure. The opening
    /// invitation counts as the first turn; Swift exits after 3 sufficient turns and always by 5.
    var structuredDisclosureAssistantTurns = 0
    var bodyExplorationCompleted = false
    var personalMeaningExplorationCompleted = false
    var hasAskedPersonalMeaningQuestion = false
    var tenderGroundingRevisionCount = 0
    var tenderGroundingConfirmed = false
    var trackingReviewCompleted = false
    var trackingReviewUnavailable = false
    var trackingContextLinkCompleted = false
    var trackingContextLinkResponse: String?
    var contextConfirmationRevisionCount = 0
    var contextSummaryConfirmed = false
    /// The synthesis confirmed after disclosure and tracking. Card narration treats this as a
    /// locked baseline and may reference it briefly, but cannot rebuild it field by field.
    var lockedBaselineNarrative: String?
    /// Number of committed image-development prompts before the first image-to-life invitation.
    /// Current sessions permit at most one relational clarification and one temporal projection;
    /// this is a protocol counter, not an interpretation of the person's words.
    var cardImageDevelopmentTurnCount = 0
    var cardConnectionAttemptCount = 0
    /// Protocol-v2 capability flag. Once true, neither a second visual scaffold nor another
    /// guidance-based bridge may be requested for the same card connection.
    var cardConnectionScaffoldUsed = false
    /// True only while the app is waiting for one image-structure answer after the user's first
    /// soft “想不到”. That answer extends the user-authored picture narrative; it is never stored
    /// as a real-life connection.
    var cardConnectionScaffoldPending = false
    /// Current-protocol card reflection may ask one responsive question after a concrete
    /// image-to-life mapping when that mapping has not yet produced an interpretive distinction.
    var cardConnectionDeepeningUsed = false
    var cardConnectionUnavailable = false
    var cardLifeConnection: String?
    /// A system-proposed bridge is deliberately separate from the user's raw image-to-life
    /// association. It is never treated as their meaning until they accept or revise it.
    var cardCandidateMapping: String?
    var cardConfirmedMapping: String?
    var cardMappingConfirmed = false
    /// A local, deterministic grounding between user-authored image and reality relations.
    /// It contains no designer meaning and absence prevents even structural card use.
    var cardGroundingMatch: CardGroundingMatch?
    var cardMeaningShiftResponse: String?
    var cardMeaningShiftCompleted = false
    /// What the card phase added beyond the locked baseline. Kept separate to prevent summary
    /// concatenation when the final record is generated.
    var cardDerivedDeltaNarrative: String?
    var candidCircumstancesCompleted = false
    var candidCircumstancesResponse: String?
    var candidAgencyCompleted = false
    var candidAgencyResponse: String?
    var integratedNarrativeConfirmed = false
    var pendingUserAuthoredAction: String?
    var userAuthoredActionConfirmed = false
    var hasPresentedFinalNarrative = false
    var finalNarrativeConfirmed = false
    var hasAskedProgressMeaningQuestion = false
    var hasAskedCardProjectionFollowUp = false
    var hasAskedCardNarrativeDeepening = false
    var hasUserAuthoredCardConnection = false
    var hasCompletedAttributionExchange = false
    var hasPresentedIntegratedNarrative = false
    var currentRoute: CompassionRoute = .tenderStabilize
    var latestAnalysis: ContextAnalysis?
    var dialogueProgress = DialogueProgress()
    var hypotheses: [Hypothesis] = []
    var actionSuggestions: [ActionSuggestion] = []
    var studyEvents: [StudyEvent] = []
    var studyMeasures = StudyMeasures()

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, stage, protocolVersion, protocolStage, reflectionReadiness, semanticMemory
        case presentedTrackingCueIDs, trackingPresentations, activeTrackingPresentationID
        case cardGuidanceShared, pendingCardGuidanceTurn, cardGuidanceTransactionID
        case condition, studySequence, studyPeriod, eventDateIsUserSpecified, messages
        case supersededAssistantMessageIDs
        case context, canvas, trackingCues
        case contextualLoadInference
        case trackingUseDeclined, pendingTrackingCueID, pendingTrackingCueIDs
        case card, cardDrawRecord, cardWasSetAside, cardInterpretation
        case cardDisplayState, cardDisplayReloadNonce
        case workflowPhase, structuredDisclosureAssistantTurns
        case bodyExplorationCompleted, personalMeaningExplorationCompleted
        case hasAskedPersonalMeaningQuestion
        case tenderGroundingRevisionCount, tenderGroundingConfirmed, trackingReviewCompleted
        case trackingReviewUnavailable, trackingContextLinkCompleted, trackingContextLinkResponse
        case contextConfirmationRevisionCount, contextSummaryConfirmed, lockedBaselineNarrative
        case cardImageDevelopmentTurnCount, cardConnectionAttemptCount, cardConnectionScaffoldUsed
        case cardConnectionScaffoldPending, cardConnectionDeepeningUsed, cardConnectionUnavailable
        case cardLifeConnection, cardCandidateMapping, cardConfirmedMapping, cardMappingConfirmed
        case cardGroundingMatch, cardGuidanceMatch, cardMeaningShiftResponse, cardMeaningShiftCompleted
        case cardDerivedDeltaNarrative
        case candidCircumstancesCompleted, candidCircumstancesResponse
        case candidAgencyCompleted, candidAgencyResponse
        case integratedNarrativeConfirmed, pendingUserAuthoredAction
        case userAuthoredActionConfirmed, hasPresentedFinalNarrative, finalNarrativeConfirmed
        case hasAskedProgressMeaningQuestion
        case hasAskedCardProjectionFollowUp, hasAskedCardNarrativeDeepening, hasUserAuthoredCardConnection
        case hasCompletedAttributionExchange, hasPresentedIntegratedNarrative, currentRoute
        case latestAnalysis, dialogueProgress, hypotheses, actionSuggestions, studyEvents, studyMeasures
    }

    init() {}

    var usesLLMTurnController: Bool { protocolVersion >= 2 }
    /// Only current protocol sessions use the prompt-only active baseline. Legacy in-progress
    /// sessions keep their original workflow so decoding an old record never changes it mid-turn.
    var usesSimpleGentleControl: Bool {
        protocolVersion >= Self.simpleGentleControlProtocolVersion &&
            condition.usesSimpleGentleReflection
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decode(UUID.self, forKey: .id)) ?? UUID()
        createdAt = (try? box.decode(Date.self, forKey: .createdAt)) ?? Date()
        stage = (try? box.decode(ReflectionState.self, forKey: .stage)) ?? .welcome
        let savedProtocolVersion = (try? box.decode(Int.self, forKey: .protocolVersion)) ?? 1
        // Protocol-4 sessions keep their established narrative-first ordering. Older typed
        // sessions normalize to that compatible contract, while only newly created protocol-5
        // sessions receive the action-first capability sequence.
        if savedProtocolVersion >= Self.actionFirstReflectionProtocolVersion {
            protocolVersion = Self.currentProtocolVersion
        } else if savedProtocolVersion >= 2 {
            protocolVersion = Self.consolidatedTurnProtocolVersion
        } else {
            protocolVersion = savedProtocolVersion
        }
        protocolStage = (try? box.decode(ReflectionProtocolStage.self, forKey: .protocolStage))
            ?? Self.inferredProtocolStage(from: stage)
        reflectionReadiness =
            (try? box.decode(ReflectionReadiness.self, forKey: .reflectionReadiness))
            ?? (protocolStage == .narrativeConfirmation || protocolStage == .optionalAction
                ? .narrativeReady
                : (protocolStage == .contextualDisclosure
                    ? .needsTender
                    : .reflectionOpen))
        var decodedSemanticMemory =
            (try? box.decode(TurnSemanticMemory.self, forKey: .semanticMemory))
            ?? TurnSemanticMemory()
        if var episode = decodedSemanticMemory.episodeStructure {
            episode.migrateLegacyEventProcessContentIfNeeded()
            decodedSemanticMemory.episodeStructure = episode
        }
        let savedCardConnectionMigration =
            decodedSemanticMemory.migrateLegacySavedCardRealityConnection()
        semanticMemory = decodedSemanticMemory
        presentedTrackingCueIDs =
            (try? box.decode(Set<String>.self, forKey: .presentedTrackingCueIDs)) ?? []
        trackingPresentations =
            (try? box.decode([TurnTrackingPresentation].self, forKey: .trackingPresentations)) ?? []
        activeTrackingPresentationID =
            try? box.decodeIfPresent(String.self, forKey: .activeTrackingPresentationID)
        cardGuidanceShared =
            (try? box.decode(Bool.self, forKey: .cardGuidanceShared)) ?? false
        pendingCardGuidanceTurn =
            (try? box.decode(Bool.self, forKey: .pendingCardGuidanceTurn)) ?? false
        cardGuidanceTransactionID =
            try? box.decodeIfPresent(String.self, forKey: .cardGuidanceTransactionID)
        condition = (try? box.decode(ExperimentalCondition.self, forKey: .condition)) ?? .cardMediated
        studySequence = try? box.decodeIfPresent(StudySequence.self, forKey: .studySequence)
        studyPeriod = try? box.decodeIfPresent(Int.self, forKey: .studyPeriod)
        eventDateIsUserSpecified = (try? box.decode(Bool.self, forKey: .eventDateIsUserSpecified)) ?? false
        messages = (try? box.decode([ChatMessage].self, forKey: .messages)) ?? []
        supersededAssistantMessageIDs =
            (try? box.decode(Set<UUID>.self, forKey: .supersededAssistantMessageIDs)) ?? []
        if let decoded = try? box.decode(ReflectionContext.self, forKey: .context) {
            context = decoded
        } else if let legacy = try? box.decode(ContextCanvas.self, forKey: .canvas) {
            context = ReflectionContext(legacy: legacy)
        }
        trackingCues = (try? box.decode([TrackingCue].self, forKey: .trackingCues)) ?? []
        contextualLoadInference =
            try? box.decodeIfPresent(ContextualLoadInference.self, forKey: .contextualLoadInference)
        trackingUseDeclined = (try? box.decode(Bool.self, forKey: .trackingUseDeclined)) ?? false
        pendingTrackingCueID = try? box.decodeIfPresent(String.self, forKey: .pendingTrackingCueID)
        pendingTrackingCueIDs =
            (try? box.decode([String].self, forKey: .pendingTrackingCueIDs))
            ?? pendingTrackingCueID.map { [$0] }
            ?? []
        card = try? box.decodeIfPresent(ReflectionCard.self, forKey: .card)
        cardDrawRecord = try? box.decodeIfPresent(CardDrawRecord.self, forKey: .cardDrawRecord)
        cardWasSetAside = (try? box.decode(Bool.self, forKey: .cardWasSetAside)) ?? false
        cardDisplayState = (try? box.decode(CardDisplayState.self, forKey: .cardDisplayState))
            ?? (card == nil ? .none : (stage == .cardIntroduction ? .selected : .displayed))
        cardDisplayReloadNonce =
            (try? box.decode(Int.self, forKey: .cardDisplayReloadNonce)) ?? 0
        let migratedIncompleteCardConnection =
            savedCardConnectionMigration == .incomplete
        let ignoredLegacyCardConnectionConflict =
            savedCardConnectionMigration == .canonicalConflictIgnored
        let migratedGuidanceWithoutConnection =
            cardGuidanceShared && semanticMemory.cardRealityConnection == nil
        if migratedGuidanceWithoutConnection {
            // Do not invent user evidence to preserve a contradictory legacy capability state.
            // The transcript remains untouched; resume returns to the existing card-reflection
            // recovery surface with guidance closed until a complete connection is committed.
            cardGuidanceShared = false
            pendingCardGuidanceTurn = false
            cardGuidanceTransactionID = nil
            if cardDisplayState == .displayed || card != nil {
                protocolStage = .cardReflection
                stage = .cardInterpretation
            }
        }
        structuredDisclosureAssistantTurns =
            (try? box.decode(Int.self, forKey: .structuredDisclosureAssistantTurns))
            ?? messages.filter {
                $0.role == .assistant && [
                    ReflectionState.eventDisclosure, .emotionDisclosure, .bodilyResponse,
                    .selfJudgment, .contextDisclosure,
                ].contains($0.state)
            }.count
        bodyExplorationCompleted =
            (try? box.decode(Bool.self, forKey: .bodyExplorationCompleted))
            ?? !context.bodilyResponses.isEmpty
        personalMeaningExplorationCompleted =
            (try? box.decode(Bool.self, forKey: .personalMeaningExplorationCompleted))
            ?? (context.personalMeaning?.isEmpty == false)
        hasAskedPersonalMeaningQuestion =
            (try? box.decode(Bool.self, forKey: .hasAskedPersonalMeaningQuestion))
            ?? personalMeaningExplorationCompleted
        tenderGroundingRevisionCount =
            (try? box.decode(Int.self, forKey: .tenderGroundingRevisionCount)) ?? 0
        tenderGroundingConfirmed =
            (try? box.decode(Bool.self, forKey: .tenderGroundingConfirmed)) ?? false
        trackingReviewCompleted =
            (try? box.decode(Bool.self, forKey: .trackingReviewCompleted))
            ?? (stage != .trackingPermission && stage != .trackingReview && stage != .tenderGrounding)
        trackingReviewUnavailable =
            (try? box.decode(Bool.self, forKey: .trackingReviewUnavailable)) ?? false
        trackingContextLinkCompleted =
            (try? box.decode(Bool.self, forKey: .trackingContextLinkCompleted))
            ?? (stage != .trackingReview)
        trackingContextLinkResponse =
            try? box.decodeIfPresent(String.self, forKey: .trackingContextLinkResponse)
        contextConfirmationRevisionCount =
            (try? box.decode(Int.self, forKey: .contextConfirmationRevisionCount)) ?? 0
        contextSummaryConfirmed =
            (try? box.decode(Bool.self, forKey: .contextSummaryConfirmed))
            ?? [
                ReflectionState.cardIntroduction, .cardInterpretation, .attributionReflection,
                .actionSelection, .summary, .completed,
            ].contains(stage)
        lockedBaselineNarrative =
            try? box.decodeIfPresent(String.self, forKey: .lockedBaselineNarrative)
        cardImageDevelopmentTurnCount =
            (try? box.decode(Int.self, forKey: .cardImageDevelopmentTurnCount)) ?? 0
        cardConnectionAttemptCount =
            (try? box.decode(Int.self, forKey: .cardConnectionAttemptCount)) ?? 0
        cardConnectionScaffoldUsed =
            (try? box.decode(Bool.self, forKey: .cardConnectionScaffoldUsed)) ?? false
        cardConnectionDeepeningUsed =
            (try? box.decode(Bool.self, forKey: .cardConnectionDeepeningUsed)) ?? false
        cardConnectionScaffoldPending =
            (try? box.decode(Bool.self, forKey: .cardConnectionScaffoldPending)) ?? false
        cardConnectionUnavailable =
            (try? box.decode(Bool.self, forKey: .cardConnectionUnavailable)) ?? cardWasSetAside
        cardLifeConnection = try? box.decodeIfPresent(String.self, forKey: .cardLifeConnection)
        cardCandidateMapping = try? box.decodeIfPresent(String.self, forKey: .cardCandidateMapping)
        // Older sessions reached candid reflection directly after a user-authored connection.
        // Treat that already-progressed route as confirmed while new sessions persist this flag.
        cardMappingConfirmed =
            (try? box.decode(Bool.self, forKey: .cardMappingConfirmed))
            ?? (cardLifeConnection?.isEmpty == false && stage == .attributionReflection)
        cardConfirmedMapping = try? box.decodeIfPresent(String.self, forKey: .cardConfirmedMapping)
            ?? (cardMappingConfirmed ? cardLifeConnection : nil)
        cardGroundingMatch =
            (try? box.decodeIfPresent(CardGroundingMatch.self, forKey: .cardGroundingMatch))
            ?? (try? box.decodeIfPresent(CardGroundingMatch.self, forKey: .cardGuidanceMatch))
        cardMeaningShiftResponse =
            try? box.decodeIfPresent(String.self, forKey: .cardMeaningShiftResponse)
        cardMeaningShiftCompleted =
            (try? box.decode(Bool.self, forKey: .cardMeaningShiftCompleted))
            ?? (cardMeaningShiftResponse?.isEmpty == false)
        cardDerivedDeltaNarrative =
            try? box.decodeIfPresent(String.self, forKey: .cardDerivedDeltaNarrative)
        candidCircumstancesResponse =
            try? box.decodeIfPresent(String.self, forKey: .candidCircumstancesResponse)
        candidCircumstancesCompleted =
            (try? box.decode(Bool.self, forKey: .candidCircumstancesCompleted))
            ?? (candidCircumstancesResponse?.isEmpty == false)
        candidAgencyResponse = try? box.decodeIfPresent(String.self, forKey: .candidAgencyResponse)
        candidAgencyCompleted =
            (try? box.decode(Bool.self, forKey: .candidAgencyCompleted))
            ?? (candidAgencyResponse?.isEmpty == false)
        integratedNarrativeConfirmed =
            (try? box.decode(Bool.self, forKey: .integratedNarrativeConfirmed))
            ?? (stage == .actionSelection || stage == .summary || stage == .completed)
        pendingUserAuthoredAction =
            try? box.decodeIfPresent(String.self, forKey: .pendingUserAuthoredAction)
        userAuthoredActionConfirmed =
            (try? box.decode(Bool.self, forKey: .userAuthoredActionConfirmed))
            ?? (context.selectedAction?.acceptedByUser == true)
        hasPresentedFinalNarrative =
            (try? box.decode(Bool.self, forKey: .hasPresentedFinalNarrative))
            ?? (stage == .summary || stage == .completed)
        finalNarrativeConfirmed =
            (try? box.decode(Bool.self, forKey: .finalNarrativeConfirmed))
            ?? (stage == .completed)
        hasAskedProgressMeaningQuestion =
            (try? box.decode(Bool.self, forKey: .hasAskedProgressMeaningQuestion)) ?? false
        hasAskedCardProjectionFollowUp =
            (try? box.decode(Bool.self, forKey: .hasAskedCardProjectionFollowUp)) ?? false
        hasAskedCardNarrativeDeepening =
            (try? box.decode(Bool.self, forKey: .hasAskedCardNarrativeDeepening)) ?? false
        hasCompletedAttributionExchange =
            (try? box.decode(Bool.self, forKey: .hasCompletedAttributionExchange))
            ?? (candidCircumstancesCompleted && candidAgencyCompleted)
        hasPresentedIntegratedNarrative =
            (try? box.decode(Bool.self, forKey: .hasPresentedIntegratedNarrative)) ?? false
        hasUserAuthoredCardConnection =
            (try? box.decode(Bool.self, forKey: .hasUserAuthoredCardConnection))
            ?? (cardLifeConnection?.isEmpty == false || hasCompletedAttributionExchange || hasPresentedIntegratedNarrative)
        currentRoute = (try? box.decode(CompassionRoute.self, forKey: .currentRoute)) ?? .tenderStabilize
        workflowPhase = (try? box.decode(ReflectionWorkflowPhase.self, forKey: .workflowPhase))
            ?? Self.inferredWorkflowPhase(
                stage: stage,
                cardDisplayState: cardDisplayState,
                hasAskedCardProjectionFollowUp: hasAskedCardProjectionFollowUp,
                hasAskedCardNarrativeDeepening: hasAskedCardNarrativeDeepening,
                hasUserAuthoredCardConnection: hasUserAuthoredCardConnection,
                cardMappingConfirmed: cardMappingConfirmed,
                candidCircumstancesCompleted: candidCircumstancesCompleted,
                cardMeaningShiftCompleted: cardMeaningShiftCompleted,
                hasCompletedAttributionExchange: hasCompletedAttributionExchange,
                hasPresentedIntegratedNarrative: hasPresentedIntegratedNarrative
            )
        latestAnalysis = try? box.decodeIfPresent(ContextAnalysis.self, forKey: .latestAnalysis)
        dialogueProgress = (try? box.decode(DialogueProgress.self, forKey: .dialogueProgress))
            ?? DialogueProgress()
        dialogueProgress.currentState = stage
        hypotheses = (try? box.decode([Hypothesis].self, forKey: .hypotheses)) ?? []
        actionSuggestions = (try? box.decode([ActionSuggestion].self, forKey: .actionSuggestions)) ?? []
        studyEvents = (try? box.decode([StudyEvent].self, forKey: .studyEvents)) ?? []
        if migratedIncompleteCardConnection,
           !studyEvents.contains(where: { $0.action == "legacy_incomplete_card_connection" }) {
            studyEvents.append(
                .init(stage: stage, action: "legacy_incomplete_card_connection")
            )
        }
        if migratedGuidanceWithoutConnection,
           !studyEvents.contains(where: {
               $0.action == "legacy_guidance_without_confirmed_connection"
           }) {
            studyEvents.append(
                .init(stage: stage, action: "legacy_guidance_without_confirmed_connection")
            )
        }
        if ignoredLegacyCardConnectionConflict,
           !studyEvents.contains(where: {
               $0.action == "legacy_card_connection_conflict_ignored"
           }) {
            studyEvents.append(
                .init(stage: stage, action: "legacy_card_connection_conflict_ignored")
            )
        }
        studyMeasures = (try? box.decode(StudyMeasures.self, forKey: .studyMeasures)) ?? StudyMeasures()
        if context.cardInterpretation == nil {
            context.cardInterpretation = try? box.decodeIfPresent(String.self, forKey: .cardInterpretation)
        }
        for index in trackingCues.indices {
            guard var insight = trackingCues[index].insight else { continue }
            insight.userRelevance = trackingCues[index].relevance
            trackingCues[index].insight = insight
        }
        let savedTrackingInterpretations = (context.confirmedTrackingInsights ?? []).reduce(
            into: [UUID: String]()
        ) { values, item in
            if let interpretation = item.userInterpretation {
                values[item.insightID] = interpretation
            }
        }
        context.confirmedTrackingCues = trackingCues.filter { $0.relevance == .relevant }
        context.confirmedTrackingInsights = trackingCues.compactMap { cue in
            guard cue.relevance == .relevant, let insight = cue.insight else { return nil }
            return ConfirmedTrackingContext(
                insightID: insight.id,
                observation: insight.neutralObservation,
                userInterpretation: savedTrackingInterpretations[insight.id],
                relevance: .relevant
            )
        }
        context.rejectedTrackingCueIDs = Set(
            trackingCues.filter { $0.relevance == .irrelevant }.map(\.id)
        )
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encode(stage, forKey: .stage)
        try box.encode(protocolVersion, forKey: .protocolVersion)
        try box.encode(protocolStage, forKey: .protocolStage)
        try box.encode(reflectionReadiness, forKey: .reflectionReadiness)
        try box.encode(semanticMemory, forKey: .semanticMemory)
        try box.encode(presentedTrackingCueIDs, forKey: .presentedTrackingCueIDs)
        try box.encode(trackingPresentations, forKey: .trackingPresentations)
        try box.encodeIfPresent(
            activeTrackingPresentationID,
            forKey: .activeTrackingPresentationID
        )
        try box.encode(cardGuidanceShared, forKey: .cardGuidanceShared)
        try box.encode(pendingCardGuidanceTurn, forKey: .pendingCardGuidanceTurn)
        try box.encodeIfPresent(
            cardGuidanceTransactionID,
            forKey: .cardGuidanceTransactionID
        )
        try box.encode(condition, forKey: .condition)
        try box.encodeIfPresent(studySequence, forKey: .studySequence)
        try box.encodeIfPresent(studyPeriod, forKey: .studyPeriod)
        try box.encode(eventDateIsUserSpecified, forKey: .eventDateIsUserSpecified)
        try box.encode(messages, forKey: .messages)
        try box.encode(supersededAssistantMessageIDs, forKey: .supersededAssistantMessageIDs)
        try box.encode(context, forKey: .context)
        try box.encode(trackingCues, forKey: .trackingCues)
        try box.encodeIfPresent(contextualLoadInference, forKey: .contextualLoadInference)
        try box.encode(trackingUseDeclined, forKey: .trackingUseDeclined)
        try box.encodeIfPresent(pendingTrackingCueID, forKey: .pendingTrackingCueID)
        try box.encode(pendingTrackingCueIDs, forKey: .pendingTrackingCueIDs)
        try box.encodeIfPresent(card, forKey: .card)
        try box.encodeIfPresent(cardDrawRecord, forKey: .cardDrawRecord)
        try box.encode(cardWasSetAside, forKey: .cardWasSetAside)
        try box.encode(cardDisplayState, forKey: .cardDisplayState)
        try box.encode(cardDisplayReloadNonce, forKey: .cardDisplayReloadNonce)
        try box.encode(workflowPhase, forKey: .workflowPhase)
        try box.encode(structuredDisclosureAssistantTurns, forKey: .structuredDisclosureAssistantTurns)
        try box.encode(bodyExplorationCompleted, forKey: .bodyExplorationCompleted)
        try box.encode(personalMeaningExplorationCompleted, forKey: .personalMeaningExplorationCompleted)
        try box.encode(hasAskedPersonalMeaningQuestion, forKey: .hasAskedPersonalMeaningQuestion)
        try box.encode(tenderGroundingRevisionCount, forKey: .tenderGroundingRevisionCount)
        try box.encode(tenderGroundingConfirmed, forKey: .tenderGroundingConfirmed)
        try box.encode(trackingReviewCompleted, forKey: .trackingReviewCompleted)
        try box.encode(trackingReviewUnavailable, forKey: .trackingReviewUnavailable)
        try box.encode(trackingContextLinkCompleted, forKey: .trackingContextLinkCompleted)
        try box.encodeIfPresent(trackingContextLinkResponse, forKey: .trackingContextLinkResponse)
        try box.encode(contextConfirmationRevisionCount, forKey: .contextConfirmationRevisionCount)
        try box.encode(contextSummaryConfirmed, forKey: .contextSummaryConfirmed)
        try box.encodeIfPresent(lockedBaselineNarrative, forKey: .lockedBaselineNarrative)
        try box.encode(cardImageDevelopmentTurnCount, forKey: .cardImageDevelopmentTurnCount)
        try box.encode(cardConnectionAttemptCount, forKey: .cardConnectionAttemptCount)
        try box.encode(cardConnectionScaffoldUsed, forKey: .cardConnectionScaffoldUsed)
        try box.encode(cardConnectionScaffoldPending, forKey: .cardConnectionScaffoldPending)
        try box.encode(cardConnectionDeepeningUsed, forKey: .cardConnectionDeepeningUsed)
        try box.encode(cardConnectionUnavailable, forKey: .cardConnectionUnavailable)
        try box.encodeIfPresent(cardLifeConnection, forKey: .cardLifeConnection)
        try box.encodeIfPresent(cardCandidateMapping, forKey: .cardCandidateMapping)
        try box.encodeIfPresent(cardConfirmedMapping, forKey: .cardConfirmedMapping)
        try box.encode(cardMappingConfirmed, forKey: .cardMappingConfirmed)
        try box.encodeIfPresent(cardGroundingMatch, forKey: .cardGroundingMatch)
        try box.encodeIfPresent(cardMeaningShiftResponse, forKey: .cardMeaningShiftResponse)
        try box.encode(cardMeaningShiftCompleted, forKey: .cardMeaningShiftCompleted)
        try box.encodeIfPresent(cardDerivedDeltaNarrative, forKey: .cardDerivedDeltaNarrative)
        try box.encode(candidCircumstancesCompleted, forKey: .candidCircumstancesCompleted)
        try box.encodeIfPresent(candidCircumstancesResponse, forKey: .candidCircumstancesResponse)
        try box.encode(candidAgencyCompleted, forKey: .candidAgencyCompleted)
        try box.encodeIfPresent(candidAgencyResponse, forKey: .candidAgencyResponse)
        try box.encode(integratedNarrativeConfirmed, forKey: .integratedNarrativeConfirmed)
        try box.encodeIfPresent(pendingUserAuthoredAction, forKey: .pendingUserAuthoredAction)
        try box.encode(userAuthoredActionConfirmed, forKey: .userAuthoredActionConfirmed)
        try box.encode(hasPresentedFinalNarrative, forKey: .hasPresentedFinalNarrative)
        try box.encode(finalNarrativeConfirmed, forKey: .finalNarrativeConfirmed)
        try box.encode(hasAskedProgressMeaningQuestion, forKey: .hasAskedProgressMeaningQuestion)
        try box.encode(hasAskedCardProjectionFollowUp, forKey: .hasAskedCardProjectionFollowUp)
        try box.encode(hasAskedCardNarrativeDeepening, forKey: .hasAskedCardNarrativeDeepening)
        try box.encode(hasUserAuthoredCardConnection, forKey: .hasUserAuthoredCardConnection)
        try box.encode(hasCompletedAttributionExchange, forKey: .hasCompletedAttributionExchange)
        try box.encode(hasPresentedIntegratedNarrative, forKey: .hasPresentedIntegratedNarrative)
        try box.encode(currentRoute, forKey: .currentRoute)
        try box.encodeIfPresent(latestAnalysis, forKey: .latestAnalysis)
        try box.encode(dialogueProgress, forKey: .dialogueProgress)
        try box.encode(hypotheses, forKey: .hypotheses)
        try box.encode(actionSuggestions, forKey: .actionSuggestions)
        try box.encode(studyEvents, forKey: .studyEvents)
        try box.encode(studyMeasures, forKey: .studyMeasures)
    }

    private static func inferredWorkflowPhase(
        stage: ReflectionState,
        cardDisplayState: CardDisplayState,
        hasAskedCardProjectionFollowUp: Bool,
        hasAskedCardNarrativeDeepening: Bool,
        hasUserAuthoredCardConnection: Bool,
        cardMappingConfirmed: Bool,
        candidCircumstancesCompleted: Bool,
        cardMeaningShiftCompleted: Bool,
        hasCompletedAttributionExchange: Bool,
        hasPresentedIntegratedNarrative: Bool
    ) -> ReflectionWorkflowPhase {
        switch stage {
        case .welcome: return .opening
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure:
            return .structuredDisclosure
        case .tenderGrounding, .tenderExploration: return .tenderGroundingConfirmation
        case .trackingPermission, .trackingReview: return .trackingReview
        case .readinessCheck: return .contextConfirmation
        case .cardIntroduction:
            return cardDisplayState == .none ? .cardSelection : .cardDisplay
        case .cardInterpretation:
            if hasAskedCardNarrativeDeepening { return .cardNarrativeDeepening }
            return hasAskedCardProjectionFollowUp ? .cardAssociation : .cardObservation
        case .attributionReflection:
            if hasPresentedIntegratedNarrative { return .reflectionNarrativeConfirmation }
            // Older payloads did not persist the finer gates. Resume them at the earliest missing
            // safe gate instead of letting a legacy stage skip meaning shift or narrative review.
            if hasCompletedAttributionExchange { return .reflectionNarrativeConfirmation }
            if hasUserAuthoredCardConnection {
                guard cardMappingConfirmed else { return .cardMappingConfirmation }
                guard candidCircumstancesCompleted else { return .candidCircumstances }
                return cardMeaningShiftCompleted ? .candidAgency : .cardMeaningShift
            }
            return .cardConnection
        case .actionSelection: return .optionalAction
        case .summary: return .narrativeConfirmation
        case .completed: return .complete
        case .safetySupport: return .safetySupport
        }
    }

    private static func inferredProtocolStage(from stage: ReflectionState) -> ReflectionProtocolStage {
        switch stage {
        case .welcome, .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure, .trackingPermission, .trackingReview:
            return .contextualDisclosure
        case .tenderGrounding, .tenderExploration:
            // LEGACY_DECODE_ONLY — pre-card Tender views resume at the current disclosure gate.
            return .contextualDisclosure
        case .readinessCheck, .cardIntroduction:
            return .cardConsent
        case .cardInterpretation:
            return .cardReflection
        case .attributionReflection:
            return .directReflection
        case .actionSelection:
            return .optionalAction
        case .summary:
            return .narrativeConfirmation
        case .completed:
            return .complete
        case .safetySupport:
            return .safetySupport
        }
    }
}

struct DialogueActionOption: Codable, Equatable {
    let category: CompassionateActionCategory
    let description: String
    let timing: String?
    let rationale: String
}

struct DialogueTurn: Codable, Equatable {
    var reflection: String
    var question: String
    var actionOptions: [DialogueActionOption]

    var visibleText: String {
        [reflection, question]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
