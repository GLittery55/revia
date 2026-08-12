import XCTest
@testable import BeyondComfort

@MainActor
final class CurrentV5CoreExecutionTests: XCTestCase {
    func testVisualScaffoldIsVisibleOnlyToItsAuthorizedPlannerAndWriterAct() throws {
        let scaffold = CardVisualScaffold(
            requiredAnchorGroups: [["门"], ["便签"]],
            question: "门暂时关着，旁边留下的联系入口让这个独处有什么范围？"
        )
        let card = LLMTurnCardContext(
            imageIsDisplayed: true,
            imageDevelopmentTurnCount: 1,
            realityAnchor: .init(
                concreteFacts: ["汇报时放错旧版本图片"],
                eventProcess: ["发现后立即换回新版"],
                impacts: []
            ),
            visualScaffolds: [scaffold],
            reflectionApproaches: nil,
            prohibitedClaims: []
        )
        let session = currentCardReflectionSession()
        let base = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .cardReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            card: card,
            protocolCorrection: nil
        )

        for operation in [
            PlannerSemanticOperation.continueCardObservation,
            .continueCardDevelopment,
            .inviteRealityConnection,
        ] {
            let request = CurrentV5TurnRequest(
                base: base,
                messages: [],
                allowedSemanticOperations: [operation]
            )
            XCTAssertEqual(request.card?.visualScaffolds, [])
            let encoded = try JSONEncoder().encode(request)
            XCTAssertFalse(
                String(decoding: encoded, as: UTF8.self).contains(scaffold.question)
            )
        }

