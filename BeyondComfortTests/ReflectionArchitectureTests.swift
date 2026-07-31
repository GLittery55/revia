import XCTest
@testable import BeyondComfort

final class ReflectionRouteResolverTests: XCTestCase {
    private let resolver = CompassionRouteResolver()

    private func readyAnalysis() -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.consentToCandor = .yes
        analysis.reflectiveCapacity = 2
        analysis.confidence = 0.9
        return analysis
    }

    private func relation(
        _ kind: SemanticRelationKind,
        concepts: [SemanticConcept]
    ) -> SemanticRelation {
        SemanticRelation(
            kind: kind,
            source: "用户确认的具体部分",
            relation: "影响",
            target: "当前处境",
            concepts: concepts,
            evidence: ["用户确认的具体部分"],
            status: .userConfirmed,
            confidence: 0.9
        )
    }

    func testHighDistressAndSelfCondemnationUsesTenderStabilize() {
        var analysis = readyAnalysis()
        analysis.distressLevel = 2
        analysis.selfAttackLevel = 2
        XCTAssertEqual(resolver.resolve(from: analysis), .tenderStabilize)
    }

    func testDecliningCandorUsesTenderStabilize() {
        var analysis = readyAnalysis()
        analysis.consentToCandor = .no
        XCTAssertEqual(resolver.resolve(from: analysis), .tenderStabilize)
    }

    func testBoundaryConcernUsesProtect() {
        var analysis = readyAnalysis()
        analysis.semanticRelations = [relation(.boundaryNeed, concepts: [.boundary, .protection])]
        XCTAssertEqual(resolver.resolve(from: analysis), .protect)
    }

    func testMissingSupportWithLowAgencyUsesProvide() {
        var analysis = readyAnalysis()
        analysis.semanticRelations = [relation(.unmetNeed, concepts: [.support])]
        XCTAssertEqual(resolver.resolve(from: analysis), .provide)
    }

    func testAcknowledgedBehaviorAndPossibleImpactUsesRepair() {
        var analysis = readyAnalysis()
        analysis.semanticRelations = [relation(.behaviorImpact, concepts: [.repair, .responsibility])]
        XCTAssertEqual(resolver.resolve(from: analysis), .repair)
    }

    func testControllableRepeatingPatternUsesChange() {
        var analysis = readyAnalysis()
        analysis.semanticRelations = [relation(.controllablePart, concepts: [.change])]
        XCTAssertEqual(resolver.resolve(from: analysis), .change)
    }

    func testUncertaintyUsesExplore() {
        var analysis = readyAnalysis()
        analysis.uncertainties = ["cause remains unclear"]
        XCTAssertEqual(resolver.resolve(from: analysis), .explore)
    }

    func testNegativeOutcomeAloneDoesNotProduceRepairOrChange() {
        var analysis = readyAnalysis()
        analysis.eventDescription = "the submission was late"
        XCTAssertEqual(resolver.resolve(from: analysis), .explore)
    }

    func testTrackingContextAloneDoesNotProduceRepairOrChange() {
        var analysis = readyAnalysis()
        analysis.semanticRelations = [relation(.conditionCapacity, concepts: [.recovery])]
        XCTAssertEqual(resolver.resolve(from: analysis), .explore)
    }

    func testLegacySummaryArraysCannotAssignResponsibilityRoute() {
        var analysis = readyAnalysis()
        analysis.personalContributions = ["模型推测的行为"]
        analysis.possibleImpactOnOthers = ["模型推测的影响"]
        analysis.possibleBoundaryConcerns = ["模型推测的边界"]
        XCTAssertEqual(resolver.resolve(from: analysis), .explore)
    }
}

final class CompassionatePracticeResolverTests: XCTestCase {
    private let resolver = CompassionatePracticeResolver()

    private func analysis(
        distress: Int = 1,
        selfAttack: Int = 0,
        capacity: Int = 2
    ) -> ContextAnalysis {
        var value = ContextAnalysis()
        value.distressLevel = distress
        value.selfAttackLevel = selfAttack
        value.reflectiveCapacity = capacity
        value.confidence = 0.9
        return value
    }

    func testSameBehaviorImpactRelationSelectsRepairAcrossUnfamiliarSituations() {
        let medical = SemanticRelation(
            kind: .behaviorImpact,
            source: "没有把用药变化告诉照护者",
            relation: "可能使",
            target: "对方缺少安排所需的信息",
            concepts: [.communication, .repair],
            evidence: ["没有告诉他", "他不知道怎么安排"],
            status: .userConfirmed,
            confidence: 0.9
        )
        let financial = SemanticRelation(
            kind: .behaviorImpact,
            source: "延后说明账单缺口",
            relation: "可能使",
            target: "共同付款的人无法及时调整",
            concepts: [.communication, .repair],
            evidence: ["一直没说账单不够", "她来不及调整"],
            status: .userConfirmed,
            confidence: 0.9
        )

        XCTAssertEqual(
            resolver.resolve(analysis: analysis(), groundedRelations: [medical]),
            .repair
        )
        XCTAssertEqual(
            resolver.resolve(analysis: analysis(), groundedRelations: [financial]),
            .repair
        )
    }

    func testBoundaryAndCapacityRelationsChooseDirectionWithoutTopicClassification() {
        let boundary = SemanticRelation(
            kind: .boundaryNeed,
            source: "当前可承受的范围",
            relation: "小于",
            target: "外部要求的范围",
            concepts: [.boundary, .protection],
            evidence: ["现在只能承担一部分"],
            status: .userStated,
            confidence: 0.88
        )
        XCTAssertEqual(
            resolver.resolve(analysis: analysis(), groundedRelations: [boundary]),
            .protection
        )

        let capacity = SemanticRelation(
            kind: .conditionCapacity,
            source: "近期休息不足",
            relation: "可能减少",
            target: "处理当前处境时可用的精力",
            concepts: [.recovery, .constraint],
            evidence: ["最近确实没有休息好"],
            status: .userConfirmed,
            confidence: 0.86
        )
        XCTAssertEqual(
            resolver.resolve(
                analysis: analysis(distress: 2, selfAttack: 2, capacity: 1),
                groundedRelations: [capacity]
            ),
            .care
        )
    }

    func testNoGroundedControllableRelationProducesNoAction() {
        XCTAssertEqual(
            resolver.resolve(analysis: analysis(), groundedRelations: []),
            .noAction
        )
    }

    func testGroundedWholeSelfEvaluationCanProduceCareWithoutResponsibilityEvidence() {
        let relation = SemanticRelation(
            kind: .selfEvaluation,
            source: "一次具体结果",
            relation: "被扩大为",
            target: "对整个人的判断",
            concepts: [.selfEvaluation, .judgment],
            evidence: ["我把这次结果看成了对整个人的判断"],
            status: .userConfirmed,
            confidence: 0.9
        )

        XCTAssertEqual(
            resolver.resolve(analysis: analysis(), groundedRelations: [relation]),
            .care
        )
    }
}

final class CrossoverStudyTests: XCTestCase {
    func testCounterbalancedSequencesContainEachConditionExactlyOnce() {
        XCTAssertEqual(StudySequence.cardFirst.condition(for: 1), .cardMediated)
        XCTAssertEqual(StudySequence.cardFirst.condition(for: 2), .directLLM)
        XCTAssertEqual(StudySequence.directFirst.condition(for: 1), .directLLM)
        XCTAssertEqual(StudySequence.directFirst.condition(for: 2), .cardMediated)
        XCTAssertNil(StudySequence.cardFirst.condition(for: 3))
    }

    func testDirectConditionUsesNoCard() {
        XCTAssertFalse(ExperimentalCondition.directLLM.usesCard)
        XCTAssertTrue(ExperimentalCondition.cardMediated.usesCard)
    }

    @MainActor
    func testDirectConditionSkipsCardAndEntersCandidCircumstances() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .directLLM
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.trackingReviewCompleted = true
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertNil(model.session.card)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action.contains("card_draw") })
    }
}

final class ReflectionPromptAndTrackingTests: XCTestCase {
    private let factory = ReflectionPromptFactory()

    private func cue(
        _ text: String,
        relevance: TrackingCueRelevance,
        source: TrackingSource = .healthSleep,
        metric: TrackingMetric = .sleepDuration,
        strength: TrackingInsightStrength = .baselineComparison,
        confidence: TrackingInsightConfidence = .moderate
    ) -> TrackingCue {
        let insight = TrackingInsight(
            id: UUID(),
            metric: metric,
            observationWindow: DateInterval(start: Date().addingTimeInterval(-604_800), end: Date()),
            validSampleCount: 5,
            expectedSampleCount: 7,
            coverageDescription: "5/7 晚有记录",
            neutralObservation: text,
            baselineWindow: nil,
            baselineDescription: nil,
            absoluteDifference: nil,
            relativeDifference: nil,
            strength: strength,
            confidence: confidence,
            limitations: ["两晚缺少记录", "个人历史覆盖不足"],
            possibleConfounders: ["设备同步"],
            suggestedReflectionQuestion: "这和你记得的情况相符吗？",
            provenance: [],
            recentMedian: nil,
            baselineMedian: nil,
            medianAbsoluteDeviation: nil,
            interquartileRange: nil,
            longestConsecutiveRun: 3,
            userRelevance: relevance
        )
        var cue = TrackingCue(source: source, observation: text, insight: insight)
        cue.relevance = relevance
        return cue
    }

    private func prompt(cues: [TrackingCue]) -> LLMPrompt {
        factory.dialoguePrompt(
            state: .tenderGrounding,
            route: .tenderStabilize,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: cues,
            nextQuestionGoal: "one detail",
            recentMessages: []
        )
    }

    func testIrrelevantCueIsOmitted() {
        XCTAssertFalse(prompt(cues: [cue("IRRELEVANT_SECRET", relevance: .irrelevant)]).user.contains("IRRELEVANT_SECRET"))
    }

    func testUnconfirmedCueDetailsAreOmittedFromLaterPrompts() {
        let uncertain = prompt(cues: [cue("UNCONFIRMED_SLEEP_RECORD", relevance: .uncertain)]).user
        let notReviewed = prompt(cues: [cue("UNREVIEWED_SLEEP_RECORD", relevance: .notReviewed)]).user

        XCTAssertFalse(uncertain.contains("UNCONFIRMED_SLEEP_RECORD"))
        XCTAssertFalse(notReviewed.contains("UNREVIEWED_SLEEP_RECORD"))
    }

    func testComputedPendingCueIsNeverSentWithoutAggregateHypothesis() {
        let computedObservation = "最近睡眠时长中位数约为 6.4 小时，个人基线约为 7.1 小时，相差约 42 分钟（更少）"
        let candidate = cue(computedObservation, relevance: .notReviewed)
        let review = factory.dialoguePrompt(
            state: .trackingReview,
            route: .tenderStabilize,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [candidate],
            nextQuestionGoal: "ask which parts of the bounded bundle fit",
            recentMessages: []
        )

        XCTAssertTrue(review.system.localizedCaseInsensitiveContains("tentative"))
        XCTAssertTrue(review.system.localizedCaseInsensitiveContains("measurement-free contextual hypothesis"))
        XCTAssertFalse(review.user.contains("睡眠"))
        XCTAssertFalse(review.user.contains(computedObservation))
        XCTAssertFalse(review.user.localizedCaseInsensitiveContains("provenance"))
        XCTAssertFalse(review.user.localizedCaseInsensitiveContains("sampleCount"))
        XCTAssertFalse(prompt(cues: [candidate]).user.contains(computedObservation))
    }

    func testRelevantLegacyCueIsOmittedWithoutAggregateHypothesis() {
        let text = prompt(cues: [cue("LEGACY_TRACKING_SECRET", relevance: .relevant)]).user
        XCTAssertFalse(text.contains("LEGACY_TRACKING_SECRET"))
        XCTAssertFalse(text.contains("User-confirmed background cue"))
    }

    func testTrackingPromptProhibitsMetricsAndSpecificEmotionInference() {
        let text = factory.dialoguePrompt(
            state: .trackingReview,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [
                cue("最近 HRV 比个人基线低 4 ms", relevance: .notReviewed, source: .healthHRV, metric: .heartRateVariability),
                cue("日程记录不足", relevance: .notReviewed, source: .calendarLoad, metric: .calendarLoad),
            ],
            nextQuestionGoal: "present the bounded tracking background",
            recentMessages: []
        ).system.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")

        XCTAssertTrue(text.contains("measurement-free contextual hypothesis"))
        XCTAssertTrue(text.contains("Do not create a separate tracking or relevance question"))
        XCTAssertTrue(text.contains("measurements"))
        XCTAssertTrue(text.contains("specific emotion"))
    }

    func testAggregateContextCueHidesEveryUnderlyingTrackingObservation() {
        let hypothesis = "用户近期可能承受着比平时更多的压力，处理事情时可用的精力或应对余地可能有所减少。"
        let evidence = DialoguePromptEvidence(
            contextualLoadCue: DialogueContextCue(
                hypothesis: hypothesis,
                confidence: .moderate,
                relevance: .notReviewed,
                usageBoundary: "不得提及测量、设备、指标或具体情绪。"
            )
        )
        let prompt = factory.dialoguePrompt(
            state: .trackingReview,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [
                cue(
                    "RAW_HRV_SECRET 最近 HRV 比个人基线低 4 ms",
                    relevance: .notReviewed,
                    source: .healthHRV,
                    metric: .heartRateVariability
                ),
            ],
            promptEvidence: evidence,
            nextQuestionGoal: "connect the contextual hypothesis to the event",
            recentMessages: []
        )

        XCTAssertTrue(prompt.user.contains(hypothesis))
        XCTAssertFalse(prompt.user.contains("RAW_HRV_SECRET"))
        XCTAssertFalse(prompt.user.contains("4 ms"))
    }

    func testCardImagePromptCannotReceiveAggregateContextCue() {
        let hypothesis = "CONTEXT_MUST_NOT_SHAPE_IMAGE_STORY"
        let prompt = factory.dialoguePrompt(
            state: .cardInterpretation,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: ReflectionCard(
                id: 1,
                neutralLabel: "图像 2",
                imageName: "2",
                reflectiveThemes: "unused"
            ),
            trackingCues: [],
            promptEvidence: DialoguePromptEvidence(
                contextualLoadCue: DialogueContextCue(
                    hypothesis: hypothesis,
                    confidence: .moderate,
                    relevance: .relevant,
                    usageBoundary: "measurement free"
                )
            ),
            nextQuestionGoal: "ask one image-only question",
            recentMessages: []
        )

        XCTAssertFalse(prompt.user.contains(hypothesis))
    }

    func testWriterPromptIncludesOnlyTheCurrentPhaseContract() {
        let tracking = factory.dialoguePrompt(
            state: .trackingReview,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "connect tracking with the confirmed situation",
            recentMessages: []
        ).system
        XCTAssertTrue(tracking.contains("LEGACY TRACKING STATE:"))
        XCTAssertTrue(tracking.contains("Do not create a separate tracking or relevance question"))
        XCTAssertFalse(tracking.contains("CARD IMAGE:"))
        XCTAssertFalse(tracking.contains("OPTIONAL PRACTICE:"))
        XCTAssertFalse(tracking.contains("FINAL NARRATIVE:"))

        let card = factory.dialoguePrompt(
            state: .cardInterpretation,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "develop one image relation",
            recentMessages: []
        ).system
        XCTAssertTrue(card.contains("CARD IMAGE:"))
        XCTAssertFalse(card.contains("TRACKING:"))
        XCTAssertFalse(card.contains("OPTIONAL PRACTICE:"))
        XCTAssertFalse(card.contains("FINAL NARRATIVE:"))
    }

    func testWriterPromptEndsWithTheMinimalJSONContract() {
        let system = factory.dialoguePrompt(
            state: .emotionDisclosure,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "respond to the latest meaning",
            recentMessages: []
        ).system.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(system.contains("FINAL OUTPUT CONTRACT"))
        XCTAssertTrue(system.hasSuffix("category, description, timing, and rationale."))
        XCTAssertEqual(
            system.components(separatedBy: "FINAL OUTPUT CONTRACT").count - 1,
            1
        )
    }

    func testTenderPromptRequiresNaturalProseInsteadOfFieldExport() {
        let text = factory.dialoguePrompt(
            state: .tenderGrounding,
            route: .tenderStabilize,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "write tender grounding",
            recentMessages: []
        ).system

        XCTAssertTrue(text.contains("not an exported field list"))
        XCTAssertTrue(text.contains("avoid headings, repeated colons, duplicated phrases"))
        XCTAssertTrue(text.contains("two or three connected spoken-Chinese sentences"))
    }

    func testAnalyzerSeparatesEventEmotionBodyAndSelfEvaluation() {
        let text = factory.analyzerPrompt(
            context: ReflectionContext(),
            messages: [
                ChatMessage(role: .user, content: "组会上被批评后，我很羞愧，脸发热，也觉得自己特别差。"),
            ]
        ).system.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")

        XCTAssertTrue(text.contains("eventDescription contains only the concrete occurrence"))
        XCTAssertTrue(text.contains("Classify emotions, self-evaluations, bodily experiences"))
        XCTAssertTrue(text.contains("semantic role"))
        XCTAssertTrue(text.contains("not by a scenario-specific word list"))
        XCTAssertTrue(text.contains("responsePlan is the private one-turn semantic plan"))
        XCTAssertTrue(text.contains("Missing emotions never automatically require"))
        XCTAssertTrue(text.contains("Swift will then use an emergency path"))
    }

    func testPromptProjectionCleansLegacyMixedEmotionAndBodyFields() {
        var context = ReflectionContext()
        context.emotions = ["羞愧", "特别差"]
        context.bodilyResponses = ["脸发热", "当时很羞愧，脸发热，也不敢看别人"]
        context.selfJudgment = "特别差"
        let user = factory.dialoguePrompt(
            state: .tenderGrounding,
            route: .tenderStabilize,
            context: context,
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "write tender grounding",
            recentMessages: []
        ).user

        XCTAssertTrue(user.contains("羞愧"))
        XCTAssertTrue(user.contains("脸发热"))
        XCTAssertTrue(user.contains("selfJudgment"))
        XCTAssertFalse(user.contains("不敢看别人"))
    }

    func testWriterReceivesOnlyTheLocallyValidatedResponsePlanAsTypedEvidence() {
        let plan = ResponsePlan(
            function: .clarifyPersonalMeaning,
            focus: "失败和整体能力判断之间的关系",
            evidence: ["测试一直失败", "能力不行"],
            relationKinds: [.selfEvaluation],
            questionIntent: "询问整体判断背后的具体担心",
            shouldAskQuestion: true,
            confidence: 0.9
        )
        let prompt = factory.dialoguePrompt(
            state: .selfJudgment,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            promptEvidence: DialoguePromptEvidence(responsePlan: plan),
            nextQuestionGoal: "semantic plan",
            recentMessages: []
        )

        XCTAssertTrue(prompt.user.contains("locally authorized by Swift"))
        XCTAssertTrue(prompt.user.contains("clarifyPersonalMeaning"))
        XCTAssertTrue(prompt.user.contains("测试一直失败"))
        XCTAssertTrue(prompt.user.contains("shouldAskQuestion"))
    }

    func testAnalyzerReceivesSwiftAllowedFunctionsForAnOpenTurn() {
        let planning = ResponsePlanningContext(
            state: .cardInterpretation,
            workflowPhase: .cardAssociation,
            allowedFunctions: [.developImageRelation, .closeWithoutQuestion],
            shouldAskQuestion: true
        )
        let prompt = factory.analyzerPrompt(
            context: ReflectionContext(),
            messages: [
                ChatMessage(
                    role: .user,
                    content: "画面里一个人扶着门，外面放着一个包裹"
                ),
            ],
            planningContext: planning
        )

        XCTAssertTrue(prompt.user.contains("Swift planning boundary"))
        XCTAssertTrue(prompt.user.contains("developImageRelation"))
        XCTAssertTrue(prompt.user.contains("closeWithoutQuestion"))
        XCTAssertTrue(prompt.user.contains("Select only from"))
        XCTAssertTrue(prompt.user.contains("do not tell you what the user means"))
    }

    func testDialoguePromptDoesNotRequireRepeatingEveryUserMessage() {
        let text = prompt(cues: []).system
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        XCTAssertTrue(text.contains("Never mechanically repeat"))
        XCTAssertTrue(text.contains("briefly pick up one concrete detail"))
        XCTAssertFalse(text.contains("Never repeat, summarize, or paraphrase"))
        XCTAssertFalse(text.contains("Reflect one concrete phrase"))
    }

    func testDialoguePromptPrioritizesNaturalRelationalLanguage() {
        let text = prompt(cues: []).system
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        XCTAssertTrue(text.contains("Do not optimize a user-facing turn only for theoretical completeness"))
        XCTAssertTrue(text.contains("emotional naturalness, conversational rhythm, and grounded specificity"))
        XCTAssertTrue(text.contains("ordinary spoken Chinese"))
        XCTAssertTrue(text.contains("never like a questionnaire"))
        XCTAssertTrue(text.contains("60–160 Chinese characters"))
        XCTAssertTrue(text.contains("under 160 Chinese characters"))
        XCTAssertFalse(text.contains("under 90 Chinese characters"))
        XCTAssertTrue(text.contains("plain, warm, ordinary spoken Chinese"))
        XCTAssertTrue(text.contains("literary, poetic, therapeutic, or vague phrases"))
        XCTAssertTrue(text.contains("never as a separate relevance question"))

        let readiness = factory.dialoguePrompt(
            state: .readinessCheck,
            route: .tenderStabilize,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "invite a choice",
            recentMessages: []
        ).system
        XCTAssertTrue(readiness.localizedCaseInsensitiveContains("whole-context confirmation"))
        XCTAssertTrue(readiness.localizedCaseInsensitiveContains("whole summary"))
        XCTAssertTrue(readiness.localizedCaseInsensitiveContains("not a readiness test"))
        XCTAssertTrue(readiness.localizedCaseInsensitiveContains("do not mention") && readiness.contains("card"))
    }

    func testDialoguePromptStopsRepeatingCompletedQuestionFunctionsAcrossScenarios() {
        let text = prompt(cues: []).system
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        XCTAssertTrue(text.contains("A simple greeting such as hello/hi/你好 is social contact"))
        XCTAssertTrue(text.contains("Count questions across BOTH reflection and question"))
        XCTAssertTrue(text.contains("question function as the unit of dialogue"))
        XCTAssertTrue(text.contains("do not ask a paraphrase merely to collect more detail"))
        XCTAssertTrue(text.contains("Move to the next unresolved function"))
        XCTAssertFalse(text.contains("特别期待会有效"))
        XCTAssertFalse(text.contains("专业指导 or 技术指导"))
        XCTAssertTrue(text.contains("technical UI state"))
        XCTAssertTrue(text.contains("local image is displayed"))
    }

    func testGlobalLabelDoesNotBecomeAnUnsupportedMechanism() {
        let text = prompt(cues: []).system
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        XCTAssertTrue(text.contains("does not by itself reveal"))
        XCTAssertTrue(text.contains("Use a mechanism only when"))
        XCTAssertFalse(text.contains("The label “拖延” does not by itself"))

        let fallback = RemoteDialogueGenerator().emergencyFallbackQuestion(for: .contextDisclosure)
        XCTAssertFalse(fallback.contains("注意力"))
        XCTAssertTrue(fallback.contains("现实情况"))

        let analyzer = factory.analyzerPrompt(
            context: ReflectionContext(),
            messages: [ChatMessage(role: .user, content: "论文没交，我觉得自己很拖延")]
        ).system
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        XCTAssertTrue(analyzer.contains("Do not infer a psychological mechanism from a global label"))
        XCTAssertTrue(analyzer.contains("Classify emotions, self-evaluations, bodily experiences"))
    }

    func testEmotionFallbackForAdvisorCriticismDoesNotUseProcrastinationTemplate() {
        var context = ReflectionContext()
        context.eventDescription = "我今天在组会上被导师批评了"
        context.selfJudgment = "我感觉自己特别差"
        let question = RemoteDialogueGenerator().emergencyFallbackQuestion(
            for: .emotionDisclosure,
            context: context,
            messages: [
                ChatMessage(
                    role: .user,
                    content: "我今天在组会上被导师批评了，我感觉自己特别差，甚至不想再做研究了。"
                ),
            ]
        )

        XCTAssertTrue(
            question.contains("最明显的感受") ||
                question.contains("最担心")
        )
        XCTAssertFalse(question.contains("一直没开始"))
        XCTAssertFalse(question.contains("很难推进"))
    }

    func testRepairPromptRewritesAbstractResponsibilityIntoConcreteInteraction() {
        var context = ReflectionContext()
        context.personalContributions = ["答应当天回复同事，但后来忘了"]
        context.possibleImpactOnOthers = ["同事第二天才拿到资料"]
        let generated = factory.dialoguePrompt(
            state: .tenderGrounding,
            route: .repair,
            context: context,
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "explore repair",
            recentMessages: []
        )

        XCTAssertTrue(generated.system.contains("Every repair question must reuse the concrete action or missing communication"))
        XCTAssertTrue(generated.system.contains("Rewrite abstract questions about responsibility"))
        XCTAssertTrue(generated.system.contains("哪段关系需要重新说清楚"))
        XCTAssertTrue(generated.user.contains("答应当天回复同事，但后来忘了"))

        let rewritten = RemoteDialogueGenerator().concreteRepairQuestion(
            rewriting: "这段关系里有什么需要修复？",
            context: context
        )
        XCTAssertFalse(rewritten.contains("有什么需要修复"))
        XCTAssertTrue(rewritten.contains("答应当天回复同事，但后来忘了"))
        XCTAssertTrue(rewritten.contains("对方当时最需要先知道什么"))
    }

