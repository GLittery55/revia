import Foundation
import os

private let semanticOperationAuditLogger = Logger(
    subsystem: "com.wj.BeyondComfort",
    category: "SemanticOperationAudit"
)

/// Test/debug observability for proving which execution authority handled a turn. Recording is
/// optional and never participates in protocol decisions.
enum ProtocolExecutionAuditStep: String, CaseIterable, Sendable {
    case semanticMapper
    case legacySemanticMapper
    case projector
    case legacyNormalizer
    case legacyTransitionBuilder
    case legacyExecutableFallback
    case silentContinuation
    case transactionCommit
}

final class ProtocolExecutionAuditRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [ProtocolExecutionAuditStep: Int] = [:]

    func record(_ step: ProtocolExecutionAuditStep) {
        lock.lock()
        counts[step, default: 0] += 1
        lock.unlock()
    }

    func count(for step: ProtocolExecutionAuditStep) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[step, default: 0]
    }
}

struct TurnProtocolOperation: Codable, Equatable, Sendable {
    let requestedStage: ReflectionProtocolStage
    let replyIntent: TurnReplyIntent
    let localAction: TurnLocalActionKind
}

struct ReflectionProtocolPermissions: Codable, Equatable, Sendable {
    let currentStage: ReflectionProtocolStage
    let allowedStages: [ReflectionProtocolStage]
    let allowedActions: [TurnLocalActionKind]
    let allowedReplyIntents: [TurnReplyIntent]
    /// Current-protocol disclosure capabilities. Empty means the field is not applicable (for
    /// legacy sessions or another stage), never "all enum values".
    let allowedDisclosurePurposes: [TurnDisclosureQuestionPurpose]
    let allowedDisclosureTargets: [TurnDisclosureQuestionTarget]
    /// Authoritative stage–intent–action tuples. The three catalogues above remain useful for
    /// diagnostics and enum repair, but they must never be treated as an arbitrary Cartesian
    /// product by the Planner.
    let allowedOperations: [TurnProtocolOperation]
    /// Closed semantic capabilities for the explicit current Planner contract. Unlike the legacy
    /// tuples above, these values are consumed directly and never reconstructed from structure.
    let allowedSemanticOperations: [PlannerSemanticOperation]

    init(
        currentStage: ReflectionProtocolStage,
        allowedStages: [ReflectionProtocolStage],
        allowedActions: [TurnLocalActionKind],
        allowedReplyIntents: [TurnReplyIntent],
        allowedDisclosurePurposes: [TurnDisclosureQuestionPurpose] = [],
        allowedDisclosureTargets: [TurnDisclosureQuestionTarget] = [],
        allowedOperations: [TurnProtocolOperation] = [],
        allowedSemanticOperations: [PlannerSemanticOperation] = []
    ) {
        self.currentStage = currentStage
        self.allowedStages = allowedStages
        self.allowedActions = allowedActions
        self.allowedReplyIntents = allowedReplyIntents
        self.allowedDisclosurePurposes = allowedDisclosurePurposes
        self.allowedDisclosureTargets = allowedDisclosureTargets
        self.allowedOperations = allowedOperations
        self.allowedSemanticOperations = allowedSemanticOperations
    }

    private enum CodingKeys: String, CodingKey {
        case currentStage, allowedStages, allowedActions, allowedReplyIntents
        case allowedDisclosurePurposes, allowedDisclosureTargets, allowedOperations
        case allowedSemanticOperations
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        currentStage = try box.decode(ReflectionProtocolStage.self, forKey: .currentStage)
        allowedStages = try box.decode([ReflectionProtocolStage].self, forKey: .allowedStages)
        allowedActions = try box.decode([TurnLocalActionKind].self, forKey: .allowedActions)
        allowedReplyIntents = try box.decode([TurnReplyIntent].self, forKey: .allowedReplyIntents)
        allowedDisclosurePurposes = (try? box.decode(
            [TurnDisclosureQuestionPurpose].self,
            forKey: .allowedDisclosurePurposes
        )) ?? []
        allowedDisclosureTargets = (try? box.decode(
            [TurnDisclosureQuestionTarget].self,
            forKey: .allowedDisclosureTargets
        )) ?? []
        allowedOperations = (try? box.decode(
            [TurnProtocolOperation].self,
            forKey: .allowedOperations
        )) ?? []
        allowedSemanticOperations = (try? box.decode(
            [PlannerSemanticOperation].self,
            forKey: .allowedSemanticOperations
        )) ?? []
    }
}

enum ReflectionProtocolViolation: Error, Equatable {
    case emptyReply
    case illegalStageTransition
    case illegalLocalAction
    case illegalReplyIntent
    case missingRequiredMemoryField(TurnRequiredMemoryField)
    case incompleteEpisodeStructure([TurnEpisodeRequirement])
    case writerIntentMismatch
    case unresolvedWriterQuality
    case unknownTrackingCue
    case duplicateTrackingCue
    case trackingReviewRequired
    case conflictingMemoryPatch
    case invalidNextPrompt
    case repeatedQuestionPurpose(
        TurnDisclosureQuestionPurpose,
        TurnDisclosureQuestionTarget
    )
    case invalidDisclosureQuestionTarget(TurnDisclosureQuestionTarget)
    case disclosureShouldAdvance
    case invalidConfirmationResolution
    case unknownConfirmationReference
    case invalidCardReferenceSelection
    case connectionSourceWithoutContent
    case incompleteCardRealityConnection
    case shareGuidanceWithoutConfirmedConnection
    case invalidPreGuidanceConnectionConfirmation
    case legacyCardConnectionPatchNotAllowed
    case confirmedCardConnectionIsImmutable
    case invalidReflectionFrame
    case fierceReflectionUngrounded
    case incompletePracticeTransition([TurnPracticeTransitionRequirement])
}

enum TurnPracticeTransitionRequirement: String, Codable, Equatable, Sendable {
    case narrativeResolution
    case requestedStage
    case proposal
    case proposalID
    case transactionReference
    case proposalKind
    case proposalContent
    case proposalBasis
    case proposalStatus
    case confirmationPrompt
    case confirmationReference
    case noActionReason
    case pendingSelectionMustBeEmpty
}

enum TurnRequiredMemoryField: String, Equatable, Sendable {
    case situationUnderstanding
    case selfCriticismStatus
    case selfCriticalStatement
    case selfCriticismLink
    case episodeStructure
    case contextRelationship
    case cardNegotiatedMeaning
    case cardInterpretiveTension
    case cardRealityMappingSource
    case candidUnderstanding
    /// Legacy repair code retained for older persisted requests.
    case fierceUnderstanding
    case finalNarrative
}

enum TurnEpisodeRequirement: String, Codable, Equatable, Sendable {
    case concreteFact
    case behaviorEvidenceStatus
    case behaviorEvidence
    case eventProcessStatus
    case eventProcessEvidence
    case eventProcessUncertainty
    case impactStatus
    case impactEvidence
}

enum TurnWriterQualityIssue: String, Equatable, Sendable {
    case realizedIntentMismatch
    case expectedSingleQuestion
    case expectedNoQuestion
}

/// Non-blocking contract imperfections. These are useful for research diagnostics and later
/// metadata repair, but they do not authorize Swift to discard an otherwise legal conversational
/// turn. Capability boundaries, object references, stage transitions, and local side effects
/// remain hard validation errors.
enum TurnProtocolWarning: String, Equatable, Sendable {
    case normalizedNextPromptMetadata
    case repeatedQuestionPurpose
    case redundantConfirmedConnectionPatch = "redundant_confirmed_connection_patch"
}

/// This controller knows study protocol, not conversation meaning. In particular, it never
/// decides whether the person has expressed enough emotion, accepted an interpretation, or has
/// sufficient evidence for responsibility. Those are LLM TurnController decisions.
struct ReflectionProtocolController: Sendable {
    private let executionAudit: ProtocolExecutionAuditRecorder?

    init(executionAudit: ProtocolExecutionAuditRecorder? = nil) {
        self.executionAudit = executionAudit
    }

    func recordExecutionAudit(_ step: ProtocolExecutionAuditStep) {
        executionAudit?.record(step)
    }

    /// Content-free migration telemetry. Divergence is observable but never executable.
    func recordSemanticOperationDiagnostic(
        explicit: PlannerSemanticOperation,
        legacyInferred: PlannerSemanticOperation?,
        isRecovery: Bool
    ) {
        let legacy = legacyInferred?.rawValue ?? "unavailable"
        semanticOperationAuditLogger.info(
            "explicitSemanticOperation=\(explicit.rawValue, privacy: .public) legacyInferredOperation=\(legacy, privacy: .public) legacyFieldsConflict=\(legacyInferred != explicit, privacy: .public) recoveryShadow=\(isRecovery, privacy: .public)"
        )
    }

    func permissions(for session: ReflectionSession) -> ReflectionProtocolPermissions {
        permissions(
            for: session,
            effectiveConnection: effectiveCardRealityConnection(for: session)
        )
    }

    /// Selects one recovery contract from the last valid persisted interaction state. It never
    /// inspects the rejected plan or validation reason, so a failed operation cannot choose its
    /// own successor or leak v4 mechanics into a v5 session.
    func recoveryOperation(for session: ReflectionSession) -> TurnRecoveryOperation {
        switch session.protocolStage {
        case .contextualDisclosure:
            return .eventDisclosure
        case .cardConsent:
            return .cardConsent
        case .cardReflection:
            if cardConnectionInteractionState(for: session) == .awaitingCandidateResolution {
                return .cardCandidateResolution
            }
            if effectiveCardRealityConnection(for: session) != nil {
                return session.protocolVersion >= ReflectionSession.currentProtocolVersion
                    ? .currentCardGuidance
                    : .legacyCardReading
            }
            return .cardOpenExploration
        case .directReflection:
            return session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding
                ? .directSynthesis
                : .directReflection
        case .narrativeConfirmation:
            return .finalNarrative
        case .optionalAction:
            return .optionalAction
        case .complete:
            return .complete
        case .safetySupport:
            return .safety
        }
    }

    /// The only connection projection used by capabilities, normalization, validation, card
    /// context, recovery, and resume. It combines typed state only; it never reads dialogue text.
    func effectiveCardRealityConnection(
        for session: ReflectionSession,
        memoryUpdate: TurnSemanticMemoryUpdate? = nil,
        resolution: TurnResolvedConfirmation? = nil
    ) -> TurnCardRealityConnection? {
        if let canonical = TurnCardRealityConnectionResolver.effective(
            memory: session.semanticMemory,
            update: memoryUpdate,
            resolution: resolution
        ) {
            return canonical
        }
        guard session.protocolVersion < ReflectionSession.currentProtocolVersion,
              memoryUpdate?.clearCardRealityConnection != true else {
            return nil
        }
        // The retired scalar runtime path is isolated to explicitly legacy sessions. Current
        // protocol capabilities and validation can never reach this branch, even when a complete
        // old triple appears in a Planner patch.
        let imageRelation = memoryUpdate?.cardImageRelation
            ?? session.semanticMemory.cardImageRelation
        let realityMapping = memoryUpdate?.cardRealityMapping
            ?? session.semanticMemory.cardRealityMapping
        let source = memoryUpdate?.cardRealityMappingSource
            ?? session.semanticMemory.cardRealityMappingSource
        guard let imageRelation, let realityMapping, let source else { return nil }
        return TurnCardRealityConnection(
            imageRelation: imageRelation,
            realityMapping: realityMapping,
            source: source
        ).normalizedConfirmed
    }

    /// Builds the sole Planner-facing interaction state from persisted pending-candidate and
    /// confirmation data. A Planner cannot infer this state from the latest answer.
    func cardConnectionInteractionState(
        for session: ReflectionSession
    ) -> CardConnectionInteractionState {
        guard session.semanticMemory.pendingCardRealityConnection?.isStructurallyComplete == true,
              effectiveCurrentPrompt(for: session)?.kind == .confirmationRequest,
              effectiveCurrentPrompt(for: session)?.target == .cardRealityConnection else {
            return .openExploration
        }
        return .awaitingCandidateResolution
    }

    private func hasLockedPostGuidanceConnection(_ session: ReflectionSession) -> Bool {
        guard effectiveCardRealityConnection(for: session) != nil else { return false }
        if session.cardGuidanceShared || session.pendingCardGuidanceTurn {
            return true
        }
        if effectiveCurrentPrompt(for: session)?.target == .cardMapping
            || nonempty(session.semanticMemory.cardNegotiatedMeaning) {
            return true
        }
        return [
            ReflectionProtocolStage.directReflection,
            .narrativeConfirmation,
            .optionalAction,
            .complete,
        ].contains(session.protocolStage)
    }