        let connectionRequest = CurrentV5TurnRequest(
            base: base,
            messages: [],
            allowedSemanticOperations: [
                .offerCardConnectionScaffold,
                .continueOpenCardConnection,
            ]
        )
        XCTAssertEqual(connectionRequest.card?.visualScaffolds, [scaffold])
        XCTAssertEqual(
            connectionRequest
                .scopedForWriter(operation: .continueOpenCardConnection)
                .card?.visualScaffolds,
            []
        )
        XCTAssertEqual(
            connectionRequest
                .scopedForWriter(operation: .offerCardConnectionScaffold)
                .card?.visualScaffolds,
            [scaffold]
        )
        let ordinaryWriterRequest = connectionRequest
            .scopedForWriter(operation: .continueOpenCardConnection)
        XCTAssertFalse(
            String(
                decoding: try JSONEncoder().encode(ordinaryWriterRequest),
                as: UTF8.self
            ).contains(scaffold.question)
        )
        let scaffoldWriterRequest = connectionRequest
            .scopedForWriter(operation: .offerCardConnectionScaffold)
        XCTAssertTrue(
            String(
                decoding: try JSONEncoder().encode(scaffoldWriterRequest),
                as: UTF8.self
            ).contains(scaffold.question)
        )
    }

    func testCurrentSessionUsesOnlyCorePlannerGateWriterAndCommit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-core-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let audit = ProtocolExecutionAuditRecorder()
        let legacy = RejectingLegacyTurnController()
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .advanceToCardConsent,
                    semanticEvidencePatch: .init(),
                    responseFocus: "简短承接已经清楚的事件并邀请一张随机反思卡"
                ),
            ],
            replies: ["事情怎么发生的已经说清楚了。我们可以抽一张随机反思卡看看吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: legacy,
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = completeEpisode

        model.draft = "我想先停在这里。"
        model.send()
        await waitUntilIdle(model)

        let corePlanCalls = await core.planCount()
        let coreWriteCalls = await core.writeCount()
        let legacyPlanCalls = await legacy.planCount()
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(corePlanCalls, 1)
        XCTAssertEqual(coreWriteCalls, 1)
        XCTAssertEqual(legacyPlanCalls, 0)
        XCTAssertEqual(audit.count(for: .semanticMapper), 1)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .silentContinuation), 0)
        XCTAssertEqual(audit.count(for: .transactionCommit), 1)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("coarse_protocol_typed_recovery")
                    || $0.action.contains("response_failed_twice")
            }
        )
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "事情怎么发生的已经说清楚了。我们可以抽一张随机反思卡看看吗？"
        )
    }

    func testMissingAtomicSynthesisDeltaIsRepairedWithoutVisibleInterruption() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-atomic-synthesis-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthesis = "协议反复中断确实让项目难以推进，但这段受阻不足以单独确定整体开发能力"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "只有展示目标，没有可提交的综合",
                    reflectionProgressionDecision: .init(
                        meaning: .synthesize,
                        candidateRef: nil
                    )
                ),
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "自然呈现原子提交的综合",
                    reflectionProgressionDecision: .init(
                        meaning: .synthesize,
                        candidateRef: nil,
                        reflectionDelta: synthesis
                    )
                ),
            ],
            replies: ["协议确实反复中断，项目也没有顺利推进；但这段受阻还不足以单独说明整体开发能力。这个总结需要调整吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "协议反复中断，项目没有推进")],
            dimensions: [.mindfulness],
            reflectionDelta: "协议反复中断是当前困难，不能单独确定整体开发能力",
            fierceEvidence: nil
        )

        model.draft = "我觉得挺对的。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let recordedCorrection = await core.correctionForPlan(at: 1)
        XCTAssertEqual(planCount, 2)
        let correction = try XCTUnwrap(recordedCorrection)
        XCTAssertEqual(correction.rejectedOperation, .synthesizeDirectReflection)
        XCTAssertEqual(correction.projectionFailure, .synthesisFrameMissing)
        XCTAssertEqual(
            correction.issue.fieldPath,
            "reflectionProgressionDecision.reflectionDelta"
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.reflectionDelta, synthesis)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("刚才没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
            }
        )
    }

    func testExplorationCorrectionUsesCumulativeEvidenceAndCommitsAtomicOutcome() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-exploration-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let link = "说了伤人的话并让关系陷入冷战后，主要责怪自己造成了这些具体影响 -> 我感觉很自责"
        let tender = "说出的内容和已经造成的关系影响需要认真面对；当前自责可以先停留在这次具体行为和影响上"
        let repair = "希望结束冷战，通过沟通解决问题"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            episodeStructure: .init(controllableParts: [repair])
                        )
                    ),
                    responseFocus: "",
                    reflectionProgressionDecision: .init(
                        meaning: .completeExploration,
                        candidateRef: nil
                    ),
                    phaseOutcomeContractApplied: true
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "",
                    reflectionProgressionDecision: .init(
                        meaning: .completeExploration,
                        candidateRef: "episodeStructure.controllableParts.0",
                        selfCriticismLink: link,
                        candidateMeaning: .repair,
                        reflectionDelta: tender
                    ),
                    phaseOutcomeContractApplied: true
                ),
            ],
            replies: ["说出的内容和关系影响确实需要面对；这份自责可以先落在这次具体行为和影响上。"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.selfCriticismStatus = .present
        model.session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        model.session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["争吵以后双方没有继续沟通，关系陷入冷战"],
            behaviorEvidence: ["我说了特别伤人的话"]
        )
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "两个人可能继续收拾，也可能直接离开",
            realityMapping: "双方之间还有问题需要解决，不能直接不讲话",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "clarify_self_criticism_attribution_relation"
        )

        model.draft = "我不希望这样冷战下去，需要沟通解决问题，我不想失去朋友。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        let recordedCorrection = await core.correctionForPlan(at: 1)
        let recordedCorrectionRequest = await core.request(at: 1)
        XCTAssertEqual(planCount, 2)
        XCTAssertEqual(writeCount, 1)
        let correction = try XCTUnwrap(recordedCorrection)
        XCTAssertEqual(correction.projectionFailure, .reflectionProgressionInvalid)
        XCTAssertEqual(correction.rejectedOperation, .continueExploratoryReflection)
        let correctionRequest = try XCTUnwrap(recordedCorrectionRequest)
        XCTAssertEqual(correctionRequest.semanticMemory.selfCriticalStatement, "我感觉很自责")
        XCTAssertEqual(
            correctionRequest.semanticMemory.episodeStructure?.behaviorEvidence,
            ["我说了特别伤人的话"]
        )
        XCTAssertEqual(
            correctionRequest.semanticMemory.episodeStructure?.controllableParts,
            [repair]
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(model.session.semanticMemory.selfCriticismLink, link)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.reflectionDelta, tender)
        XCTAssertEqual(
            model.session.semanticMemory.pendingRealityCandidate,
            .init(reference: "episodeStructure.controllableParts.0", meaning: .repair)
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("刚才没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_planner_or_gate_unavailable"
                    || $0.action == "current_v5_core_gate_unavailable"
            }
        )
    }

    func testRepeatedInvalidExplorationOutcomeUsesCanonicalContinuationInsteadOfInterruption() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-exploration-continuity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "",
            reflectionProgressionDecision: .init(
                meaning: .completeExploration,
                candidateRef: nil
            ),
            phaseOutcomeContractApplied: true
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [invalid, invalid],
            replies: ["你刚才说自己很自责，最责怪自己的，是当时做了什么？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        model.session.semanticMemory.episodeStructure = .init(
            behaviorEvidence: ["我当时说了很重的话"]
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "clarify_self_criticism_attribution_relation"
        )

        model.draft = "我需要为当时说的话道歉。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 2)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
        XCTAssertNil(model.session.semanticMemory.selfCriticismLink)
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.focus,
            "clarify_self_criticism_attribution_relation"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_continuity_fallback_")
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("刚才没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_gate_unavailable"
            }
        )
    }

    func testUniqueStateCanonicalizationAvoidsLegacyRecoveryAndExtraPlannerCall() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-core-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = RejectingLegacyTurnController()
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(),
                    responseFocus: "重复询问已经完整的事件"
                ),
            ],
            replies: ["我们可以先停在这里，抽一张随机反思卡看看吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: legacy,
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = completeEpisode

        model.draft = "就先说到这里。"
        model.send()
        await waitUntilIdle(model)

        let corePlanCalls = await core.planCount()
        let coreWriteCalls = await core.writeCount()
        let legacyPlanCalls = await legacy.planCount()
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(corePlanCalls, 1)
        XCTAssertEqual(coreWriteCalls, 1)
        XCTAssertEqual(legacyPlanCalls, 0)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
    }

    func testTenderOperationUsesExplicitSemanticDeltaWithoutPlannerCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-tender-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let distinction = "这次没有做到承诺需要面对，但不等于整个人都不靠谱"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            selfCriticalStatement: "我觉得自己不靠谱",
                            reflectionFrame: TurnReflectionFrame(
                                mode: .tender,
                                action: .softenGlobalSelfJudgment,
                                evidenceBasis: [],
                                dimensions: [],
                                reflectionDelta: distinction,
                                fierceEvidence: nil
                            )
                        )
                    ),
                    responseFocus: "自然呈现已提交的有限理解"
                ),
            ],
            replies: ["这次没有做到答应的事确实需要面对，但它和整个人都不靠谱并不是同一个判断。这样分开看以后，哪一部分还是最难受？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.reflectionReadiness = .reflectionOpen
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.selfCriticismLink =
            "这次没有做到承诺后扩大了自我判断 -> 我觉得自己不靠谱"
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "形成一个有事实依据的区分"
        )

        model.draft = "我觉得自己不靠谱。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let correction = await core.correctionForPlan(at: 0)
        XCTAssertEqual(planCount, 1)
        XCTAssertNil(correction)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.mode, .tender)
        XCTAssertEqual(
            model.session.semanticMemory.reflectionFrame?.action,
            .softenGlobalSelfJudgment
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.reflectionDelta, distinction)
        XCTAssertTrue(
            model.session.semanticMemory.reflectionFrame?.evidenceBasis.contains {
                $0.source == .episode
                    && $0.content == "这次没有做到承诺后扩大了自我判断 -> 我觉得自己不靠谱"
            } == true
        )
        XCTAssertEqual(model.session.semanticMemory.selfCriticalStatement, "我觉得自己不靠谱")
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, TurnNextPromptKind.openQuestion)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "这次没有做到答应的事确实需要面对，但它和整个人都不靠谱并不是同一个判断。这样分开看以后，哪一部分还是最难受？"
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_planner_or_gate_unavailable"
            }
        )
    }

    func testEventCorrectionRepairsMissingResponseFocusWithoutChangingOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-event-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(),
                    responseFocus: ""
                ),
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(),
                    responseFocus: "询问用户当时具体做了什么或没有做什么"
                ),
            ],
            replies: ["当时你具体做了什么，或者有什么没有做？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["项目没有按时提交"],
            eventProcessStatus: .present,
            eventProcess: ["方案基本完成后仍在继续修改"]
        )

        model.draft = "后来就错过截止时间了。"
        model.send()
        await waitUntilIdle(model)

        let recordedCorrection = await core.correctionForPlan(at: 1)
        let correction = try XCTUnwrap(recordedCorrection)
        XCTAssertEqual(correction.rejectedOperation, .clarifyEvent)
        XCTAssertNil(correction.payloadFailure)
        XCTAssertEqual(correction.projectionFailure, .responseFocusMissing)
        XCTAssertEqual(correction.allowedSemanticOperations, [.clarifyEvent])
        XCTAssertEqual(correction.issue.fieldPath, "responseFocus")
        XCTAssertEqual(correction.issue.violation, .missing)
        XCTAssertEqual(correction.issue.requiredConditions, [.provideResponseFocus])
        XCTAssertEqual(correction.recoveryPolicy, .repairSameOperation)
        XCTAssertEqual(model.session.protocolStage, .contextualDisclosure)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "当时你具体做了什么，或者有什么没有做？"
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
            }
        )
    }

    func testRealityConnectionSemanticEvidenceCompilesWithoutTaggedOutcome() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-connection-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let connection = TurnCardRealityConnection(
            imageRelation: "人物带着尚未处理完的东西继续出发",
            realityMapping: "我也在问题还没完全解决时继续推进开发",
            source: .userAuthored
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueOpenCardConnection,
                    semanticEvidencePatch: .init(
                        cardConnectionEvidence: .init(
                            imageRelation: connection.imageRelation,
                            realityMapping: connection.realityMapping
                        )
                    ),
                    responseFocus: "沿用户刚建立的现实连接继续探索"
                ),
            ],
            replies: ["这种继续推进的状态里，最让你为难的是什么？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardConnection
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物", "尚未处理完的东西"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["人物", "物件"],
            projectiveFocus: "物件是否会被一起带走",
            relationOrAction: "人物带着物件准备离开",
            anticipatedChangeOrChoice: "带着它继续出发"
        )

        model.draft = connection.realityMapping
        model.send()
        await waitUntilIdle(model)

        let unexpectedCorrection = await core.correctionForPlan(at: 0)
        let planCalls = await core.planCount()
        XCTAssertNil(unexpectedCorrection)
        XCTAssertEqual(planCalls, 1)
        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, connection)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
            }
        )
    }

    func testActionCorrectionRepairsIncompleteProposalWithoutChangingOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-action-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalidProposal = TurnPracticeProposal(
            id: "practice-1",
            kind: .change,
            content: "先固定一个最小复现",
            basis: "",
            status: .pendingConfirmation
        )
        let validProposal = TurnPracticeProposal(
            id: "practice-1",
            kind: .change,
            content: "下次先固定一个最小复现，再只改一个位置",
            basis: "episodeStructure.behaviorEvidence.0",
            status: .pendingConfirmation
        )
        func patch(_ proposal: TurnPracticeProposal) -> CurrentV5SemanticEvidencePatch {
            .init(
                memoryUpdate: .init(
                    finalNarrative: "保留已经形成的理解，并采用缩小后的核对步骤。",
                    practiceTransition: .init(
                        transactionID: "practice-1",
                        narrativeReferenceID: nil,
                        proposal: proposal,
                        noActionReason: nil
                    )
                )
            )
        }
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: patch(invalidProposal),
                    responseFocus: "提出一个有依据的小行动"
                ),
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: patch(validProposal),
                    responseFocus: "提出一个有依据的小行动"
                ),
            ],
            replies: ["下次可以先固定一个最小复现，再只改一个位置。你愿意试试吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .synthesis
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["问题反复出现，开发无法继续"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["着急时会同时修改很多地方，问题反而更乱"]
        )
        model.session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "着急时会同时修改很多地方，问题反而更乱"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前困难需要具体处理，但不需要扩大成对整体能力的判断",
            fierceEvidence: nil
        )

        model.draft = "我想从一个小地方开始改。"
        model.send()
        await waitUntilIdle(model)

        let recordedCorrection = await core.correctionForPlan(at: 1)
        let correction = try XCTUnwrap(recordedCorrection)
        XCTAssertEqual(correction.rejectedOperation, .proposePractice)
        XCTAssertNil(correction.payloadFailure)
        XCTAssertEqual(correction.projectionFailure, .practiceProposalIncomplete)
        XCTAssertEqual(correction.allowedSemanticOperations, [.proposePractice])
        XCTAssertEqual(
            correction.issue.fieldPath,
            "semanticEvidencePatch.memoryUpdate.practiceTransition.proposal.basis"
        )
        XCTAssertEqual(correction.issue.violation, .empty)
        XCTAssertEqual(correction.issue.requiredConditions, [.provideCompletePracticeProposal])
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        let committedProposal = try XCTUnwrap(
            model.session.semanticMemory.practiceTransition?.proposal
        )
        XCTAssertEqual(committedProposal.kind, validProposal.kind)
        XCTAssertEqual(committedProposal.content, validProposal.content)
        XCTAssertEqual(committedProposal.basis, validProposal.basis)
        XCTAssertEqual(committedProposal.status, .pendingConfirmation)
        XCTAssertEqual(committedProposal.source, .assistantProposed)
        XCTAssertEqual(
            model.session.semanticMemory.practiceTransition?.transactionID,
            committedProposal.id
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .practice)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.referenceID, committedProposal.id)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
            }
        )
    }

    func testNaturalPracticeAcceptanceOperationCompilesLocallyAndPersistsVisibleFinalNarrative() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-practice-accept-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthesisDelta = "这次确实有一个需要改的版本核对环节，但一次失误不足以支持对整个人的判断。"
        let finalNarrative = synthesisDelta + "\n接下来愿意尝试：汇报前核对一次图片版本"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .resolvePractice,
                    semanticEvidencePatch: .init(),
                    responseFocus: "接受当前行动并形成最终叙事"
                ),
            ],
            replies: [finalNarrative]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .optionalAction
        model.session.stage = .actionSelection
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["汇报时放错了旧版本图片"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["汇报前没有核对图片版本"]
        )
        model.session.semanticMemory.reflectionPhase = .synthesis
        model.session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "汇报前没有核对图片版本")
            ],
            dimensions: [],
            reflectionDelta: synthesisDelta,
            fierceEvidence: nil
        )
        model.session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-accept"
        )
        model.session.semanticMemory.practiceTransition = .init(
            transactionID: "practice-accept",
            narrativeReferenceID: nil,
            proposal: .init(
                id: "practice-accept",
                kind: .change,
                content: "汇报前核对一次图片版本",
                basis: "episodeStructure.behaviorEvidence.0",
                status: .pendingConfirmation,
                source: .assistantProposed
            ),
            noActionReason: nil
        )

        model.draft = "可以"
        model.send()
        await waitUntilIdle(model)

        let correction = await core.correctionForPlan(at: 0)
        XCTAssertNil(correction)
        XCTAssertEqual(model.session.protocolStage, .narrativeConfirmation)
        XCTAssertEqual(
            model.session.semanticMemory.practiceTransition?.proposal?.status,
            .confirmed
        )
        XCTAssertEqual(model.session.semanticMemory.finalNarrative, finalNarrative)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .finalNarrative)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            finalNarrative
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_single_correction_")
                    || $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_gate_unavailable"
            }
        )
    }

    func testSynthesisOperationUsesExplicitSemanticDeltaWithoutPlannerCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-synthesis-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(
                    source: .episode,
                    content: "反复排查和修改后，功能仍然没有达到想要的效果"
                ),
                .init(
                    source: .latestUserAnswer,
                    content: "用户认为适合开发的人应该很快修好 bug"
                ),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "当前问题长期没有解决，并不等同于整个人不适合开发",
            fierceEvidence: nil
        )
        let synthesis = "真正需要分开看的，是问题仍未解决和整个人不适合开发这两个判断"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "自然呈现已提交的综合理解",
                    reflectionProgressionDecision: .init(
                        meaning: .synthesize,
                        candidateRef: nil,
                        reflectionDelta: synthesis
                    )
                ),
            ],
            replies: ["好像真正需要分开的，是这个问题还没解决，和你是不是适合开发。这里面有没有哪一处你想改一改？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.reflectionFrame = committedTender
        model.session.semanticMemory.selfCriticismLink =
            "问题反复没有解决后，用户开始把长期卡住理解为自己不适合开发"

        model.draft = "如果适合开发，bug 应该很快就能改好。"
        model.send()
        await waitUntilIdle(model)

        let correction = await core.correctionForPlan(at: 0)
        XCTAssertNil(correction)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        XCTAssertEqual(
            model.session.semanticMemory.reflectionFrame?.action,
            .synthesizeUnderstanding
        )
        XCTAssertEqual(
            model.session.semanticMemory.reflectionFrame?.evidenceBasis,
            committedTender.evidenceBasis
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame?.reflectionDelta, synthesis)
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_gate_unavailable"
            }
        )
    }

    func testSynthesisCanBeClarifiedInPlaceBeforeMovingToAction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-synthesis-clarification-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let originalFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "用户连续修改bug但问题继续增加"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "用户已经形成了完整的新理解方式",
            fierceEvidence: nil
        )
        let revisedFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "用户连续修改bug但问题继续增加"),
                .init(source: .cardRealityConnection, content: "用户想到可以换一个角度看问题"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "用户目前只是多想到一个从整体查看bug影响的可能方向，是否有用仍待尝试",
            fierceEvidence: nil
        )
        let canonicalRevisedFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: originalFrame.evidenceBasis,
            dimensions: revisedFrame.dimensions,
            reflectionDelta: revisedFrame.reflectionDelta,
            fierceEvidence: nil
        )
        let proposal = TurnPracticeProposal(
            id: "practice-after-synthesis-clarification",
            kind: .change,
            content: "下一次修改前，先写下这个bug影响的流程范围",
            basis: "episodeStructure.behaviorEvidence.0",
            status: .pendingConfirmation
        )
        let transition = TurnPracticeTransition(
            transactionID: proposal.id,
            narrativeReferenceID: nil,
            proposal: proposal,
            noActionReason: nil
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: revisedFrame)
                    ),
                    responseFocus: "降低刚才结论的确定性，把它改成仍待尝试的可能方向"
                ),
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(practiceTransition: transition)
                    ),
                    responseFocus: "根据用户已经接受的方向提出一个小步骤"
                ),
            ],
            replies: [
                "我刚才说得太满了。现在更准确的是，你只是多想到一个可以试试的角度；哪里仍不符合，你可以直接改。",
                "可以先从一个很小的步骤开始：下次修改前，写下这个 bug 影响了哪一段流程。你愿意试试吗？",
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .synthesis
        model.session.semanticMemory.reflectionFrame = originalFrame
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["连续修改后 bug 仍然增加"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["修改前没有先确认 bug 影响的流程范围"]
        )

        model.draft = "这样吗"
        model.send()
        await waitUntilIdle(model)

        let capturedClarificationRequest = await core.request(at: 0)
        let clarificationRequest = try XCTUnwrap(capturedClarificationRequest)
        XCTAssertEqual(
            Set(clarificationRequest.allowedSemanticOperations),
            [.synthesizeDirectReflection, .proposePractice]
        )
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame, canonicalRevisedFrame)
        XCTAssertNil(model.session.semanticMemory.practiceTransition)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .openQuestion)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "synthesisReflection")
        XCTAssertEqual(
            model.session.semanticMemory.nextPrompt?.focus,
            "confirm_or_revise_synthesis"
        )

        model.draft = "这样更接近，我愿意试一个小步骤。"
        model.send()
        await waitUntilIdle(model)

        let capturedActionRequest = await core.request(at: 1)
        let actionRequest = try XCTUnwrap(capturedActionRequest)
        XCTAssertEqual(
            Set(actionRequest.allowedSemanticOperations),
            [.synthesizeDirectReflection, .proposePractice]
        )
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        let committedTransition = try XCTUnwrap(
            model.session.semanticMemory.practiceTransition
        )
        let committedProposal = try XCTUnwrap(committedTransition.proposal)
        XCTAssertEqual(committedProposal.kind, proposal.kind)
        XCTAssertEqual(committedProposal.content, proposal.content)
        XCTAssertEqual(committedProposal.basis, proposal.basis)
        XCTAssertEqual(committedProposal.status, .pendingConfirmation)
        XCTAssertEqual(committedProposal.source, .assistantProposed)
        XCTAssertEqual(committedTransition.transactionID, committedProposal.id)
        XCTAssertNil(committedTransition.narrativeReferenceID)
    }

    func testNaturalSynthesisAcceptanceProposesPracticeInOneTurn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-synthesis-acceptance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthesis = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "用户在汇报前没有核对图片版本"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "这次核对遗漏需要改进，但不足以支持对整体专业性的判断",
            fierceEvidence: nil
        )
        let proposal = TurnPracticeProposal(
            id: "planner-metadata-is-replaced",
            kind: .change,
            content: "下次汇报前单独核对一次图片版本",
            basis: "episodeStructure.behaviorEvidence.0",
            status: .pendingConfirmation
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            practiceTransition: .init(
                                transactionID: proposal.id,
                                narrativeReferenceID: nil,
                                proposal: proposal,
                                noActionReason: nil
                            )
                        )
                    ),
                    responseFocus: "直接提出一个小而具体的核对动作"
                ),
            ],
            replies: ["下次汇报前，可以单独留一次图片版本核对。这个做法对你来说可行吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .synthesis
        model.session.semanticMemory.reflectionFrame = synthesis
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["汇报时放错了旧版本图片"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["汇报前没有核对图片版本"]
        )

        model.draft = "可以"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        XCTAssertNotNil(model.session.semanticMemory.practiceTransition?.proposal)
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action == "current_v5_core_turn_committed_proposePractice"
            }.count,
            1
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_single_correction_")
            }
        )
    }

    func testRepeatedSynthesisCorrectionCanChoosePracticeInsteadOfReplaying() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-synthesis-disposition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let synthesis = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "用户在汇报前没有核对图片版本"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "这次核对遗漏需要改进，但不足以支持对整体专业性的判断",
            fierceEvidence: nil
        )
        let repeated = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [],
            dimensions: [.mindfulness],
            reflectionDelta: "这次核对遗漏需要改进，但不足以支持对整体专业性的判断。",
            fierceEvidence: nil
        )
        let proposal = TurnPracticeProposal(
            id: "planner-metadata-is-replaced",
            kind: .change,
            content: "下次汇报前单独核对一次图片版本",
            basis: "episodeStructure.behaviorEvidence.0",
            status: .pendingConfirmation
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: repeated)
                    ),
                    responseFocus: repeated.reflectionDelta
                ),
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            practiceTransition: .init(
                                transactionID: proposal.id,
                                narrativeReferenceID: nil,
                                proposal: proposal,
                                noActionReason: nil
                            )
                        )
                    ),
                    responseFocus: "直接提出一个小而具体的核对动作"
                ),
            ],
            replies: ["下次汇报前，可以单独留一次图片版本核对。这个做法对你来说可行吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .synthesis
        model.session.semanticMemory.reflectionFrame = synthesis
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["汇报时放错了旧版本图片"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["汇报前没有核对图片版本"]
        )

        model.draft = "可以"
        model.send()
        await waitUntilIdle(model)

        let capturedCorrectedRequest = await core.request(at: 1)
        let correctedRequest = try XCTUnwrap(capturedCorrectedRequest)
        XCTAssertEqual(
            Set(correctedRequest.allowedSemanticOperations),
            [.synthesizeDirectReflection, .proposePractice]
        )
        XCTAssertEqual(
            correctedRequest.correction?.projectionFailure,
            .synthesisDeltaMissing
        )
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 2)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action == "current_v5_core_turn_committed_proposePractice"
            }.count,
            1
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_final_rejection_")
            }
        )
    }

    func testInitialPracticeProposalLetsSwiftOwnTransactionMetadata() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.semanticMemory.reflectionPhase = .synthesis
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["这个 bug 影响的流程范围仍不清楚"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["修改前没有先确认受影响的流程范围"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "修改前没有先确认受影响的流程范围"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前需要处理的是先确认影响范围，而不是继续扩大修改",
            fierceEvidence: nil
        )

        func output(
            transactionID: String = "practice-1",
            proposalID: String = "practice-1",
            kind: TurnPracticeKind = .change,
            status: TurnPracticeProposalStatus = .pendingConfirmation,
            source: TurnPracticeProposalSource = .assistantProposed,
            narrativeReferenceID: String? = nil
        ) -> CurrentV5PlannerOutput {
            .init(
                semanticOperation: .proposePractice,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        practiceTransition: .init(
                            transactionID: transactionID,
                            narrativeReferenceID: narrativeReferenceID,
                            proposal: .init(
                                id: proposalID,
                                kind: kind,
                                content: "先确认这个 bug 影响的流程范围",
                                basis: "episodeStructure.behaviorEvidence.0",
                                status: status,
                                source: source
                            ),
                            noActionReason: nil
                        )
                    )
                ),
                responseFocus: "提出一个小而具体的行动"
            )
        }

        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertNoThrow(
            try gate.authorize(output(), for: session, allowedSemanticOperations: allowed)
        )

        let redundantProtocolVariants = [
            output(transactionID: "transaction-a", proposalID: "proposal-b"),
            output(status: .confirmed),
            output(source: .userRevised),
            output(narrativeReferenceID: "unexpected-narrative-reference"),
        ]
        for variant in redundantProtocolVariants {
            let authorized = try gate.authorize(
                variant,
                for: session,
                allowedSemanticOperations: allowed
            )
            let canonical = try XCTUnwrap(
                authorized.projectedPlan.memoryUpdate.practiceTransition
            )
            let canonicalProposal = try XCTUnwrap(canonical.proposal)
            XCTAssertEqual(canonical.transactionID, canonicalProposal.id)
            XCTAssertEqual(canonicalProposal.status, .pendingConfirmation)
            XCTAssertEqual(canonicalProposal.source, .assistantProposed)
            XCTAssertNil(canonical.narrativeReferenceID)
            XCTAssertEqual(canonicalProposal.kind, .change)
            XCTAssertEqual(canonicalProposal.content, "先确认这个 bug 影响的流程范围")
            XCTAssertEqual(canonicalProposal.basis, "episodeStructure.behaviorEvidence.0")
        }
    }

    func testPlannerCandidateWithoutIDReceivesOneSwiftOwnedIdentity() throws {
        let data = Data(
            #"{"semanticOperation":"offerCardConnectionCandidate","semanticEvidencePatch":{"memoryUpdate":{"pendingCardRealityConnection":{"imageRelation":"画面里的人停下来检查文件","candidateRealityMapping":"可能对应现实中继续前没有核对版本"}}},"responseFocus":"提供一个可以拒绝的候选连接"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(CurrentV5PlannerOutput.self, from: data)
        let pending = try XCTUnwrap(
            decoded.semanticEvidencePatch.memoryUpdate.pendingCardRealityConnection
        )
        XCTAssertFalse(pending.id.uuidString.isEmpty)
        XCTAssertEqual(pending.imageRelation, "画面里的人停下来检查文件")
        XCTAssertEqual(
            pending.candidateRealityMapping,
            "可能对应现实中继续前没有核对版本"
        )

        let encoded = try JSONEncoder().encode(pending)
        let reloaded = try JSONDecoder().decode(PendingCardRealityConnection.self, from: encoded)
        XCTAssertEqual(reloaded.id, pending.id)
    }

    func testPracticeResolutionRestoresActiveProtocolIdentityAndStatus() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .optionalAction
        session.stage = .actionSelection
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["汇报时放错了旧版本图片"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["汇报前没有核对图片版本"]
        )
        session.semanticMemory.reflectionPhase = .synthesis
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "汇报前没有核对图片版本")
            ],
            dimensions: [],
            reflectionDelta: "这次失误不足以支持对整个人的判断，但版本核对是需要改变的环节。",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "active-practice"
        )
        session.semanticMemory.practiceTransition = .init(
            transactionID: "active-practice",
            narrativeReferenceID: nil,
            proposal: .init(
                id: "active-practice",
                kind: .change,
                content: "汇报前核对一次图片版本",
                basis: "episodeStructure.behaviorEvidence.0",
                status: .pendingConfirmation,
                source: .assistantProposed
            ),
            noActionReason: nil
        )

        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let accepted = CurrentV5PlannerOutput(
            semanticOperation: .resolvePractice,
            semanticEvidencePatch: .init(),
            responseFocus: "接受当前小步"
        )

        let acceptedTurn = try gate.authorize(
            accepted,
            for: session,
            allowedSemanticOperations: allowed
        )
        let acceptedTransition = try XCTUnwrap(
            acceptedTurn.projectedPlan.memoryUpdate.practiceTransition
        )
        let acceptedProposal = try XCTUnwrap(acceptedTransition.proposal)
        XCTAssertEqual(acceptedTransition.transactionID, "active-practice")
        XCTAssertEqual(acceptedProposal.id, "active-practice")
        XCTAssertEqual(acceptedProposal.status, .confirmed)
        XCTAssertEqual(acceptedProposal.source, .assistantProposed)
        XCTAssertEqual(acceptedTurn.projectedPlan.requestedStage, .narrativeConfirmation)
        XCTAssertEqual(acceptedTurn.projectedPlan.replyIntent, .presentFinalNarrative)
        XCTAssertEqual(
            acceptedTurn.projectedPlan.memoryUpdate.finalNarrative,
            "这次失误不足以支持对整个人的判断，但版本核对是需要改变的环节。\n接下来愿意尝试：汇报前核对一次图片版本"
        )
        let acceptedWriterDirective = CurrentV5WriterDirective(authorized: acceptedTurn)
        XCTAssertNil(acceptedWriterDirective.responseFocus)
        XCTAssertNil(acceptedWriterDirective.memoryUpdate.practiceTransition)
        XCTAssertEqual(
            acceptedWriterDirective.memoryUpdate.finalNarrative,
            "这次失误不足以支持对整个人的判断，但版本核对是需要改变的环节。\n接下来愿意尝试：汇报前核对一次图片版本"
        )

        let revised = CurrentV5PlannerOutput(
            semanticOperation: .resolvePractice,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    practiceTransition: .init(
                        transactionID: "wrong-id",
                        narrativeReferenceID: "wrong-reference",
                        proposal: .init(
                            id: "wrong-proposal-id",
                            kind: .change,
                            content: "只核对最终展示的三张关键图片",
                            basis: "episodeStructure.behaviorEvidence.0",
                            status: .pendingConfirmation,
                            source: .assistantProposed
                        ),
                        noActionReason: nil
                    )
                )
            ),
            responseFocus: "采用用户缩小后的行动"
        )
        let revisedTurn = try gate.authorize(
            revised,
            for: session,
            allowedSemanticOperations: allowed
        )
        let revisedTransition = try XCTUnwrap(
            revisedTurn.projectedPlan.memoryUpdate.practiceTransition
        )
        let revisedProposal = try XCTUnwrap(revisedTransition.proposal)
        XCTAssertEqual(revisedTransition.transactionID, "active-practice")
        XCTAssertEqual(revisedProposal.id, "active-practice")
        XCTAssertEqual(revisedProposal.status, .confirmed)
        XCTAssertEqual(revisedProposal.source, .userRevised)
        XCTAssertEqual(revisedProposal.content, "只核对最终展示的三张关键图片")
        XCTAssertEqual(
            revisedTurn.projectedPlan.memoryUpdate.finalNarrative,
            "这次失误不足以支持对整个人的判断，但版本核对是需要改变的环节。\n接下来愿意尝试：只核对最终展示的三张关键图片"
        )
    }

    func testOptionalActionCapabilitiesExposeOnlyTheExecutableActionOperation() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .optionalAction

        var operations = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertTrue(operations.contains(.proposePractice))
        XCTAssertFalse(operations.contains(.resolvePractice))
        XCTAssertFalse(operations.contains(.confirmNarrative))
        XCTAssertFalse(operations.contains(.completeConversation))

        session.semanticMemory.practiceTransition = .init(
            transactionID: "practice-active",
            narrativeReferenceID: nil,
            proposal: .init(
                id: "practice-active",
                kind: .change,
                content: "先做一个小动作",
                basis: "用户已经形成了一个具体改变方向",
                status: .pendingConfirmation
            ),
            noActionReason: nil
        )
        operations = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertFalse(operations.contains(.proposePractice))
        XCTAssertTrue(operations.contains(.resolvePractice))
        XCTAssertFalse(operations.contains(.confirmNarrative))
        XCTAssertFalse(operations.contains(.completeConversation))
    }

    func testUniqueCandidateOperationAdvancesWithoutPlannerCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-candidate-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let completedPatch = TurnSemanticMemoryUpdate(
            episodeStructure: TurnEpisodeStructure(
                behaviorEvidence: ["持续修改app"],
                eventProcess: ["为了改善效果持续修改，随后bug增加"]
            )
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(memoryUpdate: completedPatch),
                    responseFocus: "继续询问已经完整的事件"
                ),
            ],
            replies: ["这件事已经说清楚了。我们可以抽一张随机反思卡看看吗？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["开发app时效果不好，bug很多"]
        )

        model.draft = "我只能继续修改。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
            }
        )
    }

    func testCandidateCapabilitiesKeepClarifyingWhileEventRemainsIncomplete() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.stage = .eventDisclosure
        session.condition = .cardMediated
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["开发app时效果不好"]
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .advanceToCardConsent,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    episodeStructure: TurnEpisodeStructure(
                        eventProcess: ["持续修改以后bug增加"]
                    )
                )
            ),
            responseFocus: "邀请随机反思卡"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(authorized.operation, .clarifyEvent)
        XCTAssertEqual(authorized.projectedPlan.requestedStage, .contextualDisclosure)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.kind, .openQuestion)
    }

    func testCompletingEventActKeepsItsOperationAndProjectsCardConsent() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.stage = .eventDisclosure
        session.condition = .cardMediated
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["开发 app 时反复出现 bug"]
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .clarifyEvent,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    episodeStructure: .init(
                        behaviorEvidence: ["持续修改多个地方"],
                        eventProcess: ["修改后问题反而增加"]
                    )
                )
            ),
            responseFocus: "承接这段已经清楚的经历"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .clarifyEvent)
        XCTAssertEqual(authorized.projectedPlan.requestedStage, .cardConsent)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.target, .cardConsent)
        XCTAssertNil(CurrentV5WriterDirective(authorized: authorized).responseFocus)
    }

    func testGateUsesDevelopmentEncodingForContinuedCardExplorationAfterObservation() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardObservation",
            focus: "describe_visible_image"
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardObservation,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    cardObservationEvidence: .init(
                        userDescribedElements: ["漏雨的屋子", "检查的人", "搬书的人"]
                    )
                )
            ),
            responseFocus: "让这段画面再向前发展一点"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardObservation)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardDevelopment")
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.cardObservationEvidence?.userDescribedElements,
            ["漏雨的屋子", "检查的人", "搬书的人"]
        )
    }

    func testGateCompilesAnInvalidOperationWhenPreTurnCapabilityHasOneMeaning() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["漏雨的屋子", "检查的人"]
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .clarifyEvent,
            semanticEvidencePatch: .init(),
            responseFocus: "继续"
        )

        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertEqual(allowed, [.continueCardDevelopment])
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(output, for: session, allowedSemanticOperations: allowed)
        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
    }

    func testPlannerSelfCriticismStatusHasNoCurrentV5OutputAuthority() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.stage = .eventDisclosure
        session.condition = .cardMediated
        let output = CurrentV5PlannerOutput(
            semanticOperation: .clarifyEvent,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(selfCriticismStatus: .present)
            ),
            responseFocus: "继续了解具体事件"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertNil(authorized.projectedPlan.memoryUpdate.selfCriticismStatus)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.selfCriticalStatement)
    }

    func testPlannerStatusResidueDoesNotTriggerCorrectionOrVisiblePause() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-self-criticism-residue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(selfCriticismStatus: .present)
                    ),
                    responseFocus: "了解具体发生的事情"
                ),
            ],
            replies: ["昨天从答应帮忙到最后没有做，中间发生了什么？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated

        model.draft = "我总是这么不靠谱。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(model.session.semanticMemory.selfCriticismStatus, .unresolved)
        XCTAssertNil(model.session.semanticMemory.selfCriticalStatement)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "昨天从答应帮忙到最后没有做，中间发生了什么？"
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_planner_or_gate_unavailable"
            }
        )
    }

    func testDirectReflectionCanAppendLateGroundedEpisodeFactsWithoutLockingThemInLink() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.episodeStructure = completeEpisode

        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    selfCriticalStatement: "  我总是这么不靠谱  ",
                    episodeStructure: TurnEpisodeStructure(
                        behaviorEvidence: ["卡住以后同时改了好几个地方"],
                        impactStatus: .present,
                        impacts: ["后来出现的 bug 反而更多了"]
                    )
                )
            ),
            responseFocus: "沿用户自己的连接探索一个仍未回答的关系"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.behaviorEvidence,
            ["卡住以后同时改了好几个地方"]
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.impacts,
            ["后来出现的 bug 反而更多了"]
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.behaviorEvidenceStatus,
            .present
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.impactStatus,
            .present
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.selfCriticismStatus, .present)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticalStatement,
            "我总是这么不靠谱"
        )
        session.semanticMemory.apply(authorized.projectedPlan.memoryUpdate)
        XCTAssertTrue(
            session.semanticMemory.episodeStructure?.behaviorEvidence.contains(
                "卡住以后同时改了好几个地方"
            ) == true
        )
        XCTAssertTrue(
            session.semanticMemory.episodeStructure?.impacts.contains(
                "后来出现的 bug 反而更多了"
            ) == true
        )
    }

    func testCardWorkCannotWriteLateEpisodeEvidence() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["一个人在修桌子"]
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    episodeStructure: TurnEpisodeStructure(
                        behaviorEvidence: ["模型从画面推断出的现实行为"]
                    )
                )
            ),
            responseFocus: "询问画面接下来可能发生什么"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertNil(authorized.projectedPlan.memoryUpdate.episodeStructure)
    }

    func testCardDevelopmentAdvancesToRealityWithoutOptionalAggregate() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["桌上的照片", "站起来的人", "门外的钟"]
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(),
            responseFocus: "邀请用户把画面放回现实"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence)
        XCTAssertNil(CurrentV5WriterDirective(authorized: authorized).responseFocus)
    }

    func testPartialCardRelationIsSavedAndDevelopmentStillAdvancesOnce() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物", "一个物件", "前方空间"]
        )
        let relationshipOnly = TurnSemanticMemoryUpdate(
            cardDevelopmentEvidence: .init(
                actorsOrElements: ["人物", "物件"],
                relationOrAction: "人物准备带着物件移动",
                anticipatedChangeOrChoice: nil
            )
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(memoryUpdate: relationshipOnly),
            responseFocus: "询问这个情境接下来可能如何继续"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence?.relationOrAction,
            "人物准备带着物件移动"
        )
        XCTAssertNil(
            authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence?.anticipatedChangeOrChoice
        )
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
    }

    func testThinDevelopmentEvidenceDoesNotCauseAnotherDevelopmentQuestion() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物", "房间里的物件"]
        )
        let shallowNarrative = TurnSemanticMemoryUpdate(
            cardDevelopmentEvidence: .init(
                actorsOrElements: ["人物", "物件"],
                relationOrAction: "人物正在搬动物件",
                anticipatedChangeOrChoice: "接下来还会继续搬"
            )
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(memoryUpdate: shallowNarrative),
            responseFocus: "沿用户注意到的未确定之处再发展一步"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertTrue(
            authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence?.hasContent == true
        )
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
    }

    func testInitialCardObservationRejectsAnEmptySparsePatch() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardObservation",
            focus: "describe_visible_image"
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardObservation,
            semanticEvidencePatch: .init(),
            responseFocus: "继续观察画面"
        )

        XCTAssertEqual(session.protocolStage, .cardReflection)
        XCTAssertEqual(session.semanticMemory.nextPrompt?.purpose, "cardObservation")
        XCTAssertFalse(EffectiveCardSemanticState(session: session).observationEvidenceExists)
        XCTAssertFalse(
            output.semanticEvidencePatch.memoryUpdate.cardObservationEvidence?.hasContent ?? false
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .payloadInvalid(failure: .cardObservationEvidenceMissing)
            )
        }
    }

    func testMissingInitialObservationUsesOneForwardCorrectionAndPersistsEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-card-observation-empty-patch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let observation = CardObservationEvidence(
            userDescribedElements: ["站在门口的人", "桌上的旧照片", "门外的钟"]
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueCardObservation,
                    semanticEvidencePatch: .init(),
                    responseFocus: "继续索取画面细节"
                ),
                .init(
                    semanticOperation: .continueCardObservation,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(cardObservationEvidence: observation)
                    ),
                    responseFocus: "开放询问画面接下来可能发生什么"
                ),
            ],
            replies: ["你觉得接下来可能会发生什么？"]
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardObservation",
            focus: "describe_visible_image"
        )

        model.draft = "有一个人站在门口，桌上放着旧照片，外面的钟在响。"
        model.send()
        await waitUntilIdle(model)

        let recordedCorrection = await core.correctionForPlan(at: 1)
        let correction = try XCTUnwrap(recordedCorrection)
        XCTAssertEqual(correction.payloadFailure, .cardObservationEvidenceMissing)
        XCTAssertEqual(
            correction.issue.fieldPath,
            "semanticEvidencePatch.memoryUpdate.cardObservationEvidence.userDescribedElements"
        )
        XCTAssertEqual(correction.issue.violation, .missing)
        XCTAssertEqual(correction.issue.requiredConditions, [.followCardEvidenceProgression])
        XCTAssertEqual(
            correction.allowedSemanticOperations,
            [.continueCardObservation]
        )
        XCTAssertTrue(
            correction.allowedSemanticOperations.contains(.continueCardObservation)
        )
        XCTAssertEqual(model.session.semanticMemory.cardObservationEvidence, observation)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "cardDevelopment")
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 2)
        XCTAssertEqual(writeCount, 1)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_planner_or_gate_unavailable"
            }
        )

        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(persisted?.semanticMemory.cardObservationEvidence, observation)
        XCTAssertEqual(persisted?.semanticMemory.nextPrompt?.purpose, "cardDevelopment")
        let reloaded = try XCTUnwrap(persisted)
        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: reloaded)
                .contains(.continueCardObservation)
        )
    }

    func testCardObservationAndDevelopmentEvidenceAdvanceWithoutCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-card-correction-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let observation = CardObservationEvidence(
            userDescribedElements: ["漏雨的屋子", "检查漏雨的人", "正在搬书的人"]
        )
        let partialDevelopment = CardDevelopmentEvidence(
            actorsOrElements: ["检查漏雨的人", "正在搬书的人", "书"],
            projectiveFocus: "漏雨时两个人不同的应对",
            relationOrAction: "一个人检查漏雨，另一个人搬书减少损失",
            anticipatedChangeOrChoice: nil
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueCardObservation,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            cardObservationEvidence: observation,
                            cardDevelopmentEvidence: partialDevelopment
                        )
                    ),
                    responseFocus: "继续询问画面观察"
                ),
            ],
            replies: ["雨还在漏的情况下，你觉得他们接下来可能会先处理什么？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardObservation",
            focus: "描述画面里正在发生什么"
        )

        model.draft = "这个屋子在漏雨，一个人在检查，另一个人在搬书减少损失。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.semanticMemory.cardObservationEvidence, observation)
        XCTAssertEqual(model.session.semanticMemory.cardDevelopmentEvidence, partialDevelopment)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "cardDevelopment")
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_turn_committed_continueCardObservation"
            }
        )
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant && $0.content.contains("没有顺利接上")
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
            }
        )
    }

    func testCardDevelopmentAggregateMergesRelationAndLaterContinuation() {
        var memory = TurnSemanticMemory()
        memory.apply(
            .init(
                cardDevelopmentEvidence: .init(
                    actorsOrElements: ["人物", "物件"],
                    relationOrAction: "人物准备带着物件移动",
                    anticipatedChangeOrChoice: nil
                )
            )
        )
        memory.apply(
            .init(
                cardDevelopmentEvidence: .init(
                    actorsOrElements: [],
                    projectiveFocus: "人物带着物件前进时会遇到什么",
                    relationOrAction: nil,
                    anticipatedChangeOrChoice: "途中可能遇到困难，但情境会继续发展"
                )
            )
        )

        XCTAssertEqual(
            memory.cardDevelopmentEvidence?.relationOrAction,
            "人物准备带着物件移动"
        )
        XCTAssertEqual(
            memory.cardDevelopmentEvidence?.anticipatedChangeOrChoice,
            "途中可能遇到困难，但情境会继续发展"
        )
        XCTAssertTrue(memory.cardDevelopmentEvidence?.hasContent == true)
    }

    func testDecodedSparseCardDevelopmentContinuationKeepsPreviouslyCommittedActors() throws {
        let patch = try JSONDecoder().decode(
            TurnSemanticMemoryUpdate.self,
            from: Data(
                """
                {
                  "cardDevelopmentEvidence": {
                    "relationOrAction": "先扶住架子并把瓷器搬下来",
                    "anticipatedChangeOrChoice": "在架子倒下前降低损失"
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(patch.cardDevelopmentEvidence?.actorsOrElements, [])

        var memory = TurnSemanticMemory()
        memory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["两个人", "架子", "瓷器"],
            projectiveFocus: "架子可能倒下"
        )
        memory.apply(patch)

        XCTAssertEqual(
            memory.cardDevelopmentEvidence?.actorsOrElements,
            ["两个人", "架子", "瓷器"]
        )
        XCTAssertEqual(
            memory.cardDevelopmentEvidence?.relationOrAction,
            "先扶住架子并把瓷器搬下来"
        )
        XCTAssertEqual(
            memory.cardDevelopmentEvidence?.anticipatedChangeOrChoice,
            "在架子倒下前降低损失"
        )
    }

    func testDecodedSparseDevelopmentPlannerAdvancesToRealityWithoutRepeatingActors() throws {
        let output = try JSONDecoder().decode(
            CurrentV5PlannerOutput.self,
            from: Data(
                """
                {
                  "semanticOperation": "continueCardDevelopment",
                  "semanticEvidencePatch": {
                    "memoryUpdate": {
                      "cardDevelopmentEvidence": {
                        "relationOrAction": "先扶住架子并把瓷器搬下来",
                        "anticipatedChangeOrChoice": "在架子倒下前降低损失"
                      }
                    },
                    "cardConnectionTurnOutcome": null
                  },
                  "responseFocus": "开放邀请用户把这段画面放回当前经历"
                }
                """.utf8
            )
        )

        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["两个人", "架子", "瓷器"]
        )
        session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["两个人", "架子", "瓷器"],
            projectiveFocus: "架子可能倒下"
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "anticipated_change"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
        XCTAssertNil(CurrentV5WriterDirective(authorized: authorized).responseFocus)
        session.semanticMemory.apply(authorized.projectedPlan.memoryUpdate)
        XCTAssertEqual(
            session.semanticMemory.cardDevelopmentEvidence?.actorsOrElements,
            ["两个人", "架子", "瓷器"]
        )
        XCTAssertEqual(
            session.semanticMemory.cardDevelopmentEvidence?.anticipatedChangeOrChoice,
            "在架子倒下前降低损失"
        )
    }

    func testDecodedPlannerDefaultsNonsemanticEnvelopeOmissionsAndStillUsesSwiftGate() throws {
        let output = try JSONDecoder().decode(
            CurrentV5PlannerOutput.self,
            from: Data(
                """
                {
                  "semanticOperation": "continueCardDevelopment",
                  "semanticEvidencePatch": {
                    "cardConnectionTurnOutcome": null
                  }
                }
                """.utf8
            )
        )
        XCTAssertEqual(output.responseFocus, "")
        XCTAssertEqual(output.semanticEvidencePatch.memoryUpdate, TurnSemanticMemoryUpdate())

        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["人物", "架子", "瓷器"]
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence)
    }

    func testDevelopmentAnswerWithoutAggregateCommitsRealityInvitationWithoutRetry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-single-development-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueCardDevelopment,
                    semanticEvidencePatch: .init(),
                    responseFocus: "把用户形成的画面放回现实"
                ),
            ],
            replies: ["把刚才这段画面放回开发 App 的经历里，你会想到什么？"]
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session = currentCardReflectionSession()
        model.session.workflowPhase = .cardObservation
        model.session.cardImageDevelopmentTurnCount = 1
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["两个人", "快倒的架子", "正在被搬下来的瓷器"]
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "anticipated_change"
        )

        model.draft = "他们可能先把瓷器搬完，再研究怎么修架子。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "cardRealityConnection")
        XCTAssertNil(model.session.semanticMemory.cardDevelopmentEvidence)
        XCTAssertEqual(model.session.cardImageDevelopmentTurnCount, 1)
        XCTAssertEqual(
            CurrentV5CapabilitySet.allowedOperations(for: model.session),
            [.continueOpenCardConnection, .offerCardConnectionScaffold]
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
                    || $0.action.contains("current_v5_core_planner_or_gate_unavailable")
            }
        )

        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(persisted?.semanticMemory.nextPrompt?.purpose, "cardRealityConnection")
        XCTAssertNil(persisted?.semanticMemory.cardDevelopmentEvidence)
    }

    func testCompletedCardMaterialAdvancesWithoutAnotherImageTurn() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["桌上的照片", "站起来的人", "门外的钟"]
        )
        let completedUnderstanding = TurnSemanticMemoryUpdate(
            cardDevelopmentEvidence: .init(
                actorsOrElements: ["照片", "人物", "钟声"],
                projectiveFocus: "人物如何面对过去与新的开始",
                relationOrAction: "人物站在过去与新的开始之间",
                anticipatedChangeOrChoice: "带着不舍继续向前"
            )
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(memoryUpdate: completedUnderstanding),
            responseFocus: "继续拆解照片和钟声"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
    }

    func testDevelopmentActCanProjectRealityFromUserAuthoredCardEvidence() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["有人在接水，接完后可能休息"]
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "anticipated_change"
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueCardDevelopment,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    cardDevelopmentEvidence: .init(
                        actorsOrElements: ["接水的人"],
                        relationOrAction: "人物接完水以后准备休息",
                        anticipatedChangeOrChoice: "先停下来休息"
                    )
                )
            ),
            responseFocus: "邀请用户把自己的画面理解带回当前经历"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueCardDevelopment)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "cardRealityConnection")
    }

    func testWriterFailurePreservesTheCompleteAuthorizedCardStateBeforePresentation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-writer-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let completedDevelopment = TurnSemanticMemoryUpdate(
            cardDevelopmentEvidence: .init(
                actorsOrElements: ["接水的人"],
                projectiveFocus: "泥泞的人会继续前进还是停下来",
                relationOrAction: "人物在接水，身上比较泥泞",
                anticipatedChangeOrChoice: "接完水后可能会休息一会"
            )
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueCardDevelopment,
                    semanticEvidencePatch: .init(memoryUpdate: completedDevelopment),
                    responseFocus: "邀请用户把已经形成的画面理解带回当前现实经历"
                ),
            ],
            replies: []
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["有一个人在接水喝"]
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "接下来可能发生什么"
        )

        model.draft = "这个人身上比较泥泞，可能会休息一会"
        model.send()
        await waitUntilIdle(model)

        let writeCount = await core.writeCount()
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "cardRealityConnection")
        XCTAssertEqual(
            model.session.semanticMemory.cardDevelopmentEvidence?.relationOrAction,
            "人物在接水，身上比较泥泞"
        )
        XCTAssertEqual(
            model.session.semanticMemory.cardDevelopmentEvidence?.anticipatedChangeOrChoice,
            "接完水后可能会休息一会"
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_semantic_evidence_committed_continueCardDevelopment"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_writer_unavailable"
            }
        )
        let failureReply = try XCTUnwrap(
            model.session.messages.last(where: { $0.role == .assistant })?.content
        )
        XCTAssertTrue(failureReply.contains("回答已经保存"))
        XCTAssertTrue(failureReply.contains("不需要重新回答"))
        XCTAssertFalse(failureReply.contains("我还在听"))
        XCTAssertFalse(failureReply.contains("先记下"))

        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(
            persisted?.semanticMemory.cardDevelopmentEvidence,
            model.session.semanticMemory.cardDevelopmentEvidence
        )
        XCTAssertEqual(persisted?.protocolStage, .cardReflection)
        XCTAssertEqual(persisted?.semanticMemory.nextPrompt?.purpose, "cardRealityConnection")
    }

    func testPunctuationOnlyWriterReplyUsesTheExistingRewritePath() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-writer-placeholder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let completedDevelopment = TurnSemanticMemoryUpdate(
            cardDevelopmentEvidence: .init(
                actorsOrElements: ["岸边的人", "包裹", "船"],
                projectiveFocus: "人物是否会带上包裹继续出发",
                relationOrAction: "人物正看向留在岸边的包裹",
                anticipatedChangeOrChoice: "可能回头带上包裹"
            )
        )
        let visibleReply = "把这个画面放回这次实验里，你最先想到什么？"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueCardDevelopment,
                    semanticEvidencePatch: .init(memoryUpdate: completedDevelopment),
                    responseFocus: "邀请用户把已经形成的画面理解带回当前经历"
                ),
            ],
            replies: ["...", visibleReply]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["岸边的人", "包裹", "船"]
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardDevelopment",
            focus: "接下来可能发生什么"
        )

        model.draft = "他可能会回头带上包裹。"
        model.send()
        await waitUntilIdle(model)

        let writeCount = await core.writeCount()
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            visibleReply
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_writer_rewrite_requested"
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_writer_unavailable"
            }
        )
    }

    func testWriterFailureCannotRollBackTheCanonicalTenderFrameOrPhase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-unseen-tender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            reflectionFrame: tenderFrame,
                            invalidatedInterpretations: ["等待说明用户很有耐心"]
                        )
                    ),
                    responseFocus: "形成一个有事实依据的 Tender 区分"
                ),
            ],
            replies: []
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.reflectionReadiness = .reflectionOpen
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "形成一个有事实依据的区分"
        )

        model.draft = "我不是耐心，我会越来越急。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame, tenderFrame)
        XCTAssertEqual(
            model.session.semanticMemory.invalidatedInterpretations,
            ["等待说明用户很有耐心"]
        )
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "tenderReflection")
        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(persisted?.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(persisted?.semanticMemory.reflectionFrame, tenderFrame)
        XCTAssertEqual(
            persisted?.semanticMemory.invalidatedInterpretations,
            ["等待说明用户很有耐心"]
        )
    }

    func testWriterSuccessCommitsPresentedTenderFrameAndPhase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-presented-tender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: tenderFrame)
                    ),
                    responseFocus: "区分具体困难与整体自我否定"
                ),
            ],
            replies: ["现在被这个问题卡住，和你根本不适合开发，并不是同一个判断。把这两件事分开以后，眼下最需要先照顾的是哪一部分？"]
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.reflectionReadiness = .reflectionOpen
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "形成一个有事实依据的区分"
        )

        model.draft = "我会越来越急，然后一下改很多地方。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame, tenderFrame)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, TurnNextPromptKind.openQuestion)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "现在被这个问题卡住，和你根本不适合开发，并不是同一个判断。把这两件事分开以后，眼下最需要先照顾的是哪一部分？"
        )
        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(persisted?.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(persisted?.semanticMemory.reflectionFrame, tenderFrame)
    }

    func testContextualRevealAppearsOnceWithoutConfirmationAndNaturalResponseCanGroundIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-context-hypothesis-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let confirmedRelationship = TurnContextRelationship(
            relevance: .related,
            userInterpretation: "每次被日程打断后再回来，我会更想马上把卡住的问题解决掉"
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: .init(
                            metricEligibility: [
                                .init(
                                    profileID: "sleep",
                                    metric: "sleepDuration",
                                    status: .qualifies,
                                    preferred: true
                                ),
                            ]
                        )
                    ),
                    responseFocus: "把最近的作息变化作为一个背景线索交给用户判断"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(contextRelationship: confirmedRelationship)
                    ),
                    responseFocus: "沿用户自然补充的情境关系继续探索具体行为"
                ),
            ],
            replies: [
                "还有一个当时的背景线索：你最近几天睡得比平时少一些。把它放在这段经历旁边，你觉得有一点关系吗，还是其实没什么关系？",
                "这种急着解决的感觉出现时，你通常会怎么处理手上的问题？",
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.reflectionReadiness = .reflectionOpen
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.episodeStructure = completeEpisode
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人停下来重新决定下一步",
            realityMapping: "用户把停下来再决定联系到处理当前问题",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "沿用户自己的连接继续探索"
        )
        model.session.trackingCues = [contextualTrackingCue(confidence: .low)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        model.draft = "卡住以后我会越来越急。"
        model.send()
        await waitUntilIdle(model)

        let firstRequest = await core.request(at: 0)
        XCTAssertEqual(firstRequest?.contextualTrackingProfiles?.count, 1)
        XCTAssertEqual(firstRequest?.contextualTrackingProfiles?.first?.domain, "sleep")
        XCTAssertEqual(
            firstRequest?.contextualTrackingProfiles?.first?.metrics.first?.coverage.recentObservedDays,
            2
        )
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)
        XCTAssertEqual(
            model.session.contextualLoadInference?.presentedMetricIdentity,
            ContextualTrackingMetricIdentity(
                profileID: "sleep",
                metric: "sleepDuration"
            )
        )
        XCTAssertEqual(model.session.contextualLoadInference?.state, .notAssessed)
        XCTAssertEqual(model.session.contextualLoadInference?.confidence, .notAssessed)
        XCTAssertNil(model.session.contextualLoadInference?.dialogueHypothesis)
        XCTAssertNil(model.session.semanticMemory.contextRelationship)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "contextRelationship")
        let revealReply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(revealReply.contains("对吗"))
        XCTAssertFalse(revealReply.contains("是不是这样"))
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .openQuestion)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "contextual_profile_reveal_offered_in_exploration"
            }
        )

        model.draft = "每次被日程打断后再回来，我就更想马上把问题解决掉。"
        model.send()
        await waitUntilIdle(model)

        let secondRequest = await core.request(at: 1)
        XCTAssertNil(secondRequest?.contextualTrackingProfiles)
        XCTAssertEqual(model.session.semanticMemory.contextRelationship, confirmedRelationship)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .relevant)
        XCTAssertEqual(
            model.session.contextualLoadInference?.presentedMetricIdentity,
            ContextualTrackingMetricIdentity(
                profileID: "sleep",
                metric: "sleepDuration"
            )
        )
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action == "contextual_profile_reveal_offered_in_exploration"
            }.count,
            1
        )
    }

    func testExplicitZeroTrackingReviewDoesNotRevealOrDelayTender() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-context-reviewed-zero-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: rejectedSleepTrackingDecision()
                    ),
                    responseFocus: "承接已经形成的现实关系并进入下一步反思"
                ),
            ],
            replies: ["这种怀疑和持续卡住之间的关系已经很清楚了，我们可以从这里继续看看这个判断本身。"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.episodeStructure = completeEpisode
        model.session.semanticMemory.selfCriticalStatement = "能力不足"
        model.session.semanticMemory.selfCriticismLink =
            "反复修改仍没有效果后开始怀疑自己 -> 能力不足"
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人面对持续的风决定如何处理正在晾晒的东西",
            realityMapping: "用户在持续出现问题时不断修改处理方式",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "沿用户自己的连接继续探索"
        )
        model.session.trackingCues = [contextualTrackingCue(confidence: .low)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        model.draft = "就是卡久了以后，我会觉得自己能力不够。"
        model.send()
        await waitUntilIdle(model)

        let firstRequest = await core.request(at: 0)
        XCTAssertEqual(firstRequest?.contextualTrackingProfiles?.first?.profileID, "sleep")
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .reviewedNotUsed)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertNil(model.session.semanticMemory.reflectionFrame)
        XCTAssertTrue(LLMTurnContextualTrackingProfile.currentV5Profiles(in: model.session).isEmpty)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "contextual_profiles_reviewed_without_reveal"
            }
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "contextual_profile_reveal_offered_in_exploration"
            }
        )
    }

    func testSelectedTrackingIsNotPersistedAsPresentedWhenWriterFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-tracking-unseen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: selectedSleepTrackingDecision()
                    ),
                    responseFocus: "展示一个背景线索"
                ),
            ],
            replies: []
        )
        let store = SessionStore(directory: directory)
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: store,
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "继续现实反思"
        )
        model.session.trackingCues = [contextualTrackingCue(confidence: .high)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        model.draft = "这件事让我越来越怀疑自己。"
        model.send()
        await waitUntilIdle(model)

        let writeCount = await core.writeCount()
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .notReviewed)
        XCTAssertNil(model.session.contextualLoadInference?.presentedMetricIdentity)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("contextual_profile_reveal_offered_")
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "current_v5_core_writer_unavailable"
            }
        )
        let persisted = try await store.load(id: model.session.id)
        XCTAssertEqual(persisted?.contextualLoadInference?.relevance, .notReviewed)
        XCTAssertNil(persisted?.contextualLoadInference?.presentedMetricIdentity)
    }

    func testEligibleTrackingReviewKeepsOmissionPendingButRejectsUnknownSelection() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        session.trackingCues = [contextualTrackingCue(confidence: .low)]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)

        let omitted = try gate.authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "继续现实探索"
            ),
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertNil(omitted.contextualTrackingMetricRef)
        XCTAssertNil(omitted.projectedPlan.memoryUpdate.contextCueOffered)

        XCTAssertThrowsError(
            try gate.authorize(
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: .init(
                            metricEligibility: [
                                .init(
                                    profileID: "unknown",
                                    metric: "sleepDuration",
                                    status: .qualifies,
                                    preferred: true
                                ),
                            ]
                        )
                    ),
                    responseFocus: "继续现实探索"
                ),
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .payloadInvalid(failure: .contextualTrackingDecisionInvalid)
            )
        }
    }

    func testTrackingSelectionAllowsAtMostOneEligibleProfile() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        session.trackingCues = [
            contextualTrackingCue(confidence: .low),
            contextualTrackingCue(confidence: .low, metric: .steps),
        ]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )
        XCTAssertEqual(
            Set(LLMTurnContextualTrackingProfile.currentV5Profiles(in: session).map(\.profileID)),
            Set(["sleep", "activity"])
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: .init(
                            metricEligibility: [
                                .init(
                                    profileID: "sleep",
                                    metric: "sleepDuration",
                                    status: .qualifies,
                                    preferred: true
                                ),
                                .init(
                                    profileID: "activity",
                                    metric: "steps",
                                    status: .qualifies,
                                    preferred: true
                                ),
                            ]
                        )
                    ),
                    responseFocus: "选择一个背景线索"
                ),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .payloadInvalid(failure: .contextualTrackingDecisionInvalid)
            )
        }
    }

    func testTrackingReviewRequiresCompleteMetricCoverageAndCompilesExactPreferredMetric() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        session.trackingCues = [
            contextualTrackingCue(confidence: .high, metric: .sleepDuration),
            contextualTrackingCue(confidence: .high, metric: .sleepTiming),
            contextualTrackingCue(confidence: .high, metric: .steps),
        ]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )
        let selectedMetricBeforeScoping = try XCTUnwrap(
            LLMTurnContextualTrackingProfile.currentV5Profiles(in: session)
                .first(where: { $0.profileID == "sleep" })?
                .metrics.first(where: { $0.metric == "sleepTiming" })
        )
        let anchorDay = try XCTUnwrap(selectedMetricBeforeScoping.recentDaily.last?.date)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = Calendar.current.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        session.context.eventDate = try XCTUnwrap(dayFormatter.date(from: anchorDay))
        session.eventDateIsUserSpecified = true
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        XCTAssertThrowsError(
            try gate.authorize(
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: .init(
                            metricEligibility: [
                                .init(
                                    profileID: "sleep",
                                    metric: "sleepTiming",
                                    status: .qualifies,
                                    preferred: true
                                ),
                            ]
                        )
                    ),
                    responseFocus: "展示一个背景线索"
                ),
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .payloadInvalid(failure: .contextualTrackingDecisionInvalid)
            )
        }

        let authorized = try gate.authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(
                    contextualTrackingDecision: .init(
                        metricEligibility: [
                            .init(
                                profileID: "sleep",
                                metric: "sleepDuration",
                                status: .doesNotQualify,
                                preferred: false
                            ),
                            .init(
                                profileID: "sleep",
                                metric: "sleepTiming",
                                status: .qualifies,
                                preferred: true
                            ),
                            .init(
                                profileID: "activity",
                                metric: "steps",
                                status: .qualifies,
                                preferred: false
                            ),
                        ]
                    )
                ),
                responseFocus: "展示一个背景线索"
            ),
            for: session,
            allowedSemanticOperations: allowed
        )

        let expectedIdentity = ContextualTrackingMetricIdentity(
            profileID: "sleep",
            metric: "sleepTiming"
        )
        XCTAssertEqual(authorized.contextualTrackingMetricRef, expectedIdentity)
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).contextualTrackingMetricRef,
            expectedIdentity
        )
        let scopedEvidence = try XCTUnwrap(authorized.contextualTrackingMetricEvidence)
        XCTAssertEqual(scopedEvidence.metric, "sleepTiming")
        XCTAssertEqual(scopedEvidence.recentDaily.map(\.date), [anchorDay])
        XCTAssertEqual(scopedEvidence.coverage.recentObservedDays, 1)
        XCTAssertEqual(scopedEvidence.coverage.recentExpectedDays, 1)
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized)
                .contextualTrackingMetricEvidence,
            scopedEvidence
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.contextCueOffered, true)
        let memoryJSON = String(
            data: try JSONEncoder().encode(authorized.projectedPlan.memoryUpdate),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(memoryJSON.contains("metricEligibility"))
        XCTAssertFalse(memoryJSON.contains("sleepTiming"))
    }

    func testExplorationLinkCanEnterTenderWhileTrackingReviewRemainsPending() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "开发能力很差"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "修补后的风筝可能继续飞，也可能再次损坏",
            realityMapping: "用户持续修改但项目仍然卡住",
            source: .userAuthored
        )
        session.trackingCues = [contextualTrackingCue(confidence: .low)]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        selfCriticismLink: "持续修改仍没有进展以后逐渐开始怀疑自己 -> 开发能力很差"
                    )
                ),
                responseFocus: "承接已经形成的累积关系"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.contextCueOffered)
        var candidate = session
        candidate.semanticMemory.apply(authorized.projectedPlan.memoryUpdate)
        XCTAssertFalse(LLMTurnContextualTrackingProfile.currentV5Profiles(in: candidate).isEmpty)
    }

    func testFirstTenderAtomicallyRecordsContextRelationshipAndTenderFrame() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticalStatement = "开发能力很差"
        session.semanticMemory.selfCriticismLink =
            "持续修改仍没有进展以后逐渐开始怀疑自己 -> 开发能力很差"
        session.semanticMemory.episodeStructure = .init(
            concreteFacts: ["持续修改仍没有进展"]
        )
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "contextRelationship",
            focus: "assess_contextual_cue_relation"
        )
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .offered
        )
        let relationship = TurnContextRelationship(
            relevance: .uncertain,
            userInterpretation: nil
        )
        let tenderDelta = "持续修改却没有进展是当前的困难，但这段经历不足以单独支持更广的能力判断。"

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        contextRelationship: relationship,
                        reflectionFrame: .init(
                            mode: .tender,
                            action: .softenGlobalSelfJudgment,
                            evidenceBasis: [
                                .init(source: .episode, content: "持续修改仍没有进展"),
                                .init(source: .cardRealityConnection, content: "现实关系"),
                            ],
                            dimensions: [],
                            reflectionDelta: tenderDelta,
                            fierceEvidence: nil
                        )
                    )
                ),
                responseFocus: "先保留这个背景线索的不确定性"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.contextRelationship, relationship)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            tenderDelta
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "tenderReflection")
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "respond_to_or_revise_bounded_tender_understanding"
        )
    }

    func testEarlyTenderTrackingOmissionDoesNotBlockFrameAndKeepsWindowOpen() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismLink =
            "反复修改没有效果后，逐渐把受阻解释成能力不足"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人持续修补一个物件",
            realityMapping: "用户也在持续修改仍未解决的问题",
            source: .userAuthored
        )
        session.trackingCues = [contextualTrackingCue(confidence: .low)]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )
        let tenderFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: session.semanticMemory.selfCriticismLink!)
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "持续受阻本身不足以确定整体能力",
            fierceEvidence: nil
        )
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)

        let omitted = try gate.authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(reflectionFrame: tenderFrame)
                ),
                responseFocus: tenderFrame.reflectionDelta
            ),
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertNil(omitted.projectedPlan.memoryUpdate.contextCueOffered)
        var pendingSession = session
        pendingSession.semanticMemory.apply(omitted.projectedPlan.memoryUpdate)
        XCTAssertFalse(LLMTurnContextualTrackingProfile.currentV5Profiles(in: pendingSession).isEmpty)

        let reviewed = try gate.authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(reflectionFrame: tenderFrame),
                    contextualTrackingDecision: rejectedSleepTrackingDecision()
                ),
                responseFocus: tenderFrame.reflectionDelta
            ),
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertNil(reviewed.contextualTrackingMetricRef)
        XCTAssertEqual(reviewed.projectedPlan.memoryUpdate.contextCueOffered, false)
    }

    func testEarlyTenderTrackingOmissionCommitsWithoutCorrectionAndRemainsPending() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-tracking-review-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let tenderFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(
                    source: .episode,
                    content: "反复修改没有效果后，逐渐把受阻解释成能力不足"
                ),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "持续受阻本身不足以确定整体能力",
            fierceEvidence: nil
        )
        let omittedDecision = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: tenderFrame)
            ),
            responseFocus: "更准确地区分当前受阻和整体能力判断"
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [omittedDecision],
            replies: ["一直卡在这里确实很消耗，但眼前的受阻还不能替整段能力下结论。"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.selfCriticismLink =
            "反复修改没有效果后，逐渐把受阻解释成能力不足"
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人持续修补一个物件",
            realityMapping: "用户也在持续修改仍未解决的问题",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "形成有证据的区分"
        )
        model.session.trackingCues = [contextualTrackingCue(confidence: .low)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        model.draft = "一直没有进展，确实让我越来越怀疑自己。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .notReviewed)
        XCTAssertFalse(LLMTurnContextualTrackingProfile.currentV5Profiles(in: model.session).isEmpty)
        let committedTrackingFrame = try XCTUnwrap(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(committedTrackingFrame.mode, tenderFrame.mode)
        XCTAssertEqual(committedTrackingFrame.action, tenderFrame.action)
        XCTAssertEqual(committedTrackingFrame.reflectionDelta, tenderFrame.reflectionDelta)
        XCTAssertTrue(
            committedTrackingFrame.evidenceBasis.contains {
                $0.source == .episode
                    && $0.content == "反复修改没有效果后，逐渐把受阻解释成能力不足"
            }
        )
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "一直卡在这里确实很消耗，但眼前的受阻还不能替整段能力下结论。"
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("current_v5_core_single_correction_")
                    || $0.action.hasPrefix("current_v5_core_final_rejection_")
                    || $0.action == "current_v5_core_planner_or_gate_unavailable"
            }
        )
    }

    func testSelectedTrackingCanAccompanyTheSameTurnTenderTransition() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己能力不足"
        session.semanticMemory.selfCriticismLink =
            "长期没有进展以后逐渐怀疑自己 -> 自己能力不足"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人经历劳累后停下来接水",
            realityMapping: "用户反复排查没有效果时也会短暂停下来",
            source: .userAuthored
        )
        session.trackingCues = [contextualTrackingCue(confidence: .low)]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(
                    contextualTrackingDecision: selectedSleepTrackingDecision()
                ),
                responseFocus: "把作息变化作为一个背景线索交给用户判断"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(
            authorized.contextualTrackingMetricRef,
            ContextualTrackingMetricIdentity(
                profileID: "sleep",
                metric: "sleepDuration"
            )
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.contextCueOffered, true)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "contextRelationship")
    }

    func testSelectedTrackingRemainsAvailableAtEarlyTenderBoundary() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismLink =
            "长期没有进展以后，逐渐把受阻解释成自己能力不足"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人经历劳累后停下来接水",
            realityMapping: "用户反复排查没有效果时也会短暂停下来",
            source: .userAuthored
        )
        session.trackingCues = [contextualTrackingCue(confidence: .low)]
        session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        XCTAssertEqual(
            LLMTurnContextualTrackingProfile.currentV5Profiles(in: session).map(\.profileID),
            ["sleep"]
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        reflectionFrame: TurnReflectionFrame(
                            mode: .tender,
                            action: .softenGlobalSelfJudgment,
                            evidenceBasis: [],
                            dimensions: [],
                            reflectionDelta: "当前确认的是长期没有进展；这不足以独自确定整体能力",
                            fierceEvidence: nil
                        )
                    ),
                    contextualTrackingDecision: selectedSleepTrackingDecision()
                ),
                responseFocus: "当时的睡眠状况可能也让排查问题更费力，但这不是对原因的定论"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueTenderReflection)
        XCTAssertEqual(
            authorized.contextualTrackingMetricRef,
            ContextualTrackingMetricIdentity(
                profileID: "sleep",
                metric: "sleepDuration"
            )
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.contextCueOffered, true)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)

        session.semanticMemory.reflectionFrame = authorized.projectedPlan.memoryUpdate.reflectionFrame
        session.contextualLoadInference?.relevance = .offered
        let relationship = TurnContextRelationship(
            relevance: .partlyRelated,
            userInterpretation: "当时睡得少可能让我更难集中排查，但不能确定就是这个原因"
        )
        let followUp = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .synthesizeDirectReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        contextRelationship: relationship,
                        reflectionFrame: TurnReflectionFrame(
                            mode: .tender,
                            action: .synthesizeUnderstanding,
                            evidenceBasis: [],
                            dimensions: [],
                            reflectionDelta: "当时睡得少是否增加排查难度仍不确定；当前受阻也不足以独自确定整体能力",
                            fierceEvidence: nil
                        )
                    )
                ),
                responseFocus: "当时睡得少可能增加了排查难度，但这不是原因定论；当前受阻也不足以单独证明整体能力问题",
                reflectionProgressionDecision: .init(
                    meaning: .synthesize,
                    candidateRef: nil
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(
            followUp.projectedPlan.memoryUpdate.contextRelationship,
            relationship
        )
        XCTAssertEqual(followUp.operation, .synthesizeDirectReflection)
        XCTAssertEqual(followUp.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
    }

    func testMissingTrackingDecisionKeepsReviewPendingDuringExploration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-context-decision-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "继续现实探索"
                ),
            ],
            replies: ["这种怀疑和一直卡住之间，是怎么连起来的？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面关系",
            realityMapping: "现实关系",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "继续现实探索"
        )
        model.session.trackingCues = [contextualTrackingCue(confidence: .low)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )

        model.draft = "卡久了以后，我就会开始怀疑自己。"
        model.send()
        await waitUntilIdle(model)

        let planCount = await core.planCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .notReviewed)
        XCTAssertFalse(LLMTurnContextualTrackingProfile.currentV5Profiles(in: model.session).isEmpty)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            "这种怀疑和一直卡住之间，是怎么连起来的？"
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("current_v5_core_single_correction")
            }
        )
    }

    func testContextualCueMayBeAbsentAndARejectedOfferDoesNotReturn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-context-absent-rejected-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rejectedRelationship = TurnContextRelationship(
            relevance: .unrelated,
            userInterpretation: nil
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "没有情境线索时，只沿现有现实关系继续"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        contextualTrackingDecision: .init(
                            metricEligibility: [
                                .init(
                                    profileID: "sleep",
                                    metric: "sleepDuration",
                                    status: .qualifies,
                                    preferred: true
                                ),
                            ]
                        )
                    ),
                    responseFocus: "只暂定地提出一次与现有关系相邻的情境假设"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(contextRelationship: rejectedRelationship)
                    ),
                    responseFocus: "接受用户拒绝，回到已经 grounded 的现实关系"
                ),
            ],
            replies: [
                "这个问题一直没有解决时，它后来怎么变成了对自己能力的判断？",
                "你最近几天一直睡得不多。这个问题没有解决时，哪一步最容易让你开始怀疑自己的能力？",
                "那就不把最近的节奏放进这件事里。真正把项目受阻连到能力判断上的是什么？",
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.reflectionPhase = .exploratory
        model.session.semanticMemory.episodeStructure = completeEpisode
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人停下来重新决定下一步",
            realityMapping: "用户把停下来再决定联系到处理当前问题",
            source: .userAuthored
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "沿用户自己的连接继续探索"
        )

        model.draft = "问题一直没解决，我就开始怀疑自己的能力。"
        model.send()
        await waitUntilIdle(model)
        let requestWithoutCue = await core.request(at: 0)
        XCTAssertNil(requestWithoutCue?.contextualTrackingProfiles)

        model.session.trackingCues = [contextualTrackingCue(confidence: .low)]
        model.session.contextualLoadInference = ContextualLoadInference(
            state: .notAssessed,
            confidence: .notAssessed,
            activation: .unknown,
            energy: .unknown,
            observationWindow: nil,
            supportingInsightIDs: [],
            supportingMetrics: [],
            alternativeExplanations: [],
            dialogueHypothesis: nil,
            relevance: .notReviewed
        )
        model.draft = "我还说不清楚。"
        model.send()
        await waitUntilIdle(model)
        let requestOfferingCue = await core.request(at: 1)
        XCTAssertEqual(requestOfferingCue?.contextualTrackingProfiles?.count, 1)
        XCTAssertEqual(requestOfferingCue?.contextualTrackingProfiles?.first?.domain, "sleep")
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .offered)

        model.draft = "不是，最近的节奏跟这件事没有关系。"
        model.send()
        await waitUntilIdle(model)

        let requestResolvingCue = await core.request(at: 2)
        XCTAssertNil(requestResolvingCue?.contextualTrackingProfiles)
        XCTAssertEqual(model.session.semanticMemory.contextRelationship, rejectedRelationship)
        XCTAssertEqual(model.session.contextualLoadInference?.relevance, .irrelevant)
        XCTAssertEqual(
            model.session.studyEvents.filter {
                $0.action == "contextual_profile_reveal_offered_in_exploration"
            }.count,
            1
        )
    }

    func testRealityConnectionInvitationCannotRepeatAfterItWasAsked() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["桌上的照片", "站起来的人", "门外的钟"]
        )
        session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["照片", "人物", "钟声"],
            projectiveFocus: "人物如何面对过去与新的开始",
            relationOrAction: "人物站在过去与新的开始之间",
            anticipatedChangeOrChoice: "带着不舍继续向前"
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "这个画面理解让你想到自己的什么经历"
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .inviteRealityConnection,
            semanticEvidencePatch: .init(),
            responseFocus: "再次询问同一个现实连接"
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            guard case let CurrentV5CoreError.operationNotAllowed(
                operation,
                allowedSemanticOperations
            ) = error else {
                return XCTFail("Expected repeated connection invitation rejection, got \(error)")
            }
            XCTAssertEqual(operation, .inviteRealityConnection)
            XCTAssertTrue(allowedSemanticOperations.contains(.offerCardConnectionScaffold))
            XCTAssertTrue(allowedSemanticOperations.contains(.continueOpenCardConnection))
            XCTAssertFalse(allowedSemanticOperations.contains(.inviteRealityConnection))
        }
    }

    func testPlannerDTOCannotCarryLegacyExecutionFields() throws {
        let data = Data(
            """
            {
              "semanticOperation":"clarifyEvent",
              "semanticEvidencePatch":{"memoryUpdate":{
                "nextPrompt":{"kind":"openQuestion","purpose":"legacy"},
                "cardObservationEvidence":{"userDescribedElements":["一个人在扶架子"]}
              },"cardConnectionTurnOutcome":null},
              "responseFocus":"邀请随机反思卡",
              "requestedStage":"complete",
              "replyIntent":"completeConversation",
              "localAction":{"kind":"completeSession","trackingCueIDs":[]},
              "nextPrompt":{"kind":"none"}
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(CurrentV5PlannerOutput.self, from: data)
        XCTAssertEqual(decoded.semanticOperation, .clarifyEvent)
        XCTAssertEqual(
            decoded.semanticEvidencePatch.memoryUpdate.cardObservationEvidence?.userDescribedElements,
            ["一个人在扶架子"]
        )
        // The DTO has no executable fields, so the contradictory legacy tuple has no runtime path.
    }

    func testCorrectionTransportCarriesOneIssueAndNoParallelRequirementList() throws {
        let correction = CurrentV5PlannerCorrection(
            rejectedOperation: .continueTenderReflection,
            rejectedDraft: .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "形成 Tender 理解"
            ),
            reason: .projectionInvalid,
            payloadFailure: nil,
            projectionFailure: .tenderDeltaMissing,
            issue: .init(
                fieldPath: "semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta",
                violation: .empty,
                requiredConditions: [.provideConcreteReflectionDelta]
            ),
            allowedSemanticOperations: [.continueTenderReflection],
            recoveryPolicy: .repairSameOperation
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(correction))
                as? [String: Any]
        )
        XCTAssertNil(object["requiredConditions"])
        let issue = try XCTUnwrap(object["issue"] as? [String: Any])
        XCTAssertEqual(
            issue["fieldPath"] as? String,
            "semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta"
        )
        XCTAssertEqual(issue["violation"] as? String, "empty")
        XCTAssertEqual(
            issue["requiredConditions"] as? [String],
            ["provideConcreteReflectionDelta"]
        )
    }

    func testSharedBackendPlannerFixtureDecodesAndPassesCurrentV5Gate() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/current-v5-planner-output-v40.json")
        let output = try JSONDecoder().decode(
            CurrentV5PlannerOutput.self,
            from: Data(contentsOf: fixtureURL)
        )

        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismStatus = .present
        session.semanticMemory.selfCriticalStatement = "我可能根本不适合做研究"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "最后一块瓷砖形状不合适，可能更换或修改",
            realityMapping: "论文收到反馈后仍有需要修改的部分",
            source: .userAuthored
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueTenderReflection)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticismLink,
            "论文需要修改后扩大了整体判断 -> 我可能根本不适合做研究"
        )
    }

    func testCurrentWireCompilerBuildsCanonicalLinkFromStructuredProviderMeaning() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "reflectionTurnOutcome":{
                    "outcome":"explorationComplete",
                    "selfCriticismLink":{
                      "reality":"反复修改以后问题仍然增加，项目一直无法推进",
                      "selfJudgment":"能力不够"
                    },
                    "tenderDelta":"目前能确定的是这段调试持续受阻，而不是对全部开发能力的结论"
                  },
                  "semanticEvidencePatch":{"memoryUpdate":{}},
                  "responseFocus":""
                }
                """.utf8
            ),
            allowedSemanticOperations: [.continueExploratoryReflection],
            canonicalSelfCriticalStatement: "我感觉自己开发能力很差"
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉自己开发能力很差"

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: [.continueExploratoryReflection]
        )

        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticismLink,
            "反复修改以后问题仍然增加，项目一直无法推进 -> 我感觉自己开发能力很差"
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "目前能确定的是这段调试持续受阻，而不是对全部开发能力的结论"
        )
    }

    func testCurrentWireCompilerDropsTupleLinkFromParallelExplorationPatch() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "reflectionTurnOutcome":{"outcome":"explorationContinue"},
                  "semanticEvidencePatch":{"memoryUpdate":{
                    "selfCriticismLink":["长期没有推进以后逐渐开始怀疑自己","模型改写的判断"]
                  }},
                  "responseFocus":"继续当前探索"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.continueExploratoryReflection],
            canonicalSelfCriticalStatement: "我感觉自己开发能力很差"
        )

        XCTAssertNil(output.semanticEvidencePatch.memoryUpdate.selfCriticismLink)
    }

    func testAmbiguousStructuredLinkDoesNotBecomeATransportFailure() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "reflectionTurnOutcome":{"outcome":"explorationContinue"},
                  "semanticEvidencePatch":{"memoryUpdate":{
                    "selfCriticismLink":{"providerSpecific":{"nested":true}}
                  }},
                  "responseFocus":"继续澄清现实困难与自我判断的关系"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.continueExploratoryReflection],
            canonicalSelfCriticalStatement: "我感觉自己开发能力很差"
        )
        XCTAssertNil(output.semanticEvidencePatch.memoryUpdate.selfCriticismLink)

        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉自己开发能力很差"
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: [.continueExploratoryReflection]
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.selfCriticismLink)
    }

    func testCurrentWireCompilerOwnsEventStatusAndPostTurnTransition() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "semanticOperation":"clarifyEvent",
                  "semanticEvidencePatch":{"memoryUpdate":{"episodeStructure":{
                    "concreteFacts":["昨天汇报时放错了旧版本图片"],
                    "eventProcess":["展示时发现放错后马上换回新版"],
                    "behaviorEvidence":["汇报前没有核对图片版本"],
                    "eventProcessStatus":"absent",
                    "behaviorEvidenceStatus":"absent"
                  }}},
                  "responseFocus":"事件已足够，简短邀请抽卡"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.clarifyEvent]
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.stage = .eventDisclosure
        session.condition = .cardMediated

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(output, for: session, allowedSemanticOperations: [.clarifyEvent])

        XCTAssertEqual(authorized.operation, .clarifyEvent)
        XCTAssertEqual(authorized.projectedPlan.requestedStage, .cardConsent)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.eventProcessStatus,
            .present
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.behaviorEvidenceStatus,
            .present
        )
    }

    func testCurrentWireCompilerBuildsConnectionProvenanceFromNeutralRealityAct() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "semanticOperation":"continueOpenCardConnection",
                  "semanticEvidencePatch":{"memoryUpdate":{},"cardConnectionEvidence":{
                    "realityMapping":"汇报失误后因为尴尬想自己待一会",
                    "kind":"candidateAccepted","source":"userAccepted","status":"confirmed"
                  }},
                  "responseFocus":"沿现实连接继续探索"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.continueOpenCardConnection, .offerCardConnectionScaffold]
        )
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["关着门的房间", "独处的人"]
        )
        session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["房间里的人"],
            projectiveFocus: "暂时独处",
            relationOrAction: "人物关门后留在房间里",
            anticipatedChangeOrChoice: "之后可能重新联系"
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let connection = try XCTUnwrap(
            authorized.projectedPlan.memoryUpdate.cardRealityConnection
        )
        XCTAssertEqual(authorized.operation, .continueOpenCardConnection)
        XCTAssertEqual(authorized.projectedPlan.requestedStage, .directReflection)
        XCTAssertEqual(connection.source, .userAuthored)
        XCTAssertEqual(connection.status, .confirmed)
        XCTAssertEqual(connection.realityMapping, "汇报失误后因为尴尬想自己待一会")
        XCTAssertTrue(connection.imageRelation.contains("人物关门后留在房间里"))
    }

    func testRealityRelationBuildsConnectionWithoutOptionalDevelopmentEvidence() throws {
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueOpenCardConnection,
            semanticEvidencePatch: .init(
                cardConnectionEvidence: .init(
                    imageRelation: nil,
                    realityMapping: "汇报已经继续，但回来以后对再次出错的担心仍然持续"
                )
            ),
            responseFocus: "沿现实关系进入反思"
        )
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: [
                "人物正在搬家",
                "房间基本收拾好了，但还留着一些东西",
            ]
        )
        session.semanticMemory.cardDevelopmentEvidence = nil
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let connection = try XCTUnwrap(
            authorized.projectedPlan.memoryUpdate.cardRealityConnection
        )

        XCTAssertEqual(authorized.operation, .continueOpenCardConnection)
        XCTAssertEqual(authorized.projectedPlan.requestedStage, .directReflection)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.cardDevelopmentEvidence)
        XCTAssertEqual(connection.source, .userAuthored)
        XCTAssertEqual(connection.status, .confirmed)
        XCTAssertEqual(
            connection.realityMapping,
            "汇报已经继续，但回来以后对再次出错的担心仍然持续"
        )
        XCTAssertTrue(connection.imageRelation.contains("人物正在搬家"))
        XCTAssertTrue(connection.imageRelation.contains("还留着一些东西"))
    }

    func testCurrentWireCompilerBuildsTenderModeActionAndEvidenceProvenance() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "semanticOperation":"continueTenderReflection",
                  "semanticEvidencePatch":{"memoryUpdate":{"reflectionFrame":{
                    "mode":"fierce","action":"identifyChangeDirection",
                    "evidenceBasis":["这次确实放错了一张图"],
                    "dimensions":["mindfulness"],
                    "reflectionDelta":"这次失误需要面对，但不足以单独证明我很蠢"
                  }}},
                  "responseFocus":"这次失误需要面对，但不足以单独证明我很蠢"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.continueTenderReflection]
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticalStatement = "我很蠢"
        session.semanticMemory.selfCriticismLink = "放错一张图后把这次失误扩大成了我很蠢"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "人物停下来确认手里的东西",
            realityMapping: "现实中当时没有停下来核对版本",
            source: .userAuthored
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let frame = try XCTUnwrap(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(frame.mode, .tender)
        XCTAssertEqual(frame.action, .softenGlobalSelfJudgment)
        XCTAssertNil(frame.fierceEvidence)
        XCTAssertTrue(frame.evidenceBasis.contains { $0.source == .episode })
        XCTAssertTrue(frame.evidenceBasis.contains { $0.source == .cardRealityConnection })
    }

    func testCurrentWireCompilerBuildsPracticeIdentityStatusSourceAndKind() throws {
        let output = try decodeCurrentV5PlannerWireOutput(
            Data(
                """
                {
                  "reflectionTurnOutcome":{"outcome":"synthesisAccepted"},
                  "semanticEvidencePatch":{"memoryUpdate":{"practiceTransition":{"proposal":{
                    "kind":"protect","content":"汇报前用一分钟核对图片版本",
                    "basis":"episodeStructure.behaviorEvidence.0","id":"model-id",
                    "status":"confirmed","source":"userRevised"
                  }}}},
                  "responseFocus":"提出一个小而具体的行动"
                }
                """.utf8
            ),
            allowedSemanticOperations: [.proposePractice]
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .synthesis
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["汇报时展示了旧版本图片"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["汇报前没有核对版本"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .fierce,
            action: .synthesizeUnderstanding,
            evidenceBasis: [.init(source: .episode, content: "汇报前没有核对版本")],
            dimensions: [.mindfulness],
            reflectionDelta: "需要修复核对环节，而不是攻击整个人",
            fierceEvidence: .init(
                behavior: "汇报前没有核对版本",
                impact: "展示了旧版本图片",
                direction: .repair
            )
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(output, for: session, allowedSemanticOperations: [.proposePractice])
        let transition = try XCTUnwrap(authorized.projectedPlan.memoryUpdate.practiceTransition)
        let proposal = try XCTUnwrap(transition.proposal)
        XCTAssertFalse(transition.transactionID.isEmpty)
        XCTAssertEqual(proposal.id, transition.transactionID)
        XCTAssertEqual(proposal.kind, .repair)
        XCTAssertEqual(proposal.status, .pendingConfirmation)
        XCTAssertEqual(proposal.source, .assistantProposed)
    }

    func testDecodedSparseEventEvidenceUsesCanonicalMergeAndAdvances() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .contextualDisclosure
        session.stage = .eventDisclosure
        session.condition = .cardMediated

        let gate = CurrentV5SwiftTurnGate(protocolController: ReflectionProtocolController())
        let first = try decodePlannerOutput(
            """
            {
              "semanticOperation":"clarifyEvent",
              "semanticEvidencePatch":{
                "memoryUpdate":{
                  "episodeStructure":{
                    "concreteFacts":["开发效果很差，bug越改越多"]
                  }
                },
                "cardConnectionTurnOutcome":null
              },
              "responseFocus":"询问事情如何发展"
            }
            """
        )
        let firstTurn = try gate.authorize(
            first,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        session.semanticMemory.apply(firstTurn.projectedPlan.memoryUpdate)

        let second = try decodePlannerOutput(
            """
            {
              "semanticOperation":"clarifyEvent",
              "semanticEvidencePatch":{
                "memoryUpdate":{
                  "episodeStructure":{
                    "concreteFacts":["开发一个chatbot app"],
                    "eventProcess":["起初进展正常，后来为了改善效果持续修改，bug反而增加"]
                  }
                },
                "cardConnectionTurnOutcome":null
              },
              "responseFocus":"询问用户实际做了什么"
            }
            """
        )
        let secondTurn = try gate.authorize(
            second,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        session.semanticMemory.apply(secondTurn.projectedPlan.memoryUpdate)

        XCTAssertEqual(
            session.semanticMemory.episodeStructure?.concreteFacts,
            ["开发效果很差，bug越改越多", "开发一个chatbot app"]
        )
        XCTAssertEqual(session.semanticMemory.episodeStructure?.eventProcessStatus, .present)

        let final = try decodePlannerOutput(
            """
            {
              "semanticOperation":"advanceToCardConsent",
              "semanticEvidencePatch":{
                "memoryUpdate":{
                  "episodeStructure":{
                    "behaviorEvidence":["继续修改，并结合AI建议和自己的方案处理bug"]
                  }
                },
                "cardConnectionTurnOutcome":null
              },
              "responseFocus":"简短承接并邀请随机反思卡"
            }
            """
        )
        let finalTurn = try gate.authorize(
            final,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        session.semanticMemory.apply(finalTurn.projectedPlan.memoryUpdate)

        XCTAssertEqual(finalTurn.projectedPlan.requestedStage, .cardConsent)
        XCTAssertEqual(session.semanticMemory.episodeStructure?.behaviorEvidenceStatus, .present)
        XCTAssertTrue(
            isEventDisclosureCoreComplete(
                EffectiveEventDisclosureState(memory: session.semanticMemory)
            )
        )
    }

    func testPersistedEventContentRepairsUnresolvedPresenceAtDecodeBoundary() throws {
        let memory = try JSONDecoder().decode(
            TurnSemanticMemory.self,
            from: Data(
                """
                {
                  "episodeStructure":{
                    "concreteFacts":["开发一个chatbot app时bug越改越多"],
                    "eventProcessStatus":"unresolved",
                    "eventProcess":["起初正常，持续修改后bug增加"],
                    "behaviorEvidenceStatus":"unresolved",
                    "behaviorEvidence":["结合AI建议和自己的方案继续修改"]
                  }
                }
                """.utf8
            )
        )

        XCTAssertEqual(memory.episodeStructure?.eventProcessStatus, .present)
        XCTAssertEqual(memory.episodeStructure?.behaviorEvidenceStatus, .present)
        XCTAssertTrue(
            isEventDisclosureCoreComplete(EffectiveEventDisclosureState(memory: memory))
        )
    }

    func testUnambiguousCardConsentIsCommittedLocallyAndSwiftDrawsLocally() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-card-consent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacy = RejectingLegacyTurnController()
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .acknowledgeCardConsent,
                    semanticEvidencePatch: .init(),
                    responseFocus: "用户接受随机反思卡"
                ),
            ],
            replies: []
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: legacy,
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardConsent
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.condition = .cardMediated
        model.session.semanticMemory.nextPrompt = .confirmationRequest(target: .cardConsent)

        model.draft = "可以"
        model.send()
        await waitUntilIdle(model)

        let corePlanCalls = await core.planCount()
        let coreWriteCalls = await core.writeCount()
        let legacyPlanCalls = await legacy.planCount()
        XCTAssertEqual(corePlanCalls, 0)
        XCTAssertEqual(coreWriteCalls, 0)
        XCTAssertEqual(legacyPlanCalls, 0)
        XCTAssertEqual(model.session.protocolStage, .cardConsent)
        XCTAssertEqual(model.session.cardDisplayState, .selected)
        XCTAssertNotNil(model.session.card)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_consent_accepted_locally"
            }
        )

        let acceptedMessageID = model.session.messages.last(where: { $0.role == .user })?.id
        let cardID = try XCTUnwrap(model.session.card?.id)
        model.cardDidDisplay(cardID: cardID)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertEqual(model.session.cardDisplayState, .displayed)
        let replies = model.session.messages.filter {
            $0.role == .assistant && $0.replyToMessageID == acceptedMessageID
        }
        XCTAssertEqual(replies.count, 1)
        XCTAssertTrue(replies[0].content.contains("没有固定答案"))
    }

    func testDescriptiveUserAuthoredConnectionCommitsImmediatelyAndEntersExploration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-connection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let connection = TurnCardRealityConnection(
            imageRelation: "画面里的人先停下来重新安排手中的东西，再继续往前",
            realityMapping: "画面里会先停下来，而我改 bug 时会不停地继续修改",
            source: .userAuthored
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueOpenCardConnection,
                    semanticEvidencePatch: .init(
                        cardConnectionEvidence: .init(
                            imageRelation: connection.imageRelation,
                            realityMapping: connection.realityMapping
                        )
                    ),
                    responseFocus: "沿用户指出的明确差异，询问一个具体的现实行为"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "沿用户自己的连接继续看现实中的应对方式"
                ),
            ],
            replies: [
                "画面里会先停下来，你这边却会一直改。越改越停不下来的时候，通常发生了什么？",
                "这种阻力出现时，你通常会怎么处理手上正在修改的部分？",
            ]
        )
        let legacy = RejectingLegacyTurnController()
        let audit = ProtocolExecutionAuditRecorder()
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: legacy,
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            protocolController: .init(executionAudit: audit),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .cardReflection
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardConnection
        model.session.condition = .cardMediated
        let card = CardService().allCards[0]
        let expectedReferenceGuidance = try XCTUnwrap(
            CardService().canonicalReferenceGuidance(for: card)
        )
        model.session.card = card
        model.session.cardDisplayState = .displayed
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["画面里的人", "手中的东西"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["画面里的人", "手中的东西"],
            projectiveFocus: "人物为什么停下来重新安排",
            relationOrAction: "停下来重新安排",
            anticipatedChangeOrChoice: "之后再决定往哪里走"
        )

        model.draft = connection.realityMapping
        model.send()
        await waitUntilIdle(model)

        let capturedEstablishmentRequest = await core.request(at: 0)
        let establishmentRequest = try XCTUnwrap(capturedEstablishmentRequest)
        XCTAssertTrue(
            establishmentRequest.allowedSemanticOperations
                .contains(.continueOpenCardConnection)
        )
        XCTAssertNil(establishmentRequest.card?.reflectionApproaches)
        XCTAssertNil(establishmentRequest.card?.referenceGuidance)

        let corePlanCalls = await core.planCount()
        let coreWriteCalls = await core.writeCount()
        let legacyPlanCalls = await legacy.planCount()
        XCTAssertEqual(corePlanCalls, 1)
        XCTAssertEqual(coreWriteCalls, 1)
        XCTAssertEqual(legacyPlanCalls, 0)
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, connection)
        XCTAssertTrue(model.session.cardGuidanceShared)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
        XCTAssertNil(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "exploratoryReflection")
        XCTAssertFalse(model.session.studyEvents.contains {
            $0.action.contains("current_v5_core_single_correction")
                || $0.action.contains("current_v5_core_final_rejection")
        })
        XCTAssertEqual(audit.count(for: .semanticMapper), 1)
        XCTAssertEqual(audit.count(for: .projector), 1)
        XCTAssertEqual(audit.count(for: .legacySemanticMapper), 0)
        XCTAssertEqual(audit.count(for: .legacyExecutableFallback), 0)
        XCTAssertEqual(audit.count(for: .silentContinuation), 0)

        XCTAssertTrue(model.session.cardWasSetAside)
        model.draft = "我会急着继续改，很难停下来判断。"
        model.send()
        await waitUntilIdle(model)

        let capturedExplorationRequest = await core.request(at: 1)
        let explorationRequest = try XCTUnwrap(capturedExplorationRequest)
        XCTAssertEqual(explorationRequest.protocolStage, .directReflection)
        XCTAssertEqual(
            Set(explorationRequest.allowedSemanticOperations),
            [.continueExploratoryReflection]
        )
        XCTAssertEqual(
            explorationRequest.semanticMemory.cardRealityConnection,
            connection
        )
        XCTAssertEqual(
            explorationRequest.semanticMemory.cardDevelopmentEvidence,
            model.session.semanticMemory.cardDevelopmentEvidence
        )
        XCTAssertEqual(explorationRequest.card?.reflectionApproaches, .standard)
        XCTAssertEqual(
            explorationRequest.card?.referenceGuidance,
            expectedReferenceGuidance
        )
        XCTAssertEqual(explorationRequest.card?.visualScaffolds, [])
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
    }

    func testPlannerResponseFocusIsEphemeralAcrossUserAuthoredConnectionTransition() throws {
        var session = currentCardReflectionSession()
        session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["站在门口的人", "桌上的照片", "门外的钟"]
        )
        session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["站在门口的人", "桌上的照片", "门外的钟"],
            projectiveFocus: "人物如何回应门内与门外的线索",
            relationOrAction: "人物停在旧照片和摆动的钟之间",
            anticipatedChangeOrChoice: "可能继续停留，也可能走向门外"
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )
        let connection = TurnCardRealityConnection(
            imageRelation: "人物停在旧照片和摆动的钟之间，处于中间状态",
            realityMapping: "我直接发出文件，没有停下来做最终确认",
            source: .userAuthored
        )
        let speculativeFocus = "继续让用户选择照片还是钟，并说明哪一个反差最大"
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueOpenCardConnection,
            semanticEvidencePatch: .init(
                cardConnectionEvidence: .init(
                    imageRelation: connection.imageRelation,
                    realityMapping: connection.realityMapping
                )
            ),
            responseFocus: speculativeFocus
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.responseFocus, speculativeFocus)
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "clarify_self_criticism_attribution_relation"
        )
        XCTAssertNotEqual(authorized.projectedPlan.nextPrompt.focus, speculativeFocus)
    }

    func testPostConnectionReferenceGuidanceIsLimitedToExplorationRequests() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-reference-boundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let frame = tenderFrame
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: frame)
                    ),
                    responseFocus: "继续已经形成的 grounded Tender distinction"
                ),
            ],
            replies: ["这次具体的困难需要面对，但它不需要变成对整个人的判决。"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.card = CardService().allCards[0]
        model.session.cardDisplayState = .displayed
        model.session.cardWasSetAside = true
        model.session.cardGuidanceShared = true
        model.session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "人物停下来重新安排手中的东西",
            realityMapping: "我也许需要在继续修改前判断什么已经够用",
            source: .userAuthored
        )
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.reflectionFrame = frame

        model.draft = "这次的问题确实存在，但不等于我什么都做不好。"
        model.send()
        await waitUntilIdle(model)

        let capturedRequest = await core.request(at: 0)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.protocolStage, .directReflection)
        XCTAssertEqual(request.semanticMemory.cardRealityConnection?.status, .confirmed)
        XCTAssertNil(request.card)
    }

    func testCurrentV5PlannerRequestProjectsSemanticEvidenceAndUsesInputOnlyAnswerContext() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "exploratoryReflection",
            focus: "照片已经过去无法改变，继续比较哪一个更沉重"
        )
        session.semanticMemory.cardImageRelation = "legacy image mirror"
        session.semanticMemory.cardRealityMapping = "legacy reality mirror"
        session.semanticMemory.cardInterpretiveTension = "legacy tension"
        session.semanticMemory.candidUnderstanding = "legacy understanding"
        let latestUser = ChatMessage(role: .user, content: "最近的问题让我很着急。")
        let base = LLMTurnControllerRequest(
            trigger: .userMessage,
            protocolStage: .directReflection,
            condition: .cardMediated,
            permissions: ReflectionProtocolController().permissions(for: session),
            recentMessages: [],
            semanticMemory: session.semanticMemory,
            trackingCandidates: [],
            contextualLoadCue: DialogueContextCue(
                hypothesis: "Swift 生成的旧假设不应进入 current-v5",
                confidence: .high,
                relevance: .notReviewed,
                usageBoundary: "legacy only"
            ),
            contextualTrackingProfiles: [
                LLMTurnContextualTrackingProfile(
                    profileID: "sleep",
                    domain: "sleep",
                    metrics: [
                        LLMTurnTemporalMetricProfile(
                            metric: "sleepDuration",
                            unit: "hours",
                            recentDaily: [
                                .init(date: "2026-08-07", value: 6.0, sampleCount: 4),
                                .init(date: "2026-08-08", value: 6.2, sampleCount: 3),
                            ],
                            recentMedian: 6.1,
                            recentTotal: nil,
                            recentRecordCount: nil,
                            baselineMedian: 6.4,
                            coverage: .init(
                                recentObservedDays: 2,
                                recentExpectedDays: 7,
                                recentSampleCount: 7,
                                baselineObservedDays: 10,
                                baselineExpectedDays: 28
                            )
                        ),
                    ]
                ),
            ],
            eventAnchorDate: "2026-08-08",
            cardMappingConfirmed: true,
            card: nil,
            protocolCorrection: nil
        )

        let request = CurrentV5TurnRequest(
            base: base,
            messages: [latestUser],
            allowedSemanticOperations: [.continueExploratoryReflection]
        )

        XCTAssertEqual(request.latestAnswerContext?.purpose, "exploratoryReflection")
        XCTAssertEqual(request.reflectionMode, .exploratory)
        XCTAssertEqual(request.eventAnchorDate, "2026-08-08")
        XCTAssertEqual(
            session.semanticMemory.nextPrompt?.focus,
            "照片已经过去无法改变，继续比较哪一个更沉重"
        )

        let encoded = try JSONEncoder().encode(request)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for residue in [
            "nextPrompt",
            "replyIntent",
            "localAction",
            "requestedStage",
            "contextualLoadCue",
            "dialogueHypothesis",
        ] {
            XCTAssertFalse(
                encodedText.contains("\"\(residue)\""),
                "Planner request leaked \(residue)"
            )
        }
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let memory = try XCTUnwrap(object["semanticMemory"] as? [String: Any])
        for residue in [
            "nextPrompt",
            "replyIntent",
            "localAction",
            "requestedStage",
            "reflectionPhase",
            "cardImageRelation",
            "cardRealityMapping",
            "cardInterpretiveTension",
            "candidUnderstanding",
        ] {
            XCTAssertNil(memory[residue], "Planner memory leaked \(residue)")
        }
        XCTAssertNotNil(object["latestAnswerContext"])
        XCTAssertEqual(object["reflectionMode"] as? String, "exploratory")
        let trackingProfiles = try XCTUnwrap(
            object["contextualTrackingProfiles"] as? [[String: Any]]
        )
        XCTAssertEqual(trackingProfiles.count, 1)
        XCTAssertEqual(trackingProfiles.first?["domain"] as? String, "sleep")
        XCTAssertFalse(encodedText.contains("\"contextualTrackingEvidence\""))
        XCTAssertFalse(encodedText.contains("\"dataQuality\""))
        XCTAssertFalse(encodedText.contains("\"patternStrength\""))
        XCTAssertFalse(encodedText.contains("\"dialogueHypothesis\""))
    }

    func testIncompleteExplorationDropsMisplacedTenderFrameWithoutInterrupting() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "照片需要等待显影后才能展示",
            realityMapping: "bug处理好以后流程才能继续",
            source: .userAuthored
        )

        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    situationUnderstanding: "流程被bug阻塞时，用户会变得急躁",
                    reflectionFrame: tenderFrame,
                    reflectionPhase: .tender
                )
            ),
            responseFocus: "探索急躁时用户实际会怎样处理bug"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.situationUnderstanding,
            "流程被bug阻塞时，用户会变得急躁"
        )
    }

    func testTenderProgressionDecisionIsTheSingleAuthorityForCompiledOperation() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["着急时同时修改了很多地方"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "问题反复出现，项目没有推进"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前项目受阻，不能单独确定整体开发能力",
            fierceEvidence: nil
        )
        let data = Data(
            """
            {
              "semanticOperation": "synthesizeDirectReflection",
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": "不具有执行权的自由文本",
              "reflectionProgressionDecision": {
                "meaning": "inspectReality",
                "candidateRef": "episodeStructure.behaviorEvidence.0"
              }
            }
            """.utf8
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let compiled = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(compiled.semanticOperation, .continueTenderGroundedFierceReflection)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            compiled,
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(authorized.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(authorized.responseFocus, "着急时同时修改了很多地方")
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
    }

    func testTenderSynthesisProgressionAtomicallyCarriesItsSemanticDelta() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "协议反复中断，项目没有推进")],
            dimensions: [.mindfulness],
            reflectionDelta: "协议反复中断是当前困难，不能单独确定整体开发能力",
            fierceEvidence: nil
        )
        let synthesis = "当前需要同时保留协议确实反复中断，以及这段受阻不足以单独确定整体开发能力"
        let data = Data(
            """
            {
              "semanticOperation": null,
              "semanticEvidencePatch": {
                "memoryUpdate": {
                  "reflectionFrame": {
                    "reflectionDelta": "旧分离字段不得覆盖原子决定"
                  }
                }
              },
              "responseFocus": "自然呈现已经提交的综合理解",
              "reflectionProgressionDecision": {
                "meaning": "synthesize",
                "candidateRef": null,
                "reflectionDelta": "\(synthesis)"
              }
            }
            """.utf8
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let compiled = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(compiled.semanticOperation, .synthesizeDirectReflection)
        XCTAssertEqual(
            compiled.semanticEvidencePatch.reflectionContribution?.reflectionDelta,
            synthesis
        )
        XCTAssertNil(compiled.semanticEvidencePatch.memoryUpdate.reflectionFrame)

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            compiled,
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(authorized.operation, .synthesizeDirectReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            synthesis
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.evidenceBasis,
            session.semanticMemory.reflectionFrame?.evidenceBasis
        )
    }

    func testActiveFierceCompletionAtomicallyProjectsSynthesisAndDropsWriterFocus() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["临时接下额外工作后，自己的报告被推迟"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "临时接下额外工作后，自己的报告被推迟"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "额外工作挤压了原有安排，这不能直接归结为整体效率",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        session.messages = [
            ChatMessage(role: .user, content: "时间有限时要明确拒绝临时工作")
        ]

        let data = Data(
            """
            {
              "semanticOperation": null,
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": "继续确认并排练拒绝话术",
              "reflectionProgressionDecision": {
                "meaning": "completeFierce",
                "reflectionDelta": "时间有限时，需要先守住原有工作的安排",
                "fierceDirection": "protect"
              }
            }
            """.utf8
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let compiled = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            compiled,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "synthesisReflection")
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.fierceEvidence?.direction,
            .protect
        )
        XCTAssertTrue(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.evidenceBasis.contains(
                .init(source: .latestUserAnswer, content: "时间有限时要明确拒绝临时工作")
            ) == true
        )
        let directive = CurrentV5WriterDirective(authorized: authorized)
        XCTAssertNil(directive.responseFocus)
        XCTAssertEqual(directive.reflectionRealization, .bridgeToSynthesis)
        XCTAssertFalse(directive.mayAskQuestion)
        XCTAssertEqual(directive.nextPrompt.purpose, "synthesisReflection")
    }

    func testActiveFierceClarificationKeepsTheSameCandidateAndOneWriterFocus() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["自己的报告被额外工作推迟"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "自己的报告被额外工作推迟")],
            dimensions: [],
            reflectionDelta: "当前安排被打乱，不足以单独确定整体效率",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "只澄清接下临时工作是否挤压了原有安排",
            reflectionProgressionDecision: .init(
                meaning: .clarifyFierce,
                candidateRef: "episodeStructure.behaviorEvidence.0"
            )
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).responseFocus,
            "只澄清接下临时工作是否挤压了原有安排"
        )
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).reflectionRealization,
            .askFierceClarification
        )
        XCTAssertTrue(CurrentV5WriterDirective(authorized: authorized).mayAskQuestion)
    }

    func testWireCompilerRecoversLegacyFierceCompletionAndKeepsAllUserEvidence() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["我说了特别伤人的话"]
        )
        let repairDirection = "我们之间还有问题需要解决，不能直接不讲话"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "有些东西还留在房间里",
            realityMapping: repairDirection,
            source: .userAuthored
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "我说了特别伤人的话"),
                .init(source: .cardRealityConnection, content: repairDirection),
            ],
            dimensions: [],
            reflectionDelta: "自责和这次行为造成的伤害有关，责任仍停留在这次行为及其影响",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        session.messages = [ChatMessage(role: .user, content: "这些话让对方感到难过")]

        let data = Data(
            """
            {
              "semanticOperation": "continueTenderGroundedFierceReflection",
              "semanticEvidencePatch": {
                "memoryUpdate": {
                  "episodeStructure": {
                    "impacts": ["这些话让对方感到难过"]
                  },
                  "reflectionFrame": {
                    "reflectionDelta": "已经造成的伤害需要被回应，关系中尚未解决的问题也需要处理",
                    "fierceEvidence": {"direction": "repair"}
                  }
                }
              },
              "responseFocus": ""
            }
            """.utf8
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let compiled = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(compiled.reflectionProgressionDecision?.meaning, .completeFierce)
        XCTAssertEqual(compiled.reflectionProgressionDecision?.fierceDirection, .repair)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            compiled,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.episodeStructure?.impacts,
            ["这些话让对方感到难过"]
        )
        let frame = try XCTUnwrap(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(frame.fierceEvidence?.direction, .repair)
        XCTAssertTrue(frame.evidenceBasis.contains(
            .init(source: .cardRealityConnection, content: repairDirection)
        ))
        XCTAssertTrue(frame.evidenceBasis.contains(
            .init(source: .latestUserAnswer, content: "这些话让对方感到难过")
        ))
    }

    func testWireCompilerRecoversUnambiguousActiveFierceClarification() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["临时接下了额外工作"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "临时接下了额外工作")],
            dimensions: [],
            reflectionDelta: "额外工作占用了原有安排，不能只从效率解释",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        let data = Data(
            """
            {
              "semanticOperation": "continueTenderGroundedFierceReflection",
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": "临时工作是否占用了原本留给自己任务的时间"
            }
            """.utf8
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let compiled = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(compiled.reflectionProgressionDecision?.meaning, .clarifyFierce)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            compiled,
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )
    }

    func testCompletionWriterDirectiveCannotReplayNarrativeOrPractice() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .narrativeConfirmation
        session.semanticMemory.nextPrompt = .confirmationRequest(target: .finalNarrative)
        session.semanticMemory.finalNarrative = "已经形成并接受的最终叙事"
        session.semanticMemory.practiceTransition = .init(
            transactionID: "practice-1",
            narrativeReferenceID: nil,
            proposal: .init(
                id: "practice-1",
                kind: .protect,
                content: "先看现有安排再回复临时请求",
                basis: "episodeStructure.behaviorEvidence.0",
                status: .confirmed,
                source: .assistantProposed
            ),
            noActionReason: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .completeConversation,
            semanticEvidencePatch: .init(),
            responseFocus: "再次提醒用户执行已经接受的行动"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        let directive = CurrentV5WriterDirective(authorized: authorized)
        XCTAssertNil(directive.responseFocus)
        XCTAssertNil(directive.memoryUpdate.finalNarrative)
        XCTAssertNil(directive.memoryUpdate.practiceTransition)
        XCTAssertEqual(directive.nextPrompt.kind, .none)
    }

    func testGroundedRealityProjectionExcludesCardImageryAndKeepsUserRealityMapping() {
        var memory = TurnSemanticMemory()
        memory.episodeStructure = .init(
            concreteFacts: ["项目连续几天没有推进"]
        )
        memory.cardRealityConnection = .init(
            imageRelation: "画面里的人在风里扶着架子",
            realityMapping: "我着急时会同时改很多地方",
            source: .userAuthored
        )
        memory.reflectionFrame = .init(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .cardRealityConnection, content: "画面里的人在风里扶着架子"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前受阻不能单独确定整体能力",
            fierceEvidence: nil
        )

        let candidates = CurrentV5GroundedRealityCandidate.projected(from: memory)

        XCTAssertTrue(
            candidates.contains {
                $0.id == "cardRealityConnection.realityMapping"
                    && $0.content == "我着急时会同时改很多地方"
                    && $0.cardAuthorship == .userAuthored
            }
        )
        XCTAssertFalse(candidates.contains { $0.content == "画面里的人在风里扶着架子" })
    }

    func testPracticeCannotUseAcceptedAssistantSynthesisAsItsGroundingReference() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .synthesis
        session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "项目连续几天没有推进"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "这是 Assistant 整理并被接受的综合文字",
            fierceEvidence: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .proposePractice,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    practiceTransition: .init(
                        transactionID: "provider-owned-id",
                        narrativeReferenceID: nil,
                        proposal: .init(
                            id: "provider-owned-id",
                            kind: .change,
                            content: "下次先只验证一个改动",
                            basis: "这是 Assistant 整理并被接受的综合文字",
                            status: .pendingConfirmation
                        ),
                        noActionReason: nil
                    )
                )
            ),
            responseFocus: "提出一个小行动"
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .proposePractice,
                    failure: .practiceEvidenceInvalid
                )
            )
        }
    }

    func testNewGroundedCumulativeLinkKeepsCurrentActAndProjectsTenderNext() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory

        let committedOperations = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertTrue(committedOperations.contains(.continueExploratoryReflection))
        XCTAssertFalse(committedOperations.contains(.continueTenderReflection))

        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    selfCriticalStatement: "能力不够",
                    selfCriticismLink: "反复修改长期没有效果以后逐渐怀疑自己 -> 能力不够"
                )
            ),
            responseFocus: "承接已经形成的累积关系"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: committedOperations
        )
        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "tenderReflection")
    }

    func testExplorationActDoesNotBecomeTenderActWhenItsLinkCompletesThePhase() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己能力不够"
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    selfCriticalStatement: "自己能力不够",
                    selfCriticismLink: "反复卡住以后逐渐怀疑自己 -> 自己能力不够"
                )
            ),
            responseFocus: "区分现实中的持续受阻和对整个人能力的判断"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticismLink,
            "反复卡住以后逐渐怀疑自己 -> 自己能力不够"
        )
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "form_first_bounded_tender_understanding"
        )
    }

    func testRealityMappingOrEmotionCannotCompleteExplorationWithoutAlignedJudgmentEndpoint() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "会觉得自己能力不好"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "画面里的人困在房间里",
            realityMapping: "一直在改 bug，不能往下推进",
            source: .userAuthored
        )

        func authorize(
            _ link: String,
            reflectionFrame: TurnReflectionFrame? = nil
        ) throws -> CurrentV5AuthorizedTurn {
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            selfCriticismLink: link,
                            reflectionFrame: reflectionFrame
                        )
                    ),
                    responseFocus: "只澄清现实困难与当前自我判断的关系"
                ),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        }

        let mapping = try authorize(
            "越急越改、越改越乱 -> 一直在改 bug，不能往下推进"
        )
        XCTAssertEqual(mapping.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertNil(mapping.projectedPlan.memoryUpdate.selfCriticismLink)

        let emotion = try authorize("反复修改没有效果 -> 很焦虑")
        XCTAssertEqual(emotion.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertNil(emotion.projectedPlan.memoryUpdate.selfCriticismLink)

        let aligned = try authorize(
            "越急越改、功能持续无法推进 -> 会觉得自己能力不好",
            reflectionFrame: tenderFrame
        )
        XCTAssertEqual(aligned.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            aligned.projectedPlan.memoryUpdate.selfCriticismLink,
            "越急越改、功能持续无法推进 -> 会觉得自己能力不好"
        )
    }

    func testChangingSelfCriticalStatementMakesOldLinkInertUntilReplacementAligns() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我不适合开发"
        session.semanticMemory.selfCriticismLink = "项目持续受阻 -> 我不适合开发"

        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let stale = try gate.authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(selfCriticalStatement: "会觉得自己能力不好")
                ),
                responseFocus: "保留用户刚刚修订的判断"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(stale.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)

        let aligned = try gate.authorize(
            .init(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        selfCriticalStatement: "会觉得自己能力不好",
                        selfCriticismLink: "持续受阻以后逐渐怀疑自己 -> 会觉得自己能力不好",
                        reflectionFrame: tenderFrame
                    )
                ),
                responseFocus: "承接用户已经形成的关系"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(aligned.projectedPlan.memoryUpdate.reflectionPhase, .tender)
    }

    func testAlignedTenderRepairRemovesStaleCardMappingLinkFromCanonicalFrame() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticalStatement = "会觉得自己能力不好"
        let stale = "越急越改、越改越乱 -> 困在里面走不出去"
        session.semanticMemory.selfCriticismLink = stale
        let connection = TurnCardRealityConnection(
            imageRelation: "画面里的人困在房间里",
            realityMapping: "一直在改 bug，不能往下推进",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: stale),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "之前保存的理解并未到达当前自我判断",
            fierceEvidence: nil
        )

        XCTAssertEqual(
            CurrentV5CapabilitySet.allowedOperations(for: session),
            [.continueTenderReflection]
        )
        let aligned = "越急越改、功能持续无法推进 -> 会觉得自己能力不好"
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        selfCriticismLink: aligned,
                        reflectionFrame: TurnReflectionFrame(
                            mode: .tender,
                            action: .softenGlobalSelfJudgment,
                            evidenceBasis: [],
                            dimensions: [],
                            reflectionDelta: "持续受阻是当前事实；它不能独自确定整体能力",
                            fierceEvidence: nil
                        )
                    )
                ),
                responseFocus: "持续受阻是当前事实；它不能独自确定整体能力",
                reflectionProgressionDecision: .init(
                    meaning: .reviseTender,
                    candidateRef: nil
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        let evidence = try XCTUnwrap(
            authorized.projectedPlan.memoryUpdate.reflectionFrame
        ).evidenceBasis
        XCTAssertFalse(evidence.contains(.init(source: .episode, content: stale)))
        XCTAssertTrue(evidence.contains(.init(source: .episode, content: aligned)))
        XCTAssertTrue(
            evidence.contains(
                .init(source: .cardRealityConnection, content: connection.realityMapping)
            )
        )
    }

    func testGroundedLinkProjectsTenderWithoutSameTurnTenderMeaning() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己能力不够"
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    selfCriticismLink: "反复卡住以后逐渐怀疑自己 -> 自己能力不够"
                )
            ),
            responseFocus: "继续"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "tenderReflection")
    }

    func testExplorationRemainsCurrentAndNextPhaseWhenLatestTurnDoesNotGroundTheLink() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory

        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueExploratoryReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(situationUnderstanding: "项目仍然卡住")
            ),
            responseFocus: "继续了解现实与自我判断的关系"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "exploratoryReflection")
    }

    func testStoredGroundedLinkProjectsTenderUnlessThePersonRevisesIt() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己的能力不行"
        session.semanticMemory.selfCriticismLink =
            "反复修改一直没有效果以后逐渐开始怀疑自己 -> 自己的能力不行"

        func projectedPhase(
            _ update: TurnSemanticMemoryUpdate
        ) throws -> TurnReflectionPhase? {
            let output = CurrentV5PlannerOutput(
                semanticOperation: .continueExploratoryReflection,
                semanticEvidencePatch: .init(memoryUpdate: update),
                responseFocus: "承接或修订当前关系"
            )
            return try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            ).projectedPlan.memoryUpdate.reflectionPhase
        }

        XCTAssertEqual(try projectedPhase(.init()), .tender)
        XCTAssertEqual(
            try projectedPhase(.init(
                invalidatedInterpretations: ["用户面对 bug 时很有耐心"]
            )),
            .tender
        )
        XCTAssertEqual(
            try projectedPhase(.init(
                invalidatedInterpretations: [
                    "反复修改一直没有效果以后逐渐开始怀疑自己 -> 自己的能力不行"
                ]
            )),
            .exploratory
        )
    }

    func testTenderCanBeginOnlyAfterExplorationAndSetsCanonicalPhase() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender

        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: tenderFrame)
            ),
            responseFocus: "区分被一个bug卡住与整个人什么都做不好"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionFrame, tenderFrame)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "tenderReflection")
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "respond_to_or_revise_bounded_tender_understanding"
        )
        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: session)
                .contains(.continueTenderGroundedFierceReflection)
        )
    }

    func testTenderOperationCanonicalizesRedundantAcknowledgmentAction() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        let acknowledgment = TurnReflectionFrame(
            mode: .tender,
            action: .acknowledgeExperience,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "这次被拒以后很难受"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "被拒以后很难受",
            fierceEvidence: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: acknowledgment)
            ),
            responseFocus: "只承接痛苦"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.action,
            .softenGlobalSelfJudgment
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            acknowledgment.reflectionDelta
        )
    }

    func testCardMediatedTenderInheritsCanonicalLineageButStillRequiresSelfCriticismLink() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        let connection = TurnCardRealityConnection(
            imageRelation: "不同大小的盆承接同一股水",
            realityMapping: "不同严重程度的bug被持续反复处理",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        func output(_ frame: TurnReflectionFrame, link: String? = nil) -> CurrentV5PlannerOutput {
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        selfCriticismLink: link,
                        reflectionFrame: frame
                    )
                ),
                responseFocus: "承认项目受阻的消耗，并区分它与不适合科研的判断"
            )
        }

        let sparseFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "项目受阻不能单独确定是否适合科研",
            fierceEvidence: nil
        )
        let sparseAuthorized = try gate.authorize(
            output(
                sparseFrame,
                link: "项目受阻被进一步解释为自己不适合科研"
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let inheritedEvidence = try XCTUnwrap(
            sparseAuthorized.projectedPlan.memoryUpdate.reflectionFrame
        ).evidenceBasis
        XCTAssertTrue(
            inheritedEvidence.contains(
                .init(
                    source: .episode,
                    content: "项目受阻被进一步解释为自己不适合科研"
                )
            )
        )
        XCTAssertTrue(
            inheritedEvidence.contains(
                .init(source: .cardRealityConnection, content: connection.realityMapping)
            )
        )

        let validFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "多个bug阻断实验流程"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "项目受阻不能单独确定是否适合科研",
            fierceEvidence: nil
        )
        XCTAssertThrowsError(
            try gate.authorize(
                output(validFrame),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .continueTenderReflection,
                    failure: .tenderEvidenceMissing
                )
            )
        }

        let authorized = try gate.authorize(
            output(validFrame, link: "项目受阻被进一步解释为自己不适合科研"),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(authorized.operation, .continueTenderReflection)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticismLink,
            "项目受阻被进一步解释为自己不适合科研"
        )
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "tenderReflection")
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.action,
            validFrame.action
        )
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            validFrame.reflectionDelta
        )
    }

    func testTenderOperationRequiresExplicitDeltaAndInheritsCommittedLineage() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismLink = "反复卡住被扩大为自己不适合开发"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "风持续吹向正在晾晒的东西",
            realityMapping: "开发过程中不断出现新的问题",
            source: .userAuthored
        )
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        let missingFrame = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "这个功能仍未解决，不足以直接说明整个人不适合开发"
        )
        XCTAssertThrowsError(
            try gate.authorize(
                missingFrame,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            guard case CurrentV5CoreError.projectionInvalid(
                operation: .continueTenderReflection,
                failure: .tenderFrameMissing
            ) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let omittedLineageJSON = """
        {
          "semanticOperation":"continueTenderReflection",
          "semanticEvidencePatch":{"memoryUpdate":{"reflectionFrame":{
            "mode":"tender",
            "action":"softenGlobalSelfJudgment",
            "dimensions":["selfKindness"],
            "reflectionDelta":"当前问题没有解决不等于整个人不适合开发",
            "fierceEvidence":null
          }}},
          "responseFocus":"形成 Tender 理解"
        }
        """
        let omittedLineage = try decodePlannerOutput(omittedLineageJSON)
        XCTAssertEqual(
            omittedLineage.semanticEvidencePatch.memoryUpdate.reflectionFrame?.evidenceBasis,
            []
        )
        let inheritedLineage = try gate.authorize(
            omittedLineage,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let inheritedFrame = try XCTUnwrap(
            inheritedLineage.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(inheritedFrame.action, .softenGlobalSelfJudgment)
        XCTAssertEqual(
            inheritedFrame.reflectionDelta,
            "当前问题没有解决不等于整个人不适合开发"
        )
        XCTAssertEqual(inheritedFrame.dimensions, [.selfKindness])
        XCTAssertTrue(inheritedFrame.hasRealityEvidence)
        XCTAssertTrue(
            inheritedFrame.evidenceBasis.contains {
                $0.source == .cardRealityConnection
            }
        )

        let missingDelta = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [],
            dimensions: [.selfKindness],
            reflectionDelta: "",
            fierceEvidence: nil
        )
        XCTAssertThrowsError(
            try gate.authorize(
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: missingDelta)
                    ),
                    responseFocus: "形成 Tender 理解"
                ),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .continueTenderReflection,
                    failure: .tenderDeltaMissing
                )
            )
        }

        let missingActionJSON = """
        {
          "semanticOperation":"continueTenderReflection",
          "semanticEvidencePatch":{"memoryUpdate":{"reflectionFrame":{
            "mode":"tender",
            "evidenceBasis":[],
            "dimensions":["selfKindness"],
            "reflectionDelta":"当前问题没有解决不等于整个人不适合开发",
            "fierceEvidence":null
          }}},
          "responseFocus":"形成 Tender 理解"
        }
        """
        let missingAction = try decodePlannerOutput(missingActionJSON)
        XCTAssertTrue(
            try XCTUnwrap(
                missingAction.semanticEvidencePatch.memoryUpdate.reflectionFrame
            ).actionWasInferredForLegacyDecode
        )
        let canonicalMissingAction = try gate.authorize(
            missingAction,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(
            canonicalMissingAction.projectedPlan.memoryUpdate.reflectionFrame?.action,
            .softenGlobalSelfJudgment
        )
    }

    func testConfirmedContextEvidenceMustMatchTheUsersConfirmedRelationship() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        let connection = TurnCardRealityConnection(
            imageRelation: "不同容量面对同一股水",
            realityMapping: "不同严重程度的bug获得了相似处理",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        session.semanticMemory.selfCriticismLink = "项目受阻被扩大为自己不适合科研"
        session.semanticMemory.contextRelationship = .init(
            relevance: .partlyRelated,
            userInterpretation: "安排较密时更想尽快同时解决问题"
        )
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        func frame(context: String) -> TurnReflectionFrame {
            .init(
                mode: .tender,
                action: .softenGlobalSelfJudgment,
                evidenceBasis: [
                    .init(source: .episode, content: "多个bug阻断实验流程"),
                    .init(source: .cardRealityConnection, content: connection.realityMapping),
                    .init(source: .confirmedContext, content: context),
                ],
                dimensions: [.mindfulness],
                reflectionDelta: "项目受阻不能单独确定是否适合科研",
                fierceEvidence: nil
            )
        }
        func output(context: String) -> CurrentV5PlannerOutput {
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(reflectionFrame: frame(context: context))
                ),
                responseFocus: "只使用用户确认的情境关系"
            )
        }

        XCTAssertThrowsError(
            try gate.authorize(
                output(context: "压力导致用户无法处理bug"),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        )
        let authorized = try gate.authorize(
            output(context: "安排较密时更想尽快同时解决问题"),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(authorized.operation, .continueTenderReflection)
    }

    func testCommittedTenderMayBeClarifiedWithoutReopeningBroadExploration() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismLink = "项目受阻被扩大为自己不适合科研"
        let connection = TurnCardRealityConnection(
            imageRelation: "不同大小的盆承接同一股水",
            realityMapping: "不同严重程度的bug被持续反复处理",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        let canonical = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "多个bug阻断实验流程"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "项目受阻不能单独确定是否适合科研",
            fierceEvidence: nil
        )
        session.semanticMemory.reflectionFrame = canonical
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertTrue(allowed.contains(.continueTenderReflection))
        XCTAssertTrue(allowed.contains(.continueTenderGroundedFierceReflection))
        XCTAssertTrue(allowed.contains(.synthesizeDirectReflection))

        let clarified = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    reflectionFrame: TurnReflectionFrame(
                        mode: .tender,
                        action: .softenGlobalSelfJudgment,
                        evidenceBasis: [],
                        dimensions: [.mindfulness],
                        reflectionDelta: "目前能确认的是项目在这次受阻；这仍不足以确定今后是否适合科研",
                        fierceEvidence: nil
                    )
                )
            ),
            responseFocus: "承认目前确实很难，同时把对未来整体能力的判断留在证据范围内",
            reflectionProgressionDecision: .init(
                meaning: .reviseTender,
                candidateRef: nil
            )
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            clarified,
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(authorized.operation, .continueTenderReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "目前能确认的是项目在这次受阻；这仍不足以确定今后是否适合科研"
        )
    }

    func testCommittedTenderCapabilityOffersClarificationFierceOrSynthesis() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        let canonical = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [.init(source: .latestUserAnswer, content: "当前结果没有达到预期")],
            dimensions: [.mindfulness],
            reflectionDelta: "当前结果没有达到预期，不等于未来一定失败",
            fierceEvidence: nil
        )
        session.semanticMemory.reflectionFrame = canonical
        let operations = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertEqual(
            Set(operations),
            [
                .continueTenderReflection,
                .continueTenderGroundedFierceReflection,
                .synthesizeDirectReflection,
            ]
        )
    }

    func testExplicitTenderCorrectionRevisesUnderstandingInTender() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.selfCriticismLink =
            "论文长期没有进展以后，逐渐把受阻解释成整体能力不足"
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "不同容器承接同一股水",
            realityMapping: "论文不同部分获得的投入不一样",
            source: .userAuthored
        )
        let rejected = "论文卡住只是普通写作困难，与投入方式没有关系"
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: session.semanticMemory.selfCriticismLink!),
                .init(
                    source: .cardRealityConnection,
                    content: session.semanticMemory.cardRealityConnection!.realityMapping
                ),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: rejected,
            fierceEvidence: nil
        )

        let corrected = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            .init(
                semanticOperation: .continueTenderReflection,
                semanticEvidencePatch: .init(
                    memoryUpdate: .init(
                        reflectionFrame: TurnReflectionFrame(
                            mode: .tender,
                            action: .softenGlobalSelfJudgment,
                            evidenceBasis: [],
                            dimensions: [],
                            reflectionDelta: "目前只能确认论文长期受阻后出现了整体能力怀疑；投入方式是否相关仍不确定",
                            fierceEvidence: nil
                        ),
                        invalidatedInterpretations: [rejected]
                    )
                ),
                responseFocus: "目前只能确认论文长期受阻后出现了整体能力怀疑；投入方式是否相关仍不确定",
                reflectionProgressionDecision: .init(
                    meaning: .reviseTender,
                    candidateRef: nil
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(corrected.operation, .continueTenderReflection)
        XCTAssertEqual(corrected.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            corrected.projectedPlan.memoryUpdate.invalidatedInterpretations,
            [rejected]
        )
        XCTAssertEqual(
            corrected.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "目前只能确认论文长期受阻后出现了整体能力怀疑；投入方式是否相关仍不确定"
        )
    }

    func testFierceAndSynthesisMustContinueTheCommittedRealityEvidenceLineage() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .tender
        let connection = TurnCardRealityConnection(
            imageRelation: "不同大小的盆承接同一股水",
            realityMapping: "不同严重程度的bug被持续反复处理",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        session.semanticMemory.selfCriticismLink = "项目受阻被扩大为自己不适合科研"
        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "多个bug阻断实验流程"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "项目受阻不能单独确定是否适合科研",
            fierceEvidence: nil
        )
        session.semanticMemory.reflectionFrame = committedTender
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        XCTAssertEqual(
            Set(CurrentV5CapabilitySet.allowedOperations(for: session)),
            [
                .continueTenderReflection,
                .continueTenderGroundedFierceReflection,
                .synthesizeDirectReflection,
            ]
        )

        func fierceOutput(
            _ frame: TurnReflectionFrame,
            groundedEvidence: String
        ) -> CurrentV5PlannerOutput {
            .init(
                semanticOperation: .continueTenderGroundedFierceReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "",
                reflectionProgressionDecision: .init(
                    meaning: .completeFierce,
                    candidateRef: "reflectionFrame.evidenceBasis.0",
                    reflectionDelta: frame.reflectionDelta,
                    fierceDirection: frame.fierceEvidence?.direction,
                    groundedEvidence: groundedEvidence
                )
            )
        }

        let opening = try gate.authorize(
            .init(
                semanticOperation: .continueTenderGroundedFierceReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "这段文字不应成为 Fierce 的第二个语义来源",
                reflectionProgressionDecision: .init(
                    meaning: .inspectReality,
                    candidateRef: "reflectionFrame.evidenceBasis.0"
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(opening.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(opening.responseFocus, "多个bug阻断实验流程")
        XCTAssertEqual(opening.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertNil(opening.projectedPlan.memoryUpdate.reflectionFrame)
        session.semanticMemory.apply(opening.projectedPlan.memoryUpdate)
        session.semanticMemory.nextPrompt = opening.projectedPlan.nextPrompt
        XCTAssertEqual(session.semanticMemory.reflectionFrame, committedTender)

        let switchedFierce = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidenceBasis: [
                .init(source: .episode, content: "没有向导师求助"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "需要改变的是没有向导师求助",
            fierceEvidence: .init(
                behavior: "没有向导师求助",
                impact: "问题仍未解决",
                direction: .change
            )
        )
        session.messages = [ChatMessage(role: .user, content: "没有向导师求助")]
        let inheritedFierce = try gate.authorize(
            fierceOutput(switchedFierce, groundedEvidence: "没有向导师求助"),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let inheritedFierceFrame = try XCTUnwrap(
            inheritedFierce.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertTrue(
            inheritedFierceFrame.evidenceBasis.contains(
                .init(source: .episode, content: "多个bug阻断实验流程")
            )
        )
        XCTAssertTrue(
            inheritedFierceFrame.evidenceBasis.contains(
                .init(source: .cardRealityConnection, content: connection.realityMapping)
            )
        )

        let committedFierce = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidenceBasis: [
                .init(source: .episode, content: "多个bug阻断实验流程"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
                .init(source: .latestUserAnswer, content: "同时反复修改了多个问题"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "需要调整的是多个问题同时出现时的处理顺序",
            fierceEvidence: .init(
                behavior: "同时反复修改了多个问题",
                impact: "关键问题继续阻断流程",
                direction: .change
            )
        )
        session.messages = [
            ChatMessage(role: .user, content: "同时反复修改了多个问题")
        ]
        _ = try gate.authorize(
            fierceOutput(committedFierce, groundedEvidence: "同时反复修改了多个问题"),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.reflectionFrame = committedFierce
        let sparseSynthesis = TurnReflectionFrame(
            mode: .fierce,
            action: .synthesizeUnderstanding,
            evidenceBasis: [],
            dimensions: [],
            reflectionDelta: "项目受阻不等于不适合科研，而同时修改多个问题的处理顺序值得调整",
            fierceEvidence: nil
        )
        let synthesis = try gate.authorize(
            .init(
                semanticOperation: .synthesizeDirectReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "综合已经形成的同一条关系",
                reflectionProgressionDecision: .init(
                    meaning: .synthesize,
                    candidateRef: nil,
                    reflectionDelta: sparseSynthesis.reflectionDelta
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let canonicalSynthesis = try XCTUnwrap(
            synthesis.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(canonicalSynthesis.evidenceBasis, committedFierce.evidenceBasis)
        XCTAssertEqual(canonicalSynthesis.dimensions, committedFierce.dimensions)
        XCTAssertEqual(canonicalSynthesis.fierceEvidence, committedFierce.fierceEvidence)
        XCTAssertEqual(canonicalSynthesis.action, .synthesizeUnderstanding)
    }

    func testWireFierceContributionInheritsCommittedTenderAndCardLineage() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.condition = .cardMediated
        session.semanticMemory.reflectionPhase = .fierce
        let connection = TurnCardRealityConnection(
            imageRelation: "一个人带着尚未处理完的行李继续前进",
            realityMapping: "反复出现的问题让项目一直没有往下推进",
            source: .userAuthored
        )
        session.semanticMemory.cardRealityConnection = connection
        let committedEpisode = TurnReflectionEvidence(
            source: .episode,
            content: "尝试多种办法后问题仍然增加，项目没有正常推进"
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                committedEpisode,
                .init(source: .cardRealityConnection, content: connection.realityMapping),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "项目当前没有推进，并不足以单独支持对整体能力的否定",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
        session.messages = [
            ChatMessage(role: .user, content: "我还是比较想尽快推进项目的进程")
        ]

        let data = try XCTUnwrap(
            """
            {
              "semanticOperation": "continueTenderGroundedFierceReflection",
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "reflectionProgressionDecision": {
                "meaning": "completeFierce",
                "reflectionDelta": "当前值得继续面对的是项目仍然没有往下推进",
                "fierceDirection": "change"
              },
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )
        let frame = try XCTUnwrap(authorized.projectedPlan.memoryUpdate.reflectionFrame)

        XCTAssertEqual(frame.mode, .fierce)
        XCTAssertEqual(frame.action, .identifyChangeDirection)
        XCTAssertEqual(frame.dimensions, [.mindfulness, .selfKindness])
        XCTAssertTrue(frame.evidenceBasis.contains(committedEpisode))
        XCTAssertTrue(
            frame.evidenceBasis.contains(
                .init(source: .cardRealityConnection, content: connection.realityMapping)
            )
        )
        XCTAssertTrue(
            frame.evidenceBasis.contains(
                .init(source: .latestUserAnswer, content: "我还是比较想尽快推进项目的进程")
            )
        )
        XCTAssertEqual(frame.fierceEvidence?.impact, "")
        XCTAssertEqual(frame.fierceEvidence?.direction, .change)
    }

    func testPhaseOutcomeAcceptedTenderWithCandidateDeterministicallyOpensFierce() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            behaviorEvidence: ["我说了特别伤人的话"],
            impacts: ["我们之间现在还有问题没有解决"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "我说了特别伤人的话"),
            ],
            dimensions: [],
            reflectionDelta: "说出伤人的话需要被认真看见，但不必再扩大成对整个人的判决",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "respond_to_or_revise_bounded_tender_understanding"
        )
        session.messages = [ChatMessage(role: .user, content: "是的")]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "semanticOperation": null,
              "reflectionProgressionDecision": null,
              "reflectionTurnOutcome": {
                "outcome": "tenderAccepted",
                "realityCandidate": {
                  "reference": "episodeStructure.behaviorEvidence.0",
                  "meaning": "repair"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(planner.semanticOperation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(planner.reflectionProgressionDecision?.meaning, .inspectReality)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "fierceReflection")
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).reflectionRealization,
            .openFierceInquiry
        )
    }

    func testPhaseOutcomeCompletesExplorationAndEstablishesFirstTenderAtomically() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己能力不够"
        session.messages = [
            ChatMessage(role: .user, content: "一直改但始终没推进以后，我就越来越觉得是自己能力不够")
        ]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "反复修改一直没有推进以后逐渐怀疑自己",
                "tenderDelta": "反复修改却没有推进是当前真实的困难；这段经历说明现在仍然卡着，但还不足以概括全部能力"
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "自己能力不够"
        )
        XCTAssertTrue(planner.phaseOutcomeContractApplied)
        XCTAssertEqual(planner.reflectionProgressionDecision?.meaning, .completeExploration)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.operation, .continueExploratoryReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "反复修改却没有推进是当前真实的困难；这段经历说明现在仍然卡着，但还不足以概括全部能力"
        )
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "respond_to_or_revise_bounded_tender_understanding"
        )
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).reflectionRealization,
            .establishTenderUnderstanding
        )
    }

    func testMalformedOptionalRealityCandidateCannotBlockExplorationCompletion() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidence: ["我说了伤人的话"]
        )
        session.messages = [ChatMessage(role: .user, content: "我主要是在责怪自己说了伤人的话。")]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "责怪自己说了伤人的话",
                "tenderDelta": "说出的内容需要认真面对；当前自责可以先落在这次具体行为上",
                "realityCandidate": {
                  "reference": "episodeStructure.controllableParts.0"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.selfCriticismLink,
            "责怪自己说了伤人的话 -> 我感觉很自责"
        )
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.pendingRealityCandidate)
    }

    func testUngroundedOptionalRealityCandidateIsDroppedWithoutRejectingTenderHandoff() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidence: ["我说了伤人的话"]
        )
        session.messages = [ChatMessage(role: .user, content: "我主要是在责怪自己说了伤人的话。")]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "责怪自己说了伤人的话",
                "tenderDelta": "说出的内容需要认真面对；当前自责可以先落在这次具体行为上",
                "realityCandidate": {
                  "reference": "episodeStructure.controllableParts.99",
                  "meaning": "repair"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.pendingRealityCandidate)
    }

    func testMissingInquiryFocusUsesCanonicalSwiftTarget() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {"outcome": "explorationContinue"},
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )
        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(
            authorized.responseFocus,
            "clarify_self_criticism_attribution_relation"
        )
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "clarify_self_criticism_attribution_relation"
        )
    }

    func testContinuityFallbackNeverAdvancesCommittedReflectionPhase() throws {
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let tenderFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "我说了伤人的话")],
            dimensions: [],
            reflectionDelta: "说出的内容需要面对，但自责可以先停留在这次行为上",
            fierceEvidence: nil
        )

        var tenderSession = ReflectionSession()
        tenderSession.protocolVersion = ReflectionSession.currentProtocolVersion
        tenderSession.protocolStage = .directReflection
        tenderSession.semanticMemory.reflectionPhase = .tender
        tenderSession.semanticMemory.reflectionFrame = tenderFrame
        let tender = try gate.authorizeCurrentReflectionContinuation(
            for: tenderSession,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(
                for: tenderSession
            )
        )
        XCTAssertEqual(tender.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            tender.projectedPlan.nextPrompt.focus,
            "clarify_current_bounded_tender_understanding"
        )

        var fierceSession = tenderSession
        fierceSession.semanticMemory.reflectionPhase = .fierce
        fierceSession.semanticMemory.episodeStructure = .init(
            behaviorEvidence: ["我说了伤人的话"]
        )
        fierceSession.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        let fierce = try gate.authorizeCurrentReflectionContinuation(
            for: fierceSession,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(
                for: fierceSession
            )
        )
        XCTAssertEqual(fierce.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(
            fierce.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )

        var synthesisSession = tenderSession
        synthesisSession.semanticMemory.reflectionPhase = .synthesis
        synthesisSession.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: tenderFrame.evidenceBasis,
            dimensions: [],
            reflectionDelta: "需要面对说出的内容，同时把评价限制在这次行为上",
            fierceEvidence: nil
        )
        let synthesis = try gate.authorizeCurrentReflectionContinuation(
            for: synthesisSession,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(
                for: synthesisSession
            )
        )
        XCTAssertEqual(synthesis.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(
            synthesis.projectedPlan.nextPrompt.focus,
            "clarify_current_synthesis"
        )
    }

    func testExplorationOutcomePreservesEarlyRepairCandidateUntilTenderAcceptance() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.stage = .attributionReflection
        session.condition = .cardMediated
        session.cardGuidanceShared = true
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticismStatus = .present
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            behaviorEvidence: ["我说了特别伤人的话"]
        )
        session.semanticMemory.cardRealityConnection = .init(
            imageRelation: "两个人一起按图纸完成事情",
            realityMapping: "争吵以后双方没有继续沟通，关系陷入冷战",
            source: .userAuthored
        )
        session.messages = [
            ChatMessage(role: .user, content: "我说了特别伤人的话，我感觉很自责。"),
            ChatMessage(
                role: .user,
                content: "我不希望这样冷战下去，需要沟通解决问题，我不想失去朋友。"
            ),
        ]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let explorationData = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "自责主要指向自己说出伤人的话以及随后的关系影响",
                "tenderDelta": "说出的内容和关系影响需要认真面对，但自责可以停留在这次具体行为和影响上",
                "realityCandidate": {
                  "reference": "episodeStructure.controllableParts.0",
                  "meaning": "repair"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {
                "episodeStructure": {
                  "controllableParts": ["希望结束冷战，通过沟通解决问题"]
                },
                "selfCriticismLink": "这个平行字段不再具有完成权限"
              }},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )
        let explorationPlan = try decodeCurrentV5PlannerWireOutput(
            explorationData,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        let exploration = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            explorationPlan,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(exploration.operation, .continueExploratoryReflection)
        XCTAssertEqual(exploration.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            exploration.projectedPlan.memoryUpdate.selfCriticismLink,
            "自责主要指向自己说出伤人的话以及随后的关系影响 -> 我感觉很自责"
        )
        XCTAssertEqual(
            exploration.projectedPlan.memoryUpdate.pendingRealityCandidate,
            .init(
                reference: "episodeStructure.controllableParts.0",
                meaning: .repair
            )
        )

        session.semanticMemory.apply(
            exploration.projectedPlan.memoryUpdate,
            committedNextPrompt: exploration.projectedPlan.nextPrompt
        )
        XCTAssertEqual(session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(
            session.semanticMemory.pendingRealityCandidate?.reference,
            "episodeStructure.controllableParts.0"
        )

        let tenderData = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {"outcome": "tenderAccepted"},
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )
        let tenderAllowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let tenderPlan = try decodeCurrentV5PlannerWireOutput(
            tenderData,
            allowedSemanticOperations: tenderAllowed,
            canonicalSelfCriticalStatement: session.semanticMemory.selfCriticalStatement,
            pendingRealityCandidate: session.semanticMemory.pendingRealityCandidate
        )
        let tender = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            tenderPlan,
            for: session,
            allowedSemanticOperations: tenderAllowed
        )

        XCTAssertEqual(tender.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(tender.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(
            tender.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.controllableParts.0"
        )
        XCTAssertEqual(tender.projectedPlan.memoryUpdate.clearPendingRealityCandidate, true)
    }

    func testExplorationContinueDoesNotInventLinkFromRelationshipValueAlone() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["我们吵架了"]
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {"outcome": "explorationContinue"},
              "semanticEvidencePatch": {"memoryUpdate": {
                "episodeStructure": {"controllableParts": ["我不想失去朋友"]},
                "selfCriticismLink": "不能由这个字段制造关系"
              }},
              "responseFocus": "询问这次争吵中的哪一部分让自责落到自己身上"
            }
            """.data(using: .utf8)
        )
        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .exploratory)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.selfCriticismLink)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "clarify_self_criticism_attribution_relation"
        )
    }

    func testObjectWrappedTenderDeltaReachesSwiftCompilerInsteadOfTransportFailure() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        session.messages = [
            ChatMessage(
                role: .user,
                content: "我说了伤人的话，伤害到了她，也可能让我们的关系发生变化，所以我很自责"
            )
        ]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "说了伤人的话并影响关系以后感到自责",
                "tenderDelta": {
                  "reflectionDelta": "已经造成的伤害需要面对；这说明这次说话确实伤人，但不需要继续扩大成对整个人的惩罚"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        XCTAssertEqual(planner.reflectionProgressionDecision?.meaning, .completeExploration)

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "已经造成的伤害需要面对；这说明这次说话确实伤人，但不需要继续扩大成对整个人的惩罚"
        )
    }

    func testAmbiguousWrappedTenderDeltaReachesGateInsteadOfTransportFailure() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "我感觉很自责"
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "explorationComplete",
                "selfCriticismLink": "说了伤人的话并影响关系以后感到自责",
                "tenderDelta": {
                  "text": "第一种理解",
                  "reflectionDelta": "冲突的第二种理解"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed,
            canonicalSelfCriticalStatement: "我感觉很自责"
        )
        XCTAssertEqual(planner.reflectionProgressionDecision?.meaning, .completeExploration)
        XCTAssertNil(planner.reflectionProgressionDecision?.reflectionDelta)
        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                planner,
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            guard case CurrentV5CoreError.projectionInvalid(
                .continueExploratoryReflection,
                .reflectionProgressionInvalid
            ) = error else {
                return XCTFail("Expected the ambiguous delta to reach the semantic Gate, got \(error)")
            }
        }
    }

    func testRemoteExplorationCannotBypassRequiredPhaseOutcome() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.selfCriticalStatement = "自己能力不够"
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "semanticOperation": "continueExploratoryReflection",
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": "继续看看两者的关系"
            }
            """.data(using: .utf8)
        )
        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                planner,
                for: session,
                allowedSemanticOperations: allowed
            )
        )
    }

    func testPhaseOutcomeRevisedTenderPreservesRevisionWhileOpeningFierce() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            behaviorEvidence: ["我说了特别伤人的话"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "我说了特别伤人的话")],
            dimensions: [],
            reflectionDelta: "原来的有限理解",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "tenderReflection",
            focus: "respond_to_or_revise_bounded_tender_understanding"
        )
        session.messages = [ChatMessage(role: .user, content: "我想修正一下，但这句话确实需要道歉")]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "tenderRevised",
                "tenderDelta": "我是在气头上说了伤人的话；情境不能抹掉伤害，道歉仍然是需要面对的部分",
                "realityCandidate": {
                  "reference": "episodeStructure.behaviorEvidence.0",
                  "meaning": "repair"
                }
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            "我是在气头上说了伤人的话；情境不能抹掉伤害，道歉仍然是需要面对的部分"
        )
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )
    }

    func testPhaseOutcomeGroundedFierceDirectionDeterministicallyClosesFierce() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.episodeStructure = TurnEpisodeStructure(
            behaviorEvidence: ["我说了特别伤人的话"]
        )
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [.init(source: .episode, content: "我说了特别伤人的话")],
            dimensions: [],
            reflectionDelta: "具体的话造成了伤害，但不继续扩大成整个人的判决",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("episodeStructure.behaviorEvidence.0")
        session.messages = [
            ChatMessage(role: .user, content: "我想和对方道歉，只是现在还说不出口")
        ]
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let data = try XCTUnwrap(
            """
            {
              "reflectionTurnOutcome": {
                "outcome": "fierceDirectionFormed",
                "fierceDelta": "当前已经形成了向对方道歉的修复方向",
                "fierceDirection": "repair"
              },
              "semanticEvidencePatch": {"memoryUpdate": {}},
              "responseFocus": ""
            }
            """.data(using: .utf8)
        )

        let planner = try decodeCurrentV5PlannerWireOutput(
            data,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(planner.reflectionProgressionDecision?.meaning, .completeFierce)
        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            planner,
            for: session,
            allowedSemanticOperations: allowed
        )

        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "synthesisReflection")
        XCTAssertEqual(
            authorized.projectedPlan.memoryUpdate.reflectionFrame?.fierceEvidence?.direction,
            .repair
        )
        XCTAssertEqual(
            CurrentV5WriterDirective(authorized: authorized).reflectionRealization,
            .bridgeToSynthesis
        )
    }

    func testTenderDimensionsArePlannerMetadataNotAReadinessGate() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        let frame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "一个 bug 卡住了当前流程"),
            ],
            dimensions: [],
            reflectionDelta: "当前被一个问题卡住，不等于什么都做不好",
            fierceEvidence: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(memoryUpdate: .init(reflectionFrame: frame)),
            responseFocus: "表达一个有事实依据的 Tender 区分"
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueTenderReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .tender)
    }

    func testFierceAcceptsGroundedBehaviorWithoutAReadinessScore() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.reflectionReadiness = .needsTender
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "一个问题卡住了当前流程"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前问题受阻不等于整个人没有能力",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
        let frame = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "一个问题卡住了当前流程"),
                .init(source: .latestUserAnswer, content: "着急以后同时改了很多地方"),
            ],
            dimensions: [],
            reflectionDelta: "当前问题受阻不等于整个人没有能力；需要面对的是着急时同时修改多个位置的处理方式",
            fierceEvidence: .init(
                behavior: "着急以后同时改了很多地方",
                impact: "",
                direction: .change
            )
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "",
            reflectionProgressionDecision: .init(
                meaning: .completeFierce,
                candidateRef: "reflectionFrame.evidenceBasis.0",
                reflectionDelta: frame.reflectionDelta,
                fierceDirection: .change,
                groundedEvidence: "着急以后同时改了很多地方"
            )
        )
        session.messages = [
            ChatMessage(role: .user, content: "着急以后同时改了很多地方")
        ]

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.kind, .openQuestion)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "synthesisReflection")
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.focus,
            "synthesize_grounded_fierce_direction"
        )
    }

    func testTenderCanOpenFierceInquiryBeforeThePersonHasFormedFierceEvidence() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.episodeStructure = .init(
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["一个问题卡住了当前流程"]
        )
        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "一个问题卡住了当前流程"),
            ],
            dimensions: [.selfKindness],
            reflectionDelta: "当前问题受阻不等于整个人没有能力",
            fierceEvidence: nil
        )
        session.semanticMemory.reflectionFrame = committedTender
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "这段自由文本不能替代 Swift 选中的现实候选",
            reflectionProgressionDecision: .init(
                meaning: .inspectReality,
                candidateRef: "episodeStructure.behaviorEvidence.0"
            )
        )

        let authorized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )

        XCTAssertEqual(authorized.operation, .continueTenderGroundedFierceReflection)
        XCTAssertEqual(authorized.responseFocus, "一个问题卡住了当前流程")
        XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertNil(authorized.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "fierceReflection")
        XCTAssertEqual(
            authorized.projectedPlan.nextPrompt.referenceID,
            "episodeStructure.behaviorEvidence.0"
        )

        session.semanticMemory.apply(authorized.projectedPlan.memoryUpdate)
        session.semanticMemory.nextPrompt = authorized.projectedPlan.nextPrompt
        XCTAssertEqual(session.semanticMemory.reflectionPhase, .fierce)
        XCTAssertEqual(session.semanticMemory.reflectionFrame, committedTender)
        let nextOperations = CurrentV5CapabilitySet.allowedOperations(for: session)
        XCTAssertTrue(nextOperations.contains(.continueTenderGroundedFierceReflection))
        XCTAssertTrue(nextOperations.contains(.synthesizeDirectReflection))
    }

    func testOpenedFierceInquiryCanFormEvidenceOrReturnToTenderSynthesis() throws {
        let committedEvidence = TurnReflectionEvidence(
            source: .latestUserAnswer,
            content: "反复修改仍然没有解决当前问题"
        )
        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [committedEvidence],
            dimensions: [.mindfulness],
            reflectionDelta: "当前问题尚未解决，与整个人不适合开发不是同一个判断",
            fierceEvidence: nil
        )
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.reflectionFrame = committedTender
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        let completedFierce = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidenceBasis: [
                committedEvidence,
                .init(source: .latestUserAnswer, content: "我还想继续，但不想再同时改很多地方"),
            ],
            dimensions: [.selfKindness],
            reflectionDelta: "即使不再用能力否定自己，同时修改很多地方的方式仍值得改变",
            fierceEvidence: .init(
                behavior: "同时修改很多地方",
                impact: "问题越来越难定位",
                direction: .change
            )
        )
        session.messages = [
            ChatMessage(role: .user, content: "我还想继续，但不想再同时改很多地方")
        ]
        let completed = try gate.authorize(
            .init(
                semanticOperation: .continueTenderGroundedFierceReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "",
                reflectionProgressionDecision: .init(
                    meaning: .completeFierce,
                    candidateRef: "reflectionFrame.evidenceBasis.0",
                    reflectionDelta: completedFierce.reflectionDelta,
                    fierceDirection: .change,
                    groundedEvidence: "我还想继续，但不想再同时改很多地方"
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let compiledFierce = try XCTUnwrap(
            completed.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(compiledFierce.mode, .fierce)
        XCTAssertEqual(compiledFierce.action, .identifyChangeDirection)
        XCTAssertEqual(compiledFierce.reflectionDelta, completedFierce.reflectionDelta)
        XCTAssertEqual(compiledFierce.fierceEvidence?.direction, .change)
        XCTAssertEqual(compiledFierce.fierceEvidence?.behavior, "")
        XCTAssertEqual(compiledFierce.fierceEvidence?.impact, "")
        XCTAssertTrue(
            compiledFierce.evidenceBasis.contains(
                .init(
                    source: .latestUserAnswer,
                    content: "我还想继续，但不想再同时改很多地方"
                )
            )
        )
        XCTAssertEqual(completed.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
        XCTAssertEqual(completed.projectedPlan.nextPrompt.purpose, "synthesisReflection")
        XCTAssertEqual(
            completed.projectedPlan.nextPrompt.focus,
            "synthesize_grounded_fierce_direction"
        )

        let tenderSynthesis = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [],
            dimensions: [],
            reflectionDelta: "当前问题尚未解决，但这不足以把整个人定义为不适合开发",
            fierceEvidence: nil
        )
        let synthesized = try gate.authorize(
            .init(
                semanticOperation: .synthesizeDirectReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "没有形成 Fierce 方向，综合已经成立的 Tender 理解",
                reflectionProgressionDecision: .init(
                    meaning: .synthesize,
                    candidateRef: nil,
                    reflectionDelta: tenderSynthesis.reflectionDelta
                )
            ),
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertEqual(
            synthesized.projectedPlan.memoryUpdate.reflectionFrame?.mode,
            .tender
        )
        XCTAssertNil(
            synthesized.projectedPlan.memoryUpdate.reflectionFrame?.fierceEvidence
        )
    }

    func testExistingFierceFrameSupportsProtectProvideAndMotivateWithoutCreatingAction() throws {
        let committedEvidence = TurnReflectionEvidence(
            source: .latestUserAnswer,
            content: "这件事一直卡着，让我很难受"
        )
        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [committedEvidence],
            dimensions: [.selfKindness],
            reflectionDelta: "当前被事情卡住，不等于整个人没有能力",
            fierceEvidence: nil
        )
        let candidates: [(TurnReflectionAction, TurnFierceEvidence, String)] = [
            (
                .identifyRepairDirection,
                .init(
                    behavior: "我答应发出的材料还没有补发",
                    impact: "同事仍然拿不到需要的版本",
                    direction: .repair
                ),
                "需要回应的是把已经答应的材料补发给同事"
            ),
            (
                .identifyProtectionDirection,
                .init(
                    behavior: "临时要求出现时，我一直没有守住原来留出的时间",
                    impact: "自己的休息时间被持续挤掉",
                    direction: .protect
                ),
                "需要保护的是原来留出的休息时间"
            ),
            (
                .clarifyBoundaryOrNeed,
                .init(
                    behavior: "",
                    impact: "我现在需要一段不被打断的恢复时间",
                    direction: .protect
                ),
                "当前没有被满足的是恢复时间"
            ),
            (
                .identifyChangeDirection,
                .init(
                    behavior: "我一直没有开始自己已经说过很重要的修改",
                    impact: "",
                    direction: .change
                ),
                "需要推动的是已经确认重要但一直停着的修改"
            ),
            (
                .identifyChangeDirection,
                .init(
                    behavior: "",
                    impact: "我感觉我还可以再努力尝试一下",
                    direction: .change
                ),
                "在承认当前阻碍之后，我仍想继续尝试这个对自己重要的方向"
            ),
        ]

        for (_, fierceEvidence, delta) in candidates {
            var session = ReflectionSession()
            session.protocolVersion = ReflectionSession.currentProtocolVersion
            session.protocolStage = .directReflection
            session.semanticMemory.reflectionPhase = .fierce
            session.semanticMemory.reflectionFrame = committedTender
            session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
                purpose: "fierceReflection",
                focus: "clarify_current_grounded_reality_direction"
            ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
            let latestAnswer = fierceEvidence.behavior.isEmpty
                ? fierceEvidence.impact
                : fierceEvidence.behavior
            session.messages = [ChatMessage(role: .user, content: latestAnswer)]
            let output = CurrentV5PlannerOutput(
                semanticOperation: .continueTenderGroundedFierceReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "",
                reflectionProgressionDecision: .init(
                    meaning: .completeFierce,
                    candidateRef: "reflectionFrame.evidenceBasis.0",
                    reflectionDelta: delta,
                    fierceDirection: fierceEvidence.direction,
                    groundedEvidence: latestAnswer
                )
            )

            let authorized = try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )

            XCTAssertEqual(authorized.operation, .continueTenderGroundedFierceReflection)
            XCTAssertEqual(authorized.projectedPlan.memoryUpdate.reflectionPhase, .synthesis)
            XCTAssertEqual(authorized.projectedPlan.nextPrompt.kind, .openQuestion)
            XCTAssertEqual(authorized.projectedPlan.nextPrompt.purpose, "synthesisReflection")
            XCTAssertEqual(
                authorized.projectedPlan.nextPrompt.focus,
                "synthesize_grounded_fierce_direction"
            )
            XCTAssertNil(authorized.projectedPlan.memoryUpdate.practiceTransition)
        }
    }

    func testDirectionOnlyFierceUsesCanonicalRealityAndSurvivesSynthesis() throws {
        let cases: [(TurnFierceDirection, String, String)] = [
            (
                .protect,
                "我觉得可能需要别人来给我一点经验，就是帮助我一下",
                "当前需要的是获得有经验的人的帮助"
            ),
            (
                .change,
                "我还是想让项目继续往下推进",
                "当前仍然想推动项目继续往下推进"
            ),
        ]

        for (direction, latestAnswer, delta) in cases {
            var session = ReflectionSession()
            session.protocolVersion = ReflectionSession.currentProtocolVersion
            session.protocolStage = .directReflection
            session.condition = .cardMediated
            session.semanticMemory.reflectionPhase = .fierce
            let connection = TurnCardRealityConnection(
                imageRelation: "人物接水后短暂休息，再继续向前",
                realityMapping: "反复 debug 很累，短暂休息后仍然继续",
                source: .userAuthored
            )
            session.semanticMemory.cardRealityConnection = connection
            let committedReality = TurnReflectionEvidence(
                source: .episode,
                content: "试了很多办法仍然没有解决，问题继续增加，项目卡住"
            )
            session.semanticMemory.reflectionFrame = TurnReflectionFrame(
                mode: .tender,
                action: .softenGlobalSelfJudgment,
                evidenceBasis: [
                    committedReality,
                    .init(source: .cardRealityConnection, content: connection.realityMapping),
                ],
                dimensions: [.mindfulness],
                reflectionDelta: "项目当前卡住，并不足以单独支持整体能力否定",
                fierceEvidence: nil
            )
            session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
                purpose: "fierceReflection",
                focus: "clarify_current_grounded_reality_direction"
            ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
            session.messages = [ChatMessage(role: .user, content: latestAnswer)]
            let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
            let data = try XCTUnwrap(
                """
                {
                  "semanticOperation": "continueTenderGroundedFierceReflection",
                  "semanticEvidencePatch": {"memoryUpdate": {}},
                  "reflectionProgressionDecision": {
                    "meaning": "completeFierce",
                    "reflectionDelta": "\(delta)",
                    "fierceDirection": "\(direction.rawValue)"
                  },
                  "responseFocus": ""
                }
                """.data(using: .utf8)
            )
            let planner = try decodeCurrentV5PlannerWireOutput(
                data,
                allowedSemanticOperations: allowed
            )
            let gate = CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            )
            let authorized = try gate.authorize(
                planner,
                for: session,
                allowedSemanticOperations: allowed
            )
            let fierce = try XCTUnwrap(authorized.projectedPlan.memoryUpdate.reflectionFrame)

            XCTAssertTrue(fierce.hasCurrentV5GroundedFierceContribution)
            XCTAssertEqual(fierce.fierceEvidence?.direction, direction)
            XCTAssertEqual(fierce.fierceEvidence?.behavior, "")
            XCTAssertEqual(fierce.fierceEvidence?.impact, "")
            XCTAssertTrue(fierce.evidenceBasis.contains(committedReality))
            XCTAssertTrue(
                fierce.evidenceBasis.contains(
                    .init(source: .cardRealityConnection, content: connection.realityMapping)
                )
            )
            XCTAssertTrue(
                fierce.evidenceBasis.contains(
                    .init(source: .latestUserAnswer, content: latestAnswer)
                )
            )

            session.semanticMemory.apply(authorized.projectedPlan.memoryUpdate)
            XCTAssertTrue(CurrentV5CapabilitySet.hasCommittedSynthesisBasis(in: session))
            XCTAssertEqual(
                CurrentV5CapabilitySet.allowedOperations(for: session),
                [.synthesizeDirectReflection],
                "Completed Fierce must require Synthesis before Action or another Fierce inquiry"
            )

            let synthesisDelta = "综合来看，\(delta)"
            let synthesis = try gate.authorize(
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            reflectionFrame: .init(
                                mode: .tender,
                                action: .synthesizeUnderstanding,
                                evidenceBasis: [],
                                dimensions: [],
                                reflectionDelta: synthesisDelta,
                                fierceEvidence: nil
                            )
                        )
                    ),
                    responseFocus: "只综合已经提交的内容"
                ),
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
            let synthesisFrame = try XCTUnwrap(
                synthesis.projectedPlan.memoryUpdate.reflectionFrame
            )
            XCTAssertEqual(synthesisFrame.mode, .fierce)
            XCTAssertEqual(synthesisFrame.reflectionDelta, synthesisDelta)
            XCTAssertEqual(synthesisFrame.fierceEvidence?.direction, direction)
            XCTAssertTrue(synthesisFrame.hasCurrentV5GroundedFierceContribution)
        }
    }

    func testFierceInquiryMayContinueWithoutContributionButRejectsPartialOrUngroundedContribution() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .fierce
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "当前事情没有按预期推进"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "当前事情受阻不等于整个人没有能力",
            fierceEvidence: nil
        )
        session.semanticMemory.nextPrompt = TurnNextPrompt.openQuestion(
            purpose: "fierceReflection",
            focus: "clarify_current_grounded_reality_direction"
        ).assigningReferenceID("reflectionFrame.evidenceBasis.0")
        let missingContribution = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "项目没有推进时，当前处理方式是否仍然提供了新的判断依据",
            reflectionProgressionDecision: .init(
                meaning: .clarifyFierce,
                candidateRef: "reflectionFrame.evidenceBasis.0"
            )
        )
        let continued = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            missingContribution,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        XCTAssertNil(continued.projectedPlan.memoryUpdate.reflectionFrame)
        XCTAssertEqual(continued.projectedPlan.memoryUpdate.reflectionPhase, .fierce)
        XCTAssertEqual(continued.projectedPlan.nextPrompt.purpose, "fierceReflection")
        XCTAssertEqual(
            continued.projectedPlan.nextPrompt.referenceID,
            "reflectionFrame.evidenceBasis.0"
        )

        let partialContribution = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "",
            reflectionProgressionDecision: .init(
                meaning: .completeFierce,
                candidateRef: "reflectionFrame.evidenceBasis.0",
                fierceDirection: .change,
                groundedEvidence: "当前事情没有按预期推进"
            )
        )
        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                partialContribution,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .continueTenderGroundedFierceReflection,
                    failure: .reflectionProgressionInvalid
                )
            )
        }

        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .cardRealityConnection, content: "画面里的人停下来接水"),
            ],
            dimensions: [],
            reflectionDelta: "只有 Card material，没有现实事件基础",
            fierceEvidence: nil
        )
        let directionWithoutReality = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderGroundedFierceReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "",
            reflectionProgressionDecision: .init(
                meaning: .completeFierce,
                candidateRef: "reflectionFrame.evidenceBasis.0",
                reflectionDelta: "系统认为用户应该改变",
                fierceDirection: .change,
                groundedEvidence: nil
            )
        )
        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                directionWithoutReality,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .continueTenderGroundedFierceReflection,
                    failure: .reflectionProgressionInvalid
                )
            )
        }
    }

    func testInvalidatedInterpretationsAccumulateAsTypedSemanticMemory() {
        var memory = TurnSemanticMemory()
        memory.apply(.init(invalidatedInterpretations: ["面对bug时很有耐心"]))
        memory.apply(.init(invalidatedInterpretations: ["面对bug时很有耐心", "这种耐心是一种力量"]))

        XCTAssertEqual(
            memory.invalidatedInterpretations,
            ["面对bug时很有耐心", "这种耐心是一种力量"]
        )
    }

    func testInvalidatedTypedPropositionCannotReturnAsReflectionEvidence() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.invalidatedInterpretations = ["面对bug时很有耐心"]
        let invalidFrame = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "面对bug时很有耐心"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "把等待理解成一种耐心",
            fierceEvidence: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .continueTenderReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: invalidFrame)
            ),
            responseFocus: "继续使用用户已经否定的解释"
        )

        XCTAssertThrowsError(
            try CurrentV5SwiftTurnGate(
                protocolController: ReflectionProtocolController()
            ).authorize(
                output,
                for: session,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .continueTenderReflection,
                    failure: .rejectedInterpretationReused
                )
            )
        }

    }

    func testNextPromptCannotChangeCanonicalReflectionPhase() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .exploratory
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "fierceReflection",
            focus: "legacy or conflicting wording metadata"
        )

        let operations = CurrentV5CapabilitySet.allowedOperations(for: session)

        XCTAssertTrue(operations.contains(.continueExploratoryReflection))
        XCTAssertFalse(operations.contains(.continueTenderReflection))
        XCTAssertFalse(operations.contains(.continueTenderGroundedFierceReflection))
        XCTAssertFalse(operations.contains(.synthesizeDirectReflection))
    }

    func testSynthesisRequiresAPreviouslyCommittedGroundedTenderBasis() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender

        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: session)
                .contains(.synthesizeDirectReflection)
        )

        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .cardRealityConnection, content: "画面里的人换了一种方法"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "可以换一种方法",
            fierceEvidence: nil
        )
        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: session)
                .contains(.synthesizeDirectReflection),
            "A card relation or solution-shaped delta is not grounded reality evidence"
        )

        let committedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "这次汇报放错了旧版本图片"),
                .init(source: .latestUserAnswer, content: "用户担心别人因此觉得自己不专业"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "一次放错图片需要面对，但现有事实不足以把它扩大成不专业",
            fierceEvidence: nil
        )
        session.semanticMemory.reflectionFrame = committedTender
        XCTAssertTrue(
            CurrentV5CapabilitySet.allowedOperations(for: session)
                .contains(.synthesizeDirectReflection)
        )

        let sparseSynthesis = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [],
            dimensions: [],
            reflectionDelta: "这次具体失误需要面对，但不能单独证明自己整体不专业",
            fierceEvidence: nil
        )
        let output = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: sparseSynthesis)
            ),
            responseFocus: "综合已经提交的 Tender 理解",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )

        let authorizedSynthesis = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            output,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let canonicalSynthesis = try XCTUnwrap(
            authorizedSynthesis.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(canonicalSynthesis.evidenceBasis, committedTender.evidenceBasis)
        XCTAssertEqual(canonicalSynthesis.dimensions, committedTender.dimensions)
        XCTAssertNil(canonicalSynthesis.fierceEvidence)

        let uncommittedFierceSynthesis = TurnReflectionFrame(
            mode: .fierce,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "这次汇报放错了旧版本图片"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "需要承担的是没有检查版本",
            fierceEvidence: .init(
                behavior: "没有检查版本",
                impact: "汇报中展示了错误图片",
                direction: .change
            )
        )
        let fierceOutput = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(reflectionFrame: uncommittedFierceSynthesis)
            ),
            responseFocus: "在 Tender-only Synthesis 中新增责任判断",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )
        let canonicalized = try CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        ).authorize(
            fierceOutput,
            for: session,
            allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(for: session)
        )
        let canonicalizedFrame = try XCTUnwrap(
            canonicalized.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(canonicalizedFrame.mode, .tender)
        XCTAssertEqual(canonicalizedFrame.action, .synthesizeUnderstanding)
        XCTAssertNil(canonicalizedFrame.fierceEvidence)
        XCTAssertEqual(canonicalizedFrame.evidenceBasis, committedTender.evidenceBasis)
    }

    func testSynthesisCanonicalizesProtocolMetadataButStillRequiresSemanticDelta() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .tender
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "问题反复修改后仍未解决"),
                .init(source: .latestUserAnswer, content: "用户因此怀疑自己不适合开发"),
            ],
            dimensions: [.selfKindness],
            reflectionDelta: "问题仍未解决，不等同于整个人不适合开发",
            fierceEvidence: nil
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )

        let redundantMetadata = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    reflectionFrame: .init(
                        mode: .fierce,
                        action: .softenGlobalSelfJudgment,
                        evidenceBasis: [
                            .init(source: .confirmedContext, content: "未经用户确认的背景解释"),
                        ],
                        dimensions: [],
                        reflectionDelta: "形成综合",
                        fierceEvidence: .init(
                            behavior: "模型自行添加的行为",
                            impact: "模型自行添加的影响",
                            direction: .change
                        )
                    )
                )
            ),
            responseFocus: "形成暂定综合",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )
        let canonical = try gate.authorize(
            redundantMetadata,
            for: session,
            allowedSemanticOperations: allowed
        )
        let canonicalFrame = try XCTUnwrap(
            canonical.projectedPlan.memoryUpdate.reflectionFrame
        )
        XCTAssertEqual(canonicalFrame.mode, .tender)
        XCTAssertEqual(canonicalFrame.action, .synthesizeUnderstanding)
        XCTAssertNil(canonicalFrame.fierceEvidence)
        XCTAssertEqual(
            canonicalFrame.evidenceBasis,
            try XCTUnwrap(session.semanticMemory.reflectionFrame).evidenceBasis
        )

        let committedDelta = try XCTUnwrap(
            session.semanticMemory.reflectionFrame
        ).reflectionDelta
        let explicitSameMeaningInitialSynthesis = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "简洁呈现已经形成的理解",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: committedDelta
            )
        )
        XCTAssertThrowsError(
            try gate.authorize(
                explicitSameMeaningInitialSynthesis,
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .synthesizeDirectReflection,
                    failure: .synthesisDeltaMissing
                )
            )
        }

        var committedSynthesisSession = session
        committedSynthesisSession.semanticMemory.reflectionPhase = .synthesis
        committedSynthesisSession.semanticMemory.reflectionFrame = canonicalFrame
        let unchangedInPlaceRevision = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    reflectionFrame: .init(
                        mode: .tender,
                        action: .synthesizeUnderstanding,
                        evidenceBasis: [],
                        dimensions: [],
                        reflectionDelta: canonicalFrame.reflectionDelta,
                        fierceEvidence: nil
                    )
                )
            ),
            responseFocus: "重复既有综合"
        )
        XCTAssertThrowsError(
            try gate.authorize(
                unchangedInPlaceRevision,
                for: committedSynthesisSession,
                allowedSemanticOperations: CurrentV5CapabilitySet.allowedOperations(
                    for: committedSynthesisSession
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .synthesizeDirectReflection,
                    failure: .synthesisDeltaMissing
                )
            )
        }

        let missingDelta = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(
                memoryUpdate: .init(
                    reflectionFrame: .init(
                        mode: .tender,
                        action: .synthesizeUnderstanding,
                        evidenceBasis: [],
                        dimensions: [],
                        reflectionDelta: "   ",
                        fierceEvidence: nil
                    )
                )
            ),
            responseFocus: "",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )
        XCTAssertThrowsError(
            try gate.authorize(
                missingDelta,
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .synthesizeDirectReflection,
                    failure: .synthesisDeltaMissing
                )
            )
        }

        let focusOnly = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "这段 Writer 指令不能成为持久化综合",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )
        XCTAssertThrowsError(
            try gate.authorize(
                focusOnly,
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .synthesizeDirectReflection,
                    failure: .synthesisFrameMissing
                )
            )
        }
    }

    func testSynthesisPhaseProgressionAcceptsRevisionAndRejectsMissingOrUnchangedDelta() throws {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .directReflection
        session.semanticMemory.reflectionPhase = .synthesis
        session.semanticMemory.reflectionFrame = TurnReflectionFrame(
            mode: .tender,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "临时工作挤压了原有安排")
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "需要区分额外任务造成的延迟和整体效率判断",
            fierceEvidence: nil
        )
        let gate = CurrentV5SwiftTurnGate(
            protocolController: ReflectionProtocolController()
        )
        let allowed = CurrentV5CapabilitySet.allowedOperations(for: session)

        let revisedDelta = "更准确地说，额外任务挤压了时间，但具体效率仍需要单独判断"
        let revised = try gate.authorize(
            .init(
                semanticOperation: .synthesizeDirectReflection,
                semanticEvidencePatch: .init(),
                responseFocus: "只呈现这次修订",
                reflectionProgressionDecision: .init(
                    meaning: .synthesize,
                    candidateRef: nil,
                    reflectionDelta: revisedDelta
                )
            ),
            for: session,
            allowedSemanticOperations: allowed
        )
        XCTAssertEqual(
            revised.projectedPlan.memoryUpdate.reflectionFrame?.reflectionDelta,
            revisedDelta
        )

        let missingDelta = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "不能代替综合内容",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil
            )
        )
        XCTAssertThrowsError(
            try gate.authorize(
                missingDelta,
                for: session,
                allowedSemanticOperations: allowed
            )
        )

        let unchanged = CurrentV5PlannerOutput(
            semanticOperation: .synthesizeDirectReflection,
            semanticEvidencePatch: .init(),
            responseFocus: "不能把重复内容当修订",
            reflectionProgressionDecision: .init(
                meaning: .synthesize,
                candidateRef: nil,
                reflectionDelta: session.semanticMemory.reflectionFrame?.reflectionDelta
            )
        )
        XCTAssertThrowsError(
            try gate.authorize(
                unchanged,
                for: session,
                allowedSemanticOperations: allowed
            )
        ) { error in
            XCTAssertEqual(
                error as? CurrentV5CoreError,
                .projectionInvalid(
                    operation: .synthesizeDirectReflection,
                    failure: .synthesisDeltaMissing
                )
            )
        }
    }

    func testSafetyOperationIsUnavailableInEveryOrdinaryCurrentV5Stage() {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion

        let ordinaryStages: [ReflectionProtocolStage] = [
            .contextualDisclosure,
            .cardConsent,
            .cardReflection,
            .directReflection,
            .narrativeConfirmation,
            .optionalAction,
            .complete,
        ]

        for stage in ordinaryStages {
            session.protocolStage = stage
            session.semanticMemory.reflectionPhase = .exploratory
            XCTAssertFalse(
                CurrentV5CapabilitySet.allowedOperations(for: session)
                    .contains(.provideSafetySupport),
                "Ordinary stage \(stage.rawValue) must not expose Planner-selected Safety"
            )
        }

        session.protocolStage = .safetySupport
        XCTAssertTrue(
            CurrentV5CapabilitySet.allowedOperations(for: session)
                .contains(.provideSafetySupport)
        )
    }

    func testOrdinaryPreTurnCapabilitiesCannotIncludeSafetyOperation() {
        var eventSession = ReflectionSession()
        eventSession.protocolVersion = ReflectionSession.currentProtocolVersion
        eventSession.protocolStage = .contextualDisclosure
        eventSession.semanticMemory.episodeStructure = TurnEpisodeStructure(
            concreteFacts: ["项目运行时报错"]
        )
        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: eventSession)
                .contains(.provideSafetySupport)
        )

        var cardSession = currentCardReflectionSession()
        cardSession.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["画面里的人和倒置的画"]
        )
        XCTAssertFalse(
            CurrentV5CapabilitySet.allowedOperations(for: cardSession)
                .contains(.provideSafetySupport)
        )
    }

    func testOrdinaryUncertaintyNeverOffersPlannerSafetyExit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-ordinary-uncertainty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "澄清刚才暂定的理解，不把普通迟疑解释成风险"
                ),
            ],
            replies: ["我刚才说得有些满了，那只是一个暂时的整理。你现在更想停在哪一部分？"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .exploratory

        model.draft = "这样吗"
        model.send()
        await waitUntilIdle(model)

        let capturedRequest = await core.request(at: 0)
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertFalse(request.allowedSemanticOperations.contains(.provideSafetySupport))
        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
        XCTAssertFalse(
            model.session.studyEvents.contains { $0.action == "safety_signal_detected" }
        )
    }

    func testExplicitLocalSafetySignalInterruptsBeforeCurrentV5Planner() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-local-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let core = ScriptedCurrentV5CoreTurnController(plans: [], replies: [])
        let legacy = RejectingLegacyTurnController()
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: legacy,
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated

        model.draft = "我现在想伤害自己。"
        model.send()

        let corePlanCalls = await core.planCount()
        let coreWriteCalls = await core.writeCount()
        let legacyPlanCalls = await legacy.planCount()
        XCTAssertEqual(model.session.protocolStage, .safetySupport)
        XCTAssertEqual(model.session.stage, .safetySupport)
        XCTAssertEqual(corePlanCalls, 0)
        XCTAssertEqual(coreWriteCalls, 0)
        XCTAssertEqual(legacyPlanCalls, 0)
        XCTAssertTrue(
            model.session.studyEvents.contains { $0.action == "safety_signal_detected" }
        )
        XCTAssertTrue(
            model.session.messages.last(where: { $0.role == .assistant })?
                .content.contains("暂停普通反思") == true
        )
    }

    func testCurrentV5CompleteCardMediatedJourneyReachesFinalNarrativeWithoutDuplicateTurns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-complete-journey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let connection = TurnCardRealityConnection(
            imageRelation: "画面里的人先停下来确认手里的东西，再决定怎么继续",
            realityMapping: "汇报时我没有停下来核对图片版本，而是直接继续了",
            source: .userAuthored
        )
        let tender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: [
                .init(source: .episode, content: "汇报时放错了旧版本图片"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
                .init(source: .latestUserAnswer, content: "我觉得自己很不专业"),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "一次没有核对版本的失误需要面对，但不足以单独证明我不专业",
            fierceEvidence: nil
        )
        let continuedTender = TurnReflectionFrame(
            mode: .tender,
            action: .softenGlobalSelfJudgment,
            evidenceBasis: tender.evidenceBasis + [
                .init(source: .latestUserAnswer, content: "我最难受的是担心别人因此觉得我不专业"),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "担心别人如何评价这次失误会放大痛苦，但这种担心仍不等于别人已经认定自己不专业",
            fierceEvidence: nil
        )
        let fierceEvidence = TurnFierceEvidence(
            behavior: "汇报前没有核对图片版本",
            impact: "展示了旧版本图片",
            direction: .change
        )
        let fierce = TurnReflectionFrame(
            mode: .fierce,
            action: .identifyChangeDirection,
            evidenceBasis: [
                .init(source: .episode, content: "汇报时放错了旧版本图片"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
                .init(source: .latestUserAnswer, content: "下次需要在汇报前确认版本"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "不需要用不专业惩罚自己，同时需要改变汇报前没有核对版本的做法",
            fierceEvidence: fierceEvidence
        )
        let synthesis = TurnReflectionFrame(
            mode: .fierce,
            action: .synthesizeUnderstanding,
            evidenceBasis: [
                .init(source: .episode, content: "汇报时放错了旧版本图片"),
                .init(source: .cardRealityConnection, content: connection.realityMapping),
                .init(source: .latestUserAnswer, content: "下次需要在汇报前确认版本"),
            ],
            dimensions: [.mindfulness, .selfKindness],
            reflectionDelta: "这次具体失误和整体职业判断可以分开，真正需要改变的是汇报前的版本核对",
            fierceEvidence: fierceEvidence
        )
        let revisedSynthesis = TurnReflectionFrame(
            mode: .fierce,
            action: .synthesizeUnderstanding,
            evidenceBasis: synthesis.evidenceBasis,
            dimensions: synthesis.dimensions,
            reflectionDelta: "更准确地说，这次失误不能单独证明我不专业，但汇报前核对版本是我需要承担并改变的部分",
            fierceEvidence: fierceEvidence
        )
        let proposal = TurnPracticeProposal(
            id: "practice-check-version",
            kind: .change,
            content: "下次汇报前，用一分钟核对文件名和图片版本",
            basis: "episodeStructure.behaviorEvidence.0",
            status: .pendingConfirmation
        )
        let pendingPractice = TurnPracticeTransition(
            transactionID: proposal.id,
            narrativeReferenceID: nil,
            proposal: proposal,
            noActionReason: nil
        )
        let declinedPractice = TurnPracticeTransition(
            transactionID: proposal.id,
            narrativeReferenceID: nil,
            proposal: proposal,
            noActionReason: .userDeclined
        )
        let finalNarrative = "这次汇报确实放错了旧图，汇报前没有核对版本是需要改变的具体环节；它本身不足以单独证明我不专业。这份记录符合你现在的理解吗？"

        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            selfCriticismStatus: .present,
                            selfCriticalStatement: "我很不专业",
                            episodeStructure: .init(
                                concreteFacts: ["昨天汇报时放错了旧版本图片"]
                            )
                        )
                    ),
                    responseFocus: "只询问这次失误是怎么发生的"
                ),
                .init(
                    semanticOperation: .clarifyEvent,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            episodeStructure: .init(
                                behaviorEvidenceStatus: .present,
                                behaviorEvidence: ["汇报前没有核对图片版本"],
                                eventProcessStatus: .present,
                                eventProcess: ["准备材料时选了旧图，展示时才发现"]
                            )
                        )
                    ),
                    responseFocus: "事件已经足够具体，简短承接并邀请随机反思卡"
                ),
                .init(
                    semanticOperation: .continueCardObservation,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            cardObservationEvidence: .init(
                                userDescribedElements: ["一个人", "手里的文件", "门口"]
                            )
                        )
                    ),
                    responseFocus: "沿用户注意到的画面元素发展一个未确定关系"
                ),
                .init(
                    semanticOperation: .continueCardDevelopment,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            cardDevelopmentEvidence: .init(
                                actorsOrElements: ["一个人", "手里的文件", "门口"],
                                projectiveFocus: "出发前是否停下来确认",
                                relationOrAction: "人物站在门口查看手里的文件",
                                anticipatedChangeOrChoice: "确认后再决定是否继续"
                            )
                        )
                    ),
                    responseFocus: "画面已有最小叙事，邀请用户自主连接现实"
                ),
                .init(
                    semanticOperation: .continueOpenCardConnection,
                    semanticEvidencePatch: .init(
                        cardConnectionEvidence: .init(
                            imageRelation: connection.imageRelation,
                            realityMapping: connection.realityMapping
                        )
                    ),
                    responseFocus: "沿用户建立的停下来核对与现实中未核对的差异开始探索"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "只澄清具体失误如何被连接到整体不专业的判断"
                ),
                .init(
                    semanticOperation: .continueExploratoryReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            selfCriticismLink: "汇报前没有核对版本并放错图片后扩大了判断 -> 我很不专业",
                            reflectionFrame: tender
                        )
                    ),
                    responseFocus: tender.reflectionDelta
                ),
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: continuedTender)
                    ),
                    responseFocus: "沿用户刚说出的评价担心，形成第一份更公平但不失真的理解"
                ),
                .init(
                    semanticOperation: .continueTenderGroundedFierceReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "这段自由文本不应覆盖 Swift 选中的现实候选",
                    reflectionProgressionDecision: .init(
                        meaning: .inspectReality,
                        candidateRef: "episodeStructure.behaviorEvidence.0"
                    )
                ),
                .init(
                    semanticOperation: .continueTenderGroundedFierceReflection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "",
                    reflectionProgressionDecision: .init(
                        meaning: .completeFierce,
                        candidateRef: "episodeStructure.behaviorEvidence.0",
                        reflectionDelta: fierce.reflectionDelta,
                        fierceDirection: .change,
                        groundedEvidence: "汇报前确实没有核对图片版本"
                    )
                ),
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: synthesis)
                    ),
                    responseFocus: "整合已形成的 Tender 与 Fierce 理解并允许修订"
                ),
                .init(
                    semanticOperation: .synthesizeDirectReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(reflectionFrame: revisedSynthesis)
                    ),
                    responseFocus: "回应用户疑问，降低结论强度并原地修订"
                ),
                .init(
                    semanticOperation: .proposePractice,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(practiceTransition: pendingPractice)
                    ),
                    responseFocus: "提出一个小而具体的版本核对动作"
                ),
                .init(
                    semanticOperation: .resolvePractice,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            finalNarrative: finalNarrative,
                            practiceTransition: declinedPractice
                        )
                    ),
                    responseFocus: "尊重用户拒绝行动，并给出可修订的最终叙事"
                ),
                .init(
                    semanticOperation: .completeConversation,
                    semanticEvidencePatch: .init(),
                    responseFocus: "用户接受最终叙事，简短结束"
                ),
            ],
            replies: [
                "当时是怎么放进旧图的？",
                "这次经过已经说清楚了。我们抽一张随机反思卡，换个角度看看吗？",
                "这个人停在门口看着手里的文件。接下来他可能会怎么做？",
                "这个先确认再继续的过程，会让你想到这次汇报里的什么？",
                "那次汇报里，你没有停下来核对。这个差异最先让你注意到什么？",
                "放错一张图，后来为什么会变成对自己是否专业的判断？",
                "这条关系已经说清楚了。接下来可以一起看看，怎样更准确地理解这个判断。",
                "一直猜别人会怎样看这次失误，会让它在心里变得更重。先不替别人下结论，你会怎样看待当时那个出了错的自己？",
                "汇报前没有核对图片版本。这个环节当时确实漏掉了吗？",
                "这次确实漏了版本核对，这是一个具体需要面对的环节。",
                "这次失误和对整个人的判断可以分开；需要承担的是汇报前的版本核对。这个整理里有哪里不符合你？",
                "更准确地说，这次失误不能单独证明你不专业，但版本核对确实是需要改变的部分。",
                "下次汇报前，可以用一分钟核对文件名和图片版本。你愿意试试吗？",
                finalNarrative,
                "好，这次就先到这里。",
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .contextualDisclosure
        model.session.stage = .eventDisclosure
        model.session.condition = .cardMediated

        func send(_ text: String) async {
            model.draft = text
            model.send()
            await waitUntilIdle(model)
        }

        await send("昨天汇报时放错了旧版本图片，我觉得自己很不专业。")
        await send("准备材料时选了旧图，汇报前也没核对，展示时才发现。")
        XCTAssertEqual(model.session.protocolStage, .cardConsent)

        await send("好")
        let cardID = try XCTUnwrap(model.session.card?.id)
        model.cardDidDisplay(cardID: cardID)
        XCTAssertEqual(model.session.protocolStage, .cardReflection)

        await send("我看到一个人站在门口，手里拿着文件。")
        await send("他可能会先看清楚手里的文件，再决定要不要出去。")
        await send(connection.realityMapping)
        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, connection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)

        await send("它让我注意到，我当时只想着把汇报继续下去。")
        await send("因为这么基本的版本都没核对，我就担心自己根本不专业。")
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertNil(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(
            model.session.semanticMemory.selfCriticismLink,
            "汇报前没有核对版本并放错图片后扩大了判断 -> 我很不专业"
        )
        XCTAssertTrue(
            tender.evidenceBasis.contains {
                $0.source == .cardRealityConnection && $0.content == connection.realityMapping
            }
        )

        await send("我最难受的是担心别人因此觉得我不专业。")
        let committedContinuation = try XCTUnwrap(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(committedContinuation.action, continuedTender.action)
        XCTAssertEqual(committedContinuation.reflectionDelta, continuedTender.reflectionDelta)
        XCTAssertTrue(
            tender.evidenceBasis.allSatisfy {
                committedContinuation.evidenceBasis.contains($0)
            }
        )
        XCTAssertTrue(
            continuedTender.evidenceBasis.allSatisfy {
                committedContinuation.evidenceBasis.contains($0)
            }
        )
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)

        await send("我不需要骂自己，但汇报前确实应该核对版本。")
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .fierce)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame, committedContinuation)

        await send("汇报前确实没有核对图片版本。")
        let committedFierce = try XCTUnwrap(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.purpose, "synthesisReflection")
        XCTAssertEqual(
            CurrentV5CapabilitySet.allowedOperations(for: model.session),
            [.synthesizeDirectReflection]
        )
        XCTAssertEqual(committedFierce.mode, fierce.mode)
        XCTAssertEqual(committedFierce.action, fierce.action)
        XCTAssertEqual(committedFierce.dimensions, continuedTender.dimensions)
        XCTAssertEqual(committedFierce.reflectionDelta, fierce.reflectionDelta)
        XCTAssertEqual(committedFierce.fierceEvidence?.direction, .change)
        XCTAssertEqual(committedFierce.fierceEvidence?.behavior, "")
        XCTAssertEqual(committedFierce.fierceEvidence?.impact, "")
        XCTAssertTrue(
            committedFierce.evidenceBasis.contains(
                .init(
                    source: .latestUserAnswer,
                    content: "汇报前确实没有核对图片版本。"
                )
            )
        )
        XCTAssertTrue(
            committedContinuation.evidenceBasis.allSatisfy {
                committedFierce.evidenceBasis.contains($0)
            }
        )
        XCTAssertTrue(
            committedFierce.evidenceBasis.contains {
                $0.source == .episode && tender.evidenceBasis.contains($0)
            }
        )
        await send("真正需要改变的是版本核对，不是给自己下结论。")
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .synthesis)
        let committedSynthesis = try XCTUnwrap(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(committedSynthesis.mode, synthesis.mode)
        XCTAssertEqual(committedSynthesis.action, synthesis.action)
        XCTAssertEqual(committedSynthesis.dimensions, synthesis.dimensions)
        XCTAssertEqual(committedSynthesis.reflectionDelta, synthesis.reflectionDelta)
        XCTAssertEqual(committedSynthesis.fierceEvidence, committedFierce.fierceEvidence)
        XCTAssertTrue(
            committedFierce.evidenceBasis.allSatisfy {
                committedSynthesis.evidenceBasis.contains($0)
            }
        )
        XCTAssertTrue(
            synthesis.evidenceBasis.contains {
                $0.source == .cardRealityConnection && $0.content == connection.realityMapping
            }
        )

        await send("这样吗")
        let committedRevision = try XCTUnwrap(model.session.semanticMemory.reflectionFrame)
        XCTAssertEqual(committedRevision.mode, revisedSynthesis.mode)
        XCTAssertEqual(committedRevision.action, revisedSynthesis.action)
        XCTAssertEqual(committedRevision.dimensions, revisedSynthesis.dimensions)
        XCTAssertEqual(committedRevision.reflectionDelta, revisedSynthesis.reflectionDelta)
        XCTAssertEqual(committedRevision.fierceEvidence, committedSynthesis.fierceEvidence)
        XCTAssertEqual(committedRevision.evidenceBasis, committedSynthesis.evidenceBasis)
        XCTAssertNil(model.session.semanticMemory.practiceTransition)

        await send("这样更准确，我愿意看看一个小步骤。")
        XCTAssertEqual(model.session.protocolStage, .optionalAction)
        XCTAssertEqual(proposal.basis, "episodeStructure.behaviorEvidence.0")
        await send("这个行动我现在不想做。")
        XCTAssertEqual(model.session.protocolStage, .narrativeConfirmation)
        XCTAssertEqual(
            model.session.semanticMemory.finalNarrative,
            revisedSynthesis.reflectionDelta + "\n这次没有加入新的行动。"
        )
        XCTAssertEqual(
            model.session.semanticMemory.practiceTransition?.noActionReason,
            .userDeclined
        )
        await send("这个总结可以。")

        XCTAssertEqual(model.session.protocolStage, .complete)
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 15)
        XCTAssertEqual(writeCount, 15)

        let committedOperations = model.session.studyEvents.compactMap { event -> String? in
            let prefix = "current_v5_core_turn_committed_"
            guard event.action.hasPrefix(prefix) else { return nil }
            return String(event.action.dropFirst(prefix.count))
        }
        XCTAssertEqual(
            committedOperations,
            [
                "clarifyEvent", "clarifyEvent",
                "continueCardObservation", "continueCardDevelopment",
                "continueOpenCardConnection", "continueExploratoryReflection",
                "continueExploratoryReflection", "continueTenderReflection",
                "continueTenderGroundedFierceReflection",
                "continueTenderGroundedFierceReflection",
                "synthesizeDirectReflection", "synthesizeDirectReflection", "proposePractice",
                "resolvePractice", "completeConversation",
            ]
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("single_correction")
                    || $0.action.contains("final_rejection")
                    || $0.action.contains("planner_or_gate_unavailable")
                    || $0.action.contains("writer_unavailable")
            }
        )

        let messages = model.session.messages
        for index in 1..<messages.count {
            XCTAssertFalse(
                messages[index - 1].role == .assistant && messages[index].role == .assistant,
                "Assistant messages must not be consecutive at index \(index)"
            )
        }
        let visibleReplies = messages.filter { $0.role == .assistant }.map(\.content)
        XCTAssertEqual(Set(visibleReplies).count, visibleReplies.count)
        let userMessageIDs = Set(messages.filter { $0.role == .user }.map(\.id))
        XCTAssertTrue(
            messages.filter { $0.role == .assistant }.allSatisfy {
                $0.replyToMessageID == nil || userMessageIDs.contains($0.replyToMessageID!)
            }
        )
    }

    func testObjectCorrespondenceUsesRealityLanguageBeforeCommittingAConnection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-object-to-relation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let connection = TurnCardRealityConnection(
            imageRelation: "最后一块瓷砖与当前结构不完全适配，可能需要调整或更换",
            realityMapping: "看过评审意见后，稿件的结构和论证确实有需要重新调整的部分",
            source: .userAuthored
        )
        let realityQuestion = "回到这次投稿本身，你看完评审意见后，具体觉得论文哪些地方需要调整？"
        let explorationQuestion = "在处理这些修改的过程中，“不适合科研”这个判断大概是从什么时候开始出现的？"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .offerCardConnectionScaffold,
                    semanticEvidencePatch: .init(),
                    responseFocus: "对象或属性对应已经出现，只用现实语言询问稿件实际需要怎样调整"
                ),
                .init(
                    semanticOperation: .continueOpenCardConnection,
                    semanticEvidencePatch: .init(
                        cardConnectionEvidence: .init(
                            imageRelation: connection.imageRelation,
                            realityMapping: connection.realityMapping
                        )
                    ),
                    responseFocus: "保存用户形成的差异关系，卡牌退场并进入现实探索"
                ),
            ],
            replies: [realityQuestion, explorationQuestion]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session = currentCardReflectionSession()
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["已经铺好的结构", "最后一块瓷砖"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["已经铺好的结构", "最后一块瓷砖"],
            projectiveFocus: "最后一块是否适配",
            relationOrAction: "最后一块与当前结构似乎不完全适配",
            anticipatedChangeOrChoice: "可能调整，也可能更换"
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        model.draft = "瓷砖像我的论文。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            realityQuestion
        )
        XCTAssertFalse(realityQuestion.contains("瓷砖"))
        XCTAssertFalse(realityQuestion.contains("最像"))
        XCTAssertFalse(realityQuestion.contains("对应"))

        model.draft = "我看完评审意见后，觉得论文的结构和论证确实需要重新调整。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.cardRealityConnection, connection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .exploratory)
        XCTAssertTrue(model.session.cardWasSetAside)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            explorationQuestion
        )
        XCTAssertFalse(explorationQuestion.contains("瓷砖"))
        XCTAssertFalse(explorationQuestion.contains("画面"))
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("single_correction")
                    || $0.action.contains("final_rejection")
                    || $0.action.contains("planner_or_gate_unavailable")
            }
        )
    }

    func testUnclearRealityAnswerCanonicalizesAContradictoryConnectionOperationWithoutCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-unclear-connection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let realityQuestion = "先不用找一一对应。你刚才说他可能收回东西，也可能换个地方，这一步还没有确定；这种‘接下来怎么走还说不准’的感觉，放回昨天的争吵里，有没有让你想到一点什么？"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueOpenCardConnection,
                    semanticEvidencePatch: .init(),
                    responseFocus: "用户暂时没有形成连接；转回现实经历继续一个低负担问题"
                ),
            ],
            replies: [realityQuestion]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session = currentCardReflectionSession()
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["摆摊的人", "下雨"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["摆摊的人", "摊位"],
            projectiveFocus: "下雨以后如何继续",
            relationOrAction: "摆摊的人开始收拾东西",
            anticipatedChangeOrChoice: "可能收回东西，也可能换地方"
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        model.draft = "有点没想到。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            realityQuestion
        )
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("single_correction")
                    || $0.action.contains("final_rejection")
                    || $0.action.contains("planner_or_gate_unavailable")
            }
        )
    }

    func testGenericSharedPropertyClaimStaysNonCanonicalAndAsksOneRealityQuestion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-thin-property-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let realityQuestion = "回到这次投稿本身，你看完评审意见后，具体觉得论文哪些地方需要调整？"
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .offerCardConnectionScaffold,
                    semanticEvidencePatch: .init(),
                    responseFocus: "泛泛的属性对应还不是现实关系；只询问稿件实际需要怎样调整"
                ),
            ],
            replies: [realityQuestion]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session = currentCardReflectionSession()
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["已经铺好的结构", "最后一块瓷砖"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["已经铺好的结构", "最后一块瓷砖"],
            projectiveFocus: "最后一块是否适配",
            relationOrAction: "最后一块与当前结构似乎不完全适配",
            anticipatedChangeOrChoice: "可能调整，也可能更换"
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        model.draft = "我的论文可能也需要改。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .cardReflection)
        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .assistant })?.content,
            realityQuestion
        )
        XCTAssertFalse(realityQuestion.contains("瓷砖"))
        XCTAssertFalse(realityQuestion.contains("最像"))
        XCTAssertFalse(realityQuestion.contains("对应"))
    }

    func testConnectionDifficultyUsesOneScaffoldThenCandidateInsteadOfRepeatingUnknownQuestion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-connection-difficulty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let pending = PendingCardRealityConnection(
            imageRelation: "画面里的人在出发前停下来检查手里的文件",
            candidateRealityMapping: "也许可以先比较画面中的停下来，和现实中直接继续汇报的差异"
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .offerCardConnectionScaffold,
                    semanticEvidencePatch: .init(),
                    responseFocus: "第一次连接困难，只指出用户已说出的尚未决定，不提供现实含义"
                ),
                .init(
                    semanticOperation: .offerCardConnectionCandidate,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(pendingCardRealityConnection: pending)
                    ),
                    responseFocus: "第二次仍不知道，提供一个明确可拒绝的候选连接"
                ),
            ],
            replies: [
                "先不用找一一对应。你刚才说他还在门口查看文件，也还没决定是否出发；这种‘下一步还没有确定’的感觉，放回那次汇报里，有没有让你想到一点什么？",
                "也许可以只比较一个差异：画面里的人停下来确认，而你当时直接继续了。这只是一种可能，不符合可以直接拒绝。",
            ]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session = currentCardReflectionSession()
        model.session.semanticMemory.cardObservationEvidence = .init(
            userDescribedElements: ["一个人", "手里的文件", "门口"]
        )
        model.session.semanticMemory.cardDevelopmentEvidence = .init(
            actorsOrElements: ["一个人", "手里的文件", "门口"],
            projectiveFocus: "出发前是否确认",
            relationOrAction: "人物在门口查看文件",
            anticipatedChangeOrChoice: "确认后再决定是否出发"
        )
        model.session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "cardRealityConnection",
            focus: "connect_image_to_reality"
        )

        model.draft = "目前联想不到。"
        model.send()
        await waitUntilIdle(model)
        let firstReply = try XCTUnwrap(
            model.session.messages.last(where: { $0.role == .assistant })?.content
        )
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.cardConnectionScaffoldUsed)
        XCTAssertNil(model.session.semanticMemory.pendingCardRealityConnection)

        model.draft = "不知道。"
        model.send()
        await waitUntilIdle(model)
        let secondReply = try XCTUnwrap(
            model.session.messages.last(where: { $0.role == .assistant })?.content
        )

        XCTAssertNotEqual(firstReply, secondReply)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertEqual(model.session.semanticMemory.pendingCardRealityConnection, pending)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.kind, .confirmationRequest)
        XCTAssertEqual(model.session.semanticMemory.nextPrompt?.target, .cardRealityConnection)
        XCTAssertNil(model.session.semanticMemory.cardRealityConnection)
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 2)
        XCTAssertEqual(writeCount, 2)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.contains("single_correction")
                    || $0.action.contains("final_rejection")
                    || $0.action.contains("planner_or_gate_unavailable")
            }
        )
    }

    func testTenderCorrectionInvalidatesRejectedInterpretationAndStaysInTender() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeyondComfort-current-tender-correction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rejected = "等待说明你很有耐心"
        let corrected = TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .episode, content: "等待 bug 处理"),
                .init(source: .latestUserAnswer, content: "我不是耐心，我其实很着急"),
            ],
            dimensions: [.mindfulness],
            reflectionDelta: "着急和流程被卡住是当前事实，不需要把等待改写成积极人格结论",
            fierceEvidence: nil
        )
        let core = ScriptedCurrentV5CoreTurnController(
            plans: [
                .init(
                    semanticOperation: .continueTenderReflection,
                    semanticEvidencePatch: .init(
                        memoryUpdate: .init(
                            reflectionFrame: corrected,
                            invalidatedInterpretations: [rejected]
                        )
                    ),
                    responseFocus: "采用用户修正，不再使用被否定的耐心解释",
                    reflectionProgressionDecision: .init(
                        meaning: .reviseTender,
                        candidateRef: nil
                    )
                ),
            ],
            replies: ["对，你说的是着急，不是耐心。bug 卡住流程本身已经够难受，不需要再把它解释成一种优点。"]
        )
        let model = ReflectionViewModel(
            analyzer: UnusedCurrentV5ContextAnalyzer(),
            dialogueGenerator: UnusedCurrentV5DialogueGenerator(),
            turnController: RejectingLegacyTurnController(),
            currentV5CoreTurnController: core,
            sessionStore: SessionStore(directory: directory),
            preparesContextDataAutomatically: false
        )
        model.session.protocolVersion = ReflectionSession.currentProtocolVersion
        model.session.protocolStage = .directReflection
        model.session.stage = .attributionReflection
        model.session.condition = .cardMediated
        model.session.semanticMemory.reflectionPhase = .tender
        model.session.semanticMemory.reflectionFrame = .init(
            mode: .tender,
            action: .connectCommonHumanity,
            evidenceBasis: [.init(source: .episode, content: "等待 bug 处理")],
            dimensions: [.commonHumanity],
            reflectionDelta: rejected,
            fierceEvidence: nil
        )

        model.draft = "我不是耐心，我其实很着急。"
        model.send()
        await waitUntilIdle(model)

        XCTAssertEqual(model.session.protocolStage, .directReflection)
        XCTAssertEqual(model.session.semanticMemory.reflectionPhase, .tender)
        XCTAssertEqual(model.session.semanticMemory.reflectionFrame, corrected)
        XCTAssertTrue(model.session.semanticMemory.invalidatedInterpretations.contains(rejected))
        XCTAssertFalse(
            model.session.messages.last(where: { $0.role == .assistant })?.content.contains("很有耐心")
                ?? true
        )
        let planCount = await core.planCount()
        let writeCount = await core.writeCount()
        XCTAssertEqual(planCount, 1)
        XCTAssertEqual(writeCount, 1)
    }

    func testLegacyReflectionFrameInfersCanonicalPhaseOnceAtDecode() throws {
        let encodedFrame = try JSONEncoder().encode(tenderFrame)
        let frameJSON = try XCTUnwrap(
            String(data: encodedFrame, encoding: .utf8)
        )
        let data = Data("""
        {"reflectionFrame":\(frameJSON)}
        """.utf8)

        let restored = try JSONDecoder().decode(TurnSemanticMemory.self, from: data)

        XCTAssertEqual(restored.reflectionPhase, .tender)
        let reencoded = try JSONEncoder().encode(restored)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        )
        XCTAssertEqual(object["reflectionPhase"] as? String, "tender")
    }

    private var completeEpisode: TurnEpisodeStructure {
        TurnEpisodeStructure(
            concreteFacts: ["昨天答应去接家人，但最后没有去"],
            behaviorEvidenceStatus: .present,
            behaviorEvidence: ["临时和朋友吃饭，也没有提前告诉家人"],
            eventProcessStatus: .present,
            eventProcess: ["原来的接人安排后来发生了变化"]
        )
    }

    private func contextualTrackingCue(
        confidence: TrackingInsightConfidence,
        metric: TrackingMetric = .sleepDuration
    ) -> TrackingCue {
        let end = Date()
        var insight = TrackingInsight(
            id: UUID(),
            metric: metric,
            observationWindow: DateInterval(
                start: end.addingTimeInterval(-604_800),
                end: end
            ),
            validSampleCount: 2,
            expectedSampleCount: 7,
            coverageDescription: "最近 7 晚中有 2 晚记录",
            neutralObservation: "最近有记录的夜晚睡眠中位数约 6.1 小时",
            baselineWindow: DateInterval(
                start: end.addingTimeInterval(-2_419_200),
                end: end.addingTimeInterval(-604_800)
            ),
            baselineDescription: "个人近期基线约 6.4 小时",
            absoluteDifference: -0.3,
            relativeDifference: -0.047,
            strength: .descriptiveOnly,
            confidence: confidence,
            limitations: ["最近窗口缺少 5 晚记录"],
            possibleConfounders: ["设备佩戴与同步情况"],
            suggestedReflectionQuestion: "",
            provenance: [],
            recentMedian: 6.1,
            baselineMedian: 6.4,
            medianAbsoluteDeviation: 0.4,
            interquartileRange: 0.6,
            longestConsecutiveRun: 1,
            userRelevance: .notReviewed
        )
        insight.recentDailyPoints = [
            TrackingDataPoint(
                date: end.addingTimeInterval(-86_400),
                value: 6.0,
                count: 4
            ),
            TrackingDataPoint(date: end, value: 6.2, count: 3),
        ]
        insight.factualBaselineMedian = 6.4
        insight.baselineObservedDays = 10
        insight.baselineExpectedDays = 28
        return TrackingCue(
            source: .healthSleep,
            observation: insight.neutralObservation,
            insight: insight
        )
    }

    private func selectedSleepTrackingDecision() -> CurrentV5ContextualTrackingDecision {
        CurrentV5ContextualTrackingDecision(
            metricEligibility: [
                .init(
                    profileID: "sleep",
                    metric: "sleepDuration",
                    status: .qualifies,
                    preferred: true
                ),
            ]
        )
    }

    private func rejectedSleepTrackingDecision() -> CurrentV5ContextualTrackingDecision {
        CurrentV5ContextualTrackingDecision(
            metricEligibility: [
                .init(
                    profileID: "sleep",
                    metric: "sleepDuration",
                    status: .doesNotQualify,
                    preferred: false
                ),
            ]
        )
    }

    private func currentCardReflectionSession() -> ReflectionSession {
        var session = ReflectionSession()
        session.protocolVersion = ReflectionSession.currentProtocolVersion
        session.protocolStage = .cardReflection
        session.stage = .cardInterpretation
        session.workflowPhase = .cardConnection
        session.condition = .cardMediated
        session.card = CardService().allCards[0]
        session.cardDisplayState = .displayed
        return session
    }

    private func decodePlannerOutput(_ json: String) throws -> CurrentV5PlannerOutput {
        try JSONDecoder().decode(CurrentV5PlannerOutput.self, from: Data(json.utf8))
    }

    private var tenderFrame: TurnReflectionFrame {
        TurnReflectionFrame(
            mode: .tender,
            action: .distinguishFactFromPrediction,
            evidenceBasis: [
                .init(source: .latestUserAnswer, content: "用户自己建立了画面与现实的联系"),
            ],
            dimensions: [.selfKindness, .mindfulness],
            reflectionDelta: "区分现实中的具体处理方式与对整个人的判断",
            fierceEvidence: nil
        )
    }

    private func waitUntilIdle(_ model: ReflectionViewModel) async {
        try? await Task.sleep(for: .milliseconds(40))
        for _ in 0..<160 {
            if !model.isTyping && !model.isStreamingResponse { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for current v5 core turn")
    }
}

private actor ScriptedCurrentV5CoreTurnController: CurrentV5CoreTurnControlling {
    private var plans: [CurrentV5PlannerOutput]
    private var replies: [String]
    private var requests: [CurrentV5TurnRequest] = []
    private var planCalls = 0
    private var writeCalls = 0

    init(plans: [CurrentV5PlannerOutput], replies: [String]) {
        self.plans = plans
        self.replies = replies
    }

    func plan(_ request: CurrentV5TurnRequest) async throws -> CurrentV5PlannerOutput {
        planCalls += 1
        requests.append(request)
        guard !plans.isEmpty else { throw CurrentV5TestError.exhausted }
        return plans.removeFirst()
    }

    func write(
        request: CurrentV5TurnRequest,
        directive: CurrentV5WriterDirective
    ) async throws -> CurrentV5WriterOutput {
        writeCalls += 1
        guard !replies.isEmpty else { throw CurrentV5TestError.exhausted }
        return .init(reply: replies.removeFirst())
    }

    func planCount() -> Int { planCalls }
    func writeCount() -> Int { writeCalls }
    func allowedOperationsForPlan(at index: Int) -> [PlannerSemanticOperation]? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index].allowedSemanticOperations
    }
    func correctionForPlan(at index: Int) -> CurrentV5PlannerCorrection? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index].correction
    }
    func request(at index: Int) -> CurrentV5TurnRequest? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index]
    }
}

private actor RejectingLegacyTurnController: ReflectionTurnControlling {
    private var calls = 0

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        calls += 1
        throw CurrentV5TestError.legacyPathReached
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        throw CurrentV5TestError.legacyPathReached
    }

    func planCount() -> Int { calls }
}

private struct UnusedCurrentV5ContextAnalyzer: ContextAnalyzing {
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage]
    ) async -> ContextAnalysis {
        XCTFail("Legacy ContextAnalyzer must not run in current v5 core")
        return ContextAnalysis()
    }
}

private struct UnusedCurrentV5DialogueGenerator: DialogueGenerating {
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
        throw CurrentV5TestError.legacyPathReached
    }
}

private enum CurrentV5TestError: Error {
    case exhausted
    case legacyPathReached
}
