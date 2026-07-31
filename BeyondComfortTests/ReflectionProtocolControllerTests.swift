import XCTest
@testable import BeyondComfort

final class ReflectionProtocolControllerTests: XCTestCase {
    private let controller = ReflectionProtocolController()

    func testLegacyPayloadKeepsLegacyProtocolAndVersionTwoRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            ReflectionSession.self,
            from: Data(#"{"stage":"emotionDisclosure"}"#.utf8)
        )
        XCTAssertEqual(legacy.protocolVersion, 1)
        XCTAssertFalse(legacy.usesLLMTurnController)
        XCTAssertEqual(legacy.protocolStage, .contextualDisclosure)
        XCTAssertNil(legacy.semanticMemory.nextPrompt)
        XCTAssertTrue(legacy.trackingPresentations.isEmpty)
        XCTAssertNil(legacy.activeTrackingPresentationID)
        XCTAssertNil(legacy.contextualLoadInference)
        XCTAssertFalse(legacy.cardConnectionScaffoldUsed)

        var current = ReflectionSession()
        current.protocolVersion = 2
        current.protocolStage = .directReflection
        current.semanticMemory.situationUnderstanding = "已形成一段可修正的处境理解"
        current.cardConnectionAttemptCount = 1
        current.cardConnectionScaffoldUsed = true
        current.contextualLoadInference = ContextualLoadInference(
            state: .possiblyElevated,
            confidence: .moderate,
            activation: .possiblyElevated,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: "用户近期可能承受着比平时更多的压力。",
            relevance: .notReviewed
        )