    func testFallbackNeverExposesInternalRepetitionRule() {
        let generator = RemoteDialogueGenerator()
        let generic = generator.emergencyFallbackQuestion(for: .summary)
        let openFeeling = generator.emergencyFallbackQuestion(for: .bodilyResponse)
        let cardAssociation = generator.emergencyFallbackQuestion(for: .cardInterpretation)
        let cardBoundary = generator.emergencyFallbackQuestion(for: .attributionReflection)

        XCTAssertFalse(generic.contains("我们先不重复追问"))
        XCTAssertTrue(generic.isEmpty)
        XCTAssertEqual(openFeeling, "想到这件事时，你现在有什么感受？没有特别明显的感觉也可以。")
        XCTAssertFalse(openFeeling.contains("身体状态"))
        XCTAssertEqual(cardAssociation, "沿着你刚才的说法，画面接下来可能会发生什么？")
        XCTAssertFalse(cardAssociation.contains("看到这张牌"))
        XCTAssertTrue(cardBoundary.contains("贴近"))
        XCTAssertEqual(cardBoundary.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    func testQuestionCleanerSelectsQuestionMatchingNextGoalInsteadOfFirstQuestion() {
        let generator = RemoteDialogueGenerator()
        let draft = DialogueTurn(
            reflection: "导师具体说了什么？",
            question: "当时最强烈的感受是什么？",
            actionOptions: []
        )

        let selected = generator.bestQuestion(
            in: draft,
            state: .emotionDisclosure,
            nextQuestionGoal: "ask one plain question about the user's felt experience"
        )

        XCTAssertEqual(selected, "当时最强烈的感受是什么？")
    }

    func testQuestionCleanerDoesNotRequireQuestionForClosingStates() {
        let generator = RemoteDialogueGenerator()

        XCTAssertFalse(generator.stateRequiresQuestion(.summary))
        XCTAssertFalse(generator.stateRequiresQuestion(.completed))
        XCTAssertFalse(generator.stateRequiresQuestion(.actionSelection))
        XCTAssertTrue(generator.stateRequiresQuestion(.emotionDisclosure))
        XCTAssertTrue(generator.stateRequiresQuestion(.trackingReview))
    }

    func testQuestionCleanerUsesOneShortRewriteBeforeEmergencyFallback() async {
        let rewritten = DialogueTurn(
            reflection: "",
            question: "这件事让你最担心它说明什么？",
            actionOptions: []
        )
        let generator = RemoteDialogueGenerator(
            questionRewriter: StaticQuestionRewriter(turn: rewritten)
        )
        let draft = DialogueTurn(
            reflection: "这确实不容易。",
            question: "",
            actionOptions: []
        )

        let result = await generator.normalizedQuestionTurn(
            in: draft,
            state: .selfJudgment,
            nextQuestionGoal: "ask what the situation led the user to conclude about themselves",
            context: .init(),
            messages: [ChatMessage(role: .user, content: "我觉得自己很差")]
        )

        XCTAssertEqual(result.reflection, "这确实不容易。")
        XCTAssertEqual(result.question, "这件事让你最担心它说明什么？")
    }

    func testQuestionCleanerUsesEmergencyFallbackOnlyAfterRewriteFailure() async {
        let generator = RemoteDialogueGenerator(
            questionRewriter: FailingQuestionRewriter()
        )
        let draft = DialogueTurn(
            reflection: "这确实不容易。",
            question: "",
            actionOptions: []
        )

        let result = await generator.normalizedQuestionTurn(
            in: draft,
            state: .bodilyResponse,
            nextQuestionGoal: "ask about the person's present felt experience",
            context: .init(),
            messages: []
        )

        XCTAssertEqual(result.question, "想到这件事时，你现在有什么感受？没有特别明显的感觉也可以。")
    }

    func testQuestionCleanerDoesNotRewriteOrAddQuestionWhenStateDoesNotRequireOne() async {
        let generator = RemoteDialogueGenerator(
            questionRewriter: FailingQuestionRewriter()
        )
        let draft = DialogueTurn(
            reflection: "这次整理先停在这里。还要再确认一次吗？",
            question: "",
            actionOptions: []
        )

        let result = await generator.normalizedQuestionTurn(
            in: draft,
            state: .summary,
            nextQuestionGoal: "close without another question",
            context: .init(),
            messages: []
        )

        XCTAssertEqual(result.reflection, "这次整理先停在这里。")
        XCTAssertTrue(result.question.isEmpty)
    }

    func testQuestionRewritePromptIsShortGoalBoundedEditor() {
        let draft = DialogueTurn(
            reflection: "你现在还好吗？",
            question: "",
            actionOptions: []
        )
        let prompt = factory.questionRewritePrompt(
            state: .emotionDisclosure,
            nextQuestionGoal: "ask about the felt experience",
            draft: draft,
            recentMessages: [ChatMessage(role: .user, content: "我在组会上被批评了")]
        )

        XCTAssertTrue(prompt.system.contains("exactly one natural spoken-Chinese question"))
        XCTAssertTrue(prompt.system.contains(#""reflection":"""#))
        XCTAssertTrue(prompt.user.contains("ask about the felt experience"))
        XCTAssertTrue(prompt.user.contains("我在组会上被批评了"))
    }

    func testCardPromptAllowsOneAssociationThenOptionalRealityConnection() {
        var context = ReflectionContext()
        context.cardInterpretation = "一个人站在两条路之间"
        let card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        let imagePhase = factory.dialoguePrompt(
            state: .cardInterpretation,
            route: .explore,
            context: context,
            analysis: nil,
            card: card,
            trackingCues: [],
            nextQuestionGoal: "one image association",
            recentMessages: []
        )
        let generated = factory.dialoguePrompt(
            state: .attributionReflection,
            route: .explore,
            context: context,
            analysis: nil,
            card: card,
            trackingCues: [],
            nextQuestionGoal: "invite a reality connection",
            recentMessages: [
                ChatMessage(role: .assistant, content: "如果顺着这个画面往下看，你觉得他会走向哪边？"),
                ChatMessage(role: .user, content: "我觉得他会走向左边那个人"),
            ]
        )

        XCTAssertTrue(imagePhase.system.contains("exactly TWO image-focused assistant turns"))
        XCTAssertTrue(imagePhase.system.contains("There is no normal third image question"))
        XCTAssertTrue(imagePhase.system.contains("ONE extra card-specific image scaffold"))
        XCTAssertTrue(imagePhase.system.contains("never ask another image question"))
        XCTAssertTrue(generated.system.contains("completed their initial image story"))
        XCTAssertTrue(generated.system.contains("OPTIONAL card-to-life connection"))
        XCTAssertTrue(generated.system.contains("First deepen the real situation around that connection"))
        XCTAssertTrue(generated.system.contains("Only after that answer may you ask whether"))
        XCTAssertTrue(generated.system.contains("Only when a concrete fierce focus is present"))
        XCTAssertTrue(generated.user.contains("reality connection"))
    }

    func testPromptContractKeepsNarrativeAndActionGatesInOrder() {
        func system(for state: ReflectionState) -> String {
            factory.dialoguePrompt(
                state: state,
                route: .explore,
                context: ReflectionContext(),
                analysis: nil,
                card: nil,
                trackingCues: [],
                nextQuestionGoal: "follow only the current Swift gate",
                recentMessages: []
            ).system
        }

        let tender = system(for: .tenderGrounding)
        XCTAssertTrue(tender.contains("TENDER GROUNDING:"))
        XCTAssertTrue(tender.contains("No tracking, card, or action yet"))

        let tracking = system(for: .trackingReview)
        XCTAssertTrue(tracking.contains("LEGACY TRACKING STATE:"))
        XCTAssertTrue(tracking.contains("whole context summary"))
        XCTAssertFalse(tracking.contains("OPTIONAL PRACTICE:"))

        let narrative = system(for: .summary)
        XCTAssertTrue(narrative.contains("FINAL NARRATIVE:"))
        XCTAssertTrue(narrative.contains("stitch fields"))

        let action = system(for: .actionSelection)
        XCTAssertTrue(action.contains("OPTIONAL PRACTICE:"))
        XCTAssertTrue(action.contains("The narrative is already confirmed"))

        for scoped in [tender, tracking, narrative, action] {
            XCTAssertTrue(scoped.contains("Swift alone owns state transitions"))
            XCTAssertTrue(scoped.contains("Never announce or advance a phase"))
        }
    }

    func testCardBoundaryAnswersMustNotTriggerAnotherConnectionProbe() {
        var context = ReflectionContext()
        context.cardInterpretation = "一个人站在两条路之间"
        let generated = factory.dialoguePrompt(
            state: .attributionReflection,
            route: .tenderStabilize,
            context: context,
            analysis: nil,
            card: ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused"),
            trackingCues: [],
            nextQuestionGoal: "ask which situation it brings to mind",
            recentMessages: [
                ChatMessage(role: .assistant, content: "这个画面会让你想到现实里的什么吗？"),
                ChatMessage(role: .user, content: "有点难想到，好像没有了"),
            ]
        )

        XCTAssertTrue(generated.system.contains("想不到/没有了/有点难想到/没想到什么"))
        XCTAssertTrue(generated.system.contains("never establishes a connection"))
        XCTAssertTrue(generated.system.contains("ONE locally selected image-structure"))
        XCTAssertTrue(generated.system.contains("ONE last optional reality connection"))
        XCTAssertTrue(generated.system.contains("valid boundary"))

        let guarded = RemoteDialogueGenerator().cardBoundaryTurn(
            for: .attributionReflection,
            nextQuestionGoal: "Workflow phase: cardConnection.",
            messages: [ChatMessage(role: .user, content: "有点难想到，好像没有了")]
        )
        XCTAssertEqual(guarded?.reflection, "好，不用勉强把画面和现实连起来。就先停在这里。")
        XCTAssertFalse(guarded?.reflection.contains("两条路") == true)
        XCTAssertEqual(guarded?.question, "")
        XCTAssertTrue(guarded?.actionOptions.isEmpty == true)

        let finalScaffold = RemoteDialogueGenerator().cardBoundaryTurn(
            for: .attributionReflection,
            nextQuestionGoal: "Workflow phase: cardConnection. Ask one final optional connection question.",
            messages: [ChatMessage(role: .user, content: "有点难想到")],
            cardInterpretation: "一个女士在喂狗；她在安抚这只狗"
        )
        XCTAssertEqual(finalScaffold?.reflection, "先不用找一个完整的解释。")
        XCTAssertTrue(finalScaffold?.question.contains("她在安抚这只狗") == true)
        XCTAssertTrue(finalScaffold?.question.contains("直接说没有就可以") == true)
        XCTAssertEqual(finalScaffold?.visibleText.filter { $0 == "？" || $0 == "?" }.count, 1)

        let descriptionFinished = RemoteDialogueGenerator().cardBoundaryTurn(
            for: .attributionReflection,
            nextQuestionGoal: "Workflow phase: cardConnection.",
            messages: [ChatMessage(role: .user, content: "没有了", state: .cardInterpretation)]
        )
        XCTAssertNil(descriptionFinished, "牌面描述结束后仍应允许一次可选的现实连接邀请")

        let candidAnswer = RemoteDialogueGenerator().cardBoundaryTurn(
            for: .attributionReflection,
            nextQuestionGoal: "Workflow phase: candidCircumstances.",
            messages: [ChatMessage(role: .user, content: "没有", state: .attributionReflection)]
        )
        XCTAssertNil(candidAnswer, "现实条件阶段的“没有”不能被误吞成卡牌无连接边界")
    }

    func testEmotionDisclosureUsesOpenNarrativeRatherThanEmotionMenu() {
        let text = factory.dialoguePrompt(
            state: .emotionDisclosure,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "one meaningful detail",
            recentMessages: []
        ).system
        XCTAssertTrue(text.contains("do not classify emotion"))
        XCTAssertTrue(text.contains("Never provide an emotion menu"))
        XCTAssertFalse(text.contains("焦虑、羞愧"))
    }

    func testBodyPromptIsOneSkippableInvitationAndNeverAsksForLocation() {
        let text = factory.dialoguePrompt(
            state: .bodilyResponse,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "continue the story",
            recentMessages: []
        ).system
        XCTAssertTrue(text.contains("open, natural question about what the person feels"))
        XCTAssertTrue(text.contains("no obvious feeling"))
        XCTAssertTrue(
            text.lowercased().contains("do not require a bodily reaction")
        )
        XCTAssertFalse(text.contains("身体哪里最明显"))
    }

    @MainActor
    func testOpeningIsSingleGreetingAndOpenInvitationWithoutAssumedState() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        XCTAssertTrue(model.session.messages.isEmpty)

        model.begin()

        XCTAssertEqual(model.session.messages.count, 1)
        let opening = model.session.messages.last?.content ?? ""
        XCTAssertTrue(opening.contains("你好"))
        XCTAssertTrue(opening.contains("最近有什么事"))
        for unsupported in ["责怪自己", "失败", "羞愧", "焦虑"] {
            XCTAssertFalse(opening.contains(unsupported))
        }
    }

    @MainActor
    func testSimpleGreetingGetsNaturalReplyWithoutStartingAnInterview() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.begin()
        model.draft = "hello"

        model.send()

        XCTAssertEqual(model.session.stage, .eventDisclosure)
        let reply = model.session.messages.last?.content ?? ""
        XCTAssertEqual(reply, "Hello，我在。你想聊什么都可以。")
        XCTAssertFalse(reply.contains("为什么"))
        XCTAssertFalse(reply.contains("特别的事"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 0)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "simple_greeting_answered_without_analysis" })
    }

    @MainActor
    func testDifficultyAnsweringGetsLightScaffoldingWithoutAdvancing() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.begin()
        model.draft = "我不知道怎么回答，可以具体一点吗"
        model.send()
        XCTAssertEqual(model.session.stage, .eventDisclosure)
        let reply = model.session.messages.last?.content ?? ""
        XCTAssertTrue(reply.contains("不用找最准确的词"))
        XCTAssertFalse(reply.contains("焦虑"))
        XCTAssertFalse(reply.contains("羞愧"))
    }

    @MainActor
    func testVerbatimUserEchoIsRemovedFromVisibleReply() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: EchoingDialogueGenerator())
        model.begin()
        model.draft = "我原本答应周五交论文初稿，但到现在还没有写完"
        model.send()
        await waitForAsyncWork()
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("我原本答应周五交论文初稿，但到现在还没有写完"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("后来发生了什么"))
    }

    @MainActor
    func testPartialUserRestatementIsRemovedButNewContentRemains() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: PartialRestatementDialogueGenerator()
        )
        model.begin()
        model.draft = "我最近在准备投稿论文，但一直没有写完"
        model.send()
        await waitForAsyncWork()

        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("你最近在准备投稿论文"))
        XCTAssertTrue(response.contains("先不急着下结论"))
        XCTAssertTrue(response.contains("最卡住的是哪个时刻"))
    }

    @MainActor
    func testSecondPersonRewordedRestatementIsRemoved() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: SemanticRestatementDialogueGenerator()
        )
        model.begin()
        model.draft = "项目负责人昨晚十一点又让我第二天早上交一份分析，我还是答应了"
        model.send()
        await waitForAsyncWork()

        let response = model.session.messages.last?.content ?? ""
        // A reworded second-person retelling is stripped even though it shares almost no vocabulary
        // with the user's message ("第二天早上交" -> "次晨交付").
        XCTAssertFalse(response.contains("次晨交付"))
        XCTAssertFalse(response.contains("你还是答应了"))
        // The genuinely new distinction and the forward question survive.
        XCTAssertTrue(response.contains("还没说出口的界线"))
        XCTAssertTrue(response.contains("最先想守住"))
    }

    @MainActor
    func testUnsupportedCardDescriptorIsRemovedAfterCardInterpretation() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: CardDescriptorGenerator()
        )
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.draft = "画面里一个人很权威地坐在两根柱子中间，像在祷告"
        model.send()
        await waitForAsyncWork()

        let response = model.session.messages.last?.content ?? ""
        // "张力"/"被拉扯" were never in the user's card narrative, so the imposed descriptor is dropped
        // while "权威" (the user's own word) would have been allowed.
        XCTAssertFalse(response.contains("张力"))
        XCTAssertFalse(response.contains("被拉扯"))
        XCTAssertTrue(response.contains("会是谁站在那儿"))
    }

    @MainActor
    func testUnsupportedEmotionInferenceIsRemoved() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: UnsupportedEmotionGenerator())
        model.begin()
        model.draft = "导师今天问了论文进度"
        model.send()
        await waitForAsyncWork()
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("焦虑"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("后来发生了什么"))
    }

    @MainActor
    func testUnsupportedSelfWorryAndAbstractMetaQuestionAreReplaced() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: UnsupportedSelfWorryGenerator()
        )
        model.begin()
        model.draft = "那道题我一下子觉得做不出来"
        model.send()
        await waitForAsyncWork()
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("对自己的担心"))
        XCTAssertFalse(response.contains("最想先回应哪一点"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("后来发生了什么"))
    }

    @MainActor
    func testPhoneUseDoesNotBecomeAvoidanceWithoutUserFraming() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: UnsupportedAvoidanceGenerator())
        model.begin()
        model.draft = "我坐下以后刷了一会儿手机"
        model.send()
        await waitForAsyncWork()
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("逃避"))
        XCTAssertFalse(response.contains("躲开"))
    }

    @MainActor
    func testBodyLocationQuestionIsRemovedWithoutBodyEvidence() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: UnsupportedBodyLocationGenerator())
        model.begin()
        model.draft = "我还没有开始整理手头的材料"
        model.send()
        await waitForAsyncWork()
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("身体哪里"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("后来发生了什么"))
    }

    @MainActor
    func testOrnateOrPressuringLanguageIsReplacedBeforeDisplay() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: OrnateDialogueGenerator()
        )
        model.begin()
        model.draft = "我答应以后就开始做了"
        model.send()
        await waitForAsyncWork()

        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("心里最沉"))
        XCTAssertFalse(response.contains("值得被看到"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("后来发生了什么"))
    }

    @MainActor
    func testProlongedEffortAndNoProgressStopsTechnicalDetailMining() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: RepetitiveTechnicalProbeGenerator()
        )
        model.session.stage = .emotionDisclosure
        model.session.messages = [
            ChatMessage(role: .user, content: "我最近在准备投论文，但是应用开发卡住了"),
            ChatMessage(role: .assistant, content: "你说的拖延，是没开始还是做着很难推进？"),
            ChatMessage(role: .user, content: "我其实一直在调整，已经调了很多天，但还是没有成功"),
            ChatMessage(role: .assistant, content: "这对你有什么影响？"),
        ]
        model.draft = "主要是很挫败，就是一直看不到进展"

        model.send()
        await waitForModelIdle(model)

        XCTAssertNotEqual(model.session.stage, .emotionDisclosure)
        let response = model.session.messages.last?.content ?? ""
        for forbidden in ["特别期待会有效", "具体的时刻或想法", "具体的调整过程或细节", "让这种挫败感特别明显"] {
            XCTAssertFalse(response.contains(forbidden))
        }
        XCTAssertFalse(response.contains("身体上有没有"))
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    @MainActor
    func testSeveralDaysWithoutEffectMovesToBodyInsteadOfAnotherPromptDetail() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: RepetitiveTechnicalProbeGenerator()
        )
        model.session.stage = .emotionDisclosure
        model.session.messages = [
            ChatMessage(role: .user, content: "我在准备投稿论文，卡在开发环节，觉得自己很拖延"),
            ChatMessage(role: .assistant, content: "是没开始，还是在做却很难推进？"),
            ChatMessage(role: .user, content: "在做了，很难推进"),
            ChatMessage(role: .assistant, content: "卡在哪里？"),
            ChatMessage(role: .user, content: "聊天机器人一直很难调到想要的效果"),
            ChatMessage(role: .assistant, content: "具体哪里？"),
            ChatMessage(role: .user, content: "调 Prompt 怎么调整都有些不对劲"),
            ChatMessage(role: .assistant, content: "继续说说。"),
        ]
        model.draft = "一直持续好几天都没有效果，就很想停下来"

        model.send()
        await waitForModelIdle(model)

        XCTAssertNotEqual(model.session.stage, .emotionDisclosure)
        let response = model.session.messages.last?.content ?? ""
        XCTAssertFalse(response.contains("身体上有没有"))
        XCTAssertFalse(response.contains("具体的地方"))
        XCTAssertFalse(response.contains("特别难受"))
        XCTAssertFalse(response.contains("想停下来") && response.contains("一瞬间"))
    }

    @MainActor
    func testClearTechnicalGuidanceNeedIsAcceptedWithoutFurtherSpecification() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .selfJudgment
        model.session.context.eventDescription = "Prompt 调整多日仍没有效果"
        model.session.context.emotions = ["挫败"]
        model.session.messages = [
            ChatMessage(role: .user, content: "我一直在调 Prompt，但好几天都没有效果"),
            ChatMessage(role: .assistant, content: "这让你最担心什么？"),
            ChatMessage(role: .user, content: "我太累了，也不知道怎么改善"),
            ChatMessage(role: .assistant, content: "现在最需要什么支持？"),
        ]
        model.draft = "一个比较明确的专业指导"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderGrounding)
        XCTAssertFalse(model.session.messages.last?.content.contains("最想从他那里获得什么") == true)
        XCTAssertFalse(model.session.messages.last?.content.contains("最先会帮你解决哪个具体问题") == true)
    }

    @MainActor
    func testDisclosureMovesOnAfterProgressMeaningAnswer() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .selfJudgment
        model.session.hasAskedProgressMeaningQuestion = true
        model.session.hasAskedPersonalMeaningQuestion = true
        model.session.context.eventDescription = "应用调试多日仍没有稳定进展"
        model.session.context.emotions = ["焦虑"]
        model.session.context.contextualConstraints = ["投稿时间紧"]
        model.session.bodyExplorationCompleted = true
        model.session.structuredDisclosureAssistantTurns = 3
        model.draft = "都有，我既怕赶不上，也担心最后做不好"

        model.send()
        await waitForModelIdle(model)

        XCTAssertFalse([
            ReflectionState.eventDisclosure, .emotionDisclosure, .bodilyResponse,
            .selfJudgment, .contextDisclosure,
        ].contains(model.session.stage))
        XCTAssertTrue(model.session.personalMeaningExplorationCompleted)
        XCTAssertEqual(model.session.context.personalMeaning, "都有，我既怕赶不上，也担心最后做不好")
    }

    @MainActor
    func testVisibleTurnAllowsOnlyOneQuestionAcrossBothFields() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: TwoVisibleQuestionsGenerator()
        )
        model.begin()
        model.draft = "我今天想聊聊论文的事"

        model.send()
        await waitForModelIdle(model)

        let response = model.session.messages.last?.content ?? ""
        XCTAssertEqual(response.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(response.contains("你今天还好吗"))
    }

    @MainActor
    func testDisclosureClosesIntoTenderGroundingBeforeAutomaticTracking() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .contextDisclosure
        model.session.workflowPhase = .structuredDisclosure

        model.skipCurrentDisclosure()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderGrounding)
        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "tender_grounding_presented" })
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "tracking_review_opened_automatically" })
        XCTAssertFalse(model.session.messages.contains { $0.content == "这次先不使用记录" })
    }

    @MainActor
    func testConfirmedTenderGroundingAutomaticallyFoldsTrackingIntoContextSummary() async throws {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        let pending = workflowTrackingCue()
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.trackingCues = [pending]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertNil(model.session.pendingTrackingCueID)
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertTrue(model.session.trackingReviewCompleted)
        XCTAssertTrue(model.session.tenderGroundingConfirmed)
        let actions = model.session.studyEvents.map(\.action)
        let tenderIndex = try XCTUnwrap(actions.firstIndex(of: "tender_grounding_confirmed"))
        let trackingIndex = try XCTUnwrap(actions.firstIndex(of: "tracking_review_started"))
        let summaryIndex = try XCTUnwrap(actions.firstIndex(of: "context_confirmation_presented"))
        XCTAssertLessThan(tenderIndex, trackingIndex)
        XCTAssertLessThan(trackingIndex, summaryIndex)
        XCTAssertFalse(model.session.messages.contains { $0.role == .user && $0.content.contains("使用记录") })
        XCTAssertNil(model.session.card)
    }

    @MainActor
    func testTenderSummaryParaphrasesFirstPersonWorryInsteadOfStitchingItIntoSecondPerson() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .contextDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.bodyExplorationCompleted = true
        model.session.personalMeaningExplorationCompleted = true
        model.session.context.eventDescription = "论文还有两个星期截止，但我已经两天没写了。我觉得自己特别懒，也很没用。"
        model.session.context.emotions = ["焦虑"]
        model.session.context.selfJudgment = "我觉得自己特别懒，也很没用"
        model.session.context.personalMeaning = "我主要怕写得很差，最后投稿被拒。"
        model.draft = "暂时没有别的了"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(reply.contains("也让你担心我主要怕"))
        XCTAssertFalse(reply.contains("我已经两天没写"))
        XCTAssertFalse(reply.contains("自己特别懒，也很没用"))
        XCTAssertFalse(reply.contains("感受包括"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    @MainActor
    func testRecurringRelationshipConflictIsNotReducedToOneIncidentOrPreparation() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.context.eventDescription = "我和谈了三年的人刚分手一周"
        model.session.context.emotions = ["伤心"]
        model.session.context.selfJudgment = "我不够体贴"
        model.session.context.personalContributions = ["吵架的时候没有沟通"]
        model.session.messages = [
            ChatMessage(role: .user, content: "异地期间经常会吵架，不止是那一次"),
        ]
        model.draft = "不止是那一次吧，经常会吵架"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(reply.contains("后悔的是那一次"))
        XCTAssertFalse(reply.contains("准备可以在下次补上"))
        XCTAssertFalse(reply.contains("你这次说到的是"))
        XCTAssertFalse(reply.contains("感受包括"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    @MainActor
    func testDescriptiveLowConfidenceTrackingCueDoesNotBecomeAStressHypothesis() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        let pending = cue(
            "最近 4/7 天有步数记录，覆盖有限",
            relevance: .notReviewed,
            source: .healthSteps,
            metric: .steps,
            strength: .descriptiveOnly,
            confidence: .low
        )
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.trackingCues = [pending]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertTrue(model.session.trackingReviewCompleted)
        XCTAssertTrue(model.session.trackingReviewUnavailable)
        XCTAssertFalse(model.session.messages.contains { $0.content.contains("压力") })
        XCTAssertNil(model.session.card)
    }

    @MainActor
    func testTrackingFallbackUsesConcreteDifferencesAndConnectsThemTentativelyToDisclosure() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.context.eventDescription = "组会上收到导师批评"
        model.session.context.emotions = ["羞愧"]
        model.session.trackingCues = [workflowTrackingCue()]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(reply.contains("睡眠"))
        XCTAssertFalse(reply.localizedCaseInsensitiveContains("HRV"))
        XCTAssertTrue(reply.contains("没有充分恢复") || reply.contains("可用的精力"))
        XCTAssertTrue(reply.contains("更难"))
        XCTAssertFalse(reply.contains("活动量和身体状态与平时有些不同"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertTrue(model.session.trackingReviewCompleted)
        XCTAssertNil(model.session.card)
    }

    @MainActor
    func testUnalignedTrackingChangesDoNotBecomeAStressHypothesis() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.context.eventDescription = "实验结果分析一直没有推进"
        model.session.context.emotions = ["着急"]
        model.session.trackingCues = [
            workflowTrackingCue(metric: .steps, source: .healthSteps, difference: -720),
            workflowTrackingCue(metric: .heartRateVariability, source: .healthHRV, difference: -4),
            workflowTrackingCue(metric: .calendarLoad, source: .calendarLoad, difference: -1),
        ]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(reply.contains("运动量"))
        XCTAssertFalse(reply.localizedCaseInsensitiveContains("HRV"))
        XCTAssertFalse(reply.contains("心率"))
        XCTAssertFalse(reply.contains("睡得更少"))
        XCTAssertFalse(reply.contains("压力较高"))
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertTrue(model.session.trackingReviewCompleted)
        XCTAssertTrue(model.session.trackingReviewUnavailable)
    }

    @MainActor
    func testTrackingConnectsCaregivingChangesToTheConcretePatienceQuestionInOneTurn() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.context.eventDescription =
            "最近一直帮家里处理住院和报销，昨晚妈妈又问已经解释过的问题，我语气很冲"
        model.session.messages = [
            ChatMessage(
                role: .user,
                content: "最近一直在帮家里处理住院和报销。昨晚妈妈又问了一遍，我很不耐烦。"
            ),
        ]
        model.session.trackingCues = [
            workflowTrackingCue(metric: .sleepDuration, source: .healthSleep, difference: -45),
            workflowTrackingCue(metric: .steps, source: .healthSteps, difference: -900),
        ]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(reply.contains("睡眠"))
        XCTAssertFalse(reply.contains("运动量"))
        XCTAssertTrue(reply.contains("没有充分恢复") || reply.contains("可用的精力"))
        XCTAssertTrue(reply.contains("昨晚") || reply.contains("当时") || reply.contains("这件事"))
        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertFalse(reply.contains("造成"))
        XCTAssertFalse(reply.contains("说明你"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    @MainActor
    func testContextSynthesisReplacesEmbeddedExploratoryQuestionWithOneAccuracyCheck() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: ContextSummaryWithEmbeddedQuestionGenerator()
        )
        let pending = workflowTrackingCue()
        model.session.stage = .trackingReview
        model.session.workflowPhase = .trackingReview
        model.session.context.eventDescription = "论文被拒稿了"
        model.session.context.emotions = ["失落"]
        model.session.trackingCues = [pending]
        model.session.pendingTrackingCueID = pending.id
        model.session.pendingTrackingCueIDs = [pending.id]
        model.draft = "拒稿之后确实更没精神，也更难重新开始"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertEqual(model.session.trackingCues.first?.relevance, .relevant)
        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("论文被拒稿"))
        XCTAssertTrue(reply.contains("睡眠比平时短一些") || reply.contains("睡得比平时短一些"))
        XCTAssertTrue(reply.contains("更难应对") || reply.contains("精力"))
        XCTAssertFalse(reply.contains("拒稿之后，你觉得自己和之前相比"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "integrated_narrative_embedded_question_replaced" ||
                    $0.action == "tracking_state_acknowledgment_repaired" ||
                    $0.action == "situational_attribution_presented_after_tracking"
            }
        )
    }

    @MainActor
    func testTrackingAndDisclosureBecomeOneEditableSituationalAttribution() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        let sleep = workflowTrackingCue(metric: .sleepDuration, source: .healthSleep, difference: -50)
        let steps = workflowTrackingCue(metric: .steps, source: .healthSteps, difference: -900)
        model.session.stage = .trackingReview
        model.session.workflowPhase = .trackingReview
        model.session.context.eventDescription = "论文系统反复调整还是没有效果，离截止时间很近"
        model.session.context.emotions = ["烦躁", "焦虑"]
        model.session.context.selfJudgment = "我能力不行"
        model.session.trackingCues = [sleep, steps]
        model.session.pendingTrackingCueID = sleep.id
        model.session.pendingTrackingCueIDs = [sleep.id, steps.id]
        model.session.messages = [
            ChatMessage(role: .user, content: "我一直在调模型，还是没有效果，担心自己能力不行。"),
        ]
        model.draft = "有的"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertNil(model.session.trackingContextLinkResponse)
        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("论文系统反复调整还是没有效果"))
        XCTAssertFalse(reply.contains("有的让"))
        XCTAssertFalse(reply.contains("数据证明"))
        XCTAssertFalse(reply.contains("造成调试失败"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertTrue(model.session.studyEvents.contains {
            $0.action == "context_confirmation_presented"
        })
    }

    @MainActor
    func testCardRequestDuringTenderCannotSkipTrackingAndContextConfirmation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        let pending = cue("最近几晚的睡眠记录比平常短", relevance: .notReviewed)
        model.session.stage = .tenderGrounding
        model.session.workflowPhase = .tenderGroundingConfirmation
        model.session.trackingCues = [pending]
        model.draft = "那就抽张卡吧"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)
        XCTAssertEqual(model.session.stage, .tenderGrounding)
        XCTAssertNil(model.session.card)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "card_selected_uniform_random" })
        XCTAssertTrue(model.session.studyEvents.contains {
            $0.action == "card_request_deferred_until_tender_confirmation"
        })
    }

    @MainActor
    func testTrackingConnectionRequiresIntegratedContextConfirmationBeforeCardInvitation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .trackingReview
        model.session.workflowPhase = .trackingReview
        let pending = cue("最近几晚的睡眠记录比平常短", relevance: .notReviewed)
        model.session.trackingCues = [pending]
        model.session.pendingTrackingCueID = pending.id
        model.draft = "可能让我当时更难集中注意力"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertTrue(model.session.trackingReviewCompleted)
        XCTAssertTrue(model.session.trackingContextLinkCompleted)
        XCTAssertEqual(model.session.trackingContextLinkResponse, "可能让我当时更难集中注意力")
        XCTAssertEqual(model.session.messages.last(where: { $0.role == .user })?.content, "可能让我当时更难集中注意力")
        XCTAssertEqual(model.session.trackingCues.first?.relevance, .relevant)
        XCTAssertEqual(model.session.context.confirmedTrackingCues.map(\.id), [pending.id])
        XCTAssertEqual(model.session.context.confirmedTrackingInsights?.first?.observation, "最近几晚的睡眠记录比平常短")
        XCTAssertNil(model.session.pendingTrackingCueID)
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "tracking_connection_healthSleep_relevant_in_dialogue"
            }
        )
        XCTAssertFalse(model.session.contextSummaryConfirmed)
        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action == "card_draw_invitation_presented_after_tracking"
            }
        )
        XCTAssertFalse(
            model.session.messages.last(where: { $0.role == .assistant })?.content.contains("抽卡") == true
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "context_confirmation_presented"
            }
        )

        model.draft = "符合"
        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(model.session.contextSummaryConfirmed)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_draw_invitation_presented"
            }
        )
        XCTAssertTrue(
            model.session.messages.last(where: { $0.role == .assistant })?.content.contains("抽卡") == true
        )
    }

    @MainActor
    func testUserSuppliedEventDateAnchorsTrackingWindowLocally() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.begin()
        model.draft = "7月20日组会上发生了一件让我很难受的事"

        model.send()
        await waitForModelIdle(model)

        let calendar = Calendar.current
        XCTAssertTrue(model.session.eventDateIsUserSpecified)
        XCTAssertEqual(calendar.component(.month, from: model.session.context.eventDate), 7)
        XCTAssertEqual(calendar.component(.day, from: model.session.context.eventDate), 20)
    }

    @MainActor
    func testTrackingBundleStoresOnlyPerDomainUserConfirmedRelevance() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .trackingReview
        model.session.workflowPhase = .trackingReview
        let sleep = cue("睡眠比个人基线少 42 分钟", relevance: .notReviewed)
        let schedule = cue(
            "日程占用比个人基线多 65 分钟",
            relevance: .notReviewed,
            source: .calendarLoad,
            metric: .calendarLoad
        )
        let activity = cue(
            "步数比个人基线少 1200 步",
            relevance: .notReviewed,
            source: .healthSteps,
            metric: .steps
        )
        let heart = cue(
            "静息心率比个人基线高 3.2 bpm",
            relevance: .notReviewed,
            source: .healthHeartRate,
            metric: .restingHeartRate
        )
        model.session.trackingCues = [sleep, schedule, activity, heart]
        model.session.pendingTrackingCueIDs = [sleep.id, schedule.id, activity.id, heart.id]
        model.session.pendingTrackingCueID = sleep.id
        model.draft = "睡眠和日程相关，活动不相关，心率不确定；睡眠和日程可能让我更累一些"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.trackingCues.map(\.relevance), [
            .relevant, .relevant, .irrelevant, .uncertain,
        ])
        XCTAssertEqual(Set(model.session.context.confirmedTrackingCues.map(\.id)), Set([sleep.id, schedule.id]))
        XCTAssertEqual(model.session.context.confirmedTrackingInsights?.count, 2)
        XCTAssertTrue(model.session.pendingTrackingCueIDs.isEmpty)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertEqual(
            model.session.trackingContextLinkResponse,
            "睡眠和日程相关，活动不相关，心率不确定；睡眠和日程可能让我更累一些"
        )
    }

    @MainActor
    func testNonAdjacentRepeatedAssistantReplyIsReplaced() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: RepeatedDialogueGenerator()
        )
        model.begin()
        model.draft = "昨天我在做一道算法题"
        model.send()
        await waitForModelIdle(model)
        model.draft = "我做到一半卡住了"
        model.send()
        await waitForModelIdle(model)

        let repeatedCount = model.session.messages.filter {
            $0.role == .assistant && $0.content.contains("固定重复回答标记")
        }.count
        XCTAssertEqual(repeatedCount, 1)
        XCTAssertFalse(model.session.messages.last?.content.contains("固定重复回答标记") == true)
    }

    @MainActor
    func testGlobalSelfJudgmentIsSeparatedFromConcreteProgressBeforeMoreTaskQuestions() async {
        let model = ReflectionViewModel(
            analyzer: SelfEvaluationAnalyzer(),
            dialogueGenerator: GoalEchoingDialogueGenerator()
        )
        model.begin()
        model.draft = "我最近在准备论文，我觉得自己太拖延了"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.context.selfJudgment, "我觉得自己太拖延了")
        let response = model.session.messages.last?.content ?? ""
        XCTAssertEqual(model.session.stage, .selfJudgment)
        XCTAssertTrue(response.contains("最担心"), "response: \(response)")
        XCTAssertFalse(response.contains("最明显的感受"), "response: \(response)")
        XCTAssertFalse(response.contains("拖延是事实"))
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "response_plan_recovered_clarifyPersonalMeaning"
            }
        )
    }

    @MainActor
    func testExplicitRepetitionFeedbackRepairsAndStopsCurrentInquiry() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: GoalEchoingDialogueGenerator()
        )
        model.session.stage = .tenderGrounding
        model.session.context.eventDescription = "Prompt 调了很多天仍然达不到预期"
        model.session.messages = [
            ChatMessage(role: .user, content: "我一直在调整 Prompt"),
            ChatMessage(role: .assistant, content: "具体哪里需要帮助？"),
        ]
        model.draft = "我觉得这个问题有些重复了"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderGrounding)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "conversation_repetition_flagged_by_user" })
        let response = model.session.messages.last?.content ?? ""
        XCTAssertTrue(response.contains("你说得对"))
        XCTAssertTrue(response.contains("问题重复了"))
        XCTAssertTrue(response.contains("不再追着问"))
        XCTAssertFalse(response.contains("brief direct repair"))
    }

    @MainActor
    func testRepeatedLowInformationAnswersCloseDisclosureInsteadOfProbingAgain() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.stage = .selfJudgment
        model.session.context.eventDescription = "应用一直调不好，实验无法开始"
        model.session.context.selfJudgment = "我太拖延了"
        model.session.messages = [
            ChatMessage(role: .user, content: "我连续调了很多天但没有稳定进展"),
            ChatMessage(role: .assistant, content: "你会怎么评价自己？"),
            ChatMessage(role: .user, content: "不知道"),
            ChatMessage(role: .assistant, content: "还有什么想法？"),
        ]
        model.draft = "不清楚"

        model.send()
        await waitForAsyncWork()

        XCTAssertFalse([ReflectionState.eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure].contains(model.session.stage))
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "repeated_low_information_answers" })
    }
}

