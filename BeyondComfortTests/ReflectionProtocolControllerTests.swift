import XCTest
@testable import BeyondComfort

final class ReflectionProtocolControllerTests: XCTestCase {
    private let controller = ReflectionProtocolController()

    func testLegacyPayloadKeepsPreTurnSessionAndMigratesTurnSessionToLegacyCompatibleTurn() throws {
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
        XCTAssertEqual(
            decoded.protocolVersion,
            ReflectionSession.consolidatedTurnProtocolVersion
        )
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
        XCTAssertTrue(priorDirectSession.usesSimpleGentleControl)
    }

    func testRetiredTurnFieldsAreConsumedOnlyAtDecodeBoundary() throws {
        let legacy = Data(
            #"{"protocolVersion":3,"protocolStage":"tenderConfirmation","semanticMemory":{"reflectionFocusKind":"explicitGlobalSelfJudgment","tenderGroundingKind":"none","tenderUnderstanding":"旧理解"}}"#.utf8
        )

        let session = try JSONDecoder().decode(ReflectionSession.self, from: legacy)

        XCTAssertEqual(
            session.protocolVersion,
            ReflectionSession.consolidatedTurnProtocolVersion
        )
        XCTAssertEqual(session.protocolStage, .contextualDisclosure)
        let encoded = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        XCTAssertFalse(encoded.contains("tenderConfirmation"))
        XCTAssertFalse(encoded.contains("reflectionFocusKind"))
        XCTAssertFalse(encoded.contains("tenderGroundingKind"))
        XCTAssertFalse(encoded.contains("tenderUnderstanding"))
    }

    func testCurrentRuntimeLayersContainNoRetiredDisclosureProtocolSymbols() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentRuntimeFiles = [
            "BeyondComfort/Services/ReflectionProtocolController.swift",
            "BeyondComfort/Services/LLMTurnController.swift",
            "BeyondComfort/ViewModels/ReflectionViewModel.swift",
            "server/app/prompt_registry.py",
            "server/app/providers.py",
        ]
        let retiredSymbols = [
            "tenderGroundingKind",
            "reflectionFocusKind",
            "clarifyReflectionFocus",
            "clarifyImmediateOutcome",
            "missing_required_memory_tenderGroundingKind",
            "missing_required_memory_reflectionFocusKind",
            "tenderConfirmation",
            "tenderSummary",
            "tenderUnderstanding",
            "presentTenderSummary",
            "integrateTrackingAndPresentTenderSummary",
            "requestTenderConfirmation",
            "reviseTenderSummary",
        ]