        let decoded = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(current)
        )
        XCTAssertEqual(decoded.protocolVersion, 2)
        XCTAssertTrue(decoded.usesLLMTurnController)
        XCTAssertEqual(decoded.protocolStage, .directReflection)
        XCTAssertEqual(
            decoded.semanticMemory.situationUnderstanding,
            "已形成一段可修正的处境理解"
        )
        XCTAssertEqual(decoded.cardConnectionAttemptCount, 1)
        XCTAssertTrue(decoded.cardConnectionScaffoldUsed)
        XCTAssertEqual(decoded.contextualLoadInference?.state, .possiblyElevated)
        XCTAssertEqual(decoded.contextualLoadInference?.energy, .possiblyReduced)
    }

    func testContextualDisclosureDoesNotExposeASeparateTrackingAction() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let first = trackingCue(id: "sleep")
        let second = trackingCue(id: "steps")
        session.trackingCues = [first, second]

        let permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedActions.contains(.presentTrackingCue))

        let separatePresentation = plan(
            stage: .contextualDisclosure,
            intent: .presentTrackingContext,
            action: .init(
                kind: .presentTrackingCue,
                trackingCueIDs: [first.id, second.id]
            )
        )
        XCTAssertThrowsError(try controller.validate(separatePresentation, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .illegalLocalAction
            )
        }
    }

    func testConditionControlsPostTenderStageWithoutSemanticFieldChecks() throws {
        var cardSession = protocolSession(stage: .tenderConfirmation)
        cardSession.condition = .cardMediated
        cardSession.semanticMemory.pendingConfirmationTarget = .tenderSummary
        XCTAssertNoThrow(
            try controller.validate(
                plan(
                    stage: .cardConsent,
                    intent: .inviteCardConsent,
                    memory: .init(clearPendingQuestionPurpose: true)
                ),
                for: cardSession
            )
        )
        XCTAssertThrowsError(
            try controller.validate(
                plan(stage: .directReflection, intent: .directCandidReflection),
                for: cardSession
            )
        )

        var directSession = protocolSession(stage: .tenderConfirmation)
        directSession.condition = .directLLM
        directSession.semanticMemory.pendingConfirmationTarget = .tenderSummary
        XCTAssertNoThrow(
            try controller.validate(
                plan(
                    stage: .directReflection,
                    intent: .directCandidReflection,
                    memory: .init(clearPendingQuestionPurpose: true)
                ),
                for: directSession
            )
        )
        XCTAssertThrowsError(
            try controller.validate(
                plan(stage: .cardConsent, intent: .inviteCardConsent),
                for: directSession
            )
        )
    }

    func testTenderConfirmationPermissionsMatchAssignedCondition() {
        var cardSession = protocolSession(stage: .tenderConfirmation)
        cardSession.condition = .cardMediated

        let cardPermissions = controller.permissions(for: cardSession)

        XCTAssertTrue(cardPermissions.allowedStages.contains(.cardConsent))
        XCTAssertFalse(cardPermissions.allowedStages.contains(.directReflection))
        XCTAssertTrue(cardPermissions.allowedReplyIntents.contains(.inviteCardConsent))
        XCTAssertFalse(
            cardPermissions.allowedReplyIntents.contains(.directCandidReflection)
        )

        var directSession = protocolSession(stage: .tenderConfirmation)
        directSession.condition = .directLLM

        let directPermissions = controller.permissions(for: directSession)

        XCTAssertTrue(directPermissions.allowedStages.contains(.directReflection))
        XCTAssertFalse(directPermissions.allowedStages.contains(.cardConsent))
        XCTAssertTrue(
            directPermissions.allowedReplyIntents.contains(.directCandidReflection)
        )
        XCTAssertFalse(directPermissions.allowedReplyIntents.contains(.inviteCardConsent))
    }

    func testNewInteractionContractSeparatesResolvedConfirmationFromNextPrompt() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let cue = trackingCue(id: "sleep")
        let batch = TurnTrackingPresentation(
            id: "batch-1",
            cueIDs: [cue.id],
            presentedAtUserTurnID: UUID()
        )
        session.trackingCues = [cue]
        session.presentedTrackingCueIDs = [cue.id]
        session.trackingPresentations = [batch]
        session.activeTrackingPresentationID = batch.id
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .trackingRelationship,
            referenceID: batch.id
        )

        let valid = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding: "最近休息不足可能增加了应对困难，但不决定原因或责任"
            ),
            resolvedConfirmation: .init(
                target: .trackingRelationship,
                decision: .partlyRelated,
                referenceID: batch.id
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .integrateTrackingAndPresentTenderSummary,
            replyGuidance: "整合已经确认的生活背景并请求核对 Tender 理解"
        )
        XCTAssertNoThrow(try controller.validate(valid, for: session))

        let wrongReference = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding: "仍是一段暂定理解"
            ),
            resolvedConfirmation: .init(
                target: .trackingRelationship,
                decision: .related,
                referenceID: "another-batch"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .integrateTrackingAndPresentTenderSummary,
            replyGuidance: "错误引用不应通过"
        )
        XCTAssertThrowsError(try controller.validate(wrongReference, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .unknownConfirmationReference
            )
        }
    }

    func testNewOpenQuestionDoesNotRequireOrCreateConfirmationTarget() throws {
        let session = protocolSession(stage: .contextualDisclosure)
        let valid = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "用户已经描述了事件，仍在说明其现实影响"
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify_concrete_impact",
                focus: "这件事目前怎样影响日常状态"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接当前回答，只问一个与现实影响有关的开放问题"
        )
        XCTAssertNoThrow(try controller.validate(valid, for: session))

        let harmlessLegacyNoOp = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(clearPendingQuestionPurpose: false),
            nextPrompt: .openQuestion(
                purpose: "continue_user_led_understanding",
                focus: "由LLM决定的下一语义焦点"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "保持相同语义计划；false不构成旧状态写入"
        )
        XCTAssertNoThrow(
            try controller.validate(harmlessLegacyNoOp, for: session)
        )

        let llmLedInvitationWithoutForcedQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .exploreContext,
            replyGuidance: "承接用户刚才的表达并自然地把说话空间留给用户"
        )
        XCTAssertNoThrow(
            try controller.validate(
                llmLedInvitationWithoutForcedQuestion,
                for: session
            )
        )

        let invalid = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: TurnNextPrompt(
                kind: .openQuestion,
                purpose: "clarify_concrete_impact",
                focus: "现实影响",
                target: .tenderSummary,
                referenceID: nil
            ),
            replyIntent: .exploreContext,
            replyGuidance: "结构冲突"
        )
        let normalized = try controller.validate(invalid, for: session)
        XCTAssertNil(normalized.nextPrompt?.target)
        XCTAssertEqual(normalized.nextPrompt?.purpose, "clarify_concrete_impact")
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: invalid,
                validatedPlan: normalized,
                for: session
            ),
            [.normalizedNextPromptMetadata]
        )
    }

    func testTypedObjectPresentationsCanonicalizeEquivalentOpenQuestions() throws {
        let tenderSession = protocolSession(stage: .contextualDisclosure)
        let tenderPlan = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding: "这次具体行为和对整个人的否定需要分开理解"
            ),
            nextPrompt: .openQuestion(
                purpose: "check_tender_summary",
                focus: "这段暂定理解是否贴近"
            ),
            replyIntent: .presentTenderSummary,
            replyGuidance: "呈现一段可修改的Tender理解，并邀请用户核对"
        )
        let normalizedTender = try controller.validate(
            tenderPlan,
            for: tenderSession
        )
        XCTAssertEqual(normalizedTender.nextPrompt?.target, .tenderSummary)

        var consentSession = protocolSession(stage: .tenderConfirmation)
        consentSession.condition = .cardMediated
        consentSession.semanticMemory.nextPrompt = .confirmationRequest(
            target: .tenderSummary,
            referenceID: "tender-1"
        )
        let consentPlan = LLMTurnResponsePlan(
            // This matches the production failure: the typed intent is unambiguous, but the
            // model repeats the old stage and says `none` in the redundant prompt label.
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .tenderSummary,
                decision: .accepted,
                referenceID: "tender-1"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .inviteCardConsent,
            replyGuidance: "说明随机性后自然邀请用户决定是否抽卡"
        )
        let normalizedConsent = try controller.validate(
            consentPlan,
            for: consentSession
        )
        XCTAssertEqual(normalizedConsent.requestedStage, .cardConsent)
        XCTAssertEqual(
            normalizedConsent.nextPrompt?.kind,
            .confirmationRequest
        )
        XCTAssertEqual(normalizedConsent.nextPrompt?.target, .cardConsent)

        var cardSession = protocolSession(stage: .cardReflection)
        cardSession.condition = .cardMediated
        cardSession.cardGuidanceShared = true
        cardSession.semanticMemory.cardImageRelation = "用户已经形成的画面关系"
        cardSession.semanticMemory.cardRealityMapping = "用户已经形成的现实映射"
        let cardPlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardNegotiatedMeaning: "一段由用户画面关系和现实关系共同形成的候选映射"
            ),
            nextPrompt: .openQuestion(
                purpose: "check_card_mapping",
                focus: "候选卡牌映射是否贴近"
            ),
            replyIntent: .presentCardReading,
            replyGuidance: "呈现可修改、可拒绝的协商式卡牌解读"
        )
        let normalizedCard = try controller.validate(cardPlan, for: cardSession)
        XCTAssertEqual(normalizedCard.nextPrompt?.target, .cardMapping)

        let directSession = protocolSession(stage: .directReflection)
        let narrativePlan = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                finalNarrative: "一段根据已确认材料自然重写的最终叙事"
            ),
            nextPrompt: .openQuestion(
                purpose: "check_final_narrative",
                focus: "最终叙事是否需要修改"
            ),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "呈现最终叙事并邀请用户修正"
        )
        let normalizedNarrative = try controller.validate(
            narrativePlan,
            for: directSession
        )
        XCTAssertEqual(normalizedNarrative.nextPrompt?.target, .finalNarrative)

        var practiceSession = protocolSession(stage: .narrativeConfirmation)
        practiceSession.semanticMemory.finalNarrative = "已确认前等待处理的最终叙事"
        practiceSession.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        let practicePlan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                practiceOptions: protocolPracticeOptions()
            ),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .openQuestion(
                purpose: "check_practice",
                focus: "建议的低负担实践是否适合"
            ),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个可接受、修改或拒绝的具体实践"
        )
        let normalizedPractice = try controller.validate(
            practicePlan,
            for: practiceSession
        )
        XCTAssertEqual(normalizedPractice.nextPrompt?.target, .practice)
    }

    func testNewContractCannotSilentlyOverwriteUnresolvedConfirmation() throws {
        var session = protocolSession(stage: .tenderConfirmation)
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .tenderSummary,
            referenceID: "tender-1"
        )

        let invalid = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "clarify_revision",
                focus: "用户想修正的部分"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "不能不处理旧确认就覆盖"
        )
        XCTAssertThrowsError(try controller.validate(invalid, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidConfirmationResolution
            )
        }
    }

    func testUsableContextDoesNotBlockTenderSummaryForASeparateQuestion() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let cue = protocolTrackingCue(id: "sleep-before-tender")
        session.trackingCues = [cue]
        session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [cue.insight!.id],
            supportingMetrics: [.sleepDuration],
            alternativeExplanations: [],
            dialogueHypothesis: "用户近期可能还没有充分恢复。",
            relevance: .notReviewed
        )
        let summary = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding: "一段包含不确定情境背景、但不要求单独确认的理解"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "呈现 Tender 理解"
        )

        XCTAssertNoThrow(try controller.validate(summary, for: session))
        XCTAssertTrue(session.presentedTrackingCueIDs.isEmpty)
    }

    func testWriterQuestionCountIsSoftQualityAndDoesNotRejectALegalTurn() throws {
        let openPlan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "clarify_effect",
                focus: "当前影响"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只问一个问题"
        )
        XCTAssertNoThrow(
            try controller.validate(
                .init(
                    realizedIntent: .exploreContext,
                    reply: "这件事现在最明显影响了什么？"
                ),
                for: openPlan
            )
        )
        let missingQuestion = LLMTurnWriterResponse(
            realizedIntent: .exploreContext,
            reply: "我会继续听你说。"
        )
        XCTAssertNoThrow(try controller.validate(missingQuestion, for: openPlan))
        XCTAssertEqual(
            controller.writerQualityIssues(missingQuestion, for: openPlan),
            [.expectedSingleQuestion]
        )

        let noPromptPlan = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .init(kind: .drawRandomCard),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardConsent,
                decision: .accepted,
                referenceID: "card-consent"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .acknowledgeCardConsent,
            replyGuidance: "简短确认即将抽卡"
        )
        let extraQuestion = LLMTurnWriterResponse(
            realizedIntent: .acknowledgeCardConsent,
            reply: "好，我们现在抽一张卡，可以吗？"
        )
        XCTAssertNoThrow(try controller.validate(extraQuestion, for: noPromptPlan))
        XCTAssertEqual(
            controller.writerQualityIssues(extraQuestion, for: noPromptPlan),
            [.expectedNoQuestion]
        )
    }

    func testPracticeOfferWithoutStructuredOptionsIsARecoverableWarning() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经由用户确认前等待处理的叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["narrative_confirmed"]
            ),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个具体、可修改或拒绝的小实践"
        )

        let validated = try controller.validate(plan, for: session)
        XCTAssertEqual(validated.requestedStage, .optionalAction)
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ),
            [.missingPracticeOptions]
        )
    }

    func testStructuredPracticeIsPersistedWithoutPreselectingIt() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经等待确认的最终叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-choices"
        )
        let options = protocolPracticeOptions()
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                practiceOptions: options
            ),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-choices"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            replyGuidance: "呈现一个证据最充分的完整实践"
        )

        let validated = try controller.validate(plan, for: session)
        XCTAssertEqual(validated.memoryUpdate.practiceOptions, options)
        XCTAssertNil(validated.memoryUpdate.practiceKind)
        XCTAssertNil(validated.memoryUpdate.selectedPractice)
        XCTAssertTrue(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ).isEmpty
        )

        session.semanticMemory.apply(validated.memoryUpdate)
        XCTAssertEqual(session.semanticMemory.practiceOptions, options)
        XCTAssertNil(session.semanticMemory.practiceKind)
        XCTAssertNil(session.semanticMemory.selectedPractice)
    }

    func testPracticeOfferRejectsMoreThanOneOption() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经等待确认的最终叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-too-many-options"
        )
        let base = protocolPracticeOptions()
        let second = TurnPracticeOption(
            id: "protect-1",
            kind: .protect,
            title: "保护一个边界",
            instruction: "只说明一个已经确认的责任范围。",
            rationale: "这是另一个候选方向。"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceOptions: base + [second]),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-too-many-options"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            replyGuidance: "候选过多"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }
    }

    func testAcceptedPresentedPracticeCanonicalizesCompletionTupleAndKind() throws {
        var session = protocolSession(stage: .optionalAction)
        let options = protocolPracticeOptions()
        session.semanticMemory.practiceOptions = options
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-choice"
        )
        let malformedButUnambiguous = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(selectedPractice: options[0].instruction),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: "practice-choice"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "用户接受现有实践，简短结束"
        )

        let normalized = try controller.validate(malformedButUnambiguous, for: session)
        XCTAssertEqual(normalized.requestedStage, .complete)
        XCTAssertEqual(normalized.localAction.kind, .completeSession)
        XCTAssertEqual(normalized.nextPrompt?.kind, TurnNextPromptKind.none)
        XCTAssertEqual(normalized.memoryUpdate.practiceKind, options[0].kind)
    }

    func testAcceptedPracticeCannotReplacePresentedOptionWithNewInstruction() throws {
        var session = protocolSession(stage: .optionalAction)
        session.semanticMemory.practiceOptions = protocolPracticeOptions()
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-choice-mismatch"
        )
        let mismatched = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(selectedPractice: "一个没有展示过的新实践"),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: "practice-choice-mismatch"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "错误替换用户所选实践"
        )

        XCTAssertThrowsError(try controller.validate(mismatched, for: session)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }
    }

    func testPracticeChoiceSetRejectsDuplicateIDsAndNoActionOption() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经等待确认的最终叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-invalid-options"
        )
        let duplicateOptions = [
            protocolPracticeOptions()[0],
            TurnPracticeOption(
                id: "care-1",
                kind: .noAction,
                title: "无效选项",
                instruction: "这不应成为一个主动实践选项。",
                rationale: "noAction 应由独立结果表达。"
            ),
        ]
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceOptions: duplicateOptions),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-invalid-options"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            replyGuidance: "无效的候选集合"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }
    }

    func testLegacySemanticMemoryWithoutPracticeOptionsKeepsExistingValues() throws {
        let data = Data(
            """
            {
              "situationUnderstanding":"已有理解",
              "answeredQuestionPurposes":["event_clarified"],
              "selectedPractice":"已有实践"
            }
            """.utf8
        )

        let memory = try JSONDecoder().decode(TurnSemanticMemory.self, from: data)

        XCTAssertEqual(memory.situationUnderstanding, "已有理解")
        XCTAssertEqual(memory.answeredQuestionPurposes, ["event_clarified"])
        XCTAssertEqual(memory.selectedPractice, "已有实践")
        XCTAssertEqual(memory.practiceOptions, [])
    }

    func testAcceptedPracticeCanCompleteWhenOnlyPracticeKindMetadataIsMissing() throws {
        var session = protocolSession(stage: .optionalAction)
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-1"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(
                answeredQuestionPurposes: ["practice_decided"],
                selectedPractice: "今晚安排十分钟有边界的恢复时间"
            ),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: "practice-1"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "确认实践已经记录，并自然结束"
        )

        let validated = try controller.validate(plan, for: session)

        XCTAssertEqual(validated.requestedStage, .complete)
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ),
            [.missingPracticeKind]
        )
    }

    func testNewContractIgnoresRedundantLegacyInteractionMetadata() throws {
        let session = protocolSession(stage: .contextualDisclosure)
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                pendingQuestionPurpose: "legacy_duplicate",
                pendingConfirmationTarget: .tenderSummary,
                clearPendingQuestionPurpose: true
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify_current_effect",
                focus: "这件事目前怎样影响用户"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "继续理解当前影响"
        )

        let validated = try controller.validate(plan, for: session)

        XCTAssertNil(validated.memoryUpdate.pendingQuestionPurpose)
        XCTAssertNil(validated.memoryUpdate.pendingConfirmationTarget)
        XCTAssertNil(validated.memoryUpdate.clearPendingQuestionPurpose)
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ),
            [.redundantLegacyInteractionFieldsIgnored]
        )
    }

    func testOpenQuestionMetadataIsCompletedWithoutRejectingTheTurn() throws {
        let controller = ReflectionProtocolController()
        let session = protocolSession(stage: .contextualDisclosure)
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: TurnNextPrompt(
                kind: .openQuestion,
                purpose: nil,
                focus: nil,
                target: nil,
                referenceID: nil
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接最新回答并继续理解"
        )

        let validated = try controller.validate(plan, for: session)

        XCTAssertEqual(validated.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(
            validated.nextPrompt?.purpose,
            "intent_exploreContext"
        )
        XCTAssertEqual(
            validated.nextPrompt?.focus,
            "continue_current_conversation"
        )
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ),
            [.normalizedNextPromptMetadata]
        )
    }

    func testTypedConfirmationIntentRepairsMissingPromptTarget() throws {
        let controller = ReflectionProtocolController()
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经等待确认的叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                practiceOptions: protocolPracticeOptions()
            ),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: TurnNextPrompt(
                kind: .confirmationRequest,
                purpose: "redundant",
                focus: nil,
                target: nil,
                referenceID: nil
            ),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个可修改或拒绝的小实践"
        )

        let validated = try controller.validate(plan, for: session)

        XCTAssertEqual(validated.nextPrompt?.target, .practice)
        XCTAssertNil(validated.nextPrompt?.purpose)
        XCTAssertEqual(
            controller.nonBlockingWarnings(
                originalPlan: plan,
                validatedPlan: validated,
                for: session
            ),
            [.normalizedNextPromptMetadata]
        )
    }

    func testNoActionRequiresTypedEvidenceBoundedReason() throws {
        let controller = ReflectionProtocolController()
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经确认前等待处理的叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )

        let unsupported = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceKind: .noAction),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            replyGuidance: "不提出任何实践"
        )

        XCTAssertThrowsError(try controller.validate(unsupported, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .missingNoActionReason)
        }

        let supported = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceKind: .noAction),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .confirmationRequest(target: .practice),
            replyIntent: .suggestPractice,
            noActionReason: .userNotReady,
            replyGuidance: "用户明确表示尚未准备好采取实践，提出可修改或拒绝的 noAction"
        )

        XCTAssertNoThrow(try controller.validate(supported, for: session))
    }

    func testNewCompletionRequiresResolvedNarrativeOrPracticeGate() throws {
        var narrative = protocolSession(stage: .narrativeConfirmation)
        narrative.semanticMemory.finalNarrative = "一段已经展示并等待确认的叙事"
        narrative.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        let completeWithoutPractice = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "用户确认叙事且当前不需要实践，简短结束"
        )
        XCTAssertThrowsError(
            try controller.validate(completeWithoutPractice, for: narrative)
        )

        var practice = protocolSession(stage: .optionalAction)
        practice.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-1"
        )
        let acceptedWithoutStoredPractice = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: "practice-1"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "缺少要保存的实践"
        )
        XCTAssertThrowsError(
            try controller.validate(acceptedWithoutStoredPractice, for: practice)
        )

        let declined = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .declined,
                referenceID: "practice-1"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "用户不采用实践，保留自主选择并简短结束"
        )
        XCTAssertNoThrow(try controller.validate(declined, for: practice))
    }

    func testMemoryUpdateNormalizesBooleanStringsAndDropsInvalidOptionalFlag() throws {
        let falseUpdate = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"clearPendingQuestionPurpose":"false"}"#.utf8)
        )
        XCTAssertEqual(falseUpdate.clearPendingQuestionPurpose, false)

        let trueUpdate = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"clearPendingQuestionPurpose":"true"}"#.utf8)
        )
        XCTAssertEqual(trueUpdate.clearPendingQuestionPurpose, true)

        let invalidUpdate = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"clearPendingQuestionPurpose":"sometimes"}"#.utf8)
        )
        XCTAssertNil(invalidUpdate.clearPendingQuestionPurpose)
    }

    func testCompletePlannerMemoryContractDecodesEverySwiftFieldType() throws {
        let content = """
        {
          "requestedStage": "contextualDisclosure",
          "localAction": {
            "kind": "none",
            "trackingCueIDs": []
          },
          "memoryUpdate": {
            "situationUnderstanding": "具体处境理解",
            "answeredQuestionPurposes": ["event_clarified", "personal_meaning_clarified"],
            "pendingQuestionPurpose": "tracking_relation_check",
            "pendingConfirmationTarget": "trackingRelationship",
            "clearPendingQuestionPurpose": false,
            "trackingAssessments": [
              {
                "cueID": "sleep",
                "relevance": "partlyRelated",
                "userInterpretation": "用户认为休息不足可能让精力更有限"
              }
            ],
            "tenderUnderstanding": "痛苦和现实限制都需要被承认",
            "cardImageRelation": "画面中一部分正在发生变化",
            "cardRealityMapping": "现实中也有一部分可以单独回看",
            "cardNegotiatedMeaning": "这是一个由用户确认的候选理解",
            "fierceUnderstanding": "仍有一个具体回应可以诚实面对",
            "finalNarrative": "已经确认的整合叙事",
            "practiceKind": "repair",
            "selectedPractice": "一个已经确认的小实践"
          },
          "resolvedConfirmation": {
            "target": "trackingRelationship",
            "decision": "partlyRelated",
            "referenceID": "batch-1"
          },
          "nextPrompt": {
            "kind": "openQuestion",
            "purpose": "clarify_remaining_context",
            "focus": "仍需理解的现实影响",
            "target": null,
            "referenceID": null
          },
          "replyIntent": "checkTrackingRelationship",
          "replyGuidance": "承接用户刚才的回答"
        }
        """
        let plan = try JSONDecoder().decode(
            LLMTurnResponsePlan.self,
            from: try XCTUnwrap(content.data(using: .utf8))
        )

        XCTAssertEqual(plan.requestedStage, .contextualDisclosure)
        XCTAssertEqual(plan.localAction.kind, .none)
        XCTAssertEqual(plan.localAction.trackingCueIDs, [])
        XCTAssertEqual(plan.memoryUpdate.situationUnderstanding, "具体处境理解")
        XCTAssertEqual(
            plan.memoryUpdate.answeredQuestionPurposes,
            ["event_clarified", "personal_meaning_clarified"]
        )
        XCTAssertEqual(plan.memoryUpdate.pendingQuestionPurpose, "tracking_relation_check")
        XCTAssertEqual(
            plan.memoryUpdate.pendingConfirmationTarget,
            .trackingRelationship
        )
        XCTAssertEqual(plan.memoryUpdate.clearPendingQuestionPurpose, false)
        XCTAssertEqual(plan.memoryUpdate.trackingAssessments?.first?.cueID, "sleep")
        XCTAssertEqual(
            plan.memoryUpdate.trackingAssessments?.first?.relevance,
            .partlyRelated
        )
        XCTAssertEqual(
            plan.memoryUpdate.trackingAssessments?.first?.userInterpretation,
            "用户认为休息不足可能让精力更有限"
        )
        XCTAssertEqual(plan.memoryUpdate.tenderUnderstanding, "痛苦和现实限制都需要被承认")
        XCTAssertEqual(plan.memoryUpdate.cardImageRelation, "画面中一部分正在发生变化")
        XCTAssertEqual(plan.memoryUpdate.cardRealityMapping, "现实中也有一部分可以单独回看")
        XCTAssertEqual(plan.memoryUpdate.cardNegotiatedMeaning, "这是一个由用户确认的候选理解")
        XCTAssertEqual(plan.memoryUpdate.fierceUnderstanding, "仍有一个具体回应可以诚实面对")
        XCTAssertEqual(plan.memoryUpdate.finalNarrative, "已经确认的整合叙事")
        XCTAssertEqual(plan.memoryUpdate.practiceKind, .repair)
        XCTAssertEqual(plan.memoryUpdate.selectedPractice, "一个已经确认的小实践")
        XCTAssertEqual(plan.resolvedConfirmation?.target, .trackingRelationship)
        XCTAssertEqual(plan.resolvedConfirmation?.decision, .partlyRelated)
        XCTAssertEqual(plan.resolvedConfirmation?.referenceID, "batch-1")
        XCTAssertEqual(plan.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(plan.nextPrompt?.purpose, "clarify_remaining_context")
        XCTAssertEqual(plan.replyIntent, .checkTrackingRelationship)
        XCTAssertEqual(plan.replyGuidance, "承接用户刚才的回答")
    }

    func testPlannerMemoryContractDropsMalformedOptionalPatchFields() throws {
        let wrongValues: [(String, Any)] = [
            ("situationUnderstanding", []),
            ("pendingQuestionPurpose", 1),
            ("pendingConfirmationTarget", 1),
            ("clearPendingQuestionPurpose", []),
            ("trackingAssessments", [:]),
            ("tenderUnderstanding", []),
            ("cardImageRelation", []),
            ("cardRealityMapping", []),
            ("cardNegotiatedMeaning", []),
            ("fierceUnderstanding", []),
            ("finalNarrative", []),
            ("practiceKind", []),
            ("selectedPractice", []),
        ]

        for (field, wrongValue) in wrongValues {
            let object: [String: Any] = [field: wrongValue]
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertNoThrow(
                try JSONDecoder().decode(TurnSemanticMemoryUpdate.self, from: data),
                "Optional metadata \(field) should not interrupt the turn"
            )
        }

        let singlePurpose = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"answeredQuestionPurposes":"event_clarified"}"#.utf8)
        )
        XCTAssertEqual(singlePurpose.answeredQuestionPurposes, ["event_clarified"])

        let invalidPractice = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"practiceKind":"support"}"#.utf8)
        )
        XCTAssertNil(invalidPractice.practiceKind)
    }

    func testPlannerNestedEnumsAndAssessmentFieldsUseOnlySwiftContractValues() throws {
        for relevance in TurnTrackingRelevance.allCases {
            let object: [String: Any] = [
                "cueID": "sleep",
                "relevance": relevance.rawValue,
                "userInterpretation": NSNull(),
            ]
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertEqual(
                try JSONDecoder().decode(TurnTrackingAssessment.self, from: data).relevance,
                relevance
            )
        }

        for invalid: [String: Any] in [
            ["cueID": 1, "relevance": "related", "userInterpretation": NSNull()],
            ["cueID": "sleep", "relevance": "confirmed", "userInterpretation": NSNull()],
            ["cueID": "sleep", "relevance": "related", "userInterpretation": []],
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    TurnTrackingAssessment.self,
                    from: JSONSerialization.data(withJSONObject: invalid)
                )
            )
        }

        for stage in ReflectionProtocolStage.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    ReflectionProtocolStage.self,
                    from: JSONEncoder().encode(stage)
                ),
                stage
            )
        }
        for action in TurnLocalActionKind.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    TurnLocalActionKind.self,
                    from: JSONEncoder().encode(action)
                ),
                action
            )
        }
        for intent in TurnReplyIntent.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    TurnReplyIntent.self,
                    from: JSONEncoder().encode(intent)
                ),
                intent
            )
        }
        for kind in TurnPracticeKind.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    TurnPracticeKind.self,
                    from: JSONEncoder().encode(kind)
                ),
                kind
            )
        }
        for target in TurnConfirmationTarget.allCases {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    TurnConfirmationTarget.self,
                    from: JSONEncoder().encode(target)
                ),
                target
            )
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ReflectionProtocolStage.self,
                from: Data(#""trackingReview""#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                TurnLocalActionKind.self,
                from: Data(#""showTracking""#.utf8)
            )
        )
        for invalidAction: [String: Any] in [
            ["kind": "none", "trackingCueIDs": NSNull()],
            ["kind": "none", "trackingCueIDs": "sleep"],
            ["kind": "showTracking", "trackingCueIDs": []],
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    TurnLocalActionRequest.self,
                    from: JSONSerialization.data(withJSONObject: invalidAction)
                )
            )
        }
    }

    func testMemoryPatchNullAndClearOperationsHaveDistinctSemantics() throws {
        var memory = TurnSemanticMemory(
            situationUnderstanding: "已有处境理解",
            answeredQuestionPurposes: ["event_clarified"],
            pendingQuestionPurpose: "personal_meaning_check",
            pendingConfirmationTarget: .trackingRelationship,
            trackingAssessments: [
                .init(
                    cueID: "sleep",
                    relevance: .related,
                    userInterpretation: "已有用户解释"
                ),
            ],
            tenderUnderstanding: "已有 Tender 理解",
            cardImageRelation: "已有画面关系",
            cardRealityMapping: "已有现实映射",
            cardNegotiatedMeaning: "已有卡片理解",
            fierceUnderstanding: "已有 Fierce 理解",
            finalNarrative: "已有叙事",
            selectedPractice: "已有实践"
        )
        let allNull = """
        {
          "situationUnderstanding": null,
          "answeredQuestionPurposes": null,
          "pendingQuestionPurpose": null,
          "pendingConfirmationTarget": null,
          "clearPendingQuestionPurpose": null,
          "trackingAssessments": null,
          "tenderUnderstanding": null,
          "cardImageRelation": null,
          "cardRealityMapping": null,
          "cardNegotiatedMeaning": null,
          "fierceUnderstanding": null,
          "finalNarrative": null,
          "selectedPractice": null
        }
        """
        let unchanged = memory
        memory.apply(
            try JSONDecoder().decode(
                TurnSemanticMemoryUpdate.self,
                from: try XCTUnwrap(allNull.data(using: .utf8))
            )
        )
        XCTAssertEqual(memory, unchanged, "null must mean no patch, not clear")

        memory.apply(
            try JSONDecoder().decode(
                TurnSemanticMemoryUpdate.self,
                from: Data(
                    #"{"answeredQuestionPurposes":[],"trackingAssessments":[]}"#.utf8
                )
            )
        )
        XCTAssertEqual(memory, unchanged, "empty update arrays must not clear cumulative memory")

        memory.apply(
            .init(
                pendingQuestionPurpose: nil,
                pendingConfirmationTarget: nil,
                clearPendingQuestionPurpose: true,
                cardNegotiatedMeaning: "",
                selectedPractice: ""
            )
        )
        XCTAssertNil(memory.pendingQuestionPurpose)
        XCTAssertNil(memory.pendingConfirmationTarget)
        XCTAssertEqual(memory.cardNegotiatedMeaning, "")
        XCTAssertEqual(memory.selectedPractice, "")
        XCTAssertEqual(memory.situationUnderstanding, "已有处境理解")
    }

    func testConflictingPendingQuestionSetAndClearIsRejected() throws {
        let session = protocolSession(stage: .contextualDisclosure)
        let conflicting = plan(
            stage: .contextualDisclosure,
            memory: .init(
                pendingQuestionPurpose: "new_question",
                clearPendingQuestionPurpose: true
            )
        )
        XCTAssertThrowsError(try controller.validate(conflicting, for: session)) { error in
            XCTAssertEqual(
                error as? ReflectionProtocolViolation,
                .conflictingMemoryPatch
            )
        }
    }

    func testCardDrawAndGuidanceRemainLocalPermissionedActions() throws {
        var consent = protocolSession(stage: .cardConsent)
        consent.condition = .cardMediated
        XCTAssertNoThrow(
            try controller.validate(
                plan(
                    stage: .cardConsent,
                    intent: .acknowledgeCardConsent,
                    action: .init(kind: .drawRandomCard)
                ),
                for: consent
            )
        )

        var reflection = protocolSession(stage: .cardReflection)
        reflection.condition = .cardMediated
        reflection.card = CardService().allCards[0]
        reflection.cardDisplayState = .displayed
        let relationMemory = TurnSemanticMemoryUpdate(
            cardImageRelation: "画面中的人先观察再决定是否靠近",
            cardRealityMapping: "用户在现实中也需要先了解请求范围再回应"
        )
        XCTAssertNoThrow(
            try controller.validate(
                plan(
                    stage: .cardReflection,
                    intent: .authorizeCardGuidance,
                    action: .init(kind: .shareCardGuidance),
                    memory: relationMemory
                ),
                for: reflection
            )
        )

        // Authorization is never a standalone visible turn. Without the matching local action it
        // would reach the Writer as an intentionally silent intent and produce an empty reply.
        XCTAssertThrowsError(
            try controller.validate(
                plan(
                    stage: .cardReflection,
                    intent: .authorizeCardGuidance,
                    action: .none,
                    memory: relationMemory
                ),
                for: reflection
            )
        ) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }

        let combinedReadingAndGuidance = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(
                cardImageRelation: "画面中的人先观察再决定是否靠近",
                cardRealityMapping: "用户在现实中也需要先了解请求范围再回应",
                cardNegotiatedMeaning: "这段含义尚未在 guidance-aware 回复中向用户展示"
            ),
            nextPrompt: .openQuestion(
                purpose: "check_card_reading",
                focus: "候选映射是否贴近"
            ),
            replyIntent: .presentCardReading,
            replyGuidance: "申请 guidance 并生成一段可协商的卡牌解读"
        )
        let normalizedAuthorization = try controller.validate(
            combinedReadingAndGuidance,
            for: reflection
        )
        XCTAssertEqual(
            normalizedAuthorization.replyIntent,
            .authorizeCardGuidance
        )
        XCTAssertEqual(
            normalizedAuthorization.localAction.kind,
            .shareCardGuidance
        )
        XCTAssertEqual(
            normalizedAuthorization.nextPrompt?.kind,
            TurnNextPromptKind.none
        )
        XCTAssertNil(
            normalizedAuthorization.memoryUpdate.cardNegotiatedMeaning
        )

        reflection.cardGuidanceShared = true
        XCTAssertFalse(
            controller.permissions(for: reflection).allowedReplyIntents.contains(
                .authorizeCardGuidance
            )
        )
        XCTAssertThrowsError(
            try controller.validate(
                plan(
                    stage: .cardReflection,
                    intent: .authorizeCardGuidance,
                    action: .none,
                    memory: relationMemory
                ),
                for: reflection
            )
        ) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }
        let readingWithoutCandidateObject = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "呈现一段可修改、可拒绝的卡牌解读"
        )
        XCTAssertThrowsError(
            try controller.validate(readingWithoutCandidateObject, for: reflection)
        ) { error in
            XCTAssertEqual(
                error as? ReflectionProtocolViolation,
                .missingRequiredMemoryField(.cardNegotiatedMeaning)
            )
        }

        reflection.cardGuidanceShared = false
        XCTAssertThrowsError(
            try controller.validate(
                plan(
                    stage: .cardReflection,
                    intent: .authorizeCardGuidance,
                    action: .init(kind: .shareCardGuidance)
                ),
                for: reflection
            )
        )

        reflection.cardGuidanceShared = true
        XCTAssertThrowsError(
            try controller.validate(
                plan(
                    stage: .cardReflection,
                    intent: .authorizeCardGuidance,
                    action: .init(kind: .shareCardGuidance)
                ),
                for: reflection
            )
        )
    }

    func testCompletionIntentCanonicalizesTheSwiftOwnedCompletionAction() throws {
        var session = protocolSession(stage: .optionalAction)
        session.condition = .directLLM
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-completion"
        )
        session.semanticMemory.selectedPractice = "一个已经确认的小实践"

        let normalized = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(
                    selectedPractice: "一个已经确认的小实践"
                ),
                resolvedConfirmation: .init(
                    target: .practice,
                    decision: .accepted,
                    referenceID: "practice-completion"
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .completeConversation,
                replyGuidance: "确认实践后结束"
            ),
            for: session
        )
        XCTAssertEqual(normalized.requestedStage, .complete)
        XCTAssertEqual(normalized.localAction.kind, .completeSession)
    }

    func testTenderStageRejectsPrematurePracticeAndCompletionIntents() throws {
        var session = protocolSession(stage: .tenderConfirmation)
        session.condition = .cardMediated
        session.semanticMemory.pendingConfirmationTarget = .tenderSummary

        let practice = plan(
            stage: .tenderConfirmation,
            intent: .suggestPractice,
            memory: .init(
                pendingQuestionPurpose: "practice_check",
                pendingConfirmationTarget: .practice
            )
        )
        XCTAssertThrowsError(try controller.validate(practice, for: session)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .illegalReplyIntent)
        }

        let completion = plan(
            stage: .tenderConfirmation,
            intent: .completeConversation,
            action: .init(kind: .completeSession),
            memory: .init(clearPendingQuestionPurpose: true)
        )
        XCTAssertThrowsError(try controller.validate(completion, for: session))
    }

    func testTypedIntentCanonicalizesUniqueDestinationIncludingCompletion() throws {
        let disclosure = protocolSession(stage: .contextualDisclosure)
        let tenderWithoutTransition = plan(
            stage: .contextualDisclosure,
            intent: .presentTenderSummary,
            memory: .init(
                pendingQuestionPurpose: "confirm_tender_summary",
                pendingConfirmationTarget: .tenderSummary,
                tenderUnderstanding: "一段待确认的理解"
            )
        )
        let normalizedTender = try controller.validate(
            tenderWithoutTransition,
            for: disclosure
        )
        XCTAssertEqual(normalizedTender.requestedStage, .tenderConfirmation)

        let narrative = protocolSession(stage: .narrativeConfirmation)
        let practiceWithoutTransition = plan(
            stage: .narrativeConfirmation,
            intent: .suggestPractice,
            memory: .init(
                pendingQuestionPurpose: "confirm_practice",
                pendingConfirmationTarget: .practice,
                practiceOptions: protocolPracticeOptions()
            )
        )
        let normalizedPractice = try controller.validate(
            practiceWithoutTransition,
            for: narrative
        )
        XCTAssertEqual(normalizedPractice.requestedStage, .optionalAction)

        var optionalAction = protocolSession(stage: .optionalAction)
        optionalAction.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "typed-completion"
        )
        optionalAction.semanticMemory.selectedPractice = "一个已经确认的小实践"
        let completionWithoutTransition = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                selectedPractice: "一个已经确认的小实践"
            ),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: "typed-completion"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "用类型化 intent 归一化完成阶段"
        )
        let normalizedCompletion = try controller.validate(
            completionWithoutTransition,
            for: optionalAction
        )
        XCTAssertEqual(normalizedCompletion.requestedStage, .complete)
        XCTAssertEqual(normalizedCompletion.localAction.kind, .completeSession)
    }

    func testWriterMustEchoValidatedTypedIntent() throws {
        let planned = plan(stage: .contextualDisclosure, intent: .exploreContext)
        let drifted = LLMTurnWriterResponse(
            realizedIntent: .suggestPractice,
            reply: "可以先做一个五分钟的小练习。"
        )
        XCTAssertThrowsError(try controller.validate(drifted, for: planned)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .writerIntentMismatch)
        }

        let faithful = LLMTurnWriterResponse(
            realizedIntent: .exploreContext,
            reply: "这些压力落到每天的生活里，最明显影响了什么？"
        )
        XCTAssertNoThrow(try controller.validate(faithful, for: planned))
    }

    func testTrackingConfirmationCannotStandInForTenderConfirmation() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let sleep = trackingCue(id: "sleep")
        session.trackingCues = [sleep]
        session.presentedTrackingCueIDs = [sleep.id]
        session.semanticMemory.pendingQuestionPurpose = "tracking_relation_check"
        session.semanticMemory.pendingConfirmationTarget = .trackingRelationship

        let assessment = plan(
            stage: .contextualDisclosure,
            intent: .checkTrackingRelationship,
            memory: .init(
                clearPendingQuestionPurpose: true,
                trackingAssessments: [
                    .init(
                        cueID: sleep.id,
                        relevance: .related,
                        userInterpretation: "用户认为休息不足让当时更难保持耐心"
                    ),
                ]
            )
        )
        XCTAssertNoThrow(try controller.validate(assessment, for: session))

        let prematureTenderTransition = plan(
            stage: .tenderConfirmation,
            intent: .presentTenderSummary,
            memory: .init(clearPendingQuestionPurpose: true)
        )
        XCTAssertThrowsError(
            try controller.validate(prematureTenderTransition, for: session)
        )
    }

    func testTrackingAnswerCanAtomicallyBecomeANewTenderConfirmation() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let sleep = trackingCue(id: "sleep")
        session.trackingCues = [sleep]
        session.presentedTrackingCueIDs = [sleep.id]
        session.semanticMemory.pendingQuestionPurpose = "tracking_relation_check"
        session.semanticMemory.pendingConfirmationTarget = .trackingRelationship

        let integrated = plan(
            stage: .tenderConfirmation,
            intent: .integrateTrackingAndPresentTenderSummary,
            memory: .init(
                pendingQuestionPurpose: "confirm_tender_summary",
                pendingConfirmationTarget: .tenderSummary,
                trackingAssessments: [
                    .init(
                        cueID: sleep.id,
                        relevance: .related,
                        userInterpretation: "用户认为休息不足让当时更难保持耐心"
                    ),
                ],
                tenderUnderstanding: "持续处理家里的事务又没有休息好，可能让当时更难保持耐心；这能说明处境更难，但不能替代对冲动语气的具体处理"
            )
        )
        XCTAssertNoThrow(try controller.validate(integrated, for: session))

        let dropsRejectedTrackingAssessment = plan(
            stage: .tenderConfirmation,
            intent: .presentTenderSummary,
            memory: .init(
                pendingQuestionPurpose: "confirm_tender_summary",
                pendingConfirmationTarget: .tenderSummary,
                tenderUnderstanding: "忽略了用户刚才对 tracking 的回答"
            )
        )
        XCTAssertThrowsError(
            try controller.validate(dropsRejectedTrackingAssessment, for: session)
        )

        let atomicReplacement = plan(
            stage: .tenderConfirmation,
            intent: .integrateTrackingAndPresentTenderSummary,
            memory: .init(
                pendingQuestionPurpose: "confirm_tender_summary",
                pendingConfirmationTarget: .tenderSummary,
                clearPendingQuestionPurpose: true,
                trackingAssessments: [
                    .init(cueID: sleep.id, relevance: .related, userInterpretation: nil),
                ],
                tenderUnderstanding: "一段理解"
            )
        )
        XCTAssertNoThrow(try controller.validate(atomicReplacement, for: session))

        var memory = session.semanticMemory
        memory.apply(atomicReplacement.memoryUpdate)
        XCTAssertEqual(memory.pendingQuestionPurpose, "confirm_tender_summary")
        XCTAssertEqual(memory.pendingConfirmationTarget, .tenderSummary)
    }

    func testTenderSummaryCreatesItsOwnConfirmationBeforeCardConsent() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        session.condition = .cardMediated
        let summary = plan(
            stage: .tenderConfirmation,
            intent: .presentTenderSummary,
            memory: .init(
                pendingQuestionPurpose: "confirm_tender_summary",
                pendingConfirmationTarget: .tenderSummary,
                tenderUnderstanding: "工作堆积和休息不足让人更容易慌乱，但不能概括整个人的能力"
            )
        )
        XCTAssertNoThrow(try controller.validate(summary, for: session))

        session.protocolStage = .tenderConfirmation
        session.semanticMemory.pendingQuestionPurpose = "confirm_tender_summary"
        session.semanticMemory.pendingConfirmationTarget = .tenderSummary
        session.semanticMemory.tenderUnderstanding =
            "工作堆积和休息不足让人更容易慌乱，但不能概括整个人的能力"
        let consent = plan(
            stage: .cardConsent,
            intent: .inviteCardConsent,
            memory: .init(clearPendingQuestionPurpose: true)
        )
        XCTAssertNoThrow(try controller.validate(consent, for: session))
    }

    func testPlannerPromptOwnsSemanticsWithoutLegacyFineGrainedStates() {
        let session = protocolSession(stage: .contextualDisclosure)
        let permissions = controller.permissions(for: session)
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .contextualDisclosure,
            condition: .cardMediated,
            permissions: permissions,
            recentMessages: [
                .init(role: .user, content: "实验失败后，我开始怀疑自己是否适合做研究。"),
            ],
            semanticMemory: .init(),
            trackingCandidates: [],
            contextualLoadCue: DialogueContextCue(
                hypothesis: "你最近可能承受着比平时更多的压力，可用的精力或应对余地可能少了一些。",
                confidence: .moderate,
                relevance: .notReviewed,
                usageBoundary: "只能作为整体理解中的一句不确定背景。"
            ),
            card: nil,
            protocolCorrection: nil
        )
        let factory = ReflectionPromptFactory()
        let planner = factory.turnPlanningPrompt(request: request)

        // Default CI checks the behavioral boundary rather than snapshotting hundreds of words.
        // Set STRICT_PROMPT_SNAPSHOT=1 only when deliberately auditing every legacy phrase below.
        if ProcessInfo.processInfo.environment["STRICT_PROMPT_SNAPSHOT"] != "1" {
            XCTAssertTrue(planner.system.contains("replyIntent"))
            XCTAssertTrue(planner.system.contains("replyGuidance"))
            XCTAssertTrue(planner.system.contains("whole Tender summary"))
            XCTAssertTrue(planner.system.contains("specific emotion"))
            XCTAssertTrue(planner.user.contains("你最近可能承受着比平时更多的压力"))
            XCTAssertFalse(planner.user.contains("HRV"))

            let focusedPlan = plan(stage: .contextualDisclosure)
            let focusedWriter = factory.turnWritingPrompt(request: request, plan: focusedPlan)
            XCTAssertTrue(focusedWriter.system.contains("request.contextualLoadCue"))
            XCTAssertTrue(
                focusedWriter.system.contains("Never create a separate tracking paragraph")
            )
            XCTAssertTrue(
                focusedWriter.system.contains("The only question is the accuracy check")
            )
            return
        }

        XCTAssertTrue(planner.system.contains("replyIntent"))
        XCTAssertTrue(planner.system.contains("replyGuidance"))
        XCTAssertTrue(planner.system.contains("resolvedConfirmation"))
        XCTAssertTrue(planner.system.contains("nextPrompt"))
        XCTAssertTrue(planner.system.contains("only visible question remains the accuracy check"))
        XCTAssertTrue(planner.system.contains("trackingCandidates is empty for new sessions"))
        XCTAssertTrue(planner.system.contains("Never mention or invent sleep, activity, heart rate, HRV"))
        XCTAssertTrue(planner.system.contains("Never use it in cardConsent or cardReflection"))
        XCTAssertTrue(planner.system.contains("event_sequence_clarified"))
        XCTAssertTrue(planner.system.contains("experienced_impact_clarified"))
        XCTAssertTrue(planner.system.contains("already answered function new"))
        XCTAssertTrue(planner.system.contains("REALITY-STORY READINESS"))
        XCTAssertTrue(planner.system.contains("exhaustive interview"))
        XCTAssertTrue(planner.system.contains("same reality story"))
        XCTAssertTrue(planner.system.contains("prefer a correctable Tender summary"))
        XCTAssertTrue(planner.system.contains("correctable Tender summary"))
        XCTAssertTrue(planner.system.contains("CANDID-REFLECTION FUNCTION CONTRACT"))
        XCTAssertTrue(planner.system.contains("fierce_behavior_or_impact_clarified"))
        XCTAssertTrue(planner.system.contains("Keep that question open"))
        XCTAssertTrue(planner.system.contains("second reassuring paraphrase"))
        XCTAssertTrue(planner.system.contains("does not prove they already behave"))
        XCTAssertTrue(
            planner.system.contains("Fierce is an optional function, not a required phase")
        )
        XCTAssertTrue(planner.system.contains("very next ordinary plan must"))
        XCTAssertTrue(planner.system.contains("Final narrative is the delta"))
        XCTAssertTrue(planner.system.contains(#""candidUnderstanding": null"#))
        XCTAssertTrue(planner.system.contains("legacy fierceUnderstanding: always null"))
        XCTAssertTrue(planner.system.contains("always moves to optionalAction"))
        XCTAssertTrue(planner.system.contains("Select only evidence-supported directions"))
        XCTAssertTrue(planner.system.contains("practiceOptions"))
        XCTAssertTrue(planner.system.contains("provide exactly one strongest complete practice"))
        XCTAssertTrue(planner.system.contains("connectionGuidance may privately select"))
        XCTAssertTrue(
            planner.system.contains(
                "cardDisplayed, cardGuidanceAvailable, and protocolContinuation"
            )
        )
        XCTAssertTrue(planner.system.contains("does not want to continue"))
        XCTAssertTrue(planner.system.contains("measurement-free possibility"))
        XCTAssertTrue(planner.system.contains("specific emotion"))
        XCTAssertTrue(planner.user.contains("你最近可能承受着比平时更多的压力"))
        XCTAssertFalse(planner.user.contains("HRV"))
        XCTAssertTrue(planner.system.contains("legacy clearPendingQuestionPurpose"))
        XCTAssertTrue(planner.system.contains("answeredQuestionPurposes: array of strings or null"))
        XCTAssertTrue(planner.system.contains("null means “leave the stored value unchanged”"))
        XCTAssertTrue(
            planner.system.contains(
                "The same successful turn may resolve one old confirmation"
            )
        )
        XCTAssertTrue(planner.system.contains("Swift assigns referenceID"))
        XCTAssertTrue(planner.system.contains("practiceOptions replaces the pending choice set"))
        XCTAssertTrue(planner.system.contains("[] clears only that choice set"))
        XCTAssertTrue(
            planner.system.contains(
                #""relevance": "related|partlyRelated|unrelated|uncertain""#
            )
        )
        XCTAssertTrue(planner.system.contains("Never output confirmed, qualified"))
        XCTAssertTrue(planner.system.contains("tarot-reading-like but non-divinatory"))
        XCTAssertTrue(
            planner.system.contains(
                "user-authored connection is sufficient"
            )
        )
        XCTAssertTrue(
            planner.system.contains(
                "the person interpret every object"
            )
        )
        XCTAssertTrue(
            planner.system.contains(
                "presentCardReading requires a non-empty"
            )
        )
        XCTAssertTrue(
            planner.system.contains(
                "pending object being shown for negotiation"
            )
        )
        XCTAssertTrue(
            planner.system.contains(
                "Card reading is content, not a stage announcement"
            )
        )
        XCTAssertTrue(planner.system.contains("substantive candidate reading in that same visible turn"))
        XCTAssertTrue(planner.system.contains("cardNegotiatedMeaning stores only what the card relationship"))
        XCTAssertTrue(planner.system.contains("newly adds beyond the already"))
        XCTAssertTrue(planner.system.contains("accepts or revises cardMapping"))
        XCTAssertTrue(planner.system.contains("do not present"))

        let planCritic = factory.turnPlanCriticPrompt(
            request: request,
            plan: LLMTurnResponsePlan(
                requestedStage: .contextualDisclosure,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .openQuestion(
                    purpose: "experienced_impact_clarified",
                    focus: "继续了解尚未确认的影响"
                ),
                replyIntent: .exploreContext,
                replyGuidance: "承接最新回答，只问一个新关系"
            )
        )
        XCTAssertTrue(planCritic.system.contains("revisePlanner"))
        XCTAssertTrue(planCritic.system.contains("duplicate_question_function"))
        XCTAssertTrue(planCritic.system.contains("overfilled_focus"))
        XCTAssertTrue(planCritic.system.contains("reality_story_ready"))
        XCTAssertTrue(planCritic.system.contains("impact of an impact"))
        XCTAssertTrue(planCritic.system.contains("tender_summary_ready"))
        XCTAssertTrue(planCritic.system.contains("tracking_context_detached"))
        XCTAssertTrue(planCritic.system.contains("tracking_responsibility_erasure"))
        XCTAssertTrue(planCritic.system.contains("fierce_memory_stale"))
        XCTAssertTrue(planCritic.system.contains("premature_action_design"))
        XCTAssertTrue(planCritic.system.contains("narrative_ready"))
        XCTAssertTrue(planCritic.system.contains("fierce_reflection_missing"))
        XCTAssertTrue(planCritic.system.contains("practice_offer_required"))
        XCTAssertTrue(planCritic.system.contains("unsupported_no_action"))
        XCTAssertTrue(planCritic.system.contains("card_reality_mapping_missing"))
        XCTAssertTrue(planCritic.system.contains("card_mapping_progress_ignored"))
        XCTAssertTrue(planCritic.system.contains("card_reading_repeated"))
        XCTAssertTrue(planCritic.system.contains("card_question_overdirected"))
        XCTAssertTrue(
            planCritic.system.contains("finalNarrative substantially restates") &&
                planCritic.system.contains("card/direct-reflection delta primary")
        )
        XCTAssertTrue(planCritic.system.contains("practice_choice_set_invalid"))
        XCTAssertTrue(planCritic.system.contains("practice_evidence_mismatch"))
        XCTAssertTrue(planCritic.system.contains("completion_contract_invalid"))
        XCTAssertTrue(planCritic.system.contains("after the confirmation-only transition"))
        XCTAssertTrue(planCritic.system.contains("practice kind does not match"))
        XCTAssertTrue(planner.system.contains("the reading again"))
        XCTAssertTrue(planner.system.contains("STAGE-SPECIFIC ADDITIONS"))
        XCTAssertTrue(
            planner.system.contains(
                "Practice presents one complete assistant-authored option"
            )
        )
        XCTAssertTrue(planner.system.contains("Tracking background never excuses"))
        XCTAssertTrue(planner.system.contains("connectionScaffoldUsed"))
        XCTAssertFalse(planner.system.contains("emotionDisclosure"))
        XCTAssertFalse(planner.system.contains("singleConcreteQuestion"))

        let semanticPlan = plan(stage: .contextualDisclosure)
        let writer = factory.turnWritingPrompt(request: request, plan: semanticPlan)
        XCTAssertTrue(writer.system.contains(#""realizedIntent""#))
        XCTAssertFalse(writer.system.contains(#""requestedStage""#))
        XCTAssertTrue(writer.system.contains("Do not add a new interpretation"))
        XCTAssertTrue(writer.system.contains("one unfolding reality story"))
        XCTAssertTrue(writer.system.contains("form fields"))
        XCTAssertTrue(writer.system.contains("further effect questions"))
        XCTAssertTrue(writer.system.contains("request.contextualLoadCue"))
        XCTAssertTrue(writer.system.contains("Never create a separate tracking paragraph"))
        XCTAssertTrue(writer.system.contains("The only question is the accuracy check"))
        XCTAssertTrue(writer.system.contains("Never mention sleep, activity, heart rate, HRV"))
        XCTAssertTrue(writer.system.contains("specific emotion"))
        XCTAssertTrue(writer.system.contains("Do not use it during card consent or card reflection"))
        XCTAssertTrue(writer.system.contains("present the one structured option"))
        XCTAssertTrue(writer.system.contains("speaks for, reveals, or knows the person"))
        XCTAssertTrue(writer.system.contains("Invite the person to accept it"))
        XCTAssertTrue(writer.system.contains("Never add a second option"))
        XCTAssertTrue(
            writer.system.contains("Do not merely") &&
                writer.system.contains("announce that an insight will come next")
        )
        XCTAssertTrue(
            writer.system.contains("write the delta beyond the already confirmed") &&
                writer.system.contains("do not restate its event, effects, or tracking observations")
        )
        XCTAssertTrue(writer.system.contains("two or three concise sentences"))
        XCTAssertTrue(writer.system.contains("Do not offer a practice"))

        let draft = LLMTurnWriterResponse(
            realizedIntent: .exploreContext,
            reply: "这件事现在怎样影响你？"
        )
        let critic = factory.turnCriticPrompt(
            request: request,
            plan: semanticPlan,
            draft: draft
        )
        XCTAssertTrue(critic.system.contains("private semantic quality Critic"))
        XCTAssertTrue(critic.system.contains("field_stitching"))
        XCTAssertTrue(critic.system.contains("deferred_content"))
        XCTAssertTrue(critic.system.contains("baseline_repetition"))
        XCTAssertTrue(critic.system.contains("status_inflation"))
        XCTAssertTrue(critic.system.contains("premature_practice"))
        XCTAssertTrue(critic.system.contains("practice_handoff"))
        XCTAssertTrue(critic.system.contains("practice_options_lost"))
        XCTAssertTrue(critic.system.contains("reality_story_fragmented"))
        XCTAssertTrue(critic.system.contains("tracking_context_detached"))
        XCTAssertTrue(critic.system.contains("tracking_responsibility_erasure"))
        XCTAssertTrue(critic.system.contains("inserted data report"))
        XCTAssertTrue(
            critic.system.contains(
                "promises a card reading, interpretation, insight, or next step later"
            )
        )
        XCTAssertTrue(critic.system.contains("Planner's typed protocol decision"))
    }

    func testFinalNarrativeContractsUseConditionSpecificSingleDelta() {
        let narrativePlan = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                finalNarrative: "待生成的条件化增量叙事"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "只组织一个新增区分，并说明它如何改变现实理解"
        )
        let permissions = ReflectionProtocolPermissions(
            currentStage: .directReflection,
            allowedStages: [.directReflection, .narrativeConfirmation],
            allowedActions: [.none],
            allowedReplyIntents: [.directCandidReflection, .presentFinalNarrative]
        )
        let sharedMemory = TurnSemanticMemory(
            tenderUnderstanding: "已经确认并锁定的 Tender 背景",
            cardImageRelation: "用户形成的画面关系",
            cardRealityMapping: "用户形成的现实映射",
            cardNegotiatedMeaning: "用户接受或修订后的卡牌区分",
            candidUnderstanding: "后续回答对同一区分的限定"
        )
        let cardRequest = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: permissions,
            recentMessages: [
                .init(role: .user, content: "这个理解贴近，但我想保留一点不确定性。"),
            ],
            semanticMemory: sharedMemory,
            trackingCandidates: [],
            cardMappingConfirmed: true,
            card: nil,
            protocolCorrection: nil
        )
        let directRequest = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .directReflection,
            condition: .directLLM,
            permissions: permissions,
            recentMessages: [
                .init(role: .user, content: "这样区分以后，我不再把一次表现当作全部能力。"),
            ],
            semanticMemory: TurnSemanticMemory(
                tenderUnderstanding: "已经确认并锁定的 Tender 背景",
                candidUnderstanding: "直接反思新增的现实区分"
            ),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let factory = ReflectionPromptFactory()
        let cardPlanner = factory.turnPlanningPrompt(request: cardRequest)
        let directPlanner = factory.turnPlanningPrompt(request: directRequest)
        let cardWriter = factory.turnWritingPrompt(
            request: cardRequest,
            plan: narrativePlan
        )
        let directWriter = factory.turnWritingPrompt(
            request: directRequest,
            plan: narrativePlan
        )
        let cardPlanCritic = factory.turnPlanCriticPrompt(
            request: cardRequest,
            plan: narrativePlan
        )
        let directCritic = factory.turnCriticPrompt(
            request: directRequest,
            plan: narrativePlan,
            draft: .init(
                realizedIntent: .presentFinalNarrative,
                reply: "一个待检查的最终叙事。"
            )
        )

        for prompt in [cardPlanner, cardWriter, cardPlanCritic] {
            XCTAssertTrue(prompt.system.contains("This is the card-mediated condition"))
            XCTAssertTrue(
                prompt.system.contains("cardMappingConfirmed value for this request is")
            )
            XCTAssertTrue(prompt.system.contains("true. Only when it is true"))
            XCTAssertTrue(prompt.system.contains("organizing thread"))
            XCTAssertTrue(
                prompt.system.contains("relational distinction that the card phase")
            )
            XCTAssertTrue(prompt.system.contains("rejected or withdrew the mapping"))
        }
        for prompt in [directPlanner, directWriter, directCritic] {
            XCTAssertTrue(prompt.system.contains("This is the direct-model condition"))
            XCTAssertTrue(prompt.system.contains("Select exactly one distinction"))
            XCTAssertTrue(prompt.system.contains("never mention a card or image"))
            XCTAssertTrue(prompt.system.contains("person's understanding of the real"))
        }
        XCTAssertTrue(cardPlanner.system.contains("replyGuidance must name"))
        XCTAssertTrue(cardPlanCritic.system.contains("narrative_delta_mismatch"))
        XCTAssertTrue(
            directCritic.system.contains(
                "states that distinction without carrying it back to the person's concrete real"
            )
        )
    }

    func testPlannerReceivesPrivateFuzzyCardGuidanceWithoutAVisibleCardMeaning() {
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolPermissions(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.inviteCardConnection]
            ),
            recentMessages: [
                .init(role: .assistant, content: "这个画面会让你想到现实中的什么吗？"),
                .init(role: .user, content: "我一下子有点想不到。"),
            ],
            semanticMemory: .init(
                tenderUnderstanding: "已经确认的现实情境",
                cardImageRelation: "用户已经形成的画面关系"
            ),
            trackingCandidates: [],
            card: LLMTurnCardContext(
                imageIsDisplayed: true,
                visualScaffolds: [],
                connectionGuidance: .init(
                    relationalTension: "内部的模糊关系张力",
                    candidateDirections: ["boundary", "support"]
                ),
                publicTheme: nil,
                coreTension: nil,
                tenderDirections: [],
                fierceDirections: [],
                selfKindnessDirections: [],
                commonHumanityDirections: [],
                mindfulnessDirections: [],
                prohibitedClaims: ["不要宣布固定牌义"]
            ),
            protocolCorrection: nil
        )

        let prompt = ReflectionPromptFactory().turnPlanningPrompt(request: request)
        XCTAssertTrue(prompt.user.contains("connectionGuidance"))
        XCTAssertTrue(prompt.user.contains("内部的模糊关系张力"))
        XCTAssertTrue(prompt.system.contains("only a possible angle"))
        XCTAssertTrue(prompt.system.contains("Do not quote relationalTension"))
        XCTAssertTrue(prompt.system.contains("leave the card aside"))
    }

    func testMalformedOptionalTrackingAssessmentIsDroppedWithoutLosingOtherMemory() throws {
        let privateReflection = "这段私人反思不应该出现在诊断日志里"
        let content = """
        {
          "requestedStage": "contextualDisclosure",
          "localAction": {"kind": "none", "trackingCueIDs": []},
          "memoryUpdate": {
            "situationUnderstanding": "\(privateReflection)",
            "answeredQuestionPurposes": ["tracking_relation_checked"],
            "pendingQuestionPurpose": null,
            "pendingConfirmationTarget": null,
            "clearPendingQuestionPurpose": null,
            "trackingAssessments": [
              {
                "cueID": "sleep",
                "relevance": "confirmed",
                "userInterpretation": "\(privateReflection)"
              }
            ],
            "tenderUnderstanding": null,
            "cardImageRelation": null,
            "cardRealityMapping": null,
            "cardNegotiatedMeaning": null,
            "fierceUnderstanding": null,
            "finalNarrative": null,
            "selectedPractice": null
          },
          "replyIntent": "checkTrackingRelationship",
          "replyGuidance": "继续理解用户确认的数据关系"
        }
        """
        let data = try XCTUnwrap(content.data(using: .utf8))

        let decoded = try JSONDecoder().decode(
            LLMTurnResponsePlan.self,
            from: data
        )
        XCTAssertEqual(
            decoded.memoryUpdate.situationUnderstanding,
            privateReflection
        )
        XCTAssertNil(decoded.memoryUpdate.trackingAssessments)
        XCTAssertEqual(decoded.replyIntent, .checkTrackingRelationship)
    }

    private func protocolSession(stage: ReflectionProtocolStage) -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = 2
        session.protocolStage = stage
        return session
    }

    private func plan(
        stage: ReflectionProtocolStage,
        intent: TurnReplyIntent = .exploreContext,
        action: TurnLocalActionRequest = .none,
        memory: TurnSemanticMemoryUpdate = .init()
    ) -> LLMTurnResponsePlan {
        LLMTurnResponsePlan(
            requestedStage: stage,
            localAction: action,
            memoryUpdate: memory,
            replyIntent: intent,
            replyGuidance: "承接用户刚才回答的内容，并自然推进一个问题功能"
        )
    }

    private func protocolPracticeOptions() -> [TurnPracticeOption] {
        [
            .init(
                id: "care-1",
                kind: .care,
                title: "先安排一个有边界的停顿",
                instruction: "今晚留出十分钟，只照顾当下的疲惫，时间到了就停止。",
                rationale: "这回应了已经确认的消耗，同时不会要求立即解决全部问题。"
            ),
        ]
    }

    func testAuthorizedGroundedCardMappingOnlyPermitsNegotiatedReading() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        session.semanticMemory.cardRealityMapping = "用户确认的现实映射"

        let permissions = controller.permissions(for: session)

        XCTAssertTrue(permissions.allowedReplyIntents.contains(.presentCardReading))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.safetySupport))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentFinalNarrative))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.directCandidReflection))
    }

    func testCardMappingResolutionMustOpenDirectReflectionBeforeNarrative() throws {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        session.semanticMemory.cardRealityMapping = "用户确认的现实映射"
        session.semanticMemory.cardNegotiatedMeaning = "等待用户确认的协商式卡牌理解"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "card-mapping-1"
        )

        let skippedReflection = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(finalNarrative: "过早出现的最终叙事"),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .accepted,
                referenceID: "card-mapping-1"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "跳过深化"
        )
        XCTAssertThrowsError(try controller.validate(skippedReflection, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .illegalStageTransition)
        }

        let groundedReflection = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["card_mapping_confirmed"]
            ),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .accepted,
                referenceID: "card-mapping-1"
            ),
            nextPrompt: .openQuestion(
                purpose: "fierce_behavior_or_impact_clarified",
                focus: "确认材料支持的一个具体行为或影响区别"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "沿用户确认的映射深化一个现实区别"
        )

        let validated = try controller.validate(groundedReflection, for: session)
        XCTAssertEqual(validated.requestedStage, .directReflection)
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
    }

    func testNarrativeReadyDirectReflectionOnlyPermitsNarrativeOrSafety() {
        var session = protocolSession(stage: .directReflection)
        session.reflectionReadiness = .narrativeReady

        let permissions = controller.permissions(for: session)

        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.presentFinalNarrative, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.directCandidReflection))
    }

    func testPendingFierceQuestionConsumesReflectionBudgetAndForcesNarrative() {
        var session = protocolSession(stage: .directReflection)
        session.reflectionReadiness = .reflectionOpen
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_behavior_or_impact_clarified",
            focus: "一个具体行为及其影响"
        )

        let permissions = controller.permissions(for: session)

        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.presentFinalNarrative, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.directCandidReflection))
    }

    func testDirectTenderResolutionCommitsBeforeOptionalReflectionDecision() throws {
        var session = protocolSession(stage: .tenderConfirmation)
        session.condition = .directLLM
        session.semanticMemory.tenderUnderstanding = "已经展示并等待确认的 Tender 理解"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .tenderSummary,
            referenceID: "tender-1"
        )

        let combined = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["tender_confirmed"],
                candidUnderstanding: "尚未向用户提问，不应提前提交"
            ),
            resolvedConfirmation: .init(
                target: .tenderSummary,
                decision: .accepted,
                referenceID: "tender-1"
            ),
            nextPrompt: .openQuestion(
                purpose: "fierce_behavior_or_impact_clarified",
                focus: "尚未决定是否需要的 Fierce 问题"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "先提交确认，再决定是否需要 candid reflection"
        )

        let validated = try controller.validate(combined, for: session)

        XCTAssertEqual(validated.requestedStage, .directReflection)
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
        XCTAssertNil(validated.memoryUpdate.candidUnderstanding)
        XCTAssertNil(validated.memoryUpdate.answeredQuestionPurposes)
    }

    func testDirectReflectionMayPresentNarrativeWithoutCandidUnderstanding() throws {
        var session = protocolSession(stage: .directReflection)
        session.reflectionReadiness = .reflectionOpen
        session.semanticMemory.tenderUnderstanding = "用户确认的痛苦、限制和不确定性"
        session.semanticMemory.candidUnderstanding = nil
        session.semanticMemory.fierceUnderstanding = nil

        let narrative = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                finalNarrative: "这次先保留已经确认的痛苦与不确定性，不制造责任或改变要求。"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "以 Tender 与不确定性形成简短叙事"
        )

        XCTAssertNoThrow(try controller.validate(narrative, for: session))
    }

    func testAnsweredFierceQuestionMustReplaceFierceUnderstanding() {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.fierceUnderstanding = "较早、尚未包含最新回答的理解"
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_behavior_or_impact_clarified",
            focus: "一个具体行为及其影响"
        )

        let stale = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["fierce_behavior_or_impact_clarified"],
                finalNarrative: "只包含旧材料的叙事"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "承接最新回答并立即收敛"
        )

        XCTAssertThrowsError(try controller.validate(stale, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .missingRequiredMemoryField(.candidUnderstanding)
            )
        }

        let synchronized = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["fierce_behavior_or_impact_clarified"],
                candidUnderstanding: "用户最新确认了具体影响，也保留了仍不确定的责任边界",
                finalNarrative: "新增理解是具体影响已确认，而责任边界仍需保留不确定性。"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "承接最新回答并立即收敛"
        )
        XCTAssertNoThrow(try controller.validate(synchronized, for: session))
    }

    func testLegacyFierceUnderstandingPatchCanonicalizesToCandidUnderstanding() throws {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_boundary_or_responsibility_clarified",
            focus: "一个已经显示的边界问题"
        )

        let legacy = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["fierce_boundary_or_responsibility_clarified"],
                fierceUnderstanding: "用户表示目前不想继续讨论边界",
                finalNarrative: "保留用户不想继续讨论的边界。"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "接受拒绝并进入叙事"
        )

        let validated = try controller.validate(legacy, for: session)

        XCTAssertEqual(
            validated.memoryUpdate.candidUnderstanding,
            "用户表示目前不想继续讨论边界"
        )
    }

    func testCardConnectionCapabilitiesAllowOnlyOneScaffoldAndTwoConnections() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardConnectionAttemptCount = 1
        session.cardConnectionScaffoldUsed = true

        var permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.developCardImage))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.inviteCardConnection))

        session.cardConnectionAttemptCount = 2
        permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.developCardImage))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.inviteCardConnection))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.inviteCardObservation))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.authorizeCardGuidance))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))

        session.cardConnectionUnavailable = true
        permissions = controller.permissions(for: session)
        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.directCandidReflection, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedActions.contains(.shareCardGuidance))
    }

    @MainActor
    func testCommittedCardIntentsConsumeTheSingleScaffoldCapability() async {
        let scripted = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardImageRelation: "用户描述的画面关系"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "card_reality_connection_invited",
                            focus: "邀请一次现实联系"
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "邀请第一次现实联系"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardImageRelation: "支架后更具体的画面关系"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "card_image_scaffold_answered",
                            focus: "只使用一次画面内支架"
                        ),
                        replyIntent: .developCardImage,
                        replyGuidance: "第一次连接困难后使用唯一支架"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardImageRelation: "支架后更具体的画面关系"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "card_reality_connection_final",
                            focus: "最后一次邀请现实联系"
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "支架后的最后一次现实联系邀请"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConnection,
                        reply: "这个画面会让你想到现实中的哪一部分？"
                    )
                ),
                .success(
                    .init(
                        realizedIntent: .developCardImage,
                        reply: "先只看画面，你觉得这个变化会先影响哪里？"
                    )
                ),
                .success(
                    .init(
                        realizedIntent: .inviteCardConnection,
                        reply: "把你刚才补充的关系放回现实，会让你想到什么？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: scripted
        )
        func waitForIdle() async {
            try? await Task.sleep(for: .milliseconds(40))
            for _ in 0..<120 {
                if !model.isTyping && !model.isStreamingResponse { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
            XCTFail("Timed out waiting for the reflection turn")
        }
        model.session.protocolVersion = 2
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.cardDisplayState = .displayed

        model.draft = "画面里接下来可能会有变化。"
        model.send()
        await waitForIdle()
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertFalse(model.session.cardConnectionScaffoldUsed)

        model.draft = "我一下子有点想不到现实联系。"
        model.send()
        await waitForIdle()
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        XCTAssertFalse(
            controller.permissions(for: model.session)
                .allowedReplyIntents.contains(.developCardImage)
        )

        model.draft = "我觉得这会先改变画面的一小部分。"
        model.send()
        await waitForIdle()
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 2)
        XCTAssertFalse(model.session.cardConnectionScaffoldPending)
        let finalPermissions = controller.permissions(for: model.session)
        XCTAssertFalse(finalPermissions.allowedReplyIntents.contains(.developCardImage))
        XCTAssertFalse(finalPermissions.allowedReplyIntents.contains(.inviteCardConnection))
    }

    func testPendingCardMappingNarrowsPermissionsToResolutionOrClarification() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        session.semanticMemory.cardRealityMapping = "用户确认的现实映射"
        session.semanticMemory.cardNegotiatedMeaning = "已经显示、等待确认的协商式解读"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "pending-card-reading"
        )

        let permissions = controller.permissions(for: session)

        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.presentCardReading, .directCandidReflection, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.inviteCardObservation))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.inviteCardConnection))
    }

    func testRejectedCardMappingClearsCandidateBeforeDirectReflection() throws {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardNegotiatedMeaning = "尚在等待用户确认的候选解读"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "rejected-card-reading"
        )
        let rejected = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .rejected,
                referenceID: "rejected-card-reading"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "只提交拒绝结果，再由新回合决定后续反思"
        )

        let validated = try controller.validate(rejected, for: session)

        XCTAssertEqual(validated.requestedStage, .directReflection)
        XCTAssertEqual(validated.memoryUpdate.cardNegotiatedMeaning, "")
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
    }

    func testAcceptedCardMappingCannotBeMislabeledAsAnotherCardReading() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        session.semanticMemory.cardRealityMapping = "用户确认的现实映射"
        session.semanticMemory.cardNegotiatedMeaning = "已经显示、等待确认的协商式解读"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "accepted-card-reading"
        )
        let repeatedReading = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(cardNegotiatedMeaning: "错误地重复生成的解读"),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .accepted,
                referenceID: "accepted-card-reading"
            ),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "错误地重复卡牌解读"
        )

        XCTAssertThrowsError(try controller.validate(repeatedReading, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidConfirmationResolution
            )
        }
    }

    func testUnclearCardMappingMayClarifyAndReestablishConfirmation() throws {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        session.semanticMemory.cardRealityMapping = "用户确认的现实映射"
        session.semanticMemory.cardNegotiatedMeaning = "已经显示、等待确认的协商式解读"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "unclear-card-reading"
        )
        let clarification = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(cardNegotiatedMeaning: "澄清后的可修改解读"),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .unclear,
                referenceID: "unclear-card-reading"
            ),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "澄清用户没有理解的关系区别"
        )

        XCTAssertNoThrow(try controller.validate(clarification, for: session))
    }

    func testPlannerFacingMemoryUsesOnlyNextPromptAfterMigration() {
        var memory = TurnSemanticMemory(
            nextPrompt: .confirmationRequest(
                target: .cardMapping,
                referenceID: "new-source-of-truth"
            ),
            pendingQuestionPurpose: "confirm_cardMapping",
            pendingConfirmationTarget: .cardMapping,
            cardNegotiatedMeaning: "等待确认的解读"
        )

        let projected = memory.plannerFacingProjection()

        XCTAssertEqual(projected.nextPrompt, memory.nextPrompt)
        XCTAssertNil(projected.pendingQuestionPurpose)
        XCTAssertNil(projected.pendingConfirmationTarget)
        XCTAssertEqual(projected.cardNegotiatedMeaning, memory.cardNegotiatedMeaning)

        memory.nextPrompt = nil
        XCTAssertEqual(memory.plannerFacingProjection(), memory)
    }

    private func trackingCue(id: String) -> TrackingCue {
        let now = Date()
        let insight = TrackingInsight(
            id: UUID(),
            metric: .sleepDuration,
            observationWindow: DateInterval(
                start: now.addingTimeInterval(-604_800),
                end: now
            ),
            validSampleCount: 5,
            expectedSampleCount: 7,
            coverageDescription: "5/7 晚有记录",
            neutralObservation: "最近睡眠比个人近期水平短一些",
            baselineWindow: nil,
            baselineDescription: "与个人近期水平比较",
            absoluteDifference: -1_200,
            relativeDifference: -0.06,
            strength: .baselineComparison,
            confidence: .moderate,
            limitations: ["两晚缺少记录"],
            possibleConfounders: ["设备同步"],
            suggestedReflectionQuestion: "这和你记得的状态对得上吗？",
            provenance: [],
            recentMedian: 23_400,
            baselineMedian: 24_600,
            medianAbsoluteDeviation: 900,
            interquartileRange: 1_800,
            longestConsecutiveRun: 3,
            userRelevance: .notReviewed
        )
        return TrackingCue(
            id: id,
            source: .healthSleep,
            observation: insight.neutralObservation,
            insight: insight
        )
    }
}

