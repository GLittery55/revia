import XCTest
@testable import BeyondComfort

/// Opt-in, live end-to-end evaluation of the production reflection path.
///
/// This is intentionally not a scripted Planner/Writer test. Each run uses
/// `RemoteReflectionTurnController`, wrapped only to record its typed requests and results. The
/// user simulator responds to `nextPrompt`, confirmation targets, and protocol stages—not to
/// hard-coded assistant wording. Consequently, the App and this runner execute the same Planner,
/// Writer, Critic, Swift protocol validation, local card action, stage transition, and atomic
/// memory commit implementation.
@MainActor
final class ReflectionLiveScenarioTests: XCTestCase {
    func testSharedRulesAreIdenticalOutsideTheReflectionMedium() {
        let controller = ReflectionProtocolController()
        let sharedStages: [ReflectionProtocolStage] = [
            .contextualDisclosure,
            .narrativeConfirmation,
            .optionalAction,
            .complete,
            .safetySupport,
        ]

        for stage in sharedStages {
            var card = ReflectionSession()
            card.protocolVersion = 2
            card.protocolStage = stage
            card.condition = .cardMediated
            card.trackingCues = Self.syntheticTrackingCues(profile: .reducedRecovery)

            var direct = card
            direct.condition = .directLLM

            let cardPermissions = controller.permissions(for: card)
            let directPermissions = controller.permissions(for: direct)

            XCTAssertEqual(
                cardPermissions.allowedReplyIntents,
                directPermissions.allowedReplyIntents,
                "\(stage.rawValue) must use the same reply rules in both conditions"
            )
            XCTAssertEqual(
                cardPermissions.allowedActions,
                directPermissions.allowedActions,
                "\(stage.rawValue) must use the same local actions in both conditions"
            )
        }
    }

    func testScenarioCatalogueAndReadableReportCoverRequiredDiagnostics() {
        XCTAssertGreaterThanOrEqual(Self.allScenarios.count, 12)
        XCTAssertEqual(
            Set(Self.allScenarios.map(\.trackingProfile)),
            Set(LiveTrackingProfile.allCases),
            "The full matrix must exercise every tracking evidence pattern."
        )
        XCTAssertTrue(Self.syntheticTrackingCues(profile: .noUsableData).isEmpty)
        XCTAssertTrue(Self.allScenarios.contains { $0.firstCardConnectionIsDifficult })
        XCTAssertTrue(Self.allScenarios.contains { $0.cardMappingResponse == .rejectOnce })
        XCTAssertTrue(Self.allScenarios.contains { $0.practiceResponse == .decline })

        let plan = LLMTurnResponsePlan(
            requestedStage: .contextualDisclosure,
            localAction: .none,
            memoryUpdate: .init(situationUnderstanding: "synthetic relationship"),
            nextPrompt: .openQuestion(
                purpose: "understand_impact",
                focus: "effect on daily life"
            ),
            replyIntent: .exploreContext,
            replyGuidance: "A semantic purpose that is independent of exact assistant wording."
        )
        let prompt = LiveNextPromptSnapshot(
            plan.nextPrompt ?? .none
        )
        let turn = LiveScenarioTurnReport(
            index: 1,
            userInput: "任意跨情境输入",
            assistantReplies: ["任意自然语言回复？"],
            stageAfterTurn: ReflectionProtocolStage.contextualDisclosure.rawValue,
            appStageAfterTurn: ReflectionState.eventDisclosure.rawValue,
            plannerAndWriterCalls: [
                .init(
                    sequence: 1,
                    kind: .planner,
                    trigger: LLMTurnTrigger.userMessage.rawValue,
                    inputStage: ReflectionProtocolStage.contextualDisclosure.rawValue,
                    protocolCorrection: nil,
                    plannerPlan: plan,
                    writerResponse: nil,
                    error: nil
                ),
                .init(
                    sequence: 2,
                    kind: .writer,
                    trigger: LLMTurnTrigger.userMessage.rawValue,
                    inputStage: ReflectionProtocolStage.contextualDisclosure.rawValue,
                    protocolCorrection: nil,
                    plannerPlan: plan,
                    writerResponse: .init(
                        realizedIntent: .exploreContext,
                        reply: "任意自然语言回复？"
                    ),
                    error: nil
                ),
            ],
            nextPrompt: prompt,
            pendingConfirmation: nil,
            studyEvents: [
                .init(
                    stage: ReflectionState.eventDisclosure.rawValue,
                    action: "protocol_transition_contextualDisclosure_to_contextualDisclosure_intent_exploreContext"
                ),
            ],
            retryAndErrorLog: ["coarse_protocol_regeneration_reason_invalid_next_prompt"],
            timedOut: false
        )
        let run = LiveScenarioRunReport(
            caseID: "report_contract",
            title: "报告合同",
            condition: ExperimentalCondition.directLLM.rawValue,
            completed: true,
            stopReason: "complete",
            finalStage: ReflectionProtocolStage.complete.rawValue,
            selectedCard: nil,
            trackingProfile: LiveTrackingProfile.stableRecords.rawValue,
            trackingExpectedBehavior: LiveTrackingProfile.stableRecords.expectedBehavior,
            initialTrackingCueIDs: ["synthetic_sleep"],
            initialTrackingCues: [],
            visitedProtocolStages: [
                ReflectionProtocolStage.contextualDisclosure.rawValue,
                ReflectionProtocolStage.directReflection.rawValue,
                ReflectionProtocolStage.narrativeConfirmation.rawValue,
                ReflectionProtocolStage.optionalAction.rawValue,
                ReflectionProtocolStage.complete.rawValue,
            ],
            finalNarrative: "synthetic final narrative",
            proposalKind: TurnPracticeKind.care.rawValue,
            practiceContent: "synthetic practice",
            turns: [turn]
        )
        let report = LiveScenarioMatrixReport(
            generatedAt: "2026-07-28T00:00:00Z",
            scenarioSet: "unit",
            usesProductionRemotePlannerAndWriter: true,
            cases: [
                .init(
                    id: "report_contract",
                    title: "报告合同",
                    initialUserInput: "任意跨情境输入"
                ),
            ],
            runs: [run],
            pairedComparisons: []
        )
        let markdown = LiveScenarioReportRenderer.markdown(report)

        [
            "用户输入",
            "Assistant 回复",
            "当前协议阶段",
            "intent=`exploreContext`",
            "nextPrompt",
            "待确认对象",
            "Writer",
            "阶段提交与事件",
            "重试与错误日志",
            "coarse_protocol_regeneration_reason_invalid_next_prompt",
        ].forEach {
            XCTAssertTrue(markdown.contains($0), "Markdown report is missing \($0)")
        }
        XCTAssertNoThrow(try JSONEncoder().encode(report))
    }

    func testSyntheticTrackingProfilesKeepDistinctEvidenceShapes() {
        let partial = Self.syntheticTrackingCues(profile: .partialAndMissing)
        XCTAssertFalse(partial.isEmpty)
        XCTAssertTrue(partial.allSatisfy {
            guard let insight = $0.insight else { return false }
            return insight.validSampleCount < insight.expectedSampleCount
                && insight.confidence == .low
                && !insight.limitations.isEmpty
        })

        let mixedText = Self.syntheticTrackingCues(profile: .mixedSignals)
            .map(\.observation)
            .joined(separator: " ")
        XCTAssertTrue(mixedText.contains("少约50分钟"))
        XCTAssertTrue(mixedText.contains("反而"))
        XCTAssertTrue(mixedText.contains("多约1600步"))

        let delayed = Self.syntheticTrackingCues(profile: .delayedSleepOnly)
        XCTAssertTrue(delayed.contains { $0.insight?.metric == .sleepTiming })
        XCTAssertTrue(delayed.contains {
            $0.insight?.metric == .sleepDuration && $0.observation.contains("接近")
        })

        let activityOnly = Self.syntheticTrackingCues(profile: .reducedActivityOnly)
        XCTAssertTrue(activityOnly.contains {
            $0.insight?.metric == .steps && $0.observation.contains("少约1800步")
        })
        XCTAssertTrue(activityOnly.contains {
            $0.insight?.metric == .sleepDuration && $0.observation.contains("接近")
        })

        let improvingText = Self.syntheticTrackingCues(profile: .improvingRecovery)
            .map(\.observation)
            .joined(separator: " ")
        XCTAssertTrue(improvingText.contains("多约40分钟"))
        XCTAssertTrue(improvingText.contains("早约25分钟"))
        XCTAssertTrue(Self.syntheticTrackingCues(profile: .noUsableData).isEmpty)
    }