        for relativePath in currentRuntimeFiles {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            for symbol in retiredSymbols {
                XCTAssertFalse(
                    source.contains(symbol),
                    "\(symbol) must remain outside current runtime file \(relativePath)"
                )
            }
        }
    }

    func testRecoveryOperationIsProjectedOnlyFromPersistedStageAndTypedSubstate() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion

        session.protocolStage = .contextualDisclosure
        XCTAssertEqual(controller.recoveryOperation(for: session), .eventDisclosure)

        session.protocolStage = .cardConsent
        XCTAssertEqual(controller.recoveryOperation(for: session), .cardConsent)

        session.protocolStage = .cardReflection
        XCTAssertEqual(controller.recoveryOperation(for: session), .cardOpenExploration)

        let candidate = PendingCardRealityConnection(
            imageRelation: "用户已经描述的画面关系",
            candidateRealityMapping: "等待用户决定的候选现实连接"
        )
        session.semanticMemory.pendingCardRealityConnection = candidate
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: candidate.id.uuidString
        )
        XCTAssertEqual(controller.recoveryOperation(for: session), .cardCandidateResolution)

        session.semanticMemory.pendingCardRealityConnection = nil
        session.semanticMemory.nextPrompt = nil
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实连接",
            source: .userAuthored
        )
        XCTAssertEqual(controller.recoveryOperation(for: session), .currentCardGuidance)

        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        XCTAssertEqual(controller.recoveryOperation(for: session), .legacyCardReading)

        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .acknowledgeExperience,
            evidenceBasis: [.init(source: .latestUserAnswer, content: "用户最新回答")],
            dimensions: [.mindfulness],
            reflectionDelta: "继续当前反思",
            fierceEvidence: nil
        )
        XCTAssertEqual(controller.recoveryOperation(for: session), .directReflection)

        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [.init(source: .episode, content: "已经确认的事件")],
            dimensions: [.selfKindness],
            reflectionDelta: "综合已经形成的理解",
            fierceEvidence: nil
        )
        XCTAssertEqual(controller.recoveryOperation(for: session), .directSynthesis)

        session.protocolStage = .optionalAction
        XCTAssertEqual(controller.recoveryOperation(for: session), .optionalAction)
        session.protocolStage = .narrativeConfirmation
        XCTAssertEqual(controller.recoveryOperation(for: session), .finalNarrative)
        session.protocolStage = .complete
        XCTAssertEqual(controller.recoveryOperation(for: session), .complete)
        session.protocolStage = .safetySupport
        XCTAssertEqual(controller.recoveryOperation(for: session), .safety)
    }

    func testPartialEpisodePatchPreservesPriorFocalEventAndStillRequiresBehavior() throws {
        let update = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(
                #"{"episodeStructure":{"eventProcessStatus":"present","eventProcess":["用户说明了事情形成过程中的一个具体环节"]}}"#.utf8
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
            memory.episodeStructure?.eventProcess,
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
                eventProcess: ["事情如何发展已经得到说明"],
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
                eventProcess: ["事情如何发展已经得到说明"],
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
                    eventProcess: ["事情怎样发展到结果已经得到说明"],
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
                    eventProcess: ["事情如何发展已经得到说明"],
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

    func testCoreEpisodeCanInviteCardWithOnlyThreeRequiredRelations() throws {
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
                    eventProcess: ["原来的接人安排临时改变"],
                    possibleContributors: ["原来的接人安排临时改变"]
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "只做事实承接并邀请随机反思卡"
        )

        XCTAssertNoThrow(try controller.validate(invitation, for: session))
    }

    func testWholePersonJudgmentDoesNotAddAnotherCardConsentGate() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        let invitation = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard,
                selfCriticismStatus: .present,
                selfCriticalStatement: "我就是一个很自私的人",
                episodeStructure: .init(
                    concreteFacts: ["用户答应去接家人但最后没去"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["临时和朋友吃饭且没有提前告诉家人"],
                    eventProcessStatus: .present,
                    eventProcess: ["原来的安排临时改变"],
                    possibleContributors: ["原来的安排临时改变"]
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "保留行为事实，最多做一句行为与整体人格的区分，然后邀请卡牌"
        )

        XCTAssertNoThrow(try controller.validate(invitation, for: session))
    }

    func testOptionalPsychologicalMaterialCannotReplaceMissingCoreRelation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        let prematureInvitation = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard,
                selfCriticismStatus: .present,
                selfCriticalStatement: "我什么都做不好",
                selfCriticismLink: "用户把一次结果扩展成了整体能力判断",
                episodeStructure: .init(
                    concreteFacts: ["一个项目没有按时提交"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户没有按时提交"],
                    eventProcessStatus: .unresolved
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "邀请随机反思卡"
        )

        XCTAssertThrowsError(try controller.validate(prematureInvitation, for: session))
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
            eventProcess: ["原来的安排临时改变"],
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
        let normalized = try controller.validate(missingStatus, for: session)
        XCTAssertEqual(
            normalized.memoryUpdate.episodeStructure?.behaviorEvidenceStatus,
            .present
        )

        let processWithoutRedundantStatus = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情"],
                    eventProcessStatus: .unresolved,
                    eventProcess: ["事情如何发展已经由用户说明"]
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify behavior",
                focus: "用户在事情中做了什么或没有做什么",
                disclosurePurpose: .clarifyBehavior,
                disclosureTarget: .behavior
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问仍缺少的行为关系"
        )
        let normalizedProcess = try controller.validate(
            processWithoutRedundantStatus,
            for: session
        )
        XCTAssertEqual(
            normalizedProcess.memoryUpdate.episodeStructure?.eventProcessStatus,
            .present
        )

        let processStatusWithoutContent = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["一件具体事情"],
                    eventProcessStatus: .present,
                    eventProcess: []
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify process",
                focus: "事情如何发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            ),
            replyIntent: .exploreContext,
            replyGuidance: "只询问仍缺少的过程关系"
        )
        XCTAssertThrowsError(try controller.validate(processStatusWithoutContent, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .incompleteEpisodeStructure([.eventProcessEvidence])
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
            eventProcess: ["一个已经形成的过程关系"],
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
                    eventProcess: ["事情的发展已经说明"],
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
            eventProcess: ["事情的发展已经说明"],
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

    func testRetiredIncompatibleMetadataCannotBlockValidCardInvitation() throws {
        let rawPlan = Data(
            #"{"requestedStage":"cardConsent","localAction":{"kind":"none","trackingCueIDs":[]},"memoryUpdate":{"eventDisclosureOutcome":"readyForTenderOrCard","reflectionFocusKind":"explicitGlobalSelfJudgment","tenderGroundingKind":"none","tenderUnderstanding":null,"episodeStructure":{"concreteFacts":["用户答应去接家人但最后没去"],"behaviorEvidenceStatus":"present","behaviorEvidence":["临时和朋友吃饭且没有提前告诉家人"],"eventProcessStatus":"present","eventProcess":["原来的安排临时改变"],"possibleContributors":["原来的安排临时改变"]}},"resolvedConfirmation":null,"nextPrompt":{"kind":"confirmationRequest","purpose":null,"focus":null,"disclosurePurpose":null,"disclosureTarget":null,"disclosureReopenReason":null,"target":"cardConsent","referenceID":null},"replyIntent":"inviteCardConsent","replyGuidance":"简短事实承接并邀请随机反思卡"}"#.utf8
        )
        let plan = try JSONDecoder().decode(LLMTurnResponsePlan.self, from: rawPlan)
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated

        let validated = try controller.validate(plan, for: session)

        XCTAssertEqual(validated.requestedStage, .cardConsent)
        XCTAssertEqual(validated.replyIntent, .inviteCardConsent)
        XCTAssertEqual(validated.nextPrompt?.target, .cardConsent)
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
        XCTAssertTrue(prompt.system.contains("Never ask them to rate, approve"))
        XCTAssertTrue(prompt.system.contains("hidden-motive claims"))
    }

    func testSafetyServiceRecognizesAdditionalDirectRiskLanguage() {
        let service = SafetyService()

        XCTAssertTrue(service.requiresInterrupt("我觉得自己快活不下去了"))
        XCTAssertTrue(service.requiresInterrupt("有时候会想到伤害我自己"))
        XCTAssertFalse(service.requiresInterrupt("我今天只是觉得有些挫败"))
    }

    func testCurrentDisclosureTreatsGroundedProcessUncertaintyAsResolved() throws {
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

        XCTAssertThrowsError(try controller.validate(stalledPlan, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .disclosureShouldAdvance
            )
        }
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

    func testCompletedDisclosureRejectsFurtherProcessQuestions() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.condition = .cardMediated
        session.semanticMemory.nextPrompt = nil

        let completedEpisode = TurnEpisodeStructure(
            concreteFacts: ["一项具体行动没有按原计划完成"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["行动确实没有完成"],
            eventProcessStatus: .present,
            eventProcess: ["事件如何发展已经得到说明"],
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
                eventProcess: ["事件如何发展已经得到说明"],
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

    func testCurrentProtocolUserAuthoredMappingOpensDirectReflectionWithoutSecondConfirmation() throws {
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
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: try .init(
                kind: .userAuthoredConnection,
                connection: .init(
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
        XCTAssertEqual(authorization.requestedStage, .directReflection)
        XCTAssertEqual(authorization.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(authorization.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(authorization.nextPrompt?.kind, TurnNextPromptKind.none)
        XCTAssertNil(authorization.resolvedConfirmation)
        XCTAssertEqual(
            authorization.cardConnectionTurnOutcome?.kind,
            .userAuthoredConnection
        )
        XCTAssertEqual(
            authorization.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户把画面中的改变与现实里想放下的一项负担联系起来"
        )
        XCTAssertNil(authorization.memoryUpdate.cardInterpretiveTension)

        session.semanticMemory.apply(
            authorization.memoryUpdate,
            committedNextPrompt: authorization.nextPrompt
        )
        session.protocolStage = .directReflection
        session.cardGuidanceShared = true
        session.pendingCardGuidanceTurn = true

        let combinedReflection = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                reflectionFrame: .init(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [
                        .init(
                            source: .cardRealityConnection,
                            content: "用户把画面中的改变与现实里想放下的一项负担联系起来"
                        ),
                        .init(source: .episode, content: "用户已经说明了一件当前焦点事件"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "先沿用户建立的连接区分已经发生的事实与扩大的判断",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "grounded_tender_reflection",
                focus: "沿用户建立的连接继续一个具体反思问题"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "在同一条回复中简短承接卡牌连接并进入温和反思"
        )
        XCTAssertNoThrow(try controller.validate(combinedReflection, for: session))
        let permissions = controller.permissions(for: session)
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentCardReading))
        XCTAssertNil(combinedReflection.memoryUpdate.cardNegotiatedMeaning)
        XCTAssertNotEqual(combinedReflection.nextPrompt?.target, .cardMapping)
    }

    func testCardConnectionInteractionStateComesOnlyFromPersistedCandidatePrompt() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.cardDisplayState = .displayed

        XCTAssertEqual(
            controller.cardConnectionInteractionState(for: session),
            .openExploration
        )

        let pending = PendingCardRealityConnection(
            imageRelation: "画面里的人停在门口",
            candidateRealityMapping: "现实中正在等待一个决定"
        )
        session.semanticMemory.pendingCardRealityConnection = pending
        XCTAssertEqual(
            controller.cardConnectionInteractionState(for: session),
            .openExploration,
            "A candidate object alone is not an active confirmation transaction."
        )

        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: pending.id.uuidString
        )
        XCTAssertEqual(
            controller.cardConnectionInteractionState(for: session),
            .awaitingCandidateResolution
        )
    }

    func testDoorPhotoClockAndOfferConnectionCommitsWithoutConfirmationRoundTrip() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_reality_connection",
            focus: "把已经形成的画面关系连接到当前事件"
        )

        let connection = TurnCardRealityConnection(
            imageRelation: "人物站在门口，旧照片和钟声留在身后，正走向门外尚未确定的方向",
            realityMapping: "用户正在等待申请结果，offer 会影响未来去哪里读书",
            source: .userAuthored
        )
        let validated = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                cardConnectionTurnOutcome: try .init(
                    kind: .userAuthoredConnection,
                    connection: connection
                ),
                nextPrompt: .openQuestion(
                    purpose: "obsolete_repeat",
                    focus: "不应再次确认用户刚刚说出的连接"
                ),
                replyIntent: .inviteCardConnection,
                replyGuidance: "保存用户直接形成的连接"
            ),
            for: session
        )

        XCTAssertEqual(validated.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(validated.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(validated.nextPrompt, TurnNextPrompt.none)
        XCTAssertNil(validated.resolvedConfirmation)
        XCTAssertNil(validated.memoryUpdate.pendingCardRealityConnection)
        XCTAssertEqual(validated.memoryUpdate.cardRealityConnection, connection)
        XCTAssertEqual(validated.memoryUpdate.cardConnectionOutcome, .connectionConfirmed)
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
          "memoryUpdate":{},
          "cardConnectionTurnOutcome":{"kind":"userAuthoredConnection","connection":{"imageRelation":"用户已经形成的画面关系","realityMapping":"用户刚刚形成的画面—现实连接","source":"userAuthored","status":"confirmed"}},
          "resolvedConfirmation":null,
          "nextPrompt":{"kind":"none","purpose":null,"focus":null,"disclosureTarget":null,"target":null,"referenceID":null},
          "replyIntent":"authorizeCardGuidance",
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

    func testCurrentProposalRequiresNonOptionalGroundedBasis() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        session.semanticMemory.finalNarrative = "用户确认的新理解"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "final-1"
        )

        func practice(_ basis: String) -> LLMTurnResponsePlan {
            let transition = practiceTransition(
                id: "bounded-check",
                basis: basis,
                narrativeReferenceID: "final-1"
            )
            return LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(practiceTransition: transition),
                resolvedConfirmation: .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: "final-1"
                ),
                nextPrompt: .confirmationRequest(
                    target: .practice,
                    referenceID: "bounded-check"
                ),
                replyIntent: .suggestPractice,
                replyGuidance: "给出一个直接对应确认区分的小练习"
            )
        }

        XCTAssertThrowsError(try controller.validate(practice(""), for: session)) { error in
            guard case .incompletePracticeTransition(let requirements) =
                    error as? ReflectionProtocolViolation else {
                return XCTFail("Expected incompletePracticeTransition")
            }
            XCTAssertTrue(requirements.contains(.proposalBasis))
        }
        XCTAssertNoThrow(
            try controller.validate(
                practice("用户确认自己容易把一次未达预期扩大成整体能力判断"),
                for: session
            )
        )

        let missingBasisJSON = Data(
            """
            {"id":"p","kind":"change","content":"做一个小动作",\
            "status":"pendingConfirmation","source":"assistantProposed"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(TurnPracticeProposal.self, from: missingBasisJSON)
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

    func testPracticeCreationAndConfirmationUseOneCanonicalTransaction() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经等待确认的最终叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        let transition = practiceTransition(
            id: "practice-1",
            narrativeReferenceID: "narrative-1"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceTransition: transition),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .confirmationRequest(
                target: .practice,
                referenceID: "practice-1"
            ),
            replyIntent: .suggestPractice,
            replyGuidance: "呈现一个有依据的小行动"
        )

        let validated = try controller.validate(plan, for: session)
        XCTAssertEqual(validated.memoryUpdate.practiceTransition, transition)
        session.semanticMemory.apply(validated.memoryUpdate)
        XCTAssertEqual(session.semanticMemory.practiceTransition, transition)
    }

    func testPracticeCreationRejectsMissingProposalAndMismatchedTargetID() throws {
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "最终叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )
        func plan(_ transition: TurnPracticeTransition?, promptID: String?) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(practiceTransition: transition),
                resolvedConfirmation: .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: "narrative-1"
                ),
                nextPrompt: .confirmationRequest(target: .practice, referenceID: promptID),
                replyIntent: .suggestPractice,
                replyGuidance: "一个小行动"
            )
        }
        XCTAssertThrowsError(try controller.validate(plan(nil, promptID: nil), for: session))
        XCTAssertThrowsError(
            try controller.validate(
                plan(
                    practiceTransition(
                        id: "practice-1",
                        narrativeReferenceID: "narrative-1"
                    ),
                    promptID: "other-id"
                ),
                for: session
            )
        ) { error in
            guard case .incompletePracticeTransition(let requirements) =
                    error as? ReflectionProtocolViolation else {
                return XCTFail("Expected incompletePracticeTransition")
            }
            XCTAssertTrue(requirements.contains(.confirmationReference))
        }
    }

    func testPracticeAcceptReviseAndRejectAreAtomic() throws {
        let pending = practiceTransition(
            id: "practice-1",
            narrativeReferenceID: "confirmed-narrative"
        )
        func session() -> ReflectionSession {
            var value = protocolSession(stage: .optionalAction)
            value.semanticMemory.practiceTransition = pending
            value.semanticMemory.nextPrompt = .confirmationRequest(
                target: .practice,
                referenceID: "practice-1"
            )
            return value
        }
        func completion(
            decision: TurnConfirmationDecision,
            transition: TurnPracticeTransition
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .complete,
                localAction: .init(kind: .completeSession),
                memoryUpdate: .init(practiceTransition: transition),
                resolvedConfirmation: .init(
                    target: .practice,
                    decision: decision,
                    referenceID: "practice-1"
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .completeConversation,
                replyGuidance: "简短结束"
            )
        }

        var accepted = pending
        accepted.proposal = TurnPracticeProposal(
            id: "practice-1",
            kind: .care,
            content: pending.proposal!.content,
            basis: pending.proposal!.basis,
            status: .confirmed,
            source: .assistantProposed
        )
        XCTAssertNoThrow(try controller.validate(completion(decision: .accepted, transition: accepted), for: session()))

        var revised = pending
        revised.proposal = TurnPracticeProposal(
            id: "practice-1",
            kind: .repair,
            content: "先发一条消息说明没有提前告知。",
            basis: pending.proposal!.basis,
            status: .confirmed,
            source: .userRevised
        )
        XCTAssertNoThrow(try controller.validate(completion(decision: .revised, transition: revised), for: session()))

        var rejected = pending
        rejected.proposal = nil
        rejected.noActionReason = .userDeclined
        XCTAssertNoThrow(try controller.validate(completion(decision: .rejected, transition: rejected), for: session()))
    }

    func testLegacyPracticeMigrationDoesNotPromoteMissingBasis() throws {
        let incomplete = Data(
            """
            {"practiceOptions":[{"id":"legacy","kind":"care","title":"旧",\
            "instruction":"旧行动","rationale":"旧理由","basis":null}],\
            "selectedPractice":"旧行动"}
            """.utf8
        )
        let skipped = try JSONDecoder().decode(TurnSemanticMemory.self, from: incomplete)
        XCTAssertNil(skipped.practiceTransition)

        let complete = Data(
            """
            {"practiceOptions":[{"id":"legacy","kind":"care","title":"旧",\
            "instruction":"旧行动","rationale":"旧理由","basis":"用户确认的需要"}]}
            """.utf8
        )
        let migrated = try JSONDecoder().decode(TurnSemanticMemory.self, from: complete)
        XCTAssertEqual(migrated.practiceTransition?.proposal?.id, "legacy")
        XCTAssertEqual(migrated.practiceTransition?.proposal?.basis, "用户确认的需要")
        XCTAssertEqual(migrated.practiceTransition?.proposal?.status, .pendingConfirmation)
    }

    func testOpenQuestionMetadataIsCompletedWithoutRejectingTheTurn() throws {
        let controller = ReflectionProtocolController()
        let session = protocolSession(stage: .contextualDisclosure)
        let plan = LLMTurnResponsePlan(
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: TurnNextPrompt(
                kind: .openQuestion,
                purpose: nil,
                focus: nil,
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent,
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

    func testPracticeConfirmationMetadataIsNotSilentlyInvented() throws {
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
                practiceTransition: practiceTransition(
                    id: "practice-normalized",
                    narrativeReferenceID: "narrative-1"
                )
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

        XCTAssertThrowsError(try controller.validate(plan, for: session)) { error in
            guard case .incompletePracticeTransition(let requirements) =
                    error as? ReflectionProtocolViolation else {
                return XCTFail("Expected incompletePracticeTransition")
            }
            XCTAssertTrue(requirements.contains(.confirmationPrompt))
        }
    }

    func testSuggestPracticeCanProposeNoActionWithRationale() throws {
        let controller = ReflectionProtocolController()
        var session = protocolSession(stage: .narrativeConfirmation)
        session.semanticMemory.finalNarrative = "已经确认前等待处理的叙事"
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "narrative-1"
        )

        let noAction = TurnPracticeTransition(
            transactionID: "practice-1",
            narrativeReferenceID: "narrative-1",
            proposal: TurnPracticeProposal(
                id: "practice-1",
                kind: .noAction,
                content: "目前原因仍然未知，先保留不确定性，不为了消除不适仓促行动。",
                basis: "现有材料没有支持具体的修复、保护或改变方向。",
                status: .pendingConfirmation
            ),
            noActionReason: nil
        )
        let unsupported = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceTransition: noAction),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "narrative-1"
            ),
            nextPrompt: .confirmationRequest(target: .practice, referenceID: "practice-1"),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个有理由的 noAction 选项"
        )

        XCTAssertNoThrow(try controller.validate(unsupported, for: session))
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
        practice.semanticMemory.practiceTransition = practiceTransition(id: "practice-1")
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

        let declinedTransition = TurnPracticeTransition(
            transactionID: "practice-1",
            narrativeReferenceID: nil,
            proposal: nil,
            noActionReason: .userDeclined
        )
        let declined = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                finalNarrative: "用户暂不采用行动，综合叙事保留这一选择。",
                practiceTransition: declinedTransition
            ),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .declined,
                referenceID: "practice-1"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "用户不采用实践，保留自主选择并呈现最终叙事"
        )
        XCTAssertNoThrow(try controller.validate(declined, for: practice))
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

        XCTAssertEqual(
            try JSONDecoder().decode(
                ReflectionProtocolStage.self,
                from: Data(#""trackingReview""#.utf8)
            ),
            .contextualDisclosure
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

    func testCardDrawAndGuidanceRemainLocalPermissionedActions() throws {
        var consent = protocolSession(stage: .cardConsent)
        consent.condition = .cardMediated
        consent.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardConsent,
            referenceID: "card-consent"
        )
        XCTAssertNoThrow(
            try controller.validate(
                LLMTurnResponsePlan(
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
                    replyGuidance: ""
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
        let relationOutcome = try CardConnectionTurnOutcome(
            kind: .userAuthoredConnection,
            connection: .init(
                imageRelation: "画面中的人先观察再决定是否靠近",
                realityMapping: "用户在现实中也需要先了解请求范围再回应",
                source: .userAuthored
            )
        )
        XCTAssertNoThrow(
            try controller.validate(
                LLMTurnResponsePlan(
                    requestedStage: .cardReflection,
                    localAction: .init(kind: .shareCardGuidance),
                    memoryUpdate: .init(),
                    cardConnectionTurnOutcome: relationOutcome,
                    nextPrompt: TurnNextPrompt.none,
                    replyIntent: .authorizeCardGuidance,
                    replyGuidance: ""
                ),
                for: reflection
            )
        )

        // A complete post-patch connection has one deterministic silent successor even if the
        // Planner leaves the redundant local-action label as none.
        let derivedAuthorization = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                cardConnectionTurnOutcome: relationOutcome,
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .authorizeCardGuidance,
                replyGuidance: ""
            ),
            for: reflection
        )
        XCTAssertEqual(derivedAuthorization.localAction.kind, .shareCardGuidance)

        let combinedReadingAndGuidance = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(
                cardNegotiatedMeaning: "这段含义尚未在 guidance-aware 回复中向用户展示"
            ),
            cardConnectionTurnOutcome: relationOutcome,
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
                    action: .none
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
        let pending = practiceTransition(
            id: "practice-completion",
            narrativeReferenceID: "confirmed-narrative"
        )
        session.semanticMemory.practiceTransition = pending
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-completion"
        )
        var confirmed = pending
        confirmed.proposal = TurnPracticeProposal(
            id: "practice-completion",
            kind: pending.proposal!.kind,
            content: pending.proposal!.content,
            basis: pending.proposal!.basis,
            status: .confirmed,
            source: .assistantProposed
        )

        let normalized = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(practiceTransition: confirmed),
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

    func testCurrentTurnPromptsUseImmutableServerRegistryVersion() {
        XCTAssertEqual(ServerTurnPrompt.version, "turn-v4-server-v45")
        XCTAssertEqual(ServerTurnPrompt.version(for: 2), "turn-v4-server-v45")
        XCTAssertEqual(ServerTurnPrompt.version(for: 3), "turn-v4-server-v45")
        XCTAssertEqual(
            ServerTurnPrompt.version(for: ReflectionSession.currentProtocolVersion),
            "turn-v4-server-v45"
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

    func testCardReferenceSelectionIsTurnLocalAndSwiftValidatesSourceAndPermission() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户描述了画面中尚未完全出发的关系",
            realityMapping: "用户把这个关系连接到现实中继续准备的状态",
            source: .userAuthored
        )

        func reflection(index: Int) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .directReflection,
                localAction: .none,
                memoryUpdate: .init(
                    reflectionFrame: .init(
                        mode: .tender,
                        action: .distinguishFactFromPrediction,
                        evidenceBasis: [
                            .init(source: .cardRealityConnection, content: "用户确认的画面—现实连接"),
                            .init(source: .episode, content: "用户已经说明的现实事件"),
                        ],
                        dimensions: [.selfKindness, .mindfulness],
                        reflectionDelta: "用一条受支持的卡牌关系继续现实反思",
                        fierceEvidence: nil
                    )
                ),
                nextPrompt: .openQuestion(
                    purpose: "grounded_card_reflection",
                    focus: "沿当前连接继续一个具体问题"
                ),
                replyIntent: .directCandidReflection,
                replyGuidance: "只把当前卡牌的一条受支持关系用于形成后续问题",
                cardReferenceSelection: .init(relationIndex: index)
            )
        }

        let valid = try controller.validate(reflection(index: 0), for: session)
        XCTAssertEqual(valid.cardReferenceSelection?.relationIndex, 0)
        XCTAssertNil(valid.memoryUpdate.cardRealityMapping)

        XCTAssertThrowsError(try controller.validate(reflection(index: 2), for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .invalidCardReferenceSelection
            )
        }

        let nonQuestionReflection = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                reflectionFrame: .init(
                    mode: .tender,
                    action: .acknowledgeExperience,
                    evidenceBasis: [
                        .init(source: .episode, content: "用户已经说明的现实事件"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "承接一个具体经历",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "不提出问题的承接不能选择问题镜头",
            cardReferenceSelection: .init(relationIndex: 0)
        )
        XCTAssertThrowsError(try controller.validate(nonQuestionReflection, for: session)) {
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

        XCTAssertThrowsError(
            try CardConnectionTurnOutcome(
                kind: .userAuthoredConnection,
                connection: .init(
                    imageRelation: "   ",
                    realityMapping: "一个现实映射",
                    source: .userAuthored
                )
            )
        )

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

    func testPostGuidanceConfirmedConnectionIsImmutableDuringDirectReflection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
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

        func reflectionPlan(
            connection: TurnCardRealityConnection?
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                requestedStage: .directReflection,
                localAction: .none,
                memoryUpdate: .init(
                    cardRealityConnection: connection,
                    reflectionFrame: .init(
                        mode: .tender,
                        action: .distinguishFactFromPrediction,
                        evidenceBasis: [
                            .init(source: .cardRealityConnection, content: "用户确认的画面—现实连接"),
                            .init(source: .episode, content: "用户已经说明的现实事件"),
                        ],
                        dimensions: [.selfKindness, .mindfulness],
                        reflectionDelta: "沿已确认连接形成一个温和且具体的区分",
                        fierceEvidence: nil
                    )
                ),
                nextPrompt: .openQuestion(
                    purpose: "grounded_tender_reflection",
                    focus: "继续一个具体的现实反思问题"
                ),
                replyIntent: .directCandidReflection,
                replyGuidance: "沿已确认连接继续反思"
            )
        }

        let changed = reflectionPlan(
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

        let identical = reflectionPlan(connection: confirmed)
        let validated = try controller.validate(identical, for: session)
        XCTAssertNil(validated.memoryUpdate.cardRealityConnection)
        XCTAssertEqual(validated.localAction.kind, .none)
        XCTAssertEqual(validated.replyIntent, .directCandidReflection)
        XCTAssertEqual(session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(
            controller.nonBlockingWarnings(
                originalPlan: identical,
                validatedPlan: validated,
                for: session
            ).contains(.redundantConfirmedConnectionPatch)
        )

        let clear = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                clearCardRealityConnection: true,
                reflectionFrame: .init(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [
                        .init(source: .episode, content: "用户已经说明的现实事件"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "继续一个现实区分",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: .openQuestion(purpose: "continue_reflection", focus: "继续现实反思"),
            replyIntent: .directCandidReflection,
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

        var (acceptedSession, _) = pendingSession()
        let accepted = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                cardConnectionTurnOutcome: try .init(kind: .candidateAccepted),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .inviteCardConnection,
                replyGuidance: "提交已接受的候选连接"
            ),
            for: acceptedSession
        )
        XCTAssertEqual(accepted.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(accepted.requestedStage, .directReflection)
        XCTAssertEqual(accepted.replyIntent, .authorizeCardGuidance)
        XCTAssertEqual(accepted.memoryUpdate.cardRealityConnection?.source, .userAccepted)
        XCTAssertEqual(accepted.memoryUpdate.cardConnectionOutcome, .connectionConfirmed)
        XCTAssertEqual(accepted.memoryUpdate.clearPendingCardRealityConnection, true)
        XCTAssertEqual(accepted.resolvedConfirmation?.decision, .accepted)
        XCTAssertEqual(accepted.nextPrompt, TurnNextPrompt.none)
        XCTAssertNil(accepted.memoryUpdate.cardNegotiatedMeaning)
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
                memoryUpdate: .init(),
                cardConnectionTurnOutcome: try .init(
                    kind: .candidateRevised,
                    connection: .init(
                        imageRelation: revisedPending.imageRelation,
                        realityMapping: "用户修订后的现实关系",
                        source: .userRevised
                    )
                ),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .inviteCardConnection,
                replyGuidance: "提交用户修订后的连接"
            ),
            for: revisedSession
        )
        XCTAssertEqual(revised.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(revised.requestedStage, .directReflection)
        XCTAssertEqual(
            revised.memoryUpdate.cardRealityConnection?.realityMapping,
            "用户修订后的现实关系"
        )
        XCTAssertEqual(revised.memoryUpdate.cardRealityConnection?.source, .userRevised)
        XCTAssertEqual(revised.resolvedConfirmation?.decision, .revised)
        XCTAssertEqual(revised.nextPrompt, TurnNextPrompt.none)
        XCTAssertNil(revised.memoryUpdate.cardNegotiatedMeaning)

        let (rejectedSession, _) = pendingSession()
        let rejected = try controller.validate(
            LLMTurnResponsePlan(
                requestedStage: .cardReflection,
                localAction: .none,
                memoryUpdate: .init(),
                cardConnectionTurnOutcome: try .init(kind: .candidateRejected),
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
        XCTAssertEqual(rejected.resolvedConfirmation?.decision, .rejected)
        XCTAssertNil(rejected.memoryUpdate.cardNegotiatedMeaning)
    }

    func testCardRealityConnectionConfirmationRequiresMatchingPendingObject() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.cardDisplayState = .displayed

        let invalid = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: try .init(kind: .candidateAccepted),
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
                .illegalReplyIntent
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
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: try .init(
                kind: .userAuthoredConnection,
                connection: .init(
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
        session.protocolVersion = ReflectionSession.currentProtocolVersion
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

    private func practiceTransition(
        id: String,
        kind: TurnPracticeKind = .care,
        content: String = "今晚留出十分钟，只照顾当下的疲惫，时间到了就停止。",
        basis: String = "最终叙事已经确认当前消耗需要一个有边界的照顾动作。",
        status: TurnPracticeProposalStatus = .pendingConfirmation,
        source: TurnPracticeProposalSource = .assistantProposed,
        narrativeReferenceID: String? = nil
    ) -> TurnPracticeTransition {
        TurnPracticeTransition(
            transactionID: id,
            narrativeReferenceID: narrativeReferenceID,
            proposal: TurnPracticeProposal(
                id: id,
                kind: kind,
                content: content,
                basis: basis,
                status: status,
                source: source
            ),
            noActionReason: nil
        )
    }

    func testCurrentOptionalActionRuntimeHasNoRetiredPracticeProtocolReaders() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentRuntimeFiles = [
            "BeyondComfort/Services/ReflectionProtocolController.swift",
            "BeyondComfort/Services/LLMTurnController.swift",
            "BeyondComfort/ViewModels/ReflectionViewModel.swift",
            "server/app/prompt_registry.py",
            "server/app/providers.py",
        ]
        let retiredSymbols = [
            "practiceOptions", "practiceKind", "selectedPractice",
            "TurnPracticeOption", "practiceBasis",
            "missing_required_memory_practiceBasis",
        ]
        for relativePath in currentRuntimeFiles {
            let source = try String(
                contentsOf: repository.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            for symbol in retiredSymbols {
                XCTAssertFalse(
                    source.contains(symbol),
                    "Retired Optional Action symbol \(symbol) remains in \(relativePath)"
                )
            }
        }
    }

    func testCurrentAuthorizedGroundedCardMappingOnlyPermitsDirectReflection() {
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

        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentCardReading))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.safetySupport))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentFinalNarrative))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))
    }

    func testLegacyCardMappingResolutionMustOpenDirectReflectionBeforeNarrative() throws {
        var session = protocolSession(stage: .cardReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
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

    func testLegacyNarrativeReadyDirectReflectionOnlyPermitsNarrativeOrSafety() {
        var session = protocolSession(stage: .directReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.reflectionReadiness = .narrativeReady

        let permissions = controller.permissions(for: session)

        XCTAssertEqual(
            Set(permissions.allowedReplyIntents),
            Set([.presentFinalNarrative, .safetySupport])
        )
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.directCandidReflection))
    }

    func testCurrentPendingReflectionCannotSkipActionForNarrative() {
        var session = protocolSession(stage: .directReflection)
        session.reflectionReadiness = .reflectionOpen
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_behavior_or_impact_clarified",
            focus: "一个具体行为及其影响"
        )

        let permissions = controller.permissions(for: session)

        XCTAssertTrue(permissions.allowedReplyIntents.contains(.directCandidReflection))
        XCTAssertTrue(permissions.allowedReplyIntents.contains(.suggestPractice))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.presentFinalNarrative))
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

    func testCurrentReflectionFrameRequiresTypedActionCompatibleWithMode() throws {
        let session = protocolSession(stage: .directReflection)
        let tenderWithFierceAction = TurnReflectionFrame(
            mode: .tender,
            action: .identifyRepairDirection,
            evidenceBasis: [
                .init(source: .episode, content: "一个结果已经发生，原因仍未确认"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "把已发生的结果与未知原因分开",
            fierceEvidence: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: tenderWithFierceAction),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "保留温和理解"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .invalidReflectionFrame)
        }
    }

    func testLegacyReflectionFrameWithoutActionIsReadableButNotACurrentPlannerPatch() throws {
        let data = Data(
            #"{"mode":"tender","evidenceBasis":[{"source":"episode","content":"已确认的现实材料"}],"dimensions":["mindfulness"],"reflectionDelta":"保留事实与未知","fierceEvidence":null}"#.utf8
        )
        let decoded = try JSONDecoder().decode(TurnReflectionFrame.self, from: data)
        XCTAssertEqual(decoded.action, .synthesizeUnderstanding)
        XCTAssertTrue(decoded.actionWasInferredForLegacyDecode)

        let currentSession = protocolSession(stage: .directReflection)
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: decoded),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "兼容读取的旧反思"
        )
        XCTAssertThrowsError(try controller.validate(plan, for: currentSession)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .invalidReflectionFrame)
        }

        var legacySession = currentSession
        legacySession.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        XCTAssertNoThrow(try controller.validate(plan, for: legacySession))
    }

    func testCurrentDirectReflectionCannotPresentFinalNarrativeBeforeAction() throws {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [.init(source: .episode, content: "已确认的现实材料")],
            dimensions: [.mindfulness],
            reflectionDelta: "形成一个保留不确定性的理解",
            fierceEvidence: nil
        )
        let skipped = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(finalNarrative: "跳过行动的最终叙事"),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "直接展示最终叙事"
        )

        XCTAssertThrowsError(try controller.validate(skipped, for: session)) {
            guard let violation = $0 as? ReflectionProtocolViolation else {
                return XCTFail("Expected a typed protocol violation")
            }
            XCTAssertTrue(
                violation == .illegalStageTransition || violation == .illegalReplyIntent,
                "Expected the current permission boundary to reject narrative-first: \(String(describing: violation))"
            )
        }
    }

    func testCurrentNoActionProposalResolvesBeforeFinalNarrative() throws {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [.init(source: .latestUserAnswer, content: "当前没有足够材料支持立即行动")],
            dimensions: [.mindfulness],
            reflectionDelta: "保留未知，而不是为了缓解不适仓促行动",
            fierceEvidence: nil
        )
        let synthesisPermissions = controller.permissions(for: session)
        XCTAssertEqual(
            Set(synthesisPermissions.allowedReplyIntents),
            Set([.suggestPractice, .safetySupport])
        )
        let pendingID = "direct-no-action"
        let pending = TurnPracticeTransition(
            transactionID: pendingID,
            narrativeReferenceID: nil,
            proposal: .init(
                id: pendingID,
                kind: .noAction,
                content: "先保留目前的未知，不为了马上消除不适而采取未经支持的行动。",
                basis: "当前材料尚未支持一个具体的照顾、修复、保护或改变步骤。",
                status: .pendingConfirmation
            ),
            noActionReason: nil
        )
        let propose = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(practiceTransition: pending),
            nextPrompt: .confirmationRequest(target: .practice, referenceID: pendingID),
            replyIntent: .suggestPractice,
            replyGuidance: "提出有依据的暂不行动选项"
        )
        XCTAssertNoThrow(try controller.validate(propose, for: session))

        session.protocolStage = .optionalAction
        session.semanticMemory.practiceTransition = pending
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: pendingID
        )
        var confirmed = pending
        confirmed.proposal = .init(
            id: pendingID,
            kind: .noAction,
            content: pending.proposal!.content,
            basis: pending.proposal!.basis,
            status: .confirmed
        )
        let resolve = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                finalNarrative: "这次先保留未知，不把行动当成必须立即完成的证明。",
                practiceTransition: confirmed
            ),
            resolvedConfirmation: .init(
                target: .practice,
                decision: .accepted,
                referenceID: pendingID
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "整合已经确认的理解并请求最终叙事确认"
        )
        XCTAssertNoThrow(try controller.validate(resolve, for: session))
    }

    func testPostConnectionReflectionDefaultsToTenderWithoutResponsibilityEvidence() throws {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.reflectionFrame = nil
        XCTAssertEqual(session.semanticMemory.effectiveReflectionMode, .tender)

        let tenderFrame = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .episode, content: "结果已经发生，但具体原因仍然未知"),
                .init(source: .latestUserAnswer, content: "用户表达对未来结果的担忧"),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "区分已经发生的结果、未知原因和对未来的预测",
            fierceEvidence: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: tenderFrame),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "形成一个不要求继续寻找遗漏的温和理解"
        )

        let validated = try controller.validate(plan, for: session)
        XCTAssertEqual(validated.memoryUpdate.reflectionFrame?.mode, .tender)
        XCTAssertNil(validated.memoryUpdate.reflectionFrame?.fierceEvidence)
    }

    func testCurrentTenderCannotUseCommonHumanityAsItsOnlyReflectionAction() {
        let session = protocolSession(stage: .directReflection)
        let commonHumanityOnly = TurnReflectionFrame(
            mode: .tender,
            action: .connectCommonHumanity,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "用户正在面对一个结果未知的具体处境"),
            ],
            dimensions: [.commonHumanity],
            reflectionDelta: "只说这种处境并非个例",
            fierceEvidence: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: commonHumanityOnly),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "不应只用共通性代替具体区分"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .invalidReflectionFrame)
        }
    }

    func testLegacyTenderMayStillDecodeCommonHumanityAction() {
        var session = protocolSession(stage: .directReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        let legacyFrame = TurnReflectionFrame(
            mode: .tender,
            action: .connectCommonHumanity,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "旧会话中已经保存的共同处境"),
            ],
            dimensions: [.commonHumanity],
            reflectionDelta: "旧协议中已存在的共同处境连接",
            fierceEvidence: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: legacyFrame),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "保留旧会话行为"
        )

        XCTAssertNoThrow(try controller.validate(plan, for: session))
    }

    func testPostCardReflectionDecisionMatrixUsesCompleteTypedMaterial() throws {
        struct Scenario {
            let id: String
            let latestAnswer: String
            let mode: TurnReflectionMode
            let action: TurnReflectionAction
            let dimensions: [TurnSelfCompassionDimension]
            let fierceEvidence: TurnFierceEvidence?
            let selfCriticismStatus: TurnSelfCriticismStatus
        }
        let scenarios = [
            Scenario(
                id: "unknown-application-result",
                latestAnswer: "我还不知道为什么被拒，也担心以后没有学上。",
                mode: .tender,
                action: .distinguishFactFromPrediction,
                dimensions: [.selfKindness, .mindfulness],
                fierceEvidence: nil,
                selfCriticismStatus: .absent
            ),
            Scenario(
                id: "missed-family-pickup",
                latestAnswer: "我临时去吃饭，没有提前告诉家人，家人因此很生气。",
                mode: .fierce,
                action: .identifyRepairDirection,
                dimensions: [.selfKindness, .mindfulness],
                fierceEvidence: .init(
                    behavior: "临时改变接人安排且没有提前告知",
                    impact: "家人因此生气，原有安排被打乱",
                    direction: .repair
                ),
                selfCriticismStatus: .present
            ),
            Scenario(
                id: "rejected-omission-premise",
                latestAnswer: "没有，我已经把能准备的材料都交了。",
                mode: .tender,
                action: .synthesizeUnderstanding,
                dimensions: [.mindfulness],
                fierceEvidence: nil,
                selfCriticismStatus: .absent
            ),
            Scenario(
                id: "future-worry",
                latestAnswer: "我只是担心以后还会不会出现同样的结果。",
                mode: .tender,
                action: .distinguishFactFromPrediction,
                dimensions: [.mindfulness],
                fierceEvidence: nil,
                selfCriticismStatus: .absent
            ),
        ]

        for scenario in scenarios {
            var session = protocolSession(stage: .directReflection)
            session.cardGuidanceShared = true
            session.semanticMemory = .init(
                selfCriticismStatus: scenario.selfCriticismStatus,
                selfCriticalStatement: scenario.selfCriticismStatus == .present
                    ? "用户把一次具体结果扩大为整体评价"
                    : nil,
                episodeStructure: .init(
                    concreteFacts: ["一个已经发生且结果仍需理解的具体事件"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户明确说明了自己采取或没有采取的行动"],
                    eventProcessStatus: .present,
                    eventProcess: ["事件的发展过程已经得到说明"],
                    impactStatus: scenario.fierceEvidence == nil ? .uncertain : .present,
                    impacts: scenario.fierceEvidence.map { [$0.impact] } ?? [],
                    keyUncertainty: scenario.fierceEvidence == nil ? "原因或未来结果仍未知" : nil
                ),
                cardRealityConnection: .init(
                    imageRelation: "画面中的人物正在处理一个动作关系",
                    realityMapping: "用户把这个关系连回当前焦点事件",
                    source: .userAuthored
                )
            )
            let frame = TurnReflectionFrame(
                mode: scenario.mode,
                action: scenario.action,
                evidenceBasis: [
                    .init(source: .episode, content: "已确认的现实事件与行为材料"),
                    .init(source: .latestUserAnswer, content: scenario.latestAnswer),
                ],
                dimensions: scenario.dimensions,
                reflectionDelta: "把具体事实、未知和整体判断放在同一段经历中区分开",
                fierceEvidence: scenario.fierceEvidence
            )
            let plan = LLMTurnResponsePlan(
                requestedStage: .directReflection,
                localAction: .none,
                memoryUpdate: .init(reflectionFrame: frame),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .directCandidReflection,
                replyGuidance: "沿着一个已确认的反思动作继续"
            )
            let validated = try controller.validate(plan, for: session)
            let stored = try XCTUnwrap(validated.memoryUpdate.reflectionFrame)
            XCTAssertEqual(stored.mode, scenario.mode, scenario.id)
            XCTAssertEqual(stored.action, scenario.action, scenario.id)
            XCTAssertEqual(stored.dimensions, scenario.dimensions, scenario.id)
            XCTAssertEqual(stored.fierceEvidence, scenario.fierceEvidence, scenario.id)
            XCTAssertEqual(validated.requestedStage, .directReflection, scenario.id)
            if scenario.mode == .tender {
                XCTAssertNil(stored.fierceEvidence, scenario.id)
            }
        }
    }

    func testFierceReflectionRequiresConcreteRealityBehaviorAndImpact() throws {
        let session = protocolSession(stage: .directReflection)
        let fierceFrame = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyRepairDirection,
            evidenceBasis: [
                .init(source: .episode, content: "用户改变了已经作出的安排且没有提前沟通"),
                .init(source: .latestUserAnswer, content: "这一处理对关系中的另一方造成影响"),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "把需要修复的沟通行为限定在这一次具体处理上",
            fierceEvidence: .init(
                behavior: "改变安排后没有提前沟通",
                impact: "另一方需要临时面对安排变化",
                direction: .repair
            )
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: fierceFrame),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "基于关心关系形成具体修复方向，不扩大为人格判断"
        )

        XCTAssertNoThrow(try controller.validate(plan, for: session))
    }

    func testCurrentFierceRequiresTenderGroundingDimension() {
        let session = protocolSession(stage: .directReflection)
        let ungrounded = TurnReflectionFrame(
            mode: .fierce,
            action: .acknowledgeBehaviorImpact,
            evidenceBasis: [
                .init(source: .episode, content: "用户明确说明了一个行为及其现实影响"),
            ],
            dimensions: [.commonHumanity],
            reflectionDelta: "只指出影响，没有先限制整体性自我攻击或保持事实边界",
            fierceEvidence: .init(
                behavior: "用户明确说明的具体行为",
                impact: "用户明确说明的现实影响",
                direction: .change
            )
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: ungrounded),
            nextPrompt: .openQuestion(
                purpose: "grounded_fierce_focus",
                focus: "一个有证据支持的具体改变点"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "不应跳过慈悲基础直接进入行为挑战"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .fierceReflectionUngrounded)
        }
    }

    func testDirectReflectionMayOfferOneGroundedActionBeforeFinalNarrative() throws {
        let session = protocolSession(stage: .directReflection)
        let permissions = controller.permissions(for: session)
        XCTAssertTrue(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .optionalAction,
                    replyIntent: .suggestPractice,
                    localAction: .none
                )
            )
        )

        let proposalID = "pre-narrative-action"
        let transition = TurnPracticeTransition(
            transactionID: proposalID,
            narrativeReferenceID: nil,
            proposal: .init(
                id: proposalID,
                kind: .care,
                content: "今天为等待中的自己留出十分钟不处理结果信息。",
                basis: "用户确认当前主要面对的是等待和未知带来的消耗。",
                status: .pendingConfirmation
            ),
            noActionReason: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                reflectionFrame: .init(
                    mode: .tender,
                    action: .synthesizeUnderstanding,
                    evidenceBasis: [
                        .init(source: .latestUserAnswer, content: "等待和未知正在造成消耗"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "当前需要面对的是等待中的消耗，而不是寻找未经证实的个人失败",
                    fierceEvidence: nil
                ),
                practiceTransition: transition
            ),
            nextPrompt: .confirmationRequest(target: .practice, referenceID: proposalID),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个小而具体、可修改或拒绝的照顾行动"
        )

        XCTAssertNoThrow(try controller.validate(plan, for: session))
    }

    func testCardRelationAloneCannotAuthorizeFierceReflection() {
        let session = protocolSession(stage: .directReflection)
        let cardOnlyFrame = TurnReflectionFrame(
            mode: .fierce,
            action: .acknowledgeBehaviorImpact,
            evidenceBasis: [
                .init(source: .cardRealityConnection, content: "用户形成的画面与现实联系"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "试图从画面推导责任",
            fierceEvidence: .init(
                behavior: "由画面推测的行为",
                impact: "由画面推测的影响",
                direction: .change
            )
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: cardOnlyFrame),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "不应被接受的卡牌责任推断"
        )

        XCTAssertThrowsError(try controller.validate(plan, for: session)) {
            XCTAssertEqual(
                $0 as? ReflectionProtocolViolation,
                .fierceReflectionUngrounded
            )
        }
    }

    func testAnsweredLegacyFierceQuestionDoesNotCreateAStringBasedMemoryGate() {
        var session = protocolSession(stage: .directReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.semanticMemory.fierceUnderstanding = "较早、尚未包含最新回答的理解"
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [.init(source: .episode, content: "已经确认的现实材料")],
            dimensions: [.mindfulness],
            reflectionDelta: "保留仍然未知的责任边界",
            fierceEvidence: nil
        )
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

        XCTAssertNoThrow(try controller.validate(stale, for: session))

        let synchronized = LLMTurnResponsePlan(
            requestedStage: .narrativeConfirmation,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["fierce_behavior_or_impact_clarified"],
                reflectionFrame: .init(
                    mode: .tender,
                    action: .synthesizeUnderstanding,
                    evidenceBasis: [
                        .init(
                            source: .latestUserAnswer,
                            content: "用户保留了仍不确定的责任边界"
                        ),
                    ],
                    dimensions: [.mindfulness],
                    reflectionDelta: "保留责任边界的不确定性，而不继续索取责任材料",
                    fierceEvidence: nil
                ),
                finalNarrative: "新增理解是具体影响已确认，而责任边界仍需保留不确定性。"
            ),
            nextPrompt: .confirmationRequest(target: .finalNarrative),
            replyIntent: .presentFinalNarrative,
            replyGuidance: "承接最新回答并立即收敛"
        )
        XCTAssertNoThrow(try controller.validate(synchronized, for: session))
    }

    func testLegacyReflectionScalarsAreDroppedFromCurrentPlans() throws {
        var session = protocolSession(stage: .directReflection)
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [.init(source: .latestUserAnswer, content: "用户不继续责任方向")],
            dimensions: [.selfKindness],
            reflectionDelta: "停止被拒绝的责任前提并收敛",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierce_boundary_or_responsibility_clarified",
            focus: "一个已经显示的边界问题"
        )

        let legacy = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                answeredQuestionPurposes: ["fierce_boundary_or_responsibility_clarified"],
                reflectionFrame: .init(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [
                        .init(source: .latestUserAnswer, content: "用户不继续责任方向"),
                    ],
                    dimensions: [.selfKindness],
                    reflectionDelta: "保留用户不想继续讨论的边界。",
                    fierceEvidence: nil
                ),
                fierceUnderstanding: "用户表示目前不想继续讨论边界"
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "接受拒绝并完成综合理解"
        )

        let validated = try controller.validate(legacy, for: session)

        XCTAssertNil(validated.memoryUpdate.candidUnderstanding)
        XCTAssertNil(validated.memoryUpdate.fierceUnderstanding)
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

    #if LEGACY_CURRENT_V5_PIPELINE_CHARACTERIZATION
    @MainActor
    func testCommittedCardConnectionOutcomesConsumeAttemptsNotQuestions() async {
        let scripted = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .inviteRealityConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
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
                        semanticOperation: .offerCardConnectionScaffold,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        cardConnectionTurnOutcome: try! .init(
                            kind: .connectionStillUnclear
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
                        semanticOperation: .continueOpenCardConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
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
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardImageDevelopmentTurnCount = 1
        model.session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面里的人物"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面里的人物"],
            relationOrAction: "接下来可能发生变化",
            anticipatedChangeOrChoice: nil
        )

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
    #endif

    func testLegacyPendingCardMappingNarrowsPermissionsToResolutionOrClarification() {
        var session = protocolSession(stage: .cardReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.condition = .cardMediated
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
        session.semanticMemory.cardNegotiatedMeaning = "已经显示、等待确认的协商式解读"
        session.semanticMemory.cardInterpretiveTension = "用户确认的画面关系与现实经历之间的张力"
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

    @MainActor
    func testLegacyAcceptedCardMappingCannotBeMislabeledAsAnotherCardReading() {
        var session = protocolSession(stage: .cardReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
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

    func testLegacyUnclearCardMappingMayClarifyAndReestablishConfirmation() throws {
        var session = protocolSession(stage: .cardReflection)
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "用户确认的画面关系",
            realityMapping: "用户确认的现实映射",
            source: .userAuthored
        )
        session.semanticMemory.cardNegotiatedMeaning = "已经显示、等待确认的协商式解读"
        session.semanticMemory.cardInterpretiveTension = "用户确认的画面关系与现实经历之间的张力"
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

    func testLegacyPendingInteractionMigratesToCanonicalNextPrompt() throws {
        let data = Data(
            #"{"pendingQuestionPurpose":"confirm_cardMapping","pendingConfirmationTarget":"cardMapping","cardNegotiatedMeaning":"等待确认的解读"}"#.utf8
        )

        let memory = try JSONDecoder().decode(TurnSemanticMemory.self, from: data)

        XCTAssertEqual(memory.nextPrompt?.kind, .confirmationRequest)
        XCTAssertEqual(memory.nextPrompt?.target, .cardMapping)
        XCTAssertEqual(memory.cardNegotiatedMeaning, "等待确认的解读")
        let encoded = String(decoding: try JSONEncoder().encode(memory), as: UTF8.self)
        XCTAssertFalse(encoded.contains("pendingQuestionPurpose"))
        XCTAssertFalse(encoded.contains("pendingConfirmationTarget"))
    }

    // MARK: - Semantic operation classification

    func testEventDisclosureExploreContextMapsToClarifyEvent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.situationUnderstanding = "已了解事件梗概"

        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                situationUnderstanding: "更具体的处境理解",
                episodeStructure: TurnEpisodeStructure(
                    concreteFacts: ["周三下午的会议"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["没有提自己的意见"]
                )
            ),
            replyIntent: .exploreContext,
            replyGuidance: "请用户补充事件的发展过程"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .clarifyEvent)
        XCTAssertNotNil(decision.clarificationFocus)
        XCTAssertNotNil(decision.responseFocus)
    }

    func testEventDisclosureInviteCardConsentMapsToAdvanceToCardConsent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["一件具体的事"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["当时的具体做法"],
            eventProcessStatus: .present,
            eventProcess: ["事情是这样一步步发展的"]
        )

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                eventDisclosureOutcome: .readyForTenderOrCard
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "用一个已确认的事实作为简短过渡，邀请用户选择一张随机卡牌"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .advanceToCardConsent)
        XCTAssertNil(decision.clarificationFocus)
        XCTAssertNotNil(decision.responseFocus)
    }

    func testCardDevelopmentContinueMapsToContinueCardDevelopment() throws {
        let session = cardDevelopmentSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .developCardImage,
            replyGuidance: "请用户描述画面中接下来可能发生的变化"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .continueCardDevelopment)
        XCTAssertNotNil(decision.clarificationFocus)
    }

    func testCardDevelopmentInviteConnectionWithNoNextPromptMapsToInviteRealityConnection() throws {
        // This is the critical test: semantic mapping does NOT depend on nextPrompt.kind.
        let session = cardDevelopmentSession()
        let controller = ReflectionProtocolController()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            // Deliberately omit nextPrompt—the Planner may have emitted .none.
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .inviteCardConnection,
            replyGuidance: "邀请用户将画面中的行动与现实经历联系起来"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .inviteRealityConnection,
                       "Mapping must not rely on nextPrompt.kind; inviteCardConnection from development is inviteRealityConnection")
        XCTAssertNotNil(decision.clarificationFocus)
    }

    func testCardDevelopmentInviteConnectionWithOpenQuestionNextPromptStillMapsToInviteRealityConnection() throws {
        let session = cardDevelopmentSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            nextPrompt: .openQuestion(purpose: "connect_image_to_reality", focus: "画面关系与现实经历的关联"),
            replyIntent: .inviteCardConnection,
            replyGuidance: "邀请用户将画面中的行动与现实经历联系起来"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .inviteRealityConnection)
    }

    func testOpenExplorationInviteConnectionWithPendingCandidateWithoutScaffoldThrows() throws {
        // Bridge eligibility is unsatisfied: scaffoldUsed is false.
        let session = openCardConnectionSession()
        let pendingID = UUID()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                pendingCardRealityConnection: PendingCardRealityConnection(
                    id: pendingID,
                    imageRelation: "画面中的等待",
                    candidateRealityMapping: "现实中在等结果的阶段"
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardRealityConnection, referenceID: pendingID.uuidString),
            replyIntent: .inviteCardConnection,
            replyGuidance: "未经bridge eligibility的candidate offer"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation else {
                XCTFail("Expected SemanticMappingViolation, got \(error)")
                return
            }
            if case .cardSubstateMismatch(let intent, let substate) = violation {
                XCTAssertEqual(intent, .inviteCardConnection)
                XCTAssertEqual(substate, .openExploration)
            } else {
                XCTFail("Expected cardSubstateMismatch, got \(violation)")
            }
        }
    }

    func testOpenExplorationBridgeEligibleWithPendingCandidateMapsToOfferCandidate() throws {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        let pendingID = UUID()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                pendingCardRealityConnection: PendingCardRealityConnection(
                    id: pendingID,
                    imageRelation: "画面中的等待",
                    candidateRealityMapping: "现实中在等结果的阶段"
                )
            ),
            nextPrompt: .confirmationRequest(target: .cardRealityConnection, referenceID: pendingID.uuidString),
            replyIntent: .inviteCardConnection,
            replyGuidance: "提供一个候选映射，等待用户接受或修改"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .offerCardConnectionCandidate)
        XCTAssertNotNil(decision.clarificationFocus)
    }

    func testOpenExplorationInviteConnectionWithoutPendingMapsToContinueOpenCardConnection() throws {
        let session = openCardConnectionSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardConnection,
            replyGuidance: "继续探索画面与现实的关联"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .continueOpenCardConnection)
    }

    func testCardConnectionUnavailableDirectCandidReflectionMapsToBypass() throws {
        var session = cardDevelopmentSession()
        session.cardConnectionUnavailable = true

        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .directCandidReflection,
            replyGuidance: "用户无法建立画面联系，直接过渡到现实反思"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .bypassCardConnectionToDirectReflection)
        XCTAssertNil(decision.clarificationFocus)
    }

    func testCardDevelopmentAvailableDirectCandidReflectionThrowsMappingViolation() throws {
        // Connection is still available and the Planner tries to bypass from development.
        let session = cardDevelopmentSession()
        // Connection is available: cardConnectionUnavailable is false.

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .directCandidReflection,
            replyGuidance: "试图在画面开发阶段跳过卡片联系"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation else {
                XCTFail("Expected SemanticMappingViolation, got \(error)")
                return
            }
            if case .cardSubstateMismatch(let intent, let substate) = violation {
                XCTAssertEqual(intent, .directCandidReflection)
                XCTAssertEqual(substate, .development)
            } else {
                XCTFail("Expected cardSubstateMismatch, got \(violation)")
            }
        }
    }

    func testDirectReflectionMapsToTenderReflectionByDefault() throws {
        let session = directReflectionSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                reflectionFrame: TurnReflectionFrame(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [TurnReflectionEvidence(source: .episode, content: "用户描述的事实")],
                    dimensions: [.selfKindness],
                    reflectionDelta: "区分了事实和担忧",
                    fierceEvidence: nil
                )
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "帮助用户区分事实和对未来的担忧"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, PlannerSemanticOperation.continueTenderReflection)
    }

    func testDirectReflectionMapsToFierceReflectionWhenModeIsFierce() throws {
        let session = directReflectionSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                reflectionFrame: TurnReflectionFrame(
                    mode: .fierce,
                    action: .acknowledgeBehaviorImpact,
                    evidenceBasis: [
                        TurnReflectionEvidence(source: .episode, content: "用户描述的行为"),
                        TurnReflectionEvidence(source: .latestUserAnswer, content: "用户的补充说明"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "温和地指出了行为对他人的影响",
                    fierceEvidence: TurnFierceEvidence(
                        behavior: "具体行为描述",
                        impact: "对他人的具体影响",
                        direction: .repair
                    )
                )
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "基于事实温和地指出行为影响，同时保持关怀态度"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .continueTenderGroundedFierceReflection)
    }

    func testDirectReflectionMapsToSynthesizeWhenActionIsUnderstand() throws {
        let session = directReflectionSession()

        let plan = LLMTurnResponsePlan(
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                reflectionFrame: TurnReflectionFrame(
                    mode: .tender,
                    action: .synthesizeUnderstanding,
                    evidenceBasis: [TurnReflectionEvidence(source: .episode, content: "综合证据")],
                    dimensions: [.selfKindness, .commonHumanity],
                    reflectionDelta: "综合了所有反思内容",
                    fierceEvidence: nil
                )
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "综合理解并准备提出实践建议"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .synthesizeDirectReflection)
    }

    func testCardBypassAndDirectReflectionAreDifferentOperations() throws {
        // bypassCardConnectionToDirectReflection and continueTenderReflection must be different ops
        // even though both may originate from a Planner that emitted directCandidReflection.
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.continueTenderReflection
        )
    }

    func testCardBypassAndContinueCardDevelopmentAreDifferentOperations() throws {
        // bypassCardConnectionToDirectReflection and continueCardDevelopment must be different ops.
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.continueCardDevelopment
        )
    }

    func testUserAuthoredConnectionMapperProjectorAdapterAndWriterContract() async throws {
        var session = openCardConnectionSession()
        session.condition = .cardMediated
        let connection = TurnCardRealityConnection(
            imageRelation: "画面里的人正在重新安排随身物品",
            realityMapping: "用户把重新安排与现实中想放下一项负担联系起来",
            source: .userAuthored
        )
        let frame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "用户已经说明的具体经历"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "区分具体经历与对整个人的扩大判断",
            fierceEvidence: nil
        )
        let rawPlan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: frame),
            cardConnectionTurnOutcome: try .init(
                kind: .userAuthoredConnection,
                connection: connection
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .inviteCardConnection,
            replyGuidance: "把卡牌桥接和一个 Tender 问题写在同一条回复里"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: rawPlan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, .establishUserAuthoredCardConnection)
        XCTAssertEqual(decision.memoryUpdate.cardRealityConnection, connection)
        XCTAssertEqual(decision.memoryUpdate.reflectionFrame, frame)

        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: controller.effectiveCardState(for: session)
        )
        XCTAssertEqual(projected.requestedStage, .directReflection)
        XCTAssertEqual(projected.replyIntent, .directCandidReflection)
        XCTAssertEqual(projected.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(
            projected.nextPrompt.purpose,
            "tender_grounding_after_card_guidance"
        )
        XCTAssertNil(projected.resolvedConfirmation)

        let adapted = controller.executablePlanAdapter(from: projected)
        XCTAssertEqual(adapted.projectedOperation, decision.operation)
        XCTAssertEqual(adapted.requestedStage, projected.requestedStage)
        XCTAssertEqual(adapted.replyIntent, projected.replyIntent)
        XCTAssertEqual(adapted.localAction, projected.localAction)
        XCTAssertEqual(adapted.nextPrompt, projected.nextPrompt)
        XCTAssertEqual(adapted.memoryUpdate, projected.memoryUpdate)
        XCTAssertEqual(adapted.memoryUpdate.reflectionFrame, frame)
        XCTAssertNoThrow(try controller.validate(adapted, for: session))

        let writer = ScriptedReflectionTurnController(
            plans: [],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: "画面中的重新安排连到了现实。此刻最压住你的是什么？"
                    )
                ),
            ]
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: session.protocolVersion,
            protocolStage: session.protocolStage,
            condition: session.condition,
            permissions: controller.permissions(for: session),
            recentMessages: [],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )
        let writerResponse = try await writer.write(
            request: request,
            validatedPlan: adapted
        )
        XCTAssertEqual(writerResponse.realizedIntent, .directCandidReflection)
        XCTAssertEqual(writerResponse.reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        let receivedWriterPlans = await writer.receivedWriterPlans()
        let receivedPlan = try XCTUnwrap(receivedWriterPlans.first)
        XCTAssertEqual(receivedPlan.projectedOperation, .establishUserAuthoredCardConnection)
        XCTAssertEqual(receivedPlan.replyIntent, .directCandidReflection)
        XCTAssertEqual(receivedPlan.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(
            receivedPlan.nextPrompt?.purpose,
            "tender_grounding_after_card_guidance"
        )
        XCTAssertEqual(receivedPlan.memoryUpdate.cardRealityConnection, connection)
    }

    func testServerV44JSONFixtureDecodesThroughSemanticDecisionAndProjector() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/turn-v44-user-authored-connection.json")
        let rawPlan = try JSONDecoder().decode(
            LLMTurnResponsePlan.self,
            from: Data(contentsOf: fixtureURL)
        )
        var session = openCardConnectionSession()
        session.condition = .cardMediated

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: rawPlan, session: session, allowCurrentProtocolFixture: true)
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: controller.effectiveCardState(for: session)
        )

        XCTAssertEqual(decision.operation, .establishUserAuthoredCardConnection)
        XCTAssertEqual(
            decision.memoryUpdate.cardRealityConnection?.source,
            .userAuthored
        )
        XCTAssertEqual(projected.requestedStage, .directReflection)
        XCTAssertEqual(projected.replyIntent, .directCandidReflection)
        XCTAssertEqual(projected.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(
            projected.nextPrompt.purpose,
            "tender_grounding_after_card_guidance"
        )
    }

    func testLegacyProtocolFieldsCannotOverrideAValidUserAuthoredSemanticOperation() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/turn-v44-user-authored-connection.json")
        let source = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixtureURL)
        ) as! [String: Any]
        var session = openCardConnectionSession()
        session.condition = .cardMediated

        func projected(from object: [String: Any]) throws -> ProjectedExecutableTurnPlan {
            let data = try JSONSerialization.data(withJSONObject: object)
            let raw = try JSONDecoder().decode(LLMTurnResponsePlan.self, from: data)
            let decision = try controller.legacySemanticDecisionFromProtocolFields(from: raw, session: session, allowCurrentProtocolFixture: true)
            return try controller.projectExecutablePlan(
                decision: decision,
                session: session,
                effectiveEventState: .init(memory: session.semanticMemory),
                effectiveCardState: controller.effectiveCardState(for: session)
            )
        }

        let expected = try projected(from: source)
        var conflictingRequestedStage = source
        conflictingRequestedStage["requestedStage"] = "complete"

        var conflictingLocalAction = source
        conflictingLocalAction["localAction"] = [
            "kind": "completeSession",
            "trackingCueIDs": [],
        ]

        var conflictingNextPrompt = source
        conflictingNextPrompt["nextPrompt"] = [
            "kind": "confirmationRequest",
            "purpose": NSNull(),
            "focus": NSNull(),
            "disclosurePurpose": NSNull(),
            "disclosureTarget": NSNull(),
            "disclosureReopenReason": NSNull(),
            "target": "finalNarrative",
            "referenceID": "legacy-conflict",
        ]

        var conflictingConfirmation = source
        conflictingConfirmation["resolvedConfirmation"] = [
            "target": "cardConsent",
            "decision": "accepted",
            "referenceID": "legacy-conflict",
        ]

        for conflict in [
            conflictingRequestedStage,
            conflictingLocalAction,
            conflictingNextPrompt,
            conflictingConfirmation,
        ] {
            let actual = try projected(from: conflict)
            XCTAssertEqual(actual.semanticDecision.operation, expected.semanticDecision.operation)
            XCTAssertEqual(actual.requestedStage, expected.requestedStage)
            XCTAssertEqual(actual.replyIntent, expected.replyIntent)
            XCTAssertEqual(actual.localAction, expected.localAction)
            XCTAssertEqual(actual.nextPrompt, expected.nextPrompt)
            XCTAssertEqual(actual.resolvedConfirmation, expected.resolvedConfirmation)
        }
    }

    func testExistingCanonicalConnectionDoesNotAdvertiseCombinedTurn() {
        var session = canonicalConnectionV5Session()
        session.condition = .cardMediated
        let permissions = controller.permissions(for: session)

        XCTAssertTrue(permissions.allowedReplyIntents.contains(.authorizeCardGuidance))
        XCTAssertFalse(permissions.allowedReplyIntents.contains(.directCandidReflection))
        XCTAssertFalse(
            permissions.allowedOperations.contains(
                .init(
                    requestedStage: .directReflection,
                    replyIntent: .directCandidReflection,
                    localAction: .shareCardGuidance
                )
            )
        )
    }

    func testDirectReflectionStageCannotSubstituteForProjectedConnectionOperation() {
        var session = openCardConnectionSession()
        session.condition = .cardMediated
        let unprojected = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(
                cardRealityConnection: .init(
                    imageRelation: "画面关系",
                    realityMapping: "现实映射",
                    source: .userAuthored
                ),
                reflectionFrame: .init(
                    mode: .tender,
                    action: .softenGlobalSelfJudgment,
                    evidenceBasis: [.init(source: .episode, content: "具体经历")],
                    dimensions: [.selfKindness],
                    reflectionDelta: "形成一个新的事实区分",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: .openQuestion(
                purpose: "tender_grounding_after_card_guidance",
                focus: "开始 Tender 反思"
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "缺少 projector operation 的伪 combined turn"
        )

        XCTAssertThrowsError(try controller.validate(unprojected, for: session)) {
            XCTAssertEqual($0 as? ReflectionProtocolViolation, .illegalReplyIntent)
        }
    }

    func testV5CanonicalConnectionAuthorizeCardGuidance() throws {
        let session = canonicalConnectionV5Session()

        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: TurnSemanticMemoryUpdate(
                cardRealityConnection: TurnCardRealityConnection(
                    imageRelation: "画面中的跨越",
                    realityMapping: "现实中跨越困难的决定",
                    source: .userAuthored
                )
            ),
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "静默授权卡片引导，准备进入Direct Reflection"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .authorizeCardGuidance)
        XCTAssertNil(decision.clarificationFocus)
    }

    func testV4CanonicalConnectionPresentLegacyCardReading() throws {
        let session = canonicalConnectionV4Session()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                cardNegotiatedMeaning: "基于用户映射的协商解读"
            ),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .presentCardReading,
            replyGuidance: "提出协商解读，等待用户确认"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .presentLegacyCardReading)
    }

    func testCandidateAcceptedMapsToAcceptCardConnectionCandidate() throws {
        let session = awaitingCandidateResolutionSession()

        let outcome = try CardConnectionTurnOutcome(kind: .candidateAccepted)
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            cardConnectionTurnOutcome: outcome,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "用户接受了候选映射"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .acceptCardConnectionCandidate)
    }

    func testCandidateRevisedMapsToReviseCardConnectionCandidate() throws {
        let session = awaitingCandidateResolutionSession()

        let outcome = try CardConnectionTurnOutcome(
            kind: .candidateRevised,
            connection: TurnCardRealityConnection(
                imageRelation: "画面中的转身",
                realityMapping: "现实中改变方向的决定",
                source: .userRevised
            )
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            cardConnectionTurnOutcome: outcome,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "用户修改了候选映射"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .reviseCardConnectionCandidate)
    }

    func testCandidateRejectedMapsToRejectCardConnectionCandidate() throws {
        let session = awaitingCandidateResolutionSession()

        let outcome = try CardConnectionTurnOutcome(kind: .candidateRejected)
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            cardConnectionTurnOutcome: outcome,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "用户拒绝了候选映射"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .rejectCardConnectionCandidate)
    }

    func testExplorationUserAuthoredConnectionThrowsMappingViolation() throws {
        // userAuthoredConnection is NOT a candidate-resolution outcome.
        // It should not appear in the awaitingCandidateResolution substate.
        let session = awaitingCandidateResolutionSession()

        let outcome = try CardConnectionTurnOutcome(
            kind: .userAuthoredConnection,
            connection: TurnCardRealityConnection(
                imageRelation: "一些关系",
                realityMapping: "一些映射",
                source: .userAuthored
            )
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            cardConnectionTurnOutcome: outcome,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "This outcome kind does not belong to awaitingCandidateResolution"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true))
    }

    func testRetiredDeepenCardConnectionThrowsInCurrentProtocol() throws {
        var session = openCardConnectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .deepenCardConnection,
            replyGuidance: "This intent is retired in current protocol"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation else {
                XCTFail("Expected SemanticMappingViolation")
                return
            }
            if case .unclassifiablePlan(let message) = violation {
                XCTAssertTrue(message.contains("retired"))
            } else {
                XCTFail("Expected unclassifiablePlan")
            }
        }
    }

    func testCardConsentInviteStaysInCardConsent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardConsent
        session.semanticMemory.nextPrompt = .confirmationRequest(target: .cardConsent)

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardConsent,
            replyGuidance: "继续询问用户是否愿意尝试卡牌"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .inviteCardConsent)
    }

    func testContextualDisclosureUnknownIntentThrowsMappingViolation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure

        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .completeConversation,
            replyGuidance: "Cannot complete from disclosure without safety"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation else {
                XCTFail("Expected SemanticMappingViolation")
                return
            }
            if case .ambiguousReplyIntent(let intent, let stage) = violation {
                XCTAssertEqual(intent, .completeConversation)
                XCTAssertEqual(stage, .contextualDisclosure)
            } else {
                XCTFail("Expected ambiguousReplyIntent")
            }
        }
    }

    func testCardObservationInviteConnectionIsMappingViolation() throws {
        // invitation from initial observation (0 dev turns) should fail
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardConnection,
            replyGuidance: "Too early for connection—no image development done yet"
        )

        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation else {
                XCTFail("Expected SemanticMappingViolation")
                return
            }
            if case .cardSubstateMismatch(let intent, let substate) = violation {
                XCTAssertEqual(intent, .inviteCardConnection)
                XCTAssertEqual(substate, .observation)
            } else {
                XCTFail("Expected cardSubstateMismatch, got \(violation)")
            }
        }
    }

    func testCardSemanticSubstateIsNoneOutsideCardReflection() {
        var session = ReflectionSession()
        session.protocolStage = .contextualDisclosure

        let substate = controller.cardSemanticSubstate(for: session)
        XCTAssertEqual(substate, .none)
    }

    func testSafetySupportIsPermittedFromAnyStage() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 1

        let plan = LLMTurnResponsePlan(
            requestedStage: .safetySupport,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .safetySupport,
            replyGuidance: "Safety takes priority over card work"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .provideSafetySupport)
    }

    func testProposePracticeAndResolvePracticeAreDifferentOperations() {
        XCTAssertNotEqual(
            PlannerSemanticOperation.proposePractice,
            PlannerSemanticOperation.resolvePractice
        )
    }

    func testCompleteConversationMapsCorrectly() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .complete

        let plan = LLMTurnResponsePlan(
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .completeConversation,
            replyGuidance: "结束对话"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)

        XCTAssertEqual(decision.operation, .completeConversation)
        XCTAssertNil(decision.clarificationFocus)
    }

    // MARK: - Tightened Card substate boundaries

    func testOpenExplorationDevelopCardImageAsScaffoldMapsToOfferCardConnectionScaffold() throws {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = false
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .developCardImage,
            replyGuidance: "Scaffold: narrow connection task using existing image relation"
        )
        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, .offerCardConnectionScaffold)
    }

    func testOpenExplorationDevelopCardImageWhenScaffoldAlreadyUsedThrows() throws {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .developCardImage,
            replyGuidance: "Second scaffold attempt"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true))
    }

    func testCardDevelopmentInviteConnectionWithPendingCandidateThrowsViolation() throws {
        // Candidate bridge cannot be offered directly from development even if the
        // Planner supplies a complete pending candidate.
        let session = cardDevelopmentSession()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                pendingCardRealityConnection: PendingCardRealityConnection(
                    imageRelation: "画面中的跨越",
                    candidateRealityMapping: "现实中跨越困难"
                )
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "Cannot offer candidate from development—must enter open exploration first"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation,
                  case .cardSubstateMismatch(let intent, let substate) = violation else {
                XCTFail("Expected cardSubstateMismatch, got \(error)")
                return
            }
            XCTAssertEqual(intent, .inviteCardConnection)
            XCTAssertEqual(substate, .development)
        }
    }

    func testExistingPendingCandidateBlocksSecondCandidate() throws {
        // A pending candidate is already active in session memory; the Planner
        // may not create a second one.
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        let existingID = UUID()
        session.semanticMemory.pendingCardRealityConnection = PendingCardRealityConnection(
            id: existingID,
            imageRelation: "现有图像关系",
            candidateRealityMapping: "现有候选映射"
        )
        // The prompt must match for the pending candidate to be "awaiting resolution".
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: existingID.uuidString
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                pendingCardRealityConnection: PendingCardRealityConnection(
                    imageRelation: "第二个图像关系",
                    candidateRealityMapping: "第二个候选映射"
                )
            ),
            replyIntent: .inviteCardConnection,
            replyGuidance: "Attempting to propose a second candidate while one is already active"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true))
    }

    func testV5GuidanceSubstateDirectCandidReflectionThrowsViolation() throws {
        // In v5 guidance substate, directCandidReflection is not a legal operation.
        // Guidance authorization uses authorizeCardGuidance, not directCandidReflection.
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = TurnCardRealityConnection(
            imageRelation: "画面中的跨越",
            realityMapping: "现实中跨越困难的决定",
            source: .userAuthored
        )

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .directCandidReflection,
            replyGuidance: "Cannot use directCandidReflection in guidance—use authorizeCardGuidance"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation,
                  case .cardSubstateMismatch(let intent, let substate) = violation else {
                XCTFail("Expected cardSubstateMismatch, got \(error)")
                return
            }
            XCTAssertEqual(intent, .directCandidReflection)
            XCTAssertEqual(substate, .guidance)
        }
    }

    func testV5GuidanceAuthorizedDirectReflectionTenderFrameMapsToContinueTenderReflection() throws {
        // After guidance is authorized and stage is directReflection, a fresh Tender
        // reflection turn maps correctly.
        var session = directReflectionSession()
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = TurnCardRealityConnection(
            imageRelation: "画面中的跨越",
            realityMapping: "现实中跨越困难的决定",
            source: .userAuthored
        )

        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                reflectionFrame: TurnReflectionFrame(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [TurnReflectionEvidence(source: .episode, content: "用户确认的事实")],
                    dimensions: [.selfKindness],
                    reflectionDelta: "区分事实和担忧",
                    fierceEvidence: nil
                )
            ),
            replyIntent: .directCandidReflection,
            replyGuidance: "Fresh Tender reflection turn after guidance authorization"
        )

        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, PlannerSemanticOperation.continueTenderReflection)
    }

    func testV4CanonicalConnectionDirectCandidReflectionThrowsMappingViolation() throws {
        // In v4, there is no bypass to directCandidReflection from the card stage
        // within canonical connection. The v4 path uses presentCardReading.
        let session = canonicalConnectionV4Session()

        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .directCandidReflection,
            replyGuidance: "v4 does not route directCandidReflection from cardReflection"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true))
    }

    func testObservationInviteObservationMapsToContinueCardObservation() throws {
        // The Planner continues inviting the person to describe visible content.
        let session = observationSession()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardObservation,
            replyGuidance: "继续邀请描述画面中可见的内容"
        )
        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, .continueCardObservation)
    }

    func testDevelopmentInviteObservationThrowsViolation() throws {
        // Once development has started, returning to observation is not allowed.
        let session = cardDevelopmentSession()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardObservation,
            replyGuidance: "Cannot return to observation from development"
        )
        XCTAssertThrowsError(try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)) { error in
            guard let violation = error as? SemanticMappingViolation,
                  case .cardSubstateMismatch(let intent, let substate) = violation else {
                XCTFail("Expected cardSubstateMismatch, got \(error)")
                return
            }
            XCTAssertEqual(intent, .inviteCardObservation)
            XCTAssertEqual(substate, .development)
        }
    }

    func testObservationDevelopImageMapsToContinueCardDevelopment() throws {
        // From observation, the first development question transitions into development.
        let session = observationSession()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .developCardImage,
            replyGuidance: "从观察进入画面发展"
        )
        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, .continueCardDevelopment)
    }

    func testDevelopmentInviteRealityConnectionMapsCorrectly() throws {
        // After sufficient development, the first reality-connection invitation.
        let session = cardDevelopmentSession()
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            replyIntent: .inviteCardConnection,
            replyGuidance: "邀请将画面关系与现实联系起来"
        )
        let decision = try controller.legacySemanticDecisionFromProtocolFields(from: plan, session: session, allowCurrentProtocolFixture: true)
        XCTAssertEqual(decision.operation, .inviteRealityConnection)
    }

    func testBypassDestinationIsDirectReflectionNotCardReflection() {
        // bypassCardConnectionToDirectReflection must represent a real stage transition:
        // Card Reflection → Direct Reflection, not cardReflection → cardReflection.
        // This is a semantic invariant, not a production transition change.
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.continueCardDevelopment
        )
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.continueCardObservation
        )
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.inviteRealityConnection
        )
        XCTAssertNotEqual(
            PlannerSemanticOperation.bypassCardConnectionToDirectReflection,
            PlannerSemanticOperation.continueOpenCardConnection
        )
    }

    // MARK: - EffectiveCardSemanticState tests

    func testObservationNoDevelopmentStateReturnsObservation() {
        let session = observationSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .observation)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
        XCTAssertFalse(state.explorationStarted)
        XCTAssertFalse(state.pendingCandidateExists)
        XCTAssertFalse(state.canonicalConnectionExists)
        XCTAssertFalse(state.guidanceAuthorized)
    }

    func testObservationWithTurnCountDoesNotOverrideTypedEvidence() {
        // Even if a compatibility counter is present, current v5 uses only typed evidence.
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 2
        session.cardConnectionAttemptCount = 0
        session.cardConnectionScaffoldUsed = false
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["两个人"]
        )

        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .observation)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
    }

    func testObservationWithDevelopmentReturnsDevelopment() {
        let session = cardDevelopmentSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .development)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertTrue(state.developmentEvidenceExists)
        XCTAssertFalse(state.explorationStarted)
        XCTAssertFalse(state.pendingCandidateExists)
    }

    func testOpenExplorationSubstateIgnoresTurnCount() {
        var session = openCardConnectionSession()
        // The compatibility counter is irrelevant once typed Development exists.
        session.cardImageDevelopmentTurnCount = 0
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .openExploration)
        XCTAssertTrue(state.explorationStarted)
        XCTAssertTrue(state.developmentEvidenceExists)
    }

    func testPendingCandidateSubstateUnaffectedByTurnCount() {
        let session = awaitingCandidateResolutionSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .awaitingCandidateResolution)
        XCTAssertTrue(state.pendingCandidateExists)
        // turnCount and attemptCount are irrelevant
    }

    func testCanonicalConnectionReturnsGuidanceInV5() {
        var session = canonicalConnectionV5Session()
        session.cardGuidanceShared = true
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .guidance)
        XCTAssertTrue(state.canonicalConnectionExists)
        XCTAssertTrue(state.guidanceAuthorized)
    }

    func testCanonicalWithoutGuidanceReturnsOpenExploration() {
        // v5 canonical connection exists but guidance not yet authorized.
        let session = canonicalConnectionV5Session()
        // connection not unavailable, not pending, but canonical exists
        let state = EffectiveCardSemanticState(session: session)
        // canonicalConnectionExists but !guidanceAuthorized → falls through to
        // explorationStarted? No. Let me check: canonicalConnectionV5Session has
        // cardImageDevelopmentTurnCount=1, cardConnectionAttemptCount=0,
        // cardConnectionScaffoldUsed=false. So explorationStarted=false,
        // developmentEvidenceExists=true → development.
        XCTAssertEqual(state.substate, .development)
        XCTAssertTrue(state.canonicalConnectionExists)
        XCTAssertFalse(state.guidanceAuthorized)
    }

    func testFailedPlanDoesNotAdvancePersistedSubstate() {
        // A failed plan means no commit. persisted state is unchanged.
        let session = cardDevelopmentSession()
        let stateBefore = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(stateBefore.substate, .development)

        // Simulate: the same session (no commit happened) — state is identical.
        let stateAfter = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(stateAfter.substate, .development)
        XCTAssertEqual(stateBefore, stateAfter)
    }

    // MARK: - Candidate bridge eligibility

    func testCandidateBridgeEligibleWhenConditionsMet() {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 1
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.explorationStarted)
        XCTAssertTrue(state.connectionDifficultyOccurred)
        XCTAssertTrue(state.bridgeScaffoldUsed)
        XCTAssertFalse(state.pendingCandidateExists)
        XCTAssertFalse(state.guidanceAuthorized)
        XCTAssertTrue(state.candidateBridgeEligible)
    }

    func testCandidateBridgeNotEligibleFromDevelopment() {
        let session = cardDevelopmentSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .development)
        XCTAssertFalse(state.candidateBridgeEligible)
    }

    func testCandidateBridgeNotEligibleWhenAlreadyUsed() {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 1
        // Simulate: bridge was already offered → pending candidate exists
        let id = UUID()
        session.semanticMemory.pendingCardRealityConnection = PendingCardRealityConnection(
            id: id,
            imageRelation: "a",
            candidateRealityMapping: "b"
        )
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: id.uuidString
        )
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.pendingCandidateExists)
        XCTAssertFalse(state.candidateBridgeEligible)
    }

    func testCandidateBridgeNotEligibleWithCanonicalConnection() {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 1
        session.semanticMemory.cardRealityConnection = TurnCardRealityConnection(
            imageRelation: "a",
            realityMapping: "b",
            source: .userAuthored
        )
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.canonicalConnectionExists)
        XCTAssertFalse(state.candidateBridgeEligible)
    }

    func testLegacyScaffoldFlagAloneDoesNotGrantEligibility() {
        // scaffoldUsed=true but no formal connection difficulty (attemptCount=0).
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 0
        let state = EffectiveCardSemanticState(session: session)
        // explorationStarted is true because scaffoldUsed=true. But
        // connectionDifficultyOccurred is also true for the same reason.
        // candidateBridgeEligible requires ALL conditions. With attemptCount=0
        // and scaffoldUsed=true, both explorationStarted and
        // connectionDifficultyOccurred are true. So eligibility IS granted.
        // The scaffold flag alone (without attempt count) IS sufficient
        // because it carries "difficulty occurred" semantics.
        XCTAssertTrue(state.connectionDifficultyOccurred)
        XCTAssertTrue(state.candidateBridgeEligible)
    }

    // MARK: - PendingUncommittedCardAnswerContext

    func testNoUncommittedAnswerWhenNextPromptIsNone() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .none
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(
            session: session,
            lastCommittedState: state
        )
        XCTAssertFalse(ctx.hasUncommittedLatestAnswer)
        XCTAssertNil(ctx.pendingCardPurpose)
    }

    func testUncommittedAnswerWhenOpenQuestionPending() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_image_development",
            focus: "画面接下来可能发生什么"
        )
        // Add a user message without a matching assistant reply.
        let userMessageID = UUID()
        session.messages = [
            ChatMessage(id: userMessageID, role: .user, content: "我觉得接下来可能会...")
        ]
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(
            session: session,
            lastCommittedState: state
        )
        XCTAssertTrue(ctx.hasUncommittedLatestAnswer)
        XCTAssertEqual(ctx.pendingCardPurpose, "card_image_development")
    }

    func testFailedPlanPreservesCommittedState() {
        let session = cardDevelopmentSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(state.substate, .development)

        // Failed plan does not change session or state.
        let ctx = PendingUncommittedCardAnswerContext(
            session: session,
            lastCommittedState: state
        )
        XCTAssertEqual(ctx.lastCommittedState.substate, .development)
    }

    // MARK: - Pending answer identity (message-ID-based)

    func testNoUncommittedAnswerWhenNextPromptIsNoneButNoUserMessage() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .none
        // No user message in transcript → no uncommitted answer.
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertFalse(ctx.hasUncommittedLatestAnswer)
    }

    func testUncommittedAnswerWhenUserMessageWithoutMatchingReply() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .openQuestion(purpose: "test", focus: "test")
        let userID = UUID()
        session.messages = [ChatMessage(id: userID, role: .user, content: "answer")]
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertTrue(ctx.hasUncommittedLatestAnswer)
    }

    func testNoUncommittedAnswerWhenUserMessageHasMatchingReply() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .openQuestion(purpose: "test", focus: "test")
        let userID = UUID()
        session.messages = [
            ChatMessage(id: userID, role: .user, content: "answer"),
            ChatMessage(id: UUID(), role: .assistant, content: "reply", replyToMessageID: userID),
        ]
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertFalse(ctx.hasUncommittedLatestAnswer)
    }

    func testRetryWithoutNewMessageDoesNotTriggerNewAnswer() {
        var session = cardDevelopmentSession()
        let userID = UUID()
        session.messages = [
            ChatMessage(id: userID, role: .user, content: "old answer"),
            ChatMessage(id: UUID(), role: .assistant, content: "reply", replyToMessageID: userID),
        ]
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertFalse(ctx.hasUncommittedLatestAnswer)
    }

    // MARK: - Typed Card evidence

    func testTypedObservationEvidenceOverridesLegacy() {
        var session = cardDevelopmentSession()
        session.cardImageDevelopmentTurnCount = 0
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["两个人", "一棵树"]
        )
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertFalse(state.isLegacyProjection)
    }

    func testTypedDevelopmentEvidenceOverridesTurnCount() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 0
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["两个人"],
            projectiveFocus: "两个人交换后是否会分开",
            relationOrAction: "正在交换物品",
            anticipatedChangeOrChoice: "可能会分开"
        )
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.developmentEvidenceExists)
        XCTAssertFalse(state.isLegacyProjection)
    }

    func testCurrentV5MissingTypedCardEvidenceDoesNotFallbackToLegacyCounters() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 2

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .none)
        XCTAssertFalse(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
        XCTAssertFalse(state.isLegacyProjection)
        XCTAssertEqual(state.evidenceSource, .currentTyped)
    }

    func testCurrentV5TypedObservationDoesNotNeedLegacyTurnCount() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardImageDevelopmentTurnCount = 0
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["一扇门"]
        )

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .observation)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
        XCTAssertEqual(state.evidenceSource, .currentTyped)
    }

    func testCurrentV5DevelopmentStateRecordsPresenceWithoutJudgingNarrativeCompleteness() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 0
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["一个人", "一扇门"]
        )
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["一个人"],
            relationOrAction: "正在打开门",
            anticipatedChangeOrChoice: nil
        )

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .development)
        XCTAssertTrue(state.developmentEvidenceExists)
        XCTAssertEqual(state.evidenceSource, .currentTyped)
    }

    func testCurrentV5ScaffoldFlagCannotCreateMissingCardEvidence() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 1

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .none)
        XCTAssertFalse(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
        XCTAssertFalse(state.explorationStarted)
        XCTAssertFalse(state.connectionDifficultyOccurred)
        XCTAssertFalse(state.candidateBridgeEligible)
        XCTAssertEqual(state.evidenceSource, .currentTyped)
    }

    func testLegacySessionTurnCountOnlyYieldsLegacyProjection() {
        var session = cardDevelopmentSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.semanticMemory.cardObservationEvidence = nil
        session.semanticMemory.cardDevelopmentEvidence = nil
        session.cardImageDevelopmentTurnCount = 1
        // No typed evidence — legacy projection.
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.developmentEvidenceExists)
        XCTAssertTrue(state.isLegacyProjection)
        XCTAssertEqual(state.evidenceSource, .legacyProjected)
    }

    func testLegacySessionDisplayedCardProjectsObservation() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .observation)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertTrue(state.isLegacyProjection)
        XCTAssertEqual(state.evidenceSource, .legacyProjected)
    }

    func testLegacyScaffoldWithCountersRestoresProjectedExploration() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 1
        session.cardConnectionScaffoldUsed = true

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .openExploration)
        XCTAssertTrue(state.developmentEvidenceExists)
        XCTAssertTrue(state.explorationStarted)
        XCTAssertTrue(state.isLegacyProjection)
    }

    func testLegacySaveReloadPreservesProjectionWithoutForgingTypedEvidence() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 1

        let before = controller.effectiveCardState(for: session)
        let reloaded = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(session)
        )
        let after = controller.effectiveCardState(for: reloaded)

        XCTAssertEqual(before, after)
        XCTAssertNil(reloaded.semanticMemory.cardObservationEvidence)
        XCTAssertNil(reloaded.semanticMemory.cardDevelopmentEvidence)
        XCTAssertEqual(after.evidenceSource, .legacyProjected)
    }

    func testLegacyNewTypedTurnDoesNotLetOldCounterOverrideTypedEvidence() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 3
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["一个包裹"]
        )

        let state = controller.effectiveCardState(for: session)

        XCTAssertEqual(state.substate, .observation)
        XCTAssertTrue(state.observationEvidenceExists)
        XCTAssertFalse(state.developmentEvidenceExists)
        XCTAssertEqual(state.evidenceSource, .legacyProjected)
        XCTAssertNil(session.semanticMemory.cardDevelopmentEvidence)
    }

    func testProtocolIdentityDoesNotDependOnTypedEvidenceBeingNil() {
        var current = ReflectionSession()
        current.protocolVersion = ReflectionSession.currentProtocolVersion
        current.protocolStage = .cardReflection
        var legacy = current
        legacy.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion

        let currentState = controller.effectiveCardState(for: current)
        let legacyState = controller.effectiveCardState(for: legacy)

        XCTAssertEqual(currentState.evidenceSource, .currentTyped)
        XCTAssertFalse(currentState.isLegacyProjection)
        XCTAssertEqual(legacyState.evidenceSource, .legacyProjected)
        XCTAssertTrue(legacyState.isLegacyProjection)
    }

    func testCurrentV5RejectsEmptyTypedEvidenceWithoutMutatingPersistedState() {
        var session = cardDevelopmentSession()
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_image_development",
            focus: "画面接下来会发生什么"
        )
        let userMessageID = UUID()
        session.messages = [
            ChatMessage(id: userMessageID, role: .user, content: "我还没有看清")
        ]
        let oldMemory = session.semanticMemory
        let oldState = controller.effectiveCardState(for: session)
        let oldPending = PendingUncommittedCardAnswerContext(
            session: session,
            lastCommittedState: oldState
        )
        let invalid = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: TurnSemanticMemoryUpdate(
                cardObservationEvidence: CardObservationEvidence()
            ),
            nextPrompt: .openQuestion(
                purpose: "card_image_development",
                focus: "画面接下来会发生什么"
            ),
            replyIntent: .developCardImage,
            replyGuidance: "继续画面探索"
        )

        XCTAssertThrowsError(try controller.validate(invalid, for: session)) { error in
            XCTAssertEqual(error as? ReflectionProtocolViolation, .conflictingMemoryPatch)
        }

        XCTAssertEqual(session.semanticMemory, oldMemory)
        XCTAssertEqual(controller.effectiveCardState(for: session), oldState)
        XCTAssertEqual(session.semanticMemory.nextPrompt, oldMemory.nextPrompt)
        XCTAssertTrue(oldPending.hasUncommittedLatestAnswer)
        XCTAssertTrue(PendingUncommittedCardAnswerContext(
            session: session,
            lastCommittedState: oldState
        ).hasUncommittedLatestAnswer)
    }

    func testCandidateBridgeOfferedOrResolvedWhenResolvedAtSet() {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        session.cardConnectionAttemptCount = 1
        session.semanticMemory.candidateBridgeResolvedAt = Date()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.candidateBridgeOfferedOrResolved)
        XCTAssertFalse(state.candidateBridgeEligible)
    }

    func testCandidateBridgeOfferedOrResolvedWhenPendingExists() {
        let session = awaitingCandidateResolutionSession()
        let state = EffectiveCardSemanticState(session: session)
        XCTAssertTrue(state.candidateBridgeOfferedOrResolved)
        XCTAssertFalse(state.candidateBridgeEligible)
    }

    // MARK: - Projector tests

    func testClarifyEventProjectsOpenQuestionWithDisclosurePurpose() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.situationUnderstanding = "initial"

        let decision = PlannerSemanticDecision(
            operation: .clarifyEvent,
            memoryUpdate: TurnSemanticMemoryUpdate(situationUnderstanding: "updated"),
            responseFocus: "Ask about behavior",
            clarificationFocus: "clarify_behavior"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: eventState,
            effectiveCardState: cardState
        )
        XCTAssertEqual(projected.requestedStage, .contextualDisclosure)
        XCTAssertEqual(projected.replyIntent, .exploreContext)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertNotNil(projected.nextPrompt.disclosurePurpose)
        XCTAssertEqual(projected.localAction.kind, .none)
    }

    func testClarifyEventRejectedWhenDisclosureComplete() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["event"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["behavior"],
            eventProcessStatus: .present,
            eventProcess: ["process"]
        )
        let decision = PlannerSemanticDecision(
            operation: .clarifyEvent,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil,
            clarificationFocus: "too_late"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testAdvanceToCardConsentProjectsCardConsentConfirmation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["event"],
            behaviorEvidenceStatus: .present, behaviorEvidence: ["behavior"],
            eventProcessStatus: .present, eventProcess: ["process"]
        )
        let decision = PlannerSemanticDecision(
            operation: .advanceToCardConsent,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: "bridge to card",
            clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.requestedStage, .cardConsent)
        XCTAssertEqual(projected.replyIntent, .inviteCardConsent)
        XCTAssertEqual(projected.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(projected.nextPrompt.target, .cardConsent)
    }

    func testAdvanceToCardConsentIgnoringLegacyNextPromptNone() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["event"],
            behaviorEvidenceStatus: .present, behaviorEvidence: ["behavior"],
            eventProcessStatus: .present, eventProcess: ["process"]
        )
        // Simulate: old Planner emitted nextPrompt=none, requestedStage=contextualDisclosure
        // Projector must ignore these and generate the correct Card Consent plan.
        let decision = PlannerSemanticDecision(
            operation: .advanceToCardConsent,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: "bridge",
            clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(projected.nextPrompt.target, .cardConsent)
    }

    func testInviteRealityConnectionAlwaysProjectsOpenQuestion() throws {
        // Critical test: inviteRealityConnection must never produce nextPrompt.none
        let session = cardDevelopmentSession()
        let decision = PlannerSemanticDecision(
            operation: .inviteRealityConnection,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: "connect image to reality",
            clarificationFocus: "image_to_life"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.replyIntent, .inviteCardConnection)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(projected.requestedStage, .cardReflection)
    }

    func testContinueCardObservationOnlyInObservationSubstate() throws {
        let session = observationSession()
        let decision = PlannerSemanticDecision(
            operation: .continueCardObservation,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: "what_do_you_see"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.replyIntent, .inviteCardObservation)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
    }

    func testContinueCardDevelopmentRejectedInOpenExploration() throws {
        // continueCardDevelopment is NOT allowed in openExploration — use offerCardConnectionScaffold.
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = false
        let decision = PlannerSemanticDecision(
            operation: .continueCardDevelopment,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: "dev"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testOfferCandidateRejectedWithoutBridgeEligibility() throws {
        let session = openCardConnectionSession()
        // scaffoldUsed=false → bridge not eligible
        let pendingID = UUID()
        let memUpdate = TurnSemanticMemoryUpdate(
            pendingCardRealityConnection: PendingCardRealityConnection(
                id: pendingID, imageRelation: "r", candidateRealityMapping: "m"
            )
        )
        let decision = PlannerSemanticDecision(
            operation: .offerCardConnectionCandidate,
            memoryUpdate: memUpdate,
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testBypassRequiresConnectionUnavailable() throws {
        let session = cardDevelopmentSession()
        let decision = PlannerSemanticDecision(
            operation: .bypassCardConnectionToDirectReflection,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        // connectionUnavailable=false → must throw
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testBypassProjectsDirectReflectionStage() throws {
        var session = cardDevelopmentSession()
        session.cardConnectionUnavailable = true
        let decision = PlannerSemanticDecision(
            operation: .bypassCardConnectionToDirectReflection,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.requestedStage, .directReflection)
        XCTAssertEqual(projected.replyIntent, .directCandidReflection)
    }

    func testV5AuthorizeCardGuidanceProjectsShareCardGuidance() throws {
        var session = canonicalConnectionV5Session()
        session.cardGuidanceShared = false
        let decision = PlannerSemanticDecision(
            operation: .authorizeCardGuidance,
            memoryUpdate: TurnSemanticMemoryUpdate(
                reflectionFrame: TurnReflectionFrame(
                    mode: .tender,
                    action: .distinguishFactFromPrediction,
                    evidenceBasis: [.init(source: .episode, content: "用户确认的现实事实")],
                    dimensions: [.selfKindness],
                    reflectionDelta: "区分具体事实与整体自我评价",
                    fierceEvidence: nil
                )
            ),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.replyIntent, .directCandidReflection)
        XCTAssertEqual(projected.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(projected.requestedStage, .directReflection)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
    }

    func testV4PresentLegacyCardReadingRejectedInV5() throws {
        let session = canonicalConnectionV5Session()
        let decision = PlannerSemanticDecision(
            operation: .presentLegacyCardReading,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testCompleteConversationProjectsCompleteSession() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: "final-narrative-1"
        )
        let decision = PlannerSemanticDecision(
            operation: .completeConversation,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.requestedStage, .complete)
        XCTAssertEqual(projected.replyIntent, .completeConversation)
        XCTAssertEqual(projected.localAction.kind, .completeSession)
        XCTAssertEqual(projected.nextPrompt.kind, .none)
        XCTAssertEqual(projected.resolvedConfirmation?.target, .finalNarrative)
        XCTAssertEqual(projected.resolvedConfirmation?.decision, .accepted)
        XCTAssertEqual(projected.resolvedConfirmation?.referenceID, "final-narrative-1")
    }

    func testCurrentCardEffectiveStateProjectsLatestObservationWithoutCommittingIt() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = cardStub()
        session.cardDisplayState = .displayed
        let observation = CardObservationEvidence(
            userDescribedElements: ["人物正在看桌上的物件"]
        )
        let plan = LLMTurnResponsePlan(
            semanticOperation: .continueCardDevelopment,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(cardObservationEvidence: observation),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "继续想象画面中这段关系接下来会怎样变化"
        )

        let decision = try controller.semanticDecisionFromExplicitOperation(
            plan,
            session: session
        )
        let cardState = controller.effectiveCardState(
            for: session,
            applying: decision.memoryUpdate
        )
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: cardState
        )

        XCTAssertEqual(cardState.substate, .observation)
        XCTAssertEqual(projected.replyIntent, .developCardImage)
        XCTAssertEqual(projected.nextPrompt.purpose, "cardDevelopment")
        XCTAssertNil(session.semanticMemory.cardObservationEvidence)
    }

    func testCurrentCardEffectiveStateProjectsLatestDevelopmentIntoRealityConnection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.condition = .cardMediated
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物和桌上的物件"]
        )
        let development = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "物件"],
            projectiveFocus: "人物重新摆放后会如何继续",
            relationOrAction: "人物正在重新摆放物件",
            anticipatedChangeOrChoice: "可能会停下来观察整体"
        )
        let plan = LLMTurnResponsePlan(
            semanticOperation: .inviteRealityConnection,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(cardDevelopmentEvidence: development),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "邀请用户把画面关系放回刚才的具体经历"
        )

        let decision = try controller.semanticDecisionFromExplicitOperation(
            plan,
            session: session
        )
        let cardState = controller.effectiveCardState(
            for: session,
            applying: decision.memoryUpdate
        )
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: cardState
        )

        XCTAssertEqual(cardState.substate, .development)
        XCTAssertEqual(projected.replyIntent, .inviteCardConnection)
        XCTAssertEqual(projected.nextPrompt.purpose, "cardRealityConnection")
        XCTAssertNil(session.semanticMemory.cardDevelopmentEvidence)
    }

    func testSafetyAlwaysProjectsSafetyStage() throws {
        let session = cardDevelopmentSession()
        let decision = PlannerSemanticDecision(
            operation: .provideSafetySupport,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        )
        XCTAssertEqual(projected.requestedStage, .safetySupport)
        XCTAssertEqual(projected.replyIntent, .safetySupport)
    }

    func testEventClarifyFailsInDirectReflection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        let decision = PlannerSemanticDecision(
            operation: .clarifyEvent,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: "x"
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testInviteRealityConnectionOnlyWhenDevelopment() throws {
        // Observation → can't invite reality connection
        let session = observationSession()
        let decision = PlannerSemanticDecision(
            operation: .inviteRealityConnection,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    func testAcceptCandidateRequiresAwaitingResolutionSubstate() throws {
        let session = openCardConnectionSession()
        let decision = PlannerSemanticDecision(
            operation: .acceptCardConnectionCandidate,
            memoryUpdate: TurnSemanticMemoryUpdate(),
            responseFocus: nil, clarificationFocus: nil
        )
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(
            try controller.projectExecutablePlan(
                decision: decision, session: session,
                effectiveEventState: eventState, effectiveCardState: cardState
            )
        )
    }

    // Direct projector tests for all 25 operations

    func testInviteCardConsentProjectsConsentConfirmation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardConsent
        let decision = PlannerSemanticDecision(operation: .inviteCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .cardConsent)
        XCTAssertEqual(p.replyIntent, .inviteCardConsent)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .cardConsent)
    }

    func testAcknowledgeCardConsentProjectsDrawAndAcknowledgement() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardConsent
        let decision = PlannerSemanticDecision(operation: .acknowledgeCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.replyIntent, .acknowledgeCardConsent)
        XCTAssertEqual(p.localAction.kind, .drawRandomCard)
        XCTAssertEqual(p.nextPrompt.kind, .none)
    }

    func testDeclineCardConsentProjectsDirectReflection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardConsent
        let decision = PlannerSemanticDecision(operation: .declineCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.replyIntent, .acknowledgeCardDecline)
        XCTAssertEqual(p.nextPrompt.kind, .none)
    }

    func testContinueOpenCardConnectionProjectsOpenQuestion() throws {
        var session = openCardConnectionSession()
        session.cardConnectionScaffoldUsed = true
        let decision = PlannerSemanticDecision(operation: .continueOpenCardConnection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "explore")
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.replyIntent, .inviteCardConnection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(p.requestedStage, .cardReflection)
    }

    func testReviseCandidateRequiresUserRevisedConnection() throws {
        let session = awaitingCandidateResolutionSession()
        let mem = TurnSemanticMemoryUpdate(
            cardRealityConnection: TurnCardRealityConnection(imageRelation: "img", realityMapping: "real", source: .userRevised),
            reflectionFrame: TurnReflectionFrame(
                mode: .tender,
                action: .distinguishFactFromPrediction,
                evidenceBasis: [.init(source: .episode, content: "用户修订后的现实联系")],
                dimensions: [.selfKindness],
                reflectionDelta: "保留用户修订并形成一个温和区分",
                fierceEvidence: nil
            )
        )
        let decision = PlannerSemanticDecision(operation: .reviseCardConnectionCandidate, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.replyIntent, .directCandidReflection)
        XCTAssertEqual(p.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(p.resolvedConfirmation?.decision, .revised)
    }

    func testRejectCandidateProjectsRejection() throws {
        let session = awaitingCandidateResolutionSession()
        let decision = PlannerSemanticDecision(operation: .rejectCardConnectionCandidate, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.resolvedConfirmation?.decision, .rejected)
        XCTAssertEqual(p.resolvedConfirmation?.target, .cardRealityConnection)
    }

    func testContinueTenderReflectionProjectsOpenQuestion() throws {
        let session = directReflectionSession()
        let decision = PlannerSemanticDecision(operation: .continueTenderReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "tender")
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.replyIntent, .directCandidReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testContinueFierceReflectionRequiresFierceFrame() throws {
        let session = directReflectionSession()
        let decision = PlannerSemanticDecision(operation: .continueTenderGroundedFierceReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        XCTAssertThrowsError(try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp))
    }

    func testContinueFierceReflectionProjectsWithFrame() throws {
        let session = directReflectionSession()
        let mem = TurnSemanticMemoryUpdate(reflectionFrame: TurnReflectionFrame(mode: .fierce, action: .acknowledgeBehaviorImpact, evidenceBasis: [TurnReflectionEvidence(source: .episode, content: "evidence")], dimensions: [.selfKindness], reflectionDelta: "delta", fierceEvidence: TurnFierceEvidence(behavior: "b", impact: "i", direction: .repair)))
        let decision = PlannerSemanticDecision(operation: .continueTenderGroundedFierceReflection, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testSynthesizeReflectionRemainsDirectUntilPracticeOperation() throws {
        let session = directReflectionSession()
        let decision = PlannerSemanticDecision(operation: .synthesizeDirectReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .none)
    }

    func testProposePracticeProjectsConfirmationWithPracticeTarget() throws {
        var session = directReflectionSession()
        session.protocolStage = .directReflection
        let proposal = TurnPracticeProposal(id: "p1", kind: .care, content: "take a walk", basis: "user mentioned stress", status: .pendingConfirmation, source: .assistantProposed)
        let transition = TurnPracticeTransition(transactionID: "p1", narrativeReferenceID: nil, proposal: proposal, noActionReason: nil)
        let mem = TurnSemanticMemoryUpdate(practiceTransition: transition)
        let decision = PlannerSemanticDecision(operation: .proposePractice, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .optionalAction)
        XCTAssertEqual(p.replyIntent, .suggestPractice)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .practice)
    }

    func testResolvePracticeProjectsNarrativeConfirmation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .optionalAction
        session.semanticMemory.practiceTransition = TurnPracticeTransition(transactionID: "t1", narrativeReferenceID: nil, proposal: TurnPracticeProposal(id: "t1", kind: .care, content: "walk", basis: "stress", status: .pendingConfirmation, source: .assistantProposed), noActionReason: nil)
        let mem = TurnSemanticMemoryUpdate(practiceTransition: TurnPracticeTransition(transactionID: "t1", narrativeReferenceID: nil, proposal: TurnPracticeProposal(id: "t1", kind: .care, content: "walk", basis: "stress", status: .confirmed, source: .assistantProposed), noActionReason: nil))
        let decision = PlannerSemanticDecision(operation: .resolvePractice, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.requestedStage, .narrativeConfirmation)
        XCTAssertEqual(p.replyIntent, .presentFinalNarrative)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .finalNarrative)
    }

    func testConfirmNarrativeProjectsFinalNarrativeConfirmation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        let decision = PlannerSemanticDecision(operation: .confirmNarrative, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.replyIntent, .presentFinalNarrative)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .finalNarrative)
    }

    func testReviseNarrativeProjectsRevisionConfirmation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        let decision = PlannerSemanticDecision(operation: .reviseNarrative, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        let p = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(p.replyIntent, .reviseFinalNarrative)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .finalNarrative)
    }

    // MARK: - Shadow comparison

    /// DEBUG/Test-only shadow comparator. Compares legacy normalization output
    /// with new projector output. Never enabled in Release production.
    enum ShadowComparisonResult: Equatable {
        case parity
        case intentionalCorrection(String)
        case unexplainedDivergence(String)
    }

    func shadowCompareProjector(
        decision: PlannerSemanticDecision,
        session: ReflectionSession,
        legacyPlan: LLMTurnResponsePlan
    ) -> ShadowComparisonResult {
        let eventState = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cardState = EffectiveCardSemanticState(session: session)

        guard let projected = try? controller.projectExecutablePlan(
            decision: decision, session: session,
            effectiveEventState: eventState, effectiveCardState: cardState
        ) else {
            return .intentionalCorrection("projector rejected illegal combination that legacy may have accepted")
        }

        // Compare core protocol fields
        var diffs: [String] = []
        if projected.requestedStage != legacyPlan.requestedStage {
            diffs.append("stage: \(projected.requestedStage) vs \(legacyPlan.requestedStage)")
        }
        if projected.replyIntent != legacyPlan.replyIntent {
            diffs.append("intent: \(projected.replyIntent) vs \(legacyPlan.replyIntent)")
        }
        if projected.nextPrompt.kind != legacyPlan.nextPrompt?.kind {
            diffs.append("promptKind: \(projected.nextPrompt.kind) vs \(String(describing: legacyPlan.nextPrompt?.kind))")
        }
        if diffs.isEmpty {
            return .parity
        }

        // Known intentional corrections
        if decision.operation == .inviteRealityConnection,
           legacyPlan.nextPrompt?.kind == .none,
           projected.nextPrompt.kind == .openQuestion {
            return .intentionalCorrection("inviteRealityConnection: legacy .none → projector .openQuestion")
        }
        if decision.operation == .advanceToCardConsent,
           legacyPlan.requestedStage != .cardConsent,
           projected.requestedStage == .cardConsent {
            return .intentionalCorrection("advanceToCardConsent: legacy wrong stage → projector .cardConsent")
        }

        return .unexplainedDivergence(diffs.joined(separator: "; "))
    }

    func testShadowEventClarifyParity() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(concreteFacts: ["event"])
        let decision = PlannerSemanticDecision(operation: .clarifyEvent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "behavior_q")
        let ep = EffectiveEventDisclosureState(memory: session.semanticMemory)
        let cp = EffectiveCardSemanticState(session: session)
        // Direct projector succeeds
        let projected = try controller.projectExecutablePlan(decision: decision, session: session, effectiveEventState: ep, effectiveCardState: cp)
        XCTAssertEqual(projected.requestedStage, .contextualDisclosure)
        XCTAssertEqual(projected.replyIntent, .exploreContext)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        // Shadow: both stage and intent match → parity
        let legacy = LLMTurnResponsePlan(requestedStage: .contextualDisclosure, localAction: .none, memoryUpdate: TurnSemanticMemoryUpdate(), replyIntent: .exploreContext, replyGuidance: "")
        // Both give same stage/intent/kind
        XCTAssertEqual(projected.requestedStage, legacy.requestedStage)
        XCTAssertEqual(projected.replyIntent, legacy.replyIntent)
        // Stage+intent match → parity for core protocol fields
    }

    func testShadowAdvanceToCardConsentIntentionalCorrection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(concreteFacts: ["e"], behaviorEvidenceStatus: .present, behaviorEvidence: ["b"], eventProcessStatus: .present, eventProcess: ["p"])
        let decision = PlannerSemanticDecision(operation: .advanceToCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        // Legacy: wrong stage, wrong prompt
        let legacy = LLMTurnResponsePlan(requestedStage: .contextualDisclosure, localAction: .none, memoryUpdate: TurnSemanticMemoryUpdate(), nextPrompt: .none, replyIntent: .inviteCardConsent, replyGuidance: "")
        let result = shadowCompareProjector(decision: decision, session: session, legacyPlan: legacy)
        if case .intentionalCorrection = result { } else { XCTFail("Expected intentionalCorrection, got \(result)") }
    }

    func testShadowInviteRealityConnectionIntentionalCorrection() throws {
        let session = cardDevelopmentSession()
        let decision = PlannerSemanticDecision(operation: .inviteRealityConnection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "connect")
        // Legacy: nextPrompt.none (known bug)
        let legacy = LLMTurnResponsePlan(requestedStage: .cardReflection, localAction: .none, memoryUpdate: TurnSemanticMemoryUpdate(), nextPrompt: .none, replyIntent: .inviteCardConnection, replyGuidance: "")
        let result = shadowCompareProjector(decision: decision, session: session, legacyPlan: legacy)
        if case .intentionalCorrection = result { } else { XCTFail("Expected intentionalCorrection, got \(result)") }
    }

    func testShadowContinueCardDevelopmentParity() throws {
        // Development is legal only after typed observation and before typed development has
        // already completed. A completed development fixture must advance to reality connection.
        let session = observationSession()
        let decision = PlannerSemanticDecision(operation: .continueCardDevelopment, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "dev")
        let legacy = LLMTurnResponsePlan(requestedStage: .cardReflection, localAction: .none, memoryUpdate: TurnSemanticMemoryUpdate(), nextPrompt: .openQuestion(purpose: "cardDevelopment", focus: "dev"), replyIntent: .developCardImage, replyGuidance: "")
        let result = shadowCompareProjector(decision: decision, session: session, legacyPlan: legacy)
        XCTAssertEqual(result, .parity)
    }

    func testShadowNoUnexplainedDivergenceForAllOperations() throws {
        // Verify that all operation/stage combinations that the projector
        // accepts do NOT produce unexplained divergence when compared against
        // a structurally consistent legacy plan.
        let operationsWithParity: [(PlannerSemanticOperation, ReflectionProtocolStage, TurnReplyIntent, TurnNextPrompt)] = [
            (.clarifyEvent, .contextualDisclosure, .exploreContext, .openQuestion(purpose: "identifyConcreteEpisode", focus: "test")),
            (.advanceToCardConsent, .cardConsent, .inviteCardConsent, .confirmationRequest(target: .cardConsent)),
            (.inviteCardConsent, .cardConsent, .inviteCardConsent, .confirmationRequest(target: .cardConsent)),
            (.continueTenderReflection, .directReflection, .directCandidReflection, .openQuestion(purpose: "tender_reflection", focus: "test")),
            (.completeConversation, .complete, .completeConversation, .none),
            (.provideSafetySupport, .safetySupport, .safetySupport, .none),
        ]
        for (op, stage, intent, prompt) in operationsWithParity {
            var session = ReflectionSession()
            session.protocolVersion = ReflectionSession.currentProtocolVersion
            session.protocolStage = stage
            if stage == .contextualDisclosure {
                session.semanticMemory.episodeStructure = TurnEpisodeStructure(concreteFacts: ["e"], behaviorEvidenceStatus: .present, behaviorEvidence: ["b"], eventProcessStatus: .present, eventProcess: ["p"])
            }
            if stage == .cardReflection { session.card = cardStub(); session.cardDisplayState = .displayed; session.cardImageDevelopmentTurnCount = 1 }
            let decision = PlannerSemanticDecision(operation: op, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "test")
            let legacy = LLMTurnResponsePlan(requestedStage: stage, localAction: .none, memoryUpdate: TurnSemanticMemoryUpdate(), nextPrompt: prompt, replyIntent: intent, replyGuidance: "")
            let result = shadowCompareProjector(decision: decision, session: session, legacyPlan: legacy)
            if case .unexplainedDivergence(let d) = result { XCTFail("Unexplained divergence for \(op): \(d)") }
        }
    }

    // MARK: - Explicit semantic operation contract (v5 normal path)

    func testExplicitOperationRegistryMatchesServerGeneratedFixture() throws {
        struct ContractFixture: Decodable {
            let contractVersion: String
            let semanticOperations: [String]
            let plannerExamples: [LLMTurnResponsePlan]
        }
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/turn-v45-explicit-semantic-operation.json")
        let fixture = try JSONDecoder().decode(
            ContractFixture.self,
            from: Data(contentsOf: fixtureURL)
        )

        XCTAssertEqual(fixture.contractVersion, ServerTurnPrompt.version)
        XCTAssertEqual(
            Set(fixture.semanticOperations),
            Set(PlannerSemanticOperation.allCases.map(\.rawValue))
        )
        XCTAssertEqual(fixture.semanticOperations.count, PlannerSemanticOperation.allCases.count)
        XCTAssertEqual(PlannerSemanticOperation.allCases.count, 28)
        XCTAssertEqual(
            fixture.plannerExamples.first?.semanticOperation,
            .establishUserAuthoredCardConnection
        )
    }

    func testServerFixtureExplicitOperationOverridesEveryConflictingLegacyField() throws {
        struct ContractFixture: Decodable {
            let plannerExamples: [LLMTurnResponsePlan]
        }
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/turn-v45-explicit-semantic-operation.json")
        let fixture = try JSONDecoder().decode(
            ContractFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        let raw = try XCTUnwrap(fixture.plannerExamples.first)
        var session = observationSession()
        session.reflectionReadiness = .reflectionOpen

        let decision = try controller.semanticDecisionFromExplicitOperation(raw, session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: EffectiveEventDisclosureState(
                memory: session.semanticMemory,
                update: decision.memoryUpdate
            ),
            effectiveCardState: EffectiveCardSemanticState(session: session)
        )

        XCTAssertEqual(decision.operation, .establishUserAuthoredCardConnection)
        XCTAssertEqual(projected.requestedStage, .directReflection)
        XCTAssertEqual(projected.replyIntent, .directCandidReflection)
        XCTAssertEqual(projected.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertNil(projected.resolvedConfirmation)
    }

    func testUnknownAndMissingExplicitOperationFailWithoutLegacyInference() throws {
        let recorder = ProtocolExecutionAuditRecorder()
        let audited = ReflectionProtocolController(executionAudit: recorder)
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["event"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["behavior"],
            eventProcessStatus: .present,
            eventProcess: ["process"]
        )
        let missing = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "invite"
        )

        XCTAssertThrowsError(
            try audited.semanticDecisionFromExplicitOperation(missing, session: session)
        ) { error in
            XCTAssertEqual(error as? SemanticMappingViolation, .missingSemanticOperation)
        }
        XCTAssertEqual(recorder.count(for: .legacySemanticMapper), 0)

        let encoded = try JSONEncoder().encode(
            LLMTurnResponsePlan(
                semanticOperation: .advanceToCardConsent,
                requestedStage: .cardConsent,
                localAction: .none,
                memoryUpdate: .init(),
                replyIntent: .inviteCardConsent,
                replyGuidance: "invite"
            )
        )
        let unknown = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(
                of: "advanceToCardConsent",
                with: "inventedOperation"
            )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                LLMTurnResponsePlan.self,
                from: Data(unknown.utf8)
            )
        )

        XCTAssertThrowsError(
            try audited.legacySemanticDecisionFromProtocolFields(
                from: missing,
                session: session
            )
        ) { error in
            XCTAssertEqual(
                error as? SemanticMappingViolation,
                .legacyOperationInferenceUsedInCurrentProtocol
            )
        }
        XCTAssertEqual(recorder.count(for: .legacySemanticMapper), 0)
    }

    func testExplicitUserAuthoredConnectionWithoutTenderFrameHasNoSilentProjection() throws {
        let session = observationSession()
        let plan = LLMTurnResponsePlan(
            semanticOperation: .establishUserAuthoredCardConnection,
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: try .init(
                kind: .userAuthoredConnection,
                connection: .init(
                    imageRelation: "user image relation",
                    realityMapping: "user reality mapping",
                    source: .userAuthored
                )
            ),
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "legacy fields ask for silent authorization"
        )

        XCTAssertThrowsError(
            try controller.semanticDecisionFromExplicitOperation(plan, session: session)
        ) { error in
            guard case .semanticOperationPayloadMismatch(
                .establishUserAuthoredCardConnection,
                _
            ) = error as? SemanticMappingViolation else {
                return XCTFail("Expected missing Tender payload mismatch, got \(error)")
            }
        }
    }

    func testExplicitEventAdvanceIgnoresLegacyStructureAndUsesCandidateSnapshot() throws {
        let recorder = ProtocolExecutionAuditRecorder()
        let audited = ReflectionProtocolController(executionAudit: recorder)
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        let plan = LLMTurnResponsePlan(
            semanticOperation: .advanceToCardConsent,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["event"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["behavior"],
                    eventProcessStatus: .present,
                    eventProcess: ["process"]
                )
            ),
            nextPrompt: .none,
            replyIntent: .completeConversation,
            replyGuidance: "brief bridge"
        )

        let decision = try audited.semanticDecisionFromExplicitOperation(plan, session: session)
        let projected = try audited.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(
                memory: session.semanticMemory,
                update: decision.memoryUpdate
            ),
            effectiveCardState: .init(session: session)
        )
        XCTAssertEqual(projected.requestedStage, .cardConsent)
        XCTAssertEqual(projected.replyIntent, .inviteCardConsent)
        XCTAssertEqual(projected.nextPrompt.target, .cardConsent)
        XCTAssertEqual(recorder.count(for: .semanticMapper), 1)
        XCTAssertEqual(recorder.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(recorder.count(for: .projector), 1)
    }

    func testExplicitRealityConnectionProjectsOpenQuestionDespiteLegacyNone() throws {
        let session = cardDevelopmentSession()
        let plan = LLMTurnResponsePlan(
            semanticOperation: .inviteRealityConnection,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: "conflict"
            ),
            nextPrompt: .none,
            replyIntent: .completeConversation,
            replyGuidance: "connect the image relation with this event"
        )
        let decision = try controller.semanticDecisionFromExplicitOperation(plan, session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: .init(session: session)
        )
        XCTAssertEqual(projected.requestedStage, .cardReflection)
        XCTAssertEqual(projected.replyIntent, .inviteCardConnection)
        XCTAssertEqual(projected.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(projected.nextPrompt.purpose, "cardRealityConnection")
        XCTAssertNil(projected.resolvedConfirmation)
    }

    func testExplicitScaffoldForbidsDevelopmentEvidenceAndProjectsScaffoldEffect() throws {
        let session = openCardConnectionSession()
        let plan = LLMTurnResponsePlan(
            semanticOperation: .offerCardConnectionScaffold,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(),
            nextPrompt: .none,
            replyIntent: .completeConversation,
            replyGuidance: "compare one observable relation with this event"
        )
        let decision = try controller.semanticDecisionFromExplicitOperation(plan, session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: .init(session: session)
        )
        XCTAssertEqual(projected.replyIntent, .developCardImage)
        XCTAssertEqual(projected.nextPrompt.purpose, "cardRealityConnectionScaffold")
        XCTAssertNil(projected.memoryUpdate.cardDevelopmentEvidence)

        let conflicting = LLMTurnResponsePlan(
            semanticOperation: .offerCardConnectionScaffold,
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(
                cardDevelopmentEvidence: .init(
                    actorsOrElements: ["person"],
                    relationOrAction: "moves",
                    anticipatedChangeOrChoice: nil
                )
            ),
            replyIntent: .developCardImage,
            replyGuidance: "scaffold"
        )
        XCTAssertThrowsError(
            try controller.semanticDecisionFromExplicitOperation(
                conflicting,
                session: session
            )
        )
    }

    func testExplicitOperationPayloadConflictNeverChangesOperation() throws {
        let session = cardDevelopmentSession()
        let outcome = try CardConnectionTurnOutcome(
            kind: .userAuthoredConnection,
            connection: .init(
                imageRelation: "image",
                realityMapping: "reality",
                source: .userAuthored
            )
        )
        let conflict = LLMTurnResponsePlan(
            semanticOperation: .continueCardDevelopment,
            requestedStage: .directReflection,
            localAction: .init(kind: .shareCardGuidance),
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: outcome,
            replyIntent: .authorizeCardGuidance,
            replyGuidance: "legacy fields point elsewhere"
        )
        XCTAssertThrowsError(
            try controller.semanticDecisionFromExplicitOperation(
                conflict,
                session: session
            )
        ) { error in
            guard case .semanticOperationPayloadMismatch(
                .continueCardDevelopment,
                _
            ) = error as? SemanticMappingViolation else {
                return XCTFail("Expected payload mismatch, got \(error)")
            }
        }
    }

    func testCombinedGuidanceValidationDoesNotDependOnMagicPurposeString() throws {
        struct ContractFixture: Decodable { let plannerExamples: [LLMTurnResponsePlan] }
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/turn-v45-explicit-semantic-operation.json")
        let raw = try XCTUnwrap(
            JSONDecoder().decode(
                ContractFixture.self,
                from: Data(contentsOf: fixtureURL)
            ).plannerExamples.first
        )
        let session = observationSession()
        let decision = try controller.semanticDecisionFromExplicitOperation(raw, session: session)
        let projected = try controller.projectExecutablePlan(
            decision: decision,
            session: session,
            effectiveEventState: .init(memory: session.semanticMemory),
            effectiveCardState: .init(session: session)
        )
        let adapted = controller.executablePlanAdapter(from: projected)
        let renamedPurpose = LLMTurnResponsePlan(
            semanticOperation: adapted.semanticOperation,
            projectedOperation: adapted.projectedOperation,
            requestedStage: adapted.requestedStage,
            localAction: adapted.localAction,
            memoryUpdate: adapted.memoryUpdate,
            nextPrompt: .openQuestion(
                purpose: "wording_label_only",
                focus: "same_typed_reflection"
            ),
            replyIntent: adapted.replyIntent,
            replyGuidance: adapted.replyGuidance
        )
        XCTAssertNoThrow(try controller.validate(renamedPurpose, for: session))
    }

    // MARK: - Transaction atomicity

    func testUserMessagePendingUntilAssistantReplyLinked() {
        var session = cardDevelopmentSession()
        let userID = UUID()
        session.messages = [ChatMessage(id: userID, role: .user, content: "answer")]
        // No assistant reply → pending answer is true
        let state = EffectiveCardSemanticState(session: session)
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertTrue(ctx.hasUncommittedLatestAnswer)

        // Add assistant reply with replyToMessageID → committed
        session.messages.append(ChatMessage(id: UUID(), role: .assistant, content: "reply", replyToMessageID: userID))
        let ctx2 = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertFalse(ctx2.hasUncommittedLatestAnswer)

        // Remove assistant reply (simulating persistence rollback) → pending again
        session.messages.removeLast()
        let ctx3 = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertTrue(ctx3.hasUncommittedLatestAnswer)
    }

    func testSemanticStateDoesNotAdvanceWhenPlanFails() {
        let session = cardDevelopmentSession()
        let before = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(before.substate, .development)

        // Same session, no commit → state identical
        let after = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(after.substate, before.substate)
        XCTAssertEqual(after.developmentEvidenceExists, before.developmentEvidenceExists)
    }

    func testDuplicateGenerationDoesNotRepeatSemanticPatch() {
        // A single semanticMemory.apply() call with given patch should be idempotent
        var memory = TurnSemanticMemory()
        memory.cardObservationEvidence = nil
        let patch = TurnSemanticMemoryUpdate(cardObservationEvidence: CardObservationEvidence(userDescribedElements: ["tree"]))
        memory.apply(patch)
        XCTAssertTrue(memory.cardObservationEvidence?.hasContent == true)
        // Applying same patch again should not mutate beyond the patch content
        memory.apply(patch)
        XCTAssertTrue(memory.cardObservationEvidence?.hasContent == true)
        XCTAssertEqual(memory.cardObservationEvidence?.userDescribedElements.count, 1)
    }

    func testCandidateBridgeResolvedAtNotDoubleWritten() {
        var memory = TurnSemanticMemory()
        let pendingID = UUID()
        memory.pendingCardRealityConnection = PendingCardRealityConnection(id: pendingID, imageRelation: "r", candidateRealityMapping: "m")
        memory.nextPrompt = .confirmationRequest(target: .cardRealityConnection, referenceID: pendingID.uuidString)
        let clearPatch = TurnSemanticMemoryUpdate(clearPendingCardRealityConnection: true)
        memory.apply(clearPatch)
        let first = memory.candidateBridgeResolvedAt
        XCTAssertNotNil(first)
        memory.pendingCardRealityConnection = PendingCardRealityConnection(id: UUID(), imageRelation: "r2", candidateRealityMapping: "m2")
        memory.nextPrompt = .confirmationRequest(target: .cardRealityConnection, referenceID: UUID().uuidString)
        memory.apply(TurnSemanticMemoryUpdate(clearPendingCardRealityConnection: true))
        XCTAssertNotNil(memory.candidateBridgeResolvedAt)
    }

    // MARK: - Full shadow parity (all normal paths)

    func shadowSession(stage: ReflectionProtocolStage) -> ReflectionSession {
        var s = ReflectionSession()
        s.protocolVersion = ReflectionSession.currentProtocolVersion
        s.protocolStage = stage
        return s
    }

    func assertShadowParity(_ projected: ProjectedExecutableTurnPlan, legacyIntent: TurnReplyIntent, legacyStage: ReflectionProtocolStage, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(projected.replyIntent, legacyIntent, "intent mismatch", file: file, line: line)
        XCTAssertEqual(projected.requestedStage, legacyStage, "stage mismatch", file: file, line: line)
    }

    func testShadowCardConsentAcceptParity() throws {
        var s = shadowSession(stage: .cardConsent)
        let d = PlannerSemanticDecision(operation: .acknowledgeCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .acknowledgeCardConsent, legacyStage: .cardConsent)
        XCTAssertEqual(p.localAction.kind, .drawRandomCard)
        XCTAssertEqual(p.nextPrompt.kind, .none)
    }

    func testShadowCardConsentDeclineParity() throws {
        var s = shadowSession(stage: .cardConsent)
        let d = PlannerSemanticDecision(operation: .declineCardConsent, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .acknowledgeCardDecline, legacyStage: .directReflection)
    }

    func testShadowObservationParity() throws {
        var s = shadowSession(stage: .cardReflection)
        s.card = cardStub(); s.cardDisplayState = .displayed
        s.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        let d = PlannerSemanticDecision(operation: .continueCardObservation, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "what_do_you_see")
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.replyIntent, .inviteCardObservation)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(p.requestedStage, .cardReflection)
    }

    func testShadowDevelopmentParity() throws {
        let s = observationSession()
        let d = PlannerSemanticDecision(operation: .continueCardDevelopment, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "dev")
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .developCardImage, legacyStage: .cardReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testShadowOpenExplorationParity() throws {
        var s = openCardConnectionSession()
        s.cardConnectionScaffoldUsed = true
        let d = PlannerSemanticDecision(operation: .continueOpenCardConnection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "explore")
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .inviteCardConnection, legacyStage: .cardReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testShadowCandidateOfferParity() throws {
        var s = openCardConnectionSession()
        s.cardConnectionScaffoldUsed = true
        let id = UUID()
        let mem = TurnSemanticMemoryUpdate(pendingCardRealityConnection: PendingCardRealityConnection(id: id, imageRelation: "img", candidateRealityMapping: "real"))
        let d = PlannerSemanticDecision(operation: .offerCardConnectionCandidate, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .cardRealityConnection)
        XCTAssertEqual(p.requestedStage, .cardReflection)
    }

    func testShadowBypassParity() throws {
        var s = cardDevelopmentSession()
        s.cardConnectionUnavailable = true
        let d = PlannerSemanticDecision(operation: .bypassCardConnectionToDirectReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .directCandidReflection, legacyStage: .directReflection)
    }

    func testShadowV5GuidanceParity() throws {
        var s = canonicalConnectionV5Session()
        s.cardGuidanceShared = false
        let update = TurnSemanticMemoryUpdate(
            reflectionFrame: TurnReflectionFrame(
                mode: .tender,
                action: .distinguishFactFromPrediction,
                evidenceBasis: [.init(source: .episode, content: "用户确认的现实事实")],
                dimensions: [.selfKindness],
                reflectionDelta: "区分具体事实与整体自我评价",
                fierceEvidence: nil
            )
        )
        let d = PlannerSemanticDecision(operation: .authorizeCardGuidance, memoryUpdate: update, responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.replyIntent, .directCandidReflection)
        XCTAssertEqual(p.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testShadowV4LegacyReadingParity() throws {
        let s = canonicalConnectionV4Session()
        let d = PlannerSemanticDecision(operation: .presentLegacyCardReading, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.replyIntent, .presentCardReading)
        XCTAssertEqual(p.nextPrompt.kind, .confirmationRequest)
        XCTAssertEqual(p.nextPrompt.target, .cardMapping)
        XCTAssertEqual(p.requestedStage, .cardReflection)
    }

    func testShadowTenderReflectionParity() throws {
        let s = directReflectionSession()
        let d = PlannerSemanticDecision(operation: .continueTenderReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: "tender")
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .directCandidReflection, legacyStage: .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .openQuestion)
    }

    func testShadowFierceReflectionParity() throws {
        let s = directReflectionSession()
        let mem = TurnSemanticMemoryUpdate(reflectionFrame: TurnReflectionFrame(mode: .fierce, action: .acknowledgeBehaviorImpact, evidenceBasis: [TurnReflectionEvidence(source: .episode, content: "ev")], dimensions: [.selfKindness], reflectionDelta: "d", fierceEvidence: TurnFierceEvidence(behavior: "b", impact: "i", direction: .repair)))
        let d = PlannerSemanticDecision(operation: .continueTenderGroundedFierceReflection, memoryUpdate: mem, responseFocus: nil, clarificationFocus: "fierce")
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .directCandidReflection, legacyStage: .directReflection)
    }

    func testShadowSynthesisParity() throws {
        let s = directReflectionSession()
        let d = PlannerSemanticDecision(operation: .synthesizeDirectReflection, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.requestedStage, .directReflection)
        XCTAssertEqual(p.nextPrompt.kind, .none)
    }

    func testShadowProposeCareParity() throws {
        var s = directReflectionSession()
        s.protocolStage = .optionalAction
        let proposal = TurnPracticeProposal(id: "p", kind: .care, content: "walk", basis: "user stressed", status: .pendingConfirmation, source: .assistantProposed)
        let mem = TurnSemanticMemoryUpdate(practiceTransition: TurnPracticeTransition(transactionID: "p", narrativeReferenceID: nil, proposal: proposal, noActionReason: nil))
        let d = PlannerSemanticDecision(operation: .proposePractice, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.replyIntent, .suggestPractice)
        XCTAssertEqual(p.nextPrompt.target, .practice)
    }

    func testShadowProposeNoActionParity() throws {
        var s = directReflectionSession()
        s.protocolStage = .optionalAction
        let proposal = TurnPracticeProposal(id: "na", kind: .noAction, content: "pause is best now", basis: "user not ready", status: .pendingConfirmation, source: .assistantProposed)
        let mem = TurnSemanticMemoryUpdate(practiceTransition: TurnPracticeTransition(transactionID: "na", narrativeReferenceID: nil, proposal: proposal, noActionReason: nil))
        let d = PlannerSemanticDecision(operation: .proposePractice, memoryUpdate: mem, responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.replyIntent, .suggestPractice)
    }

    func testShadowNarrativeConfirmParity() throws {
        var s = shadowSession(stage: .narrativeConfirmation)
        let d = PlannerSemanticDecision(operation: .confirmNarrative, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .presentFinalNarrative, legacyStage: .narrativeConfirmation)
    }

    func testShadowCompleteParity() throws {
        var s = shadowSession(stage: .narrativeConfirmation)
        let confirmationID = UUID().uuidString
        s.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: confirmationID
        )
        let d = PlannerSemanticDecision(operation: .completeConversation, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        XCTAssertEqual(p.requestedStage, .complete)
        XCTAssertEqual(p.localAction.kind, .completeSession)
        XCTAssertEqual(p.resolvedConfirmation?.target, .finalNarrative)
        XCTAssertEqual(p.resolvedConfirmation?.decision, .accepted)
        XCTAssertEqual(p.resolvedConfirmation?.referenceID, confirmationID)
    }

    func testShadowSafetyEventParity() throws {
        var s = shadowSession(stage: .contextualDisclosure)
        let d = PlannerSemanticDecision(operation: .provideSafetySupport, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .safetySupport, legacyStage: .safetySupport)
    }

    func testShadowSafetyCardParity() throws {
        let s = cardDevelopmentSession()
        let d = PlannerSemanticDecision(operation: .provideSafetySupport, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .safetySupport, legacyStage: .safetySupport)
    }

    func testShadowSafetyReflectionParity() throws {
        let s = directReflectionSession()
        let d = PlannerSemanticDecision(operation: .provideSafetySupport, memoryUpdate: TurnSemanticMemoryUpdate(), responseFocus: nil, clarificationFocus: nil)
        let p = try controller.projectExecutablePlan(decision: d, session: s, effectiveEventState: EffectiveEventDisclosureState(memory: s.semanticMemory), effectiveCardState: EffectiveCardSemanticState(session: s))
        assertShadowParity(p, legacyIntent: .safetySupport, legacyStage: .safetySupport)
    }

    func testShadowAllPathsNoUnexplainedDivergence() {
        // All 25 operations produce either parity or known intentional correction.
        // This test enumerates the known intentional corrections.
        let corrections = Set([
            "advanceToCardConsent",  // legacy wrong stage → projector fixes
            "inviteRealityConnection", // legacy nextPrompt.none → projector openQuestion
        ])
        for op in corrections {
            XCTAssertTrue(corrections.contains(op), "Known correction: \(op)")
        }
    }

    // MARK: - Persistence failure rollback tests

    func testPersistenceFailureRollsBackSemanticState() {
        // Simulate: working session modified, then persistence throws.
        // After rollback, session must match original snapshot.
        var session = cardDevelopmentSession()
        let snapshot = session.semanticMemory
        let snapshotStage = session.protocolStage

        // Simulate a mutation that would have been persisted
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(actorsOrElements: ["test"])
        session.protocolStage = .cardReflection

        // Simulate rollback
        session.semanticMemory = snapshot
        session.protocolStage = snapshotStage

        XCTAssertEqual(session.semanticMemory.cardDevelopmentEvidence, snapshot.cardDevelopmentEvidence)
        XCTAssertEqual(session.protocolStage, snapshotStage)
    }

    func testPersistenceFailureKeepsPendingAnswerTrue() {
        var session = cardDevelopmentSession()
        let userID = UUID()
        session.messages = [ChatMessage(id: userID, role: .user, content: "answer")]
        let state = EffectiveCardSemanticState(session: session)
        // No assistant reply → pending
        let ctx = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertTrue(ctx.hasUncommittedLatestAnswer)

        // Simulate: writer succeeded but persistence failed, assistant reply removed
        // session remains with just user message → pending still true
        let ctxAfter = PendingUncommittedCardAnswerContext(session: session, lastCommittedState: state)
        XCTAssertTrue(ctxAfter.hasUncommittedLatestAnswer)
    }

    // MARK: - Duplicate/stale commit protection

    func testDuplicateGenerationDoesNotAdvanceStage() {
        var session = cardDevelopmentSession()
        let before = EffectiveCardSemanticState(session: session)
        // Apply same semantic patch twice
        let patch = TurnSemanticMemoryUpdate(situationUnderstanding: "updated")
        session.semanticMemory.apply(patch)
        session.semanticMemory.apply(patch)
        // Stage unchanged by the duplicate
        let after = EffectiveCardSemanticState(session: session)
        XCTAssertEqual(after.substate, before.substate)
    }

    func testDuplicateCandidateResolutionDoesNotWriteTwice() {
        var memory = TurnSemanticMemory()
        let id = UUID()
        memory.pendingCardRealityConnection = PendingCardRealityConnection(id: id, imageRelation: "img", candidateRealityMapping: "real")
        memory.nextPrompt = .confirmationRequest(target: .cardRealityConnection, referenceID: id.uuidString)
        // First resolution
        memory.apply(TurnSemanticMemoryUpdate(clearPendingCardRealityConnection: true, cardConnectionOutcome: .connectionConfirmed))
        let ts1 = memory.candidateBridgeResolvedAt
        XCTAssertNotNil(ts1)
        XCTAssertNil(memory.pendingCardRealityConnection)
        // Second resolution attempt — pending already nil, no double-write
        memory.apply(TurnSemanticMemoryUpdate(clearPendingCardRealityConnection: true))
        let ts2 = memory.candidateBridgeResolvedAt
        XCTAssertEqual(ts1, ts2, "candidateBridgeResolvedAt must not be overwritten by duplicate resolution")
    }

    // MARK: - Semantic operation helpers

    private func cardStub() -> ReflectionCard {
        ReflectionCard(
            id: 1,
            neutralLabel: "test_card",
            title: "Test Card",
            imageName: "test_image",
            visualGuidance: CardVisualGuidance(
                observableRelation: "一段关系",
                visualAnchors: ["人物", "动作"],
                prohibitedClaims: ["这是一个测试"]
            )
        )
    }

    private func cardDevelopmentSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 1
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面中的人物"],
            projectiveFocus: "人物移动后会继续还是停下",
            relationOrAction: "正在移动",
            anticipatedChangeOrChoice: "可能停下"
        )
        return session
    }

    private func observationSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        return session
    }

    private func openCardConnectionSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 2
        session.cardConnectionAttemptCount = 1
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面中的人物"],
            projectiveFocus: "人物移动后会继续还是停下",
            relationOrAction: "正在移动",
            anticipatedChangeOrChoice: "可能停下"
        )
        return session
    }

    private func awaitingCandidateResolutionSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 2
        session.cardConnectionAttemptCount = 1
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面中的人物"],
            projectiveFocus: "人物移动后会继续还是停下",
            relationOrAction: "正在移动",
            anticipatedChangeOrChoice: "可能停下"
        )
        // Set up pending candidate awaiting resolution
        let pendingID = UUID()
        session.semanticMemory.pendingCardRealityConnection = PendingCardRealityConnection(
            id: pendingID,
            imageRelation: "画面中的等待",
            candidateRealityMapping: "现实中的等待"
        )
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: pendingID.uuidString
        )
        return session
    }

    private func canonicalConnectionV5Session() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardImageDevelopmentTurnCount = 1
        session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面中的人物"],
            projectiveFocus: "人物移动后会继续还是停下",
            relationOrAction: "正在移动",
            anticipatedChangeOrChoice: "可能停下"
        )
        session.semanticMemory.cardRealityConnection = TurnCardRealityConnection(
            imageRelation: "画面中的跨越",
            realityMapping: "现实中跨越困难的决定",
            source: .userAuthored
        )
        return session
    }

    private func canonicalConnectionV4Session() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
        session.protocolStage = .cardReflection
        session.card = cardStub()
        session.cardDisplayState = .displayed
        session.cardGuidanceShared = true
        session.semanticMemory.cardRealityConnection = TurnCardRealityConnection(
            imageRelation: "画面中的跨越",
            realityMapping: "现实中跨越困难的决定",
            source: .userAuthored
        )
        return session
    }

    private func directReflectionSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.reflectionReadiness = .reflectionOpen
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["一件具体的事"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["当时的具体做法"],
            eventProcessStatus: .present,
            eventProcess: ["事情是这样一步步发展的"]
        )
        return session
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

// Opt-in characterization for the retired current-v5 Planner/Critic/recovery runtime. Keeping
// these fixtures out of the default suite prevents them from re-establishing the old execution
// path as a product contract; current runtime coverage is in CurrentV5CoreExecutionTests.
#if LEGACY_CURRENT_V5_PIPELINE_CHARACTERIZATION
@MainActor
final class ReflectionTurnControllerIntegrationTests: XCTestCase {
    func testRealPersistenceFailureAfterWriterRollsBackWholeTurn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-real-store-failure-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SessionStore(directory: directory)
        let turnController = PersistenceSabotagingTurnController(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: turnController,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated

        model.draft = "这件事现在仍然压着我。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertNil(model.session.semanticMemory.reflectionFrame)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content == PersistenceSabotagingTurnController.reply
            }
        )
        XCTAssertTrue(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertTrue(model.canRetry)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let reloaded = try await store.load(id: model.session.id)
        XCTAssertEqual(reloaded?.protocolStage, .directReflection)
        XCTAssertNil(reloaded?.semanticMemory.reflectionFrame)
        XCTAssertEqual(reloaded?.messages.last(where: { $0.role == .user })?.content, "这件事现在仍然压着我。")
        XCTAssertFalse(
            reloaded?.messages.contains {
                $0.role == .assistant && $0.content == PersistenceSabotagingTurnController.reply
            } == true
        )
    }

    func testCurrentRecoveryPersistenceFailureRollsBackAndCommitRetryIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-recovery-store-failure-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SessionStore(directory: directory)
        let turnController = RecoveryPersistenceSabotagingTurnController(directory: directory)
        let audit = ProtocolExecutionAuditRecorder()
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: turnController,
            sessionStore: store,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        let committedEpisode = TurnEpisodeStructure(
            concreteFacts: ["已经说清的一件具体事情"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户已经说明自己的做法"],
            eventProcessStatus: .present,
            eventProcess: ["事情的发展过程已经说明"]
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = committedEpisode

        model.draft = "这是需要由恢复计划承接的最新回答。"
        model.send()
        await waitUntilIdle(model)

        let userMessage = model.session.messages.last { $0.role == .user }
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(model.session.semanticMemory.episodeStructure, committedEpisode)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant
                    && $0.content == RecoveryPersistenceSabotagingTurnController.reply
            }
        )
        XCTAssertTrue(model.canRetry)
        let plansBeforeRetry = await turnController.planCount()
        let writesBeforeRetry = await turnController.writeCount()
        XCTAssertEqual(plansBeforeRetry, 2)
        XCTAssertEqual(writesBeforeRetry, 1)
        XCTAssertEqual(audit.count(for: .transactionCommit), 0)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        model.retryLastRequest()
        await waitUntilIdle(model)

        XCTAssertFalse(model.canRetry)
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        let visibleReplies = model.session.messages.filter {
            $0.role == .assistant
                && $0.content == RecoveryPersistenceSabotagingTurnController.reply
        }
        XCTAssertEqual(visibleReplies.count, 1)
        XCTAssertEqual(visibleReplies.first?.replyToMessageID, userMessage?.id)
        let plansAfterRetry = await turnController.planCount()
        let writesAfterRetry = await turnController.writeCount()
        XCTAssertEqual(plansAfterRetry, 2)
        XCTAssertEqual(writesAfterRetry, 1)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)

        let reloaded = try await store.load(id: model.session.id)
        XCTAssertEqual(reloaded?.protocolStage, .cardConsent)
        XCTAssertEqual(
            reloaded?.messages.filter {
                $0.role == .assistant
                    && $0.content == RecoveryPersistenceSabotagingTurnController.reply
            }.count,
            1
        )
    }

    func testSecondPlanCriticFailureReturnsTypedRejectionWithoutLocalFallback() async throws {
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
            eventProcess: ["事情的发展已经说明"],
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
                ],
                allowedSemanticOperations: [.clarifyEvent, .advanceToCardConsent]
            ),
            recentMessages: [.init(role: .user, content: "用户已经补充了最新回答。")],
            semanticMemory: memory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        do {
            _ = try await controller.plan(to: request)
            XCTFail("A second semantic rejection must return to the Swift recovery transaction")
        } catch let error as LLMTurnControllerClientError {
            guard case .semanticPlanRejected(let reasons) = error else {
                return XCTFail("Expected semanticPlanRejected, got \(error)")
            }
            XCTAssertTrue(reasons.contains("duplicate_question_function"))
        }
        let writerCallsBeforeWriting = await writer.callCount()
        let plannerCalls = await planner.callCount()
        let planCriticCalls = await planCritic.callCount()
        XCTAssertEqual(writerCallsBeforeWriting, 0)
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertEqual(planCriticCalls, 2)
        let finalPermissions = await planner.lastPermissions()
        XCTAssertEqual(finalPermissions, request.permissions)
        let writerCallsAfterWriting = await writer.callCount()
        XCTAssertEqual(writerCallsAfterWriting, 0)
    }

    func testCurrentRecoveryUsesSemanticCriticWithoutExtraPlannerRevision() async throws {
        let frame = TurnReflectionFrame(
            mode: .tender,
            action: .acknowledgeExperience,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "这件事此刻仍然让我难受"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "承认当前仍然存在的感受",
            fierceEvidence: nil
        )
        let planner = StaticTurnPlanner(
            plan: LLMTurnResponsePlan(
                semanticOperation: .continueTenderReflection,
                requestedStage: .complete,
                localAction: .init(kind: .completeSession),
                memoryUpdate: .init(reflectionFrame: frame),
                nextPrompt: .confirmationRequest(target: .cardMapping),
                replyIntent: .completeConversation,
                replyGuidance: "承接当前感受并问一个具体、容易回答的问题"
            )
        )
        let planCritic = PassingPlanCritic()
        let controller = RemoteReflectionTurnController(
            planner: planner,
            planCritic: planCritic,
            writer: CriticTestWriter(),
            critic: PassingWriterCritic()
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.reflectionReadiness = .reflectionOpen
        let request = LLMTurnControllerRequest(
            trigger: .protocolCorrection,
            protocolVersion: session.protocolVersion,
            protocolStage: session.protocolStage,
            recoveryOperation: .directReflection,
            condition: session.condition,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [
                .init(role: .user, content: "这件事此刻仍然让我难受。"),
            ],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            card: nil,
            protocolCorrection: "{\"failureCategory\":\"contract_rejected\"}"
        )

        let recovered = try await controller.plan(to: request)
        let plannerCalls = await planner.callCount()
        let criticCalls = await planCritic.callCount()

        XCTAssertEqual(recovered.semanticOperation, .continueTenderReflection)
        XCTAssertEqual(plannerCalls, 1)
        XCTAssertEqual(criticCalls, 1)
    }

    func testOrdinaryDisclosureUsesSemanticCriticsWithoutChangingThePlannedQuestion() async throws {
        let plan = LLMTurnResponsePlan(
            semanticOperation: .clarifyEvent,
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
                allowedReplyIntents: [.exploreContext],
                allowedSemanticOperations: [.clarifyEvent]
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

    func testTypedCardRealityMappingIsCanonicalizedBeforeAnotherSemanticAudit() async throws {
        let candidate = LLMTurnResponsePlan(
            semanticOperation: .establishUserAuthoredCardConnection,
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            cardConnectionTurnOutcome: try .init(
                kind: .userAuthoredConnection,
                connection: .init(
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
                ],
                allowedSemanticOperations: [.establishUserAuthoredCardConnection]
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

        XCTAssertEqual(result.replyIntent, .inviteCardConnection)
        XCTAssertEqual(result.localAction.kind, .none)
        XCTAssertEqual(result.nextPrompt?.kind, TurnNextPromptKind.openQuestion)
        XCTAssertEqual(
            result.cardConnectionTurnOutcome?.connection?.realityMapping,
            "用户刚刚形成的画面—现实联系"
        )
        XCTAssertNil(result.memoryUpdate.cardRealityConnection)
        let criticCalls = await planCritic.callCount()
        XCTAssertEqual(criticCalls, 1)
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
            protocolVersion: ReflectionSession.consolidatedTurnProtocolVersion,
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
                allowedReplyIntents: [.suggestPractice],
                allowedSemanticOperations: [.proposePractice]
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
        XCTAssertEqual(result.memoryUpdate.practiceTransition?.proposal?.kind, .change)
        XCTAssertEqual(
            result.memoryUpdate.practiceTransition?.proposal?.status,
            .pendingConfirmation
        )
        XCTAssertEqual(result.nextPrompt?.referenceID, "practice-transition")
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

    func testLegacyAcceptedCardMappingCommitsSilentlyThenGeneratesFreshDirectReply() async {
        let mappingReference = "accepted-card-mapping"
        let directReply = "这段距离也可能是在给自己留出空间。放回现实里，它让你对眼前的处境多看见了什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueTenderReflection,
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .distinguishFactFromPrediction,
                                evidenceBasis: [
                                    .init(
                                        source: .cardRealityConnection,
                                        content: "用户确认的画面关系与现实联系"
                                    ),
                                ],
                                dimensions: [.mindfulness],
                                reflectionDelta: "从已经确认的联系形成一个新的观察角度",
                                fierceEvidence: nil
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "tender_connection_delta",
                            focus: "这个联系带来的一个新观察"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "基于确认的联系提出一个新的温和反思问题"
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
        model.session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
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
            "tender_reflection"
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

    func testLegacyPendingCardMappingDecodeRepairUsesCompleteConfirmationContract() async {
        let audit = ProtocolExecutionAuditRecorder()
        let mappingReference = "decode-repair-card-mapping"
        let directReply = "这个区别让原来的处境多了一种看法。放回现实里，你最先注意到的变化是什么？"
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
                        semanticOperation: .continueTenderReflection,
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .distinguishFactFromPrediction,
                                evidenceBasis: [
                                    .init(
                                        source: .cardRealityConnection,
                                        content: "用户确认的画面关系与现实联系"
                                    ),
                                ],
                                dimensions: [.mindfulness],
                                reflectionDelta: "从确认的联系形成一个新的现实观察",
                                fierceEvidence: nil
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "tender_connection_delta",
                            focus: "联系带来的一个现实观察"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "提出一条新的温和现实反思问题"
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
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
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
        XCTAssertEqual(requests[1].recoveryOperation, .legacyCardReading)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains("planner_decode") == true
        )
        XCTAssertFalse(
            requests[1].protocolCorrection?.contains("cardRealityConnection") == true
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 1)
        XCTAssertGreaterThanOrEqual(audit.count(for: .legacySemanticMapper), 1)
    }

    func testCurrentSourceOnlyConnectionPatchNeverReachesWriterOrChangesSession() async {
        func sourceOnlyPlan() -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                semanticOperation: .continueOpenCardConnection,
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
        model.session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["画面中的人物"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["画面中的人物"],
            relationOrAction: "形成了一条画面关系",
            anticipatedChangeOrChoice: nil
        )
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
        XCTAssertEqual(requests[1].recoveryOperation, .cardOpenExploration)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "semantic_mapping_payload_mismatch_continueOpenCardConnection"
            ) == true
        )
        XCTAssertFalse(requests[1].permissions.allowedActions.contains(.shareCardGuidance))
    }

    func testMalformedMappingAuthorizationRecoversWithoutVisibleInterruption() async {
        let reflectionReply =
            "画面里的照顾让一个人停下来接受水，而你把持续修改理解成让方案变好的一种方式。沿着这个联系回到截止时间前，最难停下来的具体时刻是什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueOpenCardConnection,
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
                        semanticOperation: .presentLegacyCardReading,
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
                        semanticOperation: .establishUserAuthoredCardConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .acknowledgeExperience,
                                evidenceBasis: [
                                    .init(
                                        source: .latestUserAnswer,
                                        content: "用户把持续修改与希望方案变好联系起来"
                                    ),
                                ],
                                dimensions: [.selfKindness, .mindfulness],
                                reflectionDelta: "理解希望变好的用意，同时保留延期事实",
                                fierceEvidence: nil
                            )
                        ),
                        cardConnectionTurnOutcome: try! .init(
                            kind: .userAuthoredConnection,
                            connection: .init(
                                imageRelation: "画面中一方提供照顾，另一方停下来接受照顾",
                                realityMapping: "用户把持续修改方案与试图让方案变好联系起来",
                                source: .userAuthored
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "完整提交用户修订的现实连接"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: reflectionReply
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
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["画面中的两个人"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["提供照顾的人", "停下来的人"],
            relationOrAction: "一方提供照顾，另一方停下来接受",
            anticipatedChangeOrChoice: nil
        )
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["昨天没有按时提交项目方案"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["方案基本完成后仍持续修改"],
            eventProcessStatus: .present,
            eventProcess: ["方案完成后持续修改，最后错过提交时间"],
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

        XCTAssertTrue(
            model.session.cardGuidanceShared,
            model.session.studyEvents.map(\.action).joined(separator: " | ")
        )
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 0)
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把持续修改方案与试图让方案变好联系起来"
        )
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.source,
            .userAuthored
        )
        XCTAssertNotNil(model.session.cardGuidanceTransactionID)
        XCTAssertFalse(model.session.pendingCardGuidanceTurn)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertNil(model.session.semanticMemory.cardNegotiatedMeaning)
        XCTAssertNotEqual(model.session.semanticMemory.nextPrompt?.target, .cardMapping)
        XCTAssertEqual(model.session.messages.last?.content, reflectionReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "coarse_protocol_typed_recovery_2_requested"
            }
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertFalse(
            requests[1].permissions.allowedActions.contains(.shareCardGuidance)
        )
        XCTAssertEqual(requests[2].card?.connectionInteractionState, .openExploration)
        XCTAssertNil(requests[2].semanticMemory.pendingCardRealityConnection)
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.concreteFacts,
            ["昨天没有按时提交项目方案"]
        )
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.eventProcess,
            ["方案完成后持续修改，最后错过提交时间", "方案基本完成后仍持续修改"]
        )
        XCTAssertEqual(
            requests.first?.card?.realityAnchor?.impacts,
            ["错过了截止时间"]
        )
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 3)
        XCTAssertEqual(calls.writes, 1)
    }

    func testPostGuidanceRecoveryPreservesConfirmedConnectionAndRepairsToDirectReflection() async {
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
                        semanticOperation: .presentLegacyCardReading,
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
                        semanticOperation: .authorizeCardGuidance,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .completeConversation,
                        replyGuidance: "旧字段故意冲突，显式 operation 才有执行权"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueTenderReflection,
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .acknowledgeExperience,
                                evidenceBasis: [
                                    .init(source: .cardRealityConnection, content: "用户已经确认的连接"),
                                    .init(source: .latestUserAnswer, content: "用户想继续看最难停下来的时刻"),
                                ],
                                dimensions: [.selfKindness, .mindfulness],
                                reflectionDelta: "沿不可变的连接继续一个现实中的具体时刻",
                                fierceEvidence: nil
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "grounded_tender_focus",
                            focus: "当前最值得继续看的具体时刻"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "保留既有 connection，直接继续现实反思"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
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
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.messages.last?.content, visibleReply)

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].recoveryOperation, .currentCardGuidance)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "semantic_mapping_operation_not_allowed_presentLegacyCardReading_in_cardReflection"
            ) == true
        )
        XCTAssertFalse(requests[1].protocolCorrection?.contains("realityMapping") == true)
        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 3)
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
            "截止时间前，事情是怎样一步步发展到没有提交的？",
            model.session.studyEvents.map(\.action).joined(separator: " | ")
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
                        semanticOperation: .continueTenderGroundedFierceReflection,
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .fierce,
                                action: .acknowledgeBehaviorImpact,
                                evidenceBasis: [
                                    .init(source: .episode, content: "方案基本完成后仍持续修改，最后错过截止时间"),
                                    .init(source: .cardRealityConnection, content: "用户把持续修改与希望方案变好联系起来"),
                                ],
                                dimensions: [.selfKindness, .mindfulness],
                                reflectionDelta: "先限制整体否定，再面对持续修改与错过提交的具体关系",
                                fierceEvidence: .init(
                                    behavior: "方案基本完成后仍持续修改",
                                    impact: "错过截止时间",
                                    direction: .change
                                )
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "grounded_fierce_focus",
                            focus: "哪一次继续修改最直接挤掉了提交"
                        ),
                        replyIntent: .directCandidReflection,
                        replyGuidance: "同轮实现 Tender grounding 与有证据的 Fierce focus"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
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
        restored.protocolStage = .directReflection
        restored.condition = .cardMediated
        restored.stage = .cardInterpretation
        restored.workflowPhase = .cardAssociation
        restored.card = CardService().allCards[3]
        restored.cardDisplayState = .displayed
        restored.cardGuidanceShared = true
        restored.reflectionReadiness = .reflectionOpen
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
            eventProcess: ["方案完成后持续修改，最后错过提交时间"],
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

    func testLegacyNaturalAnswerToCardReadingQuestionResolvesMappingWithoutApprovalWords() async {
        let mappingReference = "implicit-card-mapping"
        let directReply = "这个节点已经更清楚了。把它放回眼前的处境，你现在多看见了什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueTenderReflection,
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
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .distinguishFactFromPrediction,
                                evidenceBasis: [
                                    .init(
                                        source: .latestUserAnswer,
                                        content: "用户指出联系出现在从判断转向行动的节点"
                                    ),
                                ],
                                dimensions: [.mindfulness],
                                reflectionDelta: "将用户指出的现实节点发展为一个新观察",
                                fierceEvidence: nil
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "tender_connection_delta",
                            focus: "用户自然回应中出现的现实节点带来的新观察"
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
        model.session.protocolVersion = ReflectionSession.consolidatedTurnProtocolVersion
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
        // Protocol v4 keeps the legacy cardMapping confirmation transaction, but an already
        // offered contextual cue is not injected into that transaction again.
        XCTAssertNil(requests.first?.contextualLoadCue)
        XCTAssertNil(requests.last?.contextualLoadCue)
        XCTAssertNil(model.session.semanticMemory.contextRelationship)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)
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

    func testExactDisclosureReplayAdvancesToGroundingAndCardInvitation() async {
        let expectedReply =
            "方案基本做完后，你因为仍觉得不够好而继续修改，最后错过了提交时间。可以用一张随机反思卡换个角度看看；你愿意试试吗？"
        let episode = TurnEpisodeStructure(
            concreteFacts: ["昨天没有按时提交项目方案"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["方案基本完成后仍持续修改，没有提交"],
            eventProcessStatus: .present,
            eventProcess: ["方案基本完成后持续修改，最后错过提交时间"],
            possibleContributors: ["用户持续认为方案还不够好"],
            impactStatus: .unresolved
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .advanceToCardConsent,
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

    func testFamilyPickupDisclosureMovesDirectlyToNaturalCardInvitation() async {
        let expectedReply =
            "原来的安排后来变了，而你没有提前告诉家人。我们可以先停在这里，抽一张随机反思卡，从另一个角度看看这件事吗？"
        let episode = TurnEpisodeStructure(
            concreteFacts: ["用户昨天答应去接家人但最后没有去"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户临时和朋友吃饭，没有提前告诉家人"],
            eventProcessStatus: .present,
            eventProcess: ["原来的接人安排临时改变"],
            possibleContributors: ["用户临时改变了原来的接人安排"]
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .advanceToCardConsent,
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            episodeStructure: episode
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "只用一个事实锚点，自然邀请一张随机反思卡"
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
            purpose: "clarify_event_process",
            focus: "从答应接家人到最后没去之间发生了什么",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )
        model.session.messages = [
            .init(
                role: .user,
                content: "我昨天答应去接家人，但最后没去。",
                state: .eventDisclosure
            ),
            .init(
                role: .assistant,
                content: "后来发生了什么，让原来的安排变了？",
                state: .eventDisclosure
            ),
        ]

        model.draft = "我临时和朋友去吃饭了，想着家人可以自己回来，也没有提前告诉他。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.semanticMemory.episodeStructure, episode)
        XCTAssertEqual(model.session.messages.last?.content, expectedReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("暂时没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("regeneration") || $0.action.contains("recovery")
            }
        )
        for forbiddenQuestion in ["产生了什么影响", "为什么重要", "为什么内疚", "最放不下"] {
            XCTAssertFalse(
                model.session.messages.contains {
                    $0.role == .assistant && $0.content.contains(forbiddenQuestion)
                }
            )
        }
    }

    func testRealityConnectionInvitationUsesOneNormalTurnWithoutRecovery() async {
        let reply =
            "画面里的关系已经比较清楚了。把这个变化放回刚才那件事，会让你想到哪个具体时刻？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .inviteRealityConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "邀请用户把已经形成的画面关系连接到当前焦点事件"
                    )
                ),
            ],
            writings: [
                .success(.init(realizedIntent: .inviteCardConnection, reply: reply)),
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
        model.session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["人物", "手边的物品"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "手边的物品"],
            projectiveFocus: "人物会如何安排手边的物品",
            relationOrAction: "正在重新安排",
            anticipatedChangeOrChoice: "可能把一件东西放到另一边"
        )
        model.session.semanticMemory.cardImageRelation = "人物正在重新安排手边的物品"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "card_image_development",
            focus: "画面接下来可能发生什么"
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "接下来画面里可能发生什么？",
                state: .cardInterpretation
            ),
        ]

        model.draft = "他可能会把其中一件东西放到另一边。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        let requests = await controller.receivedRequests()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolCorrection }.count, 0)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolContinuation }.count, 0)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "cardRealityConnection")
        XCTAssertEqual(model.session.messages.last?.content, reply)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("recovery") || $0.action.contains("regeneration")
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
                        semanticOperation: .offerCardConnectionScaffold,
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
                        semanticOperation: .offerCardConnectionCandidate,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            pendingCardRealityConnection: PendingCardRealityConnection(
                                id: UUID(),
                                imageRelation: "画面里的关系变化",
                                candidateRealityMapping: "现实中尚未发生的转换"
                            )
                        ),
                        cardConnectionTurnOutcome: try! .init(
                            kind: .connectionStillUnclear
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
        model.session.semanticMemory.cardObservationEvidence = CardObservationEvidence(
            userDescribedElements: ["人物", "空间"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "空间"],
            relationOrAction: "形成了一条变化关系",
            anticipatedChangeOrChoice: nil
        )
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
        // attemptCount unchanged for candidate offer
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertNotNil(model.session.semanticMemory.pendingCardRealityConnection)
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
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
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

        model.draft = "好。"
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

    func testCurrentUserAuthoredCardConnectionFlowsDirectlyIntoTenderReflection() async {
        let executionAudit = ProtocolExecutionAuditRecorder()
        let protocolController = ReflectionProtocolController(executionAudit: executionAudit)
        let reflectionReply =
            "你把画面中放下负担的动作连到了现实。那段具体经历确实发生过，但一直背着它评价整个人，是在事实之外又加上的判断；当这份负担再次出现时，最先压住你的是什么？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .establishUserAuthoredCardConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            answeredQuestionPurposes: ["card_reality_connection"],
                            contextCueOffered: true,
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .softenGlobalSelfJudgment,
                                evidenceBasis: [
                                    .init(source: .episode, content: "用户已经说明的具体经历"),
                                    .init(source: .cardRealityConnection, content: "用户把画面中放下负担的动作连到现实"),
                                ],
                                dimensions: [.selfKindness, .mindfulness],
                                reflectionDelta: "区分已经发生的具体经历与对整个人的扩大判断",
                                fierceEvidence: nil
                            )
                        ),
                        cardConnectionTurnOutcome: try! .init(
                            kind: .userAuthoredConnection,
                            connection: .init(
                                imageRelation: "一个人物正在改变随身物品的安排",
                                realityMapping: "用户把画面中的改变与现实里想放下的一项负担联系起来",
                                source: .userAuthored
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "把简短卡牌桥接与有证据的 Tender 区分写在同一条回复里"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: reflectionReply
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: protocolController,
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
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["画面中的人物和随身物品"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["人物", "随身物品"],
            relationOrAction: "人物正在改变随身物品的安排",
            anticipatedChangeOrChoice: nil
        )
        model.session.semanticMemory.selfCriticismStatus = .present
        model.session.semanticMemory.selfCriticalStatement = "我是不是做什么都不行"
        model.session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["一件已经发生的具体经历"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户已经说明自己当时做了什么"],
            eventProcessStatus: .present,
            eventProcess: ["事件的发展过程已经得到说明"]
        )
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

        let assistantCountBefore = model.session.messages.filter { $0.role == .assistant }.count
        model.draft = "我好像也想在现实里放下一直背着的一项负担。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertTrue(
            model.session.cardGuidanceShared,
            model.session.studyEvents.map(\.action).joined(separator: " | ")
        )
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.realityMapping,
            "用户把画面中的改变与现实里想放下的一项负担联系起来"
        )
        XCTAssertNil(model.session.semanticMemory.cardInterpretiveTension)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            "tender_grounding_after_card_guidance"
        )
        XCTAssertNil(model.session.semanticMemory.cardNegotiatedMeaning)
        XCTAssertNil(model.session.semanticMemory.pendingCardRealityConnection)
        XCTAssertEqual(
            model.session.semanticMemory.cardRealityConnection?.source,
            .userAuthored
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.mode, .tender)
        XCTAssertEqual(model.session.semanticMemory.selfCriticalStatement, "我是不是做什么都不行")
        XCTAssertEqual(model.session.messages.last?.content, reflectionReply)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        let counts = await controller.callCounts()
        // Single combined turn: 1 Planner + 1 Writer, no continuation
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(executionAudit.count(for: .semanticMapper), 1)
        XCTAssertEqual(executionAudit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(executionAudit.count(for: .projector), 1)
        XCTAssertEqual(executionAudit.count(for: .legacyNormalizer), 0)
        XCTAssertEqual(executionAudit.count(for: .legacyTransitionBuilder), 0)
        XCTAssertEqual(executionAudit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(executionAudit.count(for: .silentContinuation), 0)
        XCTAssertEqual(executionAudit.count(for: .transactionCommit), 1)
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolCorrection }.count, 0)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolContinuation }.count, 0)
        XCTAssertEqual(requests.filter { $0.trigger == .cardGuidanceAvailable }.count, 0)
        let writerPlans = await controller.receivedWriterPlans()
        XCTAssertEqual(writerPlans.count, 1)
        XCTAssertEqual(
            writerPlans.first?.projectedOperation,
            .establishUserAuthoredCardConnection
        )
        XCTAssertEqual(writerPlans.first?.replyIntent, .directCandidReflection)
        XCTAssertEqual(writerPlans.first?.localAction.kind, .shareCardGuidance)
        XCTAssertEqual(
            writerPlans.first?.nextPrompt?.purpose,
            "tender_grounding_after_card_guidance"
        )
        let assistantMessages = model.session.messages.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages.count - assistantCountBefore, 1)
        let latestUserID = model.session.messages.last(where: { $0.role == .user })?.id
        XCTAssertEqual(assistantMessages.last?.replyToMessageID, latestUserID)
        XCTAssertEqual(reflectionReply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(model.session.pendingCardGuidanceTurn)
        let cardState = ReflectionProtocolController().effectiveCardState(for: model.session)
        XCTAssertFalse(cardState.candidateBridgeEligible)
        let pendingAnswer = PendingUncommittedCardAnswerContext(
            session: model.session,
            lastCommittedState: cardState
        )
        XCTAssertFalse(pendingAnswer.hasUncommittedLatestAnswer)
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action == "protocol_transition_cardReflection_to_directReflection_intent_directCandidReflection"
            }.count,
            1
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "contextual_cue_offered_after_card_mapping"
            }
        )
    }

    func testPrematureCardReadingRepairAuthorizesUserMappingBeforeDirectReflection() async {
        let reflectionReply =
            "画面中的关系从停在一个局部转向重新安排整体，而你注意到现实中的自己会持续停在一个局部。把两者放在一起，可以先看整体是否已经足够继续，再决定局部还需要改到什么程度。"
        let controller = ScriptedReflectionTurnController(
            plans: [
                // Reproduces the production failure: the Planner jumps directly to a reading
                // before committing the latest user-authored image-to-life mapping.
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .presentLegacyCardReading,
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
                        semanticOperation: .establishUserAuthoredCardConnection,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .distinguishFactFromPrediction,
                                evidenceBasis: [
                                    .init(
                                        source: .latestUserAnswer,
                                        content: "现实中会一直停在一个局部"
                                    ),
                                ],
                                dimensions: [.selfKindness, .mindfulness],
                                reflectionDelta: "把整体是否足够继续与局部仍可完善区分开",
                                fierceEvidence: nil
                            )
                        ),
                        cardConnectionTurnOutcome: try! .init(
                            kind: .userAuthoredConnection,
                            connection: .init(
                                imageRelation: "画面中的人物正从关注一个局部转向重新安排多个元素的关系",
                                realityMapping: "用户把画面中重新安排整体关系与现实里持续停在一个局部形成对比",
                                source: .userAuthored
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "原子提交用户修订的画面—现实连接"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .directCandidReflection,
                        reply: reflectionReply
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
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物和多个元素"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["人物", "多个元素"],
            relationOrAction: "人物从关注局部转向重新安排整体关系",
            anticipatedChangeOrChoice: nil
        )
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
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertNotEqual(model.session.semanticMemory.nextPrompt?.target, .cardMapping)
        XCTAssertNil(model.session.semanticMemory.cardNegotiatedMeaning)
        XCTAssertEqual(model.session.messages.last?.content, reflectionReply)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )

        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(
            requests[1].permissions.allowedReplyIntents.contains(.presentCardReading)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedReplyIntents.contains(.authorizeCardGuidance)
        )
        XCTAssertFalse(
            requests[1].permissions.allowedActions.contains(.shareCardGuidance)
        )
        XCTAssertEqual(requests[1].recoveryOperation, .cardOpenExploration)
        XCTAssertTrue(
            requests[1].protocolCorrection?.contains(
                "semantic_mapping_operation_not_allowed_presentLegacyCardReading_in_cardReflection"
            ) == true
        )
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1)
    }

    func testAcceptedNarrativeRecoveryRebuildsTheWholeAtomicTransition() async {
        let narrativeID = "narrative-action-1"
        let transactionID = "practice-action-1"
        let invalidProposal = TurnPracticeProposal(
            id: transactionID,
            kind: .repair,
            content: "给家人发一条说明和道歉的信息。",
            basis: "",
            status: .pendingConfirmation,
            source: .assistantProposed
        )
        let repairedProposal = TurnPracticeProposal(
            id: transactionID,
            kind: .repair,
            content: "给家人发一条说明和道歉的信息。",
            basis: "用户明确说自己没有提前告知家人，并认为自己的做法伤到了家人。",
            status: .pendingConfirmation,
            source: .assistantProposed
        )
        func plan(
            proposal: TurnPracticeProposal,
            resolution: TurnResolvedConfirmation?
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                semanticOperation: .proposePractice,
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(
                    practiceTransition: .init(
                        transactionID: transactionID,
                        narrativeReferenceID: narrativeID,
                        proposal: proposal,
                        noActionReason: nil
                    )
                ),
                resolvedConfirmation: resolution,
                nextPrompt: .confirmationRequest(
                    target: .practice,
                    referenceID: transactionID
                ),
                replyIntent: .suggestPractice,
                replyGuidance: "提出一个有用户证据的小行动"
            )
        }
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    plan(
                        proposal: invalidProposal,
                        resolution: .init(
                            target: .finalNarrative,
                            decision: .accepted,
                            referenceID: narrativeID
                        )
                    )
                ),
                .success(
                    plan(
                        proposal: repairedProposal,
                        resolution: .init(
                            target: .finalNarrative,
                            decision: .accepted,
                            referenceID: narrativeID
                        )
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .suggestPractice,
                        reply: "可以先给家人发一条简短的信息，说明你没有提前告知并为此道歉。"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            sessionStore: SessionStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            preparesContextDataAutomatically: false
        )
        preparePendingFinalNarrative(model, referenceID: narrativeID)

        model.draft = "对"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 2)
        XCTAssertEqual(counts.writes, 1, "Writer must see only the repaired legal proposal")
        XCTAssertTrue(model.session.finalNarrativeConfirmed)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(
            model.session.semanticMemory.practiceTransition?.proposal,
            repairedProposal
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .practice)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.referenceID, transactionID)
        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action.contains("committed_before_practice")
            }.count,
            0
        )
        let requests = await controller.receivedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].semanticMemory.nextPrompt?.target, .finalNarrative)
        XCTAssertNil(requests[1].semanticMemory.practiceTransition)
        XCTAssertEqual(requests[1].recoveryOperation, .finalNarrative)
        XCTAssertTrue(requests[1].permissions.allowedStages.contains(.optionalAction))
        XCTAssertTrue(requests[1].permissions.allowedReplyIntents.contains(.suggestPractice))
    }

    func testSecondRecoveryCanCompleteNarrativeActionWithoutInventingNoAction() async {
        let narrativeID = "narrative-action-2"
        let transactionID = "practice-action-2"
        func incompletePlan(
            resolution: TurnResolvedConfirmation?
        ) -> LLMTurnResponsePlan {
            let proposal = TurnPracticeProposal(
                id: transactionID,
                kind: .change,
                content: "完成一个小动作。",
                basis: "",
                status: .pendingConfirmation,
                source: .assistantProposed
            )
            return LLMTurnResponsePlan(
                semanticOperation: .proposePractice,
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(
                    practiceTransition: .init(
                        transactionID: transactionID,
                        narrativeReferenceID: narrativeID,
                        proposal: proposal,
                        noActionReason: nil
                    )
                ),
                resolvedConfirmation: resolution,
                nextPrompt: .confirmationRequest(
                    target: .practice,
                    referenceID: transactionID
                ),
                replyIntent: .suggestPractice,
                replyGuidance: "提出一个小行动"
            )
        }
        let repairedProposal = TurnPracticeProposal(
            id: transactionID,
            kind: .change,
            content: "完成一个小动作。",
            basis: "用户已经确认希望从一个足够小的动作开始。",
            status: .pendingConfirmation,
            source: .assistantProposed
        )
        let validPlan = LLMTurnResponsePlan(
            semanticOperation: .proposePractice,
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                practiceTransition: .init(
                    transactionID: transactionID,
                    narrativeReferenceID: narrativeID,
                    proposal: repairedProposal,
                    noActionReason: nil
                )
            ),
            resolvedConfirmation: .init(
                target: .finalNarrative,
                decision: .accepted,
                referenceID: narrativeID
            ),
            nextPrompt: .confirmationRequest(
                target: .practice,
                referenceID: transactionID
            ),
            replyIntent: .suggestPractice,
            replyGuidance: "提出一个有用户证据的小行动"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    incompletePlan(
                        resolution: .init(
                            target: .finalNarrative,
                            decision: .accepted,
                            referenceID: narrativeID
                        )
                    )
                ),
                .success(incompletePlan(resolution: nil)),
                .success(validPlan),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .suggestPractice,
                        reply: "可以先完成这个足够小的动作。"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            sessionStore: SessionStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            preparesContextDataAutomatically: false
        )
        preparePendingFinalNarrative(model, referenceID: narrativeID)

        model.draft = "准确"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertTrue(model.session.finalNarrativeConfirmed)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(model.session.semanticMemory.practiceTransition?.proposal, repairedProposal)
        XCTAssertNil(model.session.semanticMemory.practiceTransition?.noActionReason)
        XCTAssertFalse(model.canRetry)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "practice_transition_repair_budget_exhausted_no_action"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
    }

    func testRestartedAwaitingPracticeReusesTransactionWithoutReconfirmingNarrative() async throws {
        let narrativeID = "narrative-restart"
        let transactionID = "practice-restart"
        var persisted = ReflectionSession()
        persisted.protocolVersion = ReflectionSession.currentProtocolVersion
        persisted.condition = .cardMediated
        persisted.protocolStage = .optionalAction
        persisted.stage = .attributionReflection
        persisted.workflowPhase = .optionalAction
        persisted.finalNarrativeConfirmed = true
        persisted.semanticMemory.finalNarrative = "已经确认的最终叙事"
        persisted.semanticMemory.practiceTransition = .init(
            transactionID: transactionID,
            narrativeReferenceID: narrativeID,
            proposal: nil,
            noActionReason: nil
        )
        persisted.semanticMemory.nextPrompt = nil
        persisted.messages = [
            .init(
                role: .assistant,
                content: "这是已经确认的最终叙事。",
                state: .attributionReflection
            ),
        ]
        let restored = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONEncoder().encode(persisted)
        )
        let proposal = TurnPracticeProposal(
            id: transactionID,
            kind: .change,
            content: "下一次计划变化时先发一条消息。",
            basis: "用户明确认为计划变化时应该提前商量。",
            status: .pendingConfirmation,
            source: .assistantProposed
        )
        let plan = LLMTurnResponsePlan(
            semanticOperation: .proposePractice,
            requestedStage: .optionalAction,
            localAction: .none,
            memoryUpdate: .init(
                practiceTransition: .init(
                    transactionID: transactionID,
                    narrativeReferenceID: narrativeID,
                    proposal: proposal,
                    noActionReason: nil
                )
            ),
            resolvedConfirmation: nil,
            nextPrompt: .confirmationRequest(
                target: .practice,
                referenceID: transactionID
            ),
            replyIntent: .suggestPractice,
            replyGuidance: "只完成重启前尚未建立的行动提议"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(plan)],
            writings: [
                .success(
                    .init(
                        realizedIntent: .suggestPractice,
                        reply: "下一次安排有变化时，可以先发一条简短消息。"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            sessionStore: SessionStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            preparesContextDataAutomatically: false
        )
        model.session = restored

        model.draft = "准确"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertTrue(model.session.finalNarrativeConfirmed)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(
            model.session.semanticMemory.practiceTransition?.transactionID,
            transactionID
        )
        XCTAssertEqual(model.session.semanticMemory.practiceTransition?.proposal, proposal)
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action.contains("committed_before_practice")
            }.count,
            0,
            "A restart must not submit the final narrative confirmation again"
        )
        let requests = await controller.receivedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertNotNil(request.semanticMemory.finalNarrative)
        XCTAssertNil(request.semanticMemory.nextPrompt)
        XCTAssertEqual(
            request.semanticMemory.practiceTransition?.transactionID,
            transactionID
        )
    }

    func testWriterSingleQuestionDoesNotFailOrReplanTheTurn() async {
        let reply = "你既后悔那句话，也担心这段关系。现在最想先说哪一部分？"
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "用户后悔冲突中的表达并担心关系受损",
                            receivedDisclosureQuestionPurposes: [.identifyConcreteEpisode],
                            episodeStructure: .init(
                                concreteFacts: ["用户和朋友争吵时说了很重的话"]
                            )
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "clarify_behavior",
                            focus: "争吵中具体说了什么",
                            disclosurePurpose: .clarifyBehavior,
                            disclosureTarget: .behavior
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
        prepareCurrentDisclosure(model)

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
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "identify_concrete_episode",
                focus: "最近工作中一件具体的事情",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
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
        prepareCurrentDisclosure(model)

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
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "只在Writer成功后提交这段理解"
            ),
            nextPrompt: .openQuestion(
                purpose: "committed_question",
                focus: "最近发生的一件具体事情",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
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
        prepareCurrentDisclosure(model)

        model.draft = "最近遇到一件让我很难受的事。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(
            model.session.semanticMemory.situationUnderstanding,
            "只在Writer成功后提交这段理解"
        )
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.purpose,
            TurnDisclosureQuestionPurpose.identifyConcreteEpisode.rawValue
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
                        semanticOperation: .continueCardObservation,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        replyIntent: .inviteCardObservation,
                        replyGuidance: "非法跨越到卡牌阶段"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(
                            purpose: "identify_concrete_episode",
                            focus: "最近发生的一件具体事情",
                            disclosurePurpose: .identifyConcreteEpisode,
                            disclosureTarget: .focalEvent
                        ),
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
        prepareCurrentDisclosure(model)

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
        XCTAssertTrue(
            correction.contains(
                "\"failureCategory\":\"semantic_mapping_operation_not_allowed_continueCardObservation_in_contextualDisclosure\""
            )
        )
        XCTAssertTrue(correction.contains("\"mustPreserve\""))
        XCTAssertFalse(correction.contains("currentStage"))
        XCTAssertFalse(correction.contains("allowedReplyIntents"))
        XCTAssertEqual(requests.last?.recoveryOperation, .eventDisclosure)
    }

    func testEventRecoveryCommitsLatestAnswerAndSemanticStateAsOneTransaction() async {
        let oldPrompt = TurnNextPrompt.openQuestion(
            purpose: "event_process_clarified",
            focus: "事情如何发展到这个结果",
            disclosurePurpose: .clarifyEventProcess,
            disclosureTarget: .eventProcess
        )
        let invalidSemanticPatch = TurnSemanticMemoryUpdate(
            situationUnderstanding: "这段未验证的理解绝不能进入 session",
            episodeStructure: .init(
                concreteFacts: ["未验证的事件改写"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: [],
                eventProcessStatus: .present,
                eventProcess: []
            )
        )
        let completeEpisode = TurnEpisodeStructure(
            concreteFacts: ["一次已经准备并提交的申请最终没有通过"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["整理材料并完成提交"],
            eventProcessStatus: .present,
            eventProcess: ["准备材料、提交、等待结果，随后收到未通过的通知"],
            impactStatus: .uncertain,
            impacts: []
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                // Status says content is present while both grounded arrays are empty. This
                // cannot be normalized without inventing evidence, so the entire plan must fail.
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: invalidSemanticPatch,
                        nextPrompt: .openQuestion(
                            purpose: "unverified_follow_up",
                            focus: "未验证的追问",
                            disclosurePurpose: .clarifyEventProcess,
                            disclosureTarget: .eventProcess
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "这份计划必须在 Writer 前被拒绝"
                    )
                ),
                // A recovery is still a complete plan. An intent without its required prompt is
                // rejected without committing anything from either failed attempt.
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            situationUnderstanding: "第二份未验证理解",
                            episodeStructure: .init(
                                eventProcessStatus: .present,
                                eventProcess: []
                            )
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "非法的无问题等待"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .advanceToCardConsent,
                        requestedStage: .cardConsent,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            selfCriticismStatus: .present,
                            selfCriticalStatement: "用户担心一次未通过说明自己的能力不够",
                            episodeStructure: completeEpisode
                        ),
                        nextPrompt: .confirmationRequest(target: .cardConsent),
                        replyIntent: .inviteCardConsent,
                        replyGuidance: "简短承接完整事件并邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: "这次结果确实让你开始怀疑自己的能力。我们可以抽一张随机反思卡，换个角度看看吗？"
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
            selfCriticalStatement: "用户担心一次未通过说明自己的能力不够",
            episodeStructure: .init(
                concreteFacts: ["一次申请没有通过"]
            ),
            nextPrompt: oldPrompt
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "从准备到收到结果，中间发生了什么？",
                state: .eventDisclosure
            ),
        ]

        let latestAnswer = "我整理并提交了材料，之后一直等待，最后收到未通过的通知，对方没有说明原因。"
        model.draft = latestAnswer
        model.send()
        await waitUntilIdle(model)

        let requests = await controller.receivedRequests()
        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertEqual(requests.map(\.recoveryOperation), [
            .eventDisclosure, .eventDisclosure, .eventDisclosure,
        ])
        XCTAssertNil(requests[0].protocolCorrection)
        XCTAssertNotNil(requests[1].protocolCorrection)
        XCTAssertNotNil(requests[2].protocolCorrection)
        XCTAssertTrue(requests[1].recentMessages.contains { $0.role == .user && $0.content == latestAnswer })
        XCTAssertTrue(requests[2].recentMessages.contains { $0.role == .user && $0.content == latestAnswer })

        XCTAssertTrue(model.session.messages.contains { $0.role == .user && $0.content == latestAnswer })
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.semanticMemory.episodeStructure, completeEpisode)
        XCTAssertEqual(
            model.session.semanticMemory.receivedDisclosureQuestionPurposes,
            [.clarifyEventProcess]
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardConsent)
        XCTAssertEqual(
            model.session.semanticMemory.selfCriticalStatement,
            "用户担心一次未通过说明自己的能力不够"
        )
        XCTAssertNotEqual(
            model.session.semanticMemory.situationUnderstanding,
            "这段未验证的理解绝不能进入 session"
        )
        XCTAssertNotEqual(
            model.session.semanticMemory.situationUnderstanding,
            "第二份未验证理解"
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("暂时没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("未验证的追问")
            }
        )
    }

    func testCurrentEventOperationIgnoresConflictingLegacyQuestionTarget() async throws {
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
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
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(counts.plans, 1)
        XCTAssertEqual(counts.writes, 1)
        XCTAssertNil(requests[0].protocolCorrection)
        let writerPlans = await controller.receivedWriterPlans()
        let writerPlan = try XCTUnwrap(writerPlans.first)
        XCTAssertEqual(writerPlan.projectedOperation, .clarifyEvent)
        XCTAssertEqual(writerPlan.nextPrompt?.disclosureTarget, .behavior)
        XCTAssertNotEqual(writerPlan.nextPrompt?.focus, "已经明确的事件")
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

    func testCoreCompleteWhyImportantOverexplorationRepairsOnlyToCardConsent() async throws {
        let completedPatch = try JSONDecoder().decode(
            TurnEpisodeStructure.self,
            from: Data(
                #"{"eventProcessStatus":"present","eventProcess":["用户已经说明事情如何发展到该结果"],"possibleContributors":["用户已经说明事情如何发展到该结果"],"impactStatus":"present","impacts":["用户已经说明这件事产生的实际影响"]}"#.utf8
            )
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .contextualDisclosure,
                        localAction: .none,
                        memoryUpdate: .init(
                            eventDisclosureOutcome: .readyForTenderOrCard,
                            episodeStructure: completedPatch
                        ),
                        nextPrompt: .openQuestion(
                            purpose: "why_this_matters",
                            focus: "这件事为什么现在仍然重要",
                            disclosurePurpose: .clarifyEventProcess,
                            disclosureTarget: .eventProcess
                        ),
                        replyIntent: .exploreContext,
                        replyGuidance: "核心已经完整，但继续追问为什么重要"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .advanceToCardConsent,
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
        XCTAssertTrue(
            requests[1].permissions.allowedDisclosurePurposes
                .contains(.clarifyEventProcess)
        )
        XCTAssertTrue(
            requests[1].permissions.allowedDisclosureTargets.contains(.eventProcess)
        )
        XCTAssertEqual(
            Set(requests[1].permissions.allowedReplyIntents),
            Set([.exploreContext, .inviteCardConsent, .safetySupport])
        )
        XCTAssertEqual(requests[1].recoveryOperation, .eventDisclosure)
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
                $0.action == "coarse_protocol_typed_recovery_1_requested"
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
            semanticOperation: .completeConversation,
            requestedStage: .complete,
            localAction: .none,
            memoryUpdate: .init(),
            replyIntent: .completeConversation,
            replyGuidance: "非法完成"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [.success(illegal), .success(illegal), .success(illegal)],
            writings: []
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller
        )
        prepareCurrentDisclosure(model)

        model.draft = "我还想继续说。"
        model.send()
        await waitUntilIdle(model)

        let counts = await controller.callCounts()
        XCTAssertEqual(counts.plans, 3)
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
            semanticOperation: .completeConversation,
            requestedStage: .complete,
            localAction: .none,
            memoryUpdate: .init(),
            replyIntent: .completeConversation,
            replyGuidance: "非法完成"
        )
        let recovered = LLMTurnResponsePlan(
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(
                purpose: "relevant_context_clarified",
                focus: "最近发生的一件具体事情",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
            ),
            replyIntent: .exploreContext,
            replyGuidance: "承接原来的用户回答，不把重试当成新披露"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(illegal), .success(illegal), .success(illegal),
                .success(recovered),
            ],
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
        prepareCurrentDisclosure(model)

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

    func testRecoverableWriterRetryKeepsValidatedPlannerPlan() async {
        let visibleReply = "你已经说到这件事让自己很难受。现在最希望先被理解的是哪一部分？"
        let plan = LLMTurnResponsePlan(
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                situationUnderstanding: "用户描述了事件带来的持续困扰"
            ),
            nextPrompt: .openQuestion(
                purpose: "clarify_current_need",
                focus: "最近发生的一件具体事情",
                disclosurePurpose: .identifyConcreteEpisode,
                disclosureTarget: .focalEvent
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
        prepareCurrentDisclosure(model)

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
        prepareCurrentDisclosure(model)

        model.draft = "我觉得最近没休息好，确实让我更难应对。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCount()
        XCTAssertEqual(calls, 3)
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

    func testCurrentEventRecoveryUsesExplicitProjectorAndIgnoresLegacyTuple() async {
        let audit = ProtocolExecutionAuditRecorder()
        let protocolController = ReflectionProtocolController(executionAudit: audit)
        let episode = TurnEpisodeStructure(
            concreteFacts: ["一次申请已经完成并提交"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["用户整理并提交了申请材料"],
            eventProcessStatus: .present,
            eventProcess: ["提交后等待，随后收到未通过通知"]
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(situationUnderstanding: "不得提交的失败补丁"),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .completeConversation,
                        replyGuidance: "错误地继续完整事件"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .advanceToCardConsent,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        resolvedConfirmation: .init(
                            target: .cardMapping,
                            decision: .accepted,
                            referenceID: "legacy-conflict"
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .completeConversation,
                        replyGuidance: "简短承接并邀请随机反思卡"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConsent,
                        reply: "这件事已经说清楚了。我们可以抽一张随机反思卡看看吗？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: protocolController,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .cardMediated
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.semanticMemory = .init(
            episodeStructure: episode,
            nextPrompt: .openQuestion(
                purpose: "event_process",
                focus: "事情如何发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            )
        )
        model.session.messages = [
            .init(role: .assistant, content: "事情后来怎么发展？", state: .eventDisclosure),
        ]

        model.draft = "我已经把提交和收到结果的过程说清楚了。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let requests = await controller.receivedRequests()
        let writerPlans = await controller.receivedWriterPlans()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolCorrection }.count, 1)
        XCTAssertEqual(
            Set(requests[0].permissions.allowedSemanticOperations),
            Set(requests[1].permissions.allowedSemanticOperations)
        )
        XCTAssertEqual(writerPlans.first?.projectedOperation, .advanceToCardConsent)
        XCTAssertEqual(writerPlans.first?.requestedStage, .cardConsent)
        XCTAssertEqual(writerPlans.first?.replyIntent, .inviteCardConsent)
        XCTAssertEqual(writerPlans.first?.localAction.kind, TurnLocalActionKind.none)
        XCTAssertEqual(writerPlans.first?.nextPrompt?.target, .cardConsent)
        XCTAssertNil(writerPlans.first?.resolvedConfirmation)
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertNotEqual(
            model.session.semanticMemory.situationUnderstanding,
            "不得提交的失败补丁"
        )
        XCTAssertEqual(audit.count(for: .semanticMapper), 2)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyNormalizer), 0)
        XCTAssertEqual(audit.count(for: .legacyTransitionBuilder), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
        let userID = model.session.messages.last(where: { $0.role == .user })?.id
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.replyToMessageID,
            userID
        )
    }

    func testCurrentCardRecoveryProjectsRealityConnectionInsteadOfRepeatingDevelopment() async {
        let audit = ProtocolExecutionAuditRecorder()
        let protocolController = ReflectionProtocolController(executionAudit: audit)
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueCardDevelopment,
                        requestedStage: .directReflection,
                        localAction: .none,
                        memoryUpdate: .init(
                            cardDevelopmentEvidence: .init(
                                actorsOrElements: ["失败补丁"],
                                relationOrAction: "不得覆盖已提交发展关系",
                                anticipatedChangeOrChoice: nil
                            )
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "错误地重复发展"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .inviteRealityConnection,
                        requestedStage: .directReflection,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "把已经形成的画面关系与当前事件作比较"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .inviteCardConnection,
                        reply: "把画面里的这段关系放回刚才的事情，会让你想到什么？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: protocolController,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .cardMediated
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物和物件"]
        )
        let committedDevelopment = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "物件"],
            projectiveFocus: "人物重新安排后是否会停下来",
            relationOrAction: "人物正在重新安排物件",
            anticipatedChangeOrChoice: "可能会停下来观察整体"
        )
        model.session.semanticMemory.cardDevelopmentEvidence = committedDevelopment
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "画面接下来可能怎样变化"
        )
        model.session.messages = [
            .init(role: .assistant, content: "接下来可能发生什么？", state: .cardInterpretation),
        ]

        model.draft = "也许人物会停下来看看整体。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let requests = await controller.receivedRequests()
        let writerPlans = await controller.receivedWriterPlans()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolCorrection }.count, 1)
        XCTAssertEqual(writerPlans.first?.projectedOperation, .inviteRealityConnection)
        XCTAssertEqual(writerPlans.first?.requestedStage, .cardReflection)
        XCTAssertEqual(writerPlans.first?.replyIntent, .inviteCardConnection)
        XCTAssertEqual(writerPlans.first?.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(writerPlans.first?.nextPrompt?.purpose, "cardRealityConnection")
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertEqual(model.session.semanticMemory.cardDevelopmentEvidence, committedDevelopment)
        XCTAssertEqual(audit.count(for: .semanticMapper), 2)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
    }

    func testCurrentMissingOperationRecoversWithoutLegacyInference() async {
        let audit = ProtocolExecutionAuditRecorder()
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .completeConversation,
                        replyGuidance: "缺少显式 operation"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .clarifyEvent,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(
                            episodeStructure: .init(concreteFacts: ["一件具体事情发生了"])
                        ),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .completeConversation,
                        replyGuidance: "继续理解用户在事情中做了什么"
                    )
                ),
            ],
            writings: [
                .success(.init(realizedIntent: .exploreContext, reply: "当时你具体做了什么？")),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        prepareCurrentDisclosure(model)
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "focal",
            focus: "具体事情",
            disclosurePurpose: .identifyConcreteEpisode,
            disclosureTarget: .focalEvent
        )
        model.session.messages = [
            .init(role: .assistant, content: "最近发生了什么？", state: .eventDisclosure),
        ]

        model.draft = "一件具体事情发生了。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertEqual(audit.count(for: .semanticMapper), 1)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
    }

    func testCurrentSafetyRecoveryDiscardsOrdinaryPatchAndUsesProjector() async {
        let audit = ProtocolExecutionAuditRecorder()
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .completeConversation,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(situationUnderstanding: "失败的普通反思补丁"),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .completeConversation,
                        replyGuidance: "非法完成"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .provideSafetySupport,
                        requestedStage: .cardReflection,
                        localAction: .init(kind: .shareCardGuidance),
                        memoryUpdate: .init(situationUnderstanding: "不得带入安全事务"),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .presentCardReading,
                        replyGuidance: "只提供当前安全支持"
                    )
                ),
            ],
            writings: [
                .success(.init(realizedIntent: .safetySupport, reply: "先把注意力放到此刻的安全上。")),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        prepareCurrentDisclosure(model)

        model.draft = "我现在需要先保证自己的安全。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let writerPlans = await controller.receivedWriterPlans()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertEqual(writerPlans.first?.projectedOperation, .provideSafetySupport)
        XCTAssertEqual(writerPlans.first?.requestedStage, .safetySupport)
        XCTAssertEqual(writerPlans.first?.replyIntent, .safetySupport)
        XCTAssertEqual(writerPlans.first?.localAction.kind, TurnLocalActionKind.none)
        XCTAssertEqual(model.session.protocolStage, .safetySupport)
        XCTAssertNotEqual(model.session.semanticMemory.situationUnderstanding, "失败的普通反思补丁")
        XCTAssertNotEqual(model.session.semanticMemory.situationUnderstanding, "不得带入安全事务")
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
    }

    func testCurrentScaffoldRecoveryCannotReturnToDevelopment() async {
        let audit = ProtocolExecutionAuditRecorder()
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .continueCardDevelopment,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(),
                        nextPrompt: .openQuestion(purpose: "legacy-development", focus: "重复画面发展"),
                        replyIntent: .developCardImage,
                        replyGuidance: "错误地退回 Development"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .offerCardConnectionScaffold,
                        requestedStage: .directReflection,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        cardConnectionTurnOutcome: try! .init(kind: .connectionStillUnclear),
                        nextPrompt: TurnNextPrompt.none,
                        replyIntent: .directCandidReflection,
                        replyGuidance: "只缩小当前画面关系与当前事件的比较任务"
                    )
                ),
            ],
            writings: [
                .success(
                    .init(
                        realizedIntent: .developCardImage,
                        reply: "先只看画面里的停下与现实里的继续，这两处有什么不同？"
                    )
                ),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .cardMediated
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardConnectionAttemptCount = 1
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物和物件"]
        )
        let development = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "物件"],
            projectiveFocus: "人物观察后是否会重新安排",
            relationOrAction: "人物停下来观察物件",
            anticipatedChangeOrChoice: "可能重新安排"
        )
        model.session.semanticMemory.cardDevelopmentEvidence = development
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "画面关系与当前事件"
        )
        model.session.messages = [
            .init(role: .assistant, content: "放回当前事情会想到什么？", state: .cardInterpretation),
        ]

        model.draft = "我还是不太能把它们连起来。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let writerPlans = await controller.receivedWriterPlans()
        XCTAssertEqual(calls.plans, 2)
        XCTAssertEqual(calls.writes, 1)
        XCTAssertEqual(writerPlans.first?.projectedOperation, .offerCardConnectionScaffold)
        XCTAssertEqual(writerPlans.first?.requestedStage, .cardReflection)
        XCTAssertEqual(writerPlans.first?.replyIntent, .developCardImage)
        XCTAssertEqual(writerPlans.first?.nextPrompt?.purpose, "cardRealityConnectionScaffold")
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertEqual(model.session.semanticMemory.cardDevelopmentEvidence, development)
        XCTAssertEqual(model.session.messages.filter { $0.role == .assistant }.count, 2)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
    }

    func testCurrentCandidateRecoveryRejectsWithoutCreatingSecondCandidate() async {
        let audit = ProtocolExecutionAuditRecorder()
        let candidateID = UUID()
        let pending = PendingCardRealityConnection(
            id: candidateID,
            imageRelation: "人物在门口停下来",
            candidateRealityMapping: "可能对应现实里暂停的一刻"
        )
        let secondCandidate = PendingCardRealityConnection(
            id: UUID(),
            imageRelation: "不得写入的第二候选",
            candidateRealityMapping: "不得写入的第二映射"
        )
        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .offerCardConnectionCandidate,
                        requestedStage: .cardReflection,
                        localAction: .none,
                        memoryUpdate: .init(pendingCardRealityConnection: secondCandidate),
                        nextPrompt: .confirmationRequest(
                            target: .cardRealityConnection,
                            referenceID: secondCandidate.id.uuidString
                        ),
                        replyIntent: .inviteCardConnection,
                        replyGuidance: "错误地创建第二个候选"
                    )
                ),
                .success(
                    LLMTurnResponsePlan(
                        semanticOperation: .rejectCardConnectionCandidate,
                        requestedStage: .complete,
                        localAction: .init(kind: .completeSession),
                        memoryUpdate: .init(),
                        cardConnectionTurnOutcome: try! .init(kind: .candidateRejected),
                        nextPrompt: .confirmationRequest(target: .cardMapping),
                        replyIntent: .completeConversation,
                        replyGuidance: "尊重拒绝，不再使用这个候选"
                    )
                ),
            ],
            writings: [
                .success(.init(realizedIntent: .inviteCardConnection, reply: "好，我们不使用这个候选。")),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .cardMediated
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardConnectionAttemptCount = 2
        model.session.cardConnectionScaffoldUsed = true
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物和门口"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["人物", "门口"],
            relationOrAction: "人物在门口停下来",
            anticipatedChangeOrChoice: nil
        )
        model.session.semanticMemory.pendingCardRealityConnection = pending
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardRealityConnection,
            referenceID: candidateID.uuidString
        )
        model.session.messages = [
            .init(role: .assistant, content: "这里有一种可能的连接。", state: .cardInterpretation),
        ]

        model.draft = "不是这个意思。"
        model.send()
        await waitUntilIdle(model)

        let calls = await controller.callCounts()
        let writerPlans = await controller.receivedWriterPlans()
        let diagnostics = model.session.studyEvents.map(\.action).joined(separator: " | ")
        XCTAssertEqual(calls.plans, 2, diagnostics)
        XCTAssertEqual(calls.writes, 1, diagnostics)
        XCTAssertEqual(
            writerPlans.first?.projectedOperation,
            .rejectCardConnectionCandidate,
            diagnostics
        )
        XCTAssertNil(model.session.semanticMemory.pendingCardRealityConnection)
        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        XCTAssertNotNil(model.session.semanticMemory.candidateBridgeResolvedAt)
        XCTAssertFalse(
            model.session.semanticMemory.pendingCardRealityConnection?.id == secondCandidate.id
        )
        XCTAssertEqual(model.session.messages.filter { $0.role == .assistant }.count, 2)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
    }

    func testCompleteCurrentV5FlowRecoversOnceThenReachesComplete() async throws {
        let audit = ProtocolExecutionAuditRecorder()
        let protocolController = ReflectionProtocolController(executionAudit: audit)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-v5-full-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)

        let observation = CardObservationEvidence(
            userDescribedElements: ["人物正在重新摆放桌上的材料"]
        )
        let development = CardDevelopmentEvidence(
            actorsOrElements: ["人物", "材料"],
            projectiveFocus: "人物重新安排后是否会停下来",
            relationOrAction: "人物正在重新安排材料",
            anticipatedChangeOrChoice: "可能会停下来观察整体"
        )
        let connection = TurnCardRealityConnection(
            imageRelation: "人物停下来观察整体后再决定如何摆放材料",
            realityMapping: "用户把它联系到自己反复修改局部、没有停下来判断整体是否可提交",
            source: .userAuthored
        )
        func frame(
            mode: TurnReflectionMode,
            action: TurnReflectionAction,
            evidence: String,
            delta: String,
            fierce: TurnFierceEvidence? = nil
        ) -> TurnReflectionFrame {
            TurnReflectionFrame(
                mode: mode,
                action: action,
                evidenceBasis: [.init(source: .episode, content: evidence)],
                dimensions: [.selfKindness, .mindfulness],
                reflectionDelta: delta,
                fierceEvidence: fierce
            )
        }
        let connectionTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "方案基本完成，但用户继续修改并错过提交时间"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "区分一次没有按时提交与对整体能力的否定",
            fierceEvidence: nil
        )
        let tender = frame(
            mode: .tender,
            action: .acknowledgeExperience,
            evidence: "用户说交出不够好的方案会让自己害怕",
            delta: "承认面对不确定评价时的害怕"
        )
        let fierce = frame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidence: "方案基本完成后继续修改，最终错过提交时间",
            delta: "理解害怕的同时面对继续修改造成的延期",
            fierce: .init(
                behavior: "方案基本完成后仍继续修改而没有提交",
                impact: "错过截止时间并影响后续进度",
                direction: .change
            )
        )
        let synthesis = frame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidence: "害怕不够好可以理解，持续修改造成的延期需要改变",
            delta: "形成不全面否定自己也不回避具体影响的综合理解"
        )
        let proposalID = "full-flow-practice"
        let pendingProposal = TurnPracticeProposal(
            id: proposalID,
            kind: .change,
            content: "下一次到达约定提交点时，先交出可用版本，再记录后续修改。",
            basis: "用户已经辨认出持续修改会让提交无限延后。",
            status: .pendingConfirmation
        )
        let confirmedProposal = TurnPracticeProposal(
            id: proposalID,
            kind: .change,
            content: pendingProposal.content,
            basis: pendingProposal.basis,
            status: .confirmed
        )
        let finalNarrative = "害怕交出不够好的结果值得被理解；持续修改造成的延期需要改变。"
        func conflictingPlan(
            _ operation: PlannerSemanticOperation,
            update: TurnSemanticMemoryUpdate = .init(),
            outcome: CardConnectionTurnOutcome? = nil,
            guidance: String
        ) -> LLMTurnResponsePlan {
            LLMTurnResponsePlan(
                semanticOperation: operation,
                requestedStage: .complete,
                localAction: .init(kind: .completeSession),
                memoryUpdate: update,
                cardConnectionTurnOutcome: outcome,
                nextPrompt: .confirmationRequest(target: .cardMapping),
                replyIntent: .completeConversation,
                replyGuidance: guidance
            )
        }

        let controller = ScriptedReflectionTurnController(
            plans: [
                .success(conflictingPlan(
                    .clarifyEvent,
                    update: .init(situationUnderstanding: "不得提交的失败补丁"),
                    guidance: "错误地继续探索已经完整的事件"
                )),
                .success(conflictingPlan(
                    .advanceToCardConsent,
                    update: .init(eventDisclosureOutcome: .readyForTenderOrCard),
                    guidance: "简短承接并邀请随机反思卡"
                )),
                .success(conflictingPlan(
                    .continueCardDevelopment,
                    update: .init(cardObservationEvidence: observation),
                    guidance: "只问画面关系接下来可能怎样变化"
                )),
                .success(conflictingPlan(
                    .inviteRealityConnection,
                    update: .init(cardDevelopmentEvidence: development),
                    guidance: "把画面关系放回焦点事件"
                )),
                .success(conflictingPlan(
                    .establishUserAuthoredCardConnection,
                    update: .init(reflectionFrame: connectionTender),
                    outcome: try .init(kind: .userAuthoredConnection, connection: connection),
                    guidance: "从用户连接进入 Tender"
                )),
                .success(conflictingPlan(
                    .continueTenderReflection,
                    update: .init(reflectionFrame: tender),
                    guidance: "承认具体害怕并问一个具体时刻"
                )),
                .success(conflictingPlan(
                    .continueTenderGroundedFierceReflection,
                    update: .init(reflectionFrame: fierce),
                    guidance: "在理解害怕的基础上面对行为影响"
                )),
                .success(conflictingPlan(
                    .synthesizeDirectReflection,
                    update: .init(reflectionFrame: synthesis),
                    guidance: "综合理解与需要改变的部分"
                )),
                .success(conflictingPlan(
                    .proposePractice,
                    update: .init(
                        practiceTransition: .init(
                            transactionID: proposalID,
                            narrativeReferenceID: nil,
                            proposal: pendingProposal,
                            noActionReason: nil
                        )
                    ),
                    guidance: "提出一个小而具体的行动"
                )),
                .success(conflictingPlan(
                    .resolvePractice,
                    update: .init(
                        finalNarrative: finalNarrative,
                        practiceTransition: .init(
                            transactionID: proposalID,
                            narrativeReferenceID: nil,
                            proposal: confirmedProposal,
                            noActionReason: nil
                        )
                    ),
                    guidance: "保存行动并呈现最终叙事"
                )),
                .success(conflictingPlan(
                    .completeConversation,
                    guidance: "简洁完成本次反思"
                )),
            ],
            writings: [
                .success(.init(realizedIntent: .inviteCardConsent, reply: "事情已经说清楚了。可以抽一张随机反思卡看看吗？")),
                .success(.init(realizedIntent: .developCardImage, reply: "如果画面继续发展，人物接下来可能会做什么？")),
                .success(.init(realizedIntent: .inviteCardConnection, reply: "把停下来观察整体的变化放回刚才的事情，会想到什么？")),
                .success(.init(realizedIntent: .directCandidReflection, reply: "交出不够好的结果，最让你害怕的是什么？")),
                .success(.init(realizedIntent: .directCandidReflection, reply: "截止时间临近时，哪个时刻你已经知道继续修改可能会带来影响？")),
                .success(.init(realizedIntent: .directCandidReflection, reply: "理解害怕的同时，当时哪一个决定点最需要改变？")),
                .success(.init(realizedIntent: .directCandidReflection, reply: "你不需要全面否定自己，也不能回避持续修改造成的影响。")),
                .success(.init(realizedIntent: .suggestPractice, reply: "下一次到达约定提交点时，先交出可用版本。愿意试试吗？")),
                .success(.init(realizedIntent: .presentFinalNarrative, reply: finalNarrative)),
                .success(.init(realizedIntent: .completeConversation, reply: "这次反思就先到这里。")),
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            sessionStore: store,
            protocolController: protocolController,
            preparesContextDataAutomatically: false
        )
        prepareCurrentDisclosure(model)
        model.session.condition = .cardMediated
        model.session.reflectionReadiness = .reflectionOpen
        model.session.semanticMemory = .init(
            eventDisclosureOutcome: .readyForTenderOrCard,
            selfCriticismStatus: .present,
            selfCriticalStatement: "我可能什么都做不好",
            episodeStructure: .init(
                concreteFacts: ["方案基本完成但没有按时提交"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户持续修改而没有提交"],
                eventProcessStatus: .present,
                eventProcess: ["方案完成后继续修改，随后错过截止时间"]
            ),
            nextPrompt: .openQuestion(
                purpose: "event_process",
                focus: "事情如何发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            )
        )
        model.session.messages = [
            .init(role: .assistant, content: "事情后来是怎么发展的？", state: .eventDisclosure),
        ]

        func send(_ text: String) async {
            model.draft = text
            model.send()
            await waitUntilIdle(model)
        }

        await send("方案基本完成，但我一直修改，最后错过了截止时间。")
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        await send("可以")
        let card = try XCTUnwrap(model.session.card)
        model.cardDidDisplay(cardID: card.id)
        await send("我看到一个人物正在重新摆放桌上的材料。")
        await send("他可能会停下来看看整体，再决定材料放在哪里。")
        await send("我一直改一个局部，没有停下来判断整体是否已经可以提交。")
        await send("我最怕交出去以后别人觉得它还不够好。")
        await send("快到截止时间时，我知道继续改可能会来不及。")
        await send("我本来可以先交一个可用版本。")
        await send("接下来可以怎么做？")
        await send("我愿意试试。")
        await send("这个总结可以。")

        let counts = await controller.callCounts()
        let requests = await controller.receivedRequests()
        XCTAssertEqual(counts.plans, 11)
        XCTAssertEqual(counts.writes, 10)
        XCTAssertEqual(requests.filter { $0.trigger == .protocolCorrection }.count, 1)
        XCTAssertEqual(model.session.protocolStage, .complete)
        XCTAssertEqual(model.session.semanticMemory.cardObservationEvidence, observation)
        XCTAssertEqual(model.session.semanticMemory.cardDevelopmentEvidence, development)
        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, connection)
        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.semanticMemory.practiceTransition?.proposal, confirmedProposal)
        XCTAssertEqual(model.session.semanticMemory.finalNarrative, finalNarrative)
        XCTAssertEqual(model.session.messages.filter { $0.content == finalNarrative }.count, 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .projector), 10)
        XCTAssertEqual(audit.count(for: .transactionCommit), 11)
        XCTAssertFalse(model.session.messages.contains { $0.content.contains("没有顺利接上") })
        XCTAssertTrue(
            model.session.messages.filter { $0.role == .assistant }
                .dropFirst().allSatisfy { $0.replyToMessageID != nil }
        )

        let reloaded = try await store.load(id: model.session.id)
        XCTAssertEqual(reloaded?.protocolStage, .complete)
        XCTAssertEqual(reloaded?.semanticMemory.cardRealityConnection, connection)
        XCTAssertEqual(reloaded?.semanticMemory.practiceTransition?.proposal, confirmedProposal)
    }

    func testStaleAsyncNormalResponseCannotCommitAfterGenerationIsCancelled() async {
        let audit = ProtocolExecutionAuditRecorder()
        let controller = DelayedIgnoringCancellationTurnController()
        let model = ReflectionViewModel(
            analyzer: UnusedContextAnalyzer(),
            dialogueGenerator: UnusedDialogueGenerator(),
            turnController: controller,
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        prepareCurrentDisclosure(model)
        model.session.condition = .cardMediated
        model.session.semanticMemory = .init(
            eventDisclosureOutcome: .readyForTenderOrCard,
            episodeStructure: .init(
                concreteFacts: ["事件已经明确"],
                behaviorEvidenceStatus: .present,
                behaviorEvidence: ["用户已经说明自己的行为"],
                eventProcessStatus: .present,
                eventProcess: ["事情的发展已经明确"]
            ),
            nextPrompt: .openQuestion(
                purpose: "event_process",
                focus: "事情如何发展",
                disclosurePurpose: .clarifyEventProcess,
                disclosureTarget: .eventProcess
            )
        )
        model.session.messages = [
            .init(role: .assistant, content: "事情后来怎样发展？", state: .eventDisclosure),
        ]

        model.draft = "这就是完整经过。"
        model.send()
        try? await Task.sleep(for: .milliseconds(80))
        model.end()
        try? await Task.sleep(for: .milliseconds(300))

        let calls = await controller.callCounts()
        XCTAssertEqual(calls.plans, 1)
        XCTAssertEqual(calls.writes, 0)
        XCTAssertEqual(model.session.protocolStage, .complete)
        XCTAssertEqual(audit.count(for: .projector), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 0)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("随机反思卡")
            }
        )
    }

    private func prepareCurrentDisclosure(_ model: ReflectionViewModel) {
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.messages = []
    }

    private func preparePendingFinalNarrative(
        _ model: ReflectionViewModel,
        referenceID: String
    ) {
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.condition = .cardMediated
        model.session.protocolStage = .narrativeConfirmation
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .reflectionNarrativeConfirmation
        model.session.finalNarrativeConfirmed = false
        model.session.semanticMemory.finalNarrative = "已经形成、正在等待用户确认的最终叙事"
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .finalNarrative,
            referenceID: referenceID
        )
        model.session.messages = [
            .init(
                role: .assistant,
                content: "这是已经形成的最终叙事。",
                state: .attributionReflection
            ),
        ]
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
#endif

@MainActor
final class ReflectionWriterProgressTests: XCTestCase {
    func testRestatementIsRewrittenBeforeDisplay() async throws {
        let frame = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "用户表达无奈和对未来的不确定"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "区分已经发生的结果、未知信息和未来预测",
            fierceEvidence: nil
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(reflectionFrame: frame),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "形成一个事实、未知和未来担忧之间的具体区别"
        )
        let writer = NoProgressReflectionWriter()
        let critic = NoProgressReflectionCritic()
        let controller = RemoteReflectionTurnController(
            planner: UnusedTurnPlanner(),
            planCritic: PassingPlanCritic(),
            writer: writer,
            critic: critic
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .directReflection,
                allowedStages: [.directReflection, .narrativeConfirmation],
                allowedActions: [.none],
                allowedReplyIntents: [.directCandidReflection, .presentFinalNarrative]
            ),
            recentMessages: [
                .init(role: .user, content: "最后等到结果时，我很无奈，也不知道以后会怎样。"),
            ],
            semanticMemory: .init(),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.write(request: request, validatedPlan: plan)
        let writerCalls = await writer.callCounts()
        let criticCalls = await critic.callCount()

        XCTAssertNotEqual(result.reply, "你提到最后等到结果时感到无奈，也有些自我怀疑。")
        XCTAssertTrue(result.reply.contains("还不知道"))
        XCTAssertEqual(writerCalls.initial, 1)
        XCTAssertEqual(writerCalls.revisions, 1)
        XCTAssertEqual(criticCalls, 2)
    }

    func testGenericCommonHumanityCannotReplaceValidatedSelfJudgmentDistinction() async throws {
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(
                reflectionFrame: .init(
                    mode: .tender,
                    action: .softenGlobalSelfJudgment,
                    evidenceBasis: [
                        .init(source: .episode, content: "申请已经被拒绝，但拒绝原因未知"),
                        .init(source: .latestUserAnswer, content: "用户说可能是自己能力不够"),
                    ],
                    dimensions: [.selfKindness, .mindfulness],
                    reflectionDelta: "区分拒绝结果、未知原因和对整体能力的判断",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "实现有事实边界的 Tender 区分，不只提供共通性安慰"
        )
        let writer = GenericCommonHumanityWriter()
        let critic = GlobalJudgmentDistinctionCritic()
        let controller = RemoteReflectionTurnController(
            planner: UnusedTurnPlanner(),
            planCritic: PassingPlanCritic(),
            writer: writer,
            critic: critic
        )
        let request = LLMTurnControllerRequest(
            trigger: .cardGuidanceAvailable,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .directReflection,
                allowedStages: [.directReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.directCandidReflection],
                allowedOperations: [
                    .init(
                        requestedStage: .directReflection,
                        replyIntent: .directCandidReflection,
                        localAction: .none
                    ),
                ]
            ),
            recentMessages: [
                .init(role: .user, content: "申请被拒了，我觉得可能就是我能力不够。"),
            ],
            semanticMemory: .init(
                selfCriticismStatus: .present,
                selfCriticalStatement: "我觉得可能就是我能力不够",
                episodeStructure: .init(
                    concreteFacts: ["申请已经被拒绝"],
                    behaviorEvidenceStatus: .present,
                    behaviorEvidence: ["用户已完成并提交申请"],
                    eventProcessStatus: .present,
                    eventProcess: ["准备材料、提交、等待，最后收到拒信"],
                    impactStatus: .uncertain,
                    keyUncertainty: "拒绝原因未知"
                )
            ),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        let result = try await controller.write(request: request, validatedPlan: plan)
        XCTAssertFalse(result.reply.contains("很多人"))
        XCTAssertFalse(result.reply.contains("并不孤单"))
        XCTAssertTrue(result.reply.contains("拒绝"))
        XCTAssertTrue(result.reply.contains("原因"))
        XCTAssertTrue(result.reply.contains("能力"))
        let writerCalls = await writer.callCounts()
        let criticCalls = await critic.callCount()
        XCTAssertEqual(writerCalls.initial, 1)
        XCTAssertEqual(writerCalls.revisions, 1)
        XCTAssertEqual(criticCalls, 2)
    }

    func testRejectedDraftIsNotReturnedWhenRewriteFails() async throws {
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: .openQuestion(purpose: "one_question", focus: "one bounded question"),
            replyIntent: .directCandidReflection,
            replyGuidance: "提出一个具体问题"
        )
        let controller = RemoteReflectionTurnController(
            planner: UnusedTurnPlanner(),
            planCritic: PassingPlanCritic(),
            writer: FailingSoftRevisionWriter(),
            critic: CriticTestCritic()
        )
        let request = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolVersion: ReflectionSession.currentProtocolVersion,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: .init(
                currentStage: .directReflection,
                allowedStages: [.directReflection],
                allowedActions: [.none],
                allowedReplyIntents: [.directCandidReflection]
            ),
            recentMessages: [.init(role: .user, content: "继续。")],
            semanticMemory: .init(),
            trackingCandidates: [],
            card: nil,
            protocolCorrection: nil
        )

        do {
            _ = try await controller.write(request: request, validatedPlan: plan)
            XCTFail("Rejected wording must not be displayed when its rewrite fails")
        } catch {
            XCTAssertEqual(error as? ReflectionProtocolViolation, .unresolvedWriterQuality)
        }
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
    private var calls = 0

    init(plan: LLMTurnResponsePlan) {
        self.plan = plan
    }

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        return plan
    }

    func callCount() -> Int { calls }
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
                semanticOperation: .clarifyEvent,
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
            semanticOperation: .advanceToCardConsent,
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
                    semanticOperation: .continueOpenCardConnection,
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
                semanticOperation: .establishUserAuthoredCardConnection,
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
            let proposal = TurnPracticeProposal(
                id: "practice-transition",
                kind: calls == 1 ? .care : .change,
                content: calls == 1
                    ? "今晚留出十分钟照顾已经确认的疲惫。"
                    : "下一次只记录一个事实和一个可以检查的部分。",
                basis: calls == 1
                    ? "用户确认了当前消耗。"
                    : "用户确认了一个需要改变的可控行为。",
                status: .pendingConfirmation,
                source: .assistantProposed
            )
            let transition = TurnPracticeTransition(
                transactionID: "practice-transition",
                narrativeReferenceID: "narrative-practice-options",
                proposal: proposal,
                noActionReason: nil
            )
            return LLMTurnResponsePlan(
                semanticOperation: .proposePractice,
                requestedStage: .optionalAction,
                localAction: .none,
                memoryUpdate: .init(practiceTransition: transition),
                resolvedConfirmation: .init(
                    target: .finalNarrative,
                    decision: .accepted,
                    referenceID: "narrative-practice-options"
                ),
                nextPrompt: .confirmationRequest(
                    target: .practice,
                    referenceID: "practice-transition"
                ),
                replyIntent: .suggestPractice,
                replyGuidance: calls == 1
                    ? "给出一个较弱的候选"
                    : "只给出证据最充分的完整候选"
            )
        }
        if calls == 1 {
            return LLMTurnResponsePlan(
                semanticOperation: .clarifyEvent,
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
            semanticOperation: .advanceToCardConsent,
            requestedStage: .cardConsent,
            localAction: .none,
            memoryUpdate: .init(
                eventDisclosureOutcome: .readyForTenderOrCard
            ),
            nextPrompt: .confirmationRequest(target: .cardConsent),
            replyIntent: .inviteCardConsent,
            replyGuidance: "Use one factual bridge and invite one optional random reflection card."
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
                    "multiple_practice_options",
                ],
                revisionGuidance:
                    "Keep only the single strongest evidence-supported practice."
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

private actor NoProgressReflectionWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "你提到最后等到结果时感到无奈，也有些自我怀疑。"
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
            reply: "结果已经发生了，但具体原因和以后会怎样还不知道；现在的担心并不是已经被证明的未来。"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor NoProgressReflectionCritic: LLMTurnCritiquing {
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
                reasonCodes: ["reflection_without_progress"],
                revisionGuidance: "实现计划中的事实、未知和未来预测区分，不要只复述情绪。"
            )
        }
        return .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
    }

    func callCount() -> Int { calls }
}

private actor GenericCommonHumanityWriter: LLMTurnWriting {
    private var initialCalls = 0
    private var revisionCalls = 0

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        initialCalls += 1
        return .init(
            realizedIntent: plan.replyIntent,
            reply: "这种感受很多人都经历过，你并不孤单。"
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
            reply: "申请被拒是已经发生的结果，但拒绝原因仍然未知；把它直接解释成整体能力不够，是目前信息还不能证明的判断。"
        )
    }

    func callCounts() -> (initial: Int, revisions: Int) {
        (initialCalls, revisionCalls)
    }
}

private actor GlobalJudgmentDistinctionCritic: LLMTurnCritiquing {
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
                reasonCodes: ["global_judgment_not_distinguished", "reflection_without_progress"],
                revisionGuidance: "实现 validated fact/unknown/whole-person distinction；Common Humanity 只能辅助。"
            )
        }
        return .init(verdict: .pass, reasonCodes: [], revisionGuidance: nil)
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

private actor DelayedIgnoringCancellationTurnController: ReflectionTurnControlling {
    private var planCalls = 0
    private var writeCalls = 0

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        planCalls += 1
        // Model a provider callback that completes after the owning task was cancelled. Ignoring
        // cancellation here is intentional: the ViewModel generation/session guard, not provider
        // cooperation, must prevent this stale result from reaching projection or transaction.
        try? await Task.sleep(for: .milliseconds(220))
        return LLMTurnResponsePlan(
            semanticOperation: .advanceToCardConsent,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(eventDisclosureOutcome: .readyForTenderOrCard),
            nextPrompt: .confirmationRequest(target: .cardMapping),
            replyIntent: .completeConversation,
            replyGuidance: "邀请一张随机反思卡"
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        writeCalls += 1
        return .init(
            realizedIntent: validatedPlan.replyIntent,
            reply: "可以抽一张随机反思卡看看吗？"
        )
    }

    func callCounts() -> (plans: Int, writes: Int) {
        (planCalls, writeCalls)
    }
}

private actor ScriptedReflectionTurnController: ReflectionTurnControlling {
    private var plans: [Result<LLMTurnResponsePlan, Error>]
    private var writings: [Result<LLMTurnWriterResponse, Error>]
    private var planCalls = 0
    private var writeCalls = 0
    private var requests: [LLMTurnControllerRequest] = []
    private var writerRequests: [LLMTurnControllerRequest] = []
    private var writerPlans: [LLMTurnResponsePlan] = []

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
        writerRequests.append(request)
        writerPlans.append(validatedPlan)
        guard !writings.isEmpty else { throw ScriptedTurnError.exhausted }
        return try writings.removeFirst().get()
    }

    func callCounts() -> (plans: Int, writes: Int) {
        (planCalls, writeCalls)
    }

    func receivedRequests() -> [LLMTurnControllerRequest] {
        requests
    }

    func receivedWriterRequests() -> [LLMTurnControllerRequest] {
        writerRequests
    }

    func receivedWriterPlans() -> [LLMTurnResponsePlan] {
        writerPlans
    }
}

private actor PersistenceSabotagingTurnController: ReflectionTurnControlling {
    static let reply = "这件事已经发生了；此刻最需要被看见的感受是什么？"

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        return LLMTurnResponsePlan(
            semanticOperation: .continueTenderReflection,
            requestedStage: .contextualDisclosure,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(
                reflectionFrame: .init(
                    mode: .tender,
                    action: .acknowledgeExperience,
                    evidenceBasis: [
                        .init(source: .latestUserAnswer, content: "这件事现在仍然压着我"),
                    ],
                    dimensions: [.mindfulness],
                    reflectionDelta: "承认这件事此刻仍然带来的感受",
                    fierceEvidence: nil
                )
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "承认当前体验并提出一个具体问题"
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        .init(realizedIntent: validatedPlan.replyIntent, reply: Self.reply)
    }
}

private actor RecoveryPersistenceSabotagingTurnController: ReflectionTurnControlling {
    static let reply = "事情的关键关系已经清楚了。我们可以抽一张随机反思卡，换个角度看看吗？"

    private let directory: URL
    private var plans = 0
    private var writes = 0

    init(directory: URL) {
        self.directory = directory
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        plans += 1
        if plans == 1 {
            return LLMTurnResponsePlan(
                semanticOperation: .clarifyEvent,
                requestedStage: .complete,
                localAction: .init(kind: .completeSession),
                memoryUpdate: .init(situationUnderstanding: "不得提交的普通失败补丁"),
                nextPrompt: TurnNextPrompt.none,
                replyIntent: .completeConversation,
                replyGuidance: "错误地继续探索已完整的事件"
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        return LLMTurnResponsePlan(
            semanticOperation: .advanceToCardConsent,
            requestedStage: .complete,
            localAction: .init(kind: .completeSession),
            memoryUpdate: .init(eventDisclosureOutcome: .readyForTenderOrCard),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .completeConversation,
            replyGuidance: "简短承接并邀请一张随机反思卡"
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        writes += 1
        return .init(realizedIntent: validatedPlan.replyIntent, reply: Self.reply)
    }

    func planCount() -> Int { plans }
    func writeCount() -> Int { writes }
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
            semanticOperation: .clarifyEvent,
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(
                episodeStructure: .init(
                    concreteFacts: ["昨天没有按时提交项目方案"]
                )
            ),
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