final class SelfTrackingAnalysisTests: XCTestCase {
    func testTrackingRefreshPolicyRefreshesAnEmptyFreshSessionEvenWithOldTimestamp() {
        XCTAssertTrue(
            TrackingRefreshPolicy.shouldRefresh(
                sessionCueCount: 0,
                refreshedAt: .now
            )
        )
        XCTAssertTrue(
            TrackingRefreshPolicy.shouldRefresh(
                sessionCueCount: 3,
                refreshedAt: nil
            )
        )
        XCTAssertFalse(
            TrackingRefreshPolicy.shouldRefresh(
                sessionCueCount: 3,
                refreshedAt: .now
            )
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ offset: Int, from reference: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
    }

    private func analyze(
        metric: TrackingMetric = .sleepDuration,
        points: [TrackingDataPoint],
        reference: Date
    ) async throws -> TrackingInsight {
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let result = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(dailyMetrics: [metric: points], provenance: [:])
        )
        return try XCTUnwrap(result.insights.first)
    }

    func testMissingDaysAreNotTreatedAsZero() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (-6...0).map { offset in
            TrackingDataPoint(
                date: date(offset, from: reference),
                value: offset == -3 ? nil : 8,
                count: offset == -3 ? 0 : 1
            )
        }

        let insight = try await analyze(points: points, reference: reference)

        XCTAssertEqual(insight.validSampleCount, 6)
        XCTAssertEqual(insight.recentMedian, 8)
        XCTAssertTrue(insight.limitations.contains { $0.contains("缺少 1 天") })
    }

    func testInsufficientHistoryIsDescriptiveOnly() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 7.5, count: 1)
        }

        let insight = try await analyze(points: points, reference: reference)

        XCTAssertEqual(insight.strength, .descriptiveOnly)
        XCTAssertNil(insight.baselineMedian)
        XCTAssertNil(insight.absoluteDifference)
    }

    func testSufficientHistoryEnablesPersonalBaselineComparison() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 8, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 7, count: 1)
        }

        let insight = try await analyze(points: baseline + recent, reference: reference)

        XCTAssertNotEqual(insight.strength, .descriptiveOnly)
        XCTAssertEqual(insight.baselineMedian, 8)
        XCTAssertEqual(insight.recentMedian, 7)
        XCTAssertEqual(insight.absoluteDifference, -1)
    }

    func testFiveOfSevenRecentNightsWithTwentySevenBaselineDaysRemainEligible() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7)
            .filter { $0 != -20 }
            .map {
                TrackingDataPoint(date: date($0, from: reference), value: 8, count: 1)
            }
        let recent = (-4...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 6.9, count: 1)
        }

        let insight = try await analyze(points: baseline + recent, reference: reference)

        XCTAssertEqual(insight.validSampleCount, 5)
        XCTAssertEqual(insight.expectedSampleCount, 7)
        XCTAssertEqual(insight.baselineMedian, 8)
        XCTAssertNotEqual(insight.strength, .descriptiveOnly)
        XCTAssertEqual(insight.confidence, .moderate)
        XCTAssertTrue(insight.limitations.contains { $0.contains("缺少 2 天") })
    }

    func testRobustMedianIsNotDominatedBySingleOutlier() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        var baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 8, count: 1)
        }
        baseline[5] = TrackingDataPoint(date: baseline[5].date, value: 100, count: 1)
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 8, count: 1)
        }

        let insight = try await analyze(points: baseline + recent, reference: reference)

        XCTAssertEqual(insight.baselineMedian, 8)
        XCTAssertEqual(insight.medianAbsoluteDeviation, 0)
    }

    func testRestingHeartRateNeverProducesStressClaim() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 65, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 75, count: 1)
        }

        let insight = try await analyze(
            metric: .restingHeartRate,
            points: baseline + recent,
            reference: reference
        )

        XCTAssertFalse(insight.neutralObservation.contains("压力很大"))
        XCTAssertFalse(insight.neutralObservation.contains("焦虑"))
        XCTAssertTrue(insight.neutralObservation.contains("不能说明原因"))
    }

    func testAlignedSleepAndCardiovascularSignalsProduceMeasurementFreeLoadCue() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        func points(baseline: Double, recent: Double) -> [TrackingDataPoint] {
            (-34 ... -7).map {
                TrackingDataPoint(date: date($0, from: reference), value: baseline, count: 1)
            } + (-6...0).map {
                TrackingDataPoint(date: date($0, from: reference), value: recent, count: 1)
            }
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let analysis = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [
                    .sleepDuration: points(baseline: 8, recent: 6.8),
                    .restingHeartRate: points(baseline: 64, recent: 72),
                    .heartRateVariability: points(baseline: 50, recent: 38),
                    .steps: points(baseline: 8_000, recent: 10_000),
                ],
                provenance: [:]
            )
        )

        let inference = analysis.contextualLoadInference()

        XCTAssertEqual(inference.state, .elevated)
        XCTAssertEqual(inference.confidence, .high)
        XCTAssertEqual(inference.activation, .possiblyElevated)
        XCTAssertEqual(inference.energy, .possiblyReduced)
        XCTAssertTrue(inference.hasDialogueCue)
        XCTAssertTrue(inference.dialogueHypothesis?.contains("可能承受着比平时更多的压力") == true)
        XCTAssertFalse(inference.dialogueHypothesis?.localizedCaseInsensitiveContains("HRV") == true)
        XCTAssertFalse(inference.dialogueHypothesis?.contains("心率") == true)
        XCTAssertFalse(inference.dialogueHypothesis?.contains("睡眠") == true)
        XCTAssertTrue(inference.supportingMetrics.contains(.heartRateVariability))
        XCTAssertTrue(inference.alternativeExplanations.contains { $0.contains("活动量增加") })
    }

    func testSingleCardiovascularChangeCannotBecomePressureOrEmotionCue() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 50, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 35, count: 1)
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let analysis = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [.heartRateVariability: baseline + recent],
                provenance: [:]
            )
        )

        let inference = analysis.contextualLoadInference()

        XCTAssertEqual(inference.state, .usualRange)
        XCTAssertEqual(inference.confidence, .low)
        XCTAssertEqual(inference.activation, .unknown)
        XCTAssertEqual(inference.energy, .unknown)
        XCTAssertNil(inference.dialogueHypothesis)
        XCTAssertFalse(inference.hasDialogueCue)
    }

    func testSleepOnlyProducesRecoveryCueInsteadOfSpecificEmotion() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 8, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 6.8, count: 1)
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let analysis = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [.sleepDuration: baseline + recent],
                provenance: [:]
            )
        )

        let inference = analysis.contextualLoadInference()

        XCTAssertEqual(inference.state, .possibleReducedRecovery)
        XCTAssertEqual(inference.activation, .unknown)
        XCTAssertEqual(inference.energy, .possiblyReduced)
        XCTAssertTrue(inference.dialogueHypothesis?.contains("恢复") == true)
        XCTAssertFalse(inference.dialogueHypothesis?.contains("焦虑") == true)
        XCTAssertFalse(inference.dialogueHypothesis?.contains("难过") == true)
    }

    func testScreenTimeInsightUsesQuestionInsteadOfAvoidanceConclusion() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 2, count: 1)
        }

        let insight = try await analyze(metric: .screenTime, points: points, reference: reference)

        XCTAssertFalse(insight.suggestedReflectionQuestion.contains("逃避"))
        XCTAssertTrue(insight.suggestedReflectionQuestion.hasSuffix("？"))
    }

    func testHealthSourcePriorityIsDeterministicAndPreventsSourceMixing() {
        let candidates = [
            TrackingSourceCandidate(bundleIdentifier: "watch.source", distinctDayCount: 6, sampleCount: 12),
            TrackingSourceCandidate(bundleIdentifier: "phone.source", distinctDayCount: 5, sampleCount: 40),
            TrackingSourceCandidate(bundleIdentifier: "duplicate.source", distinctDayCount: 6, sampleCount: 8),
        ]

        let selected = HealthSourcePriorityPolicy().preferredBundleIdentifier(from: candidates)

        XCTAssertEqual(selected, "watch.source")
    }

    func testDuplicateRecordsOnOneDayDoNotInflateCoverage() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let sameDay = date(0, from: reference)
        let points = [
            TrackingDataPoint(date: sameDay, value: 6, count: 1),
            TrackingDataPoint(date: sameDay.addingTimeInterval(3_600), value: 8, count: 1),
            TrackingDataPoint(date: sameDay.addingTimeInterval(7_200), value: nil, count: 0),
            TrackingDataPoint(date: date(-1, from: reference), value: .nan, count: 1),
        ]

        let insight = try await analyze(points: points, reference: reference)

        XCTAssertEqual(insight.validSampleCount, 1)
        XCTAssertEqual(insight.recentMedian, 7)
        XCTAssertTrue(insight.limitations.contains { $0.contains("缺少 6 天") })
    }

    func testConcreteBaselineDifferencesAreProducedAcrossCoreDomains() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        func points(baseline: Double, recent: Double) -> [TrackingDataPoint] {
            (-34 ... -7).map {
                TrackingDataPoint(date: date($0, from: reference), value: baseline, count: 1)
            } + (-6...0).map {
                TrackingDataPoint(date: date($0, from: reference), value: recent, count: 1)
            }
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let result = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [
                    .sleepDuration: points(baseline: 8, recent: 7),
                    .calendarLoad: points(baseline: 2, recent: 5),
                    .steps: points(baseline: 8_000, recent: 6_000),
                    .restingHeartRate: points(baseline: 64, recent: 70),
                    .heartRateVariability: points(baseline: 50, recent: 40),
                ],
                provenance: [:]
            )
        )

        let observations = Dictionary(uniqueKeysWithValues: result.insights.map {
            ($0.metric, $0.neutralObservation)
        })
        XCTAssertTrue(try XCTUnwrap(observations[.sleepDuration]).contains("60 分钟"))
        XCTAssertTrue(try XCTUnwrap(observations[.calendarLoad]).contains("180 分钟"))
        XCTAssertTrue(try XCTUnwrap(observations[.steps]).contains("2000 步"))
        XCTAssertTrue(try XCTUnwrap(observations[.restingHeartRate]).contains("6.0 bpm"))
        XCTAssertTrue(try XCTUnwrap(observations[.heartRateVariability]).contains("10.0 ms"))
        for observation in observations.values {
            XCTAssertTrue(observation.contains("不能说明") || observation.contains("不是心理压力"))
        }
    }

    func testBackgroundSelectionRepresentsSeveralDomainsBeforeSecondMetric() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        func points(baseline: Double, recent: Double) -> [TrackingDataPoint] {
            (-34 ... -7).map {
                TrackingDataPoint(date: date($0, from: reference), value: baseline, count: 1)
            } + (-6...0).map {
                TrackingDataPoint(date: date($0, from: reference), value: recent, count: 1)
            }
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let result = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [
                    .sleepDuration: points(baseline: 8, recent: 7),
                    .sleepTiming: points(baseline: 23, recent: 0),
                    .calendarLoad: points(baseline: 2, recent: 4),
                    .steps: points(baseline: 8_000, recent: 6_000),
                    .restingHeartRate: points(baseline: 64, recent: 70),
                    .heartRateVariability: points(baseline: 50, recent: 40),
                ],
                provenance: [:]
            )
        )

        let firstFour = result.rankedBackgroundInsights(maximumCount: 4)

        XCTAssertEqual(firstFour.count, 4)
        XCTAssertEqual(Set(firstFour.map { $0.metric.selfTrackingDomain }).count, 4)
        XCTAssertEqual(
            Set(firstFour.map { $0.metric.selfTrackingDomain }),
            Set([.sleep, .schedule, .activity, .cardiovascular])
        )
    }

    func testBackgroundSummaryKeepsMultipleMeasurementsNonCausal() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        func points(baseline: Double, recent: Double) -> [TrackingDataPoint] {
            (-34 ... -7).map {
                TrackingDataPoint(date: date($0, from: reference), value: baseline, count: 1)
            } + (-6...0).map {
                TrackingDataPoint(date: date($0, from: reference), value: recent, count: 1)
            }
        }
        let analyzer = DeterministicSelfTrackingAnalyzer(calendar: calendar)
        let result = try await analyzer.analyze(
            eventDate: reference,
            availableData: SelfTrackingDataset(
                dailyMetrics: [
                    .sleepDuration: points(baseline: 8, recent: 7),
                    .calendarLoad: points(baseline: 2, recent: 5),
                    .steps: points(baseline: 8_000, recent: 6_000),
                ],
                provenance: [:]
            )
        )

        let summary = result.backgroundContextSummary(maximumCount: 3)

        XCTAssertEqual(summary.selectedInsights.count, 3)
        XCTAssertEqual(Set(summary.representedDomains), Set([.sleep, .schedule, .activity]))
        XCTAssertTrue(summary.boundaryStatement.contains("不确定的情境线索"))
        XCTAssertTrue(summary.boundaryStatement.contains("不能证明行为原因、心理状态或责任"))
        XCTAssertTrue(summary.boundaryStatement.contains("由用户确认"))
        XCTAssertTrue(summary.limitations.contains { $0.contains("不能合并成单一结论") })
        XCTAssertFalse(summary.promptText.contains("导致"))

        let cues = result.insights.map { insight in
            let source: TrackingSource = switch insight.metric {
            case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity: .healthSleep
            case .calendarLoad: .calendarLoad
            case .steps: .healthSteps
            case .restingHeartRate: .healthHeartRate
            case .heartRateVariability: .healthHRV
            case .screenTime, .weather: .healthSteps
            }
            return TrackingCue(
                source: source,
                observation: insight.neutralObservation,
                insight: insight
            )
        }
        XCTAssertEqual(cues.rankedBackgroundCues(maximumCount: 3).count, 3)
        XCTAssertEqual(cues.backgroundContextSummary(maximumCount: 3).observations.count, 3)
    }

    func testSleepTimingDifferenceUsesCircularClockDistance() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 23.5, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 0.5, count: 1)
        }

        let insight = try await analyze(
            metric: .sleepTiming,
            points: baseline + recent,
            reference: reference
        )

        XCTAssertEqual(insight.absoluteDifference, 1)
        XCTAssertNil(insight.relativeDifference)
        XCTAssertTrue(insight.neutralObservation.contains("相差约 60 分钟（更晚）"))
        XCTAssertFalse(insight.neutralObservation.contains("23.0 小时"))
    }

    func testSleepWakeTimeUsesCircularClockDistanceAndContinuityStaysNonDiagnostic() async throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let baseline = (-34 ... -7).map {
            TrackingDataPoint(date: date($0, from: reference), value: 6.5, count: 1)
        }
        let recent = (-6...0).map {
            TrackingDataPoint(date: date($0, from: reference), value: 7.5, count: 1)
        }
        let wakeInsight = try await analyze(
            metric: .sleepWakeTime,
            points: baseline + recent,
            reference: reference
        )
        XCTAssertEqual(wakeInsight.absoluteDifference, 1)
        XCTAssertTrue(wakeInsight.neutralObservation.contains("醒来时间中位数约为 07:30"))
        XCTAssertTrue(wakeInsight.neutralObservation.contains("更晚"))

        let continuityInsight = try await analyze(
            metric: .sleepContinuity,
            points: (-34 ... -7).map {
                TrackingDataPoint(date: date($0, from: reference), value: 0.92, count: 1)
            } + (-6...0).map {
                TrackingDataPoint(date: date($0, from: reference), value: 0.78, count: 1)
            },
            reference: reference
        )
        XCTAssertTrue(continuityInsight.neutralObservation.contains("78%"))
        XCTAssertTrue(continuityInsight.neutralObservation.contains("不等同于主观睡眠质量"))
        XCTAssertFalse(continuityInsight.neutralObservation.contains("焦虑"))
    }
}