    func testSemanticParticipantRevisesEachConfirmationOnlyOnce() throws {
        let mappingScenario = try XCTUnwrap(
            Self.allScenarios.first { $0.cardMappingResponse == .revise }
        )
        var mappingParticipant = SemanticScenarioParticipant(
            scenario: mappingScenario
        )
        var mappingSession = ReflectionSession()
        mappingSession.protocolStage = .cardReflection
        mappingSession.semanticMemory.nextPrompt = .confirmationRequest(
            target: .cardMapping,
            referenceID: "mapping-1"
        )

        let firstMappingReply = try XCTUnwrap(
            mappingParticipant.nextInput(
                session: mappingSession,
                latestPlan: nil
            )
        )
        let secondMappingReply = try XCTUnwrap(
            mappingParticipant.nextInput(
                session: mappingSession,
                latestPlan: nil
            )
        )
        XCTAssertTrue(firstMappingReply.contains("部分贴近"))
        XCTAssertTrue(secondMappingReply.contains("贴近我的理解，可以继续"))

        let practiceScenario = try XCTUnwrap(
            Self.allScenarios.first { $0.practiceResponse == .revise }
        )
        var practiceParticipant = SemanticScenarioParticipant(
            scenario: practiceScenario
        )
        var practiceSession = ReflectionSession()
        practiceSession.protocolStage = .optionalAction
        practiceSession.semanticMemory.nextPrompt = .confirmationRequest(
            target: .practice,
            referenceID: "practice-1"
        )

        let firstPracticeReply = try XCTUnwrap(
            practiceParticipant.nextInput(
                session: practiceSession,
                latestPlan: nil
            )
        )
        let secondPracticeReply = try XCTUnwrap(
            practiceParticipant.nextInput(
                session: practiceSession,
                latestPlan: nil
            )
        )
        XCTAssertTrue(firstPracticeReply.contains("缩小"))
        XCTAssertTrue(secondPracticeReply.contains("愿意采用"))
    }

    func testSemanticParticipantAnswersRealityClarificationAfterMapping() throws {
        let scenario = try XCTUnwrap(
            Self.allScenarios.first { !$0.candidDetails.isEmpty }
        )
        var participant = SemanticScenarioParticipant(scenario: scenario)
        var session = ReflectionSession()
        session.protocolStage = .cardReflection
        session.semanticMemory.cardRealityMapping = scenario.cardRealityConnection
        session.semanticMemory.nextPrompt = .openQuestion(
            purpose: "image_relation_developed",
            focus: "进一步澄清已经形成的现实关系"
        )
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardReflection,
            localAction: .none,
            memoryUpdate: .init(),
            nextPrompt: session.semanticMemory.nextPrompt,
            replyIntent: .developCardImage,
            replyGuidance: "继续澄清现实关系"
        )

        let reply = try XCTUnwrap(
            participant.nextInput(session: session, latestPlan: plan)
        )

        XCTAssertEqual(reply, scenario.candidDetails[0])
    }

    func testLivePairedScenarioMatrix() async throws {
#if LIVE_REFLECTION_SCENARIOS
#if REFLECTION_SCENARIO_ASSIGNED_ONLY
        let access: StudyAccess
        do {
            access = try await authenticateAssignedScenarioRunner()
        } catch {
            XCTFail(
                """
                自动案例无法登录后端：\(error.localizedDescription)
                请设置 REFLECTION_SCENARIO_USERNAME / REFLECTION_SCENARIO_PASSWORD，或先在同一
                iPhone 17 Pro 模拟器中登录正式 App。
                """
            )
            return
        }
        Self.printStudyAssignment(access, label: "assigned")
        attachStudyAssignment(access, label: "assigned")

        let scenarios = Self.selectedScenarios()
        var runs: [LiveScenarioRunReport] = []
        for scenario in scenarios {
            runs.append(
                await runScenario(
                    scenario,
                    expectedAccess: access,
                    maximumUserTurns: 22
                )
            )
        }
        let comparisons: [LivePairedComparison] = []
#else
        let scenarios = Self.selectedScenarios()
        var runs: [LiveScenarioRunReport] = []

        // A production login has one server-authoritative active condition. Use two dedicated
        // participant accounts and switch the shared cookie session between them. Running the
        // conditions concurrently would let one login overwrite the other.
        for expectedCondition in [ExperimentalCondition.cardMediated, .directLLM] {
            let access: StudyAccess
            do {
                access = try await authenticatePairedScenarioRunner(
                    expectedCondition: expectedCondition
                )
            } catch {
                XCTFail(
                    """
                    无法准备\(expectedCondition.usesCard ? "卡牌组" : "对照组")测试账号：\
                    \(error.localizedDescription)
                    配对测试需要两个当前处于不同实验条件的账号。请分别设置
                    REFLECTION_SCENARIO_CARD_USERNAME / REFLECTION_SCENARIO_CARD_PASSWORD
                    和 REFLECTION_SCENARIO_DIRECT_USERNAME / REFLECTION_SCENARIO_DIRECT_PASSWORD。
                    """
                )
                return
            }
            Self.printStudyAssignment(
                access,
                label: expectedCondition.usesCard ? "card-account" : "direct-account"
            )
            attachStudyAssignment(
                access,
                label: expectedCondition.usesCard ? "card-account" : "direct-account"
            )

            for scenario in scenarios {
                runs.append(
                    await runScenario(
                        scenario,
                        expectedAccess: access,
                        maximumUserTurns: 22
                    )
                )
            }
            try? await RemoteAPIService.shared.logout()
        }
        let comparisons = Self.comparePairedRuns(runs)
#endif

        let report = LiveScenarioMatrixReport(
            generatedAt: ISO8601DateFormatter().string(from: .now),
            scenarioSet: Self.scenarioSetName,
            usesProductionRemotePlannerAndWriter: true,
            cases: scenarios.map {
                .init(id: $0.id, title: $0.title, initialUserInput: $0.initialUserInput)
            },
            runs: runs,
            pairedComparisons: comparisons
        )
        try attach(report)

        let failures = runs.compactMap { run -> String? in
            run.completed ? nil : "\(run.caseID)/\(run.condition): \(run.stopReason)"
        }
        let comparisonFailures = comparisons.flatMap(\.violations)
        XCTAssertTrue(
            failures.isEmpty && comparisonFailures.isEmpty,
            (failures + comparisonFailures).joined(separator: "\n")
        )
#else
        throw XCTSkip(
            """
            Live scenario matrix is opt-in because it calls the configured production backend. \
            Run scripts/run-reflection-scenarios.sh to execute it and export Markdown/JSON reports.
            """
        )
#endif
    }