@MainActor
final class ReflectionTurnControllerIntegrationTests: XCTestCase {
    func testSemanticPlanCriticRevisesDuplicateQuestionBeforeWriterRuns() async throws {
        let planner = RevisingTurnPlanner()
        let planCritic = RevisingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic
        )
        let session = ReflectionSession()
        var memory = TurnSemanticMemory()
        memory.situationUnderstanding =
            "A concrete event, its experienced impact, and its personal meaning are already understood."
        memory.answeredQuestionPurposes = [
            "event_sequence_clarified",
            "experienced_impact_clarified",
            "personal_meaning_clarified",
        ]
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .contextualDisclosure,
            condition: .directLLM,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [
                .init(role: .assistant, content: "这件事最近怎样影响你？"),
                .init(role: .user, content: "我已经说清楚它对我的影响了。"),
            ],
            semanticMemory: memory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let plannerCalls = await planner.callCount()
        let planCriticCalls = await planCritic.callCount()
        let lastTrigger = await planner.lastTrigger()

        XCTAssertEqual(result.replyIntent, .presentTenderSummary)
        XCTAssertEqual(result.requestedStage, .tenderConfirmation)
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertEqual(planCriticCalls, 2)
        XCTAssertEqual(lastTrigger, .protocolCorrection)
    }

    func testSemanticPlanCriticAdvancesUserAuthoredCardMappingWithoutFillerTurn() async throws {
        let planner = RevisingTurnPlanner()
        let planCritic = RevisingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic
        )
        var memory = TurnSemanticMemory()
        memory.tenderUnderstanding = "已经确认的基础情境"
        memory.cardImageRelation = "用户已经形成了一个画面关系"
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolPermissions(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none, .shareCardGuidance],
                allowedReplyIntents: [
                    .inviteCardConnection,
                    .authorizeCardGuidance,
                    .directCandidReflection,
                ]
            ),
            recentMessages: [
                .init(role: .assistant, content: "这个画面会让你想到现实中的什么吗？"),
                .init(role: .user, content: "这让我想到现实里正在面对的同一种关系。"),
            ],
            semanticMemory: memory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let plannerCalls = await planner.callCount()
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(result.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(result.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(result.memoryUpdate.cardRealityMapping, "用户刚刚形成的现实映射")
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertEqual(criticCalls, 2)
    }

    func testSemanticPlanCriticKeepsOneStrongestSupportedPractice() async throws {
        let planner = RevisingTurnPlanner()
        let planCritic = RevisingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic
        )
        var memory = TurnSemanticMemory()
        memory.finalNarrative = "已经确认、可以支持 care 与 change 两个不同方向的叙事"
        memory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-practice-options"
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .narrativeConfirmation,
            condition: .directLLM,
            permissions: ReflectionProtocolPermissions(
                currentStage: .narrativeConfirmation,
                allowedStages: [.optionalAction],
                allowedActions: [.none],
                allowedReplyIntents: [.suggestPractice]
            ),
            recentMessages: [
                .init(role: .assistant, content: "这段理解贴近吗？"),
                .init(role: .user, content: "贴近。"),
            ],
            semanticMemory: memory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let plannerCalls = await planner.callCount()
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(result.replyIntent, .suggestPractice)
        XCTAssertEqual(result.memoryUpdate.practiceOptions?.count, 1)
        XCTAssertNil(result.memoryUpdate.practiceKind)
        XCTAssertNil(result.memoryUpdate.selectedPractice)
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertEqual(criticCalls, 2)
    }

    func testCardDisplayedSystemEventDoesNotResolveConsumedConsentAgain() async throws {
        let echoedConsentPlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardConsent,
                decision: .accepted,
                referenceID: "already-consumed-consent"
            ),
            nextPrompt: .openQuestion(
                purpose: "observe_card_image",
                focus: "用户第一眼注意到的画面关系"
            ),
            replyIntent: .inviteCardObservation,
            replyGuidance: "图片已经显示，直接邀请用户观察"
        )
        let planner = StaticTurnPlanner(plan: echoedConsentPlan)
        let controller = RemoteReflectionTurnController(planner: planner)
        let request = LLMTurnControllerRequest(
            trigger: .cardDisplayed,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolPermissions(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.inviteCardObservation]
            ),
            recentMessages: [
                .init(role: .assistant, content: "你愿意抽一张卡吗？"),
                .init(role: .user, content: "好。"),
            ],
            semanticMemory: .init(nextPrompt: TurnNextPrompt.none),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let normalized = try await controller.plan(to: request)
        XCTAssertNil(normalized.resolvedConfirmation)
        XCTAssertEqual(normalized.replyIntent, .inviteCardObservation)
        XCTAssertEqual(normalized.nextPrompt?.kind, .openQuestion)
    }

    func testProtocolContinuationDoesNotResolveCommittedCardMappingAgain() async throws {
        let echoedResolutionPlan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .accepted,
                referenceID: "already-committed-mapping"
            ),
            nextPrompt: .openQuestion(
                purpose: "fierce_behavior_or_impact_clarified",
                focus: "现实中的一个具体行为或影响"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "生成进入现实反思后的第一条新问题"
        )
        let planner = StaticTurnPlanner(plan: echoedResolutionPlan)
        let controller = RemoteReflectionTurnController(planner: planner)
        let request = LLMTurnControllerRequest(
            trigger: .protocolContinuation,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolPermissions(
                currentStage: .directReflection,
                allowedStages: [.directReflection, .narrativeConfirmation],
                allowedActions: [.none],
                allowedReplyIntents: [.directCandidReflection, .presentFinalNarrative]
            ),
            recentMessages: [
                .init(role: .user, content: "我觉得贴近。"),
            ],
            semanticMemory: .init(nextPrompt: TurnNextPrompt.none),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let normalized = try await controller.plan(to: request)

        XCTAssertNil(normalized.resolvedConfirmation)
        XCTAssertEqual(normalized.replyIntent, .directCandidReflection)
        XCTAssertEqual(normalized.nextPrompt?.kind, .openQuestion)
    }

    func testSemanticCriticRevisesWriterWithoutReplanning() async throws {
        let planner = UnusedTurnPlanner()
        let writer = CriticTestWriter()
        let critic = CriticTestCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            writer: writer,
            critic: critic
        )
        let session = ReflectionSession()
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .contextualDisclosure,
            condition: .directLLM,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [
                .init(role: .user, content: "我最近很累，也开始很苛刻地评价自己。"),
            ],
            semanticMemory: .init(),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding: "当前的疲惫需要被承认，整体否定仍只是暂时判断"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "自然改写为一段可修改的 Tender 理解"
        )

        let result = try await controller.write(
            request: request,
            validatedPlan: plan
        )

        XCTAssertEqual(result.reply, "这是修订后更自然、没有字段拼接的总结。这样理解贴近吗？")
        let writerCounts = await writer.callCounts()
        let criticCalls = await critic.callCount()
        let plannerCalls = await planner.callCount()
        XCTAssertEqual(writerCounts.initial, 1)
        XCTAssertEqual(writerCounts.revisions, 1)
        XCTAssertEqual(criticCalls, 2)
        XCTAssertEqual(plannerCalls, 0)
    }

    func testVersionTwoSessionStartUsesLocalOpeningWithoutCallingTurnController() async {
        let firstGeneratedReply = "连续几次实验失败后，你开始怀疑自己的研究能力。现在最担心它会影响什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "连续实验失败触发了对研究能力的整体怀疑",
                            answeredQuestionPurposes: ["event_sequence_clarified"]
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "personal_meaning_clarified",
                            focus: "这次失败牵动的现实担心"
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "承接用户的具体经历和整体能力怀疑，继续理解现实担心"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: firstGeneratedReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = 2
        model.session.stage = .welcome
        model.session.messages = []

        model.begin()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(model.session.stage, .eventDisclosure)
        XCTAssertEqual(model.session.workflowPhase, .structuredDisclosure)
        XCTAssertEqual(model.session.messages.count, 1)
        XCTAssertEqual(
            model.session.messages.first?.content,
            "你好，我在这里。最近有什么事想聊聊吗？可以从刚发生的一件事说起。"
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "event_sequence_clarified"
        )
        XCTAssertNil(model.session.semanticMemory.nextPrompt?.target)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "local_protocol_opening_presented"
            }
        )
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 0)
        XCTAssertEqual(calls.writes, 0)

        model.draft = "实验又失败了，已经连续试了好几次。我开始怀疑自己是不是不适合做研究。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, firstGeneratedReply)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "personal_meaning_clarified"
        )
        let callsAfterFirstUserMessage = await controller.callCounts()
        XCTAssertEqual(callsAfterFirstUserMessage.plans, 1)
        XCTAssertEqual(callsAfterFirstUserMessage.writes, 1)
    }

    func testTrackingConfirmationMustShowTenderSummaryBeforeCardConsent() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let tenderReply = """
        最近工作挤在一起，又没有休息充分，可能让你更容易着急，也更难从错过截止时间的挫败里缓下来。不过，这些处境不能直接变成“什么都做不好”的结论。这段理解贴近吗？
        """
        let consentReply = "如果你愿意，接下来可以随机抽一张图卡，借画面换个角度继续看看。要现在抽吗？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .tenderConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(
                            pendingQuestionPurpose: "confirm_tender_summary",
                            pendingConfirmationTarget: .tenderSummary,
                            clearPendingQuestionPurpose: true,
                            trackingAssessments: [
                                .init(
                                    cueID: sleep.id,
                                    relevance: .related,
                                    userInterpretation: "用户认为休息不足让自己更容易着急"
                                ),
                            ],
                            tenderUnderstanding: "工作积压和休息不足可能增加了慌乱，但不能概括整体能力"
                        ),
                        replyIntent: .integrateTrackingAndPresentTenderSummary,
                        replyGuidance: "把用户确认的 tracking 关系和现实经历整合成简短 Tender 理解，只询问是否贴近"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .tenderConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(),
                        resolvedConfirmation: .init(
                            target: .tenderSummary,
                            decision: .accepted
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "用户已确认 Tender 理解；自然邀请一次随机抽卡，不提供行动建议"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .integrateTrackingAndPresentTenderSummary,
                        reply: tenderReply
                    )
                ),
                .success(.init(realizedIntent: .inviteCardConsent, reply: consentReply)),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.trackingCues = [sleep]
        model.session.presentedTrackingCueIDs = [sleep.id]
        model.session.semanticMemory.pendingQuestionPurpose = "tracking_relation_check"
        model.session.semanticMemory.pendingConfirmationTarget = .trackingRelationship

        model.draft = "我觉得对得上，最近确实没休息好，更容易着急。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .tenderConfirmation)
        XCTAssertEqual(model.session.messages.last?.content, tenderReply)
        XCTAssertEqual(
            model.session.semanticMemory.pendingConfirmationTarget,
            .tenderSummary
        )
        let firstRequests = await controller.receivedRequests()
        XCTAssertEqual(firstRequests.first?.presentedTrackingCues.map(\.id), [sleep.id])
        XCTAssertFalse(
            firstRequests.first?.trackingCandidates.contains(where: { $0.id == sleep.id }) ?? true
        )

        model.draft = "贴近"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.messages.last?.content, consentReply)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.target,
            .cardConsent
        )
        let allRequests = await controller.receivedRequests()
        XCTAssertTrue(allRequests.last?.presentedTrackingCues.isEmpty == true)
        let callCounts = await controller.callCounts()
        XCTAssertEqual(callCounts.plans, 2)
        XCTAssertEqual(callCounts.writes, 2)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_response_regeneration_requested")
                    || $0.action.contains("coarse_protocol_response_failed_twice")
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("5分钟")
            }
        )
    }

    func testVersionTwoCanPresentSeveralComplementaryTrackingCuesInOneTurn() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let activity = protocolTrackingCue(id: "activity")
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .init(
                            kind: .presentTrackingCue,
                            trackingCueIDs: [sleep.id, activity.id]
                        ),
                        memoryUpdate: .init(
                            pendingQuestionPurpose: "tracking_relation_check",
                            pendingConfirmationTarget: .trackingRelationship
                        ),
                        replyIntent: .presentTrackingContext,
                        replyGuidance: "把睡眠和活动变化作为一个可否认的生活背景，联系到用户刚才描述的具体处境"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentTrackingContext,
                        reply: "最近睡得少一些、走动也少一些，可能说明这段时间休息得不太够。放回刚才那件事里，你觉得这有没有让当时更难应对？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.trackingCues = [sleep, activity]

        model.draft = "最近事情一直堆着，我当时很难耐心处理。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.presentedTrackingCueIDs, [sleep.id, activity.id])
        XCTAssertTrue(model.session.messages.last?.content.contains("睡得少一些") == true)
        XCTAssertEqual(
            model.session.semanticMemory.pendingQuestionPurpose,
            "tracking_relation_check"
        )
    }

    func testNewTrackingTurnCanonicalizesOpenQuestionAndCommitsOneBatchAtomically() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let activity = protocolTrackingCue(id: "activity")
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .init(
                            kind: .presentTrackingCue,
                            trackingCueIDs: [sleep.id, activity.id]
                        ),
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "check_tracking_fit",
                            focus: "这些变化是否贴近用户的实际状态"
                        ),
                        replyIntent: .presentTrackingContext,
                        replyGuidance: "把两条互补变化放回用户已经描述的生活处境，并邀请确认"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentTrackingContext,
                        reply: "最近睡得少一些、走动也少一些。放回你刚才说的处境，这些变化和你的实际感受对得上吗？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.trackingCues = [sleep, activity]

        model.draft = "最近事情一直堆着，处理起来越来越吃力。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.trackingPresentations.count, 1)
        let presentation = try? XCTUnwrap(model.session.trackingPresentations.first)
        XCTAssertEqual(
            Set(presentation?.cueIDs ?? []),
            Set([sleep.id, activity.id])
        )
        XCTAssertEqual(model.session.activeTrackingPresentationID, presentation?.id)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.target,
            .trackingRelationship
        )
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.referenceID,
            presentation?.id
        )
        XCTAssertEqual(
            model.session.semanticMemory.pendingConfirmationTarget,
            .trackingRelationship
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_response_regeneration_requested")
                    || $0.action.contains("coarse_protocol_response_failed_twice")
            }
        )
    }

    func testOverallTrackingDecisionResolvesOnlyTheActivePresentationBatch() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let activity = protocolTrackingCue(id: "activity")
        let batchID = "tracking-batch"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .tenderConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(
                            tenderUnderstanding: "用户认为近期生活状态可能让当时更难应对，但不决定原因或责任"
                        ),
                        resolvedConfirmation: .init(
                            target: .trackingRelationship,
                            decision: .partlyRelated,
                            referenceID: batchID
                        ),
                        nextPrompt: .confirmationRequest(
                            target: .tenderSummary
                        ),
                        replyIntent: .integrateTrackingAndPresentTenderSummary,
                        replyGuidance: "使用整体 tracking 评价形成可修改的 Tender 理解"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .integrateTrackingAndPresentTenderSummary,
                        reply: "这些近期变化可能让当时更难应对，但并不能决定事情的原因或责任。这段理解贴近吗？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.trackingCues = [sleep, activity]
        model.session.presentedTrackingCueIDs = [sleep.id, activity.id]
        model.session.trackingPresentations = [
            .init(
                id: batchID,
                cueIDs: [sleep.id, activity.id],
                presentedAtUserTurnID: UUID()
            ),
        ]
        model.session.activeTrackingPresentationID = batchID
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .trackingRelationship,
            referenceID: batchID
        )

        model.draft = "有一点关系，但不是全部。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertNil(model.session.activeTrackingPresentationID)
        XCTAssertEqual(
            model.session.trackingPresentations.first?.resolution,
            .partlyRelated
        )
        XCTAssertTrue(model.session.semanticMemory.trackingAssessments.isEmpty)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.target,
            .tenderSummary
        )
        XCTAssertNotEqual(
            model.session.semanticMemory.nextPrompt?.referenceID,
            batchID
        )
    }

    func testAcceptedCardMappingCommitsSilentlyThenGeneratesFreshDirectReply() async {
        let mappingReference = "accepted-card-mapping"
        let directReply = "你已经看见这段距离也有保护作用。回到现实，你现在愿意为哪一个具体影响负责？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["card_mapping_confirmed"]
                        ),
                        resolvedConfirmation: .init(
                            target: .cardMapping,
                            decision: .accepted,
                            referenceID: mappingReference
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "fierce_behavior_or_impact_clarified",
                            focus: "一个具体行为或影响"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "只提交已经接受的卡牌映射"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "fierce_behavior_or_impact_clarified",
                            focus: "用户愿意承担的一个具体影响"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "基于现实材料提出一个新的坦诚反思问题"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: directReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        model.session.protocolVersion = 2
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.cardDisplayState = .displayed
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.cardImageRelation = "用户确认的画面关系"
        model.session.semanticMemory.cardRealityMapping = "用户确认的现实联系"
        model.session.semanticMemory.cardNegotiatedMeaning = "等待确认的候选解读"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: mappingReference
        )

        model.draft = "我觉得贴近。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.messages.last?.content, directReply)
        XCTAssertTrue(model.session.cardMappingConfirmed)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "fierce_behavior_or_impact_clarified"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_mapping_resolution_committed_before_continuation"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content == "local_card_mapping_resolution"
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
    }

    func testDirectTenderConfirmationMayContinueStraightToNarrativeWithoutFierce() async {
        let tenderReference = "accepted-tender-summary"
        let finalNarrative = "这次先承认失去带来的难受，也保留目前仍无法确定的部分，不要求自己马上形成责任或改变结论。"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["tender_confirmed"]
                        ),
                        resolvedConfirmation: .init(
                            target: .tenderSummary,
                            decision: .accepted,
                            referenceID: tenderReference
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "fierce_boundary_or_responsibility_clarified",
                            focus: "不应在确认事务中提前决定的问题"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "只提交 Tender 确认"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .narrativeConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(finalNarrative: finalNarrative),
                        nextPrompt: .confirmationRequest(target: .finalNarrative),
                        replyIntent: .presentFinalNarrative,
                        replyGuidance: "没有有依据且当前必要的 Fierce 机会，直接整合叙事"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentFinalNarrative,
                        reply: finalNarrative
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        model.session.protocolVersion = 2
        model.session.protocolStage = .tenderConfirmation
        model.session.stage = .tenderGrounding
        model.session.condition = .directLLM
        model.session.semanticMemory.tenderUnderstanding = "用户确认的 Tender 基础理解"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .tenderSummary,
            referenceID: tenderReference
        )

        model.draft = "这个理解贴近。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .narrativeConfirmation)
        XCTAssertEqual(model.session.messages.last?.content, finalNarrative)
        XCTAssertNil(model.session.semanticMemory.candidUnderstanding)
        XCTAssertEqual(model.session.reflectionReadiness, .narrativeReady)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "tender_summary_resolution_committed_before_continuation"
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
    }

    func testMissingFinalNarrativeLocksProgressAndRepairsSameOperation() async {
        let finalReply = "这次经历里，现实负担提供了背景，但你也已经看清需要承担的具体影响。这段整理贴近吗？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .narrativeConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: [
                                "fierce_behavior_or_impact_clarified",
                            ],
                            fierceUnderstanding: "用户最新确认愿意为具体影响负责"
                        ),
                        nextPrompt: .confirmationRequest(target: .finalNarrative),
                        replyIntent: .presentFinalNarrative,
                        replyGuidance: "呈现已经足够形成的最终叙事"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .narrativeConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: [
                                "fierce_behavior_or_impact_clarified",
                            ],
                            fierceUnderstanding: "用户最新确认愿意为具体影响负责",
                            finalNarrative: "整合后的最终叙事"
                        ),
                        nextPrompt: .confirmationRequest(target: .finalNarrative),
                        replyIntent: .presentFinalNarrative,
                        replyGuidance: "补全最终叙事对象并请求确认"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .presentFinalNarrative, reply: finalReply)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        model.session.protocolVersion = 2
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.reflectionReadiness = .needsFierce
        model.session.semanticMemory.tenderUnderstanding = "已确认的 Tender 理解"
        model.session.semanticMemory.fierceUnderstanding = "具体行为、影响和责任已经清楚"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_behavior_or_impact_clarified",
            focus: "已经回答的责任问题"
        )

        model.draft = "我愿意为那句话造成的影响负责。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .narrativeConfirmation)
        XCTAssertEqual(model.session.reflectionReadiness, .narrativeReady)
        XCTAssertEqual(model.session.semanticMemory.finalNarrative, "整合后的最终叙事")
        XCTAssertEqual(model.session.messages.last?.content, finalReply)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "reflection_readiness_locked_narrative_ready"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("暂时没有顺利接上")
            }
        )
    }

    func testAcceptedCardDrawShowsOnlyOneObservationReplyAfterImageDisplay() async {
        let consentReference = "card-consent-1"
        let observationReply = "先只看画面，你第一眼注意到了什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .init(kind: .drawRandomCard),
                        memoryUpdate: .init(),
                        resolvedConfirmation: .init(
                            target: .cardConsent,
                            decision: .accepted,
                            referenceID: consentReference
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .acknowledgeCardConsent,
                        replyGuidance: "用户已经同意；静默执行本地随机抽卡"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "observe_card_image",
                            focus: "用户第一眼注意到的画面"
                        ),
                        replyIntent: .inviteCardObservation,
                        replyGuidance: "直接邀请用户描述自己看到的画面，不重复抽卡或显示状态"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardObservation,
                        reply: observationReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        model.session.protocolVersion = 2
        model.session.protocolStage = .cardConsent
        model.session.condition = .cardMediated
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardConsent,
            referenceID: consentReference
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "你愿意随机抽一张卡看看吗？",
                state: .readinessCheck
            ),
        ]

        model.draft = "我愿意"
        model.send()
        await waitUntilIdle(model)

        let consentMessageID = model.session.messages.last(where: {
            $0.role == .user
        })?.id
        XCTAssertNotNil(consentMessageID)
        XCTAssertEqual(model.session.cardDisplayState, .selected)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.replyToMessageID == consentMessageID
            }
        )

        guard let cardID = model.session.card?.id else {
            return XCTFail("Expected a locally selected card")
        }
        model.cardDidDisplay(cardID: cardID)
        await waitUntilIdle(model)

        let replies = model.session.messages.filter {
            $0.role == .assistant && $0.replyToMessageID == consentMessageID
        }
        XCTAssertEqual(replies.map(\.content), [observationReply])
        XCTAssertEqual(model.session.cardDisplayState, .displayed)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)

        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
    }

    func testVersionTwoUsesCardGuidanceAfterUserAuthoredImageRealityMapping() async {
        let reading = """
        一种可能的读法是：你在画面里看到的是先了解眼前的东西，再决定怎样回应；放回现实，这也让你把“立刻答应”与“先确认自己能承担多少”分开了一些。这种理解贴近吗？
        """
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .init(kind: .shareCardGuidance),
                        memoryUpdate: .init(
                            cardImageRelation: "画面中的人先了解眼前的东西再决定如何回应",
                            cardRealityMapping: "现实中用户也需要先确认请求范围再决定是否答应",
                            cardNegotiatedMeaning: "尚未展示、不得提前提交的候选解读"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "check_card_mapping",
                            focus: "候选卡牌映射是否贴近"
                        ),
                        replyIntent: .presentCardReading,
                        replyGuidance: "申请卡片 guidance 并准备一段可修改的卡牌解读"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .confirmationRequest(
                            target: .cardMapping
                        ),
                        replyIntent: .presentCardReading,
                        replyGuidance: "结合已授权 guidance 呈现候选解读"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardNegotiatedMeaning: "先了解眼前的请求，再决定自己能够承担多少"
                        ),
                        nextPrompt: .confirmationRequest(
                            target: .cardMapping
                        ),
                        replyIntent: .presentCardReading,
                        replyGuidance: "结合用户的画面关系、现实映射和相交的卡片内涵，提出一段可修改或拒绝的综合解读"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: reading
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        model.session.protocolVersion = 2
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.messages = []

        model.draft = "像是先看看里面是什么，再决定要不要接下来。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let requests = await controller.receivedRequests()
        XCTAssertEqual(calls.plans, 3)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.messages.last?.content, reading)
        XCTAssertEqual(
            model.session.semanticMemory.cardNegotiatedMeaning,
            "先了解眼前的请求，再决定自己能够承担多少"
        )
        XCTAssertNil(requests.first?.card?.coreTension)
        XCTAssertNotNil(requests.last?.card?.coreTension)
        XCTAssertFalse(requests.last?.card?.selfKindnessDirections.isEmpty ?? true)
        XCTAssertTrue(
            requests.last?.protocolCorrection?.contains(
                "memoryUpdate.cardNegotiatedMeaning"
            ) == true
        )
    }

    func testVersionTwoDisplaysWriterReplyWithoutLegacyQuestionReplacement() async {
        let expected = "这次失败让你开始怀疑自己的研究能力。论文和毕业的担心里，哪一部分现在更压着你？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "实验失败触发了对研究能力的整体怀疑",
                            pendingQuestionPurpose: "clarify_personal_meaning"
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "承接实验失败后的能力怀疑，只澄清它牵动的现实担心"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .exploreContext, reply: expected)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "实验又失败了，我开始怀疑自己是不是根本不适合做研究。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, expected)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(
            model.session.semanticMemory.pendingQuestionPurpose,
            "clarify_personal_meaning"
        )
        XCTAssertFalse(
            model.session.messages.last?.content.contains("当时最明显的感受") == true
        )
    }

    func testWriterQuestionPunctuationMismatchDoesNotFailOrReplanTheTurn() async {
        let reply = "听起来你既后悔那句话，也担心这段关系。现在最想先说哪一部分？还有别的吗？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "用户后悔冲突中的表达并担心关系受损"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "understand_current_priority",
                            focus: "用户此刻最想继续表达的部分"
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "承接后悔和关系担心，开放地继续理解"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .exploreContext, reply: reply)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "我和朋友吵架后说了很重的话，现在很后悔。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(model.session.messages.last?.content, reply)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("writer_prompt_mismatch")
            }
        )
    }

    func testWriterIntentDriftRegeneratesWriterWithoutReplanning() async {
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                pendingQuestionPurpose: "clarify_effect"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "继续理解工作压力对日常状态的具体影响"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(plan)],
            writings: [
                .success(
                    .init(
                        realizedIntent: .suggestPractice,
                        reply: "你可以先做一个五分钟的小练习。"
                    )
                ),
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: "工作堆在一起的时候，最明显影响了你每天的哪一部分？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "最近工作很多，我觉得自己什么都做不好。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 2)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "工作堆在一起的时候，最明显影响了你每天的哪一部分？"
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("五分钟")
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_writer_regeneration_reason_writer_intent_mismatch")
            }
        )
    }

    func testWriterFailureRetriesSamePlanAndCommitsOnlyAfterVisibleReplySucceeds() async {
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "只在Writer成功后提交这段理解"
            ),
            nextPrompt: .openQuestion(
                purpose: "committed_question",
                focus: "当前最需要理解的影响"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "第一次 Writer 将失败"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(plan)],
            writings: [
                .failure(.exhausted),
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: "这件事现在最明显影响了你生活里的哪一部分？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "最近遇到一件让我很难受的事。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(
            model.session.semanticMemory.situationUnderstanding,
            "只在Writer成功后提交这段理解"
        )
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "committed_question"
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 2)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_writer_regeneration_requested"
            }
        )
    }

    func testInvalidPlanIsRejectedBeforeWriterAndRegeneratedOnce() async {
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        replyIntent: .inviteCardObservation,
                        replyGuidance: "非法跨越到卡牌阶段"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(),
                        replyIntent: .exploreContext,
                        replyGuidance: "留在当前阶段，承接用户对毕业的担心"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: "论文能否发表和能否毕业，好像都被这次失败一起带了出来。"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "我担心论文发不出去，也不能顺利毕业。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "论文能否发表和能否毕业，好像都被这次失败一起带了出来。"
        )
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        let requests = await controller.receivedRequests()
        let correction = requests.last?.protocolCorrection ?? ""
        XCTAssertTrue(correction.contains("\"component\":\"planner\""))
        XCTAssertTrue(correction.contains("\"currentStage\":\"contextualDisclosure\""))
        XCTAssertTrue(correction.contains("\"allowedReplyIntents\""))
        XCTAssertTrue(correction.contains("\"mustPreserve\""))
    }

    func testTwoInvalidPlansLeaveStageAndOfferRecoverableRetry() async {
        let illegal = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .none,
            memoryUpdate: .init(),
            replyIntent: .completeConversation,
            replyGuidance: "非法完成"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(illegal), .success(illegal)],
            writings: []
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "我还想继续说。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 0)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "我已经记下你刚才的回答，当前进度也保留着。这里暂时没有顺利接上；你可以点“重试”从这里继续，不需要重新回答。"
        )
        XCTAssertTrue(model.canRetry)
    }

    func testTypedRetryResumesStoredProtocolTurnWithoutAddingNewDisclosure() async {
        let illegal = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .none,
            memoryUpdate: .init(),
            replyIntent: .completeConversation,
            replyGuidance: "非法完成"
        )
        let recovered = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "relevant_context_clarified",
                focus: "继续一个尚未回答的现实关系"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接原来的用户回答，不把重试当成新披露"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(illegal), .success(illegal), .success(recovered)],
            writings: [
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: "我们从刚才停下的位置继续。那件事里，还有哪项现实情况最需要放进来一起看？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "这是需要被保留的原始回答。"
        model.send()
        await waitUntilIdle(model)
        let userCountBeforeRetry = model.session.messages.filter { $0.role == .user }.count
        XCTAssertTrue(model.canRetry)

        model.draft = "重试"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(
            model.session.messages.filter { $0.role == .user }.count,
            userCountBeforeRetry
        )
        XCTAssertEqual(
            model.session.messages.last?.content,
            "我们从刚才停下的位置继续。那件事里，还有哪项现实情况最需要放进来一起看？"
        )
        XCTAssertFalse(model.canRetry)
    }

    func testMissingPracticeOptionsDoesNotShowTechnicalInterruption() async {
        let practiceReply = "可以先试一个很小的步骤：今晚留出十分钟休息。这个建议可以修改或拒绝，你觉得合适吗？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .optionalAction,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["narrative_confirmed"]
                        ),
                        resolvedConfirmation: .init(
                            target: .finalNarrative,
                            decision: .accepted,
                            referenceID: "narrative-1"
                        ),
                        nextPrompt: .confirmationRequest(target: .practice),
                        replyIntent: .suggestPractice,
                        replyGuidance: "提出一个具体、低负担、可以修改或拒绝的实践"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .suggestPractice,
                        reply: practiceReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.protocolStage = .narrativeConfirmation
        model.session.stage = .attributionReflection
        model.session.semanticMemory.finalNarrative = "已经等待确认的最终叙事"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )

        model.draft = "这段叙事准确，可以继续。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(model.session.messages.last?.content, practiceReply)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_soft_warning_missingPracticeOptions"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant
                    && $0.content == "刚才的回复暂时没有生成成功。你刚才说的内容还在，可以稍后再试。"
            }
        )
    }

    func testRecoverableWriterRetryKeepsValidatedPlannerPlan() async {
        let visibleReply = "你已经说到这件事让自己很难受。现在最希望先被理解的是哪一部分？"
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "用户描述了事件带来的持续困扰"
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify_current_need",
                focus: "用户此刻最希望被理解的部分"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接最新回答，继续理解当前需要"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(plan)],
            writings: [
                .failure(.exhausted),
                .failure(.exhausted),
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: visibleReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "这件事最近一直压着我。"
        model.send()
        await waitUntilIdle(model)

        var counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 2)
        XCTAssertTrue(model.canRetry)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)

        model.retryLastRequest()
        await waitUntilIdle(model)

        counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1, "Writer recovery must not re-run the Planner")
        XCTAssertEqual(counts.writes, 3)
        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.session.messages.last?.content, visibleReply)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
    }

    func testPlannerDecodeFailureRecordsSafeDiagnosticBeforeRecoverablePause() async {
        let diagnostic = TurnPlannerDecodingDiagnostic(
            kind: "data_corrupted",
            keyPath: "memoryUpdate.trackingAssessments.Index 0.relevance",
            invalidTrackingRelevance: "confirmed"
        )
        let controller = PlannerDecodeFailingTurnController(diagnostic: diagnostic)
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)

        model.draft = "我觉得最近没休息好，确实让我更难应对。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCount()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "我已经记下你刚才的回答，当前进度也保留着。这里暂时没有顺利接上；你可以点“重试”从这里继续，不需要重新回答。"
        )
        XCTAssertTrue(model.canRetry)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.contains(
                    "final_failure_planner_decode_data_corrupted"
                ) &&
                $0.action.contains("trackingAssessments") &&
                $0.action.contains("invalid_tracking_relevance_confirmed")
            }
        )
    }

    private func prepareVersionTwoDisclosure(_ model: ReflectionViewModel) {
        model.session.protocolVersion = 2
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.messages = []
    }

    private func waitUntilIdle(_ model: ReflectionViewModel) async {
        // `send()` schedules the response task; give the main actor one turn to enter it before
        // treating an initially-false `isTyping` value as completion.
        try? await Task.sleep(for: .milliseconds(40))
        for _ in 0..<120 {
            if !model.isTyping && !model.isStreamingResponse { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the reflection turn")
    }
}

private func protocolTrackingCue(id: String) -> TrackingCue {
    let now = Date()
    let insight = TrackingInsight(
        id: UUID(),
        metric: id == "sleep" ? .sleepDuration : .steps,
        observationWindow: DateInterval(
            start: now.addingTimeInterval(-604_800),
            end: now
        ),
        validSampleCount: 6,
        expectedSampleCount: 7,
        coverageDescription: "6/7 天有记录",
        neutralObservation: id == "sleep"
            ? "最近睡眠比个人近期水平短一些"
            : "最近走动比个人近期水平少一些",
        baselineWindow: nil,
        baselineDescription: "与个人近期水平比较",
        absoluteDifference: -900,
        relativeDifference: -0.05,
        strength: .baselineComparison,
        confidence: .moderate,
        limitations: [],
        possibleConfounders: [],
        suggestedReflectionQuestion: "这些变化和你的实际感受对得上吗？",
        provenance: [],
        recentMedian: 10_000,
        baselineMedian: 11_000,
        medianAbsoluteDeviation: 500,
        interquartileRange: 1_000,
        longestConsecutiveRun: 4,
        userRelevance: .notReviewed
    )
    return TrackingCue(
        id: id,
        source: id == "sleep" ? .healthSleep : .healthSteps,
        observation: insight.neutralObservation,
        insight: insight
    )
}

private enum ScriptedTurnError: Error {
    case exhausted
}

private actor UnusedTurnPlanner: LLMTurnPlanning {
    private var calls = 0

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        throw ScriptedTurnError.exhausted
    }

    func callCount() -> Int { calls }
}