final class ReflectionCardTests: XCTestCase {
    func testAllProjectiveCardImagesAreBundled() {
        let cards = CardService().allCards
        XCTAssertEqual(cards.count, 22)
        XCTAssertEqual(Set(cards.map(\.imageName)).count, 22)
        XCTAssertTrue(cards.allSatisfy { $0.neutralLabel.hasPrefix("图像卡") })
        XCTAssertTrue(cards.allSatisfy { $0.title != $0.neutralLabel })
        XCTAssertTrue(cards.allSatisfy { !$0.reflectiveThemes.isEmpty })
        XCTAssertTrue(cards.allSatisfy {
            guard let guidance = $0.internalGuidance else { return false }
            return !guidance.coreTension.isEmpty
                && !guidance.tenderLenses.isEmpty
                && !guidance.fierceLenses.isEmpty
                && !guidance.visualAnchors.isEmpty
                && !guidance.possibleDirections.isEmpty
                && !guidance.prohibitedClaims.isEmpty
        })
        XCTAssertTrue(cards.allSatisfy {
            guard let supplement = $0.internalGuidance?.selfCompassion else { return false }
            return !supplement.secondaryDimensions.isEmpty
                && !supplement.selfKindnessCandidates.isEmpty
                && !supplement.commonHumanityCandidates.isEmpty
                && !supplement.mindfulnessCandidates.isEmpty
                && !supplement.candidateQuestion.isEmpty
                && !supplement.activationHint.isEmpty
        })
        XCTAssertEqual(
            Set(cards.compactMap { $0.internalGuidance?.selfCompassion?.primaryDimension }).count,
            SelfCompassionDimension.allCases.count
        )

        for card in cards {
            let url = Bundle.main.url(forResource: card.imageName, withExtension: "png", subdirectory: "Resources/card")
                ?? Bundle.main.url(forResource: card.imageName, withExtension: "png", subdirectory: "card")
                ?? Bundle.main.url(forResource: card.imageName, withExtension: "png")
            XCTAssertNotNil(url, "Missing \(card.imageName).png")
        }
    }

    func testCardSelectionIsLocalAndAcceptsNoRouteInput() {
        let service = CardService()
        let imageNames = Set(service.allCards.map(\.imageName))
        for _ in CompassionRoute.allCases {
            let card = service.draw()
            XCTAssertTrue((0..<22).contains(card.id))
            XCTAssertTrue(imageNames.contains(card.imageName))
        }
    }

    func testGuidanceRequiresImageRealityAndCardTensionIntersection() throws {
        let door = try XCTUnwrap(CardService().allCards.first { $0.title == "半开的门" })
        let matcher = CardGuidanceMatcher()

        let match = matcher.match(
            card: door,
            userImageNarrative: "门外的人快走了，里面的人还扶着门把手。",
            semanticRelations: [
                SemanticRelation(
                    kind: .imageStructure,
                    source: "门仍然半开着，门外的人正在离开",
                    relation: "同时保留",
                    target: "距离和未完成的回应",
                    concepts: [.boundary, .communication],
                    evidence: ["门外的人快走了"],
                    status: .userStated,
                    confidence: 0.9
                ),
                SemanticRelation(
                    kind: .realityStructure,
                    source: "保持距离",
                    relation: "同时留下",
                    target: "尚未完成的沟通",
                    concepts: [.boundary, .communication],
                    evidence: ["一直没有回复对方"],
                    status: .userStated,
                    confidence: 0.9
                )
            ]
        )
        XCTAssertTrue(try XCTUnwrap(match).matchedVisualAnchors.contains("门"))
        XCTAssertTrue(try XCTUnwrap(match).candidateDirections.contains("边界"))
        XCTAssertTrue(try XCTUnwrap(match).candidateDirections.contains("沟通"))
        XCTAssertNotNil(match?.imageRelation)
        XCTAssertNotNil(match?.realityRelation)

        XCTAssertNil(matcher.match(
            card: door,
            userImageNarrative: "门外的人快走了，里面的人还扶着门把手。",
            semanticRelations: [
                SemanticRelation(
                    kind: .imageStructure,
                    source: "门内与门外",
                    relation: "形成",
                    target: "距离",
                    concepts: [.boundary],
                    evidence: ["门外的人快走了"],
                    status: .userStated,
                    confidence: 0.9
                ),
                SemanticRelation(
                    kind: .realityStructure,
                    source: "任务顺序",
                    relation: "需要",
                    target: "重新安排",
                    concepts: [.priority],
                    evidence: ["需要重新排一下"],
                    status: .userStated,
                    confidence: 0.9
                ),
            ]
        ))
    }

    func testDifferentCardsExposeDifferentTenderAndFierceDirectionsAfterIntersection() throws {
        let cards = CardService().allCards
        let door = try XCTUnwrap(cards.first { $0.title == "半开的门" })
        let vessel = try XCTUnwrap(cards.first { $0.title == "裂痕与器皿" })
        let matcher = CardGuidanceMatcher()

        let doorMatch = matcher.match(
            card: door,
            userImageNarrative: "门停在半开的位置，门内外还隔着一段距离",
            semanticRelations: semanticPair(
                image: "门内和门外 保留 一段距离",
                reality: "保护自己 同时留下 尚未完成的沟通",
                concepts: [.boundary, .communication]
            )
        )
        let vesselMatch = matcher.match(
            card: vessel,
            userImageNarrative: "器皿有一道裂痕，旁边的手正在处理裂缝",
            semanticRelations: semanticPair(
                image: "裂痕 已经造成 需要处理的影响",
                reality: "一个具体行为 已经造成 需要修复的影响",
                concepts: [.responsibility, .repair]
            )
        )

        XCTAssertNotNil(doorMatch)
        XCTAssertNotNil(vesselMatch)
        XCTAssertNotEqual(doorMatch?.candidateDirections, vesselMatch?.candidateDirections)
        XCTAssertNotNil(doorMatch?.selectedTenderLensID)
        XCTAssertNotNil(doorMatch?.selectedFierceLensID)
        XCTAssertNotNil(vesselMatch?.selectedTenderLensID)
        XCTAssertNotNil(vesselMatch?.selectedFierceLensID)
        XCTAssertNotEqual(doorMatch?.selectedTenderLensID, vesselMatch?.selectedTenderLensID)
        XCTAssertNotEqual(doorMatch?.selectedFierceLensID, vesselMatch?.selectedFierceLensID)
        XCTAssertNotEqual(door.internalGuidance?.tenderLenses, vessel.internalGuidance?.tenderLenses)
        XCTAssertNotEqual(door.internalGuidance?.fierceLenses, vessel.internalGuidance?.fierceLenses)
    }

    func testSameCardFormsDifferentGuidanceMatchesInDifferentRealityStructures() throws {
        let door = try XCTUnwrap(CardService().allCards.first { $0.title == "半开的门" })
        let matcher = CardGuidanceMatcher()
        let image = SemanticRelation(
            kind: .imageStructure,
            source: "门停在半开的位置",
            relation: "同时保留",
            target: "距离和未完成的回应",
            concepts: [.boundary, .communication],
            evidence: ["门停在半开的位置"],
            status: .userStated,
            confidence: 0.9
        )
        let boundaryMatch = matcher.match(
            card: door,
            userImageNarrative: "门停在半开的位置",
            semanticRelations: [
                image,
                SemanticRelation(
                    kind: .realityStructure,
                    source: "保持距离",
                    relation: "保护",
                    target: "当前承受范围",
                    concepts: [.boundary],
                    evidence: ["我现在需要保持一点距离"],
                    status: .userConfirmed,
                    confidence: 0.9
                ),
            ]
        )
        let communicationMatch = matcher.match(
            card: door,
            userImageNarrative: "门停在半开的位置",
            semanticRelations: [
                image,
                SemanticRelation(
                    kind: .realityStructure,
                    source: "没有回应",
                    relation: "使",
                    target: "沟通仍未完成",
                    concepts: [.communication],
                    evidence: ["我还没有把话说清楚"],
                    status: .userConfirmed,
                    confidence: 0.9
                ),
            ]
        )

        XCTAssertEqual(boundaryMatch?.candidateDirections, ["边界"])
        XCTAssertEqual(communicationMatch?.candidateDirections, ["沟通"])
        XCTAssertNotEqual(boundaryMatch?.realityRelation, communicationMatch?.realityRelation)
        XCTAssertNotNil(boundaryMatch?.selectedTenderLensID)
        XCTAssertNotNil(communicationMatch?.selectedTenderLensID)
    }

    func testLegacyCardGuidanceMatchWithoutSelectedLensIDsStillDecodes() throws {
        let current = CardGuidanceMatch(
            matchedVisualAnchors: ["门"],
            candidateDirections: ["边界"],
            imageRelation: "画面里保留距离",
            realityRelation: "现实中保留距离",
            matchedConcepts: [.boundary],
            selectedTenderLensID: "card:1:tender:0",
            selectedFierceLensID: "card:1:fierce:0",
            selectedSelfCompassionCandidateID: "card:1:self:selfKindness:0"
        )
        let encoded = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "selectedTenderLensID")
        object.removeValue(forKey: "selectedFierceLensID")
        object.removeValue(forKey: "selectedSelfCompassionCandidateID")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CardGuidanceMatch.self, from: legacyData)

        XCTAssertNil(decoded.selectedTenderLensID)
        XCTAssertNil(decoded.selectedFierceLensID)
        XCTAssertNil(decoded.selectedSelfCompassionCandidateID)
    }

    func testCardDeltaPromptUsesTypedBoundaryAndOmitsBaselineFieldsAndPreCardTranscript() {
        var context = ReflectionContext()
        context.eventDescription = "不应在增量输入里重新展开的事件"
        context.emotions = ["不应重新展开的情绪"]
        context.confirmedTrackingInsights = [
            ConfirmedTrackingContext(
                insightID: UUID(),
                observation: "不应重新播报的睡眠观察",
                userInterpretation: "最近比较累",
                relevance: .relevant
            )
        ]
        let drawTime = Date()
        let prompt = ReflectionPromptFactory().dialoguePrompt(
            state: .attributionReflection,
            route: .explore,
            context: context,
            analysis: nil,
            card: nil,
            trackingCues: [],
            promptEvidence: DialoguePromptEvidence(
                narrativeMode: .cardDerivedDelta,
                lockedBaselineNarrative: "已经确认的基础处境",
                cardDerivedDeltaNarrative: "画面关系带来的新增理解",
                matchedImageRelation: "一部分保持距离",
                matchedRealityRelation: "现实中也保留距离",
                confirmedCardMapping: "两种关系可能相似",
                tenderResponse: "当时需要保护承受范围",
                meaningShiftResponse: "开始区分保护和未回应",
                fierceResponse: "愿意把边界说清楚",
                pendingAction: nil,
                cardPhaseStartedAt: drawTime
            ),
            nextQuestionGoal: "write the card-derived delta",
            recentMessages: [
                ChatMessage(
                    role: .user,
                    content: "不应进入增量提示的抽卡前原话",
                    createdAt: drawTime.addingTimeInterval(-10)
                ),
                ChatMessage(
                    role: .user,
                    content: "抽卡后形成的画面关系",
                    createdAt: drawTime.addingTimeInterval(1)
                ),
            ]
        )

        XCTAssertTrue(prompt.user.contains("cardDerivedDelta"))
        XCTAssertTrue(prompt.user.contains("已经确认的基础处境"))
        XCTAssertTrue(prompt.user.contains("画面关系带来的新增理解"))
        XCTAssertTrue(prompt.user.contains("抽卡后形成的画面关系"))
        XCTAssertFalse(prompt.user.contains("不应在增量输入里重新展开的事件"))
        XCTAssertFalse(prompt.user.contains("不应重新展开的情绪"))
        XCTAssertFalse(prompt.user.contains("不应重新播报的睡眠观察"))
        XCTAssertFalse(prompt.user.contains("不应进入增量提示的抽卡前原话"))
    }

    @MainActor
    func testSelectedCardTenderLensProducesDifferentVisibleQuestionFunctions() async throws {
        let cards = CardService().allCards
        let door = try XCTUnwrap(cards.first { $0.title == "半开的门" })
        let vessel = try XCTUnwrap(cards.first { $0.title == "裂痕与器皿" })

        func resumedModel(
            card: ReflectionCard,
            tenderLensIndex: Int,
            imageRelation: String,
            realityRelation: String
        ) -> ReflectionViewModel {
            var saved = ReflectionSession()
            saved.condition = .cardMediated
            saved.stage = .attributionReflection
            saved.workflowPhase = .candidCircumstances
            saved.contextSummaryConfirmed = true
            saved.lockedBaselineNarrative = "已经确认的基础处境。"
            saved.card = card
            saved.cardDisplayState = .displayed
            saved.context.cardInterpretation = imageRelation
            saved.cardMappingConfirmed = true
            saved.cardConfirmedMapping = "两种关系有一个可以修改或拒绝的对应"
            saved.cardLifeConnection = saved.cardConfirmedMapping
            saved.hasUserAuthoredCardConnection = true
            saved.cardGuidanceMatch = CardGuidanceMatch(
                matchedVisualAnchors: card.internalGuidance?.visualAnchors.prefix(1).map { $0 } ?? [],
                candidateDirections: card.internalGuidance?.possibleDirections.prefix(1).map { $0 } ?? [],
                imageRelation: imageRelation,
                realityRelation: realityRelation,
                matchedConcepts: [.boundary],
                selectedTenderLensID: "card:\(card.id):tender:\(tenderLensIndex)",
                selectedFierceLensID: nil,
                selectedSelfCompassionCandidateID: nil
            )
            let model = ReflectionViewModel(
                analyzer: StaticAnalyzer(),
                dialogueGenerator: SelectedTenderLensDialogueGenerator()
            )
            model.resume(
                ResumableReflection(
                    id: saved.id.uuidString,
                    remoteID: nil,
                    session: saved,
                    updatedAt: .now
                )
            )
            return model
        }

        let doorModel = resumedModel(
            card: door,
            tenderLensIndex: 0,
            imageRelation: "门停在半开的位置",
            realityRelation: "现实中也在保留距离"
        )
        let vesselModel = resumedModel(
            card: vessel,
            tenderLensIndex: 0,
            imageRelation: "器皿有一道需要处理的裂痕",
            realityRelation: "现实中有一个具体影响需要面对"
        )
        for _ in 0..<60 {
            let doorHasReply = doorModel.session.messages.contains { $0.role == .assistant }
            let vesselHasReply = vesselModel.session.messages.contains { $0.role == .assistant }
            if doorHasReply && vesselHasReply { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await waitForModelIdle(doorModel)
        await waitForModelIdle(vesselModel)

        let doorQuestion = doorModel.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let vesselQuestion = vesselModel.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(doorQuestion.contains("保持距离"), "door reply: \(doorQuestion)")
        XCTAssertTrue(vesselQuestion.contains("具体影响"), "vessel reply: \(vesselQuestion)")
        XCTAssertNotEqual(doorQuestion, vesselQuestion)
        XCTAssertFalse(doorQuestion.contains("做错一件事"))
        XCTAssertFalse(vesselQuestion.contains("拒绝不等于"))
    }

    func testCardPromptContainsNoDiagnosticMeaning() {
        let card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "靠近与分开之间")
        let prompt = ReflectionPromptFactory().dialoguePrompt(
            state: .cardInterpretation,
            route: .explore,
            context: ReflectionContext(),
            analysis: nil,
            card: card,
            trackingCues: [],
            nextQuestionGoal: "observation",
            recentMessages: []
        )
        XCTAssertTrue(prompt.user.contains("Do not provide a meaning"))
        XCTAssertFalse(prompt.user.localizedCaseInsensitiveContains("avoiding responsibility"))
    }

    func testSelfCompassionDimensionsAreGlobalAndNotAVisibleChecklist() {
        let factory = ReflectionPromptFactory()
        let prompt = factory.dialoguePrompt(
            state: .trackingReview,
            route: .tenderStabilize,
            context: ReflectionContext(),
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "describe the supplied tracking context",
            recentMessages: []
        )
        XCTAssertTrue(prompt.system.contains("Self-kindness"))
        XCTAssertTrue(prompt.system.contains("Common humanity"))
        XCTAssertTrue(prompt.system.contains("Mindfulness"))
        XCTAssertTrue(prompt.system.contains("across the conversation"))
        XCTAssertTrue(prompt.system.contains("candidate context"))
        XCTAssertTrue(prompt.system.contains("final narrative only"))
        let analyzerPrompt = factory.analyzerPrompt(context: ReflectionContext(), messages: [])
        XCTAssertTrue(analyzerPrompt.system.contains("three self-compassion dimensions"))
        XCTAssertTrue(analyzerPrompt.system.contains("evidence-discipline constraints"))
    }

    @MainActor
    func testFirstCardQuestionInvitesAnImageNarrative() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardIntroduction
        model.session.workflowPhase = .cardSelection
        model.drawCard()
        XCTAssertEqual(model.session.stage, .cardIntroduction)
        XCTAssertEqual(model.session.cardDisplayState, .selected)
        XCTAssertFalse(model.session.messages.last?.content.contains("画面里正在发生什么") == true)
        model.cardDidDisplay(cardID: try! XCTUnwrap(model.session.card?.id))
        XCTAssertEqual(model.session.stage, .cardInterpretation)
        let message = model.session.messages.last?.content ?? ""
        XCTAssertTrue(message.contains("看到这张牌，你觉得画面里正在发生什么？"))
        XCTAssertFalse(message.contains("第一眼停在哪里"))
        XCTAssertNotNil(model.session.cardDrawRecord)
    }

    @MainActor
    func testCardInterpretationIsStoredVerbatim() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.draft = "我先看到两个人之间的一段距离"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.context.cardInterpretation, "我先看到两个人之间的一段距离")
    }

    func testCardPromptFollowsUserNarrativeAndOmitsStoredTheme() {
        var context = ReflectionContext()
        context.cardInterpretation = "这个人想往前走，但还不知道选哪边"
        let card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "STORED_THEME_MUST_NOT_APPEAR")
        let prompt = ReflectionPromptFactory().dialoguePrompt(
            state: .attributionReflection,
            route: .explore,
            context: context,
            analysis: nil,
            card: card,
            trackingCues: [],
            nextQuestionGoal: "continue the user's story",
            recentMessages: []
        )
        XCTAssertTrue(prompt.user.contains("这个人想往前走，但还不知道选哪边"))
        XCTAssertFalse(prompt.user.contains("STORED_THEME_MUST_NOT_APPEAR"))
    }

    func testCardCandorIsUserLedAndActionsUseOnlyCareRepairOrChange() {
        var context = ReflectionContext()
        context.cardInterpretation = "女士正在安抚狗"
        let candor = ReflectionPromptFactory().dialoguePrompt(
            state: .attributionReflection,
            route: .explore,
            context: context,
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "card-mediated candid question",
            recentMessages: []
        ).system

        XCTAssertTrue(candor.contains("interpretive lens"))
        XCTAssertTrue(candor.contains("concrete fierce focus"))
        XCTAssertTrue(candor.contains("tracking data as evidence"))
        XCTAssertFalse(candor.contains("OPTIONAL PRACTICE:"))

        let action = ReflectionPromptFactory().dialoguePrompt(
            state: .actionSelection,
            route: .explore,
            context: context,
            analysis: nil,
            card: nil,
            trackingCues: [],
            nextQuestionGoal: "offer the authorized practice",
            recentMessages: []
        ).system
        XCTAssertTrue(action.contains("care, repair, protect, or change"))
        XCTAssertTrue(action.contains("OPTIONAL PRACTICE:"))
    }

    func testNoRouteSpecificCardQuestionBeforeUserNarrative() {
        let card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "边界")
        let prompt = ReflectionPromptFactory().dialoguePrompt(
            state: .cardInterpretation,
            route: .protect,
            context: ReflectionContext(),
            analysis: nil,
            card: card,
            trackingCues: [],
            nextQuestionGoal: "first card narrative",
            recentMessages: []
        )
        XCTAssertFalse(prompt.system.contains("有什么需要被挡在外面"))
        XCTAssertTrue(prompt.system.contains("看到这张牌，你觉得画面里正在发生什么？"))
    }

    func testCardFollowUpContainsOnlyOneNarrativeQuestion() {
        var context = ReflectionContext()
        context.cardInterpretation = "一个人想往前走，但还没有决定方向"
        let card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        for route in CompassionRoute.allCases {
            let system = ReflectionPromptFactory().dialoguePrompt(
                state: .attributionReflection,
                route: route,
                context: context,
                analysis: nil,
                card: card,
                trackingCues: [],
                nextQuestionGoal: "one narrative question",
                recentMessages: []
            ).system
            XCTAssertTrue(system.contains("completed their initial image story"), "route: \(route)")
            XCTAssertTrue(system.contains("do not add another image question"), "route: \(route)")
            XCTAssertTrue(system.localizedCaseInsensitiveContains("First deepen the real situation around that connection"), "route: \(route)")
        }
    }

    @MainActor
    func testCardDescriptionAndInterpretationCanBeStoredTogether() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "不应主导")
        model.draft = "这个人想往前走，但好像还不知道该选哪边"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.context.cardInterpretation, "这个人想往前走，但好像还不知道该选哪边")
        XCTAssertEqual(model.session.stage, .cardInterpretation)
        XCTAssertTrue(model.session.hasAskedCardProjectionFollowUp)

        model.draft = "我说不准，像是他还不相信其中任何一边"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        XCTAssertTrue(model.session.context.cardInterpretation?.contains("还不相信") == true)
    }

    @MainActor
    func testNoMoreCardDescriptionMovesToOptionalRealityConnectionWithoutSettingCardAside() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        model.draft = "画面里一个人站在两条路之间"

        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.stage, .cardInterpretation)
        XCTAssertTrue(model.session.hasAskedCardProjectionFollowUp)

        model.draft = "没有了"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        XCTAssertFalse(model.session.cardWasSetAside)
        XCTAssertNotNil(model.session.card)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_association_completed_without_more_detail" })
        XCTAssertFalse(model.isTyping)
    }

    @MainActor
    func testExplicitlyMissingCardConnectionExitsToCircumstancesWithoutAnotherProbe() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "不同建议和有限时间构成了已经确认的现实背景。"
        model.session.card = CardService().allCards.first { $0.title == "未定之步" }
        model.session.cardDrawRecord = CardDrawRecord(
            sessionID: model.session.id,
            cardID: "1",
            drawnAt: .now,
            routeBeforeDraw: .tenderStabilize
        )
        model.session.context.cardInterpretation = "画面里一个人站在两条路之间"
        model.draft = "和我的事没有联系"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardWasSetAside)
        XCTAssertTrue(model.session.cardConnectionUnavailable)
        XCTAssertNotNil(model.session.card)
        XCTAssertNotNil(model.session.cardDrawRecord)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_connection_explicitly_unavailable"
            }
        )
        XCTAssertFalse(
            model.session.messages.last(where: { $0.role == .assistant })?.content.contains("哪一部分最像") == true
        )
    }

    @MainActor
    func testUnclearConnectionGetsAtMostOneRetryBeforeExiting() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        model.session.context.cardInterpretation = "画面里一个人站在两条路之间"

        model.draft = "有点难想到"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertEqual(
            model.session.studyEvents.filter { $0.action == "card_connection_retried_once" }.count,
            1
        )

        model.draft = "还是想不到"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 2)
        XCTAssertEqual(
            model.session.studyEvents.filter { $0.action == "card_connection_retried_once" }.count,
            1
        )
        XCTAssertTrue(model.session.cardConnectionUnavailable)
    }

    @MainActor
    func testFirstSoftNoConnectionUsesCardGuidedVisualScaffoldBeforeRetryingReality() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(concepts: [.recovery, .repair]),
            dialogueGenerator: CardCandidateMappingGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "这段现实情况已经由用户确认。"
        model.session.card = CardService().allCards.first { $0.title == "裂痕与器皿" }
        model.session.context.cardInterpretation =
            "一个器皿出现裂缝，少量水正渗到旁边的布上"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一个器皿出现裂缝，少量水正渗到旁边的布上")
        )
        model.draft = "有点想不到"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        let scaffold = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(scaffold.contains("裂缝"))
        XCTAssertTrue(scaffold.contains("接下来"))
        XCTAssertFalse(scaffold.contains("代表"))

        model.draft = "布能先接住渗出的水，但裂缝之后会不会扩大还不知道"
        model.send()
        await waitForModelIdle(model)

        XCTAssertFalse(model.session.cardConnectionScaffoldPending)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        XCTAssertTrue(model.session.context.cardInterpretation?.contains("裂缝之后会不会扩大") == true)
        XCTAssertNil(model.session.cardLifeConnection)

        model.draft = "项目里我能处理自己的分析，但跨部门的数据什么时候给我，不是我能决定的"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)
        XCTAssertNil(model.session.cardLifeConnection)
        XCTAssertFalse(model.session.cardMappingConfirmed)
        XCTAssertTrue(model.session.cardCandidateMapping?.contains("可能") == true)
        XCTAssertFalse(model.session.cardCandidateMapping?.contains("项目里我能处理") == true)

        model.draft = "贴近"
        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardMappingConfirmed)
    }

    @MainActor
    func testCandidateCardMappingCombinesUserImageRelationLifeConnectionAndConfirmedBackground() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(),
            dialogueGenerator: CardCandidateMappingGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "这段现实情况已经由用户确认。"
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        model.session.context.eventDescription = "昨晚妈妈又问了一遍已经解释过的报销问题，我语气很冲"
        model.session.context.cardInterpretation = "一辆装着货物的小车来到弯道，人物还握着转向杆"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一辆装着货物的小车来到弯道，人物还握着转向杆")
        )
        model.session.trackingContextLinkResponse = "最近睡得短一些，事情堆着时更难保持耐心"
        model.draft = "这让我想到住院和报销不可能一下子都处理完，但昨晚回应妈妈的方式仍可以调整"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)
        let candidate = try! XCTUnwrap(model.session.cardCandidateMapping)
        XCTAssertTrue(candidate.contains("可能"))
        XCTAssertTrue(candidate.contains("暂时无法改变"))
        XCTAssertFalse(candidate.contains("回应妈妈的方式"))
        XCTAssertFalse(candidate.contains("睡得短一些"))
        XCTAssertFalse(candidate.contains("这张牌"))
        XCTAssertFalse(candidate.contains("代表"))
        XCTAssertFalse(candidate.contains("？"), "stored mapping must not include a confirmation question")

        let visible = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(visible.contains(candidate))
        XCTAssertTrue(visible.contains("贴近吗"))
    }

    @MainActor
    func testUserRevisionBecomesConfirmedCardMappingBeforeCandidReflection() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(),
            dialogueGenerator: CardCandidateMappingGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "这段现实情况已经由用户确认。"
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        model.session.context.eventDescription = "我昨晚对妈妈语气很冲"
        model.session.context.cardInterpretation = "一辆小车来到弯道，人物还握着可以调整方向的把手"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一辆小车来到弯道，人物还握着可以调整方向的把手")
        )
        model.draft = "这让我想到我可以先处理昨晚语气很冲这件事"

        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)

        let revision = "不太贴近，更像是我先承认昨晚的语气伤人，再慢慢处理其他事情。"
        model.draft = revision
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardMappingConfirmed)
        XCTAssertEqual(model.session.cardConfirmedMapping, revision)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_candidate_mapping_revised_by_user" })
    }

    @MainActor
    func testRejectedCandidateMappingStopsCardUseBeforeCandidReflection() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(),
            dialogueGenerator: CardCandidateMappingGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "这段现实情况已经由用户确认。"
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        model.session.context.eventDescription = "我昨晚对妈妈语气很冲"
        model.session.context.cardInterpretation = "一辆小车来到弯道，人物还握着可以调整方向的把手"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一辆小车来到弯道，人物还握着可以调整方向的把手")
        )
        model.draft = "这让我想到昨晚和妈妈说话的方式"

        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)

        model.draft = "没有关系"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardConnectionUnavailable)
        XCTAssertFalse(model.session.cardMappingConfirmed)
        XCTAssertNil(model.session.cardCandidateMapping)
        XCTAssertNil(model.session.cardConfirmedMapping)
        XCTAssertNil(model.session.cardGuidanceMatch)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_candidate_mapping_rejected" })
    }

    @MainActor
    func testExplicitUserAuthoredMappingSkipsSystemCandidateAndDeepensMeaning() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardMappingAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards.first { $0.title == "裂痕与器皿" }
        model.session.context.eventDescription = "论文系统一直调不好，时间快来不及了"
        model.session.context.selfJudgment = "我能力不行"
        model.session.context.cardInterpretation = "一个器皿有很大的裂缝，旁边有一捆绳子；可能用绳子把裂缝捆起来"
        let mapping = "我调模型也是修修补补却没有效果，就像绳子捆住罐子，裂缝还是在"
        model.draft = mapping

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardMappingConfirmed)
        XCTAssertEqual(model.session.cardConfirmedMapping, mapping)
        XCTAssertNil(model.session.cardCandidateMapping)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "user_authored_card_mapping_confirmed_directly" })
        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(reply.contains("一个可能的对应"))
    }

    @MainActor
    func testCardStorySuppressesInventedGenderActionAndMeaning() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: InventedCardStoryGenerator()
        )
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.draft = "这是一个半开着的门，门外有一个包裹"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(reply, "你觉得接下来可能会发生什么？")
        XCTAssertFalse(reply.contains("她"))
        XCTAssertFalse(reply.contains("继续这样做"))
        XCTAssertFalse(reply.contains("自然的靠近"))
    }

    @MainActor
    func testMeaningShiftUsesGroundedEditableRelationWithoutScenarioTemplate() async {
        let model = ReflectionViewModel(
            analyzer: LatestBehaviorRelationAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardMeaningShift
        model.session.context.eventDescription = "最近一段重要关系发生了变化"
        model.draft = "争执时我有时会停止沟通，这个具体行为需要回看"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        let candid = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(candid.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(candid.contains("真实的需要、伤害或边界"))
        XCTAssertFalse(candid.contains("你后悔的更像哪一类"))

        model.draft = "我可以在情绪缓下来后说明自己真正需要什么"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(model.session.candidAgencyCompleted)
    }

    @MainActor
    func testOffTopicCandidAgencyReplyDoesNotAdvanceOrEnterNarrative() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidAgency
        model.session.context.eventDescription = "连续调整 Prompt 后，结果仍然不稳定"
        model.session.cardLifeConnection = "擦窗的一部分一部分像是在调整 Prompt"
        model.draft = "我是大帅哥"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        XCTAssertNil(model.session.candidAgencyResponse)
        XCTAssertFalse(model.session.hasCompletedAttributionExchange)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "candid_agency_response_not_usable" })
        XCTAssertTrue(model.session.messages.last?.content.contains("没太接上") == true)
    }

    @MainActor
    func testBroadButRelevantCandidAnswerIsAcknowledgedAndClarified() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidAgency
        model.session.context.eventDescription = "昨晚妈妈再次问报销的事情时，我语气很冲"
        model.draft = "更耐心一些"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        XCTAssertFalse(model.session.candidAgencyCompleted)
        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("具体到那个时刻"))
        XCTAssertFalse(reply.contains("没太接上"))
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "broad_candid_agency_clarification_prompted"
            }
        )
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "open_response_plan_validated_exploreAgencyBoundaryOrChange"
            }
        )
    }

    @MainActor
    func testEveryCardProvidesAnImageOnlyScaffoldForSoftConnectionDifficulty() {
        let cards = CardService().allCards

        XCTAssertEqual(cards.count, 22)
        for card in cards {
            let scaffolds = card.internalGuidance?.visualScaffolds ?? []
            XCTAssertFalse(scaffolds.isEmpty, "\(card.title) 缺少画面内 scaffold")
            XCTAssertTrue(scaffolds.allSatisfy { !$0.requiredAnchorGroups.isEmpty })
            XCTAssertTrue(scaffolds.allSatisfy { $0.requiredAnchorGroups.allSatisfy { !$0.isEmpty } })
            XCTAssertTrue(scaffolds.allSatisfy { $0.question.contains("？") })
            XCTAssertTrue(scaffolds.allSatisfy { scaffold in
                let forbidden = ["现实", "责任", "行动", "这张牌", "代表", "说明", "象征", "你应该"]
                return !forbidden.contains { scaffold.question.contains($0) }
            })
        }
    }

    @MainActor
    func testTurnableCartUsesCardSpecificImageScaffoldBeforeRetryingRealityConnection() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        model.session.context.cardInterpretation =
            "画面里有一辆装着货物的小车，来到弯道，人物握着转向杆"
        model.draft = "我一下子有点想不到"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        var reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("这辆车接下来可能怎样转向"))
        XCTAssertFalse(reply.contains("局部可控"))
        XCTAssertFalse(reply.contains("小步行动"))

        model.draft = "货物还在车上，但人物可以先转向或停靠"
        model.send()
        await waitForModelIdle(model)

        XCTAssertFalse(model.session.cardConnectionScaffoldPending)
        reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("你刚才补充了"))
        XCTAssertTrue(reply.contains("把这个画面放回刚才那件事里"))
        XCTAssertFalse(reply.contains("其他地方可能暂时不好动"))
    }

    @MainActor
    func testScaffoldRequiresItsOwnVisualAnchors() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        // The person mentioned a cart, but neither a turn/handle nor cargo. A card-specific
        // question must not introduce those absent elements.
        model.session.context.cardInterpretation = "画面里有一辆小车，旁边还有一条普通道路"
        model.draft = "我有点想不到"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(model.session.cardConnectionScaffoldPending)
        XCTAssertFalse(reply.contains("接下来可能怎样转向"))
        XCTAssertFalse(reply.contains("车上的东西会怎样影响"))
    }

    @MainActor
    func testScaffoldChoosesTheQuestionWhoseOwnAnchorsArePresent() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = CardService().allCards.first { $0.title == "可转向的车" }
        // This story has a cart and cargo, but no turning structure. The first scaffold is not
        // eligible, so selection must continue to the second card-specific question.
        model.session.context.cardInterpretation = "有一辆小车，车上装着一些货物"
        model.draft = "想不到"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("车上的东西会怎样影响它接下来的方向"))
        XCTAssertFalse(reply.contains("这辆车接下来可能怎样转向"))
    }

    @MainActor
    func testLegacyCardNarrativeDeepeningCanResumeIntoConnection() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardNarrativeDeepening
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        model.session.context.cardInterpretation = "画面里一个人站在两条路之间"
        model.draft = "他还在看前面的路"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
    }

    @MainActor
    func testCardCanRemainUnconnectedAndReflectionReturnsToConfirmedStory() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "不应继续使用")
        model.draft = "我觉得这张牌和我的事情没什么关系"
        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardWasSetAside)
        XCTAssertNotNil(model.session.card)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_connection_recorded_as_none" })
        XCTAssertFalse(model.session.hasCompletedAttributionExchange)
        XCTAssertFalse(model.isTyping)
    }
}