#if LIVE_REFLECTION_SCENARIOS
    private func authenticatePairedScenarioRunner(
        expectedCondition: ExperimentalCondition
    ) async throws -> StudyAccess {
        let environment = ProcessInfo.processInfo.environment
        let prefix = expectedCondition.usesCard
            ? "REFLECTION_SCENARIO_CARD"
            : "REFLECTION_SCENARIO_DIRECT"
        let username = environment["\(prefix)_USERNAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let password = environment["\(prefix)_PASSWORD"]
        guard let username, !username.isEmpty, let password, !password.isEmpty else {
            throw LiveScenarioAuthenticationError.missingCredentials(prefix: prefix)
        }

        try? await RemoteAPIService.shared.logout()
        _ = try await RemoteAPIService.shared.login(username: username, password: password)
        return try await verifiedStudyAccess(expectedCondition: expectedCondition)
    }

    private func authenticateAssignedScenarioRunner() async throws -> StudyAccess {
        let environment = ProcessInfo.processInfo.environment
        let username = environment["REFLECTION_SCENARIO_USERNAME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let password = environment["REFLECTION_SCENARIO_PASSWORD"]
        if let username, !username.isEmpty, let password, !password.isEmpty {
            try? await RemoteAPIService.shared.logout()
            _ = try await RemoteAPIService.shared.login(
                username: username,
                password: password
            )
        } else {
            _ = try await RemoteAPIService.shared.currentUser()
        }

        let access = try await RemoteAPIService.shared.currentStudyAccess()
        guard access.isAvailable, access.status == "active", access.condition != nil else {
            throw LiveScenarioAuthenticationError.inactiveStudyAccess
        }
        return access
    }

    private func verifiedStudyAccess(
        expectedCondition: ExperimentalCondition
    ) async throws -> StudyAccess {
        let access = try await RemoteAPIService.shared.currentStudyAccess()
        guard access.isAvailable, access.status == "active" else {
            throw LiveScenarioAuthenticationError.inactiveStudyAccess
        }
        guard access.condition == expectedCondition else {
            throw LiveScenarioAuthenticationError.conditionMismatch(
                expected: expectedCondition,
                actual: access.condition
            )
        }
        guard access.sequence != nil, access.period != nil else {
            throw LiveScenarioAuthenticationError.incompleteStudyAssignment
        }
        return access
    }

    private static func printStudyAssignment(
        _ access: StudyAccess,
        label: String
    ) {
        print(studyAssignmentDescription(access, label: label))
    }

    private func attachStudyAssignment(
        _ access: StudyAccess,
        label: String
    ) {
        let attachment = XCTAttachment(
            string: Self.studyAssignmentDescription(access, label: label)
        )
        attachment.name = "reflection-scenario-assignment-\(label).txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func studyAssignmentDescription(
        _ access: StudyAccess,
        label: String
    ) -> String {
        let condition = access.condition?.rawValue ?? "none"
        let displayName: String
        switch access.condition {
        case .cardMediated:
            displayName = "随机卡牌组"
        case .directLLM:
            displayName = "直接 LLM 对照组"
        case nil:
            displayName = "未分配"
        }
        return "REFLECTION_SCENARIO_ASSIGNMENT label=\(label) " +
            "condition=\(condition) condition_name=\(displayName) " +
            "sequence=\(access.sequence?.rawValue ?? "none") " +
            "period=\(access.period.map { String($0) } ?? "none")"
    }

    private func runScenario(
        _ scenario: LiveReflectionScenario,
        expectedAccess: StudyAccess,
        maximumUserTurns: Int
    ) async -> LiveScenarioRunReport {
        let condition = expectedAccess.condition ?? .cardMediated
        let recorder = RecordingReflectionTurnController(
            base: RemoteReflectionTurnController()
        )
        let model = ReflectionViewModel(
            turnController: recorder,
            preparesContextDataAutomatically: false
        )
        await model.configureStudy()

        guard model.canBeginStudy,
              model.session.condition == expectedAccess.condition,
              model.session.studySequence == expectedAccess.sequence,
              model.session.studyPeriod == expectedAccess.period else {
            return makeRunReport(
                scenario: scenario,
                condition: condition,
                model: model,
                turns: [],
                stopReason: "server_study_assignment_changed"
            )
        }

        model.session.trackingCues = Self.syntheticTrackingCues(
            profile: scenario.trackingProfile
        )

        var participant = SemanticScenarioParticipant(scenario: scenario)
        var turns: [LiveScenarioTurnReport] = []
        var messageCursor = model.session.messages.count
        var eventCursor = model.session.studyEvents.count
        var traceCursor = await recorder.count()

        model.begin()
        let openingSettled = await settle(model)
        turns.append(
            await captureTurn(
                index: 0,
                userInput: nil,
                model: model,
                recorder: recorder,
                messageCursor: &messageCursor,
                eventCursor: &eventCursor,
                traceCursor: &traceCursor,
                timedOut: !openingSettled
            )
        )

        guard openingSettled else {
            return makeRunReport(
                scenario: scenario,
                condition: condition,
                model: model,
                turns: turns,
                stopReason: "opening_turn_timeout"
            )
        }

        var nextInput: String? = scenario.initialUserInput
        var userTurn = 0
        while userTurn < maximumUserTurns,
              model.session.protocolStage != .complete,
              let input = nextInput {
            userTurn += 1
            model.draft = input
            model.send()
            var settled = await settle(model)

            // Drawing is a silent, local capability. The production UI reports successful image
            // display through this same callback; the test does so immediately after selection.
            if settled,
               model.session.cardDisplayState == .selected,
               let cardID = model.session.card?.id {
                model.cardDidDisplay(cardID: cardID)
                settled = await settle(model)
            }

            turns.append(
                await captureTurn(
                    index: userTurn,
                    userInput: input,
                    model: model,
                    recorder: recorder,
                    messageCursor: &messageCursor,
                    eventCursor: &eventCursor,
                    traceCursor: &traceCursor,
                    timedOut: !settled
                )
            )

            guard settled else { break }
            let latestPlan = await recorder.latestSuccessfulPlan()
            nextInput = participant.nextInput(
                session: model.session,
                latestPlan: latestPlan
            )
        }

        let stopReason: String
        if model.session.protocolStage == .complete {
            stopReason = "complete"
        } else if userTurn >= maximumUserTurns {
            stopReason = "maximum_user_turns_reached"
        } else if nextInput == nil {
            stopReason = "participant_had_no_legal_response"
        } else {
            stopReason = "turn_timeout"
        }

        return makeRunReport(
            scenario: scenario,
            condition: condition,
            model: model,
            turns: turns,
            stopReason: stopReason
        )
    }

    private func settle(
        _ model: ReflectionViewModel,
        timeout: Duration = .seconds(360)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        // `begin()` and `send()` enqueue the response task. Give it one MainActor turn to start.
        try? await Task.sleep(for: .milliseconds(80))
        while clock.now < deadline {
            if !model.isTyping && !model.isStreamingResponse { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func captureTurn(
        index: Int,
        userInput: String?,
        model: ReflectionViewModel,
        recorder: RecordingReflectionTurnController,
        messageCursor: inout Int,
        eventCursor: inout Int,
        traceCursor: inout Int,
        timedOut: Bool
    ) async -> LiveScenarioTurnReport {
        let newMessages = Array(model.session.messages.dropFirst(messageCursor))
        let newEvents = Array(model.session.studyEvents.dropFirst(eventCursor))
        let traces = await recorder.traces(since: traceCursor)
        messageCursor = model.session.messages.count
        eventCursor = model.session.studyEvents.count
        traceCursor += traces.count

        let errors = traces.compactMap(\.error)
            + newEvents.map(\.action).filter(Self.isRetryOrErrorEvent)
        let prompt = model.session.semanticMemory.nextPrompt

        return LiveScenarioTurnReport(
            index: index,
            userInput: userInput,
            assistantReplies: newMessages
                .filter { $0.role == .assistant }
                .map(\.content),
            stageAfterTurn: model.session.protocolStage.rawValue,
            appStageAfterTurn: model.session.stage.rawValue,
            plannerAndWriterCalls: traces,
            nextPrompt: prompt.map(LiveNextPromptSnapshot.init),
            pendingConfirmation: prompt?.kind == .confirmationRequest
                ? prompt?.target?.rawValue
                : nil,
            studyEvents: newEvents.map {
                LiveStudyEventSnapshot(
                    stage: $0.stage.rawValue,
                    action: $0.action
                )
            },
            retryAndErrorLog: errors,
            timedOut: timedOut
        )
    }

    private func makeRunReport(
        scenario: LiveReflectionScenario,
        condition: ExperimentalCondition,
        model: ReflectionViewModel,
        turns: [LiveScenarioTurnReport],
        stopReason: String
    ) -> LiveScenarioRunReport {
        let events = model.session.studyEvents.map(\.action)
        return LiveScenarioRunReport(
            caseID: scenario.id,
            title: scenario.title,
            condition: condition.rawValue,
            completed: model.session.protocolStage == .complete,
            stopReason: stopReason,
            finalStage: model.session.protocolStage.rawValue,
            selectedCard: model.session.card?.title,
            trackingProfile: scenario.trackingProfile.rawValue,
            trackingExpectedBehavior: scenario.trackingProfile.expectedBehavior,
            initialTrackingCueIDs: Self.syntheticTrackingCues(
                profile: scenario.trackingProfile
            ).map(\.id),
            initialTrackingCues: Self.syntheticTrackingCues(
                profile: scenario.trackingProfile
            ).map(LiveTrackingCueSnapshot.init),
            visitedProtocolStages: Self.visitedProtocolStages(from: events),
            finalNarrative: model.session.semanticMemory.finalNarrative,
            proposalKind: model.session.semanticMemory.practiceTransition?.proposal?.kind.rawValue,
            practiceContent: model.session.semanticMemory.practiceTransition?.proposal?.content,
            turns: turns
        )
    }

    private func attach(_ report: LiveScenarioMatrixReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(report)
        let markdown = LiveScenarioReportRenderer.markdown(report)

        let jsonAttachment = XCTAttachment(
            data: json,
            uniformTypeIdentifier: "public.json"
        )
        jsonAttachment.name = "reflection-scenario-report.json"
        jsonAttachment.lifetime = .keepAlways
        add(jsonAttachment)

        let markdownAttachment = XCTAttachment(
            data: Data(markdown.utf8),
            uniformTypeIdentifier: "net.daringfireball.markdown"
        )
        markdownAttachment.name = "reflection-scenario-report.md"
        markdownAttachment.lifetime = .keepAlways
        add(markdownAttachment)

        let completed = report.runs.filter(\.completed).count
        print(
            "REFLECTION_SCENARIO_REPORT completed=\(completed)/\(report.runs.count) " +
            "set=\(report.scenarioSet)"
        )
    }
#endif
}

// MARK: - Scenario catalogue

private enum LiveScenarioAuthenticationError: LocalizedError {
    case missingCredentials(prefix: String)
    case inactiveStudyAccess
    case incompleteStudyAssignment
    case conditionMismatch(
        expected: ExperimentalCondition,
        actual: ExperimentalCondition?
    )

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let prefix):
            return "缺少 \(prefix)_USERNAME 或 \(prefix)_PASSWORD"
        case .inactiveStudyAccess:
            return "账号当前没有处于 active 状态的研究条件"
        case .incompleteStudyAssignment:
            return "服务器分组缺少 sequence 或 period"
        case .conditionMismatch(let expected, let actual):
            return "账号当前条件为 \(actual?.rawValue ?? "none")，预期为 \(expected.rawValue)"
        }
    }
}

private enum LiveTrackingProfile: String, Codable, CaseIterable, Sendable {
    case reducedRecovery
    case denseSchedule
    case stableRecords
    case partialAndMissing
    case mixedSignals
    case delayedSleepOnly
    case reducedActivityOnly
    case improvingRecovery
    case noUsableData

    var expectedBehavior: String {
        switch self {
        case .reducedRecovery:
            return "多项同方向变化可以形成一个可拒绝的生活状态候选，但仍不能成为原因或责任证据。"
        case .denseSchedule:
            return "突出日程增加；身体数据只有轻微变化，不能把全部指标统一解释成疲惫或压力。"
        case .stableRecords:
            return "明确没有明显记录变化，不得为了推进流程硬找 tracking 原因。"
        case .partialAndMissing:
            return "说明覆盖不足并保留不确定性，不得把已记录的少数日期扩展到整个窗口。"
        case .mixedSignals:
            return "分别保留方向不一致的变化，不得拼成单一的压力、疲惫或恢复结论。"
        case .delayedSleepOnly:
            return "只讨论作息时间推后；不得改写为睡眠总量不足。"
        case .reducedActivityOnly:
            return "只把活动减少作为待确认背景；不得同时虚构睡眠或日程异常。"
        case .improvingRecovery:
            return "承认记录改善与现实困难可以同时存在；不得用改善数据否定用户痛苦。"
        case .noUsableData:
            return "跳过 tracking 展示与解释，直接继续基于 self-disclosure 对话。"
        }
    }
}

private enum LiveCardMappingResponse: String, Codable, Sendable {
    case accept
    case revise
    case rejectOnce
}

private enum LivePracticeResponse: String, Codable, Sendable {
    case accept
    case revise
    case decline
}

private struct LiveReflectionScenario: Codable, Sendable {
    let id: String
    let title: String
    let initialUserInput: String
    let disclosureDetails: [String]
    let trackingProfile: LiveTrackingProfile
    let trackingResponse: String
    let candidDetails: [String]
    let cardRealityConnection: String
    let firstCardConnectionIsDifficult: Bool
    let cardMappingResponse: LiveCardMappingResponse
    let finalNarrativeCorrection: String?
    let practiceResponse: LivePracticeResponse
}

private extension ReflectionLiveScenarioTests {
    static var allScenarios: [LiveReflectionScenario] {
        [
            .init(
                id: "research_failure_self_doubt",
                title: "反复实验失败与整体能力怀疑",
                initialUserInput: "实验又失败了，我开始怀疑自己是不是根本不适合做研究。",
                disclosureDetails: [
                    "我担心论文发不出去，也担心不能按时毕业。",
                    "我已经反复调整了很多次，持续没有结果让我很挫败，也越来越没精神。",
                    "具体来说，当前方法还没有奏效，但我把它扩大成了对整体研究能力的判断。",
                ],
                trackingProfile: .reducedRecovery,
                trackingResponse: "睡得更短和活动减少与我最近没精神有一点关系，但不能说明实验为什么失败。",
                candidDetails: [
                    "需要面对的是继续用同一套调整方法却没有重新检查假设，但这不等于我整体没有能力。",
                    "我现在能做的是先记录哪组调整真正改变了结果，再决定下一次实验。",
                ],
                cardRealityConnection: "画面里的关系让我想到，实验整体还没有解决，但其中一个方法或判断可以先单独检查。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "task_avoidance_deadline",
                title: "替代任务、拖延与临近截止",
                initialUserInput: "论文还有两个星期截止，我已经两天没写，却一直在整理不重要的文件。",
                disclosureDetails: [
                    "我打开正文看几行就觉得头大，然后转去整理文件，短时间会轻松一点。",
                    "我害怕写得很差最后被拒，所以迟迟不愿意写第一段。",
                    "整理文件确实不是当前必须完成的事，它正在让真正重要的分析继续停着。",
                ],
                trackingProfile: .delayedSleepOnly,
                trackingResponse: "最近确实睡得更晚，但总时长没有明显减少；它可能影响开始工作的节奏，却不能解释我为什么转去整理文件。",
                candidDetails: [
                    "压力和害怕被拒值得理解，但我也需要承认自己在用次要任务避开正文。",
                    "一个可控部分是只处理一个结果变量，不要求马上写出完整章节。",
                ],
                cardRealityConnection: "画面中的停顿或选择，让我想到自己在主要任务和替代任务之间反复转开。",
                firstCardConnectionIsDifficult: true,
                cardMappingResponse: .revise,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "friend_conflict_repair",
                title: "朋友冲突、伤人表达与修复",
                initialUserInput: "我和最好的朋友吵架时说了很重的话，现在非常后悔。",
                disclosureDetails: [
                    "我说他根本不在乎我的感受，他当时愣住了，后来我们一直没有说话。",
                    "我很生气，但真正想表达的是自己没有被理解；现在担心会失去这段关系。",
                    "生气能解释当时的状态，却不能取消那句话给对方造成的伤害。",
                ],
                trackingProfile: .reducedRecovery,
                trackingResponse: "最近睡得更短、更晚，活动也少了，和争吵后一直消耗精力有些贴近，但不能替我判断冲突责任。",
                candidDetails: [
                    "我需要承担的是伤人的说法，而不是把自己定义成一个糟糕的朋友。",
                    "如果联系是合适的，我愿意先为具体那句话道歉，再说明真正的感受。",
                ],
                cardRealityConnection: "画面中的距离和回应让我想到，我们现在既需要冷静，也有一段具体沟通仍未完成。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "caregiving_irritability",
                title: "家庭照护过载与不耐烦",
                initialUserInput: "最近一直处理家人住院和报销，昨晚妈妈又问已经解释过的问题，我语气特别冲。",
                disclosureDetails: [
                    "这些事情连续堆在一起，我已经很累，但看到她愣住时也意识到自己的语气伤到了她。",
                    "我需要有人分担，也希望同一个问题不用反复由我一个人解释。",
                    "疲惫和负担需要被看见，但昨晚怎样回应仍然是我能回看的具体部分。",
                ],
                trackingProfile: .reducedRecovery,
                trackingResponse: "最近睡得少、走动也少，和我一直没有休息过来很贴近，也可能让我更难保持耐心。",
                candidDetails: [
                    "我可以为语气道歉，同时说明自己已经接近承受上限，而不是继续默默扛下所有手续。",
                    "更需要保护的边界是把报销任务分给其他家人，并把常见问题写下来。",
                ],
                cardRealityConnection: "画面里并非所有部分都能马上改变，但有一个局部可以先处理，这让我想到先处理昨晚的语气和分担方式。",
                firstCardConnectionIsDifficult: true,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .revise
            ),
            .init(
                id: "work_credit_boundary",
                title: "成果被归给他人与现场愣住",
                initialUserInput: "同事在汇报里把我的成果说成了他的，我当时愣住没有开口，后来很生气。",
                disclosureDetails: [
                    "事情发生得很突然，我一时不知道怎样插话，之后又责怪自己总是只会忍着。",
                    "真正受伤的是贡献没有被承认，也担心以后继续出现同样的情况。",
                    "当时没开口不等于我已经决定忍下去，现在仍然可以用事实把贡献说清楚。",
                ],
                trackingProfile: .stableRecords,
                trackingResponse: "这些记录最近基本稳定，我认为和当时没开口没有明显关系。",
                candidDetails: [
                    "需要保护的是自己的贡献和边界，能改进的是提前准备一句现场澄清的话。",
                    "我可以整理时间线，区分自己完成的部分和共同完成的部分。",
                ],
                cardRealityConnection: "画面里的位置或边界关系让我想到，自己的贡献需要被放回正确的位置。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .revise,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "breakup_grief_uncertainty",
                title: "分手后的失落、后悔与不确定责任",
                initialUserInput: "三年的关系刚结束一周，我很伤心，也一直觉得是不是自己不够体贴。",
                disclosureDetails: [
                    "异地期间我们经常争吵，有时我生气后就停止沟通，这些是我后悔的具体行为。",
                    "关系结束的原因我不能完全确定，也不能只凭现在的后悔判断全部都是我的责任。",
                    "目前我还不适合马上联系对方，我更需要先分清失去、后悔和能够确认的行为。",
                ],
                trackingProfile: .partialAndMissing,
                trackingResponse: "有限的几晚记录和反复回想有些贴近，但覆盖不足，我不能据此判断整段时间或关系结束的原因。",
                candidDetails: [
                    "我愿意面对自己停止沟通的部分，但对方的需要和关系结束的全部原因仍有未知。",
                    "现在不需要立刻修复关系，可以先写清楚未来更早表达的真实需要。",
                ],
                cardRealityConnection: "画面中没有完成或尚未打开的关系，让我想到有些感受没说出来，但不代表现在必须重新联系。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .rejectOnce,
                finalNarrativeCorrection: "请保留我现在不准备联系对方这一点，不要暗示复合或立即修复。",
                practiceResponse: .decline
            ),
            .init(
                id: "job_rejection_shame",
                title: "求职被拒与羞愧",
                initialUserInput: "连续几次面试被拒，我开始觉得自己是不是哪里都不够好。",
                disclosureDetails: [
                    "我很失落，也不太敢告诉朋友，担心他们觉得我能力差。",
                    "目前能确认的是几次岗位没有录用我，但我不知道每次拒绝的具体原因。",
                    "我需要承认求职消耗很大，同时把岗位反馈和对整个人的评价分开。",
                ],
                trackingProfile: .improvingRecovery,
                trackingResponse: "最近睡眠和活动记录反而有所改善，但求职被拒带来的失落仍然存在；改善的数据不能否定我的感受，也不能解释招聘结果。",
                candidDetails: [
                    "可以检查的是岗位匹配和面试回答，不能确认的是招聘方所有判断。",
                    "我想先向可信任的人说出失落，而不是把拒绝藏起来。",
                ],
                cardRealityConnection: "画面里可见与不可见的部分让我想到，拒绝结果是事实，但对我整体能力的推断并不完整。",
                firstCardConnectionIsDifficult: true,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .revise
            ),
            .init(
                id: "chronic_illness_capacity",
                title: "长期身体状况与能力边界",
                initialUserInput: "最近治疗和复诊占了很多时间，我工作进度变慢，开始觉得自己拖累了团队。",
                disclosureDetails: [
                    "我会疲惫，也担心同事需要替我补工作，但团队并没有直接说我是负担。",
                    "治疗安排是真实限制，进度影响也需要沟通，二者不能被压成对人格的判断。",
                    "我希望既不隐瞒当前容量，也不需要透露所有医疗细节。",
                ],
                trackingProfile: .partialAndMissing,
                trackingResponse: "部分记录缺失，睡眠变化与治疗后的疲惫有一点贴近，但不能用来判断我的工作责任。",
                candidDetails: [
                    "需要保护的是医疗隐私和现实承受能力，需要面对的是尽早说明可交付范围。",
                    "我能提出一次任务优先级和截止时间调整，而不是独自补完所有进度。",
                ],
                cardRealityConnection: "画面里的承载、空间或帮助关系让我想到，责任需要按现在的容量重新分配。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "financial_uncertainty",
                title: "经济压力、选择与不确定性",
                initialUserInput: "最近支出突然增加，我很怕自己做错任何决定，连必要的花费也一直拖着。",
                disclosureDetails: [
                    "我担心钱不够，也会把一次消费选择想成可能造成很严重的后果。",
                    "有些支出确实可以延后，有些医疗和住房费用不能一直不处理。",
                    "我需要更多确定的信息，而不是只靠焦虑决定全部花费。",
                ],
                trackingProfile: .denseSchedule,
                trackingResponse: "日程更密和走动减少可能说明最近办事很多，但不能证明我的财务判断对不对。",
                candidDetails: [
                    "可控部分是列出必要、可延后和仍需询价的项目，不要求一次解决长期经济问题。",
                    "如果信息仍不足，我可以向专业或可信任的人确认，而不是继续完全不决定。",
                ],
                cardRealityConnection: "画面里的岔口、未知或可移动部分让我想到，需要先区分现在必须决定和可以保留余地的部分。",
                firstCardConnectionIsDifficult: true,
                cardMappingResponse: .revise,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "relocation_isolation",
                title: "搬家后的孤立与求助",
                initialUserInput: "搬到新城市以后我一直适应不好，遇到事情也不愿意麻烦别人，感觉越来越孤单。",
                disclosureDetails: [
                    "我担心求助会欠人情，也怕别人觉得我连小事都处理不了。",
                    "保持独立对我很重要，但现在完全不求助已经让我更难建立联系。",
                    "我并不是没有任何资源，只是不知道怎样提出一个边界清楚的小请求。",
                ],
                trackingProfile: .noUsableData,
                trackingResponse: "当前没有足够记录可以判断背景，先只根据我说的新环境和联系减少继续理解。",
                candidDetails: [
                    "需要照顾的是初到陌生环境的不安，需要改变的是把所有求助都等同于给别人添麻烦。",
                    "我愿意先提出一个具体、容易拒绝的请求，同时接受对方可能没空。",
                ],
                cardRealityConnection: "画面中的距离、灯光或递出的关系让我想到，联系可以保留边界，不必等于失去自主。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "missed_commitment_relationship",
                title: "答应额外任务、失约与延迟沟通",
                initialUserInput: "我答应帮同学处理数据，明知时间可能不够，最后没按时完成，也一直不敢回复催促。",
                disclosureDetails: [
                    "我怕拒绝会影响关系，所以先答应了；后来越愧疚越不知道怎样回复。",
                    "没有按时交付和没有及时说明确实影响了对方，这比说自己整个人不可靠更具体。",
                    "关系担忧能解释犹豫，但不能取消我需要说明进度和调整承诺的责任。",
                ],
                trackingProfile: .reducedActivityOnly,
                trackingResponse: "最近只有走动明显减少，睡眠和日程基本稳定；活动变化可能与伏案处理任务有关，但不能直接解释失约。",
                candidDetails: [
                    "当前优先是修复：承认延误、说明进度，并给出可行的新时间或缩小范围。",
                    "以后收到额外请求时，我需要先确认任务量和时间再答应。",
                ],
                cardRealityConnection: "画面里的未知内容和是否接下的关系，让我想到应该先了解任务范围，再决定能否承担。",
                firstCardConnectionIsDifficult: false,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
            .init(
                id: "public_criticism_mixed_responsibility",
                title: "公开批评、准备不足与整体否定",
                initialUserInput: "组会上导师批评我回答得很差，我很羞愧，甚至觉得自己不适合科研。",
                disclosureDetails: [
                    "当时脸发热、不敢看别人，也担心大家会认为我能力不行。",
                    "那篇论文我确实没有理解充分，回答问题时也没有说明自己不确定的地方。",
                    "这次准备和回答存在不足，但一次表现不能直接证明整体研究能力。",
                ],
                trackingProfile: .mixedSignals,
                trackingResponse: "最近睡得少一些，但活动量反而增加，不能把这些方向不同的变化合成一个统一的疲惫结论；它们也不能说明回答不好的原因。",
                candidDetails: [
                    "可以改进的是提前梳理论文核心问题，并在不知道时更清楚地说明。",
                    "导师公开表达的方式也让我难受，这部分不需要被解释成全部是我的问题。",
                ],
                cardRealityConnection: "画面中环境限制与仍可处理的部分，让我想到要区分公开评价带来的冲击和具体准备不足。",
                firstCardConnectionIsDifficult: true,
                cardMappingResponse: .accept,
                finalNarrativeCorrection: nil,
                practiceResponse: .accept
            ),
        ]
    }

    static var scenarioSetName: String {
#if REFLECTION_SCENARIO_SMOKE
        "smoke"
#elseif REFLECTION_SCENARIO_STANDARD
        "standard"
#else
        "full"
#endif
    }

    static func selectedScenarios() -> [LiveReflectionScenario] {
#if REFLECTION_SCENARIO_SMOKE
        Array(allScenarios.prefix(2))
#elseif REFLECTION_SCENARIO_STANDARD
        let ids = [
            "research_failure_self_doubt",
            "task_avoidance_deadline",
            "work_credit_boundary",
            "job_rejection_shame",
            "financial_uncertainty",
            "public_criticism_mixed_responsibility",
        ]
        return ids.compactMap { id in allScenarios.first { $0.id == id } }
#else
        allScenarios
#endif
    }
}

// MARK: - Semantic participant

private struct SemanticScenarioParticipant {
    let scenario: LiveReflectionScenario
    private var disclosureIndex = 0
    private var candidIndex = 0
    private var usedCardDifficulty = false
    private var usedCardMappingRevision = false
    private var usedCardMappingRejection = false
    private var usedNarrativeCorrection = false
    private var usedPracticeRevision = false

    init(scenario: LiveReflectionScenario) {
        self.scenario = scenario
    }

    mutating func nextInput(
        session: ReflectionSession,
        latestPlan: LLMTurnResponsePlan?
    ) -> String? {
        guard session.protocolStage != .complete else { return nil }
        if let prompt = session.semanticMemory.nextPrompt {
            switch prompt.kind {
            case .confirmationRequest:
                return response(to: prompt.target, session: session)
            case .openQuestion:
                return openResponse(
                    session: session,
                    intent: latestPlan?.replyIntent,
                    prompt: prompt
                )
            case .none:
                break
            }
        }
        return openResponse(
            session: session,
            intent: latestPlan?.replyIntent,
            prompt: nil
        )
    }

    private mutating func response(
        to target: TurnConfirmationTarget?,
        session: ReflectionSession
    ) -> String {
        switch target {
        case .trackingRelationship:
            return scenario.trackingResponse
        case .cardConsent:
            return "我愿意抽一张随机卡片。"
        case .cardRealityConnection:
            return "这个候选联系可以作为我对画面和这件事的理解。"
        case .cardMapping:
            switch scenario.cardMappingResponse {
            case .accept:
                return "这个画面和现实之间的联系贴近我的理解，可以继续。"
            case .revise:
                if !usedCardMappingRevision {
                    usedCardMappingRevision = true
                    return "部分贴近，但我更想强调：\(scenario.cardRealityConnection)"
                }
                return "修正后的画面和现实联系贴近我的理解，可以继续。"
            case .rejectOnce:
                if !usedCardMappingRejection {
                    usedCardMappingRejection = true
                    return "这个候选联系不太贴近，请不要把它当成我的理解；可以回到已经确认的现实情况。"
                }
                return "修正后的理解贴近，可以继续。"
            }
        case .finalNarrative:
            if let correction = scenario.finalNarrativeCorrection, !usedNarrativeCorrection {
                usedNarrativeCorrection = true
                return correction
            }
            return "这段叙事准确，可以继续。"
        case .practice:
            switch scenario.practiceResponse {
            case .accept:
                return "这个建议具体而且负担不大，我愿意采用。"
            case .revise:
                if !usedPracticeRevision {
                    usedPracticeRevision = true
                    return "方向合适，但请把它缩小成今天十分钟内可以完成的一步。"
                }
                return "缩小后的建议适合我，我愿意采用。"
            case .decline:
                return "这次我不想设置行动，先保留已经形成的理解。"
            }
        case .none:
            return fallback(for: session.protocolStage)
        }
    }

    private mutating func openResponse(
        session: ReflectionSession,
        intent: TurnReplyIntent?,
        prompt: TurnNextPrompt?
    ) -> String {
        switch session.protocolStage {
        case .contextualDisclosure:
            if disclosureIndex < scenario.disclosureDetails.count {
                defer { disclosureIndex += 1 }
                return scenario.disclosureDetails[disclosureIndex]
            }
            return "目前没有更多需要补充的内容，可以先根据已经说清楚的部分整理。"

        case .cardConsent:
            return "我愿意抽一张随机卡片。"

        case .cardReflection:
            let purpose = prompt?.purpose?.lowercased() ?? ""
            switch intent {
            case .inviteCardObservation:
                return cardObservation(session.card)
            case .developCardImage:
                // Once the Planner has already stored a reality mapping, a follow-up open
                // question is about clarifying that real relationship—not an invitation for the
                // synthetic participant to repeat the same visual sentence.
                if session.semanticMemory.cardRealityMapping?.isEmpty == false,
                   purpose.contains("relation") || purpose.contains("mapping") {
                    return nextCandidAnswer()
                }
                return cardDevelopment(session.card)
            case .inviteCardConnection:
                if scenario.firstCardConnectionIsDifficult, !usedCardDifficulty {
                    usedCardDifficulty = true
                    return "我一下子有点想不到它和现实有什么联系。"
                }
                return cardConnection(session.card)
            case .directCandidReflection:
                return nextCandidAnswer()
            case .presentCardReading:
                return "这个方向可以作为候选理解，但请让我确认或修改。"
            default:
                return cardConnection(session.card)
            }

        case .directReflection:
            return nextCandidAnswer()

        case .narrativeConfirmation:
            return response(to: .finalNarrative, session: session)
        case .optionalAction:
            return response(to: .practice, session: session)
        case .complete, .safetySupport:
            return "我明白了。"
        }
    }

    private mutating func nextCandidAnswer() -> String {
        if candidIndex < scenario.candidDetails.count {
            defer { candidIndex += 1 }
            return scenario.candidDetails[candidIndex]
        }
        return "目前责任、限制和可控部分已经分得比较清楚，可以整理成一段叙事。"
    }

    private func cardObservation(_ card: ReflectionCard?) -> String {
        let anchors = cardAnchors(card)
        guard !anchors.isEmpty else {
            return "我先注意到画面里几个物体的位置和它们之间的距离。"
        }
        return "我先注意到画面里的\(anchors.joined(separator: "、"))，它们的位置像是在形成某种关系。"
    }

    private func cardDevelopment(_ card: ReflectionCard?) -> String {
        let anchors = cardAnchors(card)
        if anchors.count >= 2 {
            return "我觉得接下来\(anchors[0])的变化可能会影响\(anchors[1])，画面里的关系不会一下子全部改变。"
        }
        return "我觉得接下来画面中的人会先观察眼前的部分，再决定怎样行动。"
    }

    private func cardConnection(_ card: ReflectionCard?) -> String {
        let anchors = cardAnchors(card)
        let imageClause: String
        if anchors.count >= 2 {
            imageClause = "画面里\(anchors[0])和\(anchors[1])之间的关系"
        } else {
            imageClause = "画面里一个部分影响另一个部分的关系"
        }
        return "\(imageClause)让我想到现实中的这一点：\(scenario.cardRealityConnection)"
    }

    private func cardAnchors(_ card: ReflectionCard?) -> [String] {
        guard let guidance = card?.visualGuidance else { return [] }
        let scaffoldAnchors = guidance.visualScaffolds
            .first?
            .requiredAnchorGroups
            .compactMap(\.first) ?? []
        var values: [String] = []
        for value in scaffoldAnchors + guidance.visualAnchors.prefix(3) where !values.contains(value) {
            values.append(value)
        }
        return Array(values.prefix(3))
    }

    private mutating func fallback(for stage: ReflectionProtocolStage) -> String {
        switch stage {
        case .contextualDisclosure:
            return "可以继续理解我刚才说的经历，而不是根据固定问题猜测。"
        case .cardConsent:
            return "我愿意抽卡。"
        case .cardReflection:
            return scenario.cardRealityConnection
        case .directReflection:
            return nextCandidAnswer()
        case .narrativeConfirmation:
            return "这段叙事准确。"
        case .optionalAction:
            return "请给出一个具体、低负担、可以拒绝的建议。"
        case .complete, .safetySupport:
            return "我明白了。"
        }
    }
}

// MARK: - Transparent Planner/Writer recorder

private struct LiveModelCallTrace: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case planner
        case writer
    }

    let sequence: Int
    let kind: Kind
    let trigger: String
    let inputStage: String
    let protocolCorrection: String?
    let plannerPlan: LLMTurnResponsePlan?
    let writerResponse: LLMTurnWriterResponse?
    let error: String?
}