private actor StaticTurnPlanner: LLMTurnPlanning {
    let plan: LLMTurnResponsePlan

    init(plan: LLMTurnResponsePlan) {
        self.plan = plan
    }

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        plan
    }
}

private actor RevisingTurnPlanner: LLMTurnPlanning {
    private var calls = 0
    private var latestTrigger: LLMTurnTrigger?

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        latestTrigger = request.trigger
        if request.protocolStage == .cardReflection {
            if calls == 1 {
                return LLMTurnResponsePlan(
                    requestedStage: .cardReflection,
                    localAction: .none,
                    memoryUpdate: .init(),
                    nextPrompt: .openQuestion(
                        purpose: "repeat_card_connection",
                        focus: "再次询问用户已经给出的画面—现实联系"
                    ),
                    replyIntent: .inviteCardConnection,
                    replyGuidance: "只确认已经形成的映射，稍后再给解读"
                )
            }
            return LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .init(kind: .shareCardGuidance),
                memoryUpdate: .init(
                    cardRealityMapping: "用户刚刚形成的现实映射"
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .authorizeCardGuidance,
                replyGuidance: "静默授权卡牌引导，并立即自动生成实质解读"
            )
        }
        if request.protocolStage == .narrativeConfirmation {
            let care = TurnPracticeOption(
                id: "care-1",
                kind: .care,
                title: "先安排恢复",
                instruction: "今晚留出十分钟照顾已经确认的疲惫。",
                rationale: "这回应了当前的消耗。"
            )
            let change = TurnPracticeOption(
                id: "change-1",
                kind: .change,
                title: "检查一个可控部分",
                instruction: "下一次只记录一个事实和一个可以检查的部分。",
                rationale: "这回应了已经确认的可控行为。"
            )
            return LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(
                    practiceOptions: calls == 1 ? [care] : [change]
                ),
                resolvedConfirmation: .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: "narrative-practice-options"
                ),
                nextPrompt: .confirmationRequest(target: .practice),
                replyIntent: .suggestPractice,
                replyGuidance: calls == 1
                    ? "给出一个较弱的候选"
                    : "只给出证据最充分的完整候选"
            )
        }
        if calls == 1 {
            return LLMTurnResponsePlan(
                requestedStage: .contextualDisclosure,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .openQuestion(
                    purpose: "topic_specific_feeling_explored",
                    focus: "Ask again how the situation feels and what the person hopes will happen."
                ),
                replyIntent: .exploreContext,
                replyGuidance: "Ask the near-duplicate question."
            )
        }
        return LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                tenderUnderstanding:
                    "The concrete experience and its impact can now be reflected without a whole-person judgment."
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "Present one correctable Tender summary."
        )
    }

    func callCount() -> Int { calls }
    func lastTrigger() -> LLMTurnTrigger? { latestTrigger }
}