final class ReflectionStateMachineTests: XCTestCase {
    private let machine = ReflectionStateMachine()
    private let workflowMachine = ReflectionWorkflowStateMachine()

    @MainActor
    func testStartingFreshReflectionInvalidatesThenAutomaticallyRefreshesTrackingSnapshot() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        await model.refreshContextData()
        XCTAssertNotNil(model.contextDataRefreshedAt)

        model.startNewInsteadOfResuming()

        XCTAssertNil(model.contextDataRefreshedAt)
        XCTAssertTrue(model.session.trackingCues.isEmpty)
        XCTAssertTrue(model.contextDataStatus.contains("重新读取"))

        for _ in 0..<100 where model.contextDataRefreshedAt == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertNotNil(model.contextDataRefreshedAt)
        XCTAssertFalse(model.isLoadingContextData)
    }

    @MainActor
    func testResumeChoiceCanBeDismissedWithoutDiscardingPausedSession() {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator(),
            preparesContextDataAutomatically: false
        )
        var pausedSession = ReflectionSession()
        pausedSession.stage = .eventDisclosure
        let candidate = ResumableReflection(
            id: pausedSession.id.uuidString,
            remoteID: nil,
            session: pausedSession,
            updatedAt: .now
        )
        model.resumeCandidate = candidate

        model.presentResumeChoice()
        XCTAssertTrue(model.isResumeChoicePresented)

        model.dismissResumeChoice()
        XCTAssertFalse(model.isResumeChoicePresented)
        XCTAssertEqual(model.resumeCandidate?.id, candidate.id)
    }

    @MainActor
    func testDeleteResetsCurrentSessionAndClearsResumeChoice() {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator(),
            preparesContextDataAutomatically: false
        )
        let deletedSessionID = model.session.id
        model.session.stage = .eventDisclosure
        model.session.messages = [ChatMessage(role: .user, content: "一段较长的对话")]
        model.resumeCandidate = ResumableReflection(
            id: deletedSessionID.uuidString,
            remoteID: nil,
            session: model.session,
            updatedAt: .now
        )
        model.presentResumeChoice()

        model.delete()

        XCTAssertNotEqual(model.session.id, deletedSessionID)
        XCTAssertEqual(model.session.stage, .welcome)
        XCTAssertTrue(model.session.messages.isEmpty)
        XCTAssertNil(model.resumeCandidate)
        XCTAssertFalse(model.isResumeChoicePresented)
    }

    func testResearchWorkflowAllowsTheFixedForwardContractAndRejectsShortcuts() {
        let canonicalPath: [ReflectionWorkflowPhase] = [
            .opening,
            .structuredDisclosure,
            .tenderGroundingConfirmation,
            .trackingReview,
            .trackingContextLink,
            .contextConfirmation,
            .cardSelection,
            .cardDisplay,
            .cardObservation,
            .cardAssociation,
            .cardConnection,
            .cardMappingConfirmation,
            .candidCircumstances,
            .cardMeaningShift,
            .candidAgency,
            .reflectionNarrativeConfirmation,
            .optionalAction,
            .narrativeConfirmation,
            .complete,
        ]

        for (current, next) in zip(canonicalPath, canonicalPath.dropFirst()) {
            XCTAssertTrue(
                workflowMachine.canTransition(from: current, to: next),
                "missing required edge \(current) -> \(next)"
            )
        }
        XCTAssertTrue(workflowMachine.canTransition(from: .optionalAction, to: .actionConfirmation))
        XCTAssertTrue(workflowMachine.canTransition(from: .actionConfirmation, to: .narrativeConfirmation))
        XCTAssertTrue(
            workflowMachine.canTransition(from: .narrativeConfirmation, to: .optionalAction),
            "a user-authored late request may return to the optional practice gate"
        )

        let forbiddenShortcuts: [(ReflectionWorkflowPhase, ReflectionWorkflowPhase)] = [
            (.structuredDisclosure, .trackingReview),
            (.tenderGroundingConfirmation, .contextConfirmation),
            (.trackingReview, .cardSelection),
            (.contextConfirmation, .cardObservation),
            (.cardObservation, .cardConnection),
            (.cardConnection, .cardMeaningShift),
            (.cardConnection, .candidAgency),
            (.cardMappingConfirmation, .candidAgency),
            (.candidAgency, .optionalAction),
            (.reflectionNarrativeConfirmation, .narrativeConfirmation),
            (.optionalAction, .complete),
        ]
        for (current, next) in forbiddenShortcuts {
            XCTAssertFalse(
                workflowMachine.canTransition(from: current, to: next),
                "unexpected shortcut \(current) -> \(next)"
            )
        }
    }

    func testActionCannotBeReachedBeforeRequiredStages() {
        for state in [ReflectionState.welcome, .eventDisclosure, .emotionDisclosure, .bodilyResponse,
                      .selfJudgment, .contextDisclosure, .trackingPermission, .trackingReview,
                      .tenderGrounding, .readinessCheck, .tenderExploration,
                      .cardIntroduction, .cardInterpretation] {
            XCTAssertFalse(machine.canTransition(from: state, to: .actionSelection), "unexpected transition from \(state)")
        }
        XCTAssertTrue(machine.canTransition(from: .attributionReflection, to: .actionSelection))
    }

    func testUserCanRemainTenderWithoutCard() {
        XCTAssertTrue(machine.canTransition(from: .readinessCheck, to: .tenderExploration))
    }

    func testBodilyDisclosureIsExploredBeforePersonalMeaning() {
        XCTAssertEqual(machine.nextDisclosureState(after: .emotionDisclosure), .bodilyResponse)
        XCTAssertTrue(machine.canTransition(from: .emotionDisclosure, to: .bodilyResponse))
    }

    func testLegacyAdaptiveResolverStillPreservesMissingEmotionForEmergencyCompatibility() {
        var context = ReflectionContext()
        context.selfJudgment = "我根本不适合读博士"
        context.contextualConstraints = ["还有两个课程作业"]
        let resolver = AdaptiveDisclosureResolver()

        XCTAssertEqual(resolver.nextState(after: .eventDisclosure, context: context), .emotionDisclosure)

        context.emotions = ["很慌"]
        XCTAssertEqual(resolver.nextState(after: .eventDisclosure, context: context), .bodilyResponse)
    }

    @MainActor
    func testValidatedResponsePlanFollowsSelfEvaluationInsteadOfMissingEmotionField() async {
        let model = ReflectionViewModel(
            analyzer: PlannedMeaningAnalyzer(),
            dialogueGenerator: ResponsePlanDialogueGenerator()
        )
        model.begin()
        model.draft = "系统一直调不好，截止时间快到了。最近测试一直失败，我觉得可能是自己能力不行。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.stage, .selfJudgment)
        XCTAssertTrue(reply.contains("最担心接下来"), "reply: \(reply)")
        XCTAssertFalse(reply.contains("当时最明显的感受"), "reply: \(reply)")
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "response_plan_validated_clarifyPersonalMeaning"
            }
        )
    }

    func testDisclosurePlanCanBeRecoveredFromGroundedLatestTurnRelation() {
        let userText = "一个重要尝试再次没有成功，我开始怀疑自己是不是不适合继续做这件事。"
        var analysis = ContextAnalysis()
        analysis.selfJudgment = "不适合继续做这件事"
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "重要尝试再次没有成功",
                relation: "被扩大为",
                target: "不适合继续做这件事",
                concepts: [.selfEvaluation, .ability],
                evidence: ["再次没有成功", "不适合继续做这件事"],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = nil
        analysis.confidence = 0.9

        let result = ResponsePlanValidator().recoverDisclosurePlan(
            analysis: analysis,
            state: .eventDisclosure,
            workflowPhase: .structuredDisclosure,
            messages: [ChatMessage(role: .user, content: userText)]
        )

        XCTAssertEqual(result?.function, .clarifyPersonalMeaning)
        XCTAssertEqual(result?.relationKinds, [.selfEvaluation])
        XCTAssertTrue(result?.evidence.contains("不适合继续做这件事") == true)
    }

    @MainActor
    func testRelationOnlySelfEvaluationDoesNotFallBackToMissingEmotionQuestion() async {
        let model = ReflectionViewModel(
            analyzer: RelationOnlyMeaningAnalyzer(),
            dialogueGenerator: ResponsePlanDialogueGenerator()
        )
        model.begin()
        model.draft = "一个重要尝试再次没有成功，我开始怀疑自己是不是不适合继续做这件事。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.stage, .selfJudgment)
        XCTAssertTrue(reply.contains("最担心接下来"), "reply: \(reply)")
        XCTAssertFalse(reply.contains("当时最明显的感受"), "reply: \(reply)")
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "response_plan_recovered_clarifyPersonalMeaning"
            }
        )
    }

    @MainActor
    func testRelationOnlySelfEvaluationKeepsMeaningQuestionWhenWriterIsUnavailable() async {
        let model = ReflectionViewModel(
            analyzer: RelationOnlyMeaningAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.begin()
        model.draft = "一个重要尝试再次没有成功，我开始怀疑自己是不是不适合继续做这件事。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.stage, .selfJudgment)
        XCTAssertTrue(reply.contains("最担心"), "reply: \(reply)")
        XCTAssertFalse(reply.contains("当时最明显的感受"), "reply: \(reply)")
        XCTAssertTrue(model.canRetry)
    }

    func testResponsePlanValidatorRejectsEvidenceThatIsNotInUserTranscript() {
        let userText = "最近测试一直失败，我开始怀疑自己的能力"
        var analysis = ContextAnalysis()
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "测试失败",
                relation: "被扩大为",
                target: "能力判断",
                concepts: [.selfEvaluation, .ability],
                evidence: ["测试一直失败", "怀疑自己的能力"],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = ResponsePlan(
            function: .clarifyPersonalMeaning,
            focus: "失败与能力判断之间的关系",
            evidence: ["用户从未说过的证据"],
            relationKinds: [.selfEvaluation],
            questionIntent: "询问这一判断带来的具体担心",
            shouldAskQuestion: true,
            confidence: 0.9
        )

        let result = ResponsePlanValidator().validate(
            analysis.responsePlan,
            analysis: analysis,
            state: .eventDisclosure,
            workflowPhase: .structuredDisclosure,
            messages: [ChatMessage(role: .user, content: userText)]
        )

        XCTAssertNil(result)
    }

    func testResponsePlanValidatorRejectsPlanFromAnEarlierUserTurn() {
        let earlier = "我开始怀疑自己的能力"
        let latest = "不过我现在想谈谈和同事之间的边界"
        var analysis = ContextAnalysis()
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "一次结果",
                relation: "被扩大为",
                target: "整体能力判断",
                concepts: [.selfEvaluation],
                evidence: [earlier],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = ResponsePlan(
            function: .clarifyPersonalMeaning,
            focus: "结果和整体能力判断之间的关系",
            evidence: [earlier],
            relationKinds: [.selfEvaluation],
            questionIntent: "继续询问能力判断",
            shouldAskQuestion: true,
            confidence: 0.9
        )

        XCTAssertNil(
            ResponsePlanValidator().validate(
                analysis.responsePlan,
                analysis: analysis,
                state: .tenderExploration,
                workflowPhase: .contextConfirmation,
                messages: [
                    ChatMessage(role: .user, content: earlier),
                    ChatMessage(role: .assistant, content: "我听到了。"),
                    ChatMessage(role: .user, content: latest),
                ]
            )
        )
    }

    @MainActor
    func testTenderOpenTurnUsesCurrentSemanticPlan() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.stage = .tenderExploration
        model.session.workflowPhase = .contextConfirmation
        model.draft = "我更希望有人先把我的话听完"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "open_response_plan_validated_deepenTenderUnderstanding"
            }
        )
        XCTAssertTrue(
            model.session.messages.last?.content.contains("最需要被理解") == true
        )
    }

    @MainActor
    func testCardImageTurnUsesCurrentSemanticPlan() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.draft = "画面里一个人扶着半开的门，门外放着一个包裹"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .cardAssociation)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "open_response_plan_validated_developImageRelation"
            }
        )
        XCTAssertTrue(
            model.session.messages.last?.content.contains("接下来") == true,
            "reply: \(model.session.messages.last?.content ?? "")"
        )
    }

    @MainActor
    func testActionRevisionUsesCurrentSemanticPlan() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.stage = .actionSelection
        model.session.workflowPhase = .optionalAction
        model.draft = "我想把它改成今天先做五分钟"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "open_response_plan_validated_proposePractice"
            }
        )
        XCTAssertEqual(model.session.actionSuggestions.first?.category, .change)
    }

    @MainActor
    func testSwiftControlledTurnDoesNotConsumeStaleResponsePlan() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.stage = .eventDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.structuredDisclosureAssistantTurns = 1
        var stale = ContextAnalysis()
        stale.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "暂时不确定",
                relation: "被扩大为",
                target: "整体判断",
                concepts: [.selfEvaluation],
                evidence: ["这一项我暂时不确定"],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        stale.responsePlan = ResponsePlan(
            function: .clarifyPersonalMeaning,
            focus: "一个旧计划",
            evidence: ["这一项我暂时不确定"],
            relationKinds: [.selfEvaluation],
            questionIntent: "不应接管固定跳过流程",
            shouldAskQuestion: true,
            confidence: 0.9
        )
        model.session.latestAnalysis = stale

        model.skipCurrentDisclosure()
        await waitForModelIdle(model)

        XCTAssertFalse(
            model.session.studyEvents.contains {
                $0.action.hasPrefix("open_response_plan_validated_")
            }
        )
        XCTAssertTrue(
            model.session.messages.last?.content.contains("现在有什么感受") == true,
            "reply: \(model.session.messages.last?.content ?? "")"
        )
    }

    func testUserCanStopAtReadinessGate() {
        XCTAssertTrue(machine.canTransition(from: .readinessCheck, to: .summary))
    }

    @MainActor
    func testSufficientDisclosureWaitsForThirdAssistantTurnBeforeTenderGrounding() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .contextDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.structuredDisclosureAssistantTurns = 2
        model.session.context.eventDescription = "负责人临时要求我第二天交分析"
        model.session.context.emotions = ["紧张"]
        model.session.context.selfJudgment = "我担心自己不负责"
        model.session.context.contextualConstraints = ["时间很紧"]
        model.session.bodyExplorationCompleted = true

        model.draft = "当时确实很紧张，也觉得时间不够"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .structuredDisclosure)
        XCTAssertEqual(model.session.structuredDisclosureAssistantTurns, 3)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "tender_grounding_started" })

        model.draft = "我也担心拒绝后会被觉得不负责"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)
        XCTAssertEqual(model.session.stage, .tenderGrounding)
        XCTAssertTrue(
            model.session.studyEvents.contains { $0.action == "structured_disclosure_completed_sufficient" }
        )
    }

    @MainActor
    func testIncompleteDisclosureContinuesThroughFourthTurnAndStopsAtFive() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .contextDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.structuredDisclosureAssistantTurns = 4
        model.session.context.eventDescription = "负责人临时要求我第二天交分析"

        model.draft = "当时还有别的工作，但我还没想清楚"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .structuredDisclosure)
        XCTAssertEqual(model.session.structuredDisclosureAssistantTurns, 5)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "tender_grounding_started" })

        model.draft = "我暂时还是说不上来"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)
        XCTAssertEqual(model.session.structuredDisclosureAssistantTurns, 5)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "structured_disclosure_completed_maximum_turns"
            }
        )
    }

    @MainActor
    func testContextConfirmationDrawsLocallyButWaitsForImageBeforeObservationQuestion() async throws {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.trackingReviewCompleted = true
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(model.session.contextSummaryConfirmed)
        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertTrue(model.session.messages.last?.content.contains("抽卡") == true)

        model.draft = "抽卡"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .cardIntroduction)
        XCTAssertEqual(model.session.workflowPhase, .cardDisplay)
        XCTAssertEqual(model.session.cardDisplayState, .selected)
        XCTAssertNotNil(model.session.cardDrawRecord)
        XCTAssertFalse(model.session.messages.last?.content.contains("画面里") == true)

        let confirmationMessageID = try XCTUnwrap(
            model.session.messages.last(where: { $0.role == .user })?.id
        )
        let deterministicCard = try XCTUnwrap(
            CardService().allCards.first { $0.title == "未定之步" }
        )
        model.session.card = deterministicCard
        model.session.context.selectedCardID = String(deterministicCard.id)
        let cardID = deterministicCard.id
        model.cardDidDisplay(cardID: cardID)

        XCTAssertEqual(model.session.workflowPhase, .cardObservation)
        XCTAssertEqual(model.session.cardDisplayState, .displayed)
        XCTAssertTrue(model.session.messages.last?.content.contains("画面里正在发生什么") == true)
        XCTAssertEqual(model.session.messages.last?.replyToMessageID, confirmationMessageID)

        await sendAndWait("画面里一个人站在两条路之间", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardAssociation)
        await sendAndWait("他像是还没有决定先走哪一边", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)

        let imageQuestions = model.session.messages.filter {
            $0.role == .assistant &&
                $0.state == .cardInterpretation &&
                ($0.content.contains("？") || $0.content.contains("?"))
        }
        XCTAssertEqual(imageQuestions.count, 2)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_observation_prompted" })
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_association_prompted" })
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "card_narrative_deepening_prompted" })
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_connection_prompted" })
    }

    @MainActor
    func testNominalFullPathFinishesWithinTurnBudgetWithoutDuplicateQuestionsOrDoubleReplies() async throws {
        let model = ReflectionViewModel(
            analyzer: WorkflowSemanticAnalyzer(),
            dialogueGenerator: WorkflowContractDialogueGenerator()
        )
        model.begin()

        await sendAndWait("负责人昨晚临时要求我今天交一份分析", to: model)
        await sendAndWait("我当时很紧张，也觉得很挫败", to: model)
        await sendAndWait("那一晚肩膀很紧，睡得也不稳", to: model)
        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)

        model.session.trackingCues = [workflowTrackingCue()]
        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .trackingReview)

        await sendAndWait("这条睡眠背景可能让我当时更难集中注意力", to: model)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)

        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        await sendAndWait("抽卡", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardDisplay)
        let deterministicCard = try XCTUnwrap(
            CardService().allCards.first { $0.title == "未定之步" }
        )
        model.session.card = deterministicCard
        model.session.context.selectedCardID = String(deterministicCard.id)
        let cardID = deterministicCard.id
        model.cardDidDisplay(cardID: cardID)
        XCTAssertEqual(model.session.workflowPhase, .cardObservation)

        await sendAndWait("画面里一个人站在两条路中间", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardAssociation)
        await sendAndWait("他像是不知道应该先走哪一边", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardConnection)
        await sendAndWait("这让我想到自己面对两个不同建议，不知道该先听谁", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)
        XCTAssertFalse(model.session.cardMappingConfirmed)
        await sendAndWait("贴近", to: model)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        await sendAndWait("两个建议确实冲突，实验时间也已经很紧", to: model)
        XCTAssertEqual(model.session.workflowPhase, .cardMeaningShift)
        await sendAndWait("我现在觉得不是完全没有判断，而是缺少一个清楚的比较标准", to: model)
        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        await sendAndWait("我可以先写清楚判断标准，再决定试哪一条", to: model)
        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .optionalAction)
        await sendAndWait("这次先不决定行动", to: model)
        XCTAssertEqual(model.session.workflowPhase, .narrativeConfirmation)
        await sendAndWait("符合", to: model)

        XCTAssertEqual(model.session.workflowPhase, .complete)
        XCTAssertEqual(model.session.stage, .completed)

        let userMessages = model.session.messages.filter { $0.role == .user }
        let assistantMessages = model.session.messages.filter { $0.role == .assistant }
        let assistantDiagnostics = assistantMessages.map {
            "\($0.content)|reply=\($0.replyToMessageID?.uuidString ?? "nil")"
        }
        let eventDiagnostics = model.session.studyEvents.suffix(8).map(\.action)
        XCTAssertTrue((13...20).contains(assistantMessages.count), "assistant turns: \(assistantMessages.count)")
        XCTAssertTrue((13...19).contains(userMessages.count), "user turns: \(userMessages.count)")

        for user in userMessages {
            let replies = assistantMessages.filter { $0.replyToMessageID == user.id }
            XCTAssertEqual(
                replies.count,
                1,
                "typed user turn \(user.id) (\(user.content)) must own exactly one reply; assistants=\(assistantDiagnostics); events=\(eventDiagnostics)"
            )
        }

        let normalizedQuestions = assistantMessages.compactMap { message -> String? in
            let line = message.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { $0.contains("？") || $0.contains("?") }
            guard let line else { return nil }
            return line.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        XCTAssertEqual(
            Set(normalizedQuestions).count,
            normalizedQuestions.count,
            "assistant questions must not repeat: \(normalizedQuestions)"
        )
    }

    @MainActor
    func testDirectConditionNominalFullPathFinishesWithoutCardOrShortcut() async throws {
        let model = ReflectionViewModel(
            analyzer: WorkflowSemanticAnalyzer(),
            dialogueGenerator: WorkflowContractDialogueGenerator()
        )
        model.session.condition = .directLLM
        model.begin()

        await sendAndWait("我需要做实验结果分析，但一直在整理不重要的文件", to: model)
        await sendAndWait("我当时很紧张，也觉得很挫败", to: model)
        await sendAndWait("那几天肩膀很紧，睡得也不稳", to: model)
        XCTAssertEqual(model.session.workflowPhase, .tenderGroundingConfirmation)

        model.session.trackingCues = [workflowTrackingCue()]
        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .trackingReview)
        XCTAssertNil(model.session.card)

        await sendAndWait("这条睡眠背景可能让我更难开始分析", to: model)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)

        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertNil(model.session.card)
        XCTAssertFalse(
            model.session.messages.contains {
                $0.role == .assistant &&
                    ($0.content.contains("抽卡") || $0.content.contains("图卡") || $0.content.contains("牌"))
            }
        )

        await sendAndWait("我明知道该分析，却总是转去整理文件", to: model)
        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        XCTAssertTrue(model.session.candidCircumstancesCompleted)

        await sendAndWait("下次先把整理放到稍后清单，先给分析留十分钟", to: model)
        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(model.session.candidAgencyCompleted)
        XCTAssertTrue(model.session.hasPresentedIntegratedNarrative)

        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .optionalAction)
        XCTAssertFalse(model.session.actionSuggestions.isEmpty)

        await sendAndWait("这次先不决定行动", to: model)
        XCTAssertEqual(model.session.workflowPhase, .narrativeConfirmation)
        XCTAssertNil(model.session.context.selectedAction)
        XCTAssertTrue(model.session.hasPresentedFinalNarrative)

        await sendAndWait("符合", to: model)
        XCTAssertEqual(model.session.workflowPhase, .complete)
        XCTAssertEqual(model.session.stage, .completed)
        XCTAssertTrue(model.session.finalNarrativeConfirmed)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action.contains("card_") })

        let userMessages = model.session.messages.filter { $0.role == .user }
        let assistantMessages = model.session.messages.filter { $0.role == .assistant }
        let assistantDiagnostics = assistantMessages.map {
            "\($0.content)|reply=\($0.replyToMessageID?.uuidString ?? "nil")"
        }
        let eventDiagnostics = model.session.studyEvents.suffix(8).map(\.action)
        for user in userMessages {
            let replies = assistantMessages.filter { $0.replyToMessageID == user.id }
            XCTAssertEqual(
                replies.count,
                1,
                "direct user turn \(user.id) (\(user.content)) must own exactly one reply; assistants=\(assistantDiagnostics); events=\(eventDiagnostics)"
            )
        }
        let normalizedQuestions = assistantMessages.compactMap { message -> String? in
            let line = message.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .last { $0.contains("？") || $0.contains("?") }
            guard let line else { return nil }
            return line.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        XCTAssertEqual(Set(normalizedQuestions).count, normalizedQuestions.count)

        let actions = model.session.studyEvents.map(\.action)
        let tracking = try XCTUnwrap(actions.firstIndex(of: "tracking_review_completed"))
        let directCandid = try XCTUnwrap(actions.firstIndex(of: "direct_candid_reflection_started"))
        let circumstances = try XCTUnwrap(actions.firstIndex(of: "candid_circumstances_completed"))
        let agency = try XCTUnwrap(actions.firstIndex(of: "candid_agency_completed"))
        let narrative = try XCTUnwrap(actions.firstIndex(of: "integrated_reflection_narrative_confirmed"))
        let action = try XCTUnwrap(actions.firstIndex(of: "optional_action_declined"))
        let completed = try XCTUnwrap(actions.firstIndex(of: "final_narrative_confirmed"))
        XCTAssertLessThan(tracking, directCandid)
        XCTAssertLessThan(directCandid, circumstances)
        XCTAssertLessThan(circumstances, agency)
        XCTAssertLessThan(agency, narrative)
        XCTAssertLessThan(narrative, action)
        XCTAssertLessThan(action, completed)
    }

    @MainActor
    func testNaturalTextDefersCardAndContinuesConversation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .readinessCheck
        model.draft = "我想继续聊，先不抽卡"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderExploration)
        XCTAssertEqual(model.session.dialogueProgress.cardPreference, .deferred)
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .user })?.content,
            "我想继续聊，先不抽卡"
        )
        XCTAssertFalse(model.session.messages.last?.content.contains("抽卡") == true)
    }

    @MainActor
    func testOrdinaryTenderReplyDoesNotReopenReadinessOrInviteCardAgain() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .tenderExploration
        model.session.dialogueProgress.currentState = .tenderExploration
        model.session.dialogueProgress.cardPreference = .deferred
        model.session.messages = [
            ChatMessage(role: .user, content: "我想继续聊，先不抽卡"),
            ChatMessage(role: .assistant, content: "好，我们就继续说刚才的事。"),
        ]
        model.draft = "我其实最在意的是导师会不会失望"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderExploration)
        XCTAssertEqual(model.session.dialogueProgress.cardPreference, .deferred)
        XCTAssertFalse(model.session.messages.last?.content.contains("卡") == true)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "tender_exploration_completed" })
    }

    @MainActor
    func testClarificationRequestStaysInTenderConversationWithoutInvitingCard() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .tenderExploration
        model.session.dialogueProgress.currentState = .tenderExploration
        model.session.dialogueProgress.cardPreference = .deferred
        model.session.context.eventDescription = "我当时不敢拒绝导师"
        model.session.messages = [
            ChatMessage(role: .assistant, content: "这件事里，你最想先回应哪一点？", state: .tenderExploration),
        ]
        model.draft = "这是什么意思"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderExploration)
        XCTAssertEqual(model.session.dialogueProgress.cardPreference, .deferred)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "abstract_question_clarified_without_advancing"
            }
        )
        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("太抽象"))
        XCTAssertFalse(reply.contains("卡"))
        XCTAssertFalse(model.isTyping)
    }

    @MainActor
    func testReplyAfterUnconnectedCardContinuesWithPriorStoryCircumstances() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardInterpretation
        model.session.workflowPhase = .cardObservation
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        model.draft = "这张卡和我的事没什么关系"

        model.send()
        await waitForModelIdle(model)
        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardWasSetAside)

        model.draft = "现实里我当时不敢拒绝，而且交付时间很紧"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertNotEqual(model.session.workflowPhase, .cardMeaningShift)
        XCTAssertTrue(model.session.candidCircumstancesCompleted)
        XCTAssertNotNil(model.session.card)
        XCTAssertFalse(model.session.messages.last?.content.contains("抽卡") == true)
    }

    @MainActor
    func testExplicitCardRequestCannotSkipTenderTrackingAndContextGates() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .tenderExploration
        model.session.dialogueProgress.currentState = .tenderExploration
        model.session.dialogueProgress.cardPreference = .deferred
        model.draft = "我想换张卡看看"

        model.send()
        await waitForAsyncWork()

        XCTAssertEqual(model.session.stage, .tenderExploration)
        XCTAssertEqual(model.session.cardDisplayState, .none)
        XCTAssertNil(model.session.card)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "card_selected_uniform_random" })
    }

    func testSessionRestorationPreservesDialogueProgressAndMessageState() throws {
        var session = ReflectionSession()
        session.stage = .tenderExploration
        session.dialogueProgress.currentState = .tenderExploration
        session.dialogueProgress.cardPreference = .deferred
        session.dialogueProgress.complete(.event)
        session.hasAskedProgressMeaningQuestion = true
        session.dialogueProgress.record(questionGoal: .selfTalk, question: "你当时怎么对自己说？")
        session.messages = [ChatMessage(role: .assistant, content: "继续聊。", state: .tenderExploration)]

        let decoded = try JSONDecoder().decode(ReflectionSession.self, from: JSONEncoder().encode(session))

        XCTAssertEqual(decoded.stage, .tenderExploration)
        XCTAssertEqual(decoded.dialogueProgress.cardPreference, .deferred)
        XCTAssertTrue(decoded.dialogueProgress.completedDimensions.contains(.event))
        XCTAssertTrue(decoded.dialogueProgress.askedQuestionGoals?.contains(.selfTalk) == true)
        XCTAssertTrue(decoded.dialogueProgress.forbiddenNextGoals.contains(.selfTalk))
        XCTAssertTrue(decoded.hasAskedProgressMeaningQuestion)
        XCTAssertEqual(decoded.messages.first?.state, .tenderExploration)
    }

    @MainActor
    func testNaturalTextAcceptsCardAndDrawsItImmediately() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.contextSummaryConfirmed = true
        model.session.trackingReviewCompleted = true
        model.session.latestAnalysis = .fallback()
        model.draft = "可以，抽一张看看"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .cardIntroduction)
        XCTAssertEqual(model.session.cardDisplayState, .selected)
        model.cardDidDisplay(cardID: try! XCTUnwrap(model.session.card?.id))
        XCTAssertEqual(model.session.stage, .cardInterpretation)
        XCTAssertEqual(model.session.currentRoute, .explore)
        XCTAssertNotNil(model.session.card)
        XCTAssertNotNil(model.session.cardDrawRecord)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "readiness_confirmed_in_dialogue" })
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_drawn_uniform_random" })
        XCTAssertEqual(
            model.session.messages.last(where: { $0.role == .user })?.content,
            "可以，抽一张看看"
        )
    }

    @MainActor
    func testCardRequestWithoutAccuracyConfirmationDoesNotBypassContextGate() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.latestAnalysis = .fallback()
        model.draft = "抽张卡吧"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertEqual(model.session.cardDisplayState, .none)
        XCTAssertFalse(model.session.messages.last?.content.contains("画面里正在发生什么") == true)
        XCTAssertNil(model.session.card)
        XCTAssertNil(model.session.cardDrawRecord)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "card_drawn_uniform_random" })
        XCTAssertTrue(model.session.messages.last?.content.contains("是否准确") == true)
    }

    @MainActor
    func testCardRequestAfterLegacyContextConfirmationRestoresTrackingReview() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        let pending = workflowTrackingCue()
        model.session.stage = .readinessCheck
        model.session.workflowPhase = .contextConfirmation
        model.session.contextSummaryConfirmed = true
        model.session.trackingCues = [pending]
        model.session.latestAnalysis = .fallback()
        model.draft = "抽卡"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .trackingReview)
        XCTAssertEqual(model.session.workflowPhase, .trackingReview)
        XCTAssertFalse(model.session.trackingReviewCompleted)
        XCTAssertNil(model.session.card)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "card_request_deferred_until_tracking_review"
            }
        )
    }

    @MainActor
    func testLegacyTenderExplorationResumeReturnsToTrackingBeforeCardInvitation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        var legacy = ReflectionSession()
        legacy.stage = .tenderExploration
        legacy.workflowPhase = .structuredDisclosure
        legacy.condition = .cardMediated
        legacy.trackingCues = [workflowTrackingCue()]

        model.resume(
            ResumableReflection(
                id: legacy.id.uuidString,
                remoteID: nil,
                session: legacy,
                updatedAt: .now
            )
        )
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .trackingReview)
        XCTAssertEqual(model.session.workflowPhase, .trackingReview)
        XCTAssertFalse(model.session.trackingReviewCompleted)
        XCTAssertNil(model.session.card)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "legacy_tender_exploration_resumed_at_tracking_review"
            }
        )
    }

    @MainActor
    func testLegacyCardMeaningShiftResumeRestoresMissingTenderCircumstances() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        var legacy = ReflectionSession()
        legacy.condition = .cardMediated
        legacy.stage = .attributionReflection
        legacy.workflowPhase = .cardMeaningShift
        legacy.contextSummaryConfirmed = true
        legacy.card = CardService().allCards.first { $0.title == "半开的门" }
        legacy.cardDisplayState = .displayed
        legacy.context.cardInterpretation = "门停在半开的位置"
        legacy.cardMappingConfirmed = true
        legacy.cardConfirmedMapping = "画面里的距离和现实中的距离有些相似"
        legacy.cardLifeConnection = legacy.cardConfirmedMapping
        legacy.hasUserAuthoredCardConnection = true
        legacy.candidCircumstancesCompleted = false

        model.resume(
            ResumableReflection(
                id: legacy.id.uuidString,
                remoteID: nil,
                session: legacy,
                updatedAt: .now
            )
        )
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "legacy_card_meaning_shift_restored_to_tender_circumstances"
            }
        )
    }

    @MainActor
    func testMissingCardReportCannotBypassCurrentTenderConversation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .tenderExploration
        model.session.latestAnalysis = .fallback()
        model.session.messages = [
            ChatMessage(role: .user, content: "抽张卡吧", state: .readinessCheck),
            ChatMessage(role: .assistant, content: "好，那我们来抽张卡。", state: .tenderExploration),
        ]
        model.draft = "没有看到卡片"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .tenderExploration)
        XCTAssertEqual(model.session.cardDisplayState, .none)
        XCTAssertNil(model.session.card)
        XCTAssertNil(model.session.cardDrawRecord)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "card_selected_uniform_random" })
    }

    @MainActor
    func testCardQuestionWaitsForSuccessfulImageDisplayAndFailureStaysTechnical() throws {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardIntroduction
        model.session.workflowPhase = .cardSelection
        model.drawCard()
        let cardID = try XCTUnwrap(model.session.card?.id)
        let assistantCount = model.session.messages.filter { $0.role == .assistant }.count

        model.cardDisplayDidFail(cardID: cardID)

        XCTAssertEqual(model.session.stage, .cardIntroduction)
        XCTAssertEqual(model.session.cardDisplayState, .loadFailed)
        XCTAssertEqual(model.session.messages.filter { $0.role == .assistant }.count, assistantCount)
        XCTAssertEqual(model.session.card?.id, cardID)
        XCTAssertEqual(model.session.cardDrawRecord?.cardID, String(cardID))
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_image_load_failed" })
    }

    @MainActor
    func testCircumstancesAndAgencyPrecedeNarrativeActionAndFinalConfirmation() async throws {
        let model = ReflectionViewModel(
            analyzer: WorkflowSemanticAnalyzer(),
            dialogueGenerator: CardIntegrationDialogueGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "不同建议和有限时间构成了已经确认的现实背景。"
        model.session.card = CardService().allCards.first { $0.title == "未定之步" }
        model.session.context.eventDescription = "导师和同学给了两个不同建议"
        model.session.context.cardInterpretation = "画面中间的人站在两条路之间"
        model.session.messages = [
            ChatMessage(role: .user, content: "画面中间的人站在两条路之间"),
        ]
        model.draft = "这让我想到自己不知道该先听谁的"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .cardMappingConfirmation)
        XCTAssertFalse(
            model.session.hasUserAuthoredCardConnection,
            "A structural candidate is not user-authored until the person confirms or rewrites it"
        )
        XCTAssertFalse(model.session.cardMappingConfirmed)
        XCTAssertFalse(model.session.cardMeaningShiftCompleted)
        XCTAssertFalse(model.session.candidCircumstancesCompleted)
        XCTAssertFalse(model.session.candidAgencyCompleted)
        XCTAssertFalse(model.session.hasCompletedAttributionExchange)
        XCTAssertFalse(model.session.hasPresentedIntegratedNarrative)
        XCTAssertTrue(model.session.actionSuggestions.isEmpty)

        model.draft = "贴近"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(model.session.cardMappingConfirmed)

        model.draft = "两个建议确实互相冲突，而且实验时间已经很紧"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .cardMeaningShift)
        XCTAssertTrue(model.session.candidCircumstancesCompleted)
        model.session.context.personalContributions = ["我没有先写清楚判断标准"]

        model.draft = "这让我看到自己不是完全没判断，而是还没有一套清楚的比较标准"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        XCTAssertTrue(model.session.cardMeaningShiftCompleted)
        XCTAssertFalse(model.session.candidAgencyCompleted)
        XCTAssertFalse(model.session.hasPresentedIntegratedNarrative)
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "optional_action_invited" })

        model.draft = "我可以先写清楚判断标准，再决定先试哪一条"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(model.session.candidAgencyCompleted)
        XCTAssertTrue(model.session.hasCompletedAttributionExchange)
        XCTAssertTrue(model.session.hasPresentedIntegratedNarrative)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "integrated_reflection_narrative_presented"
            }
        )
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "optional_action_invited" })

        model.draft = "有一处不太对，我不是完全没有判断"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "integrated_reflection_narrative_revised"
            }
        )

        model.draft = "符合"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .optionalAction)
        XCTAssertTrue(model.session.integratedNarrativeConfirmed)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "optional_action_invited" })
        XCTAssertEqual(model.session.actionSuggestions.count, 1)
        XCTAssertTrue(model.session.messages.last?.content.contains("可以选一个") == true)

        model.draft = "这次先不决定行动"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .narrativeConfirmation)
        XCTAssertNil(model.session.context.selectedAction)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "optional_action_declined" })
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "final_narrative_presented" })

        model.draft = "最后一句需要改一下，我只是现在先不决定"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .narrativeConfirmation)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "final_narrative_revised" })

        model.draft = "符合"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .complete)
        XCTAssertEqual(model.session.stage, .completed)
        XCTAssertTrue(model.session.finalNarrativeConfirmed)

        let actions = model.session.studyEvents.map(\.action)
        let meaningShift = try XCTUnwrap(actions.firstIndex(of: "user_authored_card_meaning_shift"))
        let circumstances = try XCTUnwrap(actions.firstIndex(of: "candid_circumstances_completed"))
        let agency = try XCTUnwrap(actions.firstIndex(of: "candid_agency_completed"))
        let integrated = try XCTUnwrap(actions.firstIndex(of: "integrated_reflection_narrative_presented"))
        let integratedConfirmed = try XCTUnwrap(actions.firstIndex(of: "integrated_reflection_narrative_confirmed"))
        let action = try XCTUnwrap(actions.firstIndex(of: "optional_action_invited"))
        let finalNarrative = try XCTUnwrap(actions.firstIndex(of: "final_narrative_presented"))
        let completed = try XCTUnwrap(actions.firstIndex(of: "final_narrative_confirmed"))
        XCTAssertLessThan(circumstances, meaningShift)
        XCTAssertLessThan(meaningShift, agency)
        XCTAssertLessThan(agency, integrated)
        XCTAssertLessThan(integrated, integratedConfirmed)
        XCTAssertLessThan(integratedConfirmed, action)
        XCTAssertLessThan(action, finalNarrative)
        XCTAssertLessThan(finalNarrative, completed)
    }

    @MainActor
    func testNoMeaningShiftIsAValidUserAuthoredAnswer() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: InventedMeaningChangeGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardMeaningShift
        model.session.condition = .cardMediated
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "最近睡眠比平时短一些，但这只是已经确认的背景。"
        model.session.cardMappingConfirmed = true
        model.session.cardConfirmedMapping = "画面里持续发号施令的关系，和现实里不断催促自己的关系有些相似"
        model.session.cardGuidanceMatch = CardGuidanceMatch(
            matchedVisualAnchors: ["人"],
            candidateDirections: ["行动"],
            imageRelation: "一个人不断发号施令",
            realityRelation: "自己不断催促自己",
            matchedConcepts: [.action]
        )
        model.session.hasUserAuthoredCardConnection = true
        model.session.cardLifeConnection = "画面里不断发号施令的人让我想到自己一直催着自己"
        model.session.context.cardInterpretation = "一个人在发号施令"
        model.draft = "没有变化"

        model.send()
        await waitForModelIdle(model)

        XCTAssertTrue(model.session.cardMeaningShiftCompleted)
        XCTAssertEqual(model.session.cardMeaningShiftResponse, "没有变化")
        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "user_authored_card_meaning_shift" })
        let nextReply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(nextReply.contains("重新理解"))
        XCTAssertFalse(nextReply.contains("新看见"))
        XCTAssertTrue(nextReply.contains("没有改变"))
        XCTAssertFalse(nextReply.contains("睡眠"))
        XCTAssertTrue(
            model.session.studyEvents.contains { $0.action == "invented_card_meaning_change_suppressed" }
        )

        model.end()
        let summary = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(summary.contains("重新理解"))
        XCTAssertFalse(summary.contains("新看见"))
    }

    @MainActor
    func testCardDerivedNarrativeDoesNotAppendLockedTrackingBaseline() async {
        let model = ReflectionViewModel(
            analyzer: LatestBehaviorRelationAnalyzer(),
            dialogueGenerator: RepeatingLockedBaselineGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidAgency
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative =
            "最近睡眠比平时短，活动量也少；这些变化可能让当时更难保持清晰。"
        model.session.context.eventDescription = "一次已经确认的现实处境"
        model.session.context.confirmedTrackingCues = [
            workflowTrackingCue(metric: .sleepDuration, source: .healthSleep, difference: -45)
        ]
        model.session.context.cardInterpretation = "画面里一部分停住，另一部分还可以移动"
        model.session.cardMappingConfirmed = true
        model.session.cardConfirmedMapping = "画面里两部分的关系和现实中不同控制范围的关系有些相似"
        model.session.cardGuidanceMatch = CardGuidanceMatch(
            matchedVisualAnchors: ["移动"],
            candidateDirections: ["控制"],
            imageRelation: "不能整体移动的部分 与 可以移动的部分 并存",
            realityRelation: "暂时不能改变的条件 与 可以调整的回应 并存",
            matchedConcepts: [.control, .constraint]
        )
        model.session.candidCircumstancesResponse = "有些条件当时确实不能马上改变"
        model.session.cardMeaningShiftResponse = "我开始把外部条件和自己的回应分开看"
        model.session.cardMeaningShiftCompleted = true
        model.draft = "我愿意先检查自己可以调整的回应"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        let narrative = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(narrative.contains("睡眠"))
        XCTAssertFalse(narrative.contains("活动量"))
        XCTAssertTrue(narrative.contains("画面"))
        XCTAssertTrue(narrative.contains("分开看"))
    }

    @MainActor
    func testDrawingReplacementCardClearsPriorMeaningShift() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .cardIntroduction
        model.session.workflowPhase = .cardSelection
        model.session.cardWasSetAside = true
        model.session.cardMeaningShiftResponse = "上一张卡让我换了一个角度"
        model.session.cardMeaningShiftCompleted = true

        model.drawCard()

        XCTAssertNil(model.session.cardMeaningShiftResponse)
        XCTAssertFalse(model.session.cardMeaningShiftCompleted)
    }

    @MainActor
    func testAssistantInventedCardSymbolismIsSuppressedBeforeItReachesTheUser() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(),
            dialogueGenerator: InventedCardSymbolismGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "现实背景已经确认。"
        model.session.card = CardService().allCards.first { $0.title == "半开的门" }
        model.session.context.cardInterpretation = "一个人站着发号施令"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一个人站着发号施令")
        )
        model.draft = "这让我想到自己赶论文时一直催着自己往前"

        model.send()
        await waitForModelIdle(model)

        let response = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertFalse(response.contains("焦灼"))
        XCTAssertFalse(response.contains("反转"))
        XCTAssertFalse(response.contains("代表"))
        XCTAssertFalse(response.contains("象征"))
        XCTAssertTrue(model.session.studyEvents.contains {
            $0.action == "card_candidate_mapping_writer_output_rejected"
        })
    }

    @MainActor
    func testGenericCardSymbolismLanguageIsSuppressedWithoutUserEvidence() async {
        let model = ReflectionViewModel(
            analyzer: SemanticCardStructureAnalyzer(),
            dialogueGenerator: GenericCardSymbolismGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.contextSummaryConfirmed = true
        model.session.lockedBaselineNarrative = "现实背景已经确认。"
        model.session.card = CardService().allCards.first { $0.title == "半开的门" }
        model.session.context.cardInterpretation = "一个人背后有一对翅膀"
        model.session.messages.append(
            ChatMessage(role: .user, content: "一个人背后有一对翅膀")
        )
        model.draft = "这让我想到自己不确定该不该相信当前的结果"

        model.send()
        await waitForModelIdle(model)

        let response = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertFalse(response.contains("代表"))
        XCTAssertFalse(response.contains("暗示"))
        XCTAssertFalse(response.contains("意味着"))
        XCTAssertNil(model.session.cardGuidanceMatch)
        XCTAssertTrue(model.session.studyEvents.contains {
            $0.action == "card_candidate_mapping_without_guidance_intersection"
        })
        XCTAssertTrue(model.session.studyEvents.contains {
            $0.action == "card_candidate_mapping_writer_output_rejected"
        })
    }

    @MainActor
    func testIntegratedNarrativeReplacesGlobalLabelsButKeepsConfirmedBehavior() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: GlobalLabelNarrativeGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidAgency
        model.session.context.eventDescription = "论文还没交，我觉得自己太拖延了"
        model.session.context.emotions = ["挫败"]
        model.session.context.selfJudgment = "我太拖延了"
        model.session.context.contextualConstraints = ["应用还没有稳定，投稿时间很紧"]
        model.session.context.personalContributions = ["连续三个晚上刷视频，把实验开始时间往后放"]
        model.session.cardConnectionUnavailable = true
        model.session.cardWasSetAside = true
        model.session.candidCircumstancesCompleted = true
        model.session.candidCircumstancesResponse = "应用还没有稳定，投稿时间也很紧"
        model.draft = "我可以先停下重复试同一套方案，整理已有结果"

        model.send()
        await waitForModelIdle(model)

        let response = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertFalse(response.contains("拖延"))
        XCTAssertFalse(response.contains("没用"))
        XCTAssertTrue(response.contains("连续三个晚上刷视频"))
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "global_identity_label_suppressed_in_narrative"
            }
        )
    }

    @MainActor
    func testDirectConditionTurnsExplicitTaskSubstitutionIntoEditableFierceBoundary() async {
        let model = ReflectionViewModel(
            analyzer: WorkflowSemanticAnalyzer(),
            dialogueGenerator: StaticDialogueGenerator()
        )
        model.session.condition = .directLLM
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidCircumstances
        model.session.messages.append(
            ChatMessage(
                role: .user,
                content: "我需要做实验结果分析，但一直在整理不重要的文件。"
            )
        )
        model.draft = "就是自己明明知道该分析，却总转去整理文件。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(model.session.workflowPhase, .candidAgency)
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(reply.contains("懒"))
        XCTAssertFalse(reply.contains("论文"))
        XCTAssertFalse(reply.contains("导师"))
    }

    @MainActor
    func testDirectConditionDoesNotInventFierceTargetFromDistressAlone() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.condition = .directLLM
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .candidCircumstances
        model.session.context.eventDescription = "今天在组会上被导师批评了"
        model.session.context.emotions = ["羞愧"]
        model.session.context.selfJudgment = "我觉得自己很差"
        model.draft = "当时很难受，也很害怕别人怎么看我。"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .reflectionNarrativeConfirmation)
        XCTAssertTrue(model.session.candidAgencyCompleted)
        XCTAssertNil(model.session.candidAgencyResponse)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "fierce_reflection_not_invited_without_user_supported_focus"
            }
        )
    }

    @MainActor
    func testEmotionFallbackDoesNotUseTaskProgressQuestionForGlobalSelfJudgment() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: FailingDialogueGenerator())
        model.session.stage = .emotionDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.context.eventDescription = "今天组会上被导师批评了"
        model.session.context.selfJudgment = "我根本不适合做科研"
        model.draft = "我觉得大家肯定都认为我很差。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(reply.contains("一直没开始"))
        XCTAssertFalse(reply.contains("很难推进"))
    }

    @MainActor
    func testEmotionTurnReframesRepeatedCriticismDetailProbe() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: EventDetailProbeDialogueGenerator()
        )
        model.session.stage = .emotionDisclosure
        model.session.workflowPhase = .structuredDisclosure
        model.session.context.eventDescription = "今天组会上被导师批评了"
        model.draft = "我觉得大家肯定都认为我很差。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
        XCTAssertFalse(reply.contains("我们先不重复追问"))
        XCTAssertFalse(reply.contains("这个方向已经说清楚"))
    }

    @MainActor
    func testPersonalMeaningFallbackDoesNotInventDeadlineOrPerformanceContext() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: FailingDialogueGenerator())
        model.session.stage = .bodilyResponse
        model.session.workflowPhase = .structuredDisclosure
        model.session.context.eventDescription = "我和朋友吵架了"
        model.session.context.emotions = ["难过"]
        model.draft = "当时心跳很快。"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("这件事之后"))
        XCTAssertFalse(reply.contains("结果可能来不及"))
        XCTAssertFalse(reply.contains("做不好"))
    }

    @MainActor
    func testFirstConcreteActionChoiceIsAcceptedAndCompletesWithoutReconfirmation() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .optionalAction
        model.session.integratedNarrativeConfirmed = true
        model.session.actionSuggestions = [
            ActionSuggestion(category: .change, description: "用十分钟整理最近三次尝试和结果", rationale: "缩小范围"),
            ActionSuggestion(category: .provide, description: "写下一个问题后向导师请教", rationale: "降低沟通负担"),
        ]
        model.draft = "第二个"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .complete)
        XCTAssertEqual(model.session.stage, .completed)
        XCTAssertEqual(model.session.context.selectedAction?.description, "写下一个问题后向导师请教")
        XCTAssertEqual(model.session.context.selectedAction?.acceptedByUser, true)
        XCTAssertTrue(model.session.userAuthoredActionConfirmed)
        XCTAssertTrue(model.session.finalNarrativeConfirmed)
    }

    @MainActor
    func testNoGroundedPracticeDirectionDoesNotInventAnAction() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: UnsafeEndedRelationshipActionGenerator()
        )
        model.session.condition = .cardMediated
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .reflectionNarrativeConfirmation
        model.session.integratedNarrativeConfirmed = false
        model.session.context.eventDescription = "我和谈了三年的人刚分手一周"
        model.session.context.emotions = ["伤心"]
        model.session.context.personalContributions = ["吵架的时候没有沟通"]
        model.session.candidAgencyResponse = "生气后会停止沟通，没有说出自己的需要"
        model.session.candidAgencyCompleted = true
        model.session.cardMeaningShiftResponse = "也许不能只看争执的细节，还要看它承载了什么"
        model.session.messages = [
            ChatMessage(role: .user, content: "我们刚分手一周，异地期间经常会吵架"),
        ]
        model.draft = "符合"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .optionalAction)
        XCTAssertTrue(model.session.actionSuggestions.isEmpty)
        model.draft = "这次先不设置行动"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .narrativeConfirmation)
        model.draft = "符合"
        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .complete)
        XCTAssertEqual(model.session.stage, .completed)
        let completion = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertFalse(completion.contains("准备可以在下次补上"))
        XCTAssertFalse(completion.contains("下次想吵"))
        XCTAssertFalse(completion.contains("这段理解里，有哪一句"))
        XCTAssertFalse(completion.contains("你确认先做的一小步"))
    }

    @MainActor
    func testExplicitPracticeRequestOverridesLateAccuracyGateWithCareOnly() async {
        let model = ReflectionViewModel(
            analyzer: CrossStageResponsePlanAnalyzer(),
            dialogueGenerator: CrossStageResponsePlanDialogueGenerator()
        )
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .narrativeConfirmation
        model.session.hasPresentedFinalNarrative = true
        model.session.finalNarrativeConfirmed = false
        model.session.actionSuggestions = []
        model.draft = "你有没有什么实践建议呢"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .optionalAction)
        XCTAssertEqual(model.session.actionSuggestions.count, 1)
        XCTAssertEqual(model.session.actionSuggestions.first?.category, .care)
        XCTAssertFalse(model.session.messages.last?.content.contains("请直接说符合") == true)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "semantic_practice_request_overrode_late_gate"
            }
        )
    }

    @MainActor
    func testNaturalActionRejectionAndAmbiguousAcknowledgmentDoNotBecomeActions() async {
        let rejected = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        rejected.session.stage = .attributionReflection
        rejected.session.workflowPhase = .optionalAction
        rejected.session.integratedNarrativeConfirmed = true
        rejected.session.actionSuggestions = [
            ActionSuggestion(category: .change, description: "用十分钟整理最近三次尝试", rationale: "small"),
            ActionSuggestion(category: .provide, description: "写下一个问题后请教导师", rationale: "small"),
        ]
        rejected.draft = "这两个都不适合我"

        rejected.send()
        await waitForModelIdle(rejected)

        XCTAssertEqual(rejected.session.workflowPhase, .narrativeConfirmation)
        XCTAssertNil(rejected.session.pendingUserAuthoredAction)
        XCTAssertNil(rejected.session.context.selectedAction)

        let ambiguous = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        ambiguous.session.stage = .attributionReflection
        ambiguous.session.workflowPhase = .optionalAction
        ambiguous.session.integratedNarrativeConfirmed = true
        ambiguous.session.actionSuggestions = rejected.session.actionSuggestions
        ambiguous.draft = "可以"

        ambiguous.send()
        await waitForModelIdle(ambiguous)

        XCTAssertEqual(ambiguous.session.workflowPhase, .optionalAction)
        XCTAssertNil(ambiguous.session.pendingUserAuthoredAction)
        XCTAssertNil(ambiguous.session.context.selectedAction)
        XCTAssertTrue(
            ambiguous.session.studyEvents.contains { $0.action == "optional_action_selection_unclear" }
        )
    }

    func testLegacySingularPendingTrackingCueMigratesIntoBundle() throws {
        var session = ReflectionSession()
        session.pendingTrackingCueID = "legacy-sleep-cue"
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
        )
        payload.removeValue(forKey: "pendingTrackingCueIDs")

        let decoded = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.pendingTrackingCueID, "legacy-sleep-cue")
        XCTAssertEqual(decoded.pendingTrackingCueIDs, ["legacy-sleep-cue"])
    }

    func testLegacyCardConnectionResumesAtNewMeaningShiftGate() throws {
        var session = ReflectionSession()
        session.stage = .attributionReflection
        session.workflowPhase = .candidCircumstances
        session.hasUserAuthoredCardConnection = true
        session.cardLifeConnection = "这个画面让我想到自己一直催着自己"
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
        )
        payload.removeValue(forKey: "workflowPhase")
        payload.removeValue(forKey: "cardMeaningShiftResponse")
        payload.removeValue(forKey: "cardMeaningShiftCompleted")
        payload.removeValue(forKey: "hasUserAuthoredCardConnection")

        let decoded = try JSONDecoder().decode(
            ReflectionSession.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.workflowPhase, .cardMappingConfirmation)
        XCTAssertFalse(decoded.cardMeaningShiftCompleted)
    }

    @MainActor
    func testLegacyExplicitCircumstancesPhaseNormalizesToMissingMeaningShiftOnResume() async {
        var legacy = ReflectionSession()
        legacy.stage = .attributionReflection
        legacy.workflowPhase = .candidCircumstances
        legacy.hasUserAuthoredCardConnection = true
        legacy.cardLifeConnection = "这个画面让我想到自己一直催着自己"
        legacy.context.cardInterpretation = "一个人在发号施令"
        legacy.cardMeaningShiftResponse = nil
        legacy.cardMeaningShiftCompleted = false
        legacy.candidCircumstancesCompleted = false
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())

        model.resume(
            ResumableReflection(
                id: legacy.id.uuidString,
                remoteID: nil,
                session: legacy,
                updatedAt: .now
            )
        )
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.workflowPhase, .candidCircumstances)
        XCTAssertTrue(
            model.session.studyEvents.contains {
                $0.action == "legacy_card_connection_resumed_at_circumstances"
            }
        )
    }

    @MainActor
    func testSafetyOverrideInterruptsNaturalCardAcceptance() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .readinessCheck
        var analysis = ContextAnalysis.fallback()
        analysis.safetyOverride = true
        model.session.latestAnalysis = analysis
        model.draft = "好，抽一张看看"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .safetySupport)
        XCTAssertNil(model.session.card)
    }

    @MainActor
    func testReadinessTransitionSoundsInvitedRatherThanAnnounced() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .tenderGrounding
        model.draft = "我这周真的很累，也确实没有及时和导师沟通"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertFalse(model.session.messages.last?.content.contains("阶段") == true)
    }

    @MainActor
    func testUserCanAskToReviseActionOptionsInTheirOwnWords() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .actionSelection
        model.draft = "这些对我还是太多了，我只想先发一句简短的消息"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.stage, .actionSelection)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "action_options_revision_requested" })
        XCTAssertTrue(model.session.actionSuggestions.isEmpty)
        XCTAssertTrue(model.session.messages.last?.content.contains("不一定需要定行动") == true)
    }

    func testActionCategoryTitlesUseNaturalChinese() {
        XCTAssertEqual(CompassionateActionCategory.care.title, "先照顾自己")
        XCTAssertEqual(CompassionateActionCategory.repair.title, "修复一次沟通")
    }

    @MainActor
    func testAcceptedActionIsExplicitlyMarked() {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .actionSelection
        model.session.hasUserAuthoredCardConnection = true
        model.session.hasCompletedAttributionExchange = true
        model.session.hasPresentedIntegratedNarrative = true
        model.chooseAction(ActionSuggestion(category: .repair, description: "发送一条具体说明", rationale: "small"))
        XCTAssertEqual(model.session.stage, .summary)
        XCTAssertEqual(model.session.context.selectedAction?.acceptedByUser, true)
    }

    @MainActor
    func testVagueCardFitCannotAdvanceToNarrativeOrAction() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.card = ReflectionCard(id: 1, neutralLabel: "图像 2", imageName: "2", reflectiveThemes: "unused")
        model.session.context.cardInterpretation = "这个人看起来正面，但翅膀让我怀疑他是不是可信"
        model.draft = "我觉得有一些类似"

        model.send()
        await waitForModelIdle(model)

        XCTAssertEqual(model.session.stage, .attributionReflection)
        XCTAssertFalse(model.session.hasUserAuthoredCardConnection)
        XCTAssertFalse(model.session.hasCompletedAttributionExchange)
        XCTAssertFalse(model.session.hasPresentedIntegratedNarrative)
        XCTAssertTrue(model.session.actionSuggestions.isEmpty)
        XCTAssertEqual(model.session.cardConnectionAttemptCount, 1)
        XCTAssertTrue(model.session.studyEvents.contains { $0.action == "card_connection_retried_once" })
        XCTAssertFalse(model.session.studyEvents.contains { $0.action == "optional_action_invited" })
    }

    @MainActor
    func testTypedUserTurnOwnsAtMostOneAssistantReply() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: StaticDialogueGenerator())
        model.session.stage = .attributionReflection
        model.session.workflowPhase = .cardConnection
        model.session.context.cardInterpretation = "一个人站在两条路中间"
        model.draft = "我觉得有一些类似"

        model.send()
        await waitForModelIdle(model)

        let userMessageID = model.session.messages.last(where: { $0.role == .user })?.id
        XCTAssertNotNil(userMessageID)
        let replies = model.session.messages.filter {
            $0.role == .assistant && $0.replyToMessageID == userMessageID
        }
        XCTAssertEqual(replies.count, 1)
        XCTAssertNotNil(replies.first?.assistantGenerationID)
    }
}