private actor RecordingReflectionTurnController: ReflectionTurnControlling {
    private let base: any ReflectionTurnControlling
    private var values: [LiveModelCallTrace] = []

    init(base: any ReflectionTurnControlling) {
        self.base = base
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        do {
            let plan = try await base.plan(to: request)
            values.append(
                LiveModelCallTrace(
                    sequence: values.count + 1,
                    kind: .planner,
                    trigger: request.trigger.rawValue,
                    inputStage: request.protocolStage.rawValue,
                    protocolCorrection: request.protocolCorrection,
                    plannerPlan: plan,
                    writerResponse: nil,
                    error: nil
                )
            )
            return plan
        } catch {
            values.append(
                LiveModelCallTrace(
                    sequence: values.count + 1,
                    kind: .planner,
                    trigger: request.trigger.rawValue,
                    inputStage: request.protocolStage.rawValue,
                    protocolCorrection: request.protocolCorrection,
                    plannerPlan: nil,
                    writerResponse: nil,
                    error: String(reflecting: error)
                )
            )
            throw error
        }
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        do {
            let response = try await base.write(
                request: request,
                validatedPlan: validatedPlan
            )
            values.append(
                LiveModelCallTrace(
                    sequence: values.count + 1,
                    kind: .writer,
                    trigger: request.trigger.rawValue,
                    inputStage: request.protocolStage.rawValue,
                    protocolCorrection: request.protocolCorrection,
                    plannerPlan: validatedPlan,
                    writerResponse: response,
                    error: nil
                )
            )
            return response
        } catch {
            values.append(
                LiveModelCallTrace(
                    sequence: values.count + 1,
                    kind: .writer,
                    trigger: request.trigger.rawValue,
                    inputStage: request.protocolStage.rawValue,
                    protocolCorrection: request.protocolCorrection,
                    plannerPlan: validatedPlan,
                    writerResponse: nil,
                    error: String(reflecting: error)
                )
            )
            throw error
        }
    }

    func count() -> Int { values.count }

    func traces(since index: Int) -> [LiveModelCallTrace] {
        guard index < values.count else { return [] }
        return Array(values.dropFirst(index))
    }

    func latestSuccessfulPlan() -> LLMTurnResponsePlan? {
        values.reversed().compactMap(\.plannerPlan).first
    }
}