private actor RevisingPlanCritic: LLMTurnPlanCritiquing {
    private var calls = 0

    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        calls += 1
        if calls == 1 {
            return .init(
                verdict: .revisePlanner,
                reasonCodes: [
                    "duplicate_question_function",
                    "overfilled_focus",
                    "tender_summary_ready",
                ],
                revisionGuidance:
                    "Remove the repeated function and use the allowed correctable Tender summary."
            )
        }
        return .init(
            verdict: .pass,
            reasonCodes: [],
            revisionGuidance: nil
        )
    }

    func callCount() -> Int { calls }
}

private actor CriticTestWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "你最近很累、你又很否定自己、这段理解贴近吗？"
        )
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        revisionCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "这是修订后更自然、没有字段拼接的总结。这样理解贴近吗？"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor CriticTestCritic: LLMTurnCritiquing {
    private var calls = 0

    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse {
        calls += 1
        if calls == 1 {
            return .init(
                verdict: .reviseWriter,
                reasonCodes: ["field_stitching"],
                revisionGuidance: "重写成一个连贯自然段"
            )
        }
        return .init(
            verdict: .pass,
            reasonCodes: [],
            revisionGuidance: nil
        )
    }

    func callCount() -> Int { calls }
}

private actor PlannerDecodeFailingTurnController: ReflectionTurnControlling {
    private let diagnostic: TurnPlannerDecodingDiagnostic
    private var calls = 0

    init(diagnostic: TurnPlannerDecodingDiagnostic) {
        self.diagnostic = diagnostic
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        throw LLMTurnControllerClientError.plannerDecoding(diagnostic)
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        XCTFail("Writer must not run after a Planner decode failure")
        throw ScriptedTurnError.exhausted
    }

    func callCount() -> Int {
        calls
    }
}

