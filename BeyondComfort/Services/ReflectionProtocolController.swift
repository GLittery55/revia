import Foundation

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

    init(
        currentStage: ReflectionProtocolStage,
        allowedStages: [ReflectionProtocolStage],
        allowedActions: [TurnLocalActionKind],
        allowedReplyIntents: [TurnReplyIntent],
        allowedDisclosurePurposes: [TurnDisclosureQuestionPurpose] = [],
        allowedDisclosureTargets: [TurnDisclosureQuestionTarget] = [],
        allowedOperations: [TurnProtocolOperation] = []
    ) {
        self.currentStage = currentStage
        self.allowedStages = allowedStages
        self.allowedActions = allowedActions
        self.allowedReplyIntents = allowedReplyIntents
        self.allowedDisclosurePurposes = allowedDisclosurePurposes
        self.allowedDisclosureTargets = allowedDisclosureTargets
        self.allowedOperations = allowedOperations
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
    case unknownTrackingCue
    case duplicateTrackingCue
    case trackingReviewRequired
    case missingNoActionReason
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
}

enum TurnRequiredMemoryField: String, Equatable, Sendable {
    case situationUnderstanding
    case selfCriticismStatus
    case selfCriticalStatement
    case selfCriticismLink
    case episodeStructure
    case contextRelationship
    /// Optional current memory; retained as a legacy repair label for older saved payloads.
    case tenderUnderstanding
    case cardNegotiatedMeaning
    case cardInterpretiveTension
    case cardRealityMappingSource
    case candidUnderstanding
    /// Legacy repair code retained for older persisted requests.
    case fierceUnderstanding
    case finalNarrative
    case practiceKind
    case practiceBasis
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
    case missingPracticeKind
    case missingPracticeOptions
    case limitedPracticeChoiceSet
    case normalizedNextPromptMetadata
    case repeatedQuestionPurpose
    case redundantConfirmedConnectionPatch = "redundant_confirmed_connection_patch"
}