// MARK: - Reports

private struct LiveScenarioCaseSummary: Codable {
    let id: String
    let title: String
    let initialUserInput: String
}

private struct LiveNextPromptSnapshot: Codable {
    let kind: String
    let purpose: String?
    let focus: String?
    let target: String?
    let referenceID: String?

    init(_ prompt: TurnNextPrompt) {
        kind = prompt.kind.rawValue
        purpose = prompt.purpose
        focus = prompt.focus
        target = prompt.target?.rawValue
        referenceID = prompt.referenceID
    }
}

private struct LiveStudyEventSnapshot: Codable {
    let stage: String
    let action: String
}

private struct LiveScenarioTurnReport: Codable {
    let index: Int
    let userInput: String?
    let assistantReplies: [String]
    let stageAfterTurn: String
    let appStageAfterTurn: String
    let plannerAndWriterCalls: [LiveModelCallTrace]
    let nextPrompt: LiveNextPromptSnapshot?
    let pendingConfirmation: String?
    let studyEvents: [LiveStudyEventSnapshot]
    let retryAndErrorLog: [String]
    let timedOut: Bool
}

private struct LiveTrackingCueSnapshot: Codable {
    let id: String
    let source: String
    let metric: String?
    let observation: String
    let coverage: String?
    let confidence: String?
    let limitations: [String]