private actor ScriptedReflectionTurnController: ReflectionTurnControlling {
    private var plans: [Result<LLMTurnResponsePlan, ScriptedTurnError>]
    private var writings: [Result<LLMTurnWriterResponse, ScriptedTurnError>]
    private var planCalls = 0
    private var writeCalls = 0
    private var requests: [LLMTurnControllerRequest] = []

    init(
        plans: [Result<LLMTurnResponsePlan, ScriptedTurnError>],
        writings: [Result<LLMTurnWriterResponse, ScriptedTurnError>]
    ) {
        self.plans = plans
        self.writings = writings
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        planCalls += 1
        requests.append(request)
        guard !plans.isEmpty else { throw ScriptedTurnError.exhausted }
        return try plans.removeFirst().get()
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        writeCalls += 1
        guard !writings.isEmpty else { throw ScriptedTurnError.exhausted }
        return try writings.removeFirst().get()
    }

    func callCounts() -> (plans: Int, writes: Int) {
        (planCalls, writeCalls)
    }

    func receivedRequests() -> [LLMTurnControllerRequest] {
        requests
    }
}

private struct UnusedContextAnalyzer: ContextAnalyzing {
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage]
    ) async -> ContextAnalysis {
        XCTFail("Legacy ContextAnalyzer must not run in protocol version 2")
        return ContextAnalysis()
    }
}

private struct UnusedDialogueGenerator: DialogueGenerating {
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
        XCTFail("Legacy DialogueGenerator must not run in protocol version 2")
        return DialogueTurn(reflection: "", question: "", actionOptions: [])
    }
}
