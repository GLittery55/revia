import Foundation

struct ReflectionProtocolPermissions: Codable, Equatable, Sendable {
    let currentStage: ReflectionProtocolStage
    let allowedStages: [ReflectionProtocolStage]
    let allowedActions: [TurnLocalActionKind]
    let allowedReplyIntents: [TurnReplyIntent]
}

enum ReflectionProtocolViolation: Error, Equatable {
    case emptyReply
    case illegalStageTransition
    case illegalLocalAction
    case illegalReplyIntent
    case missingRequiredMemoryField(TurnRequiredMemoryField)
    case writerIntentMismatch
    case unknownTrackingCue
    case duplicateTrackingCue
    case trackingReviewRequired
    case missingNoActionReason
    case conflictingMemoryPatch
    case invalidNextPrompt
    case invalidConfirmationResolution
    case unknownConfirmationReference
}

enum TurnRequiredMemoryField: String, Equatable, Sendable {
    case tenderUnderstanding
    case cardNegotiatedMeaning
    case candidUnderstanding
    /// Legacy repair code retained for older persisted requests.
    case fierceUnderstanding
    case finalNarrative
    case practiceKind
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
    case redundantLegacyInteractionFieldsIgnored
    case normalizedNextPromptMetadata
}

/// This controller knows study protocol, not conversation meaning. In particular, it never
/// decides whether the person has expressed enough emotion, accepted an interpretation, or has
/// sufficient evidence for responsibility. Those are LLM TurnController decisions.
struct ReflectionProtocolController: Sendable {
    func permissions(for session: ReflectionSession) -> ReflectionProtocolPermissions {
        let stages = allowedStages(
            from: session.protocolStage,
            condition: session.condition
        )
        var actions: [TurnLocalActionKind] = [.none]
        var replyIntents = allowedReplyIntents(from: session.protocolStage)

        switch session.protocolStage {
        case .contextualDisclosure:
            // Context is supplied as one measurement-free hypothesis inside ordinary reflection;
            // it no longer creates a separate local presentation or confirmation action.
            break
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
            if session.cardConnectionUnavailable {
                replyIntents = replyIntents.filter {
                    [.directCandidReflection, .safetySupport].contains($0)
                }
            } else {
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
               !session.cardConnectionUnavailable {
                actions.append(.shareCardGuidance)
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
                } else if nonempty(session.semanticMemory.cardRealityMapping),
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
            let currentPrompt = effectiveCurrentPrompt(for: session)
            let isAnsweringFierceQuestion =
                currentPrompt?.kind == .openQuestion &&
                currentPrompt?.purpose?.hasPrefix("fierce_") == true
            if session.reflectionReadiness == .narrativeReady || isAnsweringFierceQuestion {
                // A Fierce function has a one-question budget. Once that visible question is
                // pending, the next semantic turn may preserve the person's answer (including
                // refusal or uncertainty) in the final narrative, but it may not open another
                // Fierce synonym. Narrative readiness applies the same forward-only lock after a
                // formatting failure. Swift is enforcing turn budget and progression here, not
                // deciding whether the person's answer is semantically “good enough”.
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
            allowedReplyIntents: replyIntents.sorted { $0.rawValue < $1.rawValue }
        )
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

    /// Returns non-blocking wording concerns. These are used to ask the Writer—not the
    /// Planner—to polish the same validated turn. Swift does not rewrite, delete, or invent a
    /// question, and a remaining punctuation mismatch does not invalidate the workflow.
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

        if originalPlan.nextPrompt != nil,
           originalPlan.memoryUpdate.pendingQuestionPurpose != nil
            || originalPlan.memoryUpdate.pendingConfirmationTarget != nil
            || originalPlan.memoryUpdate.clearPendingQuestionPurpose != nil {
            warnings.append(.redundantLegacyInteractionFieldsIgnored)
        }
        if originalPlan.nextPrompt != validatedPlan.nextPrompt {
            warnings.append(.normalizedNextPromptMetadata)
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

        // `nextPrompt` is the sole source of truth for new responses. Models sometimes echo the
        // equivalent legacy pending fields as well. Ignoring those redundant metadata fields is
        // safe and prevents a formatting imperfection from interrupting the person; an actual
        // unresolved confirmation, its reference, and every stage/action boundary are still
        // validated below.
        if protocolPlan.nextPrompt != nil {
            memoryUpdate.pendingQuestionPurpose = nil
            memoryUpdate.pendingConfirmationTarget = nil
            memoryUpdate.clearPendingQuestionPurpose = nil
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
            memoryUpdate.cardNegotiatedMeaning = ""
        }

        var localAction = protocolPlan.localAction
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
                            : "continue_current_conversation"
                    )
                case .confirmationRequest:
                    if let target = prompt.target {
                        nextPrompt = .confirmationRequest(target: target)
                    }
                }
            }
        }
        if resolvesCardMapping || resolvesTenderIntoDirectReflection {
            // Confirmation resolution and the next dialogue generation are separate atomic
            // transactions. Discard any question drafted into this transition; a fresh
            // directReflection turn may ask one supported question or move directly to narrative.
            nextPrompt = TurnNextPrompt.none
        }