    init(_ cue: TrackingCue) {
        id = cue.id
        source = cue.source.rawValue
        metric = cue.insight?.metric.rawValue
        observation = cue.observation
        coverage = cue.insight?.coverageDescription
        confidence = cue.insight?.confidence.rawValue
        limitations = cue.insight?.limitations ?? []
    }
}

private struct LiveScenarioRunReport: Codable {
    let caseID: String
    let title: String
    let condition: String
    let completed: Bool
    let stopReason: String
    let finalStage: String
    let selectedCard: String?
    let trackingProfile: String
    let trackingExpectedBehavior: String
    let initialTrackingCueIDs: [String]
    let initialTrackingCues: [LiveTrackingCueSnapshot]
    let visitedProtocolStages: [String]
    let finalNarrative: String?
    let proposalKind: String?
    let practiceContent: String?
    let turns: [LiveScenarioTurnReport]
}

private struct LivePairedComparison: Codable {
    let caseID: String
    let sharedContextualDisclosure: Bool
    let sharedTrackingRules: Bool
    let differentReflectionMedium: Bool
    let sharedNarrativeRule: Bool
    let sharedPracticeAndCompletionRules: Bool
    let violations: [String]
}

private struct LiveScenarioMatrixReport: Codable {
    let generatedAt: String
    let scenarioSet: String
    let usesProductionRemotePlannerAndWriter: Bool
    let cases: [LiveScenarioCaseSummary]
    let runs: [LiveScenarioRunReport]
    let pairedComparisons: [LivePairedComparison]
}