/// This controller knows study protocol, not conversation meaning. In particular, it never
/// decides whether the person has expressed enough emotion, accepted an interpretation, or has
/// sufficient evidence for responsibility. Those are LLM TurnController decisions.
struct ReflectionProtocolController: Sendable {
    func permissions(for session: ReflectionSession) -> ReflectionProtocolPermissions {
        permissions(
            for: session,
            effectiveConnection: effectiveCardRealityConnection(for: session)
        )
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
        let stages = allowedStages(
            from: session.protocolStage,
            condition: session.condition
        )
        var actions: [TurnLocalActionKind] = [.none]
        var replyIntents = allowedReplyIntents(from: session.protocolStage)
        var disclosurePurposes: [TurnDisclosureQuestionPurpose] = []
        var disclosureTargets: [TurnDisclosureQuestionTarget] = []

        // Protocol-v2 sessions retain their exact saved interaction contract. The internal Tender
        // bridge and post-mapping deepening are current-protocol capabilities only.
        if session.protocolVersion < ReflectionSession.internalTenderProtocolVersion {
            replyIntents.removeAll {
                [.deepenCardConnection].contains($0)
                    || (session.protocolStage == .contextualDisclosure
                        && [.inviteCardConsent, .directCandidReflection].contains($0))
            }
        }

        switch session.protocolStage {
        case .contextualDisclosure:
            let disclosureState = EffectiveEventDisclosureState(
                memory: session.semanticMemory
            )
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                disclosurePurposes = availableDisclosurePurposes(in: disclosureState)
                disclosureTargets = Array(Set(disclosurePurposes.map(\.target))).sorted {
                    $0.rawValue < $1.rawValue
                }
            }
            // Context is supplied as one measurement-free hypothesis inside ordinary reflection;
            // it no longer creates a separate local presentation or confirmation action.
            // Keep the old tracking-resolution intents only for an actually resumed interaction
            // that is already waiting on a previously presented cue. Advertising those intents
            // to a current session with no pending tracking confirmation is contradictory: the
            // Planner may select integrateTrackingAndPresentTenderSummary even though there is
            // no trackingRelationship object it could legally resolve.
            let currentPrompt = effectiveCurrentPrompt(for: session)
            let isResolvingPresentedLegacyTracking =
                currentPrompt?.kind == .confirmationRequest
                && currentPrompt?.target == .trackingRelationship
                && (
                    session.activeTrackingPresentationID != nil
                    || !session.presentedTrackingCueIDs.isEmpty
                )
            if isResolvingPresentedLegacyTracking {
                replyIntents = replyIntents.filter {
                    [
                        .checkTrackingRelationship,
                        .integrateTrackingAndPresentTenderSummary,
                        .safetySupport,
                    ].contains($0)
                }
            } else {
                if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion {
                    // A current card session does not need a separate Tender-analysis turn before
                    // consent. Once the Planner judges the event story coherent, the card bridge
                    // itself carries the one brief, supported grounding distinction. Resumed
                    // tenderConfirmation sessions remain valid, but new card sessions choose only
                    // between one more event question and the direct optional invitation.
                    if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
                       session.condition.usesCard {
                        replyIntents = [.exploreContext, .inviteCardConsent, .safetySupport]
                        if isEventDisclosureCoreComplete(disclosureState) {
                            replyIntents.removeAll { $0 == .exploreContext }
                        }
                    } else {
                        replyIntents = [.exploreContext, .presentTenderSummary, .safetySupport]
                    }
                } else {
                    replyIntents.removeAll {
                        [
                            .presentTrackingContext,
                            .checkTrackingRelationship,
                            .integrateTrackingAndPresentTenderSummary,
                        ].contains($0)
                    }
                }
            }
        case .tenderConfirmation:
            // Advertise only the forward intent that belongs to the assigned experiment
            // condition. The validator already enforces these stage/intent pairs; applying the
            // same boundary here prevents a Planner from seeing a contradictory permission set
            // such as directReflection together with inviteCardConsent.
            if session.condition.usesCard {
                replyIntents.removeAll { $0 == .directCandidReflection }
            } else {
                replyIntents.removeAll { $0 == .inviteCardConsent }
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
            if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
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
                // A candidate reading is a post-authorization operation. Advertising it before
                // `shareCardGuidance` creates a contradictory contract: the Planner can select
                // presentCardReading from CURRENT PERMISSIONS, only for the validator to reject
                // it because no guided context exists yet. The model may still identify a new
                // user-authored mapping in this turn, but the only corresponding card operation
                // is the silent authorizeCardGuidance transaction.
                replyIntents.removeAll { $0 == .presentCardReading }
            } else if session.cardGuidanceShared {
                // Authorization is a one-time local capability. Once committed, the only useful
                // next card operation is a visible reading or later reflection; advertising the
                // silent authorization intent again lets a no-op plan loop forever.
                replyIntents.removeAll { $0 == .authorizeCardGuidance }
                if effectiveCurrentPrompt(for: session)?.target == .cardMapping,
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
            if session.reflectionReadiness == .narrativeReady {
                // Once the Planner has selected the final narrative, a formatting retry must not
                // reopen reflection. Before that point, Swift exposes both another bounded candid
                // turn and the narrative transition; the Planner decides whether further Tender
                // or Fierce exploration still adds material understanding.
                replyIntents = replyIntents.filter {
                    [.presentFinalNarrative, .safetySupport].contains($0)
                }
            }
        case .narrativeConfirmation, .optionalAction, .safetySupport:
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
            )
        )
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
        for session: ReflectionSession
    ) throws -> LLMTurnControllerResponse {
        guard !response.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReflectionProtocolViolation.emptyReply
        }
        let validatedPlan = try validate(
            LLMTurnResponsePlan(
                requestedStage: response.requestedStage,
                localAction: response.localAction,
                memoryUpdate: response.memoryUpdate,
                resolvedConfirmation: response.resolvedConfirmation,
                nextPrompt: response.nextPrompt,
                replyIntent: response.replyIntent,
                noActionReason: response.noActionReason,
                replyGuidance: "validated response"
            ),
            for: session
        )
        return LLMTurnControllerResponse(
            requestedStage: validatedPlan.requestedStage,
            localAction: validatedPlan.localAction,
            memoryUpdate: validatedPlan.memoryUpdate,
            resolvedConfirmation: validatedPlan.resolvedConfirmation,
            nextPrompt: validatedPlan.nextPrompt,
            replyIntent: validatedPlan.replyIntent,
            noActionReason: validatedPlan.noActionReason,
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
        let normalizedPlan = normalizeEquivalentProtocolLabels(
            in: plan,
            for: session
        )
        return try validateNormalized(normalizedPlan, for: session)
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

        if [.suggestPractice, .revisePractice].contains(validatedPlan.replyIntent),
           validatedPlan.memoryUpdate.practiceKind != .noAction {
            let optionCount = validatedPlan.memoryUpdate.practiceOptions?.count ?? 0
            if optionCount == 0 {
                warnings.append(.missingPracticeOptions)
            }
        }

        if validatedPlan.replyIntent == .completeConversation,
           validatedPlan.resolvedConfirmation?.target == .practice,
           let practiceDecision = validatedPlan.resolvedConfirmation?.decision,
           [TurnConfirmationDecision.accepted, .revised].contains(practiceDecision),
           validatedPlan.memoryUpdate.practiceKind == nil,
           session.semanticMemory.practiceKind == nil {
            warnings.append(.missingPracticeKind)
        }

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
        for session: ReflectionSession
    ) -> LLMTurnResponsePlan {
        let protocolPlan = splitCombinedCardGuidanceRequest(plan)
        var memoryUpdate = protocolPlan.memoryUpdate

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
           session.protocolStage == .contextualDisclosure,
           isEventDisclosureCoreComplete(
               EffectiveEventDisclosureState(
                   memory: session.semanticMemory,
                   update: memoryUpdate
               )
           ) {
            // Readiness is derived once from the canonical effective disclosure state. The
            // Planner may omit or mislabel this summary value, but it cannot create a second gate.
            memoryUpdate.eventDisclosureOutcome = .readyForTenderOrCard
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

        if !nonempty(memoryUpdate.candidUnderstanding),
           let legacy = memoryUpdate.fierceUnderstanding,
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // `fierceUnderstanding` was the earlier, overly narrow name for the optional candid
            // result. Canonicalize a legacy Planner patch without making an otherwise legal turn
            // fail; new prompts write only `candidUnderstanding`.
            memoryUpdate.candidUnderstanding = legacy
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
        let resolvesTenderIntoDirectReflection =
            !session.condition.usesCard
            && effectiveCurrentPrompt(for: session)?.target == .tenderSummary
            && protocolPlan.replyIntent == .directCandidReflection
            && protocolPlan.resolvedConfirmation?.target == .tenderSummary
            && protocolPlan.resolvedConfirmation?.decision == .accepted

        if (resolvesCardMapping || resolvesTenderIntoDirectReflection),
           permissions(for: session).allowedStages.contains(.directReflection) {
            // Resolving the shared Tender baseline in the direct condition, or resolving a
            // negotiated card reading, is a protocol boundary. The confirmation-only transaction
            // lands in directReflection; a fresh semantic plan then decides whether a supported
            // candid question is useful or the material is already ready for final narrative.
            requestedStage = .directReflection
            // Do not commit semantic work for a question the user has not seen yet. A revised or
            // rejected negotiated meaning may still be saved, but Fierce understanding and
            // completed question functions belong to the fresh continuation transaction.
            memoryUpdate.answeredQuestionPurposes = nil
            memoryUpdate.candidUnderstanding = nil
            memoryUpdate.fierceUnderstanding = nil
            memoryUpdate.finalNarrative = nil
            memoryUpdate.practiceOptions = nil
            memoryUpdate.practiceKind = nil
            memoryUpdate.selectedPractice = nil
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
        let authorizesCurrentUserAuthoredCardMapping =
            session.protocolVersion >= ReflectionSession.currentProtocolVersion
            && session.protocolStage == .cardReflection
            && !session.cardGuidanceShared
            && !session.cardConnectionUnavailable
            && session.condition.usesCard
            && session.cardDisplayState == .displayed
            && postPatchConnection != nil
            && (
                memoryUpdate.cardRealityConnection != nil
                    || resolvesPreGuidanceConnection
            )
        if authorizesCurrentUserAuthoredCardMapping {
            // The Planner has already made the only semantic judgment Swift needs: the latest
            // answer contains a user-authored image-to-life mapping. From this typed object onward
            // workflow mechanics are application-owned. Canonicalize any filler acknowledgement,
            // repeated connection invitation, premature reading, or obsolete deepening label into
            // the silent guidance authorization. The fresh guided turn then writes the visible,
            // negotiable reading. No image text or case-specific vocabulary is inspected here.
            requestedStage = .cardReflection
            replyIntent = .authorizeCardGuidance
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
            memoryUpdate.practiceOptions = nil
            memoryUpdate.practiceKind = nil
            memoryUpdate.selectedPractice = nil
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

        if protocolPlan.replyIntent == .completeConversation,
           protocolPlan.resolvedConfirmation?.target == .practice,
           protocolPlan.resolvedConfirmation?.decision == .accepted,
           memoryUpdate.practiceKind == nil,
           let selected = memoryUpdate.selectedPractice
                ?? session.semanticMemory.selectedPractice,
           let matched = session.semanticMemory.practiceOptions.first(where: {
               $0.instruction == selected
           }) {
            // The option catalogue is application-owned once presented. Its typed kind can be
            // restored without interpreting the user's language when the Planner copied the exact
            // accepted instruction.
            memoryUpdate.practiceKind = matched.kind
        }

        var nextPrompt = protocolPlan.nextPrompt
        if protocolPlan.replyIntent == .completeConversation {
            nextPrompt = TurnNextPrompt.none
        }
        if let prompt = protocolPlan.nextPrompt {
            if protocolPlan.replyIntent == .completeConversation {
                nextPrompt = TurnNextPrompt.none
            } else if let target = confirmationTargetEstablished(by: protocolPlan.replyIntent) {
                // The typed intent uniquely establishes this target. Extra or missing
                // nextPrompt metadata cannot change the conversational function, so canonicalize
                // it instead of discarding a legal turn.
                nextPrompt = .confirmationRequest(target: target)
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
                        nextPrompt = .confirmationRequest(target: target)
                    }
                }
            }
        }
        if resolvesAcceptedCardConsent
            || resolvesCardMapping
            || resolvesTenderIntoDirectReflection
            || authorizesCurrentUserAuthoredCardMapping {
            // Confirmation resolution and the next visible operation are separate atomic
            // transactions. Discard any question drafted into the transition: accepted card
            // consent waits for local image display, while a fresh directReflection turn decides
            // whether to ask one supported question or move to narrative.
            nextPrompt = TurnNextPrompt.none
        }

        return LLMTurnResponsePlan(
            requestedStage: requestedStage,
            localAction: localAction,
            memoryUpdate: memoryUpdate,
            resolvedConfirmation: resolvedConfirmation,
            nextPrompt: nextPrompt,
            replyIntent: replyIntent,
            noActionReason: memoryUpdate.practiceKind == .noAction
                ? protocolPlan.noActionReason
                : nil,
            replyGuidance: protocolPlan.replyGuidance,
            cardReferenceSelection: protocolPlan.cardReferenceSelection
        )
    }

    /// Authorizing a user-grounded card reading is a local capability operation; presenting a
    /// negotiated reading is a later visible dialogue operation. A model may reasonably request
    /// both in one semantic plan. Split that combined request into the existing silent
    /// authorization pass, after which the TurnController receives the user's grounded relations
    /// and the system-wide reflection approach for one fresh visible reading.
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
        evidenceOnlyMemory.practiceOptions = nil
        evidenceOnlyMemory.practiceKind = nil
        evidenceOnlyMemory.selectedPractice = nil

        return LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: plan.localAction,
            memoryUpdate: evidenceOnlyMemory,
            resolvedConfirmation: plan.resolvedConfirmation,
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .authorizeCardGuidance,
            noActionReason: nil,
            replyGuidance: "Authorize use of the user-grounded image-to-reality relation, then generate one visible, correctable reading in a fresh turn."
        )
    }

    private func uniqueDestinationStage(
        for intent: TurnReplyIntent
    ) -> ReflectionProtocolStage? {
        switch intent {
        case .presentTrackingContext:
            return .contextualDisclosure
        case .integrateTrackingAndPresentTenderSummary,
             .presentTenderSummary,
             .requestTenderConfirmation,
             .reviseTenderSummary:
            return .tenderConfirmation
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
        case .integrateTrackingAndPresentTenderSummary,
             .presentTenderSummary,
             .requestTenderConfirmation,
             .reviseTenderSummary:
            return .tenderSummary
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
        guard permission.allowedStages.contains(plan.requestedStage) else {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        guard permission.allowedActions.contains(plan.localAction.kind) else {
            throw ReflectionProtocolViolation.illegalLocalAction
        }
        guard permission.allowedReplyIntents.contains(plan.replyIntent) else {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if let selection = plan.cardReferenceSelection {
            let canonicalReference = session.card.flatMap {
                CardService().canonicalReferenceGuidance(for: $0)
            }
            let relationCount = canonicalReference?.relations.count ?? 0
            let hasGroundedMapping = effectiveCardRealityConnection(for: session) != nil
            let isQuestionOperation =
                (plan.replyIntent == .presentCardReading
                    && plan.nextPrompt?.kind == .confirmationRequest
                    && plan.nextPrompt?.target == .cardMapping)
                || (plan.replyIntent == .directCandidReflection
                    && plan.nextPrompt?.kind == .openQuestion)
            guard session.condition == .cardMediated,
                  session.cardDisplayState == .displayed,
                  !session.cardWasSetAside,
                  session.cardGuidanceShared,
                  hasGroundedMapping,
                  relationCount > 0,
                  (0..<relationCount).contains(selection.relationIndex),
                  isQuestionOperation else {
                throw ReflectionProtocolViolation.invalidCardReferenceSelection
            }
        }
        if !permission.allowedOperations.isEmpty {
            let selectedOperation = TurnProtocolOperation(
                requestedStage: plan.requestedStage,
                replyIntent: plan.replyIntent,
                localAction: plan.localAction.kind
            )
            guard permission.allowedOperations.contains(selectedOperation) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        if plan.replyIntent == .authorizeCardGuidance {
            // The intent is the typed label for the silent local action, never a standalone
            // conversational turn. Requiring both sides of this pair prevents Writer calls for an
            // authorization that has already happened or was never requested.
            guard plan.localAction.kind == .shareCardGuidance,
                  !session.cardGuidanceShared else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        }
        if [.suggestPractice, .revisePractice].contains(plan.replyIntent),
           plan.memoryUpdate.practiceKind == .noAction,
           plan.noActionReason == nil {
            // Swift does not decide whether the person is ready or whether an active practice is
            // therapeutically appropriate. It only requires the Planner to choose one closed,
            // auditable exception instead of using `noAction` as an unqualified shortcut.
            throw ReflectionProtocolViolation.missingNoActionReason
        }
        if [.suggestPractice, .revisePractice].contains(plan.replyIntent) {
            let options = plan.memoryUpdate.practiceOptions ?? []
            let hasDuplicateIDs = Set(options.map(\.id)).count != options.count
            let hasInvalidOption = options.contains { option in
                option.kind == .noAction
                    || option.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || option.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || option.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || option.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard options.count <= 1, !hasDuplicateIDs, !hasInvalidOption else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            if plan.memoryUpdate.practiceKind == .noAction {
                guard options.isEmpty else {
                    throw ReflectionProtocolViolation.illegalReplyIntent
                }
            } else {
                guard plan.memoryUpdate.practiceKind == nil,
                      plan.memoryUpdate.selectedPractice == nil else {
                    // A pending choice set cannot also claim that one option is already selected.
                    throw ReflectionProtocolViolation.illegalReplyIntent
                }
                if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion {
                    // Current sessions may not fall back to generic wellbeing advice. One active
                    // practice must name the confirmed basis that made it relevant; otherwise the
                    // Planner must use the typed insufficient-material noAction path.
                    guard options.count == 1,
                          options.allSatisfy({ nonempty($0.basis) }) else {
                        throw ReflectionProtocolViolation.missingRequiredMemoryField(
                            .practiceBasis
                        )
                    }
                }
            }
        }
        if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
           session.protocolVersion < ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure,
           [.presentTenderSummary, .inviteCardConsent, .directCandidReflection]
            .contains(plan.replyIntent) {
            try validateCurrentTenderGrounding(plan, for: session)
        }
        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           session.protocolStage == .contextualDisclosure,
           plan.replyIntent != .safetySupport {
            try validateCurrentDisclosurePlan(plan, for: session)
        }
        try validateIntentTransition(plan, currentStage: session.protocolStage)
        try validateInteractionContract(plan, for: session)

        if plan.replyIntent != .safetySupport,
           isFierceQuestion(effectiveCurrentPrompt(for: session)),
           !nonempty(plan.memoryUpdate.candidUnderstanding),
           !nonempty(plan.memoryUpdate.fierceUnderstanding) {
            // The question purpose is protocol metadata chosen by the LLM, not a Swift reading of
            // the person's language. Requiring a replacement here prevents a newly answered,
            // corrected, rejected, or uncertain candid reflection from leaving stale semantic
            // memory behind while the workflow moves on.
            throw ReflectionProtocolViolation.missingRequiredMemoryField(
                .candidUnderstanding
            )
        }

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
           plan.requestedStage != .cardReflection {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        if plan.localAction.kind == .shareCardGuidance,
           plan.replyIntent != .authorizeCardGuidance {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
        if plan.localAction.kind == .shareCardGuidance {
            if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
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
           !(session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion
                && plan.replyIntent == .deepenCardConnection),
           plan.replyIntent != .safetySupport {
            // When the plan itself establishes a reality mapping, the same atomic turn must
            // request the bounded local guidance capability. This prevents an acknowledgement or
            // generic reflection turn from swallowing the card condition's distinctive step.
            throw ReflectionProtocolViolation.illegalLocalAction
        }
        if plan.replyIntent == .presentCardReading {
            guard session.cardGuidanceShared,
                  effectiveCardRealityConnection(for: session) != nil else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
               session.protocolVersion < ReflectionSession.currentProtocolVersion,
               !nonempty(session.semanticMemory.cardInterpretiveTension) {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .cardInterpretiveTension
                )
            }
        }
        if plan.memoryUpdate.contextCueOffered == true {
            guard session.protocolVersion >= ReflectionSession.currentProtocolVersion,
                  session.protocolStage == .cardReflection,
                  plan.replyIntent == .presentCardReading,
                  session.cardGuidanceShared,
                  session.contextualLoadInference?.hasDialogueCue == true,
                  session.contextualLoadInference?.relevance == .notReviewed,
                  effectiveCardRealityConnection(for: session) != nil else {
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

    /// Older internal-Tender sessions retain their typed disclosure-evidence boundary. The
    /// optional Tender wording itself is not a stage credential: its absence cannot reject an
    /// otherwise legal transition.
    private func validateCurrentTenderGrounding(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        if let missing = missingCurrentTenderGroundingField(
            plan.memoryUpdate,
            for: session
        ) {
            if missing == .episodeStructure {
                throw ReflectionProtocolViolation.incompleteEpisodeStructure(
                    missingCurrentEpisodeRequirements(
                        plan.memoryUpdate,
                        for: session
                    )
                )
            }
            throw ReflectionProtocolViolation.missingRequiredMemoryField(missing)
        }
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
            let behaviorHasContent = episode.behaviorEvidence.contains(where: nonempty)
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
            if prompt.disclosureReopenReason == nil,
               effectiveMemory.receivedDisclosureQuestionPurposes.contains(purpose),
               disclosureTargetIsComplete(target, in: disclosureState) {
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
            if isEventDisclosureCoreComplete(disclosureState),
               prompt.disclosureReopenReason == nil {
                throw ReflectionProtocolViolation.disclosureShouldAdvance
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

    /// Returns only a missing legacy disclosure-evidence object. It never reads raw dialogue or
    /// requires a Tender interpretation.
    private func missingCurrentTenderGroundingField(
        _ update: TurnSemanticMemoryUpdate?,
        for session: ReflectionSession
    ) -> TurnRequiredMemoryField? {
        if let missing = missingCurrentDisclosureEvidenceField(update, for: session) {
            return missing
        }
        return nil
    }

    /// Defines only the typed evidence boundary that ends contextual disclosure. Unknowns are
    /// valid resolved statuses; the model must not keep questioning merely because a cause,
    /// feeling, or controllable part remains unknown.
    private func missingCurrentDisclosureEvidenceField(
        _ update: TurnSemanticMemoryUpdate?,
        for session: ReflectionSession
    ) -> TurnRequiredMemoryField? {
        let status = update?.selfCriticismStatus
            ?? session.semanticMemory.selfCriticismStatus
        guard status != .unresolved else { return .selfCriticismStatus }
        if status == .present {
            let statement = update?.selfCriticalStatement
                ?? session.semanticMemory.selfCriticalStatement
            guard nonempty(statement) else { return .selfCriticalStatement }
        }

        let situation = update?.situationUnderstanding
            ?? session.semanticMemory.situationUnderstanding
        if !(session.protocolVersion >= ReflectionSession.currentProtocolVersion
                && status == .present) {
            // Current self-criticism sessions use the typed episode structure below as the
            // canonical reality representation. Requiring a second free-text situation summary
            // duplicates the same evidence and previously caused otherwise complete card bridges
            // to fail. Legacy or no-self-criticism paths still retain their saved contract.
            guard nonempty(situation) else { return .situationUnderstanding }
        }

        if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
           status == .present {
            if !missingCurrentEpisodeRequirements(update, for: session).isEmpty {
                return .episodeStructure
            }
            let link = update?.selfCriticismLink
                ?? session.semanticMemory.selfCriticismLink
            guard nonempty(link) else { return .selfCriticismLink }
        }

        return nil
    }

    private func missingCurrentEpisodeRequirements(
        _ update: TurnSemanticMemoryUpdate?,
        for session: ReflectionSession
    ) -> [TurnEpisodeRequirement] {
        guard let episode = effectiveEpisodeStructure(update, for: session) else {
            return [
                .concreteFact,
                .eventProcessStatus,
                .impactStatus,
            ]
        }
        var missing: [TurnEpisodeRequirement] = []
        if !episode.concreteFacts.contains(where: nonempty) {
            missing.append(.concreteFact)
        }
        // Behavioral evidence is optional reflective material, not a separate disclosure gate.
        // An unresolved classification must never make an already reported focal event appear
        // missing or force the person through another event question. Later candid reflection may
        // use only an explicitly present/mixed status with non-empty evidence.
        if episode.eventProcessStatus == .unresolved {
            missing.append(.eventProcessStatus)
        } else if [.present, .mixed].contains(episode.eventProcessStatus) {
            let hasGroundedEventProcess =
                episode.behaviorEvidence.contains(where: nonempty)
                || episode.possibleContributors.contains(where: nonempty)
                || episode.contextualConstraints.contains(where: nonempty)
                || episode.controllableParts.contains(where: nonempty)
            if !hasGroundedEventProcess {
                missing.append(.eventProcessEvidence)
            }
        } else if episode.eventProcessStatus == .uncertain,
                  !nonempty(episode.keyUncertainty) {
            missing.append(.eventProcessUncertainty)
        }
        if episode.impactStatus == .unresolved {
            missing.append(.impactStatus)
        } else if [.present, .mixed].contains(episode.impactStatus),
                  !episode.impacts.contains(where: nonempty) {
            missing.append(.impactEvidence)
        }
        return missing
    }

    /// Planner episode updates are field-level patches. Validate the cumulative structure that
    /// would exist after commit, rather than letting omitted nested keys reset prior facts to
    /// Codable defaults during this turn.
    private func effectiveEpisodeStructure(
        _ update: TurnSemanticMemoryUpdate?,
        for session: ReflectionSession
    ) -> TurnEpisodeStructure? {
        guard let patch = update?.episodeStructure else {
            return session.semanticMemory.episodeStructure
        }
        return session.semanticMemory.episodeStructure?.merging(patch) ?? patch
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
            guard nextPrompt.purpose == nil,
                  nextPrompt.focus == nil,
                  nextPrompt.disclosurePurpose == nil,
                  nextPrompt.disclosureTarget == nil,
                  nextPrompt.disclosureReopenReason == nil,
                  nextPrompt.target != nil,
                  nextPrompt.referenceID == nil else {
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

        case .integrateTrackingAndPresentTenderSummary:
            try requireResolution(
                .trackingRelationship,
                decisions: [.related, .partlyRelated, .unrelated, .uncertain]
            )
            try requireNextConfirmation(.tenderSummary)

        case .presentTenderSummary, .reviseTenderSummary:
            try requireNextConfirmation(.tenderSummary)

        case .requestTenderConfirmation:
            try requireNextConfirmation(.tenderSummary)

        case .inviteCardConsent:
            if session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
               session.protocolStage == .contextualDisclosure {
                guard plan.resolvedConfirmation == nil else {
                    throw ReflectionProtocolViolation.invalidConfirmationResolution
                }
            } else {
                try requireResolution(
                    .tenderSummary,
                    decisions: [.accepted, .revised]
                )
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

        case .suggestPractice:
            try requireResolution(.finalNarrative, decisions: [.accepted, .revised])
            try requireNextConfirmation(.practice)

        case .revisePractice:
            try requireResolution(.practice, decisions: [.revised, .rejected, .unclear])
            try requireNextConfirmation(.practice)

        case .completeConversation:
            guard nextPrompt.kind == .none else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }
            switch session.protocolStage {
            case .narrativeConfirmation:
                guard currentPrompt?.target == .finalNarrative,
                      nonempty(session.semanticMemory.finalNarrative) else {
                    throw ReflectionProtocolViolation.invalidConfirmationResolution
                }
                try requireResolution(
                    .finalNarrative,
                    decisions: [.accepted, .revised]
                )
            case .optionalAction:
                guard currentPrompt?.target == .practice else {
                    throw ReflectionProtocolViolation.invalidConfirmationResolution
                }
                try requireResolution(
                    .practice,
                    decisions: [.accepted, .revised, .declined, .rejected]
                )
                if let decision = plan.resolvedConfirmation?.decision,
                   [TurnConfirmationDecision.accepted, .revised].contains(decision) {
                    let selected = plan.memoryUpdate.selectedPractice
                        ?? session.semanticMemory.selectedPractice
                    guard nonempty(selected) else {
                        throw ReflectionProtocolViolation.illegalReplyIntent
                    }
                    if decision == .accepted,
                       !session.semanticMemory.practiceOptions.isEmpty {
                        guard session.semanticMemory.practiceOptions.contains(where: {
                            $0.instruction == selected
                        }) else {
                            throw ReflectionProtocolViolation.illegalReplyIntent
                        }
                    }
                }
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
                case .tenderSummary, .cardMapping:
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
            guard session.protocolVersion >= ReflectionSession.internalTenderProtocolVersion,
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
            guard nextPrompt.kind == .none else {
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
        case .tenderSummary, .cardRealityConnection, .cardMapping, .finalNarrative:
            return [.accepted, .revised, .rejected, .unclear]
        case .practice:
            return [.accepted, .revised, .rejected, .unclear, .declined]
        }
    }

    private func nonempty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func isFierceQuestion(_ prompt: TurnNextPrompt?) -> Bool {
        guard prompt?.kind == .openQuestion,
              let purpose = prompt?.purpose?.lowercased() else {
            return false
        }
        return purpose.hasPrefix("fierce_")
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
            allowed = [.exploreContext, .presentTrackingContext, .checkTrackingRelationship]
        case (.contextualDisclosure, .tenderConfirmation):
            allowed = [.presentTenderSummary, .integrateTrackingAndPresentTenderSummary]
        case (.contextualDisclosure, .cardConsent):
            allowed = [.inviteCardConsent]
        case (.contextualDisclosure, .directReflection):
            allowed = [.directCandidReflection]

        case (.tenderConfirmation, .contextualDisclosure):
            allowed = [.exploreContext]
        case (.tenderConfirmation, .tenderConfirmation):
            allowed = [.requestTenderConfirmation, .reviseTenderSummary]
        case (.tenderConfirmation, .cardConsent):
            allowed = [.inviteCardConsent]
        case (.tenderConfirmation, .directReflection):
            allowed = [.directCandidReflection]

        case (.cardConsent, .cardConsent):
            allowed = [.inviteCardConsent, .acknowledgeCardConsent]
        case (.cardConsent, .tenderConfirmation):
            allowed = [.reviseTenderSummary]
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
            allowed = [.acknowledgeCardDecline, .directCandidReflection]
        case (.directReflection, .directReflection):
            allowed = [.directCandidReflection]
        case (.directReflection, .narrativeConfirmation):
            allowed = [.presentFinalNarrative]

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
            allowed = [.reviseFinalNarrative]
        case (.optionalAction, .complete):
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
                .presentTrackingContext,
                .checkTrackingRelationship,
                .integrateTrackingAndPresentTenderSummary,
                .presentTenderSummary,
                .inviteCardConsent,
                .directCandidReflection,
                .safetySupport,
            ]
        case .tenderConfirmation:
            return [
                .exploreContext,
                .requestTenderConfirmation,
                .reviseTenderSummary,
                .inviteCardConsent,
                .directCandidReflection,
                .safetySupport,
            ]
        case .cardConsent:
            return [
                .inviteCardConsent,
                .acknowledgeCardConsent,
                .acknowledgeCardDecline,
                .reviseTenderSummary,
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
                .safetySupport,
            ]
        case .narrativeConfirmation:
            return [
                .requestNarrativeConfirmation,
                .reviseFinalNarrative,
                .presentCardReading,
                .directCandidReflection,
                .suggestPractice,
                .safetySupport,
            ]
        case .optionalAction:
            return [
                .suggestPractice,
                .revisePractice,
                .reviseFinalNarrative,
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
            values = condition.usesCard
                ? [.contextualDisclosure, .tenderConfirmation, .cardConsent]
                : [.contextualDisclosure, .tenderConfirmation, .directReflection]
        case .tenderConfirmation:
            values = condition.usesCard
                ? [.contextualDisclosure, .tenderConfirmation, .cardConsent]
                : [.contextualDisclosure, .tenderConfirmation, .directReflection]
        case .cardConsent:
            values = [.cardConsent, .tenderConfirmation, .directReflection]
        case .cardReflection:
            values = [.cardReflection, .directReflection]
        case .directReflection:
            values = [.directReflection, .narrativeConfirmation]
        case .narrativeConfirmation:
            values = condition.usesCard
                ? [.cardReflection, .narrativeConfirmation, .optionalAction]
                : [.directReflection, .narrativeConfirmation, .optionalAction]
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