    private func permissions(
        for session: ReflectionSession,
        effectiveConnection: TurnCardRealityConnection?
    ) -> ReflectionProtocolPermissions {
        var stages = allowedStages(
            from: session.protocolStage,
            condition: session.condition
        )
        var actions: [TurnLocalActionKind] = [.none]
        var replyIntents = allowedReplyIntents(from: session.protocolStage)
        var disclosurePurposes: [TurnDisclosureQuestionPurpose] = []
        var disclosureTargets: [TurnDisclosureQuestionTarget] = []

        switch session.protocolStage {
        case .contextualDisclosure:
            let disclosureState = EffectiveEventDisclosureState(
                memory: session.semanticMemory
            )
            disclosurePurposes = availableDisclosurePurposes(in: disclosureState)
            disclosureTargets = Array(Set(disclosurePurposes.map(\.target))).sorted {
                $0.rawValue < $1.rawValue
            }
            replyIntents = [.exploreContext, .inviteCardConsent, .safetySupport]
            if isEventDisclosureCoreComplete(disclosureState) {
                replyIntents.removeAll { $0 == .exploreContext }
            }
        case .cardConsent:
            if session.condition.usesCard,
               session.card == nil,
               session.cardDisplayState == .none {
                actions.append(.drawRandomCard)
            }
        case .cardReflection:
            if effectiveConnection == nil {
                replyIntents.removeAll {
                    [.authorizeCardGuidance, .presentCardReading].contains($0)
                }
            }
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                // The first open observation is rendered locally after the image appears. Once
                // the person answers it, another generic observation invitation would only
                // restart the image phase. A typed user-authored image-to-life mapping is also
                // sufficient for the current protocol: Swift authorizes the candidate-reading
                // path instead of exposing a separate semantic deepening gate that can strand an
                // otherwise complete connection.
                replyIntents.removeAll {
                    [.inviteCardObservation, .deepenCardConnection].contains($0)
                }

                if session.cardConnectionAttemptCount == 0 {
                    let relationAlreadyEstablished = effectiveConnection != nil
                    if session.cardImageDevelopmentTurnCount >= 2
                        || (relationAlreadyEstablished
                            && session.cardImageDevelopmentTurnCount >= 1) {
                        // Before the first life-connection invitation, allow at most one
                        // relationship clarification and one temporal projection. If the
                        // relationship was established immediately, the single development turn
                        // is the temporal projection. This is a capability limit, not keyword
                        // interpretation by Swift.
                        replyIntents.removeAll { $0 == .developCardImage }
                    }
                }
            }
            if session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion,
               session.cardConnectionDeepeningUsed {
                replyIntents.removeAll { $0 == .deepenCardConnection }
            }
            if session.cardConnectionUnavailable {
                replyIntents = replyIntents.filter {
                    [.directCandidReflection, .safetySupport].contains($0)
                }
            } else {
                if effectiveConnection != nil {
                    replyIntents.removeAll {
                        [.inviteCardObservation, .developCardImage, .inviteCardConnection]
                            .contains($0)
                    }
                }
                if session.cardConnectionScaffoldUsed {
                    // A connection scaffold is a one-time capability. Once its visible question
                    // has been committed, Swift no longer advertises image development.
                    replyIntents.removeAll { $0 == .developCardImage }
                }
                if session.cardConnectionAttemptCount >= 2 {
                    // After the scaffold and one final connection invitation, the next semantic
                    // plan may either authorize a mapping actually found by the person or leave
                    // the card aside. It may not ask another image/connection question.
                    replyIntents.removeAll {
                        [.inviteCardObservation, .developCardImage, .inviteCardConnection]
                            .contains($0)
                    }
                }
            }
            if session.condition.usesCard,
               session.cardDisplayState == .displayed,
               !session.cardGuidanceShared,
               !session.cardConnectionUnavailable,
               effectiveConnection != nil {
                actions.append(.shareCardGuidance)
                if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                    // In v5 the canonical connection is the final card object. Authorization
                    // lands directly in Direct Reflection so its one visible successor can fold
                    // a brief card bridge into Tender/Tender-grounded Fierce. There is no second
                    // card meaning object or confirmation gate.
                    stages = stages.filter {
                        [.directReflection, .safetySupport].contains($0)
                    }
                    replyIntents = replyIntents.filter {
                        [.authorizeCardGuidance, .safetySupport].contains($0)
                    }
                } else {
                    // Legacy sessions retain their separate visible negotiated-reading step.
                    replyIntents.removeAll { $0 == .presentCardReading }
                }
            } else if session.cardGuidanceShared {
                // Authorization is a one-time local capability. Once committed, the only useful
                // next card operation is a visible reading or later reflection; advertising the
                // silent authorization intent again lets a no-op plan loop forever.
                replyIntents.removeAll { $0 == .authorizeCardGuidance }
                if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
                   effectiveConnection != nil {
                    // Compatibility for a v5 session persisted in the former narrow window:
                    // canonical connection plus authorized guidance resumes Direct Reflection
                    // without recreating cardNegotiatedMeaning or a cardMapping confirmation.
                    stages = stages.filter {
                        [.directReflection, .safetySupport].contains($0)
                    }
                    replyIntents = replyIntents.filter {
                        [.directCandidReflection, .safetySupport].contains($0)
                    }
                } else if effectiveCurrentPrompt(for: session)?.target == .cardMapping,
                   nonempty(session.semanticMemory.cardNegotiatedMeaning) {
                    // A negotiated reading is already visible and is now waiting for the
                    // person's response. Keep only the two structurally meaningful paths:
                    // clarify the pending reading, or resolve it and move into real-world
                    // reflection. Observation/connection intents would reopen completed work.
                    replyIntents = replyIntents.filter {
                        [.presentCardReading, .directCandidReflection, .safetySupport].contains($0)
                    }
                } else if effectiveConnection != nil,
                   !nonempty(session.semanticMemory.cardNegotiatedMeaning) {
                    // Once bounded guidance has been released for a real, user-grounded mapping,
                    // the next visible card operation is the negotiated reading. This is a
                    // protocol/object boundary—not Swift judging the meaning of the mapping—and
                    // prevents a Planner from silently skipping the reading into final narrative.
                    replyIntents = replyIntents.filter {
                        [.presentCardReading, .safetySupport].contains($0)
                    }
                }
            }
        case .directReflection:
            if session.protocolVersion >= ReflectionSession.actionFirstReflectionProtocolVersion {
                // Current sessions always resolve the existing optional-action node before the
                // final narrative. A stored synthesis closes further reflection questions and
                // exposes only the one proposal/noAction transaction.
                stages.removeAll { $0 == .narrativeConfirmation }
                replyIntents.removeAll { $0 == .presentFinalNarrative }
                if session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding {
                    replyIntents = replyIntents.filter {
                        [.suggestPractice, .safetySupport].contains($0)
                    }
                }
            } else if session.reflectionReadiness == .narrativeReady {
                // Once the Planner has selected the final narrative, a formatting retry must not
                // reopen reflection in a saved narrative-first session.
                replyIntents = replyIntents.filter {
                    [.presentFinalNarrative, .safetySupport].contains($0)
                }
            }
        case .narrativeConfirmation:
            if let practice = session.semanticMemory.practiceTransition,
               practice.proposal?.status == .confirmed || practice.noActionReason != nil {
                replyIntents = replyIntents.filter {
                    [.requestNarrativeConfirmation, .reviseFinalNarrative,
                     .completeConversation, .safetySupport].contains($0)
                }
            } else {
                replyIntents.removeAll { $0 == .completeConversation }
            }
            actions.append(.completeSession)
        case .optionalAction:
            if session.semanticMemory.practiceTransition?.narrativeReferenceID == nil {
                replyIntents.removeAll { $0 == .completeConversation }
            } else {
                replyIntents.removeAll { $0 == .presentFinalNarrative }
            }
            actions.append(.completeSession)
        case .safetySupport:
            actions.append(.completeSession)
        default:
            break
        }

        return ReflectionProtocolPermissions(
            currentStage: session.protocolStage,
            allowedStages: stages.sorted { $0.rawValue < $1.rawValue },
            allowedActions: actions,
            allowedReplyIntents: replyIntents.sorted { $0.rawValue < $1.rawValue },
            allowedDisclosurePurposes: disclosurePurposes,
            allowedDisclosureTargets: disclosureTargets,
            allowedOperations: allowedProtocolOperations(
                currentStage: session.protocolStage,
                stages: stages,
                actions: actions,
                intents: replyIntents
            ),
            allowedSemanticOperations: allowedSemanticOperations(
                for: session,
                effectiveConnection: effectiveConnection
            )
        )
    }

    /// Explicit operation catalogue for the current typed state. This list advertises capability
    /// only; payload validation and the projector remain the execution authorities.
    private func allowedSemanticOperations(
        for session: ReflectionSession,
        effectiveConnection: TurnCardRealityConnection?
    ) -> [PlannerSemanticOperation] {
        var operations: [PlannerSemanticOperation]

        switch session.protocolStage {
        case .contextualDisclosure:
            // The latest answer is not committed yet, so either the candidate patch completes the
            // three-relation core or it leaves one relation to clarify. Payload validation decides.
            operations = [.clarifyEvent, .advanceToCardConsent]

        case .cardConsent:
            operations = [.inviteCardConsent, .acknowledgeCardConsent, .declineCardConsent]

        case .cardReflection:
            if session.protocolVersion < ReflectionSession.currentProtocolVersion {
                operations = [.presentLegacyCardReading, .continueOpenCardConnection]
            } else if session.cardConnectionUnavailable {
                operations = [.bypassCardConnectionToDirectReflection]
            } else {
                let cardState = EffectiveCardSemanticState(session: session)
                switch cardState.substate {
                case .observation:
                    operations = [
                        .continueCardObservation,
                        .continueCardDevelopment,
                        .inviteRealityConnection,
                        .establishUserAuthoredCardConnection,
                    ]
                case .development:
                    operations = [
                        .inviteRealityConnection,
                        // The latest answer to the first Reality Connection invitation may
                        // establish typed difficulty before any attempt has been committed.
                        // Payload validation, not the previous prompt shape, decides whether the
                        // one-time scaffold is legal.
                        .offerCardConnectionScaffold,
                        .establishUserAuthoredCardConnection,
                    ]
                case .openExploration:
                    operations = [
                        .continueOpenCardConnection,
                        .establishUserAuthoredCardConnection,
                        .bypassCardConnectionToDirectReflection,
                    ]
                    if !cardState.bridgeScaffoldUsed {
                        operations.append(.offerCardConnectionScaffold)
                    }
                    if cardState.candidateBridgeEligible {
                        operations.append(.offerCardConnectionCandidate)
                    }
                case .awaitingCandidateResolution:
                    operations = [
                        .acceptCardConnectionCandidate,
                        .reviseCardConnectionCandidate,
                        .rejectCardConnectionCandidate,
                    ]
                case .guidance:
                    operations = [.authorizeCardGuidance]
                case .none:
                    // The locally rendered observation question precedes the first typed evidence
                    // commit. The latest answer may either remain at Observation, establish the
                    // visible relation and ask Development, or already contain both typed image
                    // relations and move to Reality Connection. Payload validation decides which
                    // candidate is actually supported.
                    operations = session.cardDisplayState == .displayed
                        ? [
                            .continueCardObservation,
                            .continueCardDevelopment,
                            .inviteRealityConnection,
                            .establishUserAuthoredCardConnection,
                        ]
                        : []
                }
                if effectiveConnection != nil,
                   !session.cardGuidanceShared {
                    operations = [.authorizeCardGuidance]
                }
            }

        case .directReflection:
            if session.semanticMemory.reflectionFrame?.action == .synthesizeUnderstanding,
               session.protocolVersion >= ReflectionSession.actionFirstReflectionProtocolVersion {
                operations = [.proposePractice]
            } else {
                operations = [
                    .continueTenderReflection,
                    .continueTenderGroundedFierceReflection,
                    .synthesizeDirectReflection,
                ]
            }

        case .narrativeConfirmation:
            operations = [
                .confirmNarrative,
                .reviseNarrative,
                .proposePractice,
                .completeConversation,
            ]

        case .optionalAction:
            operations = [
                .proposePractice,
                .resolvePractice,
                .confirmNarrative,
                .completeConversation,
            ]

        case .complete:
            operations = [.completeConversation]

        case .safetySupport:
            operations = [.provideSafetySupport, .completeConversation]
        }

        if session.protocolStage != .safetySupport {
            operations.append(.provideSafetySupport)
        }
        return Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
    }

    /// The single cumulative projection for the canonical practice transaction. Every current
    /// practice reader goes through this projection; no caller recombines patch and stored values
    /// independently.
    private struct EffectivePracticeTransitionState {
        let requestedStage: ReflectionProtocolStage
        let replyIntent: TurnReplyIntent
        let resolution: TurnResolvedConfirmation?
        let nextPrompt: TurnNextPrompt?
        let transition: TurnPracticeTransition?

        init(plan: LLMTurnResponsePlan, session: ReflectionSession) {
            requestedStage = plan.requestedStage
            replyIntent = plan.replyIntent
            resolution = plan.resolvedConfirmation
            nextPrompt = plan.nextPrompt
            transition = plan.memoryUpdate.practiceTransition
                ?? session.semanticMemory.practiceTransition
        }
    }

    /// The sole current validation entry for creating or replacing a practice proposal. It
    /// reports the whole invalid cross-field object at once instead of exposing whichever
    /// independent guard happened to run first.
    private func validatePracticeTransition(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        let resolvesPendingPractice = session.protocolStage == .optionalAction
            && [.completeConversation, .presentFinalNarrative].contains(plan.replyIntent)
        guard [.suggestPractice, .revisePractice].contains(plan.replyIntent)
                || resolvesPendingPractice else {
            return
        }
        let state = EffectivePracticeTransitionState(plan: plan, session: session)
        var missing: [TurnPracticeTransitionRequirement] = []

        if resolvesPendingPractice {
            let finalNarrativeAfterAction = plan.replyIntent == .presentFinalNarrative
            if finalNarrativeAfterAction {
                if state.requestedStage != .narrativeConfirmation {
                    missing.append(.requestedStage)
                }
                if plan.localAction.kind != .none { missing.append(.requestedStage) }
                if state.nextPrompt?.kind != .confirmationRequest
                    || state.nextPrompt?.target != .finalNarrative {
                    missing.append(.confirmationPrompt)
                }
            } else {
                if state.requestedStage != .complete { missing.append(.requestedStage) }
                if plan.localAction.kind != .completeSession { missing.append(.requestedStage) }
                if state.nextPrompt?.kind != TurnNextPromptKind.none {
                    missing.append(.confirmationPrompt)
                }
            }
            guard state.resolution?.target == .practice,
                  let decision = state.resolution?.decision,
                  [.accepted, .revised, .declined, .rejected].contains(decision),
                  let pending = session.semanticMemory.practiceTransition,
                  let pendingProposal = pending.proposal,
                  pendingProposal.status == .pendingConfirmation,
                  let transition = state.transition,
                  transition.transactionID == pending.transactionID,
                  transition.narrativeReferenceID == pending.narrativeReferenceID else {
                missing.append(.narrativeResolution)
                throw ReflectionProtocolViolation.incompletePracticeTransition(
                    Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
                )
            }
            if finalNarrativeAfterAction != (pending.narrativeReferenceID == nil) {
                missing.append(.requestedStage)
            }
            switch decision {
            case .accepted:
                guard let proposal = transition.proposal,
                      transition.noActionReason == nil,
                      proposal.status == .confirmed,
                      proposal.id == pendingProposal.id,
                      proposal.kind == pendingProposal.kind,
                      proposal.content == pendingProposal.content,
                      proposal.basis == pendingProposal.basis,
                      proposal.source == pendingProposal.source else {
                    missing.append(.proposal)
                    throw ReflectionProtocolViolation.incompletePracticeTransition(
                        Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
                    )
                }
            case .revised:
                guard let proposal = transition.proposal,
                      transition.noActionReason == nil,
                      proposal.status == .confirmed,
                      proposal.source == .userRevised,
                      proposal.id == pendingProposal.id,
                      nonempty(proposal.content),
                      nonempty(proposal.basis) else {
                    missing.append(.proposal)
                    throw ReflectionProtocolViolation.incompletePracticeTransition(
                        Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
                    )
                }
            case .declined, .rejected:
                guard transition.proposal == nil,
                      transition.noActionReason == .userDeclined else {
                    missing.append(.noActionReason)
                    throw ReflectionProtocolViolation.incompletePracticeTransition(
                        Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
                    )
                }
            case .related, .partlyRelated, .unrelated, .uncertain, .unclear:
                missing.append(.narrativeResolution)
            }
            if !missing.isEmpty {
                throw ReflectionProtocolViolation.incompletePracticeTransition(
                    Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
                )
            }
            return
        }

        if state.requestedStage != .optionalAction {
            missing.append(.requestedStage)
        }
        let isPreNarrativeProposal = session.protocolStage == .directReflection
        let awaitingAcceptedNarrative = session.protocolStage == .optionalAction
            && session.semanticMemory.practiceTransition?.proposal == nil
            && session.semanticMemory.practiceTransition?.noActionReason == nil
        let isReplacingPendingPractice = session.protocolStage == .optionalAction
            && state.replyIntent == .suggestPractice
            && session.semanticMemory.practiceTransition?.proposal?.status
                == .pendingConfirmation
        if isPreNarrativeProposal {
            if state.resolution != nil { missing.append(.narrativeResolution) }
        } else if state.replyIntent == .suggestPractice, awaitingAcceptedNarrative {
            if state.resolution != nil { missing.append(.narrativeResolution) }
        } else if isReplacingPendingPractice {
            if state.resolution?.target != .practice
                || state.resolution?.decision != .revised {
                missing.append(.narrativeResolution)
            }
        } else {
            let expectedResolutionTarget: TurnConfirmationTarget =
                state.replyIntent == .suggestPractice ? .finalNarrative : .practice
            let allowedDecisions: Set<TurnConfirmationDecision> =
                state.replyIntent == .suggestPractice
                    ? [.accepted, .revised]
                    : [.unclear]
            if state.resolution?.target != expectedResolutionTarget
                || !allowedDecisions.contains(state.resolution?.decision ?? .unclear) {
                missing.append(.narrativeResolution)
            }
        }
        if state.nextPrompt?.kind != .confirmationRequest
            || state.nextPrompt?.target != .practice {
            missing.append(.confirmationPrompt)
        }

        guard let transition = state.transition,
              let proposal = transition.proposal,
              transition.noActionReason == nil else {
            missing.append(.proposal)
            throw ReflectionProtocolViolation.incompletePracticeTransition(
                Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
            )
        }
        if !nonempty(transition.transactionID) { missing.append(.proposalID) }
        if !nonempty(proposal.id) { missing.append(.proposalID) }
        if proposal.id != transition.transactionID {
            missing.append(.transactionReference)
        }
        if let awaiting = session.semanticMemory.practiceTransition,
           awaiting.proposal == nil,
           (transition.transactionID != awaiting.transactionID
                || transition.narrativeReferenceID != awaiting.narrativeReferenceID) {
            missing.append(.transactionReference)
        }
        if session.protocolStage == .narrativeConfirmation,
           state.replyIntent == .suggestPractice,
           transition.narrativeReferenceID
            != effectiveCurrentPrompt(for: session)?.referenceID {
            missing.append(.transactionReference)
        }
        if isPreNarrativeProposal,
           transition.narrativeReferenceID != nil {
            missing.append(.transactionReference)
        }
        if !nonempty(proposal.content) { missing.append(.proposalContent) }
        if !nonempty(proposal.basis) { missing.append(.proposalBasis) }
        if proposal.status != .pendingConfirmation { missing.append(.proposalStatus) }
        if state.nextPrompt?.referenceID != proposal.id {
            missing.append(.confirmationReference)
        }

        if !missing.isEmpty {
            throw ReflectionProtocolViolation.incompletePracticeTransition(
                Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
            )
        }
    }

    private func availableDisclosurePurposes(
        in state: EffectiveEventDisclosureState
    ) -> [TurnDisclosureQuestionPurpose] {
        var purposes: [TurnDisclosureQuestionPurpose] = []
        if !state.hasConcreteFocalEvent {
            purposes.append(.identifyConcreteEpisode)
        }
        if !state.hasUserBehaviorOrOmission {
            purposes.append(.clarifyBehavior)
        }
        if !state.hasEventProcess {
            purposes.append(.clarifyEventProcess)
        }
        return purposes.filter {
            !state.memory.receivedDisclosureQuestionPurposes.contains($0)
                || !disclosureTargetIsComplete($0.target, in: state)
        }
    }

    private func allowedProtocolOperations(
        currentStage: ReflectionProtocolStage,
        stages: [ReflectionProtocolStage],
        actions: [TurnLocalActionKind],
        intents: [TurnReplyIntent]
    ) -> [TurnProtocolOperation] {
        var result: [TurnProtocolOperation] = []
        for stage in stages {
            for intent in intents where intentTransitionIsAllowed(
                from: currentStage,
                to: stage,
                intent: intent
            ) {
                let requiredAction: TurnLocalActionKind
                switch intent {
                case .presentTrackingContext:
                    requiredAction = .presentTrackingCue
                case .acknowledgeCardConsent:
                    requiredAction = .drawRandomCard
                case .authorizeCardGuidance:
                    requiredAction = .shareCardGuidance
                case .completeConversation:
                    requiredAction = .completeSession
                default:
                    requiredAction = .none
                }
                guard actions.contains(requiredAction) else { continue }
                let operation = TurnProtocolOperation(
                    requestedStage: stage,
                    replyIntent: intent,
                    localAction: requiredAction
                )
                if !result.contains(operation) { result.append(operation) }
            }
        }
        return result.sorted {
            ($0.requestedStage.rawValue, $0.replyIntent.rawValue, $0.localAction.rawValue)
                < ($1.requestedStage.rawValue, $1.replyIntent.rawValue, $1.localAction.rawValue)
        }
    }

    func validate(
        _ response: LLMTurnControllerResponse,
        for session: ReflectionSession,
        projectedOperation: PlannerSemanticOperation? = nil
    ) throws -> LLMTurnControllerResponse {
        guard !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReflectionProtocolViolation.emptyReply
        }
        let validatedPlan = try validate(
            LLMTurnResponsePlan(
                semanticOperation: projectedOperation,
                projectedOperation: projectedOperation,
                requestedStage: response.requestedStage,
                localAction: response.localAction,
                memoryUpdate: response.memoryUpdate,
                cardConnectionTurnOutcome: response.cardConnectionTurnOutcome,
                resolvedConfirmation: response.resolvedConfirmation,
                nextPrompt: response.nextPrompt,
                replyIntent: response.replyIntent,
                replyGuidance: "validated response"
            ),
            for: session,
            origin: .swiftCommittedResponse
        )
        return LLMTurnControllerResponse(
            requestedStage: validatedPlan.requestedStage,
            localAction: validatedPlan.localAction,
            memoryUpdate: validatedPlan.memoryUpdate,
            cardConnectionTurnOutcome: validatedPlan.cardConnectionTurnOutcome,
            resolvedConfirmation: validatedPlan.resolvedConfirmation,
            nextPrompt: validatedPlan.nextPrompt,
            replyIntent: validatedPlan.replyIntent,
            reply: response.reply
        )
    }

    func validate(
        _ writerResponse: LLMTurnWriterResponse,
        for plan: LLMTurnResponsePlan
    ) throws -> LLMTurnWriterResponse {
        // `realizedIntent` is a typed capability boundary: the Writer cannot replace a validated
        // Planner function with a later-stage function. Natural-language shape, however, is soft
        // quality. A missing or extra question mark must never discard an otherwise legal turn or
        // cause Swift to choose a different conversational direction.
        guard writerResponse.realizedIntent == plan.replyIntent else {
            throw ReflectionProtocolViolation.writerIntentMismatch
        }
        guard !writerResponse.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReflectionProtocolViolation.emptyReply
        }
        return writerResponse
    }

    /// Returns only deterministic response-shape concerns. Whether wording is repetitive,
    /// flattering, inferential, mechanical, or otherwise unnatural requires discourse meaning and
    /// belongs to the semantic Writer Critic, never a Swift phrase list.
    func writerQualityIssues(
        _ writerResponse: LLMTurnWriterResponse,
        for plan: LLMTurnResponsePlan
    ) -> [TurnWriterQualityIssue] {
        var issues: [TurnWriterQualityIssue] = []
        if writerResponse.realizedIntent != plan.replyIntent {
            issues.append(.realizedIntentMismatch)
        }
        guard let nextPrompt = plan.nextPrompt else { return issues }
        let questionCount = writerResponse.reply.reduce(into: 0) { count, character in
            if character == "？" || character == "?" { count += 1 }
        }
        switch nextPrompt.kind {
        case .none where questionCount > 0:
            issues.append(.expectedNoQuestion)
        case .openQuestion where questionCount != 1,
             .confirmationRequest where questionCount != 1:
            issues.append(.expectedSingleQuestion)
        default:
            break
        }
        return issues
    }

    func validate(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws -> LLMTurnResponsePlan {
        try validate(plan, for: session, origin: .plannerOutput)
    }

    private enum ProtocolPlanOrigin {
        case plannerOutput
        case swiftCommittedResponse
    }

    private func validate(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession,
        origin: ProtocolPlanOrigin
    ) throws -> LLMTurnResponsePlan {
        // A projected plan is already the canonical protocol shape. Running it back through the
        // migration normalizer would let legacy labels override the projector and erase the
        // semantic operation required for operation-aware capability validation.
        if plan.projectedOperation != nil {
            return try validateNormalized(
                normalizeProjectedExecutableMemory(in: plan, for: session),
                for: session
            )
        }
        executionAudit?.record(.legacyNormalizer)
        executionAudit?.record(.legacyTransitionBuilder)
        let normalizedPlan = try normalizeEquivalentProtocolLabels(
            in: plan,
            for: session,
            origin: origin
        )
        return try validateNormalized(normalizedPlan, for: session)
    }

    /// Applies only cumulative memory bookkeeping to a projected plan. Protocol fields and the
    /// projected operation are copied verbatim, so legacy normalization cannot override them.
    private func normalizeProjectedExecutableMemory(
        in plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) -> LLMTurnResponsePlan {
        var memoryUpdate = plan.memoryUpdate
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure {
            if let patch = memoryUpdate.episodeStructure {
                let cumulative = session.semanticMemory.episodeStructure?.merging(patch) ?? patch
                memoryUpdate.episodeStructure = cumulative.normalizingGroundedPresence()
            }
            let effectiveStatement = memoryUpdate.selfCriticalStatement
                ?? session.semanticMemory.selfCriticalStatement
            let effectiveStatus = memoryUpdate.selfCriticismStatus
                ?? session.semanticMemory.selfCriticismStatus
            if nonempty(effectiveStatement), effectiveStatus == .unresolved {
                memoryUpdate.selfCriticismStatus = .present
            }
            let disclosure = EffectiveEventDisclosureState(
                memory: session.semanticMemory,
                update: memoryUpdate
            )
            memoryUpdate.eventDisclosureOutcome = isEventDisclosureCoreComplete(disclosure)
                ? .readyForTenderOrCard
                : (disclosure.hasConcreteFocalEvent
                    ? .needsBehaviorOrProcess
                    : .needsConcreteEpisode)
            if let answeredPurpose = effectiveCurrentPrompt(for: session)?.disclosurePurpose {
                memoryUpdate.receivedDisclosureQuestionPurposes = Array(
                    Set(
                        (memoryUpdate.receivedDisclosureQuestionPurposes ?? [])
                            + session.semanticMemory.receivedDisclosureQuestionPurposes
                            + [answeredPurpose]
                    )
                ).sorted { $0.rawValue < $1.rawValue }
            }
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
            memoryUpdate.candidUnderstanding = nil
            memoryUpdate.fierceUnderstanding = nil
        }
        return LLMTurnResponsePlan(
            semanticOperation: plan.semanticOperation,
            projectedOperation: plan.projectedOperation,
            requestedStage: plan.requestedStage,
            localAction: plan.localAction,
            memoryUpdate: memoryUpdate,
            cardConnectionTurnOutcome: plan.cardConnectionTurnOutcome,
            resolvedConfirmation: plan.resolvedConfirmation,
            nextPrompt: plan.nextPrompt,
            replyIntent: plan.replyIntent,
            replyGuidance: plan.replyGuidance,
            cardReferenceSelection: plan.cardReferenceSelection
        )
    }

    /// Reports metadata defects that do not change the visible conversational function. The
    /// caller records these after validation, while allowing the Writer and atomic stage commit to
    /// continue. This deliberately never infers a practice category from prose.
    func nonBlockingWarnings(
        originalPlan: LLMTurnResponsePlan,
        validatedPlan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) -> [TurnProtocolWarning] {
        var warnings: [TurnProtocolWarning] = []

        if originalPlan.nextPrompt != validatedPlan.nextPrompt {
            warnings.append(.normalizedNextPromptMetadata)
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           hasLockedPostGuidanceConnection(session),
           originalPlan.memoryUpdate.cardRealityConnection?.normalizedConfirmed
            == effectiveCardRealityConnection(for: session),
           validatedPlan.memoryUpdate.cardRealityConnection == nil {
            warnings.append(.redundantConfirmedConnectionPatch)
        }
        // Current disclosure semantics belong to the Planner: Swift neither ranks possible event
        // questions nor decides whether the scene and behavior are sufficient to leave the stage.
        // Only the typed operation, prompt shape, transition, and local capability are validated.
        if session.protocolStage != .contextualDisclosure,
           let purpose = validatedPlan.nextPrompt?.purpose?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !purpose.isEmpty,
           session.semanticMemory.answeredQuestionPurposes.contains(where: {
               $0.trimmingCharacters(in: .whitespacesAndNewlines)
                   .caseInsensitiveCompare(purpose) == .orderedSame
           }) {
            // Repetition is conversational quality, not a capability violation.
            warnings.append(.repeatedQuestionPurpose)
        }

        return Array(Set(warnings)).sorted { $0.rawValue < $1.rawValue }
    }

    /// A typed reply intent already establishes the unique protocol destination and which
    /// application-owned object will wait for the person's response. Some language models repeat
    /// that decision inconsistently in `requestedStage` or label the natural confirmation wording
    /// as `openQuestion`/`none`. Treating those redundant labels as fatal semantic errors causes a
    /// needless Planner retry even though the capability request is unambiguous.
    ///
    /// This normalization never reads the person's text and never chooses a conversational
    /// direction. It only canonicalizes labels already implied by the typed intent, and only when
    /// that destination is permitted from the current Swift-owned stage. Local actions, object
    /// references, confirmation resolutions, and persistence lifecycle are still checked below.
    private func normalizeEquivalentProtocolLabels(
        in plan: LLMTurnResponsePlan,
        for session: ReflectionSession,
        origin: ProtocolPlanOrigin
    ) throws -> LLMTurnResponsePlan {
        let splitPlan = splitCombinedCardGuidanceRequest(plan)
        let protocolPlan: LLMTurnResponsePlan
        switch origin {
        case .plannerOutput:
            protocolPlan = try normalizeCardConnectionTurnOutcome(
                in: splitPlan,
                for: session
            )
        case .swiftCommittedResponse:
            protocolPlan = splitPlan
        }
        var memoryUpdate = protocolPlan.memoryUpdate

        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure {
            if let patch = memoryUpdate.episodeStructure {
                let cumulative = session.semanticMemory.episodeStructure?.merging(patch) ?? patch
                memoryUpdate.episodeStructure = cumulative.normalizingGroundedPresence()
            }

            let effectiveSelfCriticalStatement = memoryUpdate.selfCriticalStatement
                ?? session.semanticMemory.selfCriticalStatement
            let effectiveSelfCriticismStatus = memoryUpdate.selfCriticismStatus
                ?? session.semanticMemory.selfCriticismStatus
            if nonempty(effectiveSelfCriticalStatement),
               effectiveSelfCriticismStatus == .unresolved {
                memoryUpdate.selfCriticismStatus = .present
            }

            let disclosureState = EffectiveEventDisclosureState(
                memory: session.semanticMemory,
                update: memoryUpdate
            )
            memoryUpdate.eventDisclosureOutcome = if isEventDisclosureCoreComplete(
                disclosureState
            ) {
                .readyForTenderOrCard
            } else if disclosureState.hasConcreteFocalEvent {
                .needsBehaviorOrProcess
            } else {
                .needsConcreteEpisode
            }
        }

        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure,
           let answeredPurpose = effectiveCurrentPrompt(for: session)?.disclosurePurpose {
            // Receiving the next user message deterministically answers the visible question
            // function, even when the semantic relation remains unresolved. The Planner still
            // decides what the answer means; Swift only closes the interaction loop.
            memoryUpdate.receivedDisclosureQuestionPurposes = Array(
                Set(
                    (memoryUpdate.receivedDisclosureQuestionPurposes ?? [])
                        + session.semanticMemory.receivedDisclosureQuestionPurposes
                        + [answeredPurpose]
                )
            ).sorted { $0.rawValue < $1.rawValue }
        }

        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           hasLockedPostGuidanceConnection(session),
           let proposed = memoryUpdate.cardRealityConnection?.normalizedConfirmed,
           proposed == effectiveCardRealityConnection(for: session) {
            // The confirmed pre-guidance connection is immutable once its guidance has been used.
            // An identical echo is harmless metadata, not a new persistence or authorization act.
            memoryUpdate.cardRealityConnection = nil
            memoryUpdate.cardConnectionOutcome = nil
        }

        if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
            // Retired scalar reflection fields remain decodable in saved sessions, but current
            // plans cannot revive them as a parallel mode or readiness truth source.
            memoryUpdate.candidUnderstanding = nil
            memoryUpdate.fierceUnderstanding = nil
        }

        var requestedStage = protocolPlan.requestedStage
        var replyIntent = protocolPlan.replyIntent
        var resolvedConfirmation = protocolPlan.resolvedConfirmation
        let operationMatches = permissions(for: session).allowedOperations.filter {
            $0.replyIntent == protocolPlan.replyIntent
                && $0.localAction == protocolPlan.localAction.kind
        }
        if operationMatches.count == 1,
           let operation = operationMatches.first {
            // A typed intent/action pair may identify exactly one legal destination. Repair the
            // redundant stage label without changing the Planner's conversational choice. This
            // prevents a flattened permission catalogue from surfacing a technical interruption.
            requestedStage = operation.requestedStage
        }
        if let destination = uniqueDestinationStage(for: protocolPlan.replyIntent),
           permissions(for: session).allowedStages.contains(destination) {
            requestedStage = destination
        }
        let resolvesCardMapping =
            effectiveCurrentPrompt(for: session)?.target == .cardMapping
            && protocolPlan.replyIntent == .directCandidReflection
            && protocolPlan.resolvedConfirmation?.target == .cardMapping
            && protocolPlan.resolvedConfirmation.map {
                [TurnConfirmationDecision.accepted, .revised, .rejected]
                    .contains($0.decision)
            } == true
        if resolvesCardMapping,
           permissions(for: session).allowedStages.contains(.directReflection) {
            // Resolving a negotiated card reading is a protocol boundary. The confirmation-only
            // transaction lands in directReflection; a fresh semantic plan then decides whether
            // a supported candid question is useful or the material is ready for final narrative.
            requestedStage = .directReflection
            // Do not commit semantic work for a question the user has not seen yet. A revised or
            // rejected negotiated meaning may still be saved, but Fierce understanding and
            // completed question functions belong to the fresh continuation transaction.
            memoryUpdate.answeredQuestionPurposes = nil
            memoryUpdate.candidUnderstanding = nil
            memoryUpdate.fierceUnderstanding = nil
            memoryUpdate.finalNarrative = nil
            memoryUpdate.practiceTransition = nil
        }
        if resolvesCardMapping,
           protocolPlan.resolvedConfirmation?.decision == .rejected {
            // A rejected candidate remains useful study history in the transcript, but it is no
            // longer valid semantic evidence. Clear the model-facing candidate atomically with
            // the application-owned confirmation resolution so a later narrative cannot reuse it.
            if session.protocolVersion < ReflectionSession.currentProtocolVersion {
                memoryUpdate.cardImageRelation = ""
                memoryUpdate.cardRealityMapping = ""
            }
            memoryUpdate.cardInterpretiveTension = ""
            memoryUpdate.cardNegotiatedMeaning = ""
        }

        let resolvesPreGuidanceConnection =
            effectiveCurrentPrompt(for: session)?.target == .cardRealityConnection
            && resolvedConfirmation?.target == .cardRealityConnection
        if resolvesPreGuidanceConnection {
            switch resolvedConfirmation?.decision {
            case .accepted:
                if let promoted = effectiveCardRealityConnection(
                    for: session,
                    memoryUpdate: memoryUpdate,
                    resolution: resolvedConfirmation
                ) {
                    memoryUpdate.cardRealityConnection = promoted
                    memoryUpdate.clearPendingCardRealityConnection = true
                    memoryUpdate.cardConnectionOutcome = .connectionConfirmed
                }
            case .revised:
                if let revised = memoryUpdate.cardRealityConnection?.normalizedConfirmed,
                   revised.source == .userRevised {
                    memoryUpdate.cardRealityConnection = revised
                    memoryUpdate.clearPendingCardRealityConnection = true
                    memoryUpdate.cardConnectionOutcome = .connectionConfirmed
                }
            case .rejected, .declined:
                memoryUpdate.clearPendingCardRealityConnection = true
                memoryUpdate.cardConnectionOutcome = .candidateRejected
            case .unclear, .related, .partlyRelated, .unrelated, .uncertain, .none:
                break
            }
        }

        if memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil,
           memoryUpdate.cardConnectionOutcome == nil {
            memoryUpdate.cardConnectionOutcome = .connectionConfirmed
        }

        var localAction = protocolPlan.localAction
        let currentPrompt = effectiveCurrentPrompt(for: session)
        let resolvesAcceptedCardConsent =
            session.protocolStage == .cardConsent
            && currentPrompt?.target == .cardConsent
            && resolvedConfirmation?.target == .cardConsent
            && resolvedConfirmation?.decision == .accepted
        if resolvesAcceptedCardConsent,
           permissions(for: session).allowedActions.contains(.drawRandomCard) {
            // The model has already supplied the semantic decision: the pending card invitation
            // was accepted. Swift owns all protocol mechanics that follow from that typed
            // decision, so normalize redundant labels instead of asking the person to consent a
            // second time because of a malformed stage, intent, action, prompt, or reference.
            requestedStage = .cardConsent
            replyIntent = .acknowledgeCardConsent
            localAction = TurnLocalActionRequest(kind: .drawRandomCard)
            resolvedConfirmation = TurnResolvedConfirmation(
                target: .cardConsent,
                decision: .accepted,
                referenceID: currentPrompt?.referenceID
            )
        }

        let postPatchConnection = effectiveCardRealityConnection(
            for: session,
            memoryUpdate: memoryUpdate,
            resolution: resolvedConfirmation
        )
        let hasTypedCurrentConnectionResolution =
            protocolPlan.cardConnectionTurnOutcome != nil
            || resolvesPreGuidanceConnection
        let authorizesCurrentTypedCardMapping =
            session.protocolVersion >= ReflectionSession.currentProtocolVersion
            && session.protocolStage == .cardReflection
            && !session.cardGuidanceShared
            && !session.cardConnectionUnavailable
            && session.condition.usesCard
            && session.cardDisplayState == .displayed
            && postPatchConnection != nil
            && hasTypedCurrentConnectionResolution
        if authorizesCurrentTypedCardMapping {
            // The Planner has already made the only semantic judgment Swift needs: the latest
            // answer contains a user-authored image-to-life mapping. From this typed object onward
            // workflow mechanics are application-owned. Canonicalize any filler acknowledgement,
            // repeated connection invitation, premature reading, or obsolete deepening label into
            // silent guidance authorization. The fresh current-protocol turn enters Direct
            // Reflection. No image text or case-specific vocabulary is inspected here.
            requestedStage = .directReflection
            // Preserve .directCandidReflection for the combined Guidance+Tender turn
            // (establishUserAuthoredCardConnection). The projector already set it.
            if replyIntent != .directCandidReflection {
                replyIntent = .authorizeCardGuidance
            }
            localAction = TurnLocalActionRequest(kind: .shareCardGuidance)
            if !resolvesPreGuidanceConnection {
                resolvedConfirmation = nil
            }
            memoryUpdate.clearPendingCardRealityConnection = true
            memoryUpdate.cardConnectionOutcome = .connectionConfirmed
            memoryUpdate.cardNegotiatedMeaning = nil
            memoryUpdate.contextCueOffered = nil
            memoryUpdate.candidUnderstanding = nil
            memoryUpdate.fierceUnderstanding = nil
            memoryUpdate.finalNarrative = nil
            memoryUpdate.practiceTransition = nil
        }
        if protocolPlan.replyIntent == .completeConversation,
           localAction.kind == .none,
           permissions(for: session).allowedActions.contains(.completeSession) {
            // completeConversation is an unambiguous request to finish, while Swift still owns the
            // actual persistence side effect. Canonicalize the redundant action label, then let the
            // strict confirmation, selected-practice, and persistence checks below decide whether
            // completion is legal.
            localAction = TurnLocalActionRequest(kind: .completeSession)
        }

        var nextPrompt = protocolPlan.nextPrompt
        if protocolPlan.replyIntent == .completeConversation {
            nextPrompt = TurnNextPrompt.none
        }
        if let prompt = protocolPlan.nextPrompt {
            if protocolPlan.replyIntent == .completeConversation {
                nextPrompt = TurnNextPrompt.none
            } else if let target = confirmationTargetEstablished(by: protocolPlan.replyIntent),
                      target != .practice {
                // The typed intent uniquely establishes this target. Extra or missing
                // nextPrompt metadata cannot change the conversational function, so canonicalize
                // it instead of discarding a legal turn.
                nextPrompt = .confirmationRequest(
                    target: target,
                    referenceID: nil
                )
            } else {
                switch prompt.kind {
                case .none:
                    nextPrompt = TurnNextPrompt.none
                case .openQuestion:
                    nextPrompt = .openQuestion(
                        purpose: nonempty(prompt.purpose)
                            ? prompt.purpose!
                            : "intent_\(protocolPlan.replyIntent.rawValue)",
                        focus: nonempty(prompt.focus)
                            ? prompt.focus!
                            : "continue_current_conversation",
                        disclosurePurpose: prompt.disclosurePurpose,
                        disclosureTarget: prompt.disclosureTarget,
                        disclosureReopenReason: prompt.disclosureReopenReason
                    )
                case .confirmationRequest:
                    if let target = prompt.target {
                        nextPrompt = .confirmationRequest(
                            target: target,
                            referenceID: target == .practice
                                ? prompt.referenceID
                                : nil
                        )
                    }
                }
            }
        }
        if resolvesAcceptedCardConsent
            || resolvesCardMapping
            || (authorizesCurrentTypedCardMapping
                && nextPrompt?.kind != .openQuestion) {
            // The local transition never displays a question UNLESS this is a
            // combined Guidance+Tender turn (establishUserAuthoredCardConnection),
            // which carries its own openQuestion.
            nextPrompt = TurnNextPrompt.none
        }

        return LLMTurnResponsePlan(
            semanticOperation: protocolPlan.semanticOperation,
            requestedStage: requestedStage,
            localAction: localAction,
            memoryUpdate: memoryUpdate,
            cardConnectionTurnOutcome: protocolPlan.cardConnectionTurnOutcome,
            resolvedConfirmation: resolvedConfirmation,
            nextPrompt: nextPrompt,
            replyIntent: replyIntent,
            replyGuidance: protocolPlan.replyGuidance,
            cardReferenceSelection: protocolPlan.cardReferenceSelection
        )
    }

    /// Converts the Planner's mutually exclusive card outcome into the existing application
    /// memory patch and, only for a persisted candidate, into a confirmation resolution. This is
    /// the sole place where Card Reality Connection outcomes become protocol mechanics.
    private func normalizeCardConnectionTurnOutcome(
        in plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws -> LLMTurnResponsePlan {
        guard session.protocolVersion >= ReflectionSession.currentProtocolVersion,
              session.protocolStage == .cardReflection else {
            return plan
        }

        // A v5 Planner may not send the generic confirmation field for a card connection. The
        // typed outcome below is the only legal source for this resolution.
        if plan.resolvedConfirmation?.target == .cardRealityConnection {
            throw ReflectionProtocolViolation.invalidPreGuidanceConnectionConfirmation
        }

        guard let outcome = plan.cardConnectionTurnOutcome else {
            // Current card turns may omit the outcome after guidance has already been shared, but
            // before guidance a raw connection patch is an obsolete protocol shape.
            if !session.cardGuidanceShared,
               plan.memoryUpdate.cardRealityConnection != nil
                || plan.memoryUpdate.clearCardRealityConnection == true
                || plan.memoryUpdate.clearPendingCardRealityConnection == true
                || plan.memoryUpdate.cardConnectionOutcome != nil {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            return plan
        }

        var memory = plan.memoryUpdate
        guard memory.cardRealityConnection == nil,
              memory.clearCardRealityConnection == nil,
              memory.clearPendingCardRealityConnection == nil,
              memory.cardConnectionOutcome == nil else {
            // The raw memory fields are application-owned projections. They cannot be combined
            // with the Planner union in a single new-protocol response.
            throw ReflectionProtocolViolation.illegalReplyIntent
        }

        let interactionState = cardConnectionInteractionState(for: session)
        let pending = session.semanticMemory.pendingCardRealityConnection
        let currentPrompt = effectiveCurrentPrompt(for: session)

        func resolution(
            _ decision: TurnConfirmationDecision
        ) throws -> TurnResolvedConfirmation {
            guard interactionState == .awaitingCandidateResolution,
                  pending?.isStructurallyComplete == true,
                  currentPrompt?.target == .cardRealityConnection else {
                throw ReflectionProtocolViolation.invalidPreGuidanceConnectionConfirmation
            }
            return TurnResolvedConfirmation(
                target: .cardRealityConnection,
                decision: decision,
                referenceID: currentPrompt?.referenceID
            )
        }

        switch (interactionState, outcome.kind) {
        case (.openExploration, .userAuthoredConnection):
            guard let connection = outcome.connection?.normalizedConfirmed,
                  connection.source == .userAuthored else {
                throw ReflectionProtocolViolation.incompleteCardRealityConnection
            }
            memory.cardRealityConnection = connection
            memory.clearPendingCardRealityConnection = true
            memory.cardConnectionOutcome = .connectionConfirmed
            return LLMTurnResponsePlan(
                semanticOperation: plan.semanticOperation,
                requestedStage: .directReflection,
                localAction: .init(kind: .shareCardGuidance),
                memoryUpdate: memory,
                cardConnectionTurnOutcome: outcome,
                resolvedConfirmation: nil,
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .authorizeCardGuidance,
                replyGuidance: "Commit the user-authored image-to-life connection and silently authorize guidance.",
                cardReferenceSelection: plan.cardReferenceSelection
            )

        case (.openExploration, .connectionStillUnclear):
            memory.cardConnectionOutcome = .noConnectionFound
            return LLMTurnResponsePlan(
                semanticOperation: plan.semanticOperation,
                requestedStage: plan.requestedStage,
                localAction: plan.localAction,
                memoryUpdate: memory,
                cardConnectionTurnOutcome: outcome,
                resolvedConfirmation: nil,
                nextPrompt: plan.nextPrompt,
                replyIntent: plan.replyIntent,
                replyGuidance: plan.replyGuidance,
                cardReferenceSelection: plan.cardReferenceSelection
            )

        case (.awaitingCandidateResolution, .candidateAccepted):
            guard let pending else {
                throw ReflectionProtocolViolation.invalidPreGuidanceConnectionConfirmation
            }
            memory.cardRealityConnection = TurnCardRealityConnection(
                imageRelation: pending.imageRelation,
                realityMapping: pending.candidateRealityMapping,
                source: .userAccepted
            )
            memory.clearPendingCardRealityConnection = true
            memory.cardConnectionOutcome = .connectionConfirmed
            return LLMTurnResponsePlan(
                semanticOperation: plan.semanticOperation,
                requestedStage: .directReflection,
                localAction: .init(kind: .shareCardGuidance),
                memoryUpdate: memory,
                cardConnectionTurnOutcome: outcome,
                resolvedConfirmation: try resolution(.accepted),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .authorizeCardGuidance,
                replyGuidance: "Commit the accepted candidate and silently authorize guidance.",
                cardReferenceSelection: plan.cardReferenceSelection
            )

        case (.awaitingCandidateResolution, .candidateRevised):
            guard let connection = outcome.connection?.normalizedConfirmed,
                  connection.source == .userRevised else {
                throw ReflectionProtocolViolation.incompleteCardRealityConnection
            }
            memory.cardRealityConnection = connection
            memory.clearPendingCardRealityConnection = true
            memory.cardConnectionOutcome = .connectionConfirmed
            return LLMTurnResponsePlan(
                semanticOperation: plan.semanticOperation,
                requestedStage: .directReflection,
                localAction: .init(kind: .shareCardGuidance),
                memoryUpdate: memory,
                cardConnectionTurnOutcome: outcome,
                resolvedConfirmation: try resolution(.revised),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .authorizeCardGuidance,
                replyGuidance: "Commit the user's revised connection and silently authorize guidance.",
                cardReferenceSelection: plan.cardReferenceSelection
            )

        case (.awaitingCandidateResolution, .candidateRejected):
            memory.clearPendingCardRealityConnection = true
            memory.cardConnectionOutcome = .candidateRejected
            return LLMTurnResponsePlan(
                semanticOperation: plan.semanticOperation,
                requestedStage: plan.requestedStage,
                localAction: plan.localAction,
                memoryUpdate: memory,
                cardConnectionTurnOutcome: outcome,
                resolvedConfirmation: try resolution(.rejected),
                nextPrompt: plan.nextPrompt,
                replyIntent: plan.replyIntent,
                replyGuidance: plan.replyGuidance,
                cardReferenceSelection: plan.cardReferenceSelection
            )

        default:
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
    }

    /// Guidance authorization is a local capability operation. A legacy Planner may combine it
    /// with its visible negotiated reading, while a current Planner may still emit that retired
    /// shape during repair. Split either shape into the existing silent authorization pass; the
    /// next visible turn is selected from the protocol-version-specific capability (legacy reading
    /// or current Direct Reflection).
    ///
    /// The authorization pass commits only image/reality evidence. It must not establish a hidden
    /// card-mapping confirmation or save a negotiated meaning before that reading is displayed.
    private func splitCombinedCardGuidanceRequest(
        _ plan: LLMTurnResponsePlan
    ) -> LLMTurnResponsePlan {
        guard plan.localAction.kind == .shareCardGuidance,
              plan.replyIntent == .presentCardReading else {
            return plan
        }

        var evidenceOnlyMemory = plan.memoryUpdate
        evidenceOnlyMemory.cardNegotiatedMeaning = nil
        evidenceOnlyMemory.contextCueOffered = nil
        evidenceOnlyMemory.candidUnderstanding = nil
        evidenceOnlyMemory.fierceUnderstanding = nil
        evidenceOnlyMemory.finalNarrative = nil
        evidenceOnlyMemory.practiceTransition = nil

        return LLMTurnResponsePlan(
            semanticOperation: plan.semanticOperation,
            requestedStage: .cardReflection,
            localAction: plan.localAction,
            memoryUpdate: evidenceOnlyMemory,
            cardConnectionTurnOutcome: plan.cardConnectionTurnOutcome,
            resolvedConfirmation: plan.resolvedConfirmation,
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "Authorize the user-grounded image-to-reality relation; the next visible turn follows the protocol-version-specific capability."
        )
    }

    private func uniqueDestinationStage(
        for intent: TurnReplyIntent
    ) -> ReflectionProtocolStage? {
        switch intent {
        case .presentTrackingContext:
            return .contextualDisclosure
        case .inviteCardConsent:
            return .cardConsent
        case .presentCardReading:
            return .cardReflection
        case .presentFinalNarrative,
             .requestNarrativeConfirmation,
             .reviseFinalNarrative:
            return .narrativeConfirmation
        case .suggestPractice, .revisePractice:
            return .optionalAction
        case .completeConversation:
            return .complete
        default:
            return nil
        }
    }

    private func confirmationTargetEstablished(
        by intent: TurnReplyIntent
    ) -> TurnConfirmationTarget? {
        switch intent {
        case .presentTrackingContext:
            return .trackingRelationship
        case .inviteCardConsent:
            return .cardConsent
        case .presentCardReading:
            return .cardMapping
        case .presentFinalNarrative,
             .requestNarrativeConfirmation,
             .reviseFinalNarrative:
            return .finalNarrative
        case .suggestPractice, .revisePractice:
            return .practice
        default:
            return nil
        }
    }

    private func validateNormalized(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws -> LLMTurnResponsePlan {
        let authorizesCombinedUserAuthoredTurn =
            isAuthorizedCombinedUserAuthoredTurn(plan, for: session)
        let isSilentLocalTransaction = [
            TurnLocalActionKind.drawRandomCard,
            TurnLocalActionKind.shareCardGuidance,
        ].contains(plan.localAction.kind)
        if !isSilentLocalTransaction,
           plan.replyGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReflectionProtocolViolation.emptyReply
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           plan.memoryUpdate.legacyConnectionFieldsPresentInPayload {
            throw ReflectionProtocolViolation.legacyCardConnectionPatchNotAllowed
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           let observation = plan.memoryUpdate.cardObservationEvidence,
           !observation.hasContent {
            throw ReflectionProtocolViolation.conflictingMemoryPatch
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           let development = plan.memoryUpdate.cardDevelopmentEvidence,
           !development.hasContent {
            throw ReflectionProtocolViolation.conflictingMemoryPatch
        }
        if session.protocolVersion < ReflectionSession.currentProtocolVersion,
           plan.memoryUpdate.cardRealityMappingSource != nil,
           !(nonempty(plan.memoryUpdate.cardImageRelation)
                && nonempty(plan.memoryUpdate.cardRealityMapping)) {
            throw ReflectionProtocolViolation.connectionSourceWithoutContent
        }
        if let proposed = plan.memoryUpdate.cardRealityConnection,
           proposed.normalizedConfirmed == nil {
            throw ReflectionProtocolViolation.incompleteCardRealityConnection
        }
        if let pending = plan.memoryUpdate.pendingCardRealityConnection,
           !pending.isStructurallyComplete {
            throw ReflectionProtocolViolation.incompleteCardRealityConnection
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           hasLockedPostGuidanceConnection(session) {
            if plan.memoryUpdate.clearCardRealityConnection == true
                || plan.memoryUpdate.pendingCardRealityConnection != nil {
                throw ReflectionProtocolViolation.confirmedCardConnectionIsImmutable
            }
            if let proposed = plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed,
               proposed != effectiveCardRealityConnection(for: session) {
                throw ReflectionProtocolViolation.confirmedCardConnectionIsImmutable
            }
        }
        if plan.resolvedConfirmation?.target == .cardRealityConnection {
            let current = effectiveCurrentPrompt(for: session)
            guard current?.kind == .confirmationRequest,
                  current?.target == .cardRealityConnection,
                  let pending = session.semanticMemory.pendingCardRealityConnection,
                  pending.isStructurallyComplete,
                  (current?.referenceID == nil
                    || current?.referenceID == pending.id.uuidString) else {
                throw ReflectionProtocolViolation.invalidPreGuidanceConnectionConfirmation
            }
            if plan.resolvedConfirmation?.decision == .revised {
                guard let revised = plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed,
                      revised.source == .userRevised else {
                    throw ReflectionProtocolViolation.incompleteCardRealityConnection
                }
            }
        }
        let effectiveConnection = effectiveCardRealityConnection(
            for: session,
            memoryUpdate: plan.memoryUpdate,
            resolution: plan.resolvedConfirmation
        )
        if plan.memoryUpdate.cardConnectionOutcome == .connectionConfirmed,
           effectiveConnection == nil {
            throw ReflectionProtocolViolation.incompleteCardRealityConnection
        }
        if plan.localAction.kind == .shareCardGuidance,
           effectiveConnection == nil {
            // Report the missing dependency before the generic capability check so recovery can
            // request one complete connection patch instead of retrying the same illegal action.
            throw ReflectionProtocolViolation.shareGuidanceWithoutConfirmedConnection
        }
        let permission = permissions(
            for: session,
            effectiveConnection: effectiveConnection
        )
        let isCurrentProjectedPlan = session.protocolVersion >= ReflectionSession.currentProtocolVersion
            && plan.projectedOperation != nil
        if let projectedOperation = plan.projectedOperation, isCurrentProjectedPlan {
            // Operation authority comes from the last committed state. Candidate effects may
            // expose the successor capability, but cannot retroactively invalidate the operation
            // that produced them (for example, establishing a connection exposes authorization).
            let committedPermission = permissions(for: session)
            guard committedPermission.allowedSemanticOperations.contains(projectedOperation) else {
                throw SemanticMappingViolation.semanticOperationNotAllowed(
                    projectedOperation,
                    session.protocolStage
                )
            }
        } else {
            guard permission.allowedStages.contains(plan.requestedStage) else {
                throw ReflectionProtocolViolation.illegalStageTransition
            }
            guard permission.allowedActions.contains(plan.localAction.kind) else {
                throw ReflectionProtocolViolation.illegalLocalAction
            }
            guard permission.allowedReplyIntents.contains(plan.replyIntent)
                    || authorizesCombinedUserAuthoredTurn else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        if let selection = plan.cardReferenceSelection {
            let canonicalReference = session.card.flatMap {
                CardService().canonicalReferenceGuidance(for: $0)
            }
            let relationCount = canonicalReference?.relations.count ?? 0
            let hasGroundedMapping = effectiveCardRealityConnection(for: session) != nil
            let isQuestionOperation =
                (session.protocolVersion < ReflectionSession.currentProtocolVersion
                    && plan.replyIntent == .presentCardReading
                    && plan.nextPrompt?.kind == .confirmationRequest
                    && plan.nextPrompt?.target == .cardMapping)
                || (plan.replyIntent == .directCandidReflection
                    && plan.nextPrompt?.kind == .openQuestion)
            guard session.condition == .cardMediated,
                  session.cardDisplayState == .displayed,
                  !session.cardWasSetAside,
                  session.cardGuidanceShared,
                  hasGroundedMapping,
                  (session.protocolStage == .cardReflection
                    || session.protocolStage == .directReflection),
                  relationCount > 0,
                  (0..<relationCount).contains(selection.relationIndex),
                  isQuestionOperation else {
                throw ReflectionProtocolViolation.invalidCardReferenceSelection
            }
        }
        if !isCurrentProjectedPlan, !permission.allowedOperations.isEmpty {
            let selectedOperation = TurnProtocolOperation(
                requestedStage: plan.requestedStage,
                replyIntent: plan.replyIntent,
                localAction: plan.localAction.kind
            )
            guard permission.allowedOperations.contains(selectedOperation)
                    || authorizesCombinedUserAuthoredTurn else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        if plan.replyIntent == .authorizeCardGuidance {
            // The intent is the typed label for the silent local action, never a standalone
            // conversational turn. Requiring both sides of this pair prevents Writer calls for an
            // authorization that has already happened or was never requested.
            guard plan.localAction.kind == .shareCardGuidance,
                  isCurrentProjectedPlan || !session.cardGuidanceShared else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        try validatePracticeTransition(plan, for: session)
        try validateReflectionFrame(plan, for: session)
        if session.protocolStage == .contextualDisclosure,
           plan.replyIntent != .safetySupport {
            try validateCurrentDisclosurePlan(plan, for: session)
        }
        try validateIntentTransition(plan, currentStage: session.protocolStage)
        try validateInteractionContract(plan, for: session)

        if plan.localAction.kind == .presentTrackingCue {
            let requestedIDs = plan.localAction.trackingCueIDs
            guard !requestedIDs.isEmpty,
                  Set(requestedIDs).count == requestedIDs.count else {
                throw ReflectionProtocolViolation.unknownTrackingCue
            }
            let available = eligibleTrackingCueIDs(in: session)
            let requested = Set(requestedIDs)
            guard requested.isSubset(of: available) else {
                throw ReflectionProtocolViolation.unknownTrackingCue
            }
            guard requested.isDisjoint(with: session.presentedTrackingCueIDs) else {
                throw ReflectionProtocolViolation.duplicateTrackingCue
            }
        } else if !plan.localAction.trackingCueIDs.isEmpty {
            throw ReflectionProtocolViolation.illegalLocalAction
        }

        if let assessments = plan.memoryUpdate.trackingAssessments {
            // A cue cannot be assessed in the same turn in which it is first shown: only the
            // person's later answer can make it related, partly related, or unrelated.
            guard assessments.allSatisfy({
                session.presentedTrackingCueIDs.contains($0.cueID)
            }) else {
                throw ReflectionProtocolViolation.unknownTrackingCue
            }
            if let activeID = session.activeTrackingPresentationID,
               let presentation = session.trackingPresentations.first(where: {
                   $0.id == activeID
               }) {
                let activeCueIDs = Set(presentation.cueIDs)
                guard assessments.allSatisfy({
                    activeCueIDs.contains($0.cueID)
                }) else {
                    throw ReflectionProtocolViolation.unknownTrackingCue
                }
            }
        }

        if plan.localAction.kind == .drawRandomCard,
           plan.requestedStage != .cardConsent {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        if plan.localAction.kind == .drawRandomCard,
           plan.replyIntent != .acknowledgeCardConsent {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if plan.localAction.kind == .presentTrackingCue,
           plan.requestedStage != .contextualDisclosure {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        if plan.localAction.kind == .presentTrackingCue,
           plan.replyIntent != .presentTrackingContext {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if plan.localAction.kind == .shareCardGuidance,
           plan.requestedStage != (
               session.protocolVersion >= ReflectionSession.currentProtocolVersion
                    ? .directReflection
                    : .cardReflection
           ) {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        if plan.localAction.kind == .shareCardGuidance,
           plan.replyIntent != .authorizeCardGuidance
            && plan.replyIntent != .directCandidReflection {
            // directCandidReflection + shareCardGuidance is the combined
            // Guidance+Tender turn (establishUserAuthoredCardConnection).
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if plan.localAction.kind == .shareCardGuidance {
            if session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion,
               session.protocolVersion < ReflectionSession.currentProtocolVersion {
                let tension = plan.memoryUpdate.cardInterpretiveTension
                    ?? session.semanticMemory.cardInterpretiveTension
                guard nonempty(tension) else {
                    throw ReflectionProtocolViolation.missingRequiredMemoryField(
                        .cardInterpretiveTension
                    )
                }
            }
        }
        if session.protocolStage == .cardReflection,
           !session.cardGuidanceShared,
           plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil,
           plan.localAction.kind != .shareCardGuidance,
           !(session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion
                && plan.replyIntent == .deepenCardConnection),
           plan.replyIntent != .safetySupport {
            // When the plan itself establishes a reality mapping, the same atomic turn must
            // request the bounded local guidance capability. This prevents an acknowledgement or
            // generic reflection turn from swallowing the card condition's distinctive step.
            throw ReflectionProtocolViolation.illegalLocalAction
        }
        if plan.replyIntent == .presentCardReading {
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                // v5 has no post-connection card-meaning object. The canonical connection is
                // consumed by the first Direct Reflection response instead.
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            guard session.cardGuidanceShared,
                  effectiveCardRealityConnection(for: session) != nil else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            if session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion,
               session.protocolVersion < ReflectionSession.currentProtocolVersion,
               !nonempty(session.semanticMemory.cardInterpretiveTension) {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .cardInterpretiveTension
                )
            }
        }
        if plan.memoryUpdate.contextCueOffered == true {
            let currentCombinedGuidance =
                authorizesCombinedUserAuthoredTurn
                || (session.protocolVersion >= ReflectionSession.currentProtocolVersion
                    && session.protocolStage == .directReflection
                    && session.pendingCardGuidanceTurn
                    && plan.replyIntent == .directCandidReflection)
            let legacyReading =
                session.protocolVersion < ReflectionSession.currentProtocolVersion
                && session.protocolStage == .cardReflection
                && plan.replyIntent == .presentCardReading
            guard currentCombinedGuidance || legacyReading,
                  (session.cardGuidanceShared || authorizesCombinedUserAuthoredTurn),
                  session.contextualLoadInference?.hasDialogueCue == true,
                  session.contextualLoadInference?.relevance == .notReviewed,
                  effectiveConnection != nil else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        if plan.localAction.kind == .completeSession,
           plan.requestedStage != .complete {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        if plan.localAction.kind == .completeSession,
           plan.replyIntent != .completeConversation {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if plan.requestedStage == .complete,
           plan.localAction.kind != .completeSession {
            throw ReflectionProtocolViolation.illegalLocalAction
        }

        return plan
    }

    /// The sole exception to the ordinary card-reflection permission catalogue. A combined
    /// Guidance + first Tender reply is legal only when this exact projected operation carries
    /// the complete user-authored evidence and complete executable tuple in the same turn.
    private func isAuthorizedCombinedUserAuthoredTurn(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) -> Bool {
        guard session.protocolVersion == ReflectionSession.currentProtocolVersion,
              session.protocolStage == .cardReflection,
              session.condition.usesCard,
              session.cardDisplayState == .displayed,
              !session.cardGuidanceShared,
              !session.cardConnectionUnavailable,
              session.semanticMemory.pendingCardRealityConnection == nil,
              plan.projectedOperation == .establishUserAuthoredCardConnection,
              let connection = plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed,
              connection.source == .userAuthored,
              plan.memoryUpdate.pendingCardRealityConnection == nil,
              plan.memoryUpdate.clearPendingCardRealityConnection == true,
              plan.requestedStage == .directReflection,
              plan.replyIntent == .directCandidReflection,
              plan.localAction.kind == .shareCardGuidance,
              plan.memoryUpdate.reflectionFrame?.mode == .tender,
              plan.nextPrompt?.kind == .openQuestion,
              plan.resolvedConfirmation == nil else {
            return false
        }
        return true
    }

    private func eligibleTrackingCueIDs(in session: ReflectionSession) -> Set<String> {
        guard let inference = session.contextualLoadInference else {
            // Compatibility for sessions and protocol tests created before the aggregate cue was
            // added. Fresh sessions always compute an inference after reading context data.
            return Set(session.trackingCues.compactMap { cue in
                cue.insight == nil ? nil : cue.id
            })
        }
        guard inference.hasDialogueCue,
              inference.relevance == .notReviewed else {
            return []
        }
        let supportingIDs = Set(inference.supportingInsightIDs)
        return Set(session.trackingCues.compactMap { cue in
            guard let insightID = cue.insight?.id,
                  supportingIDs.contains(insightID) else { return nil }
            return cue.id
        })
    }

    private func validateCurrentDisclosurePlan(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        let disclosureState = EffectiveEventDisclosureState(
            memory: session.semanticMemory,
            update: plan.memoryUpdate
        )
        let effectiveMemory = disclosureState.memory
        let episode = disclosureState.episode

        if let episode {
            let behaviorHasContent = episode.hasBehaviorEvidenceContent
            if [.present, .mixed].contains(episode.behaviorEvidenceStatus),
               !behaviorHasContent {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .behaviorEvidence,
                ])
            }
            if behaviorHasContent,
               [.unresolved, .absent].contains(episode.behaviorEvidenceStatus) {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .behaviorEvidenceStatus,
                ])
            }

            let processHasContent = episode.hasEventProcessContent
            if [.present, .mixed].contains(episode.eventProcessStatus),
               !processHasContent {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .eventProcessEvidence,
                ])
            }
            if processHasContent,
               [.unresolved, .absent].contains(episode.eventProcessStatus) {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .eventProcessStatus,
                ])
            }

            let impactHasContent = episode.hasImpactContent
            if [.present, .mixed].contains(episode.impactStatus),
               !impactHasContent {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .impactEvidence,
                ])
            }
            if impactHasContent,
               [.unresolved, .absent].contains(episode.impactStatus) {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                    .impactStatus,
                ])
            }
        }

        if effectiveMemory.selfCriticismStatus == .present,
           !nonempty(effectiveMemory.selfCriticalStatement) {
            throw ReflectionProtocolViolation.missingRequiredMemoryField(
                .selfCriticalStatement
            )
        }
        if effectiveMemory.selfCriticismStatus == .absent,
           nonempty(effectiveMemory.selfCriticalStatement) {
            throw ReflectionProtocolViolation.conflictingMemoryPatch
        }

        if plan.memoryUpdate.eventDisclosureOutcome != nil {
            switch effectiveMemory.eventDisclosureOutcome {
            case .needsConcreteEpisode:
                guard episode?.concreteFacts.contains(where: nonempty) != true else {
                    throw ReflectionProtocolViolation.incompleteEpisodeStructure([
                        .behaviorEvidenceStatus,
                    ])
                }
            case .needsBehaviorOrProcess:
                guard episode?.concreteFacts.contains(where: nonempty) == true else {
                    throw ReflectionProtocolViolation.incompleteEpisodeStructure([.concreteFact])
                }
            case .readyForTenderOrCard:
                try requireDisclosureEpisodeCore(disclosureState)
            }
        }

        switch plan.replyIntent {
        case .exploreContext:
            guard let prompt = plan.nextPrompt,
                  prompt.kind == .openQuestion,
                  let purpose = prompt.disclosurePurpose,
                  let target = prompt.disclosureTarget else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
            guard target == purpose.target else {
                throw ReflectionProtocolViolation.invalidDisclosureQuestionTarget(
                    purpose.target
                )
            }
            let currentPurposes: Set<TurnDisclosureQuestionPurpose> = [
                .identifyConcreteEpisode,
                .clarifyBehavior,
                .clarifyEventProcess,
            ]
            guard currentPurposes.contains(purpose) else {
                if isEventDisclosureCoreComplete(disclosureState) {
                    throw ReflectionProtocolViolation.disclosureShouldAdvance
                }
                let expected = availableDisclosurePurposes(
                    in: disclosureState
                ).first?.target ?? .focalEvent
                throw ReflectionProtocolViolation.invalidDisclosureQuestionTarget(expected)
            }
            if isEventDisclosureCoreComplete(disclosureState) {
                // Once the projected patch completes the three canonical relations, neither a
                // repeated purpose nor a reopen label can keep disclosure alive. Classifying this
                // as the single forward-boundary violation lets recovery advertise Card Consent
                // only, instead of reconstructing an obsolete question path from stored state.
                throw ReflectionProtocolViolation.disclosureShouldAdvance
            }
            if prompt.disclosureReopenReason == nil,
               effectiveMemory.receivedDisclosureQuestionPurposes.contains(purpose) {
                throw ReflectionProtocolViolation.repeatedQuestionPurpose(purpose, target)
            }
            if prompt.disclosureReopenReason == nil,
               disclosureTargetIsComplete(target, in: disclosureState) {
                guard let expected = availableDisclosurePurposes(
                    in: disclosureState
                ).first?.target else {
                    throw ReflectionProtocolViolation.disclosureShouldAdvance
                }
                throw ReflectionProtocolViolation.invalidDisclosureQuestionTarget(expected)
            }
        case .inviteCardConsent:
            guard isEventDisclosureCoreComplete(disclosureState) else {
                throw ReflectionProtocolViolation.disclosureShouldAdvance
            }
        default:
            break
        }
    }

    private func requireDisclosureEpisodeCore(
        _ state: EffectiveEventDisclosureState
    ) throws {
        guard !isEventDisclosureCoreComplete(state) else { return }
        var missing: [TurnEpisodeRequirement] = []
        if !state.hasConcreteFocalEvent { missing.append(.concreteFact) }
        if !state.hasUserBehaviorOrOmission {
            missing.append(contentsOf: [.behaviorEvidenceStatus, .behaviorEvidence])
        }
        if !state.hasEventProcess { missing.append(.eventProcessStatus) }
        throw ReflectionProtocolViolation.incompleteEpisodeStructure(missing)
    }

    private func disclosureTargetIsComplete(
        _ target: TurnDisclosureQuestionTarget,
        in state: EffectiveEventDisclosureState
    ) -> Bool {
        switch target {
        case .focalEvent:
            return state.hasConcreteFocalEvent
        case .behavior:
            return state.hasUserBehaviorOrOmission
        case .eventProcess:
            return state.hasEventProcess
        case .contextRelationship:
            return state.memory.contextRelationship != nil
        }
    }

    private func validateInteractionContract(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        guard let nextPrompt = plan.nextPrompt else {
            throw ReflectionProtocolViolation.conflictingMemoryPatch
        }

        switch nextPrompt.kind {
        case .none:
            guard nextPrompt.purpose == nil,
                  nextPrompt.focus == nil,
                  nextPrompt.disclosurePurpose == nil,
                  nextPrompt.disclosureTarget == nil,
                  nextPrompt.disclosureReopenReason == nil,
                  nextPrompt.target == nil,
                  nextPrompt.referenceID == nil else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        case .openQuestion:
            guard nonempty(nextPrompt.purpose),
                  nonempty(nextPrompt.focus),
                  nextPrompt.target == nil,
                  nextPrompt.referenceID == nil else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        case .confirmationRequest:
            let hasLegalReference: Bool
            switch nextPrompt.target {
            case .practice:
                hasLegalReference = nonempty(nextPrompt.referenceID)
            case .cardRealityConnection:
                hasLegalReference = if let pending = plan.memoryUpdate
                    .pendingCardRealityConnection,
                    pending.isStructurallyComplete {
                    nextPrompt.referenceID == pending.id.uuidString
                } else {
                    false
                }
            case .trackingRelationship, .cardConsent, .cardMapping,
                 .finalNarrative, .none:
                hasLegalReference = nextPrompt.referenceID == nil
            }
            guard nextPrompt.purpose == nil,
                  nextPrompt.focus == nil,
                  nextPrompt.disclosurePurpose == nil,
                  nextPrompt.disclosureTarget == nil,
                  nextPrompt.disclosureReopenReason == nil,
                  nextPrompt.target != nil,
                  hasLegalReference else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure,
           plan.replyIntent == .exploreContext {
            guard nextPrompt.kind == .openQuestion,
                  nextPrompt.disclosureTarget != nil else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        }

        if let resolution = plan.resolvedConfirmation {
            let current = effectiveCurrentPrompt(for: session)
            guard current?.kind == .confirmationRequest,
                  current?.target == resolution.target else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
            if let expectedReference = current?.referenceID {
                guard resolution.referenceID == expectedReference else {
                    throw ReflectionProtocolViolation.unknownConfirmationReference
                }
            }
            guard allowedDecisions(for: resolution.target).contains(resolution.decision) else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
            if resolution.target == .trackingRelationship {
                guard let activeID = session.activeTrackingPresentationID,
                      session.trackingPresentations.contains(where: {
                          $0.id == activeID
                      }),
                      current?.referenceID == nil || current?.referenceID == activeID else {
                    throw ReflectionProtocolViolation.unknownConfirmationReference
                }
            }
        }

        if let current = effectiveCurrentPrompt(for: session),
           current.kind == .confirmationRequest,
           plan.resolvedConfirmation == nil,
           plan.replyIntent != .safetySupport {
            // A clarification may keep the same confirmation pending, but a new prompt may not
            // silently overwrite an unresolved confirmation.
            guard nextPrompt.kind == .confirmationRequest,
                  nextPrompt.target == current.target else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
        }

        try validateInteractionIntent(
            plan,
            currentPrompt: effectiveCurrentPrompt(for: session),
            session: session
        )
    }

    private func validateInteractionIntent(
        _ plan: LLMTurnResponsePlan,
        currentPrompt: TurnNextPrompt?,
        session: ReflectionSession
    ) throws {
        guard let nextPrompt = plan.nextPrompt else {
            throw ReflectionProtocolViolation.invalidNextPrompt
        }

        func requireNextConfirmation(_ target: TurnConfirmationTarget) throws {
            guard nextPrompt.kind == .confirmationRequest,
                  nextPrompt.target == target else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        }

        func requireResolution(
            _ target: TurnConfirmationTarget,
            decisions: Set<TurnConfirmationDecision>
        ) throws {
            guard let resolution = plan.resolvedConfirmation,
                  resolution.target == target,
                  decisions.contains(resolution.decision) else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
        }

        switch plan.replyIntent {
        case .presentTrackingContext:
            try requireNextConfirmation(.trackingRelationship)
            guard plan.resolvedConfirmation == nil else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }

        case .checkTrackingRelationship:
            try requireResolution(
                .trackingRelationship,
                decisions: [.related, .partlyRelated, .unrelated, .uncertain]
            )
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .inviteCardConsent:
            guard plan.resolvedConfirmation == nil else {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
            try requireNextConfirmation(.cardConsent)

        case .acknowledgeCardConsent:
            try requireResolution(.cardConsent, decisions: [.accepted])
            guard nextPrompt.kind == .none else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .acknowledgeCardDecline:
            try requireResolution(.cardConsent, decisions: [.declined, .rejected])
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .presentCardReading:
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            if currentPrompt?.target == .cardMapping {
                // Re-presenting/revising a pending reading is only a clarification path. An
                // accepted, revised, or rejected mapping belongs to directCandidReflection and
                // must not be mislabeled as another card reading.
                try requireResolution(.cardMapping, decisions: [.unclear])
            } else if plan.resolvedConfirmation != nil {
                throw ReflectionProtocolViolation.invalidConfirmationResolution
            }
            try requireNextConfirmation(.cardMapping)
            guard nonempty(plan.memoryUpdate.cardNegotiatedMeaning) else {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .cardNegotiatedMeaning
                )
            }

        case .presentFinalNarrative, .requestNarrativeConfirmation, .reviseFinalNarrative:
            try requireNextConfirmation(.finalNarrative)
            guard nonempty(plan.memoryUpdate.finalNarrative) else {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .finalNarrative
                )
            }

        case .suggestPractice, .revisePractice:
            // The complete proposal, resolution, destination stage, and confirmation prompt are
            // validated atomically by `validatePracticeTransition`.
            break

        case .completeConversation:
            guard nextPrompt.kind == .none else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
            switch session.protocolStage {
            case .narrativeConfirmation:
                guard currentPrompt?.target == .finalNarrative,
                      nonempty(session.semanticMemory.finalNarrative),
                      session.semanticMemory.practiceTransition.map({
                          $0.proposal?.status == .confirmed || $0.noActionReason != nil
                      }) == true else {
                    throw ReflectionProtocolViolation.invalidConfirmationResolution
                }
                try requireResolution(
                    .finalNarrative,
                    decisions: [.accepted, .revised]
                )
            case .optionalAction:
                // The exact pending proposal, accepted/revised/noAction state, prompt resolution,
                // destination, and completion action are one atomic contract validated by
                // `validatePracticeTransition`.
                break
            case .complete, .safetySupport:
                break
            default:
                throw ReflectionProtocolViolation.illegalStageTransition
            }

        case .directCandidReflection:
            if currentPrompt?.kind == .confirmationRequest,
               let target = currentPrompt?.target {
                let allowed: Set<TurnConfirmationDecision>
                switch target {
                case .cardMapping:
                    allowed = [.accepted, .revised, .rejected]
                default:
                    allowed = allowedDecisions(for: target)
                }
                try requireResolution(target, decisions: allowed)
                if target == .cardMapping {
                    // This transaction resolves only the negotiated reading. Swift requests the
                    // first directReflection question in a separate turn after the state commit.
                    guard plan.requestedStage == .directReflection,
                          nextPrompt.kind == .none else {
                        throw ReflectionProtocolViolation.invalidNextPrompt
                    }
                    if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
                       let decision = plan.resolvedConfirmation?.decision,
                       [.revised, .rejected].contains(decision) {
                        guard nonempty(plan.memoryUpdate.situationUnderstanding) else {
                            throw ReflectionProtocolViolation.missingRequiredMemoryField(
                                .situationUnderstanding
                            )
                        }
                        guard plan.memoryUpdate.episodeStructure != nil else {
                            throw ReflectionProtocolViolation.missingRequiredMemoryField(
                                .episodeStructure
                            )
                        }
                        if decision == .revised,
                           !nonempty(plan.memoryUpdate.cardNegotiatedMeaning) {
                            throw ReflectionProtocolViolation.missingRequiredMemoryField(
                                .cardNegotiatedMeaning
                            )
                        }
                    }
                }
            }
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .deepenCardConnection:
            guard session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion,
                  session.protocolVersion < ReflectionSession.currentProtocolVersion,
                  session.protocolStage == .cardReflection,
                  !session.cardConnectionDeepeningUsed,
                  !session.cardGuidanceShared,
                  nonempty(plan.memoryUpdate.cardRealityMapping
                    ?? session.semanticMemory.cardRealityMapping),
                  !nonempty(plan.memoryUpdate.cardInterpretiveTension
                    ?? session.semanticMemory.cardInterpretiveTension),
                  nextPrompt.kind == .openQuestion else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }

        case .inviteCardObservation:
            // The first visible card turn must give the person a usable, user-led observation
            // invitation. A transition sentence with no open floor leaves the card flow stalled.
            guard nextPrompt.kind == .openQuestion else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .developCardImage
            where session.protocolVersion >= ReflectionSession.currentProtocolVersion,
             .inviteCardConnection
            where session.protocolVersion >= ReflectionSession.currentProtocolVersion:
            // These current card operations exist to make one concrete conversational move:
            // develop the image relation, narrow a failed connection attempt, or offer the final
            // negotiable connection. A questionless acknowledgement cannot realize any of those
            // functions and previously left the card flow in place with no new information.
            if plan.replyIntent == .inviteCardConnection,
               let pending = plan.memoryUpdate.pendingCardRealityConnection {
                guard pending.isStructurallyComplete else {
                    throw ReflectionProtocolViolation.incompleteCardRealityConnection
                }
                try requireNextConfirmation(.cardRealityConnection)
            } else if plan.projectedOperation == .rejectCardConnectionCandidate {
                // Candidate rejection is a complete projected resolution transaction. It clears
                // the active candidate and intentionally leaves no follow-up prompt; requiring a
                // new open question here would contradict the projector and re-open a resolved
                // confirmation boundary.
                guard nextPrompt.kind == .none else {
                    throw ReflectionProtocolViolation.invalidNextPrompt
                }
            } else {
                guard nextPrompt.kind == .openQuestion else {
                    throw ReflectionProtocolViolation.invalidNextPrompt
                }
            }

        case .exploreContext, .developCardImage, .inviteCardConnection:
            // The LLM owns whether this ordinary semantic turn is best expressed as a direct
            // question or as a brief invitation that leaves the floor open. Swift checks only
            // that it does not create an unrelated confirmation object. This compatibility path
            // preserves the saved contract of sessions created before the current protocol.
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .authorizeCardGuidance:
            // May carry an openQuestion when guidance is combined with
            // the first Tender reflection turn (user-authored connection).
            guard nextPrompt.kind == .none
                    || nextPrompt.kind == .openQuestion else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .safetySupport:
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
        }
    }

    private func effectiveCurrentPrompt(for session: ReflectionSession) -> TurnNextPrompt? {
        guard let prompt = session.semanticMemory.nextPrompt,
              prompt.kind != .none else { return nil }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           prompt.target == .cardMapping {
            // A cardMapping prompt can exist only in a restored v42/v4-compatible record. It is
            // readable research history, not an active v5 confirmation capability.
            return nil
        }
        return prompt
    }

    private func allowedDecisions(
        for target: TurnConfirmationTarget
    ) -> Set<TurnConfirmationDecision> {
        switch target {
        case .trackingRelationship:
            return [.related, .partlyRelated, .unrelated, .uncertain]
        case .cardConsent:
            return [.accepted, .declined, .unclear]
        case .cardRealityConnection, .cardMapping, .finalNarrative:
            return [.accepted, .revised, .rejected, .unclear]
        case .practice:
            return [.accepted, .revised, .rejected, .unclear, .declined]
        }
    }

    private func nonempty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Reflection meaning remains with the Planner and semantic Critic. Swift validates only the
    /// typed capability boundary: Tender cannot smuggle in Fierce evidence, while Fierce requires
    /// a real-world basis plus complete conduct/impact/direction fields. Missing legacy metadata
    /// safely defaults to Tender instead of reopening responsibility questions.
    private func validateReflectionFrame(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        let isReflectionOperation = [.directCandidReflection, .presentFinalNarrative]
            .contains(plan.replyIntent)
            || (session.protocolStage == .directReflection
                && plan.replyIntent == .suggestPractice)
        guard isReflectionOperation else {
            return
        }
        guard let frame = plan.memoryUpdate.reflectionFrame
            ?? session.semanticMemory.reflectionFrame else {
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
               session.protocolStage == .directReflection {
                throw ReflectionProtocolViolation.invalidReflectionFrame
            }
            return
        }
        guard frame.hasNonemptyEvidence,
              frame.hasUsableDimensions,
              frame.hasReflectionDelta else {
            throw ReflectionProtocolViolation.invalidReflectionFrame
        }

        if session.protocolVersion >= ReflectionSession.actionFirstReflectionProtocolVersion,
           plan.memoryUpdate.reflectionFrame?.actionWasInferredForLegacyDecode == true {
            throw ReflectionProtocolViolation.invalidReflectionFrame
        }

        switch frame.mode {
        case .tender:
            guard frame.action.isTenderCompatible,
                  !(session.protocolVersion >= ReflectionSession.currentProtocolVersion
                    && frame.action == .connectCommonHumanity),
                  frame.fierceEvidence == nil else {
                throw ReflectionProtocolViolation.invalidReflectionFrame
            }
        case .fierce:
            guard frame.hasRealityEvidence,
                  frame.fierceEvidence?.isStructurallyComplete == true,
                  frame.dimensions.contains(where: {
                      $0 == .selfKindness || $0 == .mindfulness
                  }) else {
                throw ReflectionProtocolViolation.fierceReflectionUngrounded
            }
            guard !frame.action.isTenderCompatible || frame.action == .synthesizeUnderstanding else {
                throw ReflectionProtocolViolation.invalidReflectionFrame
            }
            if let requiredDirection = frame.action.requiredFierceDirection,
               frame.fierceEvidence?.direction != requiredDirection {
                throw ReflectionProtocolViolation.invalidReflectionFrame
            }
        }

        if session.protocolVersion >= ReflectionSession.actionFirstReflectionProtocolVersion,
           session.protocolStage == .directReflection,
           plan.replyIntent == .suggestPractice,
           frame.action != .synthesizeUnderstanding {
            throw ReflectionProtocolViolation.invalidReflectionFrame
        }
    }

    private func validateIntentTransition(
        _ plan: LLMTurnResponsePlan,
        currentStage: ReflectionProtocolStage
    ) throws {
        guard intentTransitionIsAllowed(
            from: currentStage,
            to: plan.requestedStage,
            intent: plan.replyIntent
        ) else {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
    }

    private func intentTransitionIsAllowed(
        from currentStage: ReflectionProtocolStage,
        to requestedStage: ReflectionProtocolStage,
        intent: TurnReplyIntent
    ) -> Bool {
        if requestedStage == .safetySupport {
            return intent == .safetySupport
        }

        let allowed: Set<TurnReplyIntent>
        switch (currentStage, requestedStage) {
        case (.contextualDisclosure, .contextualDisclosure):
            allowed = [.exploreContext]
        case (.contextualDisclosure, .cardConsent):
            allowed = [.inviteCardConsent]

        case (.cardConsent, .cardConsent):
            allowed = [.inviteCardConsent, .acknowledgeCardConsent]
        case (.cardConsent, .directReflection):
            allowed = [.acknowledgeCardDecline]

        case (.cardReflection, .cardReflection):
            allowed = [
                .inviteCardObservation,
                .developCardImage,
                .inviteCardConnection,
                .deepenCardConnection,
                .authorizeCardGuidance,
                .presentCardReading,
                .directCandidReflection,
            ]
        case (.cardReflection, .directReflection):
            allowed = [
                .acknowledgeCardDecline,
                .authorizeCardGuidance,
                .directCandidReflection,
            ]
        case (.directReflection, .directReflection):
            allowed = [.directCandidReflection]
        case (.directReflection, .narrativeConfirmation):
            allowed = [.presentFinalNarrative]
        case (.directReflection, .optionalAction):
            allowed = [.suggestPractice]

        case (.narrativeConfirmation, .narrativeConfirmation):
            allowed = [.requestNarrativeConfirmation, .reviseFinalNarrative]
        case (.narrativeConfirmation, .cardReflection):
            allowed = [.presentCardReading, .reviseFinalNarrative]
        case (.narrativeConfirmation, .directReflection):
            allowed = [.directCandidReflection, .reviseFinalNarrative]
        case (.narrativeConfirmation, .optionalAction):
            allowed = [.suggestPractice]
        case (.optionalAction, .optionalAction):
            allowed = [.suggestPractice, .revisePractice]
        case (.optionalAction, .narrativeConfirmation):
            allowed = [.presentFinalNarrative, .reviseFinalNarrative]
        case (.optionalAction, .complete):
            allowed = [.completeConversation]

        case (.narrativeConfirmation, .complete):
            allowed = [.completeConversation]

        case (.complete, .complete):
            allowed = [.completeConversation]
        case (.safetySupport, .safetySupport):
            allowed = [.safetySupport]
        case (.safetySupport, .complete):
            allowed = [.completeConversation]
        default:
            return false
        }
        return allowed.contains(intent)
    }

    private func allowedReplyIntents(
        from stage: ReflectionProtocolStage
    ) -> [TurnReplyIntent] {
        switch stage {
        case .contextualDisclosure:
            return [
                .exploreContext,
                .inviteCardConsent,
                .safetySupport,
            ]
        case .cardConsent:
            return [
                .inviteCardConsent,
                .acknowledgeCardConsent,
                .acknowledgeCardDecline,
                .safetySupport,
            ]
        case .cardReflection:
            return [
                .inviteCardObservation,
                .developCardImage,
                .inviteCardConnection,
                .deepenCardConnection,
                .authorizeCardGuidance,
                .presentCardReading,
                .directCandidReflection,
                .acknowledgeCardDecline,
                .safetySupport,
            ]
        case .directReflection:
            return [
                .directCandidReflection,
                .presentFinalNarrative,
                .suggestPractice,
                .safetySupport,
            ]
        case .narrativeConfirmation:
            return [
                .requestNarrativeConfirmation,
                .reviseFinalNarrative,
                .presentCardReading,
                .directCandidReflection,
                .suggestPractice,
                .completeConversation,
                .safetySupport,
            ]
        case .optionalAction:
            return [
                .suggestPractice,
                .revisePractice,
                .reviseFinalNarrative,
                .presentFinalNarrative,
                .completeConversation,
                .safetySupport,
            ]
        case .complete:
            return [.completeConversation]
        case .safetySupport:
            return [.safetySupport, .completeConversation]
        }
    }

    private func allowedStages(
        from stage: ReflectionProtocolStage,
        condition: ExperimentalCondition
    ) -> [ReflectionProtocolStage] {
        var values: [ReflectionProtocolStage]
        switch stage {
        case .contextualDisclosure:
            values = [.contextualDisclosure, .cardConsent]
        case .cardConsent:
            values = [.cardConsent, .directReflection]
        case .cardReflection:
            values = [.cardReflection, .directReflection]
        case .directReflection:
            values = [.directReflection, .narrativeConfirmation, .optionalAction]
        case .narrativeConfirmation:
            values = condition.usesCard
                ? [.cardReflection, .narrativeConfirmation, .optionalAction, .complete]
                : [.directReflection, .narrativeConfirmation, .optionalAction, .complete]
        case .optionalAction:
            values = [.optionalAction, .narrativeConfirmation, .complete]
        case .complete:
            values = [.complete]
        case .safetySupport:
            values = [.safetySupport, .complete]
        }
        if stage != .complete, !values.contains(.safetySupport) {
            values.append(.safetySupport)
        }
        if !values.contains(stage) { values.append(stage) }
        return values
    }
}

// MARK: - Effective Card Semantic State

/// Identifies the contract that is authoritative for Observation and Development evidence.
/// Selection is based on persisted protocol identity, never inferred from missing evidence.
enum CardSemanticEvidenceSource: Equatable, Sendable {
    case currentTyped
    case legacyProjected
}

/// The only compatibility adapter allowed to infer Card evidence from pre-v5 state.
/// Its projection is read-only and is never written back as user-authored typed evidence.
private enum LegacyCardSemanticEvidenceProjector {
    static func project(session: ReflectionSession) -> (
        observationEvidenceExists: Bool,
        developmentEvidenceExists: Bool
    ) {
        let typedObservation = session.semanticMemory.cardObservationEvidence?.hasContent == true
        let typedDevelopment = session.semanticMemory.cardDevelopmentEvidence?.hasContent == true

        // Once a legacy session receives typed evidence in a new turn, that contract becomes
        // authoritative for both phases; old counters cannot fill the other typed phase.
        if typedObservation || typedDevelopment {
            return (typedObservation, typedDevelopment)
        }

        return (
            session.cardDisplayState == .displayed
                && session.card != nil
                && session.protocolStage == .cardReflection,
            session.cardImageDevelopmentTurnCount >= 1
        )
    }
}

/// Central version boundary for Card evidence. Current sessions read only typed memory, while
/// explicitly legacy sessions go through the compatibility projector above.
private enum CardSemanticEvidenceResolver {
    static func resolve(session: ReflectionSession) -> (
        source: CardSemanticEvidenceSource,
        observationEvidenceExists: Bool,
        developmentEvidenceExists: Bool
    ) {
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
            return (
                .currentTyped,
                session.semanticMemory.cardObservationEvidence?.hasContent == true,
                // Presence is a protocol fact. Whether this material is rich enough to leave the
                // image is a Planner judgment, not a second Swift sufficiency test.
                session.semanticMemory.cardDevelopmentEvidence?.hasContent == true
            )
        }

        let projected = LegacyCardSemanticEvidenceProjector.project(session: session)
        return (
            .legacyProjected,
            projected.observationEvidenceExists,
            projected.developmentEvidenceExists
        )
    }
}

/// Single typed projection of the Card stage, derived from committed persisted state only.
/// All semantic mapping and eligibility decisions read this; no raw counter or flag is used
/// independently outside this constructor.
struct EffectiveCardSemanticState: Equatable, Sendable {
    /// The canonical substate, computed once from committed typed evidence.
    let substate: CardSemanticSubstate

    // ── Status flags (read-only, derived) ──────────────────────────────

    /// Image has been displayed and the person has seen it.
    let observationEvidenceExists: Bool
    /// The Planner has committed user-authored image-development evidence. Its reflective
    /// sufficiency is deliberately not re-judged by Swift.
    let developmentEvidenceExists: Bool
    /// A connection attempt or scaffold question has been committed — the system
    /// has formally entered Reality Connection exploration.
    let explorationStarted: Bool
    /// The Planner returned `noConnectionFound` or a connection attempt was made,
    /// confirming that the person experienced connection difficulty.
    let connectionDifficultyOccurred: Bool
    /// A structurally complete pending candidate is awaiting resolution.
    let pendingCandidateExists: Bool
    /// A canonical card-reality connection has been confirmed (user-authored,
    /// accepted, or revised).
    let canonicalConnectionExists: Bool
    /// Guidance (shareCardGuidance) has been authorized in v5, or cardMapping
    /// has been confirmed in v4.
    let guidanceAuthorized: Bool
    /// The session uses the current protocol (v5+).
    let isCurrentProtocol: Bool

    // ── Candidate bridge eligibility ──────────────────────────────────

    /// The typed conditions for offering a candidate bridge are all satisfied
    /// RIGHT NOW. This is computed from current state, not from a single flag.
    let candidateBridgeEligible: Bool
    /// A scaffold (bridge-enabling development question) was already used in
    /// this session. Once used it prevents returning to development but does
    /// NOT by itself mean a bridge is currently eligible.
    let bridgeScaffoldUsed: Bool
    /// The Card connection is typed unavailable — person cannot or does not
    /// want to form an image-to-reality connection.
    let connectionUnavailable: Bool
    /// A candidate bridge was offered and resolved (accepted, revised, or rejected)
    /// in this session. Once resolved, the bridge cannot be offered again.
    let candidateBridgeOfferedOrResolved: Bool
    /// `true` only when an explicit pre-v5 session is using the legacy projection contract.
    let isLegacyProjection: Bool
    /// Explicit evidence contract selected from the persisted protocol identity.
    let evidenceSource: CardSemanticEvidenceSource

    // MARK: - Construction

    /// All inputs come from committed persisted session state.
    /// No Planner output, no `nextPrompt`, and no uncommitted answer are consulted.
    init(session: ReflectionSession) {
        let protocolStage = session.protocolStage
        let protocolVersion = session.protocolVersion
        let memory = session.semanticMemory

        isCurrentProtocol = protocolVersion >= ReflectionSession.currentProtocolVersion

        // ── Canonical typed evidence (priority order) ──────────────────

        canonicalConnectionExists =
            TurnCardRealityConnectionResolver.effective(
                memory: memory
            ) != nil

        // v5: guidance authorized by shareCardGuidance commit
        // v4: cardMappingConfirmed after negotiated reading
        guidanceAuthorized = canonicalConnectionExists && (
            session.cardGuidanceShared
            || session.pendingCardGuidanceTurn
            || (!isCurrentProtocol && session.cardMappingConfirmed)
        )

        let prompt = memory.nextPrompt
        let isAwaitingResolution =
            memory.pendingCardRealityConnection?.isStructurallyComplete == true
            && prompt?.kind == .confirmationRequest
            && prompt?.target == .cardRealityConnection

        pendingCandidateExists = memory.pendingCardRealityConnection?
            .isStructurallyComplete == true
            && isAwaitingResolution

        // ── Observation evidence ──────────────────────────────────────

        // The centralized resolver selects either the v5 typed contract or the legacy adapter.
        let evidence = CardSemanticEvidenceResolver.resolve(session: session)
        evidenceSource = evidence.source
        observationEvidenceExists = evidence.observationEvidenceExists

        // ── Development evidence ──────────────────────────────────────

        // Both phases come from the same selected source; they are never OR-combined here.
        developmentEvidenceExists = evidence.developmentEvidenceExists
        isLegacyProjection = evidence.source == .legacyProjected

        // ── Exploration / difficulty ──────────────────────────────────

        let rawExplorationSignal =
            session.cardConnectionAttemptCount > 0
            || session.cardConnectionScaffoldUsed
        // A v5 lifecycle flag cannot manufacture the user's typed Card evidence. Development
        // richness is not a lifecycle prerequisite; the Planner owns that semantic judgment.
        explorationStarted = isCurrentProtocol
            ? (observationEvidenceExists && rawExplorationSignal)
            : rawExplorationSignal

        connectionDifficultyOccurred = isCurrentProtocol
            ? (observationEvidenceExists && rawExplorationSignal)
            : rawExplorationSignal

        // ── Bridge scaffold (only input; not a derived decision) ───────

        bridgeScaffoldUsed = session.cardConnectionScaffoldUsed
        connectionUnavailable = session.cardConnectionUnavailable

        // ── Candidate bridge lifecycle ────────────────────────────────

        // A candidate was offered and resolved if either:
        // a) A resolution timestamp was recorded, or
        // b) A pending candidate currently exists (offered but not yet resolved)
        candidateBridgeOfferedOrResolved =
            memory.candidateBridgeResolvedAt != nil
            || pendingCandidateExists

        // ── Candidate bridge eligibility ───────────────────────────────

        // All conditions must hold simultaneously:
        // 1. Current protocol (no legacy path).
        // 2. Exploration started, no pending candidate, no canonical connection,
        //    guidance not yet authorized.
        // 3. Connection difficulty formally recorded.
        // 4. Scaffold used (bridge-enabling question was asked).
        // 5. Candidate bridge has NOT been offered/resolved yet this session.
        candidateBridgeEligible =
            isCurrentProtocol
            && observationEvidenceExists
            && explorationStarted
            && !pendingCandidateExists
            && !canonicalConnectionExists
            && !guidanceAuthorized
            && connectionDifficultyOccurred
            && bridgeScaffoldUsed
            && !candidateBridgeOfferedOrResolved

        // ── Substate derivation (strict priority) ──────────────────────

        guard protocolStage == .cardReflection else {
            substate = .none
            return
        }

        if guidanceAuthorized {
            substate = .guidance
        } else if pendingCandidateExists {
            substate = .awaitingCandidateResolution
        } else if explorationStarted {
            substate = .openExploration
        } else if developmentEvidenceExists {
            substate = .development
        } else if observationEvidenceExists {
            substate = .observation
        } else {
            substate = .none
        }
    }
}

/// Non-persisted recovery input describing the gap between raw user input and
/// committed semantic state. This is used only when a normal turn fails and
/// recovery must re-extract a semantic patch from the same latest answer.
struct PendingUncommittedCardAnswerContext: Equatable, Sendable {
    /// The latest persisted semantic state (unchanged by the failed plan).
    let lastCommittedState: EffectiveCardSemanticState
    /// `true` when a raw user message exists in the transcript that has not
    /// yet been consumed by a successful semantic commit.
    let hasUncommittedLatestAnswer: Bool
    /// The purpose of the card question that the uncommitted answer is answering,
    /// derived from the last committed nextPrompt.
    let pendingCardPurpose: String?

    init(session: ReflectionSession, lastCommittedState: EffectiveCardSemanticState) {
        self.lastCommittedState = lastCommittedState

        // Derive uncommitted-answer status from message identity, not from
        // nextPrompt.kind. An answer is uncommitted when the latest user message
        // in the transcript has no matching assistant reply with a committed
        // replyToMessageID.
        let messages = session.messages
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            hasUncommittedLatestAnswer = false
            pendingCardPurpose = nil
            return
        }
        let lastUserMessage = messages[lastUserIndex]
        let hasMatchingAssistantReply = messages.contains {
            $0.role == .assistant && $0.replyToMessageID == lastUserMessage.id
        }

        hasUncommittedLatestAnswer = !hasMatchingAssistantReply

        // Purpose derived from the committed nextPrompt, not from the raw message.
        let currentPrompt = session.semanticMemory.nextPrompt
        pendingCardPurpose = {
            guard let prompt = currentPrompt,
                  prompt.kind != .none else { return nil }
            return prompt.purpose ?? prompt.focus
        }()
    }
}

// MARK: - Card semantic substate (facade over EffectiveCardSemanticState)

extension ReflectionProtocolController {

    /// Deterministically computes the current card substate from the committed
    /// typed projection. This is the single entry point for all substate queries.
    func cardSemanticSubstate(for session: ReflectionSession) -> CardSemanticSubstate {
        EffectiveCardSemanticState(session: session).substate
    }

    /// Returns the full effective Card state for semantic mapping and eligibility. When a
    /// candidate semantic patch is supplied, project it onto a value-copy of the last committed
    /// session. This mirrors `EffectiveEventDisclosureState(memory:update:)`: the latest raw
    /// answer can establish typed Observation/Development evidence for validation, while the
    /// persisted session remains unchanged until the atomic turn transaction succeeds.
    func effectiveCardState(
        for session: ReflectionSession,
        applying update: TurnSemanticMemoryUpdate? = nil
    ) -> EffectiveCardSemanticState {
        guard let update else { return EffectiveCardSemanticState(session: session) }
        var candidate = session
        candidate.semanticMemory.apply(update)
        return EffectiveCardSemanticState(session: candidate)
    }

    // MARK: - Semantic operation mapping

    /// Current-protocol entry point. The operation is read once from the explicit Planner field;
    /// payload may support or reject that choice but can never replace it.
    func semanticDecisionFromExplicitOperation(
        _ plan: LLMTurnResponsePlan,
        session: ReflectionSession
    ) throws -> PlannerSemanticDecision {
        guard session.protocolVersion >= ReflectionSession.currentProtocolVersion else {
            throw SemanticMappingViolation.semanticOperationNotAllowed(
                plan.semanticOperation ?? .provideSafetySupport,
                session.protocolStage
            )
        }
        guard let operation = plan.semanticOperation else {
            throw SemanticMappingViolation.missingSemanticOperation
        }
        return try currentV5SemanticDecision(
            operation: operation,
            memoryUpdate: plan.memoryUpdate,
            cardConnectionTurnOutcome: plan.cardConnectionTurnOutcome,
            responseFocus: plan.replyGuidance,
            session: session
        )
    }

    /// The single semantic entry used by the rebuilt current-v5 core. Unlike the compatibility
    /// overload above, this API cannot receive Planner-authored stage, prompt, action, intent, or
    /// confirmation fields because those values do not exist in its input type.
    func currentV5SemanticDecision(
        operation: PlannerSemanticOperation,
        memoryUpdate proposedMemoryUpdate: TurnSemanticMemoryUpdate,
        cardConnectionTurnOutcome: CardConnectionTurnOutcome?,
        responseFocus: String,
        session: ReflectionSession
    ) throws -> PlannerSemanticDecision {
        guard session.protocolVersion >= ReflectionSession.currentProtocolVersion else {
            throw SemanticMappingViolation.semanticOperationNotAllowed(
                operation,
                session.protocolStage
            )
        }
        executionAudit?.record(.semanticMapper)

        var memoryUpdate = try validateSemanticPayload(
            for: operation,
            memoryUpdate: proposedMemoryUpdate,
            cardConnectionTurnOutcome: cardConnectionTurnOutcome,
            responseFocus: responseFocus,
            session: session
        )
        if operation == .provideSafetySupport {
            // Safety is a protocol transition, not permission to carry an unrelated failed
            // reflection patch into the safety transaction.
            memoryUpdate = TurnSemanticMemoryUpdate()
        }
        if operation == .establishUserAuthoredCardConnection,
           let connection = cardConnectionTurnOutcome?.connection?.normalizedConfirmed {
            memoryUpdate.cardRealityConnection = connection
            memoryUpdate.clearPendingCardRealityConnection = true
            memoryUpdate.cardConnectionOutcome = .connectionConfirmed
        }
        if operation == .reviseCardConnectionCandidate,
           let connection = cardConnectionTurnOutcome?.connection?.normalizedConfirmed {
            memoryUpdate.cardRealityConnection = connection
        }
        if [
            PlannerSemanticOperation.continueOpenCardConnection,
            .offerCardConnectionScaffold,
        ].contains(operation),
           cardConnectionTurnOutcome?.kind == .connectionStillUnclear {
            memoryUpdate.cardConnectionOutcome = .noConnectionFound
        }

        return makeSemanticDecision(
            operation: operation,
            memoryUpdate: memoryUpdate,
            responseFocus: responseFocus
        )
    }

    /// Central current-protocol Operation–Payload contract. It is exhaustive and side-effect free:
    /// no structural field is projected here and no legacy field may select another operation.
    func validateSemanticPayload(
        for operation: PlannerSemanticOperation,
        plan: LLMTurnResponsePlan,
        session: ReflectionSession
    ) throws -> TurnSemanticMemoryUpdate {
        try validateSemanticPayload(
            for: operation,
            memoryUpdate: plan.memoryUpdate,
            cardConnectionTurnOutcome: plan.cardConnectionTurnOutcome,
            responseFocus: plan.replyGuidance,
            session: session
        )
    }

    private func validateSemanticPayload(
        for operation: PlannerSemanticOperation,
        memoryUpdate update: TurnSemanticMemoryUpdate,
        cardConnectionTurnOutcome: CardConnectionTurnOutcome?,
        responseFocus: String,
        session: ReflectionSession
    ) throws -> TurnSemanticMemoryUpdate {
        let event = EffectiveEventDisclosureState(
            memory: session.semanticMemory,
            update: update
        )
        let card = effectiveCardState(for: session, applying: update)

        func mismatch(_ detail: String) throws -> Never {
            throw SemanticMappingViolation.semanticOperationPayloadMismatch(operation, detail)
        }
        func requireStage(_ stages: ReflectionProtocolStage...) throws {
            guard stages.contains(session.protocolStage) else {
                throw SemanticMappingViolation.semanticOperationNotAllowed(
                    operation, session.protocolStage
                )
            }
        }
        func requireNoConnectionOutcome() throws {
            guard cardConnectionTurnOutcome == nil else {
                try mismatch("cardConnectionTurnOutcome conflicts with explicit operation")
            }
        }
        func requireReflectionFrame(
            mode: TurnReflectionMode,
            synthesis: Bool
        ) throws -> TurnReflectionFrame {
            guard let frame = update.reflectionFrame,
                  frame.mode == mode,
                  frame.hasNonemptyEvidence,
                  frame.hasUsableDimensions,
                  frame.hasReflectionDelta,
                  frame.actionWasInferredForLegacyDecode == false,
                  (frame.action == .synthesizeUnderstanding) == synthesis else {
                try mismatch("complete matching reflectionFrame required")
            }
            switch mode {
            case .tender:
                guard frame.action.isTenderCompatible,
                      frame.fierceEvidence == nil else {
                    try mismatch("Tender operation conflicts with Fierce frame content")
                }
            case .fierce:
                guard session.reflectionReadiness == .reflectionOpen,
                      frame.hasRealityEvidence,
                      frame.fierceEvidence?.isStructurallyComplete == true,
                      frame.dimensions.contains(where: {
                          $0 == .selfKindness || $0 == .mindfulness
                      }) else {
                    try mismatch("Fierce operation requires readiness and user-grounded evidence")
                }
                if !synthesis, frame.action.isTenderCompatible {
                    try mismatch("Fierce operation requires a Fierce-compatible action")
                }
                if let direction = frame.action.requiredFierceDirection,
                   frame.fierceEvidence?.direction != direction {
                    try mismatch("Fierce direction conflicts with reflection action")
                }
            }
            return frame
        }

        // Retired scalar connection fields and internally contradictory episode patches are
        // Planner payload defects. Reject them here, before Effective State projection, so current
        // recovery can rebuild a clean semantic patch without ever entering legacy validation.
        if update.legacyConnectionFieldsPresentInPayload {
            try mismatch("legacy Card connection fields are not valid current semantic evidence")
        }
        if update.episodeStructure != nil,
           let episode = event.episode {
            let behaviorHasContent = episode.behaviorEvidence.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if [.present, .mixed].contains(episode.behaviorEvidenceStatus),
               !behaviorHasContent {
                try mismatch("behaviorEvidence status requires grounded content")
            }
            if behaviorHasContent,
               [.unresolved, .absent].contains(episode.behaviorEvidenceStatus) {
                try mismatch("behaviorEvidence content requires a compatible status")
            }
            let processHasContent = episode.hasEventProcessContent
            if [.present, .mixed].contains(episode.eventProcessStatus),
               !processHasContent {
                try mismatch("eventProcess status requires grounded content")
            }
            if processHasContent,
               [.unresolved, .absent].contains(episode.eventProcessStatus) {
                try mismatch("eventProcess content requires a compatible status")
            }
        }

        switch operation {
        case .clarifyEvent:
            try requireStage(.contextualDisclosure)
            guard !isEventDisclosureCoreComplete(event) else {
                try mismatch("Event Disclosure core is already complete")
            }
            guard !responseFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try mismatch("clarifyEvent requires a grounded response focus")
            }
            try requireNoConnectionOutcome()

        case .advanceToCardConsent:
            try requireStage(.contextualDisclosure)
            guard isEventDisclosureCoreComplete(event) else {
                try mismatch("candidate Event snapshot is incomplete")
            }
            try requireNoConnectionOutcome()

        case .inviteCardConsent,
             .acknowledgeCardConsent,
             .declineCardConsent:
            try requireStage(.cardConsent)
            try requireNoConnectionOutcome()

        case .continueCardObservation:
            try requireStage(.cardReflection)
            guard card.substate == .observation else {
                try mismatch("Card Observation substate required")
            }
            guard update.cardDevelopmentEvidence == nil,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("Observation cannot create Development or candidate evidence")
            }
            try requireNoConnectionOutcome()

        case .continueCardDevelopment:
            try requireStage(.cardReflection)
            guard card.substate == .observation else {
                try mismatch("Card Observation substate required before Development is established")
            }
            guard update.pendingCardRealityConnection == nil else {
                try mismatch("Development cannot create a pending candidate")
            }
            try requireNoConnectionOutcome()

        case .inviteRealityConnection:
            try requireStage(.cardReflection)
            guard card.substate == .development,
                  card.observationEvidenceExists,
                  card.developmentEvidenceExists else {
                try mismatch("complete Observation and Development evidence required")
            }
            guard update.pendingCardRealityConnection == nil else {
                try mismatch("Reality invitation cannot create a pending candidate")
            }
            try requireNoConnectionOutcome()

        case .continueOpenCardConnection:
            try requireStage(.cardReflection)
            guard card.substate == .openExploration,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("open exploration without a candidate is required")
            }
            if let outcome = cardConnectionTurnOutcome,
               outcome.kind != .connectionStillUnclear {
                try mismatch("only connectionStillUnclear may accompany open exploration")
            }

        case .offerCardConnectionScaffold:
            try requireStage(.cardReflection)
            let reportsCurrentDifficulty =
                cardConnectionTurnOutcome?.kind == .connectionStillUnclear
            let candidateOpenExploration = card.substate == .openExploration
                || (card.substate == .development && reportsCurrentDifficulty)
            guard candidateOpenExploration,
                  (card.connectionDifficultyOccurred || reportsCurrentDifficulty),
                  !card.bridgeScaffoldUsed,
                  update.cardDevelopmentEvidence == nil,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("eligible one-time scaffold state required")
            }
            if let outcome = cardConnectionTurnOutcome,
               outcome.kind != .connectionStillUnclear {
                try mismatch("scaffold may only accompany connectionStillUnclear")
            }

        case .offerCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard card.substate == .openExploration,
                  card.candidateBridgeEligible,
                  !card.canonicalConnectionExists,
                  update.pendingCardRealityConnection?.isStructurallyComplete == true else {
                try mismatch("eligible complete pending candidate required")
            }
            if let outcome = cardConnectionTurnOutcome,
               outcome.kind != .connectionStillUnclear {
                try mismatch("candidate offer conflicts with connection outcome")
            }

        case .establishUserAuthoredCardConnection:
            try requireStage(.cardReflection)
            guard let outcome = cardConnectionTurnOutcome,
                  outcome.kind == .userAuthoredConnection,
                  outcome.connection?.normalizedConfirmed?.source == .userAuthored,
                  update.pendingCardRealityConnection == nil,
                  !card.pendingCandidateExists else {
                try mismatch("complete direct user-authored connection required")
            }
            _ = try requireReflectionFrame(mode: .tender, synthesis: false)

        case .acceptCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard card.substate == .awaitingCandidateResolution,
                  cardConnectionTurnOutcome?.kind == .candidateAccepted,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("candidateAccepted for the active candidate required")
            }

        case .reviseCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard card.substate == .awaitingCandidateResolution,
                  cardConnectionTurnOutcome?.kind == .candidateRevised,
                  cardConnectionTurnOutcome?.connection?.normalizedConfirmed?.source == .userRevised,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("complete user revision of the active candidate required")
            }

        case .rejectCardConnectionCandidate:
            try requireStage(.cardReflection)
            guard card.substate == .awaitingCandidateResolution,
                  cardConnectionTurnOutcome?.kind == .candidateRejected,
                  update.pendingCardRealityConnection == nil else {
                try mismatch("candidateRejected for the active candidate required")
            }

        case .bypassCardConnectionToDirectReflection:
            try requireStage(.cardReflection)
            guard card.connectionUnavailable else {
                try mismatch("typed unavailable/skip state required")
            }
            try requireNoConnectionOutcome()

        case .authorizeCardGuidance:
            try requireStage(.cardReflection)
            guard card.canonicalConnectionExists else {
                try mismatch("committed canonical connection required")
            }
            try requireNoConnectionOutcome()

        case .presentLegacyCardReading:
            throw SemanticMappingViolation.semanticOperationNotAllowed(
                operation, session.protocolStage
            )

        case .continueExploratoryReflection:
            // Current v5 executes this operation only through CurrentV5SwiftTurnGate and the
            // canonical projector. The legacy semantic mapper must never become a second route.
            throw SemanticMappingViolation.semanticOperationNotAllowed(
                operation, session.protocolStage
            )

        case .continueTenderReflection:
            try requireStage(.directReflection)
            _ = try requireReflectionFrame(mode: .tender, synthesis: false)
            try requireNoConnectionOutcome()

        case .continueTenderGroundedFierceReflection:
            try requireStage(.directReflection)
            _ = try requireReflectionFrame(mode: .fierce, synthesis: false)
            try requireNoConnectionOutcome()

        case .synthesizeDirectReflection:
            try requireStage(.directReflection)
            guard let frame = update.reflectionFrame else {
                try mismatch("synthesis reflectionFrame required")
            }
            _ = try requireReflectionFrame(mode: frame.mode, synthesis: true)
            try requireNoConnectionOutcome()

        case .proposePractice:
            try requireStage(.directReflection, .narrativeConfirmation, .optionalAction)
            guard let transition = update.practiceTransition,
                  let proposal = transition.proposal,
                  transition.noActionReason == nil,
                  nonempty(proposal.id),
                  nonempty(proposal.content),
                  nonempty(proposal.basis) else {
                try mismatch("complete practice proposal transition required")
            }
            if session.protocolStage == .narrativeConfirmation {
                guard session.semanticMemory.nextPrompt?.target == .finalNarrative,
                      let narrativeReferenceID = session.semanticMemory.nextPrompt?.referenceID,
                      transition.narrativeReferenceID == narrativeReferenceID else {
                    try mismatch("practice proposal must resolve the active final narrative")
                }
            }
            try requireNoConnectionOutcome()

        case .resolvePractice:
            try requireStage(.optionalAction)
            guard session.semanticMemory.practiceTransition?.proposal != nil,
                  update.practiceTransition != nil else {
                try mismatch("active proposal and complete resolution transition required")
            }
            try requireNoConnectionOutcome()

        case .confirmNarrative:
            try requireStage(.directReflection, .narrativeConfirmation, .optionalAction)
            guard nonempty(update.finalNarrative ?? session.semanticMemory.finalNarrative) else {
                try mismatch("final narrative content required")
            }
            try requireNoConnectionOutcome()

        case .reviseNarrative:
            try requireStage(.narrativeConfirmation)
            guard nonempty(update.finalNarrative) else {
                try mismatch("revised final narrative required")
            }
            try requireNoConnectionOutcome()

        case .completeConversation:
            try requireStage(.narrativeConfirmation, .optionalAction, .complete, .safetySupport)
            try requireNoConnectionOutcome()

        case .provideSafetySupport:
            try requireNoConnectionOutcome()
        }

        return update
    }

    private func makeSemanticDecision(
        operation: PlannerSemanticOperation,
        memoryUpdate: TurnSemanticMemoryUpdate,
        responseFocus: String
    ) -> PlannerSemanticDecision {
        let normalizedFocus = responseFocus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let clarificationFocus: String?
        switch operation {
        case .clarifyEvent,
             .inviteCardConsent,
             .continueCardObservation,
             .continueCardDevelopment,
             .continueOpenCardConnection,
             .inviteRealityConnection,
             .offerCardConnectionScaffold,
             .offerCardConnectionCandidate,
             .continueExploratoryReflection,
             .continueTenderReflection,
             .continueTenderGroundedFierceReflection:
            clarificationFocus = normalizedFocus
        case .advanceToCardConsent,
             .acknowledgeCardConsent,
             .declineCardConsent,
             .establishUserAuthoredCardConnection,
             .acceptCardConnectionCandidate,
             .reviseCardConnectionCandidate,
             .rejectCardConnectionCandidate,
             .bypassCardConnectionToDirectReflection,
             .authorizeCardGuidance,
             .presentLegacyCardReading,
             .synthesizeDirectReflection,
             .proposePractice,
             .resolvePractice,
             .confirmNarrative,
             .reviseNarrative,
             .completeConversation,
             .provideSafetySupport:
            clarificationFocus = nil
        }
        return PlannerSemanticDecision(
            operation: operation,
            memoryUpdate: memoryUpdate,
            responseFocus: normalizedFocus,
            clarificationFocus: clarificationFocus
        )
    }

    /// Legacy/recovery adapter. Current v5 normal execution must never call this function.
    ///
    /// Classifies a Planner turn into exactly one semantic operation from the current typed state,
    /// the raw `replyIntent`, and the plan's memory update plus connection outcome.
    ///
    /// This function does **not** read `nextPrompt`, `requestedStage`, or `eventDisclosureOutcome`
    /// from the plan as truth sources. It operates on the pre-normalization Planner output so it
    /// can report classification defects that normalization would otherwise mask.
    ///
    /// - Parameters:
    ///   - plan: The raw Planner output (before `normalizeEquivalentProtocolLabels`).
    ///   - session: The current committed session state.
    /// - Returns: A `PlannerSemanticDecision` with exactly one operation.
    /// - Throws: `SemanticMappingViolation` when the combination cannot be uniquely classified.
    func legacySemanticDecisionFromProtocolFields(
        from plan: LLMTurnResponsePlan,
        session: ReflectionSession,
        allowCurrentProtocolFixture: Bool = false
    ) throws -> PlannerSemanticDecision {
        guard session.protocolVersion < ReflectionSession.currentProtocolVersion
                || allowCurrentProtocolFixture else {
            throw SemanticMappingViolation.legacyOperationInferenceUsedInCurrentProtocol
        }
        executionAudit?.record(.legacySemanticMapper)
        let memoryUpdate = plan.memoryUpdate
        let responseFocus = plan.replyGuidance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let effectiveCard = effectiveCardState(for: session)

        let operation = try classifyOperation(
            plan: plan,
            session: session,
            effectiveCard: effectiveCard
        )

        let clarificationFocus: String?
        switch operation {
        case .clarifyEvent,
             .inviteCardConsent,
             .continueCardObservation,
             .continueCardDevelopment,
             .continueOpenCardConnection,
             .inviteRealityConnection,
             .offerCardConnectionScaffold,
             .offerCardConnectionCandidate,
             .continueExploratoryReflection,
             .continueTenderReflection,
             .continueTenderGroundedFierceReflection:
            clarificationFocus = responseFocus
        case .advanceToCardConsent,
             .acknowledgeCardConsent,
             .declineCardConsent,
             .establishUserAuthoredCardConnection,
             .acceptCardConnectionCandidate,
             .reviseCardConnectionCandidate,
             .rejectCardConnectionCandidate,
             .bypassCardConnectionToDirectReflection,
             .authorizeCardGuidance,
             .presentLegacyCardReading,
             .synthesizeDirectReflection,
             .proposePractice,
             .resolvePractice,
             .confirmNarrative,
             .reviseNarrative,
             .completeConversation,
             .provideSafetySupport:
            clarificationFocus = nil
        }

        // Transfer user-authored connection from outcome to memory update
        // so the projector can validate canonicalConnectionExists.
        var resolvedMemoryUpdate = memoryUpdate
        if operation == .establishUserAuthoredCardConnection,
           memoryUpdate.cardRealityConnection == nil,
           let connection = plan.cardConnectionTurnOutcome?.connection {
            resolvedMemoryUpdate.cardRealityConnection = connection
            resolvedMemoryUpdate.clearPendingCardRealityConnection = true
            resolvedMemoryUpdate.cardConnectionOutcome = .connectionConfirmed
        }
        if plan.cardConnectionTurnOutcome?.kind == .connectionStillUnclear,
           operation != .offerCardConnectionCandidate {
            resolvedMemoryUpdate.cardConnectionOutcome = .noConnectionFound
        }

        return PlannerSemanticDecision(
            operation: operation,
            memoryUpdate: resolvedMemoryUpdate,
            responseFocus: responseFocus,
            clarificationFocus: clarificationFocus
        )
    }

    /// Read-only migration diagnostic. Its result never participates in validation, projection,
    /// writing, or transaction commit and it does not count as legacy execution.
    func legacyInferredOperationForDiagnostics(
        from plan: LLMTurnResponsePlan,
        session: ReflectionSession
    ) -> PlannerSemanticOperation? {
        try? classifyOperation(
            plan: plan,
            session: session,
            effectiveCard: effectiveCardState(for: session)
        )
    }

    /// The core classification switch. Every arm is explicit; there is no `default` branch.
    /// All Card-state reads go through `effectiveCard` — no raw session counter or flag is
    /// consulted independently.
    private func classifyOperation(
        plan: LLMTurnResponsePlan,
        session: ReflectionSession,
        effectiveCard: EffectiveCardSemanticState
    ) throws -> PlannerSemanticOperation {
        let substate = effectiveCard.substate

        switch (session.protocolStage, plan.replyIntent) {

        // ── Contextual Disclosure ──────────────────────────────────────────

        case (.contextualDisclosure, .exploreContext):
            return .clarifyEvent

        case (.contextualDisclosure, .inviteCardConsent):
            return .advanceToCardConsent

        // ── Card Consent ───────────────────────────────────────────────────

        case (.cardConsent, .inviteCardConsent):
            return .inviteCardConsent

        case (.cardConsent, .acknowledgeCardConsent):
            return .acknowledgeCardConsent

        case (.cardConsent, .acknowledgeCardDecline):
            return .declineCardConsent

        // ── Card Reflection (substate-gated) ───────────────────────────────

        // Card-connection outcomes with a typed outcome are definitive
        // and match before any specific replyIntent. This prevents a Planner
        // replyIntent like authorizeCardGuidance from shadowing a candidate
        // resolution or user-authored connection that the Planner actually performed.
        case (.cardReflection, _)
            where plan.cardConnectionTurnOutcome != nil
                && substate == .awaitingCandidateResolution:
            return try classifyCardCandidateResolution(from: plan)

        // User-authored connection: the person spontaneously formed a complete
        // image-to-reality mapping. This bypasses the candidate path entirely.
        case (.cardReflection, _)
            where plan.cardConnectionTurnOutcome?.kind == .userAuthoredConnection:
            return .establishUserAuthoredCardConnection

        case (.cardReflection, .inviteCardObservation):
            guard substate == .observation else {
                throw SemanticMappingViolation.cardSubstateMismatch(
                    .inviteCardObservation, substate
                )
            }
            return .continueCardObservation

        case (.cardReflection, .developCardImage):
            switch substate {
            case .observation, .development:
                return .continueCardDevelopment
            case .openExploration:
                // In open exploration, developCardImage is a scaffold question,
                // not image development. Only legal when scaffold not yet used.
                guard effectiveCard.connectionDifficultyOccurred,
                      !effectiveCard.bridgeScaffoldUsed,
                      !effectiveCard.candidateBridgeOfferedOrResolved,
                      !effectiveCard.pendingCandidateExists,
                      !effectiveCard.canonicalConnectionExists else {
                    throw SemanticMappingViolation.cardSubstateMismatch(
                        .developCardImage, substate
                    )
                }
                return .offerCardConnectionScaffold
            case .awaitingCandidateResolution, .guidance, .none:
                throw SemanticMappingViolation.cardSubstateMismatch(
                    .developCardImage, substate
                )
            }

        case (.cardReflection, .inviteCardConnection):
            switch substate {
            case .development:
                // First invitation: from development into connection exploration.
                // A candidate bridge cannot be offered from the development substate
                // even if the Planner happens to supply a complete pending candidate.
                guard !hasStructurallyCompletePendingCandidate(in: plan.memoryUpdate) else {
                    throw SemanticMappingViolation.cardSubstateMismatch(
                        .inviteCardConnection, substate
                    )
                }
                return .inviteRealityConnection
            case .openExploration:
                if hasStructurallyCompletePendingCandidate(in: plan.memoryUpdate) {
                    // Candidate bridges are only legal when the typed eligibility
                    // condition (scaffold-used or equivalent) is satisfied.
                    guard candidateBridgeEligible(for: session, effectiveCard: effectiveCard) else {
                        throw SemanticMappingViolation.cardSubstateMismatch(
                            .inviteCardConnection, substate
                        )
                    }
                    // A pending candidate already exists — the Planner may not
                    // create a second one.
                    guard !effectiveCard.pendingCandidateExists else {
                        throw SemanticMappingViolation.unclassifiablePlan(
                            "Cannot offer a second pending candidate while one is already active"
                        )
                    }
                    return .offerCardConnectionCandidate
                }
                return .continueOpenCardConnection
            case .observation, .awaitingCandidateResolution, .guidance, .none:
                throw SemanticMappingViolation.cardSubstateMismatch(
                    .inviteCardConnection, substate
                )
            }

        case (.cardReflection, .deepenCardConnection):
            // Legacy v3/v4 only; semantically equivalent to continuing open connection.
            guard session.protocolVersion < ReflectionSession.currentProtocolVersion else {
                throw SemanticMappingViolation.unclassifiablePlan(
                    "deepenCardConnection is retired in current protocol"
                )
            }
            return .continueOpenCardConnection

        case (.cardReflection, .authorizeCardGuidance):
            // v5: silent authorization of a confirmed connection.
            guard substate == .guidance
                    || plan.memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil else {
                throw SemanticMappingViolation.cardSubstateMismatch(
                    .authorizeCardGuidance, substate
                )
            }
            return .authorizeCardGuidance

        case (.cardReflection, .presentCardReading):
            // v4: legacy negotiated reading.
            return .presentLegacyCardReading

        case (.cardReflection, .directCandidReflection):
            // The Planner selected direct reflection while still in cardReflection stage.
            // This is only legal as an explicit bypass when connection is typed unavailable.
            if effectiveCard.connectionUnavailable {
                return .bypassCardConnectionToDirectReflection
            }
            // In any other cardReflection substate, directCandidReflection is not a legal
            // semantic operation. The v5 guidance authorization path uses authorizeCardGuidance
            // with the shareCardGuidance local action, never directCandidReflection. Once
            // guidance is authorized the stage is directReflection, not cardReflection.
            throw SemanticMappingViolation.cardSubstateMismatch(
                .directCandidReflection, substate
            )

        // ── Direct Reflection ──────────────────────────────────────────────

        case (.directReflection, .directCandidReflection):
            return try classifyDirectReflectionOperation(from: plan, session: session)

        case (.directReflection, .presentFinalNarrative):
            return .confirmNarrative

        case (.directReflection, .suggestPractice):
            return .proposePractice

        // ── Narrative Confirmation ─────────────────────────────────────────

        case (.narrativeConfirmation, .requestNarrativeConfirmation):
            return .confirmNarrative

        case (.narrativeConfirmation, .reviseFinalNarrative):
            return .reviseNarrative

        case (.narrativeConfirmation, .presentCardReading):
            // Legacy re-entry from narrative back to card reading.
            return .presentLegacyCardReading

        case (.narrativeConfirmation, .directCandidReflection):
            // Legacy re-entry: return to direct reflection from narrative.
            return try classifyDirectReflectionOperation(from: plan, session: session)

        case (.narrativeConfirmation, .suggestPractice):
            return .proposePractice

        case (.narrativeConfirmation, .completeConversation):
            return .completeConversation

        // ── Optional Action ────────────────────────────────────────────────

        case (.optionalAction, .suggestPractice):
            // Proposing a new practice or re-proposing after unclear.
            return .proposePractice

        case (.optionalAction, .revisePractice):
            return .resolvePractice

        case (.optionalAction, .presentFinalNarrative):
            return .confirmNarrative

        case (.optionalAction, .completeConversation):
            return .completeConversation

        // ── Complete ───────────────────────────────────────────────────────

        case (.complete, .completeConversation):
            return .completeConversation

        // ── Safety Support ─────────────────────────────────────────────────

        case (.safetySupport, .safetySupport):
            return .provideSafetySupport

        case (.safetySupport, .completeConversation):
            return .completeConversation

        // Cross-stage safety is always permitted.
        case (_, .safetySupport):
            return .provideSafetySupport

        // ── Explicitly unclassified ────────────────────────────────────────

        default:
            throw SemanticMappingViolation.ambiguousReplyIntent(
                plan.replyIntent,
                session.protocolStage
            )
        }
    }

    // MARK: - Sub-classification helpers

    /// Resolves the direction of a `directCandidReflection` turn inside the Direct Reflection stage.
    private func classifyDirectReflectionOperation(
        from plan: LLMTurnResponsePlan,
        session: ReflectionSession
    ) throws -> PlannerSemanticOperation {
        let frame = plan.memoryUpdate.reflectionFrame
            ?? session.semanticMemory.reflectionFrame

        guard let frame else {
            // Current protocol requires a reflection frame for reflection operations.
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                throw SemanticMappingViolation.missingRequiredOutcome(.directCandidReflection)
            }
            // Legacy sessions default to Tender.
            return .continueTenderReflection
        }

        if frame.action == .synthesizeUnderstanding {
            return .synthesizeDirectReflection
        }

        switch frame.mode {
        case .tender:
            return .continueTenderReflection
        case .fierce:
            return .continueTenderGroundedFierceReflection
        }
    }

    /// Resolves the specific candidate-resolution outcome from the typed card-connection union.
    private func classifyCardCandidateResolution(
        from plan: LLMTurnResponsePlan
    ) throws -> PlannerSemanticOperation {
        guard let outcome = plan.cardConnectionTurnOutcome else {
            throw SemanticMappingViolation.missingRequiredOutcome(.inviteCardConnection)
        }

        switch outcome.kind {
        case .candidateAccepted:
            return .acceptCardConnectionCandidate
        case .candidateRevised:
            return .reviseCardConnectionCandidate
        case .candidateRejected:
            return .rejectCardConnectionCandidate
        case .userAuthoredConnection, .connectionStillUnclear:
            throw SemanticMappingViolation.unclassifiablePlan(
                "cardConnectionTurnOutcome kind \(outcome.kind.rawValue) is not a candidate-resolution outcome"
            )
        }
    }

    /// The formal typed eligibility condition for offering a candidate bridge.
    /// Reads from `EffectiveCardSemanticState` — all conditions must be satisfied:
    /// exploration started, difficulty occurred, scaffold used, no pending candidate,
    /// no canonical connection, no guidance authorized, current protocol.
    private func candidateBridgeEligible(
        for session: ReflectionSession,
        effectiveCard: EffectiveCardSemanticState
    ) -> Bool {
        effectiveCard.candidateBridgeEligible
    }

    /// A pending candidate is structurally complete when both image relation and reality
    /// mapping are present in the memory update.
    private func hasStructurallyCompletePendingCandidate(
        in update: TurnSemanticMemoryUpdate
    ) -> Bool {
        update.pendingCardRealityConnection?.isStructurallyComplete == true
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Semantic Operation Projector

extension ReflectionProtocolController {

    /// Deterministically projects a `PlannerSemanticDecision` into a complete
    /// executable turn plan. All protocol metadata (stage, intent, prompt, confirmation,
    /// local action) is derived from the semantic operation and typed state — never
    /// from the old Planner's `requestedStage`, `nextPrompt`, or `confirmation` fields.
    ///
    /// - Parameters:
    ///   - decision: Classified semantic operation with grounded memory patch and focus.
    ///   - session: Current committed session state.
    ///   - effectiveEventState: Projected Event Disclosure state.
    ///   - effectiveCardState: Projected Card semantic state.
    /// - Returns: A fully specified `ProjectedExecutableTurnPlan`.
    /// - Throws: `ProjectionViolation` if the operation is illegal for the current state.
    func projectExecutablePlan(
        decision: PlannerSemanticDecision,
        session: ReflectionSession,
        effectiveEventState: EffectiveEventDisclosureState,
        effectiveCardState: EffectiveCardSemanticState
    ) throws -> ProjectedExecutableTurnPlan {
        executionAudit?.record(.projector)
        let sourceStage = session.protocolStage
        let isCurrentProtocol = session.protocolVersion >= ReflectionSession.currentProtocolVersion
        let memoryUpdate = decision.memoryUpdate

        let plan = try project(
            operation: decision.operation,
            memoryUpdate: memoryUpdate,
            responseFocus: decision.responseFocus,
            clarificationFocus: decision.clarificationFocus,
            sourceStage: sourceStage,
            effectiveEventState: effectiveEventState,
            effectiveCardState: effectiveCardState,
            isCurrentProtocol: isCurrentProtocol,
            session: session
        )

        return plan
    }

    // ── Private projection switch (exhaustive, no default) ──────────────

    private func project(
        operation: PlannerSemanticOperation,
        memoryUpdate: TurnSemanticMemoryUpdate,
        responseFocus: String?,
        clarificationFocus: String?,
        sourceStage: ReflectionProtocolStage,
        effectiveEventState: EffectiveEventDisclosureState,
        effectiveCardState: EffectiveCardSemanticState,
        isCurrentProtocol: Bool,
        session: ReflectionSession
    ) throws -> ProjectedExecutableTurnPlan {

        // ── Helpers ───────────────────────────────────────────────────

        func plan(
            requestedStage: ReflectionProtocolStage,
            replyIntent: TurnReplyIntent,
            nextPrompt: TurnNextPrompt,
            localAction: TurnLocalActionRequest = .none,
            resolvedConfirmation: TurnResolvedConfirmation? = nil
        ) -> ProjectedExecutableTurnPlan {
            ProjectedExecutableTurnPlan(
                semanticDecision: PlannerSemanticDecision(
                    operation: operation,
                    memoryUpdate: memoryUpdate,
                    responseFocus: responseFocus,
                    clarificationFocus: clarificationFocus
                ),
                sourceStage: sourceStage,
                requestedStage: requestedStage,
                replyIntent: replyIntent,
                localAction: localAction,
                nextPrompt: nextPrompt,
                resolvedConfirmation: resolvedConfirmation,
                memoryUpdate: memoryUpdate,
                responseFocus: responseFocus
            )
        }

        func openQuestion(
            purpose: String,
            focus: String,
            stage: ReflectionProtocolStage,
            intent: TurnReplyIntent,
            disclosurePurpose: TurnDisclosureQuestionPurpose? = nil,
            disclosureTarget: TurnDisclosureQuestionTarget? = nil
        ) -> TurnNextPrompt {
            .openQuestion(
                purpose: purpose,
                focus: focus,
                disclosurePurpose: disclosurePurpose,
                disclosureTarget: disclosureTarget
            )
        }

        func confirmation(
            target: TurnConfirmationTarget,
            referenceID: String? = nil
        ) -> TurnNextPrompt {
            .confirmationRequest(target: target, referenceID: referenceID)
        }

        // ── Switch ────────────────────────────────────────────────────

        switch operation {

        // ── Event Disclosure ──────────────────────────────────────────

        case .clarifyEvent:
            guard sourceStage == .contextualDisclosure else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard !isEventDisclosureCoreComplete(effectiveEventState) else {
                throw ProjectionViolation.structuralInvariant(
                    operation, "Disclosure core is complete; use advanceToCardConsent"
                )
            }
            guard let focus = clarificationFocus else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "clarificationFocus required for clarifyEvent"
                )
            }
            var candidateMemory = effectiveEventState.memory
            if let answeredPurpose = effectiveCurrentPrompt(for: session)?.disclosurePurpose {
                candidateMemory.receivedDisclosureQuestionPurposes = Array(
                    Set(candidateMemory.receivedDisclosureQuestionPurposes + [answeredPurpose])
                ).sorted { $0.rawValue < $1.rawValue }
            }
            let candidateState = EffectiveEventDisclosureState(memory: candidateMemory)
            guard let purpose = availableDisclosurePurposes(in: candidateState).first else {
                throw ProjectionViolation.structuralInvariant(
                    operation, "No unresolved Event Disclosure relation remains"
                )
            }
            return plan(
                requestedStage: .contextualDisclosure,
                replyIntent: .exploreContext,
                nextPrompt: openQuestion(
                    purpose: purpose.rawValue,
                    focus: focus,
                    stage: .contextualDisclosure,
                    intent: .exploreContext,
                    disclosurePurpose: purpose,
                    disclosureTarget: purpose.target
                )
            )

        case .advanceToCardConsent:
            guard sourceStage == .contextualDisclosure else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard isEventDisclosureCoreComplete(effectiveEventState) else {
                throw ProjectionViolation.structuralInvariant(
                    operation, "Disclosure core not complete; use clarifyEvent"
                )
            }
            return plan(
                requestedStage: .cardConsent,
                replyIntent: .inviteCardConsent,
                nextPrompt: confirmation(target: .cardConsent)
            )

        // ── Card Consent ──────────────────────────────────────────────

        case .inviteCardConsent:
            guard sourceStage == .cardConsent else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .cardConsent,
                replyIntent: .inviteCardConsent,
                nextPrompt: confirmation(target: .cardConsent)
            )

        case .acknowledgeCardConsent:
            guard sourceStage == .cardConsent else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .cardConsent,
                replyIntent: .acknowledgeCardConsent,
                nextPrompt: .none,
                localAction: .init(kind: .drawRandomCard),
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .cardConsent,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            )

        case .declineCardConsent:
            guard sourceStage == .cardConsent else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .directReflection,
                replyIntent: .acknowledgeCardDecline,
                nextPrompt: .none,
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .cardConsent,
                    decision: .declined
                )
            )

        // ── Card Observation ──────────────────────────────────────────

        case .continueCardObservation:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard effectiveCardState.substate == .observation else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .inviteCardObservation,
                nextPrompt: openQuestion(
                    purpose: "cardObservation",
                    focus: clarificationFocus ?? "describe_visible_image",
                    stage: .cardReflection,
                    intent: .inviteCardObservation
                )
            )

        // ── Card Development ──────────────────────────────────────────

        case .continueCardDevelopment:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            // Once typed Development exists, the next operation is Reality Connection; another
            // Development operation would repeat a completed relation.
            guard effectiveCardState.substate == .observation else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .developCardImage,
                nextPrompt: openQuestion(
                    purpose: "cardDevelopment",
                    focus: clarificationFocus ?? "anticipated_change",
                    stage: .cardReflection,
                    intent: .developCardImage
                )
            )

        case .offerCardConnectionScaffold:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            let entersOpenExploration =
                effectiveCardState.substate == .development
                && memoryUpdate.cardConnectionOutcome == .noConnectionFound
            guard effectiveCardState.substate == .openExploration
                    || entersOpenExploration else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            guard (effectiveCardState.connectionDifficultyOccurred
                    || memoryUpdate.cardConnectionOutcome == .noConnectionFound),
                  !effectiveCardState.bridgeScaffoldUsed,
                  !effectiveCardState.candidateBridgeOfferedOrResolved,
                  !effectiveCardState.pendingCandidateExists,
                  !effectiveCardState.canonicalConnectionExists else {
                throw ProjectionViolation.capabilityNotAvailable(
                    operation, "Scaffold requires difficulty, no prior scaffold, no candidate"
                )
            }
            // Use developCardImage so updateProtocolCardConnectionCapabilities sets
            // cardConnectionScaffoldUsed=true atomically. The purpose distinguishes
            // this scaffold from actual image development.
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .developCardImage,
                nextPrompt: openQuestion(
                    purpose: "cardRealityConnectionScaffold",
                    focus: clarificationFocus ?? "narrow_connection_task",
                    stage: .cardReflection,
                    intent: .developCardImage
                )
            )

        case .establishUserAuthoredCardConnection:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard isCurrentProtocol,
                  session.protocolVersion == ReflectionSession.currentProtocolVersion,
                  session.condition.usesCard,
                  session.cardDisplayState == .displayed,
                  !session.cardGuidanceShared,
                  !session.cardConnectionUnavailable,
                  !effectiveCardState.pendingCandidateExists,
                  let connection = memoryUpdate.cardRealityConnection?.normalizedConfirmed,
                  connection.source == .userAuthored else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation,
                    "Current user-authored connection required"
                )
            }
            guard memoryUpdate.reflectionFrame?.mode == .tender else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation,
                    "Tender reflectionFrame required for combined guidance"
                )
            }
            // Single combined visible turn: shareCardGuidance authorizes the
            // canonical connection while directCandidReflection lets the Writer
            // produce a Tender openQuestion with a Card Guidance bridge.
            return plan(
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: .openQuestion(
                    purpose: "tender_grounding_after_card_guidance",
                    focus: "begin_tender_reflection_after_user_authored_connection"
                ),
                localAction: .init(kind: .shareCardGuidance)
            )

        // ── Reality Connection ────────────────────────────────────────

        case .inviteRealityConnection:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard effectiveCardState.substate == .development else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            guard !effectiveCardState.pendingCandidateExists,
                  !effectiveCardState.canonicalConnectionExists else {
                throw ProjectionViolation.structuralInvariant(
                    operation, "Cannot invite reality connection with active pending/canonical connection"
                )
            }
            // Deliberately always openQuestion, never .none
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .inviteCardConnection,
                nextPrompt: openQuestion(
                    purpose: "cardRealityConnection",
                    focus: clarificationFocus ?? "connect_image_to_reality",
                    stage: .cardReflection,
                    intent: .inviteCardConnection
                )
            )

        case .continueOpenCardConnection:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard effectiveCardState.substate == .openExploration else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .inviteCardConnection,
                nextPrompt: openQuestion(
                    purpose: "cardRealityConnection",
                    focus: clarificationFocus ?? "explore_connection",
                    stage: .cardReflection,
                    intent: .inviteCardConnection
                )
            )

        case .offerCardConnectionCandidate:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard effectiveCardState.substate == .openExploration else {
                throw ProjectionViolation.illegalOperationForCardSubstate(
                    operation, effectiveCardState.substate
                )
            }
            guard effectiveCardState.candidateBridgeEligible else {
                throw ProjectionViolation.capabilityNotAvailable(
                    operation, "Candidate bridge not eligible"
                )
            }
            guard let pending = memoryUpdate.pendingCardRealityConnection,
                  pending.isStructurallyComplete else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "pendingCardRealityConnection required in memory update"
                )
            }
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .inviteCardConnection,
                nextPrompt: confirmation(
                    target: .cardRealityConnection,
                    referenceID: pending.id.uuidString
                )
            )

        // ── Candidate Resolution ──────────────────────────────────────

        case .acceptCardConnectionCandidate:
            guard effectiveCardState.substate == .awaitingCandidateResolution,
                  let pending = session.semanticMemory.pendingCardRealityConnection,
                  pending.isStructurallyComplete else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "No active pending candidate to accept"
                )
            }
            var mem = memoryUpdate
            mem.cardRealityConnection = TurnCardRealityConnection(
                imageRelation: pending.imageRelation,
                realityMapping: pending.candidateRealityMapping,
                source: .userAccepted
            )
            mem.clearPendingCardRealityConnection = true
            mem.cardConnectionOutcome = .connectionConfirmed
            mem.candidateBridgeResolvedAt = Date()
            if isCurrentProtocol,
               mem.reflectionFrame?.mode != .tender {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Tender reflectionFrame required for combined candidate acceptance"
                )
            }
            let stage: ReflectionProtocolStage = isCurrentProtocol ? .directReflection : .cardReflection
            return ProjectedExecutableTurnPlan(
                semanticDecision: PlannerSemanticDecision(
                    operation: operation, memoryUpdate: mem,
                    responseFocus: responseFocus, clarificationFocus: clarificationFocus
                ),
                sourceStage: sourceStage,
                requestedStage: stage,
                replyIntent: isCurrentProtocol ? .directCandidReflection : .authorizeCardGuidance,
                localAction: isCurrentProtocol ? .init(kind: .shareCardGuidance) : .none,
                nextPrompt: isCurrentProtocol
                    ? .openQuestion(
                        purpose: "tender_grounding_after_card_guidance",
                        focus: "continue_from_accepted_card_connection"
                    )
                    : .none,
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .cardRealityConnection,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                ),
                memoryUpdate: mem,
                responseFocus: responseFocus
            )

        case .reviseCardConnectionCandidate:
            guard effectiveCardState.substate == .awaitingCandidateResolution,
                  session.semanticMemory.pendingCardRealityConnection?.isStructurallyComplete == true else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "No active pending candidate to revise"
                )
            }
            guard let revised = memoryUpdate.cardRealityConnection?.normalizedConfirmed,
                  revised.source == .userRevised else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Revised connection with source=userRevised required"
                )
            }
            var mem = memoryUpdate
            mem.clearPendingCardRealityConnection = true
            mem.cardConnectionOutcome = .connectionConfirmed
            mem.candidateBridgeResolvedAt = Date()
            if isCurrentProtocol,
               mem.reflectionFrame?.mode != .tender {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Tender reflectionFrame required for combined candidate revision"
                )
            }
            let stage: ReflectionProtocolStage = isCurrentProtocol ? .directReflection : .cardReflection
            return ProjectedExecutableTurnPlan(
                semanticDecision: PlannerSemanticDecision(
                    operation: operation, memoryUpdate: mem,
                    responseFocus: responseFocus, clarificationFocus: clarificationFocus
                ),
                sourceStage: sourceStage,
                requestedStage: stage,
                replyIntent: isCurrentProtocol ? .directCandidReflection : .authorizeCardGuidance,
                localAction: isCurrentProtocol ? .init(kind: .shareCardGuidance) : .none,
                nextPrompt: isCurrentProtocol
                    ? .openQuestion(
                        purpose: "tender_grounding_after_card_guidance",
                        focus: "continue_from_revised_card_connection"
                    )
                    : .none,
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .cardRealityConnection,
                    decision: .revised,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                ),
                memoryUpdate: mem,
                responseFocus: responseFocus
            )

        case .rejectCardConnectionCandidate:
            guard effectiveCardState.substate == .awaitingCandidateResolution,
                  session.semanticMemory.pendingCardRealityConnection?.isStructurallyComplete == true else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "No active pending candidate to reject"
                )
            }
            var mem = memoryUpdate
            mem.clearPendingCardRealityConnection = true
            mem.cardConnectionOutcome = .candidateRejected
            mem.candidateBridgeResolvedAt = Date()
            return ProjectedExecutableTurnPlan(
                semanticDecision: PlannerSemanticDecision(
                    operation: operation, memoryUpdate: mem,
                    responseFocus: responseFocus, clarificationFocus: clarificationFocus
                ),
                sourceStage: sourceStage,
                requestedStage: .cardReflection,
                replyIntent: .inviteCardConnection,
                localAction: .none,
                nextPrompt: isCurrentProtocol
                    ? .openQuestion(
                        purpose: "cardRealityConnection",
                        focus: "continue_after_rejected_candidate"
                    )
                    : .none,
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .cardRealityConnection,
                    decision: .rejected,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                ),
                memoryUpdate: mem,
                responseFocus: responseFocus
            )

        // ── Card Bypass ───────────────────────────────────────────────

        case .bypassCardConnectionToDirectReflection:
            guard sourceStage == .cardReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard effectiveCardState.connectionUnavailable else {
                throw ProjectionViolation.structuralInvariant(
                    operation, "Bypass requires connectionUnavailable or explicit user request"
                )
            }
            return plan(
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: .openQuestion(
                    purpose: "enter_direct_reflection",
                    focus: "begin_tender_reflection"
                )
            )

        // ── Card Guidance (v5) / Legacy Reading (v4) ──────────────────

        case .authorizeCardGuidance:
            guard isCurrentProtocol else {
                throw ProjectionViolation.capabilityNotAvailable(
                    operation, "authorizeCardGuidance requires v5+"
                )
            }
            // Connection may be in the session (already committed) or in the
            // memory update (transferred from userAuthoredConnection outcome).
            let hasConnection = effectiveCardState.canonicalConnectionExists
                || memoryUpdate.cardRealityConnection?.normalizedConfirmed != nil
            guard hasConnection else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Canonical connection required for guidance authorization"
                )
            }
            guard memoryUpdate.reflectionFrame?.mode == .tender else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Tender reflectionFrame required for visible guidance continuation"
                )
            }
            return plan(
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: .openQuestion(
                    purpose: "tender_grounding_after_card_guidance",
                    focus: "continue_from_confirmed_card_connection"
                ),
                localAction: .init(kind: .shareCardGuidance)
            )

        case .presentLegacyCardReading:
            guard !isCurrentProtocol else {
                throw ProjectionViolation.capabilityNotAvailable(
                    operation, "presentLegacyCardReading is v4 only"
                )
            }
            return plan(
                requestedStage: .cardReflection,
                replyIntent: .presentCardReading,
                nextPrompt: confirmation(target: .cardMapping)
            )

        // ── Direct Reflection ─────────────────────────────────────────

        case .continueExploratoryReflection:
            throw ProjectionViolation.capabilityNotAvailable(
                operation, "current-v5 exploratory reflection uses the canonical projector only"
            )

        case .continueTenderReflection:
            guard sourceStage == .directReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: openQuestion(
                    purpose: "tender_reflection",
                    focus: clarificationFocus ?? "grounded_tender_distinction",
                    stage: .directReflection,
                    intent: .directCandidReflection
                )
            )

        case .continueTenderGroundedFierceReflection:
            guard sourceStage == .directReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            guard let frame = memoryUpdate.reflectionFrame,
                  frame.mode == .fierce else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Fierce reflectionFrame required"
                )
            }
            return plan(
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: openQuestion(
                    purpose: "tender_grounded_fierce_reflection",
                    focus: clarificationFocus ?? "fierce_distinction",
                    stage: .directReflection,
                    intent: .directCandidReflection
                )
            )

        case .synthesizeDirectReflection:
            guard sourceStage == .directReflection else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                // Synthesis is the final Direct Reflection turn. The subsequent explicit
                // proposePractice/noAction operation owns the transition into Optional Action.
                requestedStage: .directReflection,
                replyIntent: .directCandidReflection,
                nextPrompt: .none
            )

        // ── Optional Action ───────────────────────────────────────────

        case .proposePractice:
            guard let transition = memoryUpdate.practiceTransition,
                  let proposal = transition.proposal,
                  transition.noActionReason == nil else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "Complete practiceTransition with proposal required"
                )
            }
            return plan(
                requestedStage: .optionalAction,
                replyIntent: .suggestPractice,
                nextPrompt: confirmation(
                    target: .practice,
                    referenceID: proposal.id
                ),
                resolvedConfirmation: sourceStage == .narrativeConfirmation
                    ? TurnResolvedConfirmation(
                        target: .finalNarrative,
                        decision: .accepted,
                        referenceID: transition.narrativeReferenceID
                    )
                    : nil
            )

        case .resolvePractice:
            guard let pending = session.semanticMemory.practiceTransition,
                  pending.proposal != nil else {
                throw ProjectionViolation.missingTypedPrecondition(
                    operation, "No pending practice to resolve"
                )
            }
            return plan(
                requestedStage: .narrativeConfirmation,
                replyIntent: .presentFinalNarrative,
                nextPrompt: confirmation(target: .finalNarrative),
                resolvedConfirmation: TurnResolvedConfirmation(
                    target: .practice,
                    decision: .accepted,
                    referenceID: pending.transactionID
                )
            )

        // ── Narrative ─────────────────────────────────────────────────

        case .confirmNarrative:
            guard sourceStage == .narrativeConfirmation
                    || sourceStage == .directReflection
                    || sourceStage == .optionalAction else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .narrativeConfirmation,
                replyIntent: .presentFinalNarrative,
                nextPrompt: confirmation(target: .finalNarrative)
            )

        case .reviseNarrative:
            guard sourceStage == .narrativeConfirmation else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            return plan(
                requestedStage: .narrativeConfirmation,
                replyIntent: .reviseFinalNarrative,
                nextPrompt: confirmation(target: .finalNarrative)
            )

        // ── Completion ────────────────────────────────────────────────

        case .completeConversation:
            guard sourceStage == .narrativeConfirmation
                    || sourceStage == .optionalAction
                    || sourceStage == .complete
                    || sourceStage == .safetySupport else {
                throw ProjectionViolation.illegalOperationForStage(operation, sourceStage)
            }
            let finalNarrativeResolution: TurnResolvedConfirmation?
            if sourceStage == .narrativeConfirmation {
                guard session.semanticMemory.nextPrompt?.target == .finalNarrative else {
                    throw ProjectionViolation.missingTypedPrecondition(
                        operation,
                        "Active finalNarrative confirmation required to complete"
                    )
                }
                finalNarrativeResolution = TurnResolvedConfirmation(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: session.semanticMemory.nextPrompt?.referenceID
                )
            } else {
                finalNarrativeResolution = nil
            }
            return plan(
                requestedStage: .complete,
                replyIntent: .completeConversation,
                nextPrompt: .none,
                localAction: .init(kind: .completeSession),
                resolvedConfirmation: finalNarrativeResolution
            )

        // ── Safety ────────────────────────────────────────────────────

        case .provideSafetySupport:
            return plan(
                requestedStage: .safetySupport,
                replyIntent: .safetySupport,
                nextPrompt: .none
            )
        }
    }

    /// Converts a projected executable plan into the shape expected by the Writer
    /// and existing transaction commit. This adapter is a pure function — it reads
    /// only the projected plan and never the original Planner output.
    func executablePlanAdapter(
        from projected: ProjectedExecutableTurnPlan
    ) -> LLMTurnResponsePlan {
        LLMTurnResponsePlan(
            semanticOperation: projected.semanticDecision.operation,
            projectedOperation: projected.semanticDecision.operation,
            requestedStage: projected.requestedStage,
            localAction: projected.localAction,
            memoryUpdate: projected.memoryUpdate,
            cardConnectionTurnOutcome: nil,
            resolvedConfirmation: projected.resolvedConfirmation,
            nextPrompt: projected.nextPrompt,
            replyIntent: projected.replyIntent,
            replyGuidance: projected.responseFocus ?? ""
        )
    }
}