private extension ReflectionLiveScenarioTests {
    static func syntheticTrackingCues(profile: LiveTrackingProfile) -> [TrackingCue] {
        typealias Observation = (
            id: String,
            source: TrackingSource,
            metric: TrackingMetric,
            text: String,
            validSamples: Int,
            expectedSamples: Int,
            confidence: TrackingInsightConfidence,
            limitations: [String],
            longestRun: Int
        )
        let observations: [Observation]
        switch profile {
        case .reducedRecovery:
            observations = [
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠时长比个人过去四周中位数少约45分钟，7晚有6晚记录", 6, 7, .moderate, [], 6),
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间比个人过去四周中位数晚约35分钟，7晚有6晚记录", 6, 7, .moderate, [], 6),
                ("steps", .healthSteps, .steps, "最近一周日均步数比个人过去四周中位数少约1200步，7天都有记录", 7, 7, .moderate, [], 7),
            ]
        case .denseSchedule:
            observations = [
                ("calendar", .calendarLoad, .calendarLoad, "最近一周日历中有明确时段的安排比个人过去四周中位数多4项", 7, 7, .moderate, ["日历只包含实际记录的安排"], 7),
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠时长比个人过去四周中位数少约10分钟，变化很小", 7, 7, .moderate, [], 7),
                ("steps", .healthSteps, .steps, "最近一周日均步数比个人过去四周中位数少约200步，变化很小", 7, 7, .moderate, [], 7),
            ]
        case .stableRecords:
            observations = [
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠时长与个人过去四周中位数接近，7晚都有记录", 7, 7, .moderate, [], 7),
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间与个人过去四周中位数接近", 7, 7, .moderate, [], 7),
                ("steps", .healthSteps, .steps, "最近一周日均步数与个人过去四周中位数接近，7天都有记录", 7, 7, .moderate, [], 7),
                ("calendar", .calendarLoad, .calendarLoad, "最近一周日历中记录的安排数量与个人过去四周水平接近", 7, 7, .moderate, ["日历只包含实际记录的安排"], 7),
            ]
        case .partialAndMissing:
            observations = [
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周只有3晚睡眠记录；已记录夜晚的入睡时间比个人过去四周中位数晚约40分钟", 3, 7, .low, ["缺少4晚睡眠记录，不能代表整周"], 2),
                ("sleep", .healthSleep, .sleepDuration, "最近一周只有2晚可用睡眠时长记录；已记录夜晚平均短约35分钟", 2, 7, .low, ["缺少5晚睡眠记录，不能代表整周"], 1),
                ("steps", .healthSteps, .steps, "最近一周只有4天有步数记录；已记录日的步数略少", 4, 7, .low, ["缺少3天步数记录，变化方向不稳定"], 2),
            ]
        case .mixedSignals:
            observations = [
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠时长比个人过去四周中位数少约50分钟", 7, 7, .moderate, [], 7),
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间比个人过去四周中位数晚约30分钟", 7, 7, .moderate, [], 7),
                ("steps", .healthSteps, .steps, "最近一周日均步数反而比个人过去四周中位数多约1600步", 7, 7, .moderate, [], 7),
                ("calendar", .calendarLoad, .calendarLoad, "最近一周日历中记录的安排比个人过去四周少2项", 7, 7, .moderate, ["日历减少不等于现实任务减少"], 7),
            ]
        case .delayedSleepOnly:
            observations = [
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间比个人过去四周中位数晚约55分钟", 7, 7, .moderate, [], 7),
                ("wake_time", .healthSleep, .sleepWakeTime, "最近一周醒来时间也比个人过去四周中位数晚约50分钟", 7, 7, .moderate, [], 7),
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠总时长与个人过去四周中位数接近", 7, 7, .moderate, [], 7),
                ("steps", .healthSteps, .steps, "最近一周日均步数与个人过去四周中位数接近", 7, 7, .moderate, [], 7),
            ]
        case .reducedActivityOnly:
            observations = [
                ("steps", .healthSteps, .steps, "最近一周日均步数比个人过去四周中位数少约1800步", 7, 7, .moderate, [], 7),
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠总时长与个人过去四周中位数接近", 7, 7, .moderate, [], 7),
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间与个人过去四周中位数接近", 7, 7, .moderate, [], 7),
                ("calendar", .calendarLoad, .calendarLoad, "最近一周日历中记录的安排数量与个人过去四周水平接近", 7, 7, .moderate, ["日历只包含实际记录的安排"], 7),
            ]
        case .improvingRecovery:
            observations = [
                ("sleep", .healthSleep, .sleepDuration, "最近一周睡眠时长比个人过去四周中位数多约40分钟", 7, 7, .moderate, [], 7),
                ("sleep_timing", .healthSleep, .sleepTiming, "最近一周入睡时间比个人过去四周中位数早约25分钟", 7, 7, .moderate, [], 7),
                ("steps", .healthSteps, .steps, "最近一周日均步数比个人过去四周中位数多约900步", 7, 7, .moderate, [], 7),
            ]
        case .noUsableData:
            return []
        }

        let now = Date()
        return observations.map { item in
            let insight = TrackingInsight(
                id: Self.stableUUID(for: "\(profile.rawValue)_\(item.id)"),
                metric: item.metric,
                observationWindow: DateInterval(
                    start: now.addingTimeInterval(-7 * 86_400),
                    end: now
                ),
                validSampleCount: item.validSamples,
                expectedSampleCount: item.expectedSamples,
                coverageDescription: item.validSamples < item.expectedSamples
                    ? "最近窗口只有 \(item.validSamples)/\(item.expectedSamples) 个有效日"
                    : "最近窗口记录完整",
                neutralObservation: item.text,
                baselineWindow: DateInterval(
                    start: now.addingTimeInterval(-35 * 86_400),
                    end: now.addingTimeInterval(-7 * 86_400)
                ),
                baselineDescription: "与个人过去四周中位数比较",
                absoluteDifference: nil,
                relativeDifference: nil,
                strength: .baselineComparison,
                confidence: item.confidence,
                limitations: item.limitations,
                possibleConfounders: ["设备佩戴、同步和日常安排都可能影响记录"],
                suggestedReflectionQuestion: "这些变化和当时的生活状态是否有联系，由用户确认",
                provenance: [],
                recentMedian: nil,
                baselineMedian: nil,
                medianAbsoluteDeviation: nil,
                interquartileRange: nil,
                longestConsecutiveRun: item.longestRun,
                userRelevance: .notReviewed
            )
            return TrackingCue(
                id: "scenario_\(profile.rawValue)_\(item.id)",
                source: item.source,
                observation: item.text,
                insight: insight
            )
        }
    }