final class ReflectionFailureTests: XCTestCase {
    func testInvalidAnalyzerJSONThrowsWithoutInventingAnalysis() {
        XCTAssertThrowsError(try ContextAnalysisParser.parse("not json"))
    }

    func testMissingAnalyzerFieldsPreserveUnknowns() throws {
        let parsed = try ContextAnalysisParser.parse("{}")
        XCTAssertEqual(parsed.consentToCandor, .unknown)
        XCTAssertEqual(parsed.eventType, .unclear)
        XCTAssertEqual(parsed.taskProgressStatus, .notApplicable)
        XCTAssertFalse(parsed.userAdmittedBehavior)
        XCTAssertTrue(parsed.behaviorEvidence.isEmpty)
        XCTAssertEqual(parsed.pastControllability, .unknown)
        XCTAssertEqual(parsed.presentAgency, .unknown)
        XCTAssertEqual(parsed.recommendedRoute, .explore)
        XCTAssertTrue(parsed.personalContributions.isEmpty)
        XCTAssertNil(parsed.responsePlan)
    }

    func testAnalyzerParsesTypedResponsePlanWithoutTurningItIntoDialogue() throws {
        let parsed = try ContextAnalysisParser.parse(
            """
            {
              "semanticRelations":[{
                "kind":"selfEvaluation",
                "source":"测试失败",
                "relation":"被扩大为",
                "target":"整体能力判断",
                "concepts":["selfEvaluation","ability"],
                "evidence":["测试一直失败","能力不行"],
                "status":"userStated",
                "confidence":0.9
              }],
              "responsePlan":{
                "function":"clarifyPersonalMeaning",
                "focus":"失败和整体能力判断之间的关系",
                "evidence":["测试一直失败","能力不行"],
                "relationKinds":["selfEvaluation"],
                "questionIntent":"询问整体判断背后的具体担心",
                "shouldAskQuestion":true,
                "confidence":0.88
              },
              "confidence":0.9
            }
            """
        )

        XCTAssertEqual(parsed.responsePlan?.function, .clarifyPersonalMeaning)
        XCTAssertEqual(parsed.responsePlan?.relationKinds, [.selfEvaluation])
        XCTAssertTrue(parsed.responsePlan?.shouldAskQuestion == true)
    }

