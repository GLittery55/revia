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

        let legacyEpisode = try JSONDecoder().decode(
            TurnEpisodeStructure.self,
            from: Data(
                #"{"concreteFacts":["一件已经发生的事"],"behaviorEvidenceStatus":"present","behaviorEvidence":["一个已报告的行为"]}"#.utf8
            )
        )
        XCTAssertEqual(legacyEpisode.eventProcessStatus, .unresolved)

        var current = ReflectionSession()
        current.protocolVersion = 2
        current.protocolStage = .directReflection
        current.semanticMemory.situationUnderstanding = "已形成一段可修正的处境理解"
        current.semanticMemory.episodeStructure = .init(
            concreteFacts: ["已经连续三次没有开始"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["连续三次没有开始"],
            impactStatus: .present,
            impacts: ["后续进度受到影响"],
            keyUncertainty: "开始时的阻力未知"
        )
        let supersededMessageID = UUID()
        current.supersededAssistantMessageIDs = [supersededMessageID]
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
        XCTAssertEqual(
            decoded.semanticMemory.episodeStructure?.behaviorEvidenceStatus,
            .present
        )
        XCTAssertEqual(
            decoded.semanticMemory.episodeStructure?.impacts,
            ["后续进度受到影响"]
        )
        XCTAssertEqual(decoded.supersededAssistantMessageIDs, Set([supersededMessageID]))
        XCTAssertEqual(decoded.cardConnectionAttemptCount, 1)
        XCTAssertTrue(decoded.cardConnectionScaffoldUsed)
        XCTAssertEqual(decoded.contextualLoadInference?.state, .possiblyElevated)
        XCTAssertEqual(decoded.contextualLoadInference?.energy, .possiblyReduced)

        var priorDirectSession = decoded
        priorDirectSession.condition = .directLLM
        XCTAssertFalse(priorDirectSession.usesSimpleGentleControl)
        priorDirectSession.protocolVersion = ReflectionSession.currentProtocolVersion
        XCTAssertTrue(priorDirectSession.usesSimpleGentleControl)
    }

    func testPartialEpisodePatchPreservesPriorFocalEventAndStillRequiresBehavior() throws {
        let update = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(
                #"{"episodeStructure":{"eventProcessStatus":"present","possibleContributors":["用户说明了事情形成过程中的一个具体环节"]}}"#.utf8
            )
        )

        var memory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体尝试没有得到预期结果"],
                behaviorEvidenceStatus: .unresolved,
                eventProcessStatus: .unresolved,
                impactStatus: .unresolved
            )
        )
        memory.apply(update)

        XCTAssertEqual(
            memory.episodeStructure?.concreteFacts,
            ["一次具体尝试没有得到预期结果"]
        )
        XCTAssertEqual(memory.episodeStructure?.behaviorEvidenceStatus, .unresolved)
        XCTAssertEqual(memory.episodeStructure?.eventProcessStatus, .present)
        XCTAssertEqual(
            memory.episodeStructure?.possibleContributors,
            ["用户说明了事情形成过程中的一个具体环节"]
        )

        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体尝试没有得到预期结果"],
                behaviorEvidenceStatus: .unresolved,
                eventProcessStatus: .unresolved,
                impactStatus: .unresolved
            )
        )
        let impactQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: update,
            nextPrompt: .openQuestion(
                purpose: "actual_result_clarified",
                focus: "这次经历实际造成的结果",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问尚未说明的实际结果"
        )

        XCTAssertThrowsError(try controller.validate(impactQuestion, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidDisclosureQuestionTarget(.behavior)
            )
        }
    }

    func testEmptyEpisodePatchCannotReopenResolvedEvidenceWithoutAStatusCorrection() throws {
        var memory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体经历"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户已经说明了一个具体行为"],
                eventProcessStatus: .present,
                impactStatus: .present,
                impacts: ["用户已经说明了一个实际结果"]
            )
        )
        let accidentalClear = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(
                #"{"episodeStructure":{"behaviorEvidenceStatus":"present","behaviorEvidence":[],"eventProcessStatus":"present","possibleContributors":[],"contextualConstraints":[],"controllableParts":[],"impactStatus":"present","impacts":[]}}"#.utf8
            )
        )

        memory.apply(accidentalClear)

        XCTAssertEqual(
            memory.episodeStructure?.behaviorEvidence,
            ["用户已经说明了一个具体行为"]
        )
        XCTAssertEqual(
            memory.episodeStructure?.impacts,
            ["用户已经说明了一个实际结果"]
        )

        var disclosureSession = ReflectionSession()
        disclosureSession.protocolVersion = ReflectionSession.currentProtocolVersion
        disclosureSession.protocolStage = .contextualDisclosure
        disclosureSession.condition = .cardMediated
        disclosureSession.semanticMemory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体经历"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户已经说明了一个具体行为"],
                eventProcessStatus: .present,
                impactStatus: .unresolved
            )
        )
        let impactQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: accidentalClear,
            nextPrompt: .openQuestion(
                purpose: "actual_impact_clarified",
                focus: "事情产生的实际影响",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问仍未解决的实际影响"
        )
        XCTAssertThrowsError(
            try ReflectionProtocolController().validate(
                impactQuestion,
                for: disclosureSession
            )
        ) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .illegalReplyIntent
            )
        }

        let explicitCorrection = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(
                #"{"episodeStructure":{"behaviorEvidenceStatus":"absent","behaviorEvidence":[],"eventProcessStatus":"absent","possibleContributors":[],"contextualConstraints":[],"controllableParts":[],"impactStatus":"absent","impacts":[]}}"#.utf8
            )
        )
        memory.apply(explicitCorrection)

        XCTAssertEqual(memory.episodeStructure?.behaviorEvidenceStatus, .absent)
        XCTAssertEqual(memory.episodeStructure?.behaviorEvidence, [])
        XCTAssertEqual(memory.episodeStructure?.eventProcessStatus, .absent)
        XCTAssertEqual(memory.episodeStructure?.impactStatus, .absent)
        XCTAssertEqual(memory.episodeStructure?.impacts, [])
    }

    func testCurrentDisclosureAllowsOnlyMissingCoreQuestionTargets() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体尝试没有得到预期结果"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户已经描述了自己在过程中采取的行动"],
                eventProcessStatus: .unresolved,
                impactStatus: .unresolved
            )
        )

        let impactFirst = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "actual_result_clarified",
                focus: "这次经历实际造成的结果",
                disclosurePurpose: .clarifyBehavior,
                disclosureTarget: .behavior
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接用户刚才对结果的描述，先询问实际影响"
        )

        XCTAssertThrowsError(try controller.validate(impactFirst, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidDisclosureQuestionTarget(.eventProcess)
            )
        }

        let processQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "event_process_clarified",
                focus: "事情怎样发展到这个结果",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "询问仍未解决的事件过程"
        )
        XCTAssertNoThrow(try controller.validate(processQuestion, for: session))
    }

    func testBehaviorAndResolvedProcessAdvanceWithoutImpactQuestion() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let impactQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                selfCriticismStatus: .present,
                selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
                episodeStructure: .init(
                    concreteFacts: ["一次具体尝试没有得到预期结果"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户描述了过程中采取的具体行动"],
                    eventProcessStatus: .present,
                    impactStatus: .unresolved
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "actual_result_clarified",
                focus: "这次经历实际造成的结果",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "过程已经得到描述，不要求用户继续寻找确定原因"
        )

        XCTAssertThrowsError(try controller.validate(impactQuestion, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .disclosureShouldAdvance
            )
        }
    }

    func testReadyDisclosureAllowsUnresolvedImpactAndDirectCardInvitation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let ready = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard,
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情及其直接结果"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户明确说明了自己的行为"],
                    eventProcessStatus: .present,
                    possibleContributors: ["事情如何发展已经得到说明"],
                    impactStatus: .unresolved
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "同一回复内进行 grounding 并邀请随机反思卡"
        )

        XCTAssertNoThrow(try controller.validate(ready, for: session))
    }

    func testCoreEpisodeCanInviteCardWithoutImpactEmotionOrReflectionFocus() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let invitation = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard,
                episodeStructure: .init(
                    concreteFacts: ["用户答应去接家人但最后没有去"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["临时和朋友吃饭且没有提前告诉家人"],
                    eventProcessStatus: .present,
                    possibleContributors: ["原来的接人安排临时改变"]
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "只做事实承接并邀请随机反思卡"
        )

        XCTAssertNoThrow(try controller.validate(invitation, for: session))
    }

    func testStoredCoreEpisodeExposesOnlyForwardCardInvitation() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["用户答应去接家人但最后没有去"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["临时和朋友吃饭且没有提前告知"],
            eventProcessStatus: .present,
            possibleContributors: ["原来的安排临时改变"]
        )

        let permissions = controller.permissions(for: session)

        XCTAssertFalse(permissions.allowedReplyIntents.contains(.exploreContext))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.inviteCardConsent))
        XCTAssertTrue(permissions.allowedDisclosurePurposes.isEmpty)
        XCTAssertTrue(permissions.allowedDisclosureTargets.isEmpty)
    }

    func testBehaviorEvidenceStatusAndContentMustRemainStructurallyConsistent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure

        let missingContent = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: []
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify behavior",
                focus: "用户在事情中的处理",
                disclosurePurpose: .clarifyBehavior,
                disclosureTarget: .behavior
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问尚未形成的行为关系"
        )
        XCTAssertThrowsError(try controller.validate(missingContent, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .incompleteEpisodeStructure([.behaviorEvidence])
            )
        }

        let missingStatus = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情"],
                    behaviorEvidenceStatus: .unresolved,
                    behaviorEvidence: ["用户明确说明了自己的行为"]
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify process",
                focus: "事情如何发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问尚未形成的过程关系"
        )
        XCTAssertThrowsError(try controller.validate(missingStatus, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .incompleteEpisodeStructure([.behaviorEvidenceStatus])
            )
        }
    }

    func testCompletedCoreCannotBeReopenedAsAnotherDisclosureQuestion() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.receivedDisclosureQuestionPurposes = [.clarifyEventProcess]
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["一件具体事情"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["一个明确行为"],
            eventProcessStatus: .present,
            possibleContributors: ["一个已经形成的过程关系"]
        )

        func plan(reopen: TurnDisclosureReopenReason?) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .contextualDisclosure,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .openQuestion(
                    purpose: "a completely different free-text label",
                    focus: "同一事件过程",
                    disclosurePurpose: .clarifyEventProcess,
                    disclosureTarget: .eventProcess,
                    disclosureReopenReason: reopen
                ),
                replyIntent: .exploreContext,
                replyGuidance: "保留同一个 typed purpose"
            )
        }

        XCTAssertThrowsError(try controller.validate(plan(reopen: nil), for: session))
        XCTAssertThrowsError(
            try controller.validate(
                plan(reopen: .userCorrectedPreviousFact),
                for: session
            )
        )
    }

    func testPreviousTypedQuestionIsMarkedReceivedBeforeNewPlanCommits() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "prior process question",
            focus: "事情如何发展",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )

        session.condition = .cardMediated
        let next = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard,
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户的明确行为"],
                    eventProcessStatus: .present,
                    possibleContributors: ["事情的发展已经说明"]
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "简短承接并邀请随机反思卡"
        )

        let validated = try controller.validate(next, for: session)
        XCTAssertEqual(
            validated.memoryUpdate.receivedDisclosureQuestionPurposes,
            [.clarifyEventProcess]
        )
    }

    func testOnlyCoreDisclosureMetadataGatesCardConsent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        let episode = TurnEpisodeStructure(
            concreteFacts: ["一件具体事情及其直接结果"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["一个明确行为"],
            eventProcessStatus: .present,
            possibleContributors: ["事情的发展已经说明"]
        )

        func bridge() -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .cardConsent,
                localAction: .none,
                memoryUpdate: .init(
                    eventDisclosureOutcome: .readyForTenderOrCard,
                    episodeStructure: episode
                ),
                nextPrompt: .confirmationRequest(target: .cardConsent),
                replyIntent: .inviteCardConsent,
                replyGuidance: "grounding 与邀请在同一回复"
            )
        }

        XCTAssertNoThrow(
            try controller.validate(
                bridge(),
                for: session
            )
        )
    }

    func testSimpleGentleReplyValidatorEnforcesOnlyDeterministicShape() throws {
        let validator = SimpleGentleReflectionReplyValidator()

        XCTAssertEqual(
            try validator.validate(
                "这段经历确实让人很难受。现在最占据你注意力的是什么？"
            ),
            "这段经历确实让人很难受。现在最占据你注意力的是什么？"
        )
        XCTAssertThrowsError(
            try validator.validate(
                "你现在是什么感受？你希望接下来怎样？"
            )
        ) {
            XCTAssertEqual(
                $0 as? SimpleGentleReflectionViolation,
                .multipleQuestions
            )
        }
        let prompt = ReflectionPromptFactory().simpleGentleReflectionPrompt(
            recentMessages: [
                .init(role: .user, content: "一段需要温和回应的经历"),
            ],
            correction: nil
        )
        XCTAssertTrue(prompt.system.contains("Do not ask the user to rate, approve"))
        XCTAssertTrue(prompt.system.contains("hidden-motive claims"))
    }

    func testSafetyServiceRecognizesAdditionalDirectRiskLanguage() {
        let service = SafetyService()

        XCTAssertTrue(service.requiresInterrupt("我觉得自己快活不下去了"))
        XCTAssertTrue(service.requiresInterrupt("有时候会想到伤害我自己"))
        XCTAssertFalse(service.requiresInterrupt("我今天只是觉得有些挫败"))
    }

    func testContextualDisclosureDoesNotExposeASeparateTrackingAction() throws {
        var session = protocolSession(stage: .contextualDisclosure)
        let first = trackingCue(id: "sleep")
        let second = trackingCue(id: "steps")
        session.trackingCues = [first, second]

        let permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedActions.contains(.presentTrackingCue))
        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.exploreContext, .presentTenderSummary, .safetySupport])
        )

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

    func testCurrentCardDisclosureUsesDirectBridgeInsteadOfSeparateTenderTurn() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "self_criticism_clarified",
            focus: "用户在具体失败后如何评价自己"
        )

        let permissions = controller.permissions(for: session)
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.inviteCardConsent))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentTenderSummary))
        XCTAssertFalse(permissions.allowedStages.contains(.directReflection))

        let missingSelfCriticism = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "app 反复修改仍没有达到预期",
                tenderUnderstanding: "当前版本的问题不能直接概括整体能力"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "简短呈现可修正的事件理解"
        )
        XCTAssertThrowsError(try controller.validate(missingSelfCriticism, for: session))

        let missingCriticismLink = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                selfCriticismStatus: .present,
                selfCriticalStatement: "用户担心这说明自己能力不足",
                episodeStructure: .init(
                    concreteFacts: ["一次具体结果没有达到预期"],
                    behaviorEvidenceStatus: .uncertain,
                    eventProcessStatus: .uncertain,
                    impactStatus: .uncertain,
                    keyUncertainty: "事情如何发展目前不清楚"
                ),
                tenderUnderstanding: "结果需要被承认，但不能自动证明整体能力"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "缺少事实与自我评价之间的关系"
        )
        XCTAssertThrowsError(try controller.validate(missingCriticismLink, for: session))

        let groundedBridge = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                selfCriticismStatus: .present,
                selfCriticalStatement: "用户担心这说明自己能力不足",
                selfCriticismLink: "用户把当前结果不理想视为自己可能能力不足的证据",
                episodeStructure: .init(
                    concreteFacts: ["app 反复修改仍没有达到预期"],
                    behaviorEvidenceStatus: .uncertain,
                    eventProcessStatus: .uncertain,
                    impactStatus: .uncertain,
                    keyUncertainty: "目前还不清楚问题主要来自哪里"
                ),
                tenderUnderstanding: "结果没有达到预期是事实，但原因仍不清楚，不能直接概括整体能力"
            ),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "呈现一段简短、可修正的现实—自我评价理解"
        )
        XCTAssertThrowsError(try controller.validate(groundedBridge, for: session))
    }

    func testCurrentTenderClarificationDoesNotRequireStoredUnderstanding() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .tenderConfirmation
        session.condition = .cardMediated
        session.semanticMemory.tenderUnderstanding = "已经展示并保存的 Tender 理解"
        session.semanticMemory.nextPrompt = .confirmationRequest(target: .tenderSummary)

        let clarification = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .requestTenderConfirmation,
            replyGuidance: "自然承接含糊回答，不重复改写已保存内容"
        )

        XCTAssertNoThrow(try controller.validate(clarification, for: session))

        session.semanticMemory.tenderUnderstanding = nil
        XCTAssertNoThrow(try controller.validate(clarification, for: session))
    }

    func testCompleteCardDisclosureKeepsQuestionOrDirectConsentAvailable() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.structuredDisclosureAssistantTurns = 1
        session.semanticMemory.situationUnderstanding =
            "一项承诺没有按原计划推进，并已经产生具体影响"
        session.semanticMemory.selfCriticismStatus = .present
        session.semanticMemory.selfCriticalStatement = "用户据此形成了整体自我评价"
        session.semanticMemory.selfCriticismLink =
            "用户把一个未完成的具体步骤扩展成了对整个人的评价"
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["原计划中的一个步骤没有完成"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["该步骤确实没有完成"],
            eventProcessStatus: .uncertain,
            impactStatus: .present,
            impacts: ["后续安排受到影响"],
            keyUncertainty: "造成停滞的主要条件仍不明确"
        )

        let permissions = controller.permissions(for: session)

        XCTAssertTrue(permissions.allowedReplyIntents.contains(.exploreContext))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentTenderSummary))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.inviteCardConsent))
        XCTAssertTrue(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .cardConsent,
                    replyIntent: .inviteCardConsent,
                    localAction: .none
                )
            )
        )
    }

    func testCurrentCardDisclosureCanEnterConsentWithoutTenderUnderstanding() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let bridge = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "一件具体事情及用户的主要处理已经形成连贯叙述",
                eventDisclosureOutcome: .readyForTenderOrCard,
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情已经发生"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户说明了自己采取或没有采取的处理"],
                    eventProcessStatus: .present,
                    possibleContributors: ["用户说明了事情如何发展"],
                    impactStatus: .unresolved
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "用轻量、不羞辱的承接邀请一张随机反思卡"
        )

        XCTAssertNil(bridge.memoryUpdate.tenderUnderstanding)
        XCTAssertNoThrow(try controller.validate(bridge, for: session))

        let lightTender = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "在不制造整体自我判断时进行一次轻量过渡"
        )
        XCTAssertThrowsError(try controller.validate(lightTender, for: session))
    }

    func testCurrentDisclosureSwiftDoesNotJudgeStoryReadiness() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "concrete_impact_clarified",
            focus: "尚未明确的现实影响",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )

        let stalledPlan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "一项承诺没有推进并影响后续安排",
                answeredQuestionPurposes: ["concrete_impact_clarified"],
                selfCriticismStatus: .present,
                selfCriticalStatement: "用户据此形成了整体自我评价",
                selfCriticismLink: "用户把未完成的具体步骤扩展成了整体自我评价",
                episodeStructure: .init(
                    concreteFacts: ["原计划中的一个步骤没有完成"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["该步骤确实没有完成"],
                    eventProcessStatus: .uncertain,
                    impactStatus: .present,
                    impacts: ["后续安排受到影响"],
                    keyUncertainty: "造成停滞的主要条件仍不明确"
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "additional_explanation_requested",
                focus: "另一个可能有关但不是必需的解释",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "继续探索另一个可能因素"
        )

        let validated = try controller.validate(stalledPlan, for: session)
        let warnings = controller.nonBlockingWarnings(
            originalPlan: stalledPlan,
            validatedPlan: validated,
            for: session
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func testCompletedDisclosurePurposeIsRejectedBeforeWriter() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.receivedDisclosureQuestionPurposes = [.identifyConcreteEpisode]
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["一件已经说清楚的具体事情"]
        )

        let repeated = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "concrete_effect_clarified",
                focus: "再次询问同一个已经完成的作用",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
            ),
            replyIntent: .exploreContext,
            replyGuidance: "重复一个已经完成的问题功能"
        )

        XCTAssertThrowsError(try controller.validate(repeated, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .repeatedQuestionPurpose(.identifyConcreteEpisode, .focalEvent)
            )
        }
    }

    func testTenderPermissionsExposeOnlyAtomicStageIntentActionOperations() {
        var session = protocolSession(stage: .tenderConfirmation)
        session.condition = .cardMediated

        let permissions = controller.permissions(for: session)

        XCTAssertTrue(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .contextualDisclosure,
                    replyIntent: .exploreContext,
                    localAction: .none
                )
            )
        )
        XCTAssertTrue(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .tenderConfirmation,
                    replyIntent: .reviseTenderSummary,
                    localAction: .none
                )
            )
        )
        XCTAssertFalse(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .tenderConfirmation,
                    replyIntent: .exploreContext,
                    localAction: .none
                )
            )
        )
    }

    func testUniqueAtomicOperationNormalizesMismatchedTenderStageLabel() throws {
        var session = protocolSession(stage: .tenderConfirmation)
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .tenderSummary,
            referenceID: "tender-summary"
        )

        let mislabeled = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .tenderSummary,
                decision: .rejected,
                referenceID: "tender-summary"
            ),
            nextPrompt: .openQuestion(
                purpose: "self_criticism_link_reopened_after_correction",
                focus: "用户纠正后仍需理解的现实关系",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess,
                disclosureReopenReason: .userCorrectedPreviousFact
            ),
            replyIntent: .exploreContext,
            replyGuidance: "保留用户修正并回到一个具体关系"
        )

        let normalized = try controller.validate(mislabeled, for: session)

        XCTAssertEqual(normalized.requestedStage, .contextualDisclosure)
        XCTAssertEqual(normalized.replyIntent, .exploreContext)
    }

    func testCompletedDisclosureRejectsProcessAndReflectionFocusQuestions() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "actual_result_clarified",
            focus: "一项具体经历已经造成的现实结果",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )

        let completedEpisode = TurnEpisodeStructure(
            concreteFacts: ["一项具体行动没有按原计划完成"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["行动确实没有完成"],
            eventProcessStatus: .present,
            possibleContributors: ["用户已经说明事件形成过程中的一个近端因素"],
            impactStatus: .present,
            impacts: ["原有安排因此发生改变"]
        )
        let commonMemory = TurnSemanticMemoryUpdate(
            answeredQuestionPurposes: ["actual_result_clarified"],
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由这次具体经历形成了整体自我否定",
            episodeStructure: completedEpisode
        )
        let reopenedProcess = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: commonMemory,
            nextPrompt: .openQuestion(
                purpose: "finer_process_detail_requested",
                focus: "已经完成辨析的事件过程",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "继续追问事件过程"
        )

        XCTAssertThrowsError(try controller.validate(reopenedProcess, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .disclosureShouldAdvance
            )
        }

        let linkQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: commonMemory,
            nextPrompt: .openQuestion(
                purpose: "reality_to_self_evaluation_link_clarified",
                focus: "具体经历如何成为整体自我评价",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只澄清现实结果与整体自我评价之间的关系"
        )
        XCTAssertThrowsError(try controller.validate(linkQuestion, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .disclosureShouldAdvance
            )
        }
    }

    func testCurrentDisclosureResolvedRelationProducesNoSwiftWarning() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let memory = TurnSemanticMemoryUpdate(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一项具体经历形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一项具体行动没有按原计划完成"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["行动确实没有完成"],
                eventProcessStatus: .present,
                possibleContributors: ["用户已经说明一个近端过程因素"],
                impactStatus: .unresolved
            )
        )
        let repeatedProcess = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: memory,
            nextPrompt: .openQuestion(
                purpose: "another_process_detail_requested",
                focus: "事件过程中的另一个细节",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "继续探索原因"
        )

        XCTAssertThrowsError(try controller.validate(repeatedProcess, for: session))

        let impactQuestion = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: memory,
            nextPrompt: .openQuestion(
                purpose: "actual_result_clarified",
                focus: "这项具体经历实际造成的结果",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问实际结果，不再探索原因"
        )
        XCTAssertThrowsError(try controller.validate(impactQuestion, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .disclosureShouldAdvance
            )
        }
    }

    func testAcceptedCardConsentCanonicalizesSwiftOwnedDrawMechanics() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardConsent
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardConsent,
            referenceID: "active-card-consent"
        )

        let semanticallyAcceptedButMechanicallyInconsistent = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardConsent,
                decision: .accepted,
                referenceID: "stale-reference"
            ),
            nextPrompt: .openQuestion(
                purpose: "redundant_transition",
                focus: "a transition that Swift should own"
            ),
            replyIntent: .inviteCardConsent,
            replyGuidance: "The pending invitation was accepted."
        )

        let validated = try controller.validate(
            semanticallyAcceptedButMechanicallyInconsistent,
            for: session
        )

        XCTAssertEqual(validated.requestedStage, .cardConsent)
        XCTAssertEqual(validated.localAction.kind, .drawRandomCard)
        XCTAssertEqual(validated.replyIntent, .acknowledgeCardConsent)
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
        XCTAssertEqual(
            validated.resolvedConfirmation,
            .init(
                target: .cardConsent,
                decision: .accepted,
                referenceID: "active-card-consent"
            )
        )
    }

    func testCurrentProtocolLeavesContextRelationshipReadinessToPlannerAndCritic() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        // The current card condition bridges directly from disclosure to card consent. Keep
        // this test on the non-card route, where a standalone Tender summary is still legal.
        session.condition = .directLLM
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "context_relationship_clarified",
            focus: "最近睡眠状况是否以及如何参与具体修改经历"
        )
        session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [.sleepDuration],
            alternativeExplanations: [],
            dialogueHypothesis: "你最近可能没有休息充分。",
            relevance: .notReviewed
        )

        func bridge(_ relationship: TurnContextRelationship?) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .tenderConfirmation,
                localAction: .none,
                memoryUpdate: .init(
                    situationUnderstanding: "app 修改效果没有达到预期",
                    selfCriticismStatus: .present,
                    selfCriticalStatement: "用户担心自己能力不够",
                    selfCriticismLink: "用户把当前修改结果视为自己可能能力不够的证据",
                    episodeStructure: .init(
                        concreteFacts: ["app 修改效果没有达到预期"],
                        behaviorEvidenceStatus: .uncertain,
                        eventProcessStatus: .uncertain,
                        contextualConstraints: ["用户正在判断近期休息是否参与了修改困难"],
                        impactStatus: .uncertain,
                        keyUncertainty: "休息状况与修改困难的关系仍待用户说明"
                    ),
                    contextRelationship: relationship,
                    tenderUnderstanding: "区分当前技术困难、可用状态与整体能力判断"
                ),
                nextPrompt: .confirmationRequest(target: .tenderSummary),
                replyIntent: .presentTenderSummary,
                replyGuidance: "简短呈现包含已确认 context 关系的事件理解"
            )
        }

        // Contextual cues remain optional evidence. On a route that permits a standalone summary,
        // Swift exposes the legal operation while the Planner and semantic critic decide whether
        // this relationship is useful enough to include before moving on.
        XCTAssertNoThrow(try controller.validate(bridge(nil), for: session))
        XCTAssertNoThrow(
            try controller.validate(
                bridge(
                    .init(
                        relevance: .related,
                        userInterpretation: "用户认为休息不足让判断修改方向更困难"
                    )
                ),
                for: session
            )
        )
    }

    func testCurrentProtocolDoesNotHardCodeEpisodeReadinessForTenderBridge() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        // The current card condition no longer inserts a separate Tender-analysis turn. The
        // non-card route still permits one, so readiness remains a semantic rather than field gate.
        session.condition = .directLLM
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "immediate_barrier_clarified",
            focus: "每次准备开始实验时发生的具体阻力"
        )

        func bridge(_ episode: TurnEpisodeStructure) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .tenderConfirmation,
                localAction: .none,
                memoryUpdate: .init(
                    situationUnderstanding: "用户知道实验大致效果，但一直没有开始，并影响后续事项",
                    selfCriticismStatus: .present,
                    selfCriticalStatement: "用户认为自己确实在拖延",
                    selfCriticismLink: "用户把持续没有开始视为自己正在拖延的行为依据",
                    episodeStructure: episode,
                    tenderUnderstanding: "持续没有开始是事实，但它不能定义整个人；开始时的阻力仍不清楚"
                ),
                nextPrompt: .confirmationRequest(target: .tenderSummary),
                replyIntent: .presentTenderSummary,
                replyGuidance: "中性呈现事实、评价、影响和未知阻力并允许修正"
            )
        }

        let incomplete = TurnEpisodeStructure(
            concreteFacts: ["用户知道实验大致效果但一直没有开始"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["持续没有开始"],
            impactStatus: .unresolved
        )
        // These fields help the LLM decide whether another question has semantic value. Their
        // absence is not a workflow violation once a permitted Tender summary is selected.
        XCTAssertNoThrow(try controller.validate(bridge(incomplete), for: session))

        let grounded = TurnEpisodeStructure(
            concreteFacts: ["用户知道实验大致效果但一直没有开始"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["持续没有开始"],
            eventProcessStatus: .uncertain,
            impactStatus: .present,
            impacts: ["后续很多事情无法完成"],
            keyUncertainty: "每次准备开始时具体在回避或等待什么仍不清楚"
        )
        XCTAssertNoThrow(try controller.validate(bridge(grounded), for: session))
    }

    func testCurrentProtocolUserAuthoredMappingAuthorizesReadingWithoutSeparateTension() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "把画面关系连接到现实经历"
        )

        let repeatedConnectionPlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "一个人物正在改变随身物品的安排",
                    realityMapping: "用户把画面中的改变与现实里想放下的一项负担联系起来",
                    source: .userAuthored
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "repeat_card_connection",
                focus: "再次询问已经给出的现实联系"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "先回应这条联系，再继续确认"
        )
        let authorization = try controller.validate(repeatedConnectionPlan, for: session)
        XCTAssertEqual(authorization.requestedStage, .cardReflection)
        XCTAssertEqual(authorization.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(authorization.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(authorization.nextPrompt?.kind, TurnNextPromptKind.none)
        XCTAssertEqual(
            authorization.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户把画面中的改变与现实里想放下的一项负担联系起来"
        )
        XCTAssertNil(authorization.memoryUpdate.cardInterpretiveTension)

        session.semanticMemory.apply(
            authorization.memoryUpdate,
            committedNextPrompt: authorization.nextPrompt
        )
        session.cardGuidanceShared = true

        let candidateReading = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardNegotiatedMeaning: "候选解读只沿用用户自己建立的画面—现实联系"
            ),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "不补造更深象征含义，呈现可修改或拒绝的温和候选解读"
        )
        XCTAssertNoThrow(try controller.validate(candidateReading, for: session))
        XCTAssertFalse(
            controller.permissions(for: session).allowedReplyIntents
                .contains(.deepenCardConnection)
        )
    }

    func testSilentCardGuidanceTransactionAllowsMissingPrivateWritingGuidance() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed

        let JSON = """
        {
          "requestedStage":"cardReflection",
          "localAction":{"kind":"shareCardGuidance","trackingCueIDs":[]},
          "memoryUpdate":{"cardRealityConnection":{"imageRelation":"用户已经形成的画面关系","realityMapping":"用户刚刚形成的画面—现实连接","source":"userAuthored","status":"confirmed"}},
          "resolvedConfirmation":null,
          "nextPrompt":{"kind":"none","purpose":null,"focus":null,"disclosureTarget":null,"target":null,"referenceID":null},
          "replyIntent":"authorizeCardGuidance",
          "noActionReason":null,
          "replyGuidance":null,
          "cardReferenceSelection":null
        }
        """
        let plan = try JSONDecoder().decode(
            LLMTurnResponsePlan.self,
            from: try XCTUnwrap(JSON.data(using: .utf8))
        )

        XCTAssertEqual(plan.replyGuidance, "")
        let validated = try controller.validate(plan, for: session)
        XCTAssertEqual(validated.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(validated.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(
            validated.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户刚刚形成的画面—现实连接"
        )

        let visiblePlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "card_reality_connection",
                focus: "继续当前现实连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: ""
        )
        XCTAssertThrowsError(try controller.validate(visiblePlan, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .emptyReply)
        }
    }

    func testCurrentProtocolRejectsPracticeWithoutConfirmedBasis() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        session.semanticMemory.finalNarrative = "用户确认的新理解"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "final-1"
        )

        func practice(_ basis: String?) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(
                    practiceOptions: [
                        .init(
                            id: "bounded-check",
                            kind: .change,
                            title: "只验证一个问题",
                            instruction: "下一轮修改前写下一个要验证的问题，结束后只检查它。",
                            rationale: "避免把一次结果扩大成对整体能力的判断。",
                            basis: basis
                        ),
                    ]
                ),
                resolvedConfirmation: .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: "final-1"
                ),
                nextPrompt: .confirmationRequest(target: .practice),
                replyIntent: .suggestPractice,
                replyGuidance: "给出一个直接对应确认区分的小练习"
            )
        }

        XCTAssertThrowsError(try controller.validate(practice(nil), for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .missingRequiredMemoryField(.practiceBasis)
            )
        }
        XCTAssertNoThrow(
            try controller.validate(
                practice("用户确认自己容易把一次未达预期扩大成整体能力判断"),
                for: session
            )
        )
    }

    func testSwiftWriterQualityChecksOnlyDeterministicResponseShape() {
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(cardNegotiatedMeaning: "一个可协商的新区分"),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "给出候选解读并以内容问题继续"
        )
        let semanticDefect = LLMTurnWriterResponse(
            realizedIntent: .presentCardReading,
            reply: "这段候选说法需要你判断是否成立吗？"
        )
        XCTAssertEqual(
            controller.writerQualityIssues(semanticDefect, for: plan),
            []
        )

        let structurallyWrong = LLMTurnWriterResponse(
            realizedIntent: .presentCardReading,
            reply: "第一问？第二问？"
        )
        XCTAssertEqual(
            controller.writerQualityIssues(structurallyWrong, for: plan),
            [.expectedSingleQuestion]
        )
    }

    func testResumedLegacyTrackingReviewExposesOnlyResolutionIntents() {
        var session = protocolSession(stage: .contextualDisclosure)
        let cue = trackingCue(id: "sleep")
        let batch = TurnTrackingPresentation(
            id: "legacy-batch",
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

        let permissions = controller.permissions(for: session)

        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([
                .checkTrackingRelationship,
                .integrateTrackingAndPresentTenderSummary,
                .safetySupport,
            ])
        )
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentTrackingContext))
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
        cardSession.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户已经形成的画面关系",
            realityMapping: "用户已经形成的现实映射",
            source: .userAuthored
        )
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

    func testSemanticLanguageDefectsDoNotBecomeSwiftPhraseRules() throws {
        let disclosurePlan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["一件具体事件"],
                    behaviorEvidenceStatus: .unresolved,
                    eventProcessStatus: .unresolved,
                    impactStatus: .unresolved
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "understand_event_development",
                focus: "事情怎样发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "直接询问同一个事件经过"
        )
        let recapDraft = LLMTurnWriterResponse(
            realizedIntent: .exploreContext,
            reply: "你刚才说事情没有按计划发展。后来发生了什么？"
        )

        XCTAssertNoThrow(try controller.validate(recapDraft, for: disclosurePlan))
        XCTAssertEqual(controller.writerQualityIssues(recapDraft, for: disclosurePlan), [])

        let tenderPlan = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .presentTenderSummary,
            replyGuidance: "进行一次轻量过渡"
        )
        let praiseDraft = LLMTurnWriterResponse(
            realizedIntent: .presentTenderSummary,
            reply: "这说明你很负责。现在最在意哪一部分？"
        )

        XCTAssertNoThrow(try controller.validate(praiseDraft, for: tenderPlan))
        XCTAssertEqual(controller.writerQualityIssues(praiseDraft, for: tenderPlan), [])
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
            "contextCueOffered": true,
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
            "cardRealityConnection": {
              "imageRelation": "画面中一部分正在发生变化",
              "realityMapping": "现实中也有一部分可以单独回看",
              "source": "userAuthored",
              "status": "confirmed"
            },
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
        XCTAssertEqual(plan.memoryUpdate.contextCueOffered, true)
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
        XCTAssertEqual(
            plan.memoryUpdate.cardRealityConnection?.imageRelation,
            "画面中一部分正在发生变化"
        )
        XCTAssertEqual(
            plan.memoryUpdate.cardRealityConnection?.realityMapping,
            "现实中也有一部分可以单独回看"
        )
        XCTAssertFalse(plan.memoryUpdate.legacyConnectionFieldsPresentInPayload)
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
            ("contextCueOffered", []),
            ("trackingAssessments", [:]),
            ("tenderUnderstanding", []),
            ("cardRealityConnection", []),
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
          "cardRealityConnection": null,
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
        reflection.protocolVersion = ReflectionSession.currentProtocolVersion
        reflection.condition = .cardMediated
        reflection.card = CardService().allCards[0]
        reflection.cardDisplayState = .displayed
        let preAuthorizationPermissions = controller.permissions(for: reflection)
        XCTAssertNil(reflection.semanticMemory.cardRealityConnection)
        XCTAssertNil(
            controller.effectiveCardRealityConnection(for: reflection),
            "legacy mirrors unexpectedly formed a connection: \(reflection.semanticMemory)"
        )
        XCTAssertFalse(
            preAuthorizationPermissions.allowedReplyIntents.contains(
                .authorizeCardGuidance
            ),
            "authorize unexpectedly allowed: \(preAuthorizationPermissions)"
        )
        XCTAssertFalse(
            preAuthorizationPermissions.allowedActions.contains(.shareCardGuidance),
            "unexpected pre-connection permissions: \(preAuthorizationPermissions)"
        )
        XCTAssertFalse(
            preAuthorizationPermissions.allowedReplyIntents.contains(
                .presentCardReading
            ),
            "reading unexpectedly allowed: \(preAuthorizationPermissions)"
        )
        let relationMemory = TurnSemanticMemoryUpdate(
            cardRealityConnection: .init(
                imageRelation: "画面中的人先观察再决定是否靠近",
                realityMapping: "用户在现实中也需要先了解请求范围再回应",
                source: .userAuthored
            )
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

        // A complete post-patch connection has one deterministic silent successor even if the
        // Planner leaves the redundant local-action label as none.
        let derivedAuthorization = try controller.validate(
            plan(
                stage: .cardReflection,
                intent: .authorizeCardGuidance,
                action: .none,
                memory: relationMemory
            ),
            for: reflection
        )
        XCTAssertEqual(derivedAuthorization.localAction.kind, .shareCardGuidance)

        let combinedReadingAndGuidance = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "画面中的人先观察再决定是否靠近",
                    realityMapping: "用户在现实中也需要先了解请求范围再回应",
                    source: .userAuthored
                ),
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
                .illegalReplyIntent
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

    func testCurrentTurnPromptsUseImmutableServerRegistryVersion() {
        XCTAssertEqual(ServerTurnPrompt.version, "turn-v4-server-v34")
        XCTAssertEqual(ServerTurnPrompt.version(for: 2), "turn-v4-server-v34")
        XCTAssertEqual(ServerTurnPrompt.version(for: 3), "turn-v4-server-v34")
        XCTAssertEqual(
            ServerTurnPrompt.version(for: ReflectionSession.currentProtocolVersion),
            "turn-v4-server-v34"
        )
        XCTAssertEqual(ServerTurnPrompt.Task.planner.rawValue, "planner")
        XCTAssertEqual(ServerTurnPrompt.Task.planCritic.rawValue, "plan_critic")
        XCTAssertEqual(ServerTurnPrompt.Task.writer.rawValue, "writer")
        XCTAssertEqual(ServerTurnPrompt.Task.writerCritic.rawValue, "writer_critic")
        XCTAssertEqual(ServerTurnPrompt.Task.writerRevision.rawValue, "writer_revision")
    }

    func testNextPromptDropsAnInvalidOptionalDisclosureTargetWithoutLosingCardQuestion() throws {
        let data = Data(
            """
            {
              "kind": "openQuestion",
              "purpose": "card_reality_connection",
              "focus": "connect the image relation with real life",
              "disclosureTarget": "cardRelationship",
              "target": null,
              "referenceID": null
            }
            """.utf8
        )

        let prompt = try JSONDecoder().decode(TurnNextPrompt.self, from: data)

        XCTAssertEqual(prompt.kind, .openQuestion)
        XCTAssertEqual(prompt.purpose, "card_reality_connection")
        XCTAssertNil(prompt.disclosureTarget)
        XCTAssertNil(prompt.target)
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
            "cardRealityConnection": null,
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
        XCTAssertNil(decoded.cardReferenceSelection)
    }

    func testCardReferenceSelectionIsTurnLocalAndSwiftValidatesSourceAndPermission() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户描述了画面中尚未完全出发的关系",
            realityMapping: "用户把这个关系连接到现实中继续准备的状态",
            source: .userAuthored
        )

        func reading(index: Int) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(
                    cardNegotiatedMeaning: "等待用户通过后续回答发展或修正的候选理解"
                ),
                nextPrompt: .confirmationRequest(target: .cardMapping),
                replyIntent: .presentCardReading,
                replyGuidance: "只把当前卡牌的一条受支持关系用于形成后续问题",
                cardReferenceSelection: .init(relationIndex: index)
            )
        }

        let valid = try controller.validate(reading(index: 0), for: session)
        XCTAssertEqual(valid.cardReferenceSelection?.relationIndex, 0)
        XCTAssertNil(valid.memoryUpdate.cardRealityMapping)

        XCTAssertThrowsError(try controller.validate(reading(index: 2), for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidCardReferenceSelection
            )
        }

        session.protocolStage = .directReflection
        session.semanticMemory.cardNegotiatedMeaning = "用户已经确认的候选连接"
        let narrative = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(finalNarrative: "一段候选综合叙事"),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "呈现最终叙事",
            cardReferenceSelection: .init(relationIndex: 0)
        )
        XCTAssertThrowsError(try controller.validate(narrative, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidCardReferenceSelection
            )
        }
    }

    func testSourceOnlyAndIncompleteCardRealityConnectionsAreRejectedAtomically() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed

        let sourceOnly = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(cardRealityMappingSource: .userAuthored),
            nextPrompt: .openQuestion(
                purpose: "continue_current_connection",
                focus: "继续当前事件中的画面—现实连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "只继续当前连接"
        )
        XCTAssertThrowsError(try controller.validate(sourceOnly, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .legacyCardConnectionPatchNotAllowed
            )
        }
        XCTAssertNil(session.semanticMemory.cardRealityConnection)
        XCTAssertNil(session.semanticMemory.cardRealityMappingSource)
        XCTAssertFalse(
            controller.permissions(for: session).allowedActions.contains(.shareCardGuidance)
        )

        for retiredPatch in [
            TurnSemanticMemoryUpdate(cardImageRelation: "只有旧式画面关系"),
            TurnSemanticMemoryUpdate(cardRealityMapping: "只有旧式现实映射"),
            TurnSemanticMemoryUpdate(
                cardImageRelation: "旧式画面关系",
                cardRealityMapping: "旧式现实映射"
            ),
        ] {
            let plan = LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: retiredPatch,
                nextPrompt: .openQuestion(
                    purpose: "continue_current_connection",
                    focus: "继续当前事件中的画面—现实连接"
                ),
                replyIntent: .inviteCardConnection,
                replyGuidance: "任何旧字段组合都必须被拒绝"
            )
            XCTAssertThrowsError(try controller.validate(plan, for: session)) {
                XCTAssertEqual(
                    $0 as? ReflectionProtocolViolation,
                    .legacyCardConnectionPatchNotAllowed
                )
            }
        }

        let completeLegacyPatch = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardImageRelation: "旧式画面关系",
                cardRealityMapping: "旧式现实映射",
                cardRealityMappingSource: .userAuthored
            ),
            nextPrompt: .openQuestion(
                purpose: "continue_current_connection",
                focus: "继续当前事件中的画面—现实连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "旧式完整 patch 仍必须被拒绝"
        )
        XCTAssertNil(
            controller.effectiveCardRealityConnection(
                for: session,
                memoryUpdate: completeLegacyPatch.memoryUpdate
            )
        )
        XCTAssertThrowsError(try controller.validate(completeLegacyPatch, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .legacyCardConnectionPatchNotAllowed
            )
        }

        let explicitNullLegacyUpdate = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(#"{"cardRealityMapping":null}"#.utf8)
        )
        XCTAssertTrue(explicitNullLegacyUpdate.legacyConnectionFieldsPresentInPayload)
        let explicitNullLegacyPlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: explicitNullLegacyUpdate,
            nextPrompt: .openQuestion(
                purpose: "continue_current_connection",
                focus: "继续当前事件中的画面—现实连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "显式 null 也属于已退役字段 patch"
        )
        XCTAssertThrowsError(try controller.validate(explicitNullLegacyPlan, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .legacyCardConnectionPatchNotAllowed
            )
        }

        let incomplete = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "   ",
                    realityMapping: "一个现实映射",
                    source: .userAuthored
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "continue_current_connection",
                focus: "继续当前事件中的画面—现实连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "只继续当前连接"
        )
        XCTAssertThrowsError(try controller.validate(incomplete, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .incompleteCardRealityConnection
            )
        }

        let guidanceWithoutConnection = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: ""
        )
        XCTAssertThrowsError(
            try controller.validate(guidanceWithoutConnection, for: session)
        ) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .shareGuidanceWithoutConfirmedConnection
            )
        }
    }

    func testOnlyCompleteConfirmedConnectionUnlocksGuidanceCapabilities() {
        func baseSession() -> ReflectionSession {
            var session = ReflectionSession()
            session.protocolVersion = ReflectionSession.currentProtocolVersion
            session.protocolStage = .cardReflection
            session.condition = .cardMediated
            session.card = CardService().allCards[0]
            session.cardDisplayState = .displayed
            return session
        }
        func assertClosed(_ session: ReflectionSession, file: StaticString = #filePath, line: UInt = #line) {
            let permissions = controller.permissions(for: session)
            XCTAssertFalse(
                permissions.allowedActions.contains(.shareCardGuidance),
                file: file,
                line: line
            )
            XCTAssertFalse(
                permissions.allowedReplyIntents.contains(.authorizeCardGuidance),
                file: file,
                line: line
            )
            XCTAssertFalse(
                permissions.allowedReplyIntents.contains(.presentCardReading),
                file: file,
                line: line
            )
        }

        var sourceOnly = baseSession()
        sourceOnly.semanticMemory.cardRealityMappingSource = .userAuthored
        assertClosed(sourceOnly)

        var relationOnly = baseSession()
        relationOnly.semanticMemory.cardImageRelation = "一个画面关系"
        assertClosed(relationOnly)

        var mappingOnly = baseSession()
        mappingOnly.semanticMemory.cardRealityMapping = "一个现实映射"
        assertClosed(mappingOnly)

        var pendingOnly = baseSession()
        pendingOnly.semanticMemory.pendingCardRealityConnection = .init(
            imageRelation: "一个候选画面关系",
            candidateRealityMapping: "一个尚未确认的候选现实映射"
        )
        assertClosed(pendingOnly)

        var confirmed = baseSession()
        confirmed.semanticMemory.cardRealityConnection = .init(
            imageRelation: "一个已确认的画面关系",
            realityMapping: "一个已确认的现实映射",
            source: .userAuthored
        )
        let permissions = controller.permissions(for: confirmed)
        XCTAssertTrue(permissions.allowedActions.contains(.shareCardGuidance))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.authorizeCardGuidance))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentCardReading))
    }

    func testPostGuidanceConfirmedConnectionIsImmutableAndIdenticalEchoIsNoOp() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.cardConnectionAttemptCount = 1
        let confirmed = TurnCardRealityConnection(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实关系",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = confirmed

        func readingPlan(
            connection: TurnCardRealityConnection?
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(
                    cardRealityConnection: connection,
                    cardNegotiatedMeaning: "当前 post-guidance 候选解读"
                ),
                nextPrompt: .confirmationRequest(target: .cardMapping),
                replyIntent: .presentCardReading,
                replyGuidance: "只生成当前候选解读"
            )
        }

        let changed = readingPlan(
            connection: .init(
                imageRelation: confirmed.imageRelation,
                realityMapping: "试图改写已经确认的现实关系",
                source: .userRevised
            )
        )
        XCTAssertThrowsError(try controller.validate(changed, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .confirmedCardConnectionIsImmutable
            )
        }
        XCTAssertEqual(session.semanticMemory.cardRealityConnection, confirmed)
        XCTAssertEqual(session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(session.cardGuidanceShared)

        let identical = readingPlan(connection: confirmed)
        let validated = try controller.validate(identical, for: session)
        XCTAssertNil(validated.memoryUpdate.cardRealityConnection)
        XCTAssertEqual(validated.localAction.kind, .none)
        XCTAssertEqual(validated.replyIntent, .presentCardReading)
        XCTAssertEqual(session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(
            controller.nonBlockingWarnings(
                originalPlan: identical,
                validatedPlan: validated,
                for: session
            ).contains(.redundantConfirmedConnectionPatch)
        )

        let clear = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(clearCardRealityConnection: true),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "不得清除已确认连接"
        )
        XCTAssertThrowsError(try controller.validate(clear, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .confirmedCardConnectionIsImmutable
            )
        }

        let reopenPending = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                pendingCardRealityConnection: .init(
                    imageRelation: "试图重新打开的画面关系",
                    candidateRealityMapping: "试图重新打开的现实关系"
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardRealityConnection),
            replyIntent: .inviteCardConnection,
            replyGuidance: "不得重新打开连接确认"
        )
        XCTAssertThrowsError(try controller.validate(reopenPending, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .confirmedCardConnectionIsImmutable
            )
        }
        XCTAssertEqual(session.semanticMemory.cardRealityConnection, confirmed)
        XCTAssertEqual(session.cardConnectionAttemptCount, 1)
    }

    func testPendingCardRealityConnectionAcceptReviseAndRejectAreTyped() throws {
        func pendingSession() -> (ReflectionSession, PendingCardRealityConnection) {
            var session = ReflectionSession()
            session.protocolVersion = ReflectionSession.currentProtocolVersion
            session.protocolStage = .cardReflection
            session.condition = .cardMediated
            session.card = CardService().allCards[0]
            session.cardDisplayState = .displayed
            let pending = PendingCardRealityConnection(
                imageRelation: "画面中的一个部分停下来观察另一个部分",
                candidateRealityMapping: "现实中也可能存在停下来重新观察的对比"
            )
            session.semanticMemory.pendingCardRealityConnection = pending
            session.semanticMemory.nextPrompt = .confirmationRequest(
                target: .cardRealityConnection,
                referenceID: pending.id.uuidString
            )
            return (session, pending)
        }

        var (acceptedSession, pending) = pendingSession()
        let accepted = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                resolvedConfirmation: .init(
                    target: .cardRealityConnection,
                    decision: .accepted,
                    referenceID: pending.id.uuidString
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .inviteCardConnection,
                replyGuidance: "提交已接受的候选连接"
            ),
            for: acceptedSession
        )
        XCTAssertEqual(accepted.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(accepted.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(accepted.memoryUpdate.cardRealityConnection?.source, .userAccepted)
        XCTAssertEqual(accepted.memoryUpdate.cardConnectionOutcome, .connectionConfirmed)
        XCTAssertEqual(accepted.memoryUpdate.clearPendingCardRealityConnection, true)
        acceptedSession.semanticMemory.apply(
            accepted.memoryUpdate,
            committedNextPrompt: accepted.nextPrompt
        )
        XCTAssertNil(acceptedSession.semanticMemory.pendingCardRealityConnection)
        XCTAssertEqual(acceptedSession.semanticMemory.cardRealityConnection?.source, .userAccepted)

        let (revisedSession, revisedPending) = pendingSession()
        let revised = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(
                    cardRealityConnection: .init(
                        imageRelation: revisedPending.imageRelation,
                        realityMapping: "用户修订后的现实关系",
                        source: .userRevised
                    )
                ),
                resolvedConfirmation: .init(
                    target: .cardRealityConnection,
                    decision: .revised,
                    referenceID: revisedPending.id.uuidString
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .inviteCardConnection,
                replyGuidance: "提交用户修订后的连接"
            ),
            for: revisedSession
        )
        XCTAssertEqual(revised.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(
            revised.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户修订后的现实关系"
        )
        XCTAssertEqual(revised.memoryUpdate.cardRealityConnection?.source, .userRevised)

        let (rejectedSession, rejectedPending) = pendingSession()
        let rejected = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                resolvedConfirmation: .init(
                    target: .cardRealityConnection,
                    decision: .rejected,
                    referenceID: rejectedPending.id.uuidString
                ),
                nextPrompt: .openQuestion(
                    purpose: "connection_after_rejection",
                    focus: "允许用户继续当前事件内的连接或把卡牌放到一边"
                ),
                replyIntent: .inviteCardConnection,
                replyGuidance: "不再使用被拒绝的候选"
            ),
            for: rejectedSession
        )
        XCTAssertNil(rejected.memoryUpdate.cardRealityConnection)
        XCTAssertEqual(rejected.memoryUpdate.cardConnectionOutcome, .candidateRejected)
        XCTAssertEqual(rejected.memoryUpdate.clearPendingCardRealityConnection, true)
        XCTAssertEqual(rejected.localAction.kind, .none)
    }

    func testCardRealityConnectionConfirmationRequiresMatchingPendingObject() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.cardDisplayState = .displayed

        let invalid = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardRealityConnection,
                decision: .accepted,
                referenceID: "not-pending"
            ),
            nextPrompt: .openQuestion(
                purpose: "continue_current_connection",
                focus: "继续当前事件中的连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "继续合法连接路径"
        )
        XCTAssertThrowsError(try controller.validate(invalid, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidPreGuidanceConnectionConfirmation
            )
        }
        XCTAssertNil(session.semanticMemory.pendingCardRealityConnection)
        XCTAssertNil(session.semanticMemory.cardRealityConnection)
    }

    func testLegacyCardRealityConnectionMigrationPreservesOnlyCompleteTriples() throws {
        func decode(
            memory: [String: Any],
            guidanceShared: Bool = false
        ) throws -> ReflectionSession {
            let payload: [String: Any] = [
                "protocolVersion": ReflectionSession.currentProtocolVersion,
                "protocolStage": "cardReflection",
                "stage": "cardInterpretation",
                "condition": "cardMediated",
                "cardDisplayState": "displayed",
                "cardGuidanceShared": guidanceShared,
                "semanticMemory": memory,
            ]
            return try JSONDecoder().decode(
                ReflectionSession.self,
                from: JSONSerialization.data(withJSONObject: payload)
            )
        }

        let complete = try decode(memory: [
            "cardImageRelation": "旧画面关系",
            "cardRealityMapping": "旧现实映射",
            "cardRealityMappingSource": "userAuthored",
        ])
        XCTAssertEqual(complete.semanticMemory.cardRealityConnection?.imageRelation, "旧画面关系")
        XCTAssertEqual(complete.semanticMemory.cardRealityConnection?.realityMapping, "旧现实映射")
        XCTAssertEqual(complete.semanticMemory.cardRealityConnection?.source, .userAuthored)

        let canonicalDominates = try decode(memory: [
            "cardRealityConnection": [
                "imageRelation": "canonical 画面关系",
                "realityMapping": "canonical 现实映射",
                "source": "userRevised",
                "status": "confirmed",
            ],
            "cardImageRelation": "冲突的旧画面关系",
            "cardRealityMapping": "冲突的旧现实映射",
            "cardRealityMappingSource": "userAuthored",
        ])
        XCTAssertEqual(
            canonicalDominates.semanticMemory.cardRealityConnection?.imageRelation,
            "canonical 画面关系"
        )
        XCTAssertEqual(
            canonicalDominates.semanticMemory.cardRealityConnection?.realityMapping,
            "canonical 现实映射"
        )
        XCTAssertEqual(
            canonicalDominates.semanticMemory.cardRealityConnection?.source,
            .userRevised
        )
        XCTAssertTrue(
            canonicalDominates.studyEvents.contains {
                $0.action == "legacy_card_connection_conflict_ignored"
            }
        )

        let canonicalRoundTrip = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(canonicalDominates)
        )
        XCTAssertEqual(
            canonicalRoundTrip.studyEvents.filter {
                $0.action == "legacy_card_connection_conflict_ignored"
            }.count,
            1
        )
        XCTAssertEqual(
            canonicalRoundTrip.semanticMemory.cardRealityConnection,
            canonicalDominates.semanticMemory.cardRealityConnection
        )

        for partial in [
            ["cardRealityMappingSource": "userAuthored"],
            ["cardImageRelation": "只有画面关系"],
            ["cardRealityMapping": "只有现实映射"],
        ] {
            let migrated = try decode(memory: partial)
            XCTAssertNil(migrated.semanticMemory.cardRealityConnection)
            XCTAssertNil(migrated.semanticMemory.cardRealityMappingSource)
            XCTAssertTrue(
                migrated.studyEvents.contains {
                    $0.action == "legacy_incomplete_card_connection"
                }
            )
            XCTAssertFalse(
                controller.permissions(for: migrated).allowedActions
                    .contains(.shareCardGuidance)
            )
        }

        let inconsistent = try decode(
            memory: ["cardRealityMappingSource": "userAuthored"],
            guidanceShared: true
        )
        XCTAssertFalse(inconsistent.cardGuidanceShared)
        XCTAssertEqual(inconsistent.protocolStage, .cardReflection)
        XCTAssertEqual(inconsistent.stage, .cardInterpretation)
        XCTAssertTrue(
            inconsistent.studyEvents.contains {
                $0.action == "legacy_guidance_without_confirmed_connection"
            }
        )

        let roundTripped = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(inconsistent)
        )
        XCTAssertEqual(
            roundTripped.studyEvents.filter {
                $0.action == "legacy_incomplete_card_connection"
            }.count,
            1
        )
    }

    func testKnownRealityConnectionFailureReplayCommitsOnceAndUnlocksGuidance() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        session.cardConnectionAttemptCount = 2

        let proposed = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "一个人在稳住架子，另一个人在搬下物件并检查损坏原因",
                    realityMapping: "用户把减少损失和检查原因的画面关系连接到修改项目、寻找不完美原因的当前事件",
                    source: .userAuthored
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "obsolete_connection_question",
                focus: "不应再次询问已经形成的连接"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "提交连接"
        )
        let authorization = try controller.validate(proposed, for: session)
        XCTAssertEqual(authorization.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(authorization.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(authorization.nextPrompt?.kind, TurnNextPromptKind.none)
        XCTAssertEqual(authorization.memoryUpdate.cardConnectionOutcome, .connectionConfirmed)

        session.semanticMemory.apply(
            authorization.memoryUpdate,
            committedNextPrompt: authorization.nextPrompt
        )
        session.semanticMemory.apply(
            authorization.memoryUpdate,
            committedNextPrompt: authorization.nextPrompt
        )
        XCTAssertNotNil(session.semanticMemory.cardRealityConnection)
        XCTAssertEqual(session.cardConnectionAttemptCount, 2)
        XCTAssertTrue(controller.permissions(for: session).allowedActions.contains(.shareCardGuidance))
        XCTAssertFalse(
            controller.permissions(for: session).allowedReplyIntents
                .contains(.inviteCardConnection)
        )
    }

    func testCanonicalCardRealityConnectionRestartDoesNotRunLegacyMigration() throws {
        var original = ReflectionSession()
        original.protocolVersion = ReflectionSession.currentProtocolVersion
        original.protocolStage = .cardReflection
        original.condition = .cardMediated
        original.stage = .cardInterpretation
        original.card = CardService().allCards[0]
        original.cardDisplayState = .displayed
        original.cardGuidanceShared = true
        original.cardConnectionAttemptCount = 1
        let confirmed = TurnCardRealityConnection(
            imageRelation: "重启前已经确认的画面关系",
            realityMapping: "重启前已经确认的现实关系",
            source: .userRevised
        )
        original.semanticMemory.cardRealityConnection = confirmed
        original.semanticMemory.cardImageRelation = confirmed.imageRelation
        original.semanticMemory.cardRealityMapping = confirmed.realityMapping
        original.semanticMemory.cardRealityMappingSource = confirmed.source

        let restored = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(restored.semanticMemory.cardRealityConnection, confirmed)
        XCTAssertEqual(restored.semanticMemory.cardRealityConnection?.source, .userRevised)
        XCTAssertEqual(restored.cardConnectionAttemptCount, 1)
        XCTAssertTrue(restored.cardGuidanceShared)
        XCTAssertFalse(
            restored.studyEvents.contains {
                [
                    "legacy_incomplete_card_connection",
                    "legacy_card_connection_conflict_ignored",
                    "legacy_guidance_without_confirmed_connection",
                ].contains($0.action)
            }
        )
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
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )

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
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
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

    func testPendingCandidQuestionKeepsReflectionAndNarrativeChoicesAvailable() {
        var session = protocolSession(stage: .directReflection)
        session.reflectionReadiness = .reflectionOpen
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_behavior_or_impact_clarified",
            focus: "一个具体行为及其影响"
        )

        let permissions = controller.permissions(for: session)

        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.presentFinalNarrative))
        XCTAssertTrue(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .directReflection,
                    replyIntent: .directCandidReflection,
                    localAction: .none
                )
            )
        )
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
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.authorizeCardGuidance))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))

        session.cardConnectionUnavailable = true
        permissions = controller.permissions(for: session)
        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.directCandidReflection, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedActions.contains(.shareCardGuidance))
    }

    func testCurrentCardConnectionMovesCannotCommitWithoutAnOpenQuestion() throws {
        var session = protocolSession(stage: .cardReflection)
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardConnectionAttemptCount = 1
        session.semanticMemory.cardImageRelation = "用户已经形成一条人物与空间的关系"

        func connectionPlan(
            intent: TurnReplyIntent,
            nextPrompt: TurnNextPrompt
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: nextPrompt,
                replyIntent: intent,
                replyGuidance: "继续当前卡牌连接工作"
            )
        }

        XCTAssertThrowsError(
            try controller.validate(
                connectionPlan(intent: .developCardImage, nextPrompt: TurnNextPrompt.none),
                for: session
            )
        ) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .invalidNextPrompt)
        }
        XCTAssertNoThrow(
            try controller.validate(
                connectionPlan(
                    intent: .developCardImage,
                    nextPrompt: .openQuestion(
                        purpose: "card_connection_scaffold",
                        focus: "用一条已有画面关系缩小现实连接任务"
                    )
                ),
                for: session
            )
        )

        session.cardConnectionScaffoldUsed = true
        XCTAssertThrowsError(
            try controller.validate(
                connectionPlan(intent: .inviteCardConnection, nextPrompt: TurnNextPrompt.none),
                for: session
            )
        ) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .invalidNextPrompt)
        }
        XCTAssertNoThrow(
            try controller.validate(
                connectionPlan(
                    intent: .inviteCardConnection,
                    nextPrompt: .openQuestion(
                        purpose: "candidate_card_connection",
                        focus: "提供一条可拒绝候选并允许发展、修正或放下"
                    )
                ),
                for: session
            )
        )
    }

    func testCurrentCardImageDevelopmentStopsAfterRelationProjection() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.cardDisplayState = .displayed

        var permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.inviteCardObservation))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.developCardImage))

        // One relational clarification may still be followed by one temporal-development turn
        // when the typed relationship has not yet been established.
        session.cardImageDevelopmentTurnCount = 1
        permissions = controller.permissions(for: session)
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.developCardImage))

        // The legacy scalar is no longer a capability credential. Only the bounded turn counter or
        // a complete canonical connection may change available operations.
        session.semanticMemory.cardImageRelation = "一个人物正向另一个人物示范某件事"
        permissions = controller.permissions(for: session)
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.developCardImage))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.inviteCardConnection))

        // Even without a usable relation, the pre-connection image phase cannot continue after
        // its two bounded development capabilities have been consumed.
        session.semanticMemory.cardImageRelation = nil
        session.cardImageDevelopmentTurnCount = 2
        permissions = controller.permissions(for: session)
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.developCardImage))
    }

    @MainActor
    func testCommittedCardConnectionOutcomesConsumeAttemptsNotQuestions() async {
        let scripted = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardConnectionOutcome: .partialConnection
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
                            cardConnectionOutcome: .noConnectionFound
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
                            cardConnectionOutcome: .partialConnection
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.cardDisplayState = .displayed

        model.draft = "画面里接下来可能会有变化。"
        model.send()
        await waitForIdle()
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 0)
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
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        let finalPermissions = controller.permissions(for: model.session)
        XCTAssertFalse(finalPermissions.allowedReplyIntents.contains(.developCardImage))
        XCTAssertTrue(finalPermissions.allowedReplyIntents.contains(.inviteCardConnection))
    }

    func testPendingCardMappingNarrowsPermissionsToResolutionOrClarification() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
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
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "两个人抬着花盆尚未放下",
            realityMapping: "用户把尚未放下的画面连接到现实中持续没有开始",
            source: .userAuthored
        )
        session.semanticMemory.cardInterpretiveTension = "在两个位置之间犹豫"
        session.semanticMemory.cardNegotiatedMeaning = "尚在等待用户确认的候选解读"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "rejected-card-reading"
        )
        let rejected = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "用户大致知道想要的实验效果，但持续没有开始",
                episodeStructure: .init(
                    concreteFacts: ["用户知道大致效果但持续没有开始"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["持续没有开始"],
                    impactStatus: .present,
                    impacts: ["后续事项无法完成"],
                    keyUncertainty: "开始任务时的具体阻力仍不清楚"
                ),
                tenderUnderstanding: "持续没有开始是事实，但它不定义整个人；具体阻力仍不清楚"
            ),
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
        XCTAssertNil(validated.memoryUpdate.cardImageRelation)
        XCTAssertNil(validated.memoryUpdate.cardRealityMapping)
        XCTAssertNil(validated.memoryUpdate.clearCardRealityConnection)
        XCTAssertEqual(validated.memoryUpdate.cardInterpretiveTension, "")
        XCTAssertEqual(validated.memoryUpdate.cardNegotiatedMeaning, "")
        XCTAssertEqual(
            validated.memoryUpdate.situationUnderstanding,
            "用户大致知道想要的实验效果，但持续没有开始"
        )
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
    }

    @MainActor
    func testRejectedCardCandidateIsExcludedFromContinuationEvidence() async {
        let correctedEpisode = TurnEpisodeStructure(
            concreteFacts: ["用户知道实验大致效果但一直没有开始"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["一直没有开始"],
            impactStatus: .present,
            impacts: ["后续很多事情无法完成"],
            keyUncertainty: "每次准备开始时的具体阻力仍不清楚"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "用户知道大致效果，但持续没有开始",
                            episodeStructure: correctedEpisode,
                            tenderUnderstanding: "持续没有开始是事实，但不能定义整个人；开始时的阻力仍不清楚"
                        ),
                        resolvedConfirmation: .init(
                            target: .cardMapping,
                            decision: .rejected,
                            referenceID: "candidate-1"
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "只提交拒绝和用户修正"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "fierce_immediate_barrier_clarified",
                            focus: "每次准备开始实验时出现的具体阻力"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "承认先前理解错误，只询问开始那一刻的阻力"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: "刚才把它理解成方向不清楚并不准确。每次准备真正开始实验时，最先让你停下来的是什么？"
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "两个人抬着花盆，没有决定位置",
            realityMapping: "用户把画面中的停留连接到现实中持续没有开始",
            source: .userAuthored
        )
        model.session.semanticMemory.cardInterpretiveTension = "在两个方向之间犹豫"
        model.session.semanticMemory.cardNegotiatedMeaning =
            "事情很重要，所以用户想找到真正合适的方向"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "candidate-1"
        )
        let candidate = ChatMessage(
            role: .assistant,
            content: "也许事情很重要，所以你想找到真正合适的方向。",
            state: .cardInterpretation
        )
        model.session.messages = [candidate]

        model.draft = "不是，我大概知道想要什么效果，但一直不想去做。"
        model.send()
        try? await Task.sleep(for: .milliseconds(40))
        for _ in 0..<120 {
            if !model.isTyping && !model.isStreamingResponse { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(model.isTyping)

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests.first?.recentMessages.contains(where: {
                $0.content.contains("真正合适的方向")
            }) == true
        )
        XCTAssertFalse(
            requests.last?.recentMessages.contains(where: {
                $0.content.contains("真正合适的方向")
            }) == true
        )
        XCTAssertTrue(model.session.supersededAssistantMessageIDs.contains(candidate.id))
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把画面中的停留连接到现实中持续没有开始"
        )
        XCTAssertEqual(model.session.semanticMemory.cardNegotiatedMeaning, "")
        XCTAssertEqual(
            model.session.lockedBaselineNarrative,
            "持续没有开始是事实，但不能定义整个人；开始时的阻力仍不清楚"
        )
        XCTAssertEqual(model.session.messages.last?.role, .assistant)
        XCTAssertTrue(model.session.messages.last?.content.contains("最先让你停下来") == true)
    }

    func testAcceptedCardMappingCannotBeMislabeledAsAnotherCardReading() {
        var session = protocolSession(stage: .cardReflection)
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
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
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
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
    func testSecondPlanCriticFailureNarrowsPurposeBeforeAnyWriterCall() async throws {
        let planner = RepeatedDisclosureThenBridgePlanner()
        let planCritic = TwiceRejectingDisclosurePlanCritic()
        let writer = CardInviteTestWriter()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic,
            writer: writer,
            critic: PassingWriterCritic()
        )
        var memory = TurnSemanticMemory()
        memory.receivedDisclosureQuestionPurposes = [.clarifyEventProcess]
        memory.episodeStructure = .init(
            concreteFacts: ["一件具体事情及其直接结果"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户明确说明的行为"],
            eventProcessStatus: .present,
            possibleContributors: ["事情的发展已经说明"]
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .contextualDisclosure,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .contextualDisclosure,
                allowedStages: [.contextualDisclosure, .cardConsent],
                allowedActions: [.none],
                allowedReplyIntents: [.exploreContext, .inviteCardConsent],
                allowedDisclosurePurposes: [.clarifyEventProcess],
                allowedDisclosureTargets: [.eventProcess],
                allowedOperations: [
                    .init(
                        requestedStage: .contextualDisclosure,
                        replyIntent: .exploreContext,
                        localAction: .none
                    ),
                    .init(
                        requestedStage: .cardConsent,
                        replyIntent: .inviteCardConsent,
                        localAction: .none
                    ),
                ]
            ),
            recentMessages: [.init(role: .user, content: "用户已经补充了最新回答。")],
            semanticMemory: memory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let planned = try await controller.plan(to: request)
        let writerCallsBeforeWriting = await writer.callCount()
        let plannerCalls = await planner.callCount()
        let planCriticCalls = await planCritic.callCount()
        XCTAssertEqual(writerCallsBeforeWriting, 0)
        XCTAssertEqual(planned.replyIntent, .inviteCardConsent)
        XCTAssertEqual(planned.requestedStage, .cardConsent)
        XCTAssertEqual(plannerCalls, 3)
        XCTAssertEqual(planCriticCalls, 3)
        let finalPermissions = await planner.lastPermissions()
        XCTAssertFalse(
            finalPermissions?.allowedDisclosurePurposes.contains(.clarifyEventProcess)
                ?? true
        )
        XCTAssertFalse(
            finalPermissions?.allowedDisclosureTargets.contains(.eventProcess) ?? true
        )

        _ = try await controller.write(request: request, validatedPlan: planned)
        let writerCallsAfterWriting = await writer.callCount()
        XCTAssertEqual(writerCallsAfterWriting, 1)
    }

    func testOrdinaryDisclosureUsesSemanticCriticsWithoutChangingThePlannedQuestion() async throws {
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "event_development_clarified",
                focus: "事情如何发展以及用户当时做了什么",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问事情如何发展"
        )
        let planCritic = PassingPlanCritic()
        let writer = PlainDisclosureWriter()
        let writerCritic = CriticTestCritic()
        let controller = RemoteReflectionTurnController(
            planner: StaticTurnPlanner(plan: plan),
            planCritic: planCritic,
            writer: writer,
            critic: writerCritic
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .contextualDisclosure,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .contextualDisclosure,
                allowedStages: [.contextualDisclosure],
                allowedActions: [.none],
                allowedReplyIntents: [.exploreContext]
            ),
            recentMessages: [.init(role: .user, content: "我已经说明了事情是怎么发生的。")],
            semanticMemory: .init(),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let planned = try await controller.plan(to: request)
        let written = try await controller.write(request: request, validatedPlan: planned)
        let planCriticCalls = await planCritic.callCount()
        let writerCriticCalls = await writerCritic.callCount()
        let writerCalls = await writer.callCounts()

        XCTAssertFalse(written.reply.hasPrefix("你提到"))
        XCTAssertEqual(written.reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertEqual(
            planned.memoryUpdate.episodeStructure,
            plan.memoryUpdate.episodeStructure
        )
        XCTAssertEqual(planCriticCalls, 1)
        XCTAssertEqual(writerCriticCalls, 2)
        XCTAssertEqual(writerCalls.initial, 1)
        XCTAssertEqual(writerCalls.revisions, 1)
    }

    func testFailedSoftWriterRewriteReturnsOriginalLegalReplyAndKeepsMemoryPatch() async throws {
        let episode = TurnEpisodeStructure(
            concreteFacts: ["一件具体事件"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户说明了自己的处理"],
            eventProcessStatus: .present,
            possibleContributors: ["事情的发展经过"],
            impactStatus: .unresolved
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(episodeStructure: episode),
            nextPrompt: .openQuestion(
                purpose: "continue_event_development",
                focus: "同一事件的下一段经过",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只问同一个自然问题"
        )
        let writer = FailingSoftRevisionWriter()
        let critic = CriticTestCritic()
        let controller = RemoteReflectionTurnController(
            planner: StaticTurnPlanner(plan: plan),
            planCritic: PassingPlanCritic(),
            writer: writer,
            critic: critic
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .contextualDisclosure,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .contextualDisclosure,
                allowedStages: [.contextualDisclosure],
                allowedActions: [.none],
                allowedReplyIntents: [.exploreContext]
            ),
            recentMessages: [.init(role: .user, content: "用户继续说明同一件事情。")],
            semanticMemory: .init(),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.write(request: request, validatedPlan: plan)
        let calls = await writer.callCounts()
        let criticCalls = await critic.callCount()

        XCTAssertTrue(result.reply.hasPrefix("你提到"))
        XCTAssertEqual(result.reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertEqual(plan.memoryUpdate.episodeStructure, episode)
        XCTAssertEqual(calls.initial, 1)
        XCTAssertEqual(calls.revisions, 1)
        XCTAssertEqual(criticCalls, 1)
    }

    func testTenderClarificationWithoutStoredUnderstandingNeedsNoPlannerRepair() async throws {
        let plan = LLMTurnResponsePlan(
            requestedStage: .tenderConfirmation,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .tenderSummary),
            replyIntent: .requestTenderConfirmation,
            replyGuidance: "承接含糊回答并保留同一个确认对象"
        )
        let planCritic = PassingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: StaticTurnPlanner(plan: plan),
            planCritic: planCritic
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .tenderConfirmation
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = .confirmationRequest(target: .tenderSummary)
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .tenderConfirmation,
            condition: .cardMediated,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [.init(role: .user, content: "我暂时不知道怎么说。")],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(result.replyIntent, .requestTenderConfirmation)
        XCTAssertNil(result.memoryUpdate.tenderUnderstanding)
        XCTAssertEqual(criticCalls, 0)
        XCTAssertNoThrow(try ReflectionProtocolController().validate(result, for: session))
    }

    func testPlannerDoesNotRepairAgainOnlyBecauseTenderMemoryIsMissing() async throws {
        let planner = ChainedInvalidTenderPlanner()
        let planCritic = PassingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic
        )
        var session = ReflectionSession()
        session.protocolVersion = 2
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.situationUnderstanding =
            "论文和 app 进展不理想，用户感到焦虑，并已说明这关系到毕业与工作。"
        session.semanticMemory.answeredQuestionPurposes = [
            "event_sequence_clarified",
            "personal_meaning_clarified",
        ]
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .contextualDisclosure,
            condition: .cardMediated,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [
                .init(role: .assistant, content: "论文和这个 app 为什么这么重要？"),
                .init(role: .user, content: "它关系到科研能力、毕业和找工作。"),
            ],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            presentedTrackingCues: [],
            activeTrackingPresentation: nil,
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let calls = await planner.callCount()
        let corrections = await planner.corrections()
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(criticCalls, 1)
        XCTAssertEqual(result.requestedStage, .tenderConfirmation)
        XCTAssertEqual(result.replyIntent, .presentTenderSummary)
        XCTAssertNil(result.memoryUpdate.tenderUnderstanding)
        XCTAssertTrue(corrections[1]?.contains("CURRENT ALLOWED OPERATIONS") == true)
        XCTAssertNoThrow(
            try ReflectionProtocolController().validate(result, for: session)
        )
    }

    func testOrdinaryDisclosureLetsSemanticPlanCriticChooseProgression() async throws {
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
            card: .init(
                imageIsDisplayed: true,
                visualScaffolds: [],
                reflectionApproaches: nil,
                prohibitedClaims: []
            ),
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)
        let plannerCalls = await planner.callCount()
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(result.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(result.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(
            result.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户刚刚形成的现实映射"
        )
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertEqual(criticCalls, 1)
    }

    func testTypedCardRealityMappingIsCanonicalizedBeforeAnotherSemanticAudit() async throws {
        let candidate = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "用户此前形成的画面关系",
                    realityMapping: "用户刚刚形成的画面—现实联系",
                    source: .userAuthored
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "repeat_connection",
                focus: "重复询问已经形成的联系"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "错误地再问一次联系"
        )
        let planCritic = PassingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: StaticTurnPlanner(plan: candidate),
            planCritic: planCritic
        )
        let authorization = TurnProtocolOperation(
            requestedStage: .cardReflection,
            replyIntent: .authorizeCardGuidance,
            localAction: .shareCardGuidance
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none, .shareCardGuidance],
                allowedReplyIntents: [.inviteCardConnection, .authorizeCardGuidance],
                allowedOperations: [
                    .init(
                        requestedStage: .cardReflection,
                        replyIntent: .inviteCardConnection,
                        localAction: .none
                    ),
                    authorization,
                ]
            ),
            recentMessages: [
                .init(role: .user, content: "用户用自己的话形成了画面与现实之间的关系。"),
            ],
            semanticMemory: .init(cardImageRelation: "用户此前形成的画面关系"),
            trackingCandidates: [],
            card: .init(
                imageIsDisplayed: true,
                visualScaffolds: [],
                reflectionApproaches: nil,
                prohibitedClaims: []
            ),
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)

        XCTAssertEqual(result.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(result.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(result.nextPrompt?.kind, TurnNextPromptKind.none)
        XCTAssertEqual(
            result.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户刚刚形成的画面—现实联系"
        )
        let criticCalls = await planCritic.callCount()
        XCTAssertEqual(criticCalls, 0)
    }

    func testSemanticCriticCanRemoveUnsupportedOptionalCardReferenceWithoutChangingTurn() async throws {
        let candidate = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(cardNegotiatedMeaning: "一段仍由用户发展或修正的候选理解"),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "提出一个具体、可继续回答的问题",
            cardReferenceSelection: .init(relationIndex: 0)
        )
        let critic = RejectingCardReferencePlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: StaticTurnPlanner(plan: candidate),
            planCritic: critic
        )
        let references = try XCTUnwrap(CardService().allCards[0].referenceGuidance)
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.presentCardReading],
                allowedOperations: [
                    .init(
                        requestedStage: .cardReflection,
                        replyIntent: .presentCardReading,
                        localAction: .none
                    ),
                ]
            ),
            recentMessages: [
                .init(role: .user, content: "用户已经形成自己的画面解释与现实连接。"),
            ],
            semanticMemory: .init(
                cardRealityConnection: .init(
                    imageRelation: "用户形成的画面关系",
                    realityMapping: "用户确认的现实连接",
                    source: .userAuthored
                )
            ),
            trackingCandidates: [],
            card: .init(
                imageIsDisplayed: true,
                visualScaffolds: [],
                reflectionApproaches: .standard,
                referenceGuidance: references,
                prohibitedClaims: []
            ),
            protocolCorrection: nil
        )

        let result = try await controller.plan(to: request)

        XCTAssertNil(result.cardReferenceSelection)
        XCTAssertEqual(result.replyIntent, candidate.replyIntent)
        XCTAssertEqual(result.nextPrompt, candidate.nextPrompt)
        XCTAssertEqual(result.memoryUpdate, candidate.memoryUpdate)
        let calls = await critic.callCount()
        XCTAssertEqual(calls, 2)
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

        XCTAssertEqual(
            result.reply,
            "这是修订后更自然、没有字段拼接的总结。沿着这段整理，你现在最想继续说哪一部分？"
        )
        let writerCounts = await writer.callCounts()
        let criticCalls = await critic.callCount()
        let plannerCalls = await planner.callCount()
        XCTAssertEqual(writerCounts.initial, 1)
        XCTAssertEqual(writerCounts.revisions, 1)
        XCTAssertEqual(criticCalls, 2)
        XCTAssertEqual(plannerCalls, 0)
    }

    func testRealityConnectionCriticHidesOtherLifeSearchAndRewritesToFocalEpisode() async throws {
        let writer = RealityConnectionBoundaryWriter()
        let critic = RealityConnectionBoundaryCritic(passAfterRevision: true)
        let controller = RemoteReflectionTurnController(
            planner: UnusedTurnPlanner(),
            planCritic: PassingPlanCritic(),
            writer: writer,
            critic: critic
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "card_reality_connection",
                focus: "比较画面关系与当前项目事件"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "只把用户描述的照顾关系与当前项目事件作比较"
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.inviteCardConnection]
            ),
            recentMessages: [
                .init(
                    role: .user,
                    content: "一个人提供照顾，另一个人停下来接受照顾。"
                ),
            ],
            semanticMemory: .init(
                cardImageRelation: "一方提供照顾，另一方停下来接受照顾"
            ),
            trackingCandidates: [],
            card: .init(
                imageIsDisplayed: true,
                realityAnchor: .init(
                    concreteFacts: ["方案已经基本完成"],
                    eventProcess: ["用户持续修改方案"],
                    impacts: ["最后错过截止时间"]
                ),
                visualScaffolds: [],
                reflectionApproaches: nil,
                prohibitedClaims: []
            ),
            protocolCorrection: nil
        )

        let result = try await controller.write(request: request, validatedPlan: plan)

        XCTAssertFalse(result.reply.contains("自己的生活里"))
        XCTAssertTrue(result.reply.contains("这个项目"))
        XCTAssertTrue(result.reply.contains("持续修改"))
        let writerCalls = await writer.callCounts()
        let criticCalls = await critic.callCount()
        XCTAssertEqual(writerCalls.initial, 1)
        XCTAssertEqual(writerCalls.revisions, 1)
        XCTAssertEqual(criticCalls, 2)
    }

    func testTwoSemanticDriftsUseOneBoundedLLMFallbackWithoutReplanning() async throws {
        let writer = TwiceDriftingRealityWriter()
        let critic = RealityConnectionBoundaryCritic(passAfterRevision: false)
        let planner = UnusedTurnPlanner()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: PassingPlanCritic(),
            writer: writer,
            critic: critic
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "card_reality_connection",
                focus: "比较画面关系与当前项目事件"
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "围绕当前项目事件提出一个具体连接问题"
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .cardReflection,
                allowedStages: [.cardReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.inviteCardConnection]
            ),
            recentMessages: [
                .init(role: .user, content: "一个人递水，另一个人停下来接过水。"),
            ],
            semanticMemory: .init(
                cardImageRelation: "一方递水，另一方停下来接受"
            ),
            trackingCandidates: [],
            card: .init(
                imageIsDisplayed: true,
                realityAnchor: .init(
                    concreteFacts: ["方案已经基本完成"],
                    eventProcess: ["持续修改而没有提交"],
                    impacts: ["错过截止时间"]
                ),
                visualScaffolds: [],
                reflectionApproaches: nil,
                prohibitedClaims: []
            ),
            protocolCorrection: nil
        )

        let result = try await controller.write(request: request, validatedPlan: plan)

        XCTAssertEqual(
            result.reply,
            "画面里有人停下来接过水，而这个项目里你没有停下修改。把这两个动作放在一起，截止时间前最明显的差别出现在哪里？"
        )
        let writerCalls = await writer.callCounts()
        let criticCalls = await critic.callCount()
        let plannerCalls = await planner.callCount()
        XCTAssertEqual(writerCalls.initial, 1)
        XCTAssertEqual(writerCalls.revisions, 2)
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
        最近工作挤在一起，又没有休息充分，可能让你更容易着急，也更难从错过截止时间的挫败里缓下来。不过，这些处境不能直接变成“什么都做不好”的结论。放回那次经历，哪一部分现在最压着你？
        """
        let generatedConsentReply =
            "一个具体影响不需要扩大成整体评价。接下来可以随机抽一张反思卡，它没有固定答案；你愿意试试看吗？"
        let displayedConsentReply =
            generatedConsentReply
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
                        replyGuidance: "把用户确认的 tracking 关系和现实经历整合成简短 Tender 理解，并以内容问题自然承接"
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
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: generatedConsentReply
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

        model.draft = "最压着我的还是后面的安排可能继续受影响。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.messages.last?.content, displayedConsentReply)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "premature_card_identity_removed_locally"
            }
        )
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

    func testVersionTwoFoldsComplementaryTrackingIntoTenderSummaryWithoutPresentation() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let activity = protocolTrackingCue(id: "activity")
        let contextualHypothesis =
            "你最近可能有点累。"
        let tenderReply =
            "事情一直堆着已经很吃力，你最近可能也有点累。放回当时，哪一部分最需要继续说？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .tenderConfirmation,
                        localAction: .none,
                        memoryUpdate: .init(
                            tenderUnderstanding:
                                "事情堆积已经让人吃力，最近可能也有点累"
                        ),
                        nextPrompt: .confirmationRequest(
                            target: .tenderSummary
                        ),
                        replyIntent: .presentTenderSummary,
                        replyGuidance:
                            "把应用提供的无测量值背景作为整体 Tender 理解中的一句不确定背景，只确认整体理解是否贴近"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentTenderSummary,
                        reply: tenderReply
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
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [sleep.insight!.id, activity.insight!.id],
            supportingMetrics: [.sleepDuration, .steps],
            alternativeExplanations: [],
            dialogueHypothesis: contextualHypothesis,
            relevance: .notReviewed
        )

        model.draft = "最近事情一直堆着，我当时很难耐心处理。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .tenderConfirmation)
        XCTAssertEqual(model.session.messages.last?.content, tenderReply)
        XCTAssertTrue(model.session.presentedTrackingCueIDs.isEmpty)
        XCTAssertTrue(model.session.trackingPresentations.isEmpty)
        XCTAssertNil(model.session.activeTrackingPresentationID)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.target,
            .tenderSummary
        )
        let requests = await controller.receivedRequests()
        XCTAssertTrue(requests.first?.trackingCandidates.isEmpty == true)
        XCTAssertEqual(
            requests.first?.contextualLoadCue?.hypothesis,
            contextualHypothesis
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
    }

    func testVersionTwoRejectsFreshTrackingPresentationBeforeWriterRuns() async {
        let sleep = protocolTrackingCue(id: "sleep")
        let activity = protocolTrackingCue(id: "activity")
        let illegalPresentation = LLMTurnResponsePlan(
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
            replyGuidance: "尝试打开一个新版流程不允许的独立 tracking 确认"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(illegalPresentation), .success(illegalPresentation)],
            writings: []
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareVersionTwoDisclosure(model)
        model.session.trackingCues = [sleep, activity]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [sleep.insight!.id, activity.insight!.id],
            supportingMetrics: [.sleepDuration, .steps],
            alternativeExplanations: [],
            dialogueHypothesis:
                "你最近可能有点累。",
            relevance: .notReviewed
        )

        model.draft = "最近事情一直堆着，处理起来越来越吃力。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.session.trackingPresentations.isEmpty)
        XCTAssertTrue(model.session.presentedTrackingCueIDs.isEmpty)
        XCTAssertNil(model.session.activeTrackingPresentationID)
        XCTAssertNil(model.session.semanticMemory.nextPrompt)
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 0)
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.trackingCandidates.isEmpty })
        XCTAssertTrue(requests.allSatisfy { $0.contextualLoadCue != nil })
        XCTAssertTrue(model.canRetry)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_response_regeneration_requested")
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_response_failed_twice")
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
                        reply: "这些近期变化可能让当时更难应对，但并不能决定事情的原因或责任。放回当时，哪一部分最值得继续说？"
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
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实联系",
            source: .userAuthored
        )
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
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_mapping_explicit_acceptance_committed_locally"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content == "local_card_mapping_resolution"
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
    }

    func testPendingCardMappingDecodeRepairUsesCompleteConfirmationContract() async {
        let mappingReference = "decode-repair-card-mapping"
        let directReply = "把这个区别放回现实，接下来最需要坦诚面对的一个具体影响是什么？"
        let diagnostic = TurnPlannerDecodingDiagnostic(
            kind: "key_not_found",
            keyPath: "resolvedConfirmation.decision",
            invalidNextPromptKind: "candidReflection"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .failure(LLMTurnControllerClientError.plannerDecoding(diagnostic)),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        resolvedConfirmation: .init(
                            target: .cardMapping,
                            decision: .accepted,
                            referenceID: mappingReference
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "只提交当前 cardMapping 接受事务"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "fierce_behavior_or_impact_clarified",
                            focus: "一个仍需面对的具体影响"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "提出一条新的现实反思问题"
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
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.cardDisplayState = .displayed
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实联系",
            source: .userAuthored
        )
        model.session.semanticMemory.cardNegotiatedMeaning = "等待确认的候选解读"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: mappingReference
        )

        model.draft = "我认同这个方向。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertTrue(model.session.cardMappingConfirmed)
        XCTAssertEqual(model.session.messages.last?.content, directReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "Repair the complete confirmation transaction"
            ) == true
        )
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "This transaction only commits the old confirmation"
            ) == true
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
        XCTAssertEqual(counts.writes, 1)
    }

    func testCurrentSourceOnlyConnectionPatchNeverReachesWriterOrChangesSession() async {
        func sourceOnlyPlan() -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(cardRealityMappingSource: .userAuthored),
                nextPrompt: .openQuestion(
                    purpose: "continue_current_connection",
                    focus: "继续当前事件中的画面—现实连接"
                ),
                replyIntent: .inviteCardConnection,
                replyGuidance: "尝试提交 source-only 旧字段"
            )
        }
        let turnController = ScriptedReflectionTurnController(
            plans: [.success(sourceOnlyPlan()), .success(sourceOnlyPlan())],
            writings: []
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: turnController,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardConnectionAttemptCount = 1
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "把画面关系连接到当前事件"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "把画面里的关系放回刚才的事情，会让你想到什么？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "我想到了一点联系。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        XCTAssertNil(model.session.semanticMemory.cardRealityMappingSource)
        XCTAssertNil(model.session.semanticMemory.cardImageRelation)
        XCTAssertFalse(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        let calls = await turnController.callCounts()
        XCTAssertEqual(calls.plans, 3)
        XCTAssertEqual(calls.writes, 0)
        let requests = await turnController.receivedRequests()
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "one complete canonical cardRealityConnection"
            ) == true
        )
        XCTAssertFalse(requests[1].permissions.allowedActions.contains(.shareCardGuidance))
    }

    func testMalformedMappingAuthorizationRecoversWithoutVisibleInterruption() async {
        let candidateReply =
            "画面里的照顾让一个人停下来接受水，而你把持续修改理解成让方案变好的一种方式。沿着这个联系回到截止时间前，最难停下来的具体时刻是什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardRealityMappingSource: .userAuthored
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "continue_current_connection",
                            focus: "继续当前事件中的画面—现实连接"
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "尝试保存用户形成的连接"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .init(kind: .shareCardGuidance),
                        memoryUpdate: .init(),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .authorizeCardGuidance,
                        replyGuidance: ""
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardRealityConnection: .init(
                                imageRelation: "画面中一方提供照顾，另一方停下来接受照顾",
                                realityMapping: "用户把持续修改方案与试图让方案变好联系起来",
                                source: .userRevised
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "完整提交用户修订的现实连接"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardNegotiatedMeaning:
                                "照顾方案的意图与持续修改造成的延期同时存在"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "围绕当前焦点事件呈现一条可继续发展的候选解读"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: candidateReply
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[3]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardImageRelation =
            "画面中一方提供照顾，另一方停下来接受照顾"
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["昨天没有按时提交项目方案"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["方案基本完成后仍持续修改"],
            eventProcessStatus: .present,
            impactStatus: .present,
            impacts: ["错过了截止时间"]
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "把画面关系连接到当前焦点事件"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "画面里的这段关系，放回刚才错过截止时间的事情里，会让你想到什么？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "有点像，就是希望变好。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 0)
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把持续修改方案与试图让方案变好联系起来"
        )
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.source,
            .userRevised
        )
        XCTAssertNotNil(model.session.cardGuidanceTransactionID)
        XCTAssertFalse(model.session.pendingCardGuidanceTurn)
        XCTAssertEqual(model.session.messages.last?.content, candidateReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_continuity_recovery_succeeded"
            }
        )

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertFalse(
            requests[1].permissions.allowedActions.contains(.shareCardGuidance)
        )
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "one complete canonical cardRealityConnection"
            ) == true
        )
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.concreteFacts,
            ["昨天没有按时提交项目方案"]
        )
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.eventProcess,
            ["方案基本完成后仍持续修改"]
        )
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.impacts,
            ["错过了截止时间"]
        )
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.writes, 1)
    }

    func testPostGuidanceRecoveryPreservesConfirmedConnectionAndRepairsOnlyReading() async {
        let confirmed = TurnCardRealityConnection(
            imageRelation: "画面中两个部分正在重新安排彼此的位置",
            realityMapping: "用户把这种重新安排联系到当前事件中的处理方式",
            source: .userAuthored
        )
        let visibleReply = "沿着你已经形成的连接，当前最值得继续看的具体时刻是什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardRealityConnection: .init(
                                imageRelation: confirmed.imageRelation,
                                realityMapping: "试图在后续解读中改写现实连接",
                                source: .userRevised
                            ),
                            cardNegotiatedMeaning: "错误地依赖改写 connection 的候选解读"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "尝试生成后续候选解读"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardNegotiatedMeaning: "只修复当前 post-guidance 候选解读"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "保留既有 connection，只生成当前候选解读"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: visibleReply
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardGuidanceShared = true
        model.session.cardConnectionAttemptCount = 1
        model.session.semanticMemory.cardRealityConnection = confirmed
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "continue_post_guidance_reading",
            focus: "继续当前卡牌解读"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "沿着刚才的连接，你还想继续看哪一部分？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "我想继续看看当时最难停下来的地方。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, confirmed)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertEqual(model.session.messages.last?.content, visibleReply)

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "Preserve the confirmed cardRealityConnection unchanged"
            ) == true
        )
        XCTAssertFalse(
            requests[1].protocolCorrection?.contains("cardRealityMapping") == true
        )
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.writes, 1)
    }

    func testUserInputIsPersistedBeforePlannerAndVisibleCommitIsDurable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BeyondComfort-Persistence-\(UUID().uuidString)",
            isDirectory: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let sessionID = UUID()
        let controller = PersistenceObservingTurnController(
            store: store,
            sessionID: sessionID
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.id = sessionID
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "focal_event_clarified",
            focus: "当前具体事件",
            disclosurePurpose: .identifyConcreteEpisode,
            disclosureTarget: .focalEvent
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "最近发生了什么？",
                state: .eventDisclosure
            ),
        ]
        model.draft = "我昨天没有按时提交项目方案。"
        model.send()
        await waitUntilIdle(model)

        let didObservePersistedInput = await controller.didObservePersistedInput()
        XCTAssertTrue(didObservePersistedInput)
        let saved = try await store.load(id: sessionID)
        XCTAssertEqual(
            saved?.messages.last(where: { $0.role == .user })?.content,
            "我昨天没有按时提交项目方案。"
        )
        XCTAssertEqual(
            saved?.messages.last(where: { $0.role == .assistant })?.content,
            "截止时间前，事情是怎样一步步发展到没有提交的？"
        )
        XCTAssertFalse(model.canRetry)
    }

    func testResumeAfterSilentGuidanceCommitRunsOnlyOneVisibleSuccessor() async {
        let visibleReply =
            "你把继续修改和希望方案变好连在了一起；回到截止时间前，哪一次继续修改最直接地挤掉了提交？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardNegotiatedMeaning:
                                "希望方案变好的用意与持续修改造成的延期同时存在"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "围绕当前项目事件提出一条可继续修正的候选理解"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: visibleReply
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
        var restored = ReflectionSession()
        restored.protocolVersion = ReflectionSession.currentProtocolVersion
        restored.protocolStage = .cardReflection
        restored.condition = .cardMediated
        restored.stage = .cardInterpretation
        restored.workflowPhase = .cardAssociation
        restored.card = CardService().allCards[3]
        restored.cardDisplayState = .displayed
        restored.cardGuidanceShared = true
        restored.pendingCardGuidanceTurn = true
        restored.cardGuidanceTransactionID = "card-guidance-restored-turn"
        restored.semanticMemory.cardRealityConnection = .init(
            imageRelation: "一方提供照顾，另一方停下来接受照顾",
            realityMapping: "用户把持续修改方案与试图让方案变好联系起来",
            source: .userRevised
        )
        restored.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["昨天没有按时提交项目方案"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["方案基本完成后仍持续修改"],
            eventProcessStatus: .present,
            impactStatus: .present,
            impacts: ["错过截止时间"]
        )
        let userID = UUID()
        restored.messages = [
            .init(
                id: userID,
                role: .user,
                content: "有点像，就是希望变好。",
                state: .cardInterpretation
            ),
        ]

        model.resume(
            .init(
                id: restored.id.uuidString,
                remoteID: nil,
                session: restored,
                updatedAt: .now
            )
        )
        await waitUntilIdle(model)

        XCTAssertFalse(model.session.pendingCardGuidanceTurn)
        XCTAssertEqual(
            model.session.messages.filter {
                $0.role == .assistant && $0.replyToMessageID == userID
            }.map(\.content),
            [visibleReply]
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "pending_card_guidance_turn_resumed"
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "silent_transaction_committed"
            }
        )
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 1)
        XCTAssertEqual(calls.writes, 1)
    }

    func testNaturalAnswerToCardReadingQuestionResolvesMappingWithoutApprovalWords() async {
        let mappingReference = "implicit-card-mapping"
        let directReply = "这个节点已经更清楚了。它目前带来的哪一个实际影响最需要被正视？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        resolvedConfirmation: .init(
                            target: .cardMapping,
                            decision: .accepted,
                            referenceID: mappingReference
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "提交自然回应所隐含的 cardMapping 接受事务"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "supported_impact_distinguished",
                            focus: "用户自然回应中出现的现实节点"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "承接最新内容并只推进一个有现实意义的辨析"
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
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.cardDisplayState = .displayed
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户建立的画面关系",
            realityMapping: "用户建立的现实联系",
            source: .userAuthored
        )
        model.session.semanticMemory.cardNegotiatedMeaning = "一段等待协商的候选解读"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: mappingReference
        )
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [.sleepDuration],
            alternativeExplanations: [],
            dialogueHypothesis: "近期可用于恢复的时间可能比平时少一些。",
            relevance: .offered
        )

        model.draft = "它主要出现在我从判断转向行动的那个节点。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.session.cardMappingConfirmed)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.messages.last?.content, directReply)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "card_mapping_explicit_acceptance_recognized_locally"
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
        let requests = await controller.receivedRequests()
        XCTAssertEqual(
            requests.first?.contextualLoadCue?.relevance,
            .offered
        )
        XCTAssertNil(requests.last?.contextualLoadCue)
        XCTAssertNil(model.session.semanticMemory.contextRelationship)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)
    }

    func testCurrentDirectConditionUsesOnlySimpleGentleControlGenerator() async {
        let controller = ScriptedReflectionTurnController(
            plans: [],
            writings: []
        )
        let simpleGenerator = ScriptedSimpleGentleReflectionGenerator(
            replies: [
                .init(
                    reply: "连续遇到挫折后开始怀疑自己，确实会让人很难受。此刻最压着你的是什么？"
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            simpleGentleReflectionGenerator: simpleGenerator,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .directLLM
        model.session.stage = .welcome
        model.session.context.eventDescription = "不应进入对照组 prompt 的结构化处境"
        model.session.trackingCues = [protocolTrackingCue(id: "sleep")]

        model.begin()
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.stage, .eventDisclosure)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_started"
            }
        )

        let userText = "实验连续失败了好几次，我开始怀疑自己是不是不适合做研究。"
        model.draft = userText
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(
            model.session.messages.last?.content,
            "连续遇到挫折后开始怀疑自己，确实会让人很难受。此刻最压着你的是什么？"
        )
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertNil(model.session.semanticMemory.tenderUnderstanding)
        XCTAssertFalse(model.session.cardGuidanceShared)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_reply_presented"
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 0)
        XCTAssertEqual(counts.writes, 0)
        let requests = await simpleGenerator.receivedMessages()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.last?.content, userText)
        XCTAssertFalse(
            requests.first?.contains {
                $0.content.contains("不应进入对照组 prompt 的结构化处境")
            } ?? true
        )
    }

    func testSimpleGentleControlOffersSwiftOwnedCompletionAndLogsRegeneration() async {
        let simpleGenerator = ScriptedSimpleGentleReflectionGenerator(
            replies: [
                .init(
                    reply: "这几次没有达到预期，确实让你承受了不少压力。现在可以先停在最想整理的部分。",
                    generationAttempts: 2
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: ScriptedReflectionTurnController(plans: [], writings: []),
            simpleGentleReflectionGenerator: simpleGenerator,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .directLLM
        model.begin()
        for index in 1...3 {
            model.session.messages.append(
                .init(role: .user, content: "先前的用户回应 \(index)", state: .eventDisclosure)
            )
            model.session.messages.append(
                .init(role: .assistant, content: "先前的温和回应 \(index)", state: .eventDisclosure)
            )
        }

        model.draft = "我想再整理一下这次失败带来的压力。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.canCompleteSimpleGentleControl)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_completion_offer_available"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_reply_regenerated_once"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("simple_gentle_control_reply_latency_ms_")
            }
        )

        model.finishSimpleGentleControl()

        XCTAssertEqual(model.session.protocolStage, .complete)
        XCTAssertEqual(model.session.stage, .completed)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_completion_offer_accepted"
            }
        )
    }

    func testSimpleGentleControlSoftBoundaryAllowsConversationToContinue() async {
        let boundaryReply = "你已经把这次经历中最在意的部分说得更清楚了。还有哪一点想继续谈谈？"
        let continuedReply = "可以，我们继续留在这个部分，不急着得出结论。"
        let simpleGenerator = ScriptedSimpleGentleReflectionGenerator(
            replies: [
                .init(reply: boundaryReply),
                .init(reply: continuedReply),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: ScriptedReflectionTurnController(plans: [], writings: []),
            simpleGentleReflectionGenerator: simpleGenerator,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .directLLM
        model.begin()
        for index in 1...7 {
            model.session.messages.append(
                .init(role: .user, content: "先前的用户回应 \(index)", state: .eventDisclosure)
            )
            model.session.messages.append(
                .init(role: .assistant, content: "先前的温和回应 \(index)", state: .eventDisclosure)
            )
        }

        model.draft = "这是这一轮最后想补充的内容。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, boundaryReply)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.stage, .eventDisclosure)
        XCTAssertTrue(model.canCompleteSimpleGentleControl)
        XCTAssertTrue(model.hasReachedSimpleGentleControlSoftBoundary)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "simple_gentle_control_soft_boundary_reached"
            }
        )

        model.draft = "我还想继续谈谈对下一次实验的担心。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, continuedReply)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.stage, .eventDisclosure)
    }

    func testSimpleGentleControlUsesConditionNeutralSafetyInterruption() async {
        let simpleGenerator = ScriptedSimpleGentleReflectionGenerator(replies: [])
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: ScriptedReflectionTurnController(plans: [], writings: []),
            simpleGentleReflectionGenerator: simpleGenerator,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .directLLM
        model.begin()

        model.draft = "我有时候觉得自己快活不下去了。"
        model.send()

        XCTAssertEqual(model.session.protocolStage, .safetySupport)
        XCTAssertEqual(model.session.stage, .safetySupport)
        XCTAssertFalse(model.session.messages.last?.content.contains("抽卡") ?? true)
        XCTAssertTrue(model.session.messages.last?.content.contains("暂停普通反思") ?? false)
        let safetyGenerationRequests = await simpleGenerator.receivedMessages()
        XCTAssertTrue(safetyGenerationRequests.isEmpty)
    }

    func testMissingFinalNarrativeLocksProgressAndRepairsSameOperation() async {
        let finalReply = "这次经历里，现实负担提供了背景，但你也已经看清需要承担的具体影响。回看整个过程，你最想保留的是哪一部分？"
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

    func testCurrentDisclosureBridgesToCardConsentWithoutAnExtraAnalysisQuestion() async {
        let expectedReply =
            "一个具体步骤没有完成，也确实影响了后面的安排，但这不等于对整个人的否定。接下来可以看一张随机反思卡，看看画面会让你想到什么；你愿意试试吗？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            selfCriticismStatus: .present,
                            selfCriticalStatement: "用户由一次具体经历形成了整体自我评价",
                            selfCriticismLink:
                                "用户把一个具体步骤没有完成扩展成了对整个人的否定",
                            episodeStructure: .init(
                                concreteFacts: ["一项既定安排没有按预期完成"],
                                behaviorEvidenceStatus: .present,
                                behaviorEvidence: ["一个具体步骤没有完成"],
                                eventProcessStatus: .present,
                                possibleContributors: ["用户描述了一个可能影响行动的判断"],
                                impactStatus: .present,
                                impacts: ["后续安排受到影响"]
                            ),
                            tenderUnderstanding:
                                "具体行为和影响需要被承认，但不能直接扩展为对整个人的判断"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "用一个事实和一个有依据的区分直接邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .inviteCardConsent, reply: expectedReply)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "remaining_relation_clarified",
            focus: "尚未厘清的一项现实关系",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "这件事后来带来了什么具体影响？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "它确实影响了后面的安排，也让我开始整体否定自己。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.messages.last?.content, expectedReply)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .confirmationRequest)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardConsent)
        XCTAssertTrue(model.session.tenderGroundingConfirmed)
        XCTAssertTrue(
            model.session.semanticMemory.situationUnderstanding
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("最难松开的")
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
    }

    func testExactDisclosureReplayAdvancesToGroundingAndCardInvitation() async {
        let expectedReply =
            "方案基本做完后，你因为仍觉得不够好而继续修改，最后错过了提交时间。可以用一张随机反思卡换个角度看看；你愿意试试吗？"
        let episode = TurnEpisodeStructure(
            concreteFacts: ["昨天没有按时提交项目方案"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["方案基本完成后仍持续修改，没有提交"],
            eventProcessStatus: .present,
            possibleContributors: ["用户持续认为方案还不够好"],
            impactStatus: .unresolved
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            episodeStructure: episode
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "用已确认行为和结果简短 grounding，并在同一回复邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .inviteCardConsent, reply: expectedReply)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "event_process_clarified",
            focus: "事情如何发展到没有按时提交",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )
        model.session.messages = [
            .init(
                role: .user,
                content: "我昨天没有按时提交项目方案。",
                state: .eventDisclosure
            ),
            .init(
                role: .assistant,
                content: "没按时提交之前，事情是怎么发展到这个结果的？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "方案其实基本做完了，但我一直觉得还不够好，改来改去就错过时间了。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.semanticMemory.episodeStructure, episode)
        XCTAssertEqual(
            model.session.semanticMemory.receivedDisclosureQuestionPurposes,
            [.clarifyEventProcess]
        )
        XCTAssertEqual(model.session.messages.last?.content, expectedReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("怎么决定继续修改")
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("是否想过停止")
            }
        )
    }

    func testCurrentFailedCardConnectionUsesOneScaffoldThenOneCandidate() async {
        let scaffoldReply =
            "先只抓住画面里已经发生的关系变化。现实中有没有一个具体时刻，也出现了相似或相反的变化？"
        let candidateReply =
            "一种可能是，画面里的关系变化对应着现实中某个尚未发生的转换；如果从这个可能出发，最接近的是哪个具体时刻？完全不对也可以直接放下。"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "card_connection_scaffold",
                            focus: "用用户已经形成的一条画面关系缩小连接任务"
                        ),
                        replyIntent: .developCardImage,
                        replyGuidance: "第一次没有形成现实连接，只问一个更小的连接问题"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardConnectionOutcome: .noConnectionFound
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "candidate_card_connection",
                            focus: "提供一条可拒绝候选并允许发展、修正或放下"
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "scaffold 后仍未连接，只提供一条可拒绝候选"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(realizedIntent: .developCardImage, reply: scaffoldReply)
                ),
                .success(
                    .init(realizedIntent: .inviteCardConnection, reply: candidateReply)
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardImageDevelopmentTurnCount = 1
        model.session.cardConnectionAttemptCount = 1
        model.session.semanticMemory.cardImageRelation =
            "用户已经形成一条人物、空间与变化之间的画面关系"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "邀请用户建立画面与现实的联系"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "画面里的这种关系变化，会让你想到现实中的什么吗？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "我暂时想不到它和现实有什么联系。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, scaffoldReply)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)

        model.draft = "缩小以后还是没有想到具体联系。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.messages.last?.content, candidateReply)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 2)
        XCTAssertFalse(model.session.cardConnectionScaffoldPending)
        XCTAssertNil(model.session.semanticMemory.cardRealityMapping)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.card?.reflectionApproaches == nil })
        XCTAssertTrue(
            requests.allSatisfy {
                $0.card?.prohibitedClaims.contains(where: {
                    $0.contains("接受或修订现实映射前")
                }) == true
            }
        )
    }

    func testAcceptedCardDrawShowsOnlyOneObservationReplyAfterImageDisplay() async {
        let consentReference = "card-consent-1"
        let observationReply =
            "这张卡是随机抽取的，也没有固定答案。先只看画面，你觉得这里正在发生什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [],
            writings: []
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
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_consent_accepted_locally"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_selected_uniform_random"
            }
        )
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
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "card_image_observation"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_observation_invitation_presented_locally"
            }
        )

        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 0)
        XCTAssertEqual(calls.writes, 0)
    }

    func testCurrentUserAuthoredCardConnectionFlowsDirectlyIntoCandidateReading() async {
        let candidateReply =
            "你已经把画面中的改变和现实里想放下的一项负担连在了一起。一种可能的读法是，这张图没有替你判断那段经历，而是让‘发生过的具体事情’和‘继续背着它评价整个人’显出了区别；你也可以继续改写这个理解。"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["card_reality_connection"],
                            cardRealityConnection: .init(
                                imageRelation: "一个人物正在改变随身物品的安排",
                                realityMapping: "用户把画面中的改变与现实里想放下的一项负担联系起来",
                                source: .userAuthored
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "repeat_card_connection",
                            focus: "再次确认已经给出的画面—现实联系"
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "先确认这条联系，再决定是否继续"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            contextCueOffered: true,
                            cardNegotiatedMeaning:
                                "把具体经历与持续背负的整体评价区分开"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "沿用用户自己的连接给出可修改或拒绝的温和候选解读"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: candidateReply
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [.sleepDuration],
            alternativeExplanations: [],
            dialogueHypothesis: "近期可用于恢复的时间可能比平时少一些。",
            relevance: .notReviewed
        )
        model.session.semanticMemory.cardImageRelation =
            "一个人物正在改变随身物品的安排"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "邀请用户把画面过程连接到现实"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "把画面里的这个变化放回现实，会让你想到什么？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "我好像也想在现实里放下一直背着的一项负担。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把画面中的改变与现实里想放下的一项负担联系起来"
        )
        XCTAssertNil(model.session.semanticMemory.cardInterpretiveTension)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardMapping)
        XCTAssertEqual(model.session.messages.last?.content, candidateReply)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
        let requests = await controller.receivedRequests()
        XCTAssertNil(requests.first?.contextualLoadCue)
        XCTAssertEqual(
            requests.last?.contextualLoadCue?.hypothesis,
            "近期可用于恢复的时间可能比平时少一些。"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "contextual_cue_offered_after_card_mapping"
            }
        )
    }

    func testPrematureCardReadingRepairAuthorizesUserMappingBeforeCandidateReading() async {
        let candidateReply =
            "画面中的关系会从停留在一个局部转向重新安排整体，而你注意到现实中的自己有时会持续停在一个局部。把两者放在一起，一种可能是先看整体是否已经足够继续，而不是让一个部分决定全部进度；这个方向也可以由你继续改写。"
        let controller = ScriptedReflectionTurnController(
            plans: [
                // Reproduces the production failure: the Planner jumps directly to a reading
                // before committing the latest user-authored image-to-life mapping.
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .presentCardReading,
                        replyGuidance: "过早生成候选解读"
                    )
                ),
                // The narrowed correction must first preserve the mapping and request the silent
                // Swift-owned authorization operation.
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardRealityConnection: .init(
                                imageRelation: "画面中的人物正从关注一个局部转向重新安排多个元素的关系",
                                realityMapping: "用户把画面中重新安排整体关系与现实里持续停在一个局部形成对比",
                                source: .userRevised
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "原子提交用户修订的画面—现实连接"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardNegotiatedMeaning:
                                "从持续停在一个局部转向观察整体是否已经足够继续"
                        ),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "呈现一段可修改或拒绝的候选解读"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .presentCardReading,
                        reply: candidateReply
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardConnectionAttemptCount = 2
        model.session.cardConnectionScaffoldUsed = true
        model.session.semanticMemory.cardImageRelation =
            "画面中的人物正从关注一个局部转向重新安排多个元素的关系"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "邀请用户把画面过程连接到现实"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "画面里的这种关系变化，和你的现实处境有什么联系或不同？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "有点不同，现实中的我会一直停在一个局部，让整体很难继续。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把画面中重新安排整体关系与现实里持续停在一个局部形成对比"
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardMapping)
        XCTAssertEqual(model.session.messages.last?.content, candidateReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertFalse(
            requests[1].permissions.allowedReplyIntents.contains(.presentCardReading)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedReplyIntents.contains(.authorizeCardGuidance)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedActions.contains(.shareCardGuidance)
        )
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "A candidate card reading is not authorized yet"
            ) == true
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
        XCTAssertEqual(counts.writes, 1)
    }

    func testVersionTwoUsesSystemReflectionApproachesAfterUserAuthoredImageRealityMapping() async {
        let reading = """
        一种可能的读法是：你在画面里看到的是先了解眼前的东西，再决定怎样回应；放回现实，最近可用余力可能比平时少一些，这也让“立刻答应”与“先确认自己能承担多少”之间的区别更清楚了。我先把这个可能性留在这里；再看这张图时，有没有哪一处和刚才不太一样了？
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
                            cardRealityMappingSource: .userAuthored,
                            cardNegotiatedMeaning: "尚未展示、不得提前提交的候选解读"
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "check_card_mapping",
                            focus: "候选卡牌映射是否贴近"
                        ),
                        replyIntent: .presentCardReading,
                        replyGuidance: "申请使用用户建立的画面—现实关系，并准备一段可修改的解读"
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
                        replyGuidance: "结合已授权的用户关系和系统反思方式呈现候选解读"
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
                        replyGuidance: "结合用户自己的画面关系与现实映射，提出一段可修改或拒绝的综合解读"
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
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .possibleReducedRecovery,
            confidence: .moderate,
            activation: .unknown,
            energy: .possiblyReduced,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: "用户近期可能还没有充分恢复，处理事情时可用的精力可能比平时少。",
            relevance: .relevant
        )
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
        XCTAssertNil(requests.first?.card?.reflectionApproaches)
        XCTAssertEqual(requests.last?.card?.reflectionApproaches, .standard)
        XCTAssertNil(requests.first?.card?.referenceGuidance)
        XCTAssertEqual(
            requests.last?.card?.referenceGuidance,
            model.session.card?.referenceGuidance
        )
        XCTAssertNil(requests.first?.contextualLoadCue)
        XCTAssertEqual(
            requests.last?.contextualLoadCue?.hypothesis,
            "你最近可能还没有充分恢复，处理事情时可用的精力可能比平时少。"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "contextualized_card_reading_candidate_presented"
            }
        )
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
                .failure(ScriptedTurnError.exhausted),
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

    func testCoherentDisclosureCommitsOptionalTenderBridgeAndEntersCardConsent() async {
        let episode = TurnEpisodeStructure(
            concreteFacts: ["一件近期事件已经被说明"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户说明了自己在其中的主要处理"],
            eventProcessStatus: .present,
            possibleContributors: ["事情的发展经过已经清楚"],
            impactStatus: .unresolved
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "事件及用户的主要参与已经形成连贯叙述",
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            selfCriticismStatus: .absent,
                            episodeStructure: episode
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "轻量承接后邀请一张随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: "这件事的经过已经清楚一些了。接下来可以看一张随机反思卡，它没有固定答案；你愿意试试吗？"
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.messages = [
            .init(
                role: .assistant,
                content: "最近发生了什么？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "一件事情发生后，我也说明了自己当时怎样处理。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.semanticMemory.episodeStructure, episode)
        XCTAssertNil(model.session.semanticMemory.tenderUnderstanding)
        XCTAssertTrue(model.session.tenderGroundingConfirmed)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardConsent)
        XCTAssertEqual(
            model.session.messages.last?.content.filter { $0 == "？" || $0 == "?" }.count,
            1
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(
            requests[0].permissions.allowedReplyIntents.contains(.inviteCardConsent)
        )
    }

    func testCurrentCardDisclosureBridgesDirectlyToConsentWithoutExtraTenderQuestion() async {
        let coherentEpisode = TurnEpisodeStructure(
            concreteFacts: ["一项有明确时间要求的工作没有按时完成"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["这项工作确实超过了原定时间"],
            eventProcessStatus: .present,
            possibleContributors: ["用户说明了事情如何发展到该结果"],
            impactStatus: .uncertain
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["self_criticism_scope_clarified"],
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            selfCriticismStatus: .absent,
                            episodeStructure: coherentEpisode
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "用一个事实和一个有依据的区分直接邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: "这次没有按时完成需要面对，你也很在意别人会怎样看这件事。接下来可以看一张随机反思卡，它没有固定答案；你愿意试试吗？"
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "self_criticism_scope_clarified",
            focus: "这件事怎样连接到用户对自己的评价",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "这件事让你怎样看自己，或者担心别人怎样评价你？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "我担心别人会因此觉得我的能力不够。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "这次没有按时完成需要面对，你也很在意别人会怎样看这件事。接下来可以看一张随机反思卡，它没有固定答案；你愿意试试吗？"
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(
            requests[0].permissions.allowedReplyIntents.contains(.inviteCardConsent)
        )
        XCTAssertFalse(
            requests[0].permissions.allowedReplyIntents.contains(.presentTenderSummary)
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
    }

    func testResolvedDisclosureTargetIsRejectedBeforeWriterAndRepairUsesOpenRelation() async throws {
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "event_reopened",
                            focus: "已经明确的事件",
                            disclosurePurpose: .identifyConcreteEpisode,
                            disclosureTarget: .focalEvent
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "错误地重新询问已经明确的事件"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .needsBehaviorOrProcess
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "event_process_clarified",
                            focus: "事情如何发展到这个结果",
                            disclosurePurpose: .clarifyEventProcess,
                            disclosureTarget: .eventProcess
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "只询问仍未形成的事件过程"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .exploreContext,
                        reply: "关于这次经历，你还记得事情是怎样一步步发展到这个结果的吗？"
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.semanticMemory = TurnSemanticMemory(
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            episodeStructure: .init(
                concreteFacts: ["一次具体尝试没有得到预期结果"],
                eventProcessStatus: .unresolved,
                impactStatus: .unresolved
            ),
            nextPrompt: .openQuestion(
                purpose: "initial_event_received",
                focus: "一次具体经历",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
            )
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "可以说说最近发生的一件具体事情吗？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "我已经把发生的事情说清楚了。"
        model.send()
        await waitUntilIdle(model)

        let requests = await controller.receivedRequests()
        let counts = await controller.callCounts()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertNotNil(requests[1].protocolCorrection)
        XCTAssertFalse(
            requests[1].permissions.allowedDisclosurePurposes
                .contains(.identifyConcreteEpisode)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedDisclosureTargets.contains(.focalEvent)
        )
        XCTAssertEqual(
            model.session.messages.last?.content,
            "关于这次经历，你还记得事情是怎样一步步发展到这个结果的吗？"
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_soft_warning_nonPreferredDisclosureOrder"
            }
        )
    }

    func testDisclosurePatchCannotReopenCompletedProcessAndRepairAdvances() async throws {
        let completedPatch = try JSONDecoder().decode(
            TurnEpisodeStructure.self,
            from: Data(
                #"{"eventProcessStatus":"present","possibleContributors":["用户已经说明事情如何发展到该结果"],"impactStatus":"present","impacts":["用户已经说明这件事产生的实际影响"]}"#.utf8
            )
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            episodeStructure: completedPatch
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "event_process_clarified",
                            focus: "事情如何发展到这个结果",
                            disclosurePurpose: .clarifyEventProcess,
                            disclosureTarget: .eventProcess
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "材料已经较完整，但本轮继续询问一个具体关系"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            episodeStructure: completedPatch
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "用一个事实区分具体结果和整体判断，并邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: "这次结果确实需要面对，但它不能单独证明整体能力。接下来可以看一张随机反思卡；你愿意试试吗？"
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.condition = .cardMediated
        model.session.stage = .eventDisclosure
        model.session.semanticMemory = TurnSemanticMemory(
            receivedDisclosureQuestionPurposes: [.clarifyEventProcess],
            selfCriticismStatus: .present,
            selfCriticalStatement: "用户由一次具体结果形成了整体自我否定",
            selfCriticismLink: "用户把具体结果扩展成对整体能力的判断",
            episodeStructure: .init(
                concreteFacts: ["一次具体经历没有得到预期结果"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户说明了自己在事件中的具体处理"],
                eventProcessStatus: .unresolved,
                impactStatus: .unresolved
            ),
            nextPrompt: .openQuestion(
                purpose: "self_criticism_link_clarified",
                focus: "具体结果怎样连接到整体自我评价",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            )
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "这件事进一步让你怎样看待自己？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "我担心这说明自己的整体能力不够。"
        model.send()
        await waitUntilIdle(model)

        let requests = await controller.receivedRequests()
        let counts = await controller.callCounts()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertFalse(
            requests[1].permissions.allowedDisclosurePurposes
                .contains(.clarifyEventProcess)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedDisclosureTargets.contains(.eventProcess)
        )
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(
            model.session.messages.last?.content,
            "这次结果确实需要面对，但它不能单独证明整体能力。接下来可以看一张随机反思卡；你愿意试试吗？"
        )
        XCTAssertEqual(
            model.session.semanticMemory.episodeStructure?.eventProcessStatus,
            .present
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_soft_warning_continuedDisclosureAfterReady"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_response_regeneration_requested"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
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

        model.draft = "我最想保留的是，现实困难和需要承担的影响可以同时成立。"
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
                .failure(ScriptedTurnError.exhausted),
                .failure(ScriptedTurnError.exhausted),
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

private actor ChainedInvalidTenderPlanner: LLMTurnPlanning {
    private var calls = 0
    private var receivedCorrections: [String?] = []

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        receivedCorrections.append(request.protocolCorrection)
        switch calls {
        case 1:
            return LLMTurnResponsePlan(
                requestedStage: .tenderConfirmation,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .confirmationRequest(target: .tenderSummary),
                replyIntent: .integrateTrackingAndPresentTenderSummary,
                replyGuidance: "错误地尝试整合并不存在的 tracking 确认"
            )
        case 2:
            return LLMTurnResponsePlan(
                requestedStage: .tenderConfirmation,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .confirmationRequest(target: .tenderSummary),
                replyIntent: .presentTenderSummary,
                replyGuidance: "请求展示总结但漏掉总结对象"
            )
        default:
            return LLMTurnResponsePlan(
                requestedStage: .tenderConfirmation,
                localAction: .none,
                memoryUpdate: .init(
                    tenderUnderstanding:
                        "论文、app、毕业和工作的压力彼此牵连，焦虑和着急值得先被完整理解。"
                ),
                nextPrompt: .confirmationRequest(target: .tenderSummary),
                replyIntent: .presentTenderSummary,
                replyGuidance: "呈现一段完整、可修正的 Tender 理解"
            )
        }
    }

    func callCount() -> Int { calls }
    func corrections() -> [String?] { receivedCorrections }
}

private actor PassingPlanCritic: LLMTurnPlanCritiquing {
    private var calls = 0

    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        calls += 1
        return .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
    }

    func callCount() -> Int { calls }
}

private actor TwiceRejectingDisclosurePlanCritic: LLMTurnPlanCritiquing {
    private var calls = 0

    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        calls += 1
        if calls <= 2 {
            return .init(
                verdict: .revisePlanner,
                reasonCodes: [
                    "duplicate_question_function",
                    "resolved_relation_reopened",
                    "latest_answer_ignored",
                ],
                revisionGuidance: "Remove the completed typed purpose and advance when ready."
            )
        }
        return .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
    }

    func callCount() -> Int { calls }
}

private actor RepeatedDisclosureThenBridgePlanner: LLMTurnPlanning {
    private var calls = 0
    private var permissions: [ReflectionProtocolPermissions] = []

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        permissions.append(request.permissions)
        if calls <= 2 {
            return LLMTurnResponsePlan(
                requestedStage: .contextualDisclosure,
                localAction: .none,
                memoryUpdate: .init(),
                nextPrompt: .openQuestion(
                    purpose: calls == 1 ? "first wording" : "renamed wording",
                    focus: "已经完成的事件过程",
                    disclosurePurpose: .clarifyEventProcess,
                    disclosureTarget: .eventProcess
                ),
                replyIntent: .exploreContext,
                replyGuidance: "重复已经完成的 typed purpose"
            )
        }
        return LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "用一个事实承接并邀请随机反思卡"
        )
    }

    func callCount() -> Int { calls }
    func lastPermissions() -> ReflectionProtocolPermissions? { permissions.last }
}

private actor CardInviteTestWriter: LLMTurnWriting {
    private var calls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        calls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "可以从一张没有固定答案的随机反思卡换个角度看看，你愿意试试吗？"
        )
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        draft
    }

    func callCount() -> Int { calls }
}

private actor PassingWriterCritic: LLMTurnCritiquing {
    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse {
        .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
    }
}

private actor RejectingCardReferencePlanCritic: LLMTurnPlanCritiquing {
    private var calls = 0

    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        calls += 1
        return .init(
            verdict: .revisePlanner,
            reasonCodes: ["unsupported_card_reference_selection"],
            revisionGuidance: "Remove the unsupported optional card reference selection."
        )
    }

    func callCount() -> Int { calls }
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
                localAction: .none,
                memoryUpdate: .init(
                    cardRealityConnection: .init(
                        imageRelation: "用户已经形成了一个画面关系",
                        realityMapping: "用户刚刚形成的现实映射",
                        source: .userAuthored
                    )
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .inviteCardConnection,
                replyGuidance: "原子提交用户形成的连接，由 Swift 静默授权"
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
            reply: "你最近很累、你又很否定自己。现在最想继续说哪一部分？"
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
            reply: "这是修订后更自然、没有字段拼接的总结。沿着这段整理，你现在最想继续说哪一部分？"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor RealityConnectionBoundaryWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "在你自己的生活里，有没有什么时候，你也经历过类似这样的照顾或被照顾的关系？"
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
            reply: "画面里一方提供照顾、另一方停下来接受，而这个项目里你一直持续修改。把这两个动作放在一起，截止时间前最明显的差别出现在哪里？"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor TwiceDriftingRealityWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "在你自己的生活里，有没有类似被照顾的经历？"
        )
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        revisionCalls += 1
        let reply: String
        if revisionCalls == 1 {
            reply = "这可能说明你其实需要被照顾。这个理解对吗？"
        } else {
            reply = "画面里有人停下来接过水，而这个项目里你没有停下修改。把这两个动作放在一起，截止时间前最明显的差别出现在哪里？"
        }
        return .init(realizedIntent: plan.replyIntent, reply: reply)
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor RealityConnectionBoundaryCritic: LLMTurnCritiquing {
    private let passAfterRevision: Bool
    private var calls = 0

    init(passAfterRevision: Bool) {
        self.passAfterRevision = passAfterRevision
    }

    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse {
        calls += 1
        if passAfterRevision && calls > 1 {
            return .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
        }
        return .init(
            verdict: .reviseWriter,
            reasonCodes: [
                "generic_life_example_search",
                "connection_left_current_episode",
                "reality_anchor_not_used",
                "image_relation_not_compared_with_focal_episode",
            ],
            revisionGuidance: "只比较用户已经描述的画面关系与当前焦点事件，不搜索其他生活经历，也不增加心理含义。"
        )
    }

    func callCount() -> Int { calls }
}

private actor PlainDisclosureWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "你提到事情没有按计划发展。截止时间临近时，你当时做了什么？"
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
            reply: "截止时间临近时，你当时做了什么？"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor FailingSoftRevisionWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "你提到事情还在发展。后来发生了什么？"
        )
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        revisionCalls += 1
        throw ScriptedTurnError.exhausted
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
    private var plans: [Result<LLMTurnResponsePlan, Error>]
    private var writings: [Result<LLMTurnWriterResponse, Error>]
    private var planCalls = 0
    private var writeCalls = 0
    private var requests: [LLMTurnControllerRequest] = []

    init(
        plans: [Result<LLMTurnResponsePlan, Error>],
        writings: [Result<LLMTurnWriterResponse, Error>]
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

private actor PersistenceObservingTurnController: ReflectionTurnControlling {
    private let store: SessionStore
    private let sessionID: UUID
    private var observedPersistedInput = false

    init(store: SessionStore, sessionID: UUID) {
        self.store = store
        self.sessionID = sessionID
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        let persisted = try await store.load(id: sessionID)
        observedPersistedInput = persisted?.messages.last(where: {
            $0.role == .user
        })?.content == "我昨天没有按时提交项目方案。"
        return LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "event_process_clarified",
                focus: "事情如何发展到没有提交",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问当前事件如何发展"
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        .init(
            realizedIntent: validatedPlan.replyIntent,
            reply: "截止时间前，事情是怎样一步步发展到没有提交的？"
        )
    }

    func didObservePersistedInput() -> Bool {
        observedPersistedInput
    }
}

private actor ScriptedSimpleGentleReflectionGenerator:
    SimpleGentleReflectionGenerating
{
    private var replies: [SimpleGentleReflectionReply]
    private var requests: [[ChatMessage]] = []

    init(replies: [SimpleGentleReflectionReply]) {
        self.replies = replies
    }

    func generate(
        recentMessages: [ChatMessage]
    ) async throws -> SimpleGentleReflectionReply {
        requests.append(recentMessages)
        guard !replies.isEmpty else { throw ScriptedTurnError.exhausted }
        return replies.removeFirst()
    }

    func receivedMessages() -> [[ChatMessage]] {
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