    static func stableUUID(for value: String) -> UUID {
        let bytes = Array(value.utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let suffix = String(format: "%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }

    static func isRetryOrErrorEvent(_ action: String) -> Bool {
        let normalized = action.lowercased()
        return [
            "reject",
            "regeneration",
            "retry",
            "failed",
            "failure",
            "error",
            "invalid",
            "suppressed",
        ].contains { normalized.contains($0) }
    }

    static func visitedProtocolStages(from actions: [String]) -> [String] {
        var stages: [String] = [ReflectionProtocolStage.contextualDisclosure.rawValue]
        for action in actions where action.hasPrefix("protocol_transition_") {
            let marker = "_to_"
            guard let range = action.range(of: marker) else { continue }
            let suffix = action[range.upperBound...]
            let stage = suffix.range(of: "_intent_").map {
                String(suffix[..<$0.lowerBound])
            } ?? String(suffix)
            if stages.last != stage { stages.append(stage) }
        }
        return stages
    }

    static func comparePairedRuns(
        _ runs: [LiveScenarioRunReport]
    ) -> [LivePairedComparison] {
        Dictionary(grouping: runs, by: \.caseID)
            .keys
            .sorted()
            .compactMap { caseID in
                let values = runs.filter { $0.caseID == caseID }
                guard let card = values.first(where: {
                    $0.condition == ExperimentalCondition.cardMediated.rawValue
                }),
                let direct = values.first(where: {
                    $0.condition == ExperimentalCondition.directLLM.rawValue
                }) else { return nil }

                let contextual = [card, direct].allSatisfy {
                    $0.visitedProtocolStages.contains(
                        ReflectionProtocolStage.contextualDisclosure.rawValue
                    )
                }
                let tracking = card.initialTrackingCueIDs == direct.initialTrackingCueIDs
                let medium =
                    card.visitedProtocolStages.contains(
                        ReflectionProtocolStage.cardReflection.rawValue
                    )
                    && !direct.visitedProtocolStages.contains(
                        ReflectionProtocolStage.cardReflection.rawValue
                    )
                    && direct.visitedProtocolStages.contains(
                        ReflectionProtocolStage.directReflection.rawValue
                    )
                let narrative = [card, direct].allSatisfy {
                    $0.visitedProtocolStages.contains(
                        ReflectionProtocolStage.narrativeConfirmation.rawValue
                    )
                }
                let finalRules = [card, direct].allSatisfy {
                    $0.completed
                        && $0.finalNarrative?.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty == false
                }

                var violations: [String] = []
                if !contextual { violations.append("\(caseID): contextual disclosure missing") }
                if !tracking { violations.append("\(caseID): paired tracking inputs differ") }
                if !medium { violations.append("\(caseID): reflection medium was not the only intended branch") }
                if !narrative { violations.append("\(caseID): final narrative confirmation missing") }
                if !finalRules { violations.append("\(caseID): practice/no-action completion contract incomplete") }

                return LivePairedComparison(
                    caseID: caseID,
                    sharedContextualDisclosure: contextual,
                    sharedTrackingRules: tracking,
                    differentReflectionMedium: medium,
                    sharedNarrativeRule: narrative,
                    sharedPracticeAndCompletionRules: finalRules,
                    violations: violations
                )
            }
    }
}

private enum LiveScenarioReportRenderer {
    static func markdown(_ report: LiveScenarioMatrixReport) -> String {
        var lines: [String] = [
            "# Beyond Comfort 自动完整流程案例报告",
            "",
            "- 生成时间：\(report.generatedAt)",
            "- 案例集：\(report.scenarioSet)",
            "- 使用正式 Remote Planner / Writer：\(report.usesProductionRemotePlannerAndWriter ? "是" : "否")",
            "- 运行数：\(report.runs.count)",
            "- 完成数：\(report.runs.filter(\.completed).count)",
            "",
            "两组运行共享 contextual disclosure、tracking、最终叙事、Practice 与完成协议；仅反思媒介分为随机卡牌和直接 LLM 反思。",
            "",
        ]

        for comparison in report.pairedComparisons {
            lines += [
                "## 配对检查：\(comparison.caseID)",
                "",
                "| 检查 | 结果 |",
                "|---|---|",
                "| Contextual disclosure | \(mark(comparison.sharedContextualDisclosure)) |",
                "| Tracking 输入与规则 | \(mark(comparison.sharedTrackingRules)) |",
                "| 仅反思媒介不同 | \(mark(comparison.differentReflectionMedium)) |",
                "| 最终叙事 | \(mark(comparison.sharedNarrativeRule)) |",
                "| Practice / complete | \(mark(comparison.sharedPracticeAndCompletionRules)) |",
                "",
            ]
            if !comparison.violations.isEmpty {
                lines += comparison.violations.map { "- ⚠️ \($0)" } + [""]
            }
        }

        for run in report.runs {
            lines += [
                "# \(run.title) · \(conditionName(run.condition))",
                "",
                "- 案例 ID：`\(run.caseID)`",
                "- 完成：\(run.completed ? "是" : "否")",
                "- 停止原因：`\(run.stopReason)`",
                "- 最终阶段：`\(run.finalStage)`",
                "- 随机卡片：\(run.selectedCard ?? "无")",
                "- Tracking profile：`\(run.trackingProfile)`",
                "- Tracking 预期行为：\(run.trackingExpectedBehavior)",
                "- 阶段路径：\(run.visitedProtocolStages.map { "`\($0)`" }.joined(separator: " → "))",
                "",
                "## 初始 cleaned tracking 输入",
                "",
            ]

            if run.initialTrackingCues.isEmpty {
                lines.append("- 无可用数据；系统不得制造 tracking 解释。")
            } else {
                for cue in run.initialTrackingCues {
                    lines.append(
                        "- `\(cue.id)` · source=`\(cue.source)` · metric=`\(cue.metric ?? "none")` · " +
                        "confidence=`\(cue.confidence ?? "none")`：\(cue.observation)"
                    )
                    if let coverage = cue.coverage {
                        lines.append("  - 覆盖：\(coverage)")
                    }
                    if !cue.limitations.isEmpty {
                        lines.append("  - 限制：\(cue.limitations.joined(separator: "；"))")
                    }
                }
            }
            lines.append("")

            for turn in run.turns {
                lines += [
                    "## Turn \(turn.index)",
                    "",
                    "**用户输入**",
                    "",
                    blockquote(turn.userInput ?? "（会话开始事件，无用户输入）"),
                    "",
                    "**Assistant 回复**",
                    "",
                ]
                if turn.assistantReplies.isEmpty {
                    lines.append("> （本轮没有用户可见回复；可能是静默本地动作或失败）")
                } else {
                    lines.append(contentsOf: turn.assistantReplies.map(blockquote))
                }
                lines += [
                    "",
                    "- 当前协议阶段：`\(turn.stageAfterTurn)`",
                    "- 当前 App 阶段：`\(turn.appStageAfterTurn)`",
                    "- nextPrompt：\(describe(turn.nextPrompt))",
                    "- 待确认对象：`\(turn.pendingConfirmation ?? "none")`",
                    "",
                    "**Planner / Writer 调用**",
                    "",
                ]

                if turn.plannerAndWriterCalls.isEmpty {
                    lines.append("- 无")
                }
                for call in turn.plannerAndWriterCalls {
                    switch call.kind {
                    case .planner:
                        if let plan = call.plannerPlan {
                            lines += [
                                "- Planner #\(call.sequence) · trigger=`\(call.trigger)` · 输入阶段=`\(call.inputStage)`",
                                "  - intent=`\(plan.replyIntent.rawValue)` · requestedStage=`\(plan.requestedStage.rawValue)` · localAction=`\(plan.localAction.kind.rawValue)`",
                                "  - nextPrompt=\(describe(plan.nextPrompt.map(LiveNextPromptSnapshot.init)))",
                                "  - resolvedConfirmation=\(describe(plan.resolvedConfirmation))",
                                "  - replyGuidance：\(plan.replyGuidance)",
                            ]
                        } else {
                            lines.append("- Planner #\(call.sequence) 失败：\(call.error ?? "unknown")")
                        }
                    case .writer:
                        if let writer = call.writerResponse {
                            lines += [
                                "- Writer #\(call.sequence) · realizedIntent=`\(writer.realizedIntent.rawValue)`",
                                "  - 输出：\(writer.reply.replacingOccurrences(of: "\n", with: " "))",
                            ]
                        } else {
                            lines.append("- Writer #\(call.sequence) 失败：\(call.error ?? "unknown")")
                        }
                    }
                    if let correction = call.protocolCorrection, !correction.isEmpty {
                        lines.append("  - 协议重试提示：\(correction)")
                    }
                }

                lines += ["", "**阶段提交与事件**", ""]
                if turn.studyEvents.isEmpty {
                    lines.append("- 无")
                } else {
                    lines += turn.studyEvents.map { "- `\($0.stage)` · `\($0.action)`" }
                }
                lines += ["", "**重试与错误日志**", ""]
                if turn.retryAndErrorLog.isEmpty {
                    lines.append("- 无")
                } else {
                    lines += turn.retryAndErrorLog.map { "- ⚠️ \($0)" }
                }
                lines.append("")
            }

            lines += [
                "## 最终产出",
                "",
                "- 最终叙事：\(run.finalNarrative ?? "无")",
                "- Practice 类型：`\(run.proposalKind ?? "none")`",
                "- Practice：\(run.practiceContent ?? "无")",
                "",
            ]
        }

        return lines.joined(separator: "\n")
    }

    private static func mark(_ value: Bool) -> String { value ? "✅" : "❌" }

    private static func conditionName(_ value: String) -> String {
        value == ExperimentalCondition.cardMediated.rawValue ? "随机卡牌组" : "直接 LLM 对照组"
    }

    private static func blockquote(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }

    private static func describe(_ prompt: LiveNextPromptSnapshot?) -> String {
        guard let prompt else { return "`none`" }
        let fields = [
            "kind=\(prompt.kind)",
            "purpose=\(prompt.purpose ?? "none")",
            "focus=\(prompt.focus ?? "none")",
            "target=\(prompt.target ?? "none")",
            "referenceID=\(prompt.referenceID ?? "none")",
        ]
        return "`\(fields.joined(separator: " · "))`"
    }

    private static func describe(_ resolution: TurnResolvedConfirmation?) -> String {
        guard let resolution else { return "`none`" }
        return "`target=\(resolution.target.rawValue) · decision=\(resolution.decision.rawValue) · referenceID=\(resolution.referenceID ?? "none")`"
    }
}