    func testPersistedAnalysisWithoutSemanticRelationsStillDecodes() throws {
        var current = ContextAnalysis()
        current.confidence = 0.8
        current.semanticRelations = [
            SemanticRelation(
                kind: .uncertainty,
                source: "当前信息",
                relation: "仍不足以确定",
                target: "完整原因",
                concepts: [.uncertainty],
                evidence: ["还不确定"],
                status: .userStated,
                confidence: 0.8
            )
        ]
        let encoded = try JSONEncoder().encode(current)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "semanticRelations")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ContextAnalysis.self, from: legacyData)

        XCTAssertTrue(decoded.resolvedSemanticRelations.isEmpty)
        XCTAssertEqual(decoded.confidence, 0.8, accuracy: 0.001)
    }

    func testAnalyzerSemanticCandidatesRequireLiteralBehaviorEvidence() throws {
        let parsed = try ContextAnalysisParser.parse(
            """
            {"eventType":"taskProgress","taskProgressStatus":"startedButStalled",
            "userAdmittedBehavior":true,"confirmedBehavior":"转去整理文件",
            "behaviorEvidence":["打开了看几行就去整理文件"],
            "semanticRelations":[
              {"kind":"behaviorImpact","source":"转去整理文件","relation":"让","target":"结果分析继续停在那里",
               "concepts":["change","stagnation"],"evidence":["打开了看几行就去整理文件"],
               "status":"userStated","confidence":0.88}
            ],"confidence":0.88}
            """
        )
        XCTAssertEqual(parsed.eventType, .taskProgress)
        XCTAssertEqual(parsed.taskProgressStatus, .startedButStalled)
        XCTAssertTrue(parsed.userAdmittedBehavior)
        XCTAssertEqual(parsed.behaviorEvidence, ["打开了看几行就去整理文件"])
        XCTAssertEqual(parsed.resolvedSemanticRelations.first?.kind, .behaviorImpact)
        XCTAssertEqual(
            Set(parsed.resolvedSemanticRelations.first?.concepts ?? []),
            Set([.change, .stagnation])
        )

        let unsupported = try ContextAnalysisParser.parse(
            "{\"userAdmittedBehavior\":true,\"confirmedBehavior\":\"模型猜测\",\"behaviorEvidence\":[]}"
        )
        XCTAssertFalse(unsupported.userAdmittedBehavior)
        XCTAssertNil(unsupported.confirmedBehavior)
    }

    func testDialogueJSONMayOmitActionOptions() throws {
        let parsed = try DialogueTurnParser.parse(
            "{\"reflection\":\"这件事还留在心里。\",\"question\":\"后来发生了什么？\"}"
        )
        XCTAssertEqual(parsed.reflection, "这件事还留在心里。")
        XCTAssertEqual(parsed.question, "后来发生了什么？")
        XCTAssertEqual(parsed.actionOptions, [])
    }

    func testDialogueJSONMayOmitOptionalVisibleFields() throws {
        let parsed = try DialogueTurnParser.parse(
            "{\"actionOptions\":[{\"category\":\"care\",\"description\":\"休息五分钟\",\"timing\":null,\"rationale\":\"小而可行\"}]}"
        )
        XCTAssertEqual(parsed.reflection, "")
        XCTAssertEqual(parsed.question, "")
        XCTAssertEqual(parsed.actionOptions.first?.description, "休息五分钟")
    }

    @MainActor
    func testNetworkFailureIsRecoverableAndDoesNotCorruptState() async {
        let model = ReflectionViewModel(analyzer: StaticAnalyzer(), dialogueGenerator: FailingDialogueGenerator())
        model.begin()
        model.draft = "昨天我错过了投稿截止时间"
        model.send()
        await waitForAsyncWork()
        XCTAssertEqual(model.session.context.eventDescription, "昨天我错过了投稿截止时间")
        XCTAssertEqual(model.session.stage, .emotionDisclosure)
        XCTAssertTrue(model.canRetry)
        XCTAssertFalse(model.session.messages.last?.content.contains("保留你刚才写下的内容") == true)
        XCTAssertFalse(model.session.messages.last?.content.isEmpty == true)
    }

    @MainActor
    func testTenderFallbackUsesNaturalProseInsteadOfStructuredFieldStitching() async {
        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session.stage = .selfJudgment
        model.session.workflowPhase = .structuredDisclosure
        model.session.context.eventDescription = "我今天在组会上被导师批评了，我感觉自己特别差，甚至不想再做研究了。"
        model.session.context.emotions = ["羞愧", "特别差"]
        model.session.context.bodilyResponses = ["脸发热"]
        model.session.context.selfJudgment = "我感觉自己特别差"
        model.session.context.contextualConstraints = ["组会上公开收到批评"]
        model.session.bodyExplorationCompleted = true
        model.session.structuredDisclosureAssistantTurns = 4
        model.draft = "我一直觉得大家会认为我能力不行"

        model.send()
        await waitForModelIdle(model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("组会上被导师批评"))
        XCTAssertTrue(reply.contains("羞愧"))
        XCTAssertTrue(reply.contains("脸发热"))
        XCTAssertFalse(reply.contains("这次具体发生的是我"))
        XCTAssertFalse(reply.contains("你这次说到的是"))
        XCTAssertFalse(reply.contains("感受包括"))
        XCTAssertFalse(reply.contains("身体上的变化"))
        XCTAssertFalse(reply.contains("特别差、羞愧"))
        XCTAssertFalse(reply.contains("担心很羞愧"))
        XCTAssertEqual(reply.filter { $0 == "？" || $0 == "?" }.count, 1)
    }

    @MainActor
    func testUnavailableTrackingIsExplainedInsteadOfSilentlySkippingToCard() async {
        var session = ReflectionSession()
        session.stage = .readinessCheck
        session.workflowPhase = .contextConfirmation
        session.trackingReviewCompleted = true
        session.trackingReviewUnavailable = true
        session.context.eventDescription = "我今天在组会上被导师批评了"
        session.context.emotions = ["羞愧"]
        session.context.selfJudgment = "我感觉自己特别差"

        let model = ReflectionViewModel(
            analyzer: StaticAnalyzer(),
            dialogueGenerator: FailingDialogueGenerator()
        )
        model.session = session
        await sendAndWait("这里需要改", to: model)

        let reply = model.session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(reply.contains("没有形成足够可靠的近期状态线索"))
        XCTAssertTrue(reply.contains("不根据缺失线索作判断"))
        XCTAssertEqual(model.session.stage, .readinessCheck)
        XCTAssertEqual(model.session.workflowPhase, .contextConfirmation)
        XCTAssertNil(model.session.card)
    }
}

private struct StaticAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.nextQuestionGoal = "one concrete detail"
        return analysis
    }
}

private struct SelfEvaluationAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.confidence = 0.9
        let evidence = "我觉得自己太拖延了"
        analysis.selfJudgment = evidence
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "当前的具体进展",
                relation: "被扩大为",
                target: evidence,
                concepts: [.selfEvaluation, .judgment],
                evidence: [evidence],
                status: .userStated,
                confidence: 0.9
            )
        ]
        return analysis
    }
}

private struct SemanticCardMappingAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.nextQuestionGoal = "deepen the user-authored image-to-reality mapping"
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .imageRealityMapping,
                source: "绳子捆住罐子，裂缝还是在",
                relation: "对应",
                target: "调模型也是修修补补却没有效果",
                concepts: [.problemSolving, .selfEvaluation],
                evidence: [
                    "绳子捆住罐子，裂缝还是在",
                    "调模型也是修修补补却没有效果",
                ],
                status: .userStated,
                confidence: 0.92
            )
        ]
        analysis.confidence = 0.92
        return analysis
    }
}