        return LLMTurnResponsePlan(
            requestedStage: requestedStage,
            localAction: localAction,
            memoryUpdate: memoryUpdate,
            resolvedConfirmation: protocolPlan.resolvedConfirmation,
            nextPrompt: nextPrompt,
            replyIntent: protocolPlan.replyIntent,
            noActionReason: memoryUpdate.practiceKind == .noAction
                ? protocolPlan.noActionReason
                : nil,
            replyGuidance: protocolPlan.replyGuidance
        )
    }

    /// Releasing card guidance is a local capability operation; presenting a negotiated reading is
    /// a later visible dialogue operation. A model may reasonably request both in one semantic
    /// plan. Split that combined request into the existing silent authorization pass, after which
    /// the TurnController receives the real guidance and creates one fresh visible reading.
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
            replyGuidance: "Authorize the bounded local card guidance, then generate the visible reading in a fresh guidance-aware turn."
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
        guard !plan.replyGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReflectionProtocolViolation.emptyReply
        }
        let permission = permissions(for: session)
        guard permission.allowedStages.contains(plan.requestedStage) else {
            throw ReflectionProtocolViolation.illegalStageTransition
        }
        guard permission.allowedActions.contains(plan.localAction.kind) else {
            throw ReflectionProtocolViolation.illegalLocalAction
        }
        guard permission.allowedReplyIntents.contains(plan.replyIntent) else {
            throw ReflectionProtocolViolation.illegalReplyIntent
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
                // Missing structured options are recoverable metadata, not a capability or stage
                // violation. The visible Writer reply may still contain one grounded practice;
                // keep the conversation flowing and record `missingPracticeOptions` as a soft
                // warning. Invalid, duplicate, or excessive supplied options remain hard errors.
            }
        }
        try validateIntentTransition(plan, currentStage: session.protocolStage)
        let usesNewInteractionContract =
            plan.nextPrompt != nil || plan.resolvedConfirmation != nil
        if usesNewInteractionContract {
            try validateInteractionContract(plan, for: session)
        } else {
            try validateConfirmationContract(plan, for: session)
        }
        if !usesNewInteractionContract,
           plan.memoryUpdate.clearPendingQuestionPurpose == true {
            let replacesPurpose = plan.memoryUpdate.pendingQuestionPurpose != nil
            let replacesTarget = plan.memoryUpdate.pendingConfirmationTarget != nil
            // `clear + neither` is an ordinary clear. `clear + both` is an atomic replacement of
            // one confirmation gate by another. A partial replacement would leave a yes/no reply
            // attached to the wrong semantic target and is therefore rejected.
            if replacesPurpose != replacesTarget {
                throw ReflectionProtocolViolation.conflictingMemoryPatch
            }
        }

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
            if usesNewInteractionContract,
               let activeID = session.activeTrackingPresentationID,
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
            let imageRelation = plan.memoryUpdate.cardImageRelation
                ?? session.semanticMemory.cardImageRelation
            let realityMapping = plan.memoryUpdate.cardRealityMapping
                ?? session.semanticMemory.cardRealityMapping
            guard imageRelation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  realityMapping?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ReflectionProtocolViolation.illegalLocalAction
            }
        }
        if session.protocolStage == .cardReflection,
           !session.cardGuidanceShared,
           nonempty(plan.memoryUpdate.cardRealityMapping),
           plan.localAction.kind != .shareCardGuidance,
           plan.replyIntent != .safetySupport {
            // When the plan itself establishes a reality mapping, the same atomic turn must
            // request the bounded local guidance capability. This prevents an acknowledgement or
            // generic reflection turn from swallowing the card condition's distinctive step.
            throw ReflectionProtocolViolation.illegalLocalAction
        }
        if plan.replyIntent == .presentCardReading {
            guard session.cardGuidanceShared,
                  nonempty(session.semanticMemory.cardImageRelation),
                  nonempty(session.semanticMemory.cardRealityMapping) else {
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

    private func validateInteractionContract(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        // New responses have one source of truth for pending interaction. Legacy patch fields are
        // accepted only on the legacy path so two representations can never disagree. An
        // explicit `false` clear flag is a harmless no-op and is normalized like null; only
        // `true` would mutate the legacy representation.
        guard plan.memoryUpdate.pendingQuestionPurpose == nil,
              plan.memoryUpdate.pendingConfirmationTarget == nil,
              plan.memoryUpdate.clearPendingQuestionPurpose != true,
              let nextPrompt = plan.nextPrompt else {
            throw ReflectionProtocolViolation.conflictingMemoryPatch
        }

        switch nextPrompt.kind {
        case .none:
            guard nextPrompt.purpose == nil,
                  nextPrompt.focus == nil,
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
                  nextPrompt.target != nil,
                  nextPrompt.referenceID == nil else {
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
            guard nonempty(plan.memoryUpdate.tenderUnderstanding) else {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .tenderUnderstanding
                )
            }

        case .presentTenderSummary, .requestTenderConfirmation, .reviseTenderSummary:
            try requireNextConfirmation(.tenderSummary)
            guard nonempty(plan.memoryUpdate.tenderUnderstanding) else {
                throw ReflectionProtocolViolation.missingRequiredMemoryField(
                    .tenderUnderstanding
                )
            }

        case .inviteCardConsent:
            try requireResolution(
                .tenderSummary,
                decisions: [.accepted, .revised]
            )
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
                }
            }
            guard [.openQuestion, .none].contains(nextPrompt.kind) else {
                throw ReflectionProtocolViolation.invalidNextPrompt
            }

        case .exploreContext, .inviteCardObservation, .developCardImage,
             .inviteCardConnection:
            // The LLM owns whether this ordinary semantic turn is best expressed as a direct
            // question or as a brief invitation that leaves the floor open. Swift checks only
            // that it does not create an unrelated confirmation object.
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
        if let prompt = session.semanticMemory.nextPrompt {
            return prompt.kind == .none ? nil : prompt
        }
        if let target = session.semanticMemory.pendingConfirmationTarget {
            return .confirmationRequest(target: target)
        }
        if let purpose = session.semanticMemory.pendingQuestionPurpose,
           !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .openQuestion(purpose: purpose, focus: purpose)
        }
        return nil
    }

    private func allowedDecisions(
        for target: TurnConfirmationTarget
    ) -> Set<TurnConfirmationDecision> {
        switch target {
        case .trackingRelationship:
            return [.related, .partlyRelated, .unrelated, .uncertain]
        case .cardConsent:
            return [.accepted, .declined, .unclear]
        case .tenderSummary, .cardMapping, .finalNarrative:
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

    private func validateConfirmationContract(
        _ plan: LLMTurnResponsePlan,
        for session: ReflectionSession
    ) throws {
        func nonempty(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        switch plan.replyIntent {
        case .presentTrackingContext:
            guard plan.memoryUpdate.pendingConfirmationTarget == .trackingRelationship,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .checkTrackingRelationship:
            guard session.semanticMemory.pendingConfirmationTarget == .trackingRelationship,
                  plan.memoryUpdate.clearPendingQuestionPurpose == true,
                  plan.memoryUpdate.trackingAssessments?.isEmpty == false else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .integrateTrackingAndPresentTenderSummary:
            guard session.semanticMemory.pendingConfirmationTarget == .trackingRelationship,
                  plan.memoryUpdate.trackingAssessments?.isEmpty == false,
                  plan.memoryUpdate.pendingConfirmationTarget == .tenderSummary,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose),
                  nonempty(plan.memoryUpdate.tenderUnderstanding) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .presentTenderSummary, .requestTenderConfirmation, .reviseTenderSummary:
            guard plan.memoryUpdate.pendingConfirmationTarget == .tenderSummary,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose),
                  nonempty(plan.memoryUpdate.tenderUnderstanding)
                    || nonempty(session.semanticMemory.tenderUnderstanding) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            if plan.replyIntent == .presentTenderSummary,
               session.semanticMemory.pendingConfirmationTarget == .trackingRelationship,
               plan.memoryUpdate.trackingAssessments?.isEmpty != false {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .inviteCardConsent:
            guard session.semanticMemory.pendingConfirmationTarget == .tenderSummary,
                  plan.memoryUpdate.clearPendingQuestionPurpose == true else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .directCandidReflection
            where session.protocolStage == .tenderConfirmation:
            guard session.semanticMemory.pendingConfirmationTarget == .tenderSummary,
                  plan.memoryUpdate.clearPendingQuestionPurpose == true else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .presentCardReading:
            guard plan.memoryUpdate.pendingConfirmationTarget == .cardMapping,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose),
                  nonempty(plan.memoryUpdate.cardNegotiatedMeaning) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .presentFinalNarrative, .requestNarrativeConfirmation, .reviseFinalNarrative:
            guard plan.memoryUpdate.pendingConfirmationTarget == .finalNarrative,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose),
                  nonempty(plan.memoryUpdate.finalNarrative)
                    || nonempty(session.semanticMemory.finalNarrative) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .suggestPractice, .revisePractice:
            guard plan.memoryUpdate.pendingConfirmationTarget == .practice,
                  nonempty(plan.memoryUpdate.pendingQuestionPurpose) else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
        case .completeConversation:
            if session.protocolStage == .narrativeConfirmation {
                guard session.semanticMemory.pendingConfirmationTarget == .finalNarrative,
                      plan.memoryUpdate.clearPendingQuestionPurpose == true else {
                    throw ReflectionProtocolViolation.illegalReplyIntent
                }
            } else if session.protocolStage == .optionalAction {
                guard session.semanticMemory.pendingConfirmationTarget == .practice,
                      plan.memoryUpdate.clearPendingQuestionPurpose == true else {
                    throw ReflectionProtocolViolation.illegalReplyIntent
                }
            }
        default:
            break
        }
    }

    private func validateIntentTransition(
        _ plan: LLMTurnResponsePlan,
        currentStage: ReflectionProtocolStage
    ) throws {
        if plan.requestedStage == .safetySupport {
            guard plan.replyIntent == .safetySupport else {
                throw ReflectionProtocolViolation.illegalReplyIntent
            }
            return
        }

        let allowed: Set<TurnReplyIntent>
        switch (currentStage, plan.requestedStage) {
        case (.contextualDisclosure, .contextualDisclosure):
            allowed = [.exploreContext, .presentTrackingContext, .checkTrackingRelationship]
        case (.contextualDisclosure, .tenderConfirmation):
            allowed = [.presentTenderSummary, .integrateTrackingAndPresentTenderSummary]

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
            throw ReflectionProtocolViolation.illegalStageTransition
        }

        guard allowed.contains(plan.replyIntent) else {
            throw ReflectionProtocolViolation.illegalReplyIntent
        }
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
            values = [.contextualDisclosure, .tenderConfirmation]
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