private struct SemanticCardStructureAnalyzer: ContextAnalyzing {
    let concepts: [SemanticConcept]

    init(concepts: [SemanticConcept] = [.constraint, .control, .problemSolving, .action]) {
        self.concepts = concepts
    }

    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.confidence = 0.9

        let userMessages = messages.filter { $0.role == .user }.map(\.content)
        guard let realityEvidence = userMessages.last,
              let imageNarrative = context.cardInterpretation,
              let imageEvidence = userMessages.dropLast().last(where: {
                  imageNarrative.contains($0) || $0.contains(imageNarrative)
              }) else {
            return analysis
        }
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .imageStructure,
                source: "画面中暂时不能整体改变的部分",
                relation: "与",
                target: "能够先发生变化的部分并存",
                concepts: concepts,
                evidence: [imageEvidence],
                status: .userStated,
                confidence: 0.9
            ),
            SemanticRelation(
                kind: .realityStructure,
                source: "现实中暂时不能整体改变的部分",
                relation: "与",
                target: "能够单独回看的部分并存",
                concepts: concepts,
                evidence: [realityEvidence],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        return analysis
    }
}

private struct LatestBehaviorRelationAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.confidence = 0.9
        guard let evidence = messages.last(where: { $0.role == .user })?.content else {
            return analysis
        }
        analysis.userAdmittedBehavior = true
        analysis.confirmedBehavior = evidence
        analysis.behaviorEvidence = [evidence]
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .behaviorImpact,
                source: evidence,
                relation: "是用户愿意具体回看的部分",
                target: "当前处境中的可调整回应",
                concepts: [.change, .communication],
                evidence: [evidence],
                status: .userStated,
                confidence: 0.9
            )
        ]
        return analysis
    }
}

/// A domain-neutral analyzer fixture for end-to-end workflow tests. It models the typed relation
/// contract rather than recognizing any test scenario vocabulary.
private struct WorkflowSemanticAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.reflectiveCapacity = 2
        analysis.consentToCandor = .yes
        analysis.confidence = 0.9
        let userMessages = messages.filter { $0.role == .user }.map(\.content)
        guard let latest = userMessages.last else { return analysis }

        var relations: [SemanticRelation] = []
        if let imageNarrative = context.cardInterpretation,
           let imageEvidence = userMessages.reversed().first(where: {
               imageNarrative.contains($0) || $0.contains(imageNarrative)
           }) {
            relations.append(
                SemanticRelation(
                    kind: .imageStructure,
                    source: "画面中的两个部分",
                    relation: "形成",
                    target: "一个尚未解决的关系",
                    concepts: [.choice, .uncertainty],
                    evidence: [imageEvidence],
                    status: .userStated,
                    confidence: 0.9
                )
            )
            let affirmation = ["贴近", "符合", "是的", "对"].contains {
                latest.filter { $0.isLetter || $0.isNumber } ==
                    $0.filter { $0.isLetter || $0.isNumber }
            }
            let realityEvidence = affirmation
                ? userMessages.dropLast().reversed().first(where: { candidate in
                    !imageNarrative.contains(candidate) && candidate.count >= 4
                })
                : latest
            if let realityEvidence {
                relations.append(
                    SemanticRelation(
                        kind: .realityStructure,
                        source: "现实中的两个部分",
                        relation: "形成",
                        target: "一个尚未解决的关系",
                        concepts: [.choice, .uncertainty],
                        evidence: [realityEvidence],
                        status: .userStated,
                        confidence: 0.9
                    )
                )
                if affirmation {
                    relations.append(
                        SemanticRelation(
                            kind: .imageRealityMapping,
                            source: "用户描述的画面关系",
                            relation: "与",
                            target: "用户描述的现实关系相似",
                            concepts: [.choice, .uncertainty],
                            evidence: [imageEvidence, realityEvidence],
                            status: .userConfirmed,
                            confidence: 0.9
                        )
                    )
                }
            }
        } else {
            relations.append(
                SemanticRelation(
                    kind: .behaviorImpact,
                    source: latest,
                    relation: "是用户愿意具体检查的回应",
                    target: "当前处境中的可调整部分",
                    concepts: [.change],
                    evidence: [latest],
                    status: .userStated,
                    confidence: 0.9
                )
            )
            analysis.userAdmittedBehavior = true
            analysis.confirmedBehavior = latest
            analysis.behaviorEvidence = [latest]
        }
        relations.append(
            SemanticRelation(
                kind: .controllablePart,
                source: latest,
                relation: "包含",
                target: "用户愿意考虑的一个可调整部分",
                concepts: [.change, .choice],
                evidence: [latest],
                status: .userStated,
                confidence: 0.85
            )
        )
        analysis.semanticRelations = relations
        return analysis
    }
}

private struct StaticDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(reflection: "我记下了这个具体部分。", question: "接下来最明显的是什么？", actionOptions: [])
    }
}

private struct PlannedMeaningAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        var analysis = ContextAnalysis()
        analysis.eventDescription = "系统测试持续失败"
        analysis.selfJudgment = "自己能力不行"
        analysis.contextualConstraints = ["截止时间快到了"]
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "测试一直失败",
                relation: "被扩大为",
                target: "自己能力不行",
                concepts: [.selfEvaluation, .ability],
                evidence: ["测试一直失败", "自己能力不行"],
                status: .userStated,
                confidence: 0.92
            ),
            SemanticRelation(
                kind: .conditionCapacity,
                source: "截止时间快到了",
                relation: "压缩",
                target: "处理问题的时间",
                concepts: [.constraint, .overload],
                evidence: ["截止时间快到了"],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = ResponsePlan(
            function: .clarifyPersonalMeaning,
            focus: "持续失败和时间限制如何牵动整体能力判断",
            evidence: ["截止时间快到了", "测试一直失败", "自己能力不行"],
            relationKinds: [.selfEvaluation, .conditionCapacity],
            questionIntent: "询问整体能力判断背后最担心的具体结果",
            shouldAskQuestion: true,
            confidence: 0.91
        )
        analysis.confidence = 0.9
        return analysis
    }
}

private struct RelationOnlyMeaningAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        guard let latest = messages.last(where: { $0.role == .user })?.content else {
            return .fallback()
        }
        var analysis = ContextAnalysis()
        analysis.eventDescription = latest
        analysis.selfJudgment = "不适合继续做这件事"
        analysis.semanticRelations = [
            SemanticRelation(
                kind: .selfEvaluation,
                source: "重要尝试再次没有成功",
                relation: "被扩大为",
                target: "不适合继续做这件事",
                concepts: [.selfEvaluation, .ability],
                evidence: ["再次没有成功", "不适合继续做这件事"],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = nil
        analysis.confidence = 0.9
        return analysis
    }
}

private struct ResponsePlanDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "",
            question: "这件事现在最让你担心什么？",
            actionOptions: []
        )
    }

    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        guard promptEvidence.responsePlan?.function == .clarifyPersonalMeaning else {
            return DialogueTurn(
                reflection: "",
                question: "这件事发生时，你当时最明显的感受是什么？",
                actionOptions: []
            )
        }
        return DialogueTurn(
            reflection: "反复没有得到可用结果，已经开始牵动你怎么看自己的能力。",
            question: "你开始这样看自己时，最担心接下来会发生什么？",
            actionOptions: []
        )
    }
}

private struct CrossStageResponsePlanAnalyzer: ContextAnalyzing {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        .fallback()
    }

    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis {
        guard let latest = messages.last(where: { $0.role == .user })?.content,
              let planningContext else {
            return .fallback()
        }
        var analysis = ContextAnalysis()
        analysis.confidence = 0.9

        let function: ResponseFunction
        let kind: SemanticRelationKind
        let concepts: [SemanticConcept]
        switch planningContext.state {
        case .tenderExploration:
            function = .deepenTenderUnderstanding
            kind = .unmetNeed
            concepts = [.support, .connection]
        case .cardInterpretation:
            function = .developImageRelation
            kind = .imageStructure
            concepts = [.relationship, .uncertainty]
        case .actionSelection:
            function = .proposePractice
            kind = .controllablePart
            concepts = [.change, .choice]
        case .attributionReflection where planningContext.workflowPhase == .candidAgency:
            function = .exploreAgencyBoundaryOrChange
            kind = .controllablePart
            concepts = [.change, .choice]
        case .attributionReflection where [
            ReflectionWorkflowPhase.reflectionNarrativeConfirmation,
            .optionalAction,
            .narrativeConfirmation,
        ].contains(planningContext.workflowPhase):
            function = .proposePractice
            kind = .unmetNeed
            concepts = [.support, .choice]
        default:
            return .fallback()
        }
        guard planningContext.allowedFunctions.contains(function) else {
            return .fallback()
        }
        analysis.semanticRelations = [
            SemanticRelation(
                kind: kind,
                source: latest,
                relation: "包含",
                target: "当前回合需要继续理解的关系",
                concepts: concepts,
                evidence: [latest],
                status: .userStated,
                confidence: 0.9
            ),
        ]
        analysis.responsePlan = ResponsePlan(
            function: function,
            focus: "跟随用户这一回合表达的关系",
            evidence: [latest],
            relationKinds: [kind],
            questionIntent: "自然承接当前用户意图",
            shouldAskQuestion: true,
            confidence: 0.9
        )
        return analysis
    }
}

private struct CrossStageResponsePlanDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "",
            question: "你想补充哪一点？",
            actionOptions: []
        )
    }

    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        switch promptEvidence.responsePlan?.function {
        case .deepenTenderUnderstanding:
            return DialogueTurn(
                reflection: "你希望自己的话能先被完整听见。",
                question: "这里面最需要被理解的是什么？",
                actionOptions: []
            )
        case .developImageRelation:
            return DialogueTurn(
                reflection: "",
                question: "沿着你看到的关系，接下来可能发生什么？",
                actionOptions: []
            )
        case .proposePractice:
            return DialogueTurn(
                reflection: "",
                question: "",
                actionOptions: [
                    DialogueActionOption(
                        category: .change,
                        description: "今天先做五分钟，再决定是否继续",
                        timing: "今天",
                        rationale: "这是用户已经提出的可调整范围"
                    ),
                ]
            )
        case .exploreAgencyBoundaryOrChange:
            let latest = messages.last(where: { $0.role == .user })?.content ?? "这个方向"
            return DialogueTurn(
                reflection: "你希望自己当时能\(latest)。",
                question: "具体到那个时刻，这会是什么做法？",
                actionOptions: []
            )
        case .some:
            return DialogueTurn(
                reflection: "",
                question: "这个旧计划最担心什么？",
                actionOptions: []
            )
        default:
            return DialogueTurn(
                reflection: "",
                question: "想到这件事时，你现在有什么感受？",
                actionOptions: []
            )
        }
    }
}

/// Simulates the Writer while asserting that Swift supplied one exact locally selected Tender
/// direction rather than the whole card catalogue. The resulting user-visible questions differ
/// by reflective function, not merely by card metadata.
private struct SelectedTenderLensDialogueGenerator: DialogueGenerating {
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
        if nextQuestionGoal.contains("保持距离可能是在保护安全、精力或尊严"),
           !nextQuestionGoal.contains("拒绝不等于冷漠或自私") {
            return DialogueTurn(
                reflection: "保持距离可能也在保护你当时能承受的范围。",
                question: "在这段距离里，当时最需要先被保护的是什么？",
                actionOptions: []
            )
        }
        if nextQuestionGoal.contains("做错一件事不等于整个人失败"),
           !nextQuestionGoal.contains("羞愧可以被看见") {
            return DialogueTurn(
                reflection: "先把整个人的判断放下，眼前是一个具体影响。",
                question: "这个具体影响里，哪一部分让你当时最难受？",
                actionOptions: []
            )
        }
        return DialogueTurn(
            reflection: "",
            question: "这段关系里，当时有哪些真实情况需要先被理解？",
            actionOptions: []
        )
    }
}

private struct CardCandidateMappingGenerator: DialogueGenerating {
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
        if nextQuestionGoal.contains("imageStructure"),
           analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .imageStructure }) == true,
           analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .realityStructure }) == true {
            return DialogueTurn(
                reflection: "一个可能的方向是：画面和现实里都同时存在暂时无法改变的部分，以及当前能够单独回看的一部分。",
                question: "",
                actionOptions: []
            )
        }
        return DialogueTurn(
            reflection: "我记下了这个具体部分。",
            question: "接下来最明显的是什么？",
            actionOptions: []
        )
    }
}

private struct ContextSummaryWithEmbeddedQuestionGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "好，那这个背景就先放在这里。拒稿之后，你觉得自己和之前相比，有什么不一样的地方吗？",
            question: "",
            actionOptions: []
        )
    }
}

private struct InventedCardStoryGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这个动作里好像有一种很自然的靠近。",
            question: "你觉得她为什么会继续这样做？",
            actionOptions: []
        )
    }
}

private struct PrematureSingularRelationshipGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "后悔的是那一次没有沟通，不是整个人不够体贴。",
            question: "这段理解里，有哪一句不像你的想法？",
            actionOptions: []
        )
    }
}

private struct UnsafeEndedRelationshipActionGenerator: DialogueGenerating {
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
        if state == .actionSelection {
            return DialogueTurn(
                reflection: "",
                question: "",
                actionOptions: [
                    DialogueActionOption(
                        category: .change,
                        description: "下次想吵时，先问自己细节重要还是感情重要",
                        timing: "下次冲突时",
                        rationale: "避免争吵"
                    ),
                    DialogueActionOption(
                        category: .repair,
                        description: "联系对方重新沟通",
                        timing: "今天",
                        rationale: "尝试修复"
                    ),
                ]
            )
        }
        return DialogueTurn(
            reflection: "也有一部分准备可以在下次补上：吵架的时候没有沟通。这个表达有点抽象。",
            question: "这段理解里，有哪一句不像你的想法？",
            actionOptions: []
        )
    }
}

private struct EventDetailProbeDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "被批评后马上想到别人会怎么看你，这种担心很真实。",
            question: "导师具体说了什么，让你觉得最难受？",
            actionOptions: []
        )
    }
}

private struct GoalEchoingDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(reflection: nextQuestionGoal, question: "", actionOptions: [])
    }
}

private struct RepeatedDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "固定重复回答标记：这是一段会被模型再次返回的较长回答内容。",
            question: "那一刻，接下来发生了什么？",
            actionOptions: []
        )
    }
}

private struct EchoingDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: messages.last(where: { $0.role == .user })?.content ?? "",
            question: "这件事里，哪一部分最让你放不下？",
            actionOptions: []
        )
    }
}

private struct PartialRestatementDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "你最近在准备投稿论文，但一直没有写完。我们先不急着下结论。",
            question: "最卡住的是哪个时刻？",
            actionOptions: []
        )
    }
}

private struct SemanticRestatementDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "那晚又被要求次晨交付，你还是答应了，时间很紧。这里也许藏着一条你还没说出口的界线。",
            question: "那条界线，你最先想守住的是什么？",
            actionOptions: []
        )
    }
}

private struct CardDescriptorGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这画面里有被权威拉扯的张力。",
            question: "画面里那个位置，如果换成你的处境，会是谁站在那儿？",
            actionOptions: []
        )
    }
}

private struct UnsupportedEmotionGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这件事已经让你非常焦虑。",
            question: "你想继续说吗？",
            actionOptions: []
        )
    }
}

private struct UnsupportedAvoidanceGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "刷手机说明你在逃避，也是在躲开论文。",
            question: "你为什么要这样做？",
            actionOptions: []
        )
    }
}

private struct UnsupportedSelfWorryGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "那种感觉也牵动了你对自己的担心。",
            question: "你最想先回应哪一点？",
            actionOptions: []
        )
    }
}

private struct UnsupportedBodyLocationGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "",
            question: "说到这里，身体哪里最明显？",
            actionOptions: []
        )
    }
}

private struct OrnateDialogueGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这份感受值得被看到。",
            question: "那一刻，你心里最沉的是什么？",
            actionOptions: []
        )
    }
}

private struct RepetitiveTechnicalProbeGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这种卡住感确实会加重挫败。",
            question: "有没有某个具体的调整过程或细节，让这种挫败感特别明显？",
            actionOptions: []
        )
    }
}

private struct TwoVisibleQuestionsGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "你今天还好吗？",
            question: "这件事是从什么时候开始的？",
            actionOptions: []
        )
    }
}

private struct CardIntegrationDialogueGenerator: DialogueGenerating {
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
        if nextQuestionGoal.contains("imageStructure"),
           analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .imageStructure }) == true,
           analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .realityStructure }) == true {
            return DialogueTurn(
                reflection: "一个可能的方向是：画面里尚未决定的关系，和现实中暂时难以判断的关系有些相似。",
                question: "",
                actionOptions: []
            )
        }
        switch state {
        case .attributionReflection:
            return DialogueTurn(
                reflection: "把导师和同学的不同建议，和画面里站在两条路之间的人放在一起，这次的为难就更具体了。",
                question: "这样放在一起看，和你的实际感受贴近吗？",
                actionOptions: []
            )
        case .actionSelection:
            return DialogueTurn(
                reflection: "既然这个理解贴近，我们可以从很小的一步开始，不用马上替整件事找到答案。",
                question: "",
                actionOptions: [
                    DialogueActionOption(
                        category: .change,
                        description: "先写下两条建议各自最重要的一点",
                        timing: "今天有十分钟时",
                        rationale: "先把选择看清楚，不要求立刻决定"
                    )
                ]
            )
        default:
            return DialogueTurn(reflection: "我跟着这个具体部分继续。", question: "接下来发生了什么？", actionOptions: [])
        }
    }
}

private struct InventedCardSymbolismGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这张牌里的焦灼和反转，说明你正在被某种力量推着往前。",
            question: "你现在能改变什么？",
            actionOptions: []
        )
    }
}

private struct InventedMeaningChangeGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "这张图让你重新理解了原来的经历，也有了一个此前没有新看见的方向。",
            question: "哪些现实情况需要先被承认？",
            actionOptions: []
        )
    }
}

private struct RepeatingLockedBaselineGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "最近睡眠比平时短，活动量也少。画面和现实有联系，所以你有了新的理解。",
            question: "这段整理符合吗？",
            actionOptions: []
        )
    }
}

private struct GenericCardSymbolismGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "翅膀代表未知，画面暗示你应该相信接下来的反转。",
            question: "这意味着你现在能改变什么？",
            actionOptions: []
        )
    }
}

private struct GlobalLabelNarrativeGenerator: DialogueGenerating {
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
        DialogueTurn(
            reflection: "最后你看见了自己的拖延和没用，也意识到只要更自律就一定可以解决论文问题。",
            question: "这段总结符合吗？",
            actionOptions: []
        )
    }
}

private struct WorkflowContractDialogueGenerator: DialogueGenerating {
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
        let goal = nextQuestionGoal.lowercased()
        switch state {
        case .eventDisclosure:
            return DialogueTurn(reflection: "可以从这件具体的事开始。", question: "当时发生了什么？", actionOptions: [])
        case .emotionDisclosure:
            return DialogueTurn(reflection: "先不用急着解释原因。", question: "你当时最明显的感受是什么？", actionOptions: [])
        case .selfJudgment:
            return DialogueTurn(reflection: "这件事也影响了你怎么看自己。", question: "你那时会怎么评价自己？", actionOptions: [])
        case .contextDisclosure:
            return DialogueTurn(reflection: "我们再把现实情况说清楚一点。", question: "当时有哪些实际限制？", actionOptions: [])
        case .tenderGrounding:
            return DialogueTurn(
                reflection: "临时交付和时间紧是这次的具体处境，它们和对自己能力的整体判断是两部分。",
                question: "这样区分符合你的感受吗？",
                actionOptions: []
            )
        case .trackingReview:
            return DialogueTurn(
                reflection: "最近睡眠比个人近期水平短一些，这只能作为当时的背景，不能说明原因或责任。",
                question: "它和你记得的状态相符吗？",
                actionOptions: []
            )
        case .readinessCheck:
            return DialogueTurn(
                reflection: "目前是临时交付、时间紧和挫败叠在一起；睡眠变化只保留为你认可的背景。",
                question: "这段情况需要修改吗？",
                actionOptions: []
            )
        case .cardInterpretation:
            return DialogueTurn(
                reflection: "先只沿着你看到的画面说。",
                question: "哪个细节让你觉得他还没决定方向？",
                actionOptions: []
            )
        case .attributionReflection:
            if goal.contains("imagestructure"),
               analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .imageStructure }) == true,
               analysis?.resolvedSemanticRelations.contains(where: { $0.kind == .realityStructure }) == true {
                return DialogueTurn(
                    reflection: "一个可能的方向是：画面里尚未决定的关系，和现实中暂时难以判断的关系有些相似。",
                    question: "",
                    actionOptions: []
                )
            }
            if goal.contains("final concise narrative") ||
                goal.contains("revise the final narrative") ||
                goal.contains("final card-derived delta") {
                return DialogueTurn(
                    reflection: "这次你把临时交付、时间限制、睡眠背景和自己的判断分开来看。两条路的画面连到不同建议，也让你找到先写判断标准的可能；这次你选择先不决定行动。",
                    question: "这段最终记录需要改吗？",
                    actionOptions: []
                )
            }
            if goal.contains("integrated reflection") || goal.contains("card-derived delta narrative") {
                return DialogueTurn(
                    reflection: "负责人临时要求次日交分析，时间紧让你挫败。画面里站在两条路中间的人，让你想到面对不同建议时的犹豫；你也看见自己可以先写清判断标准。",
                    question: "这段理解符合你的实际感受吗？",
                    actionOptions: []
                )
            }
            if goal.contains("circumstance") || goal.contains("limitation") || goal.contains("realit") {
                return DialogueTurn(
                    reflection: "我们先回到你已经说清楚的实际处境。",
                    question: "哪些现实困难需要先被承认？",
                    actionOptions: []
                )
            }
            if goal.contains("agency") || goal.contains("boundary") || goal.contains("choosable") {
                return DialogueTurn(
                    reflection: "这些限制被承认以后，再看仍然能由你决定的部分。",
                    question: "其中哪一小部分是你还可以重新选择的？",
                    actionOptions: []
                )
            }
            if goal.contains("small next step") {
                return DialogueTurn(
                    reflection: "这段理解已经由你确认。",
                    question: "你现在想选一个很小的下一步吗？也可以不选。",
                    actionOptions: []
                )
            }
            return DialogueTurn(
                reflection: "先不替这张图下结论。",
                question: "它让你想到实际经历里的哪一部分？",
                actionOptions: []
            )
        default:
            return DialogueTurn(reflection: "我跟着这个具体部分继续。", question: "接下来发生了什么？", actionOptions: [])
        }
    }
}

private struct StaticQuestionRewriter: DialogueQuestionRewriting {
    let turn: DialogueTurn

    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        turn
    }
}

private struct FailingQuestionRewriter: DialogueQuestionRewriting {
    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        throw URLError(.notConnectedToInternet)
    }
}

private func workflowTrackingCue(
    metric: TrackingMetric = .sleepDuration,
    source: TrackingSource = .healthSleep,
    difference: Double = -1_800
) -> TrackingCue {
    let now = Date()
    let observation: String = switch metric {
    case .sleepDuration: "最近睡眠比个人近期水平短一些"
    case .sleepTiming: "最近入睡比个人近期水平晚一些"
    case .sleepWakeTime: "最近醒来时间与个人近期水平不同"
    case .sleepContinuity: "最近设备记录到的睡眠片段更零散"
    case .restingHeartRate: "最近安静状态下的心率与个人近期水平不同"
    case .heartRateVariability: "最近身体恢复方面的设备记录比个人近期水平低一些"
    case .steps: "最近运动量和走动比个人近期水平少一些"
    case .calendarLoad: "最近日历中记录到的安排比个人近期水平少一些"
    case .screenTime: "最近屏幕使用时长与个人近期水平不同"
    case .weather: "最近外部环境记录与个人近期水平不同"
    }
    let insight = TrackingInsight(
        id: UUID(),
        metric: metric,
        observationWindow: DateInterval(start: now.addingTimeInterval(-604_800), end: now),
        validSampleCount: 5,
        expectedSampleCount: 7,
        coverageDescription: "5/7 晚有记录",
        neutralObservation: observation,
        baselineWindow: DateInterval(start: now.addingTimeInterval(-2_419_200), end: now.addingTimeInterval(-604_800)),
        baselineDescription: "与个人近期水平比较",
        absoluteDifference: difference,
        relativeDifference: -0.08,
        strength: .baselineComparison,
        confidence: .moderate,
        limitations: ["两晚缺少记录"],
        possibleConfounders: ["设备同步"],
        suggestedReflectionQuestion: "这和你记得的情况相符吗？",
        provenance: [],
        recentMedian: 23_400,
        baselineMedian: 25_200,
        medianAbsoluteDeviation: 900,
        interquartileRange: 1_800,
        longestConsecutiveRun: 3,
        userRelevance: .notReviewed
    )
    return TrackingCue(source: source, observation: insight.neutralObservation, insight: insight)
}

private func semanticPair(
    image: String,
    reality: String,
    concepts: [SemanticConcept]
) -> [SemanticRelation] {
    [
        SemanticRelation(
            kind: .imageStructure,
            source: image,
            relation: "形成",
            target: "画面中的关系",
            concepts: concepts,
            evidence: [image],
            status: .userStated,
            confidence: 0.9
        ),
        SemanticRelation(
            kind: .realityStructure,
            source: reality,
            relation: "形成",
            target: "现实中的关系",
            concepts: concepts,
            evidence: [reality],
            status: .userConfirmed,
            confidence: 0.9
        ),
    ]
}

private struct FailingDialogueGenerator: DialogueGenerating {
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
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
private func waitForAsyncWork() async {
    try? await Task.sleep(for: .milliseconds(350))
}

@MainActor
private func sendAndWait(_ text: String, to model: ReflectionViewModel) async {
    model.draft = text
    model.send()
    await waitForModelIdle(model)
}

@MainActor
private func waitForStreamingStart(_ model: ReflectionViewModel) async {
    for _ in 0..<100 {
        if model.isStreamingResponse { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func waitForModelIdle(_ model: ReflectionViewModel) async {
    for _ in 0..<60 {
        if !model.isTyping && !model.isStreamingResponse { return }
        try? await Task.sleep(for: .milliseconds(50))
    }
}
