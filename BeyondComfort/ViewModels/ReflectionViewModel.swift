import Foundation
import Combine

private enum ReflectionResponseContext {
    @TaskLocal static var sessionID: UUID?
    @TaskLocal static var userMessageID: UUID?
    @TaskLocal static var generationID: UUID?
}

/// Planning/protocol failures may request a fresh semantic plan. Writer failures must not: the
/// already validated plan remains the single semantic decision for the user turn.
private enum ProtocolTurnAttemptFailure: Error {
    case incompletePracticeTransition(
        error: Error,
        plan: LLMTurnResponsePlan
    )
    case writerFailedTwice(
        error: Error,
        request: LLMTurnControllerRequest,
        originalPlan: LLMTurnResponsePlan,
        validatedPlan: LLMTurnResponsePlan
    )
}

private enum ProtocolCommitFailure: Error {
    case persistenceFailed
}

private enum ProtocolRetryRoute {
    case planner(
        correction: String,
        permissions: ReflectionProtocolPermissions
    )
    case writer(
        request: LLMTurnControllerRequest,
        originalPlan: LLMTurnResponsePlan,
        validatedPlan: LLMTurnResponsePlan
    )
    case commit(
        response: LLMTurnControllerResponse,
        appendVisibleReply: Bool,
        continuation: LLMTurnTrigger?
    )
}

private struct ProtocolCorrectionPayload: Encodable {
    let component: String
    let errorCode: String
    let currentStage: String
    let allowedStages: [String]
    let allowedActions: [String]
    let allowedReplyIntents: [String]
    let missingConditions: [String]
    let forbiddenOperations: [String]
    let allowedEnumValues: [String: [String]]
    let validReferences: [String: String]
    let mustPreserve: [String]
    let instruction: String
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: AccountUser?
    @Published var username = ""
    @Published var password = ""
    @Published var consentAccepted = false
    @Published var isRegistering = true
    @Published var isWorking = false
    @Published var errorMessage = ""

    var isAuthenticated: Bool { user != nil }

    func restoreSession() async {
        guard await RemoteAPIService.shared.isConfigured else { return }
        do { user = try await RemoteAPIService.shared.currentUser() } catch { user = nil }
    }

    func submit() async {
        errorMessage = ""
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.count >= 3 else { errorMessage = "用户名至少 3 个字符"; return }
        guard password.count >= 10 else { errorMessage = "密码至少 10 个字符"; return }
        if isRegistering && !consentAccepted { errorMessage = "请先同意研究数据说明"; return }
        isWorking = true
        defer { isWorking = false }
        do {
            user = isRegistering
                ? try await RemoteAPIService.shared.register(username: cleanUsername, password: password)
                : try await RemoteAPIService.shared.login(username: cleanUsername, password: password)
            password = ""
        } catch { errorMessage = error.localizedDescription }
    }

    func logout() async {
        try? await RemoteAPIService.shared.logout()
        user = nil
        password = ""
    }
}

@MainActor
final class StudyAdministrationViewModel: ObservableObject {
    @Published private(set) var isAdministrator = false
    @Published private(set) var participants: [StudyParticipant] = []
    @Published private(set) var schedules: [StudySchedule] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""

    func refresh() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            async let participantRequest = RemoteAPIService.shared.studyParticipants()
            async let scheduleRequest = RemoteAPIService.shared.studySchedules()
            participants = try await participantRequest
            schedules = try await scheduleRequest
            isAdministrator = true
        } catch {
            participants = []
            schedules = []
            isAdministrator = false
            if let remoteError = error as? RemoteAPIError,
               case .server(let status, _) = remoteError,
               status == 403 {
                return
            }
            errorMessage = "无法读取研究管理数据，请稍后重试。"
        }
    }

    func schedule(for participant: StudyParticipant) -> StudySchedule? {
        schedules.first { $0.userId == participant.id }
    }

    func save(
        participant: StudyParticipant,
        sequence: StudySequence,
        periodOneStartsAt: Date?,
        periodTwoStartsAt: Date?,
        enabled: Bool
    ) async -> Bool {
        errorMessage = ""
        do {
            let schedule = try await RemoteAPIService.shared.updateStudySchedule(
                participantID: participant.id,
                update: StudyScheduleUpdate(
                    sequence: sequence,
                    periodOneStartsAt: periodOneStartsAt,
                    periodTwoStartsAt: periodTwoStartsAt,
                    enabled: enabled
                )
            )
            schedules.removeAll { $0.userId == participant.id }
            schedules.append(schedule)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
final class ReflectionViewModel: ObservableObject {
    @Published var session = ReflectionSession()
    @Published var draft = ""
    @Published var isTyping = false
    @Published private(set) var isStreamingResponse = false
    @Published private(set) var streamRevision = 0
    @Published var isLoadingContextData = false
    @Published private(set) var isPreparingContextData = false
    @Published private(set) var isOpeningTrackingReview = false
    @Published var contextDataStatus = "尚未读取健康与日历记录"
    @Published private(set) var contextDataRefreshedAt: Date?
    @Published var isPaused = false
    @Published var resumeCandidate: ResumableReflection?
    @Published var isResumeChoicePresented = false
    @Published var isCheckingForResume = false
    @Published var saveNotice = ""
    @Published private(set) var llmStatus = "AI 反思服务已连接"
    @Published var exportURL: URL?
    @Published private(set) var cloudStatus = "尚未连接云端记录"
    @Published private(set) var canRetry = false
    @Published private(set) var studyAvailabilityMessage = "正在获取研究安排…"

    private let analyzer: any ContextAnalyzing
    private let dialogueGenerator: any DialogueGenerating
    private let turnController: any ReflectionTurnControlling
    private let simpleGentleReflectionGenerator: any SimpleGentleReflectionGenerating
    private let protocolController = ReflectionProtocolController()
    private let stateMachine = ReflectionStateMachine()
    private let workflowStateMachine = ReflectionWorkflowStateMachine()
    private let disclosureResolver = AdaptiveDisclosureResolver()
    private let cards = CardService()
    private let cardGroundingMatcher = CardGroundingMatcher()
    private let responsePlanValidator = ResponsePlanValidator()
    private let practiceResolver = CompassionatePracticeResolver()
    private let safety = SafetyService()
    private let store: SessionStore
    private let health = HealthKitService()
    private let calendar = CalendarService()
    /// Live scenario tests inject already-cleaned, synthetic tracking cues. Disabling the
    /// asynchronous HealthKit/EventKit refresh keeps those deterministic cues from being replaced;
    /// the conversational path still uses the production Planner, Writer, protocol validation,
    /// stage transitions, and atomic commit implementation.
    private let preparesContextDataAutomatically: Bool
    private var didRequestContextData = false
    private var cloudSyncEnabled = false
    private var remoteSessionID: String?
    private var syncTask: Task<Void, Never>?
    private var contextRefreshTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private var activeResponseGenerationID: UUID?
    private var activeUserTurnGenerations: [UUID: UUID] = [:]
    private var pendingCardReplyToMessageID: UUID?
    private var retryTarget: RetryTarget?
    private let completedRemoteSessionDefaultsKey = "BeyondComfort.completedRemoteReflectionSessionIDs"
    private var studyAccess: StudyAccess?
    private var didConfigureStudyAccess = false

    var canBeginStudy: Bool {
        !didConfigureStudyAccess || studyAccess?.isAvailable == true
    }

    private let minimumStructuredDisclosureAssistantTurns = 3
    private let maximumStructuredDisclosureAssistantTurns = 5
    private let simpleGentleControlCompletionOfferTurn = 4
    private let simpleGentleControlSoftBoundaryTurn = 8

    var canCompleteSimpleGentleControl: Bool {
        session.usesSimpleGentleControl &&
            session.stage != .completed &&
            simpleGentleControlUserTurnCount >= simpleGentleControlCompletionOfferTurn
    }

    var hasReachedSimpleGentleControlSoftBoundary: Bool {
        session.usesSimpleGentleControl &&
            session.stage != .completed &&
            simpleGentleControlUserTurnCount >= simpleGentleControlSoftBoundaryTurn
    }

    /// User-meaning turns require a fresh, evidence-checked Analyzer plan. Swift-controlled turns
    /// include fixed notices, confirmations, experiment gates, tracking presentation, safety,
    /// and state-driven synthesis; a stale model plan can never override those contracts.
    private enum DialogueAuthority {
        case swiftControlled
        case userMeaning(ResponsePlan?)
    }

    private enum RetryTarget {
        case dialogue(
            state: ReflectionState,
            goal: String,
            authority: DialogueAuthority,
            requiresIntegratedNarrative: Bool,
            integratedNarrativeAccuracyCheck: Bool,
            trackingCuesOverride: [TrackingCue]?
        )
        case protocolPlanner(
            correction: String,
            permissions: ReflectionProtocolPermissions,
            recoveryMessageID: UUID?,
            userMessageID: UUID?
        )
        case protocolWriter(
            request: LLMTurnControllerRequest,
            originalPlan: LLMTurnResponsePlan,
            validatedPlan: LLMTurnResponsePlan,
            recoveryMessageID: UUID?,
            userMessageID: UUID?
        )
        case protocolCommit(
            response: LLMTurnControllerResponse,
            appendVisibleReply: Bool,
            continuation: LLMTurnTrigger?,
            recoveryMessageID: UUID?,
            userMessageID: UUID?
        )
    }

    init(
        analyzer: any ContextAnalyzing = RemoteContextAnalyzer(),
        dialogueGenerator: any DialogueGenerating = RemoteDialogueGenerator(),
        turnController: any ReflectionTurnControlling = RemoteReflectionTurnController(),
        simpleGentleReflectionGenerator: any SimpleGentleReflectionGenerating =
            RemoteSimpleGentleReflectionGenerator(),
        sessionStore: SessionStore = SessionStore(),
        preparesContextDataAutomatically: Bool = true
    ) {
        self.analyzer = analyzer
        self.dialogueGenerator = dialogueGenerator
        self.turnController = turnController
        self.simpleGentleReflectionGenerator = simpleGentleReflectionGenerator
        self.store = sessionStore
        self.preparesContextDataAutomatically = preparesContextDataAutomatically
        session.messages = []
        session.studyEvents = [.init(stage: .welcome, action: "session_started")]
    }

    /// The server decides availability, sequence, period, and condition. No completion count,
    /// local clock, model response, or participant action can advance the crossover.
    func configureStudy() async {
        didConfigureStudyAccess = true
        do {
            studyAccess = try await RemoteAPIService.shared.currentStudyAccess()
            studyAvailabilityMessage = studyAccessMessage(for: studyAccess)
        } catch {
            studyAccess = nil
            studyAvailabilityMessage = "暂时无法确认本周安排，请稍后重试。"
        }
        guard session.stage == .welcome else { return }
        session = makeNewSession()
        invalidateTrackingRefreshForFreshSession()
        session.messages = []
        session.studyEvents = [.init(stage: .welcome, action: "session_started")]
    }

    func refreshStudyAccessAndBegin() async {
        await configureStudy()
        begin()
    }

    func begin() {
        guard canBeginStudy else {
            saveNotice = studyAvailabilityMessage
            return
        }
        guard session.stage == .welcome else { return }
        if session.usesSimpleGentleControl {
            session.protocolStage = .directReflection
            session.stage = .eventDisclosure
            session.workflowPhase = .structuredDisclosure
            session.dialogueProgress.currentState = .eventDisclosure
            session.structuredDisclosureAssistantTurns = 1
            session.studyEvents.append(
                .init(stage: .eventDisclosure, action: "simple_gentle_control_started")
            )
            addAssistant("你好，我在这里。最近有什么事想聊聊吗？可以从刚发生的一件事说起。")
            return
        }
        if session.usesLLMTurnController {
            session.protocolStage = .contextualDisclosure
            session.stage = .eventDisclosure
            session.workflowPhase = .structuredDisclosure
            session.dialogueProgress.currentState = .eventDisclosure
            session.structuredDisclosureAssistantTurns = 1
            session.studyEvents.append(
                .init(stage: .eventDisclosure, action: "coarse_protocol_session_started")
            )
            let openingPrompt = TurnNextPrompt.openQuestion(
                purpose: "event_sequence_clarified",
                focus: "最近想一起反思的一件具体经历"
            )
            session.semanticMemory.apply(
                .init(),
                committedNextPrompt: openingPrompt
            )
            session.studyEvents.append(
                .init(stage: .eventDisclosure, action: "local_protocol_opening_presented")
            )
            session.studyEvents.append(
                .init(stage: .eventDisclosure, action: "next_prompt_committed_openQuestion")
            )
            addAssistant("你好，我在这里。最近有什么事想聊聊吗？可以从刚发生的一件事说起。")
            if preparesContextDataAutomatically {
                Task { @MainActor [weak self] in
                    await self?.prepareRequiredContextData()
                }
            }
            return
        }
        setWorkflowPhase(.structuredDisclosure, action: "structured_disclosure_started")
        transition(to: .eventDisclosure, action: "reflection_started")
        session.structuredDisclosureAssistantTurns = 1
        addAssistant("你好，我在这里。最近有什么事想聊聊吗？可以从刚发生的一件事说起。")
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping, !isStreamingResponse else { return }
        if canRetry,
           retryTarget != nil,
           ["重试", "再试一次", "重新尝试"].contains(text) {
            // Treat a typed retry command exactly like the visible retry button. Do not append it
            // as a new disclosure turn and do not discard the stored Planner/Writer/commit target.
            draft = ""
            retryLastRequest()
            return
        }
        draft = ""
        clearRetry()
        let userMessageID = addUser(text)
        if !session.usesSimpleGentleControl {
            updateTrackingAnchorIfUserSpecifiedDate(in: text)
        }
        if safety.requiresInterrupt(text) { interruptForSafety(replyingTo: userMessageID); return }
        // A safety flag may already have been produced by the analyzer before a user chooses a
        // card or answers a gate. Do not let a feature request route around that interrupt.
        if session.latestAnalysis?.safetyOverride == true {
            interruptForSafety(replyingTo: userMessageID)
            return
        }
        if userWantsToEnd(text) {
            endEarly(replyingTo: userMessageID)
            return
        }

        if session.usesSimpleGentleControl {
            launchPersistedModelResponse(replyingTo: userMessageID) { model in
                await model.processSimpleGentleControlTurn(replyingTo: userMessageID)
            }
            return
        }

        if session.usesLLMTurnController {
            if acceptExplicitProtocolCardConsentIfNeeded(
                text,
                replyingTo: userMessageID
            ) {
                return
            }
            if acceptExplicitProtocolCardMappingIfNeeded(
                text,
                replyingTo: userMessageID
            ) {
                return
            }
            launchPersistedModelResponse(replyingTo: userMessageID) { model in
                await model.processProtocolTurn(trigger: .userMessage)
            }
            return
        }

        if isClarificationRequest(text), isPreCardReflectionState(session.stage) {
            isTyping = true
            let state = session.stage
            launchResponse(replyingTo: userMessageID) { model in
                await model.processClarificationRequest(state: state)
            }
            return
        }

        if userIsStillAnswering(text) {
            session.studyEvents.append(
                .init(stage: session.stage, action: "user_kept_current_turn_open")
            )
            addAssistant("好，你继续说，我先不往下走。", replyingTo: userMessageID)
            return
        }

        if session.condition.usesCard, shouldStartCardImmediately(from: text) {
            startCardImmediately(replyingTo: userMessageID)
            return
        }

        if isDisclosureState(session.stage), isSimpleGreeting(text) {
            session.studyEvents.append(.init(stage: session.stage, action: "simple_greeting_answered_without_analysis"))
            addAssistant("Hello，我在。你想聊什么都可以。", replyingTo: userMessageID)
            return
        }

        if isConversationRupture(text), isPreCardReflectionState(session.stage) {
            isTyping = true
            let state = session.stage
            launchResponse(replyingTo: userMessageID) { model in await model.processConversationRepair(text, state: state) }
            return
        }

        if isDisclosureState(session.stage), isAskingForScaffolding(text) {
            session.studyEvents.append(.init(stage: session.stage, action: "light_scaffolding_requested"))
            addAssistant("不用找最准确的词。可以说“心里很乱”“有点难受”，也可以直接描述当时发生了什么。", replyingTo: userMessageID)
            return
        }

        switch session.stage {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure:
            isTyping = true
            let state = session.stage
            launchResponse(replyingTo: userMessageID) { model in await model.processDisclosure(text, state: state) }
        case .trackingReview:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processTrackingResponse(text) }
        case .tenderGrounding, .tenderExploration:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processTenderResponse(text) }
        case .readinessCheck:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processReadinessResponse(text) }
        case .cardInterpretation:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processCardInterpretation(text) }
        case .attributionReflection:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processAttributionResponse(text) }
        case .actionSelection:
            isTyping = true
            launchResponse(replyingTo: userMessageID) { model in await model.processActionRevision(text) }
        default:
            break
        }
    }

    func skipCurrentDisclosure() {
        let state = session.stage
        guard [.eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure].contains(state) else { return }
        let skippedText = "这一项我暂时不确定"
        addUser(skippedText)
        storeLiteralDisclosure(skippedText, state: state)
        session.studyEvents.append(.init(stage: state, action: "disclosure_skipped"))
        if state == .contextDisclosure ||
            session.structuredDisclosureAssistantTurns >= maximumStructuredDisclosureAssistantTurns {
            closeRemainingDisclosureAsUncertain(reason: "disclosure_completed_after_skip")
            isTyping = true
            launchResponse { model in
                await model.beginTenderGrounding(
                    action: "structured_disclosure_completed_after_skip",
                    managesTyping: true
                )
            }
            return
        }
        guard let next = nextDepthDisclosureState() else { return }
        if next == .trackingPermission {
            closeRemainingDisclosureAsUncertain(reason: "disclosure_completed_after_skip")
            isTyping = true
            launchResponse { model in
                await model.beginTenderGrounding(
                    action: "structured_disclosure_completed_after_skip",
                    managesTyping: true
                )
            }
            return
        }
        transition(to: next, action: "disclosure_advanced_after_skip")
        if next == .selfJudgment {
            session.hasAskedPersonalMeaningQuestion = true
        }
        session.structuredDisclosureAssistantTurns += 1
        isTyping = true
        launchResponse { model in
            await model.generateDialogue(state: next, goal: model.questionGoal(for: next))
        }
    }

    /// New sessions reach the review automatically once the conversation has enough context.
    /// The legacy permission state and method remain decodable for saved sessions, but the UI no
    /// longer asks for a second all-or-nothing tracking choice after system authorization.
    private func enterAutomaticTrackingReview(conversationRepair: Bool = false) {
        guard session.stage == .trackingPermission, !isOpeningTrackingReview else { return }
        setWorkflowPhase(.trackingReview, action: "tracking_review_started")
        transition(to: .trackingReview, action: "tracking_review_opened_automatically")
        launchResponse { model in await model.loadTrackingReviewData(conversationRepair: conversationRepair) }
    }

    private func loadTrackingReviewData(conversationRepair: Bool = false) async {
        guard session.stage == .trackingReview, !isOpeningTrackingReview else { return }
        isOpeningTrackingReview = true
        isTyping = true
        defer {
            if responseContextIsCurrent() {
                isOpeningTrackingReview = false
                isTyping = false
            }
        }

        // Reuse a deterministic, domain-diverse bundle of already-cleaned insights. Selection is
        // independent of the conversation, route, emotion, and model output.
        if session.contextualLoadInference == nil, !session.trackingCues.isEmpty {
            refreshContextualLoadInference()
        }
        var candidates = preferredTrackingCandidates()
        if candidates.isEmpty, session.trackingCues.isEmpty {
            await prepareRequiredContextData()
            guard responseContextIsCurrent(expectedStage: .trackingReview) else { return }
            if contextDataRefreshedAt == nil {
                await refreshContextData()
            }
            candidates = preferredTrackingCandidates()
        }

        guard responseContextIsCurrent(expectedStage: .trackingReview) else { return }
        session.studyEvents.append(.init(stage: .trackingReview, action: "tracking_review_data_ready"))
        session.trackingReviewCompleted = true
        session.trackingReviewUnavailable = candidates.isEmpty
        session.trackingContextLinkCompleted = true
        session.trackingContextLinkResponse = nil
        session.pendingTrackingCueIDs = []
        session.pendingTrackingCueID = nil
        session.studyEvents.append(
            .init(
                stage: .trackingReview,
                action: candidates.isEmpty
                    ? "tracking_context_unavailable_without_prompt"
                    : "tracking_context_folded_into_context_summary"
            )
        )
        await beginContextConfirmation(
            action: conversationRepair
                ? "context_confirmation_after_tracking_and_repair"
                : "context_confirmation_without_tracking_relevance_question",
            managesTyping: false
        )
    }

    func deleteTrackingCues() {
        session.pendingTrackingCueID = nil
        session.pendingTrackingCueIDs = []
        session.trackingCues.removeAll()
        session.contextualLoadInference = nil
        session.context.confirmedTrackingCues.removeAll()
        session.context.confirmedTrackingInsights = []
        session.context.rejectedTrackingCueIDs.removeAll()
        session.studyEvents.append(.init(stage: session.stage, action: "tracking_cues_deleted"))
        scheduleCloudSync(action: "tracking_cues_deleted")
    }

    func drawCard(replyingTo userMessageID: UUID? = nil) {
        guard session.stage == .cardIntroduction,
              [.cardSelection, .cardDisplay].contains(session.workflowPhase) else { return }
        pendingCardReplyToMessageID = userMessageID ?? ReflectionResponseContext.userMessageID
        if session.cardWasSetAside {
            // The original user message remains in the transcript for the research record. Clear
            // only the derived active-card interpretation so a requested replacement card starts
            // from the user's new description instead of inheriting the set-aside card's words.
            session.context.cardInterpretation = nil
        }
        let card = cards.draw()
        session.card = card
        session.cardDisplayState = .selected
        session.cardDisplayReloadNonce = 0
        setWorkflowPhase(.cardDisplay, action: "card_display_waiting_for_ui")
        session.context.selectedCardID = String(card.id)
        session.dialogueProgress.cardPreference = .completed
        session.cardWasSetAside = false
        session.hasAskedCardProjectionFollowUp = false
        session.hasAskedCardNarrativeDeepening = false
        session.hasUserAuthoredCardConnection = false
        session.hasCompletedAttributionExchange = false
        session.hasPresentedIntegratedNarrative = false
        session.cardImageDevelopmentTurnCount = 0
        session.cardConnectionAttemptCount = 0
        session.cardConnectionScaffoldUsed = false
        session.cardConnectionScaffoldPending = false
        session.cardConnectionUnavailable = false
        session.cardLifeConnection = nil
        session.cardCandidateMapping = nil
        session.cardConfirmedMapping = nil
        session.cardMappingConfirmed = false
        session.cardGuidanceShared = false
        session.cardGroundingMatch = nil
        session.cardMeaningShiftResponse = nil
        session.cardMeaningShiftCompleted = false
        session.cardDerivedDeltaNarrative = nil
        session.candidCircumstancesCompleted = false
        session.candidCircumstancesResponse = nil
        session.candidAgencyCompleted = false
        session.candidAgencyResponse = nil
        session.integratedNarrativeConfirmed = false
        session.pendingUserAuthoredAction = nil
        session.userAuthoredActionConfirmed = false
        session.hasPresentedFinalNarrative = false
        session.finalNarrativeConfirmed = false
        session.actionSuggestions.removeAll()
        session.cardDrawRecord = CardDrawRecord(
            sessionID: session.id,
            cardID: String(card.id),
            drawnAt: .now,
            routeBeforeDraw: session.currentRoute
        )
        session.studyEvents.append(.init(stage: .cardIntroduction, action: "card_selected_uniform_random"))
        scheduleCloudSync(action: "card_selected_uniform_random")
    }

    func cardDidDisplay(cardID: Int, replyingTo userMessageID: UUID? = nil) {
        if session.usesLLMTurnController {
            guard session.protocolStage == .cardConsent,
                  session.stage == .cardIntroduction,
                  session.card?.id == cardID,
                  session.cardDisplayState == .selected else { return }
            let replyToMessageID = userMessageID ?? pendingCardReplyToMessageID
            session.cardDisplayState = .displayed
            session.protocolStage = .cardReflection
            session.stage = .cardInterpretation
            session.workflowPhase = .cardObservation
            session.dialogueProgress.currentState = .cardInterpretation
            pendingCardReplyToMessageID = nil
            session.studyEvents.append(
                .init(stage: .cardInterpretation, action: "random_card_image_displayed")
            )
            session.semanticMemory.nextPrompt = .openQuestion(
                purpose: "card_image_observation",
                focus: "the person's own account of what is happening in the displayed image"
            )
            addAssistant(
                "这张卡是随机抽取的，也没有固定答案。先只看画面，你觉得这里正在发生什么？",
                replyingTo: replyToMessageID
            )
            session.studyEvents.append(
                .init(
                    stage: .cardInterpretation,
                    action: "card_observation_invitation_presented_locally"
                )
            )
            scheduleCloudSync(action: "random_card_image_displayed")
            return
        }
        guard session.stage == .cardIntroduction,
              session.card?.id == cardID,
              session.cardDisplayState == .selected else { return }
        session.cardDisplayState = .displayed
        setWorkflowPhase(.cardObservation, action: "card_observation_prompted")
        transition(to: .cardInterpretation, action: "card_drawn_uniform_random")
        let replyToMessageID = userMessageID ?? pendingCardReplyToMessageID
        pendingCardReplyToMessageID = nil
        addAssistant(
            "这张卡是随机抽取的，不是根据你刚才的回答或记录选择的，也没有固定答案。\n\n看到这张牌，你觉得画面里正在发生什么？",
            replyingTo: replyToMessageID
        )
    }

    func cardDisplayDidFail(cardID: Int) {
        guard session.stage == .cardIntroduction,
              session.card?.id == cardID,
              session.cardDisplayState == .selected else { return }
        session.cardDisplayState = .loadFailed
        session.studyEvents.append(.init(stage: .cardIntroduction, action: "card_image_load_failed"))
        // Loading failure is UI state, not a second conversational turn. Keep the original user
        // turn pending so a successful reload receives exactly one assistant reply: the first
        // image-observation question after the same selected card is actually visible.
        scheduleCloudSync(action: "card_image_load_failed")
    }

    func retryCardDisplay() {
        guard session.stage == .cardIntroduction, session.cardDisplayState == .loadFailed else { return }
        guard session.card != nil else {
            session.cardDisplayState = .none
            setWorkflowPhase(.cardSelection, action: "missing_selected_card_replaced_after_load_failure")
            drawCard()
            return
        }
        // A load failure must not silently change the random stimulus. Refresh the view identity
        // while preserving the originally selected card ID.
        session.cardDisplayState = .selected
        session.cardDisplayReloadNonce += 1
        session.studyEvents.append(.init(stage: .cardIntroduction, action: "same_card_display_retried"))
        scheduleCloudSync(action: "same_card_display_retried")
    }

    func chooseAction(_ suggestion: ActionSuggestion) {
        guard session.stage == .actionSelection,
              session.hasUserAuthoredCardConnection,
              session.hasCompletedAttributionExchange,
              session.hasPresentedIntegratedNarrative else { return }
        session.context.selectedAction = CompassionateAction(
            category: suggestion.category,
            description: suggestion.description,
            timing: suggestion.timing,
            acceptedByUser: true
        )
        session.userAuthoredActionConfirmed = true
        setWorkflowPhase(.narrativeConfirmation, action: "legacy_action_selection_entered_narrative_review")
        transition(to: .summary, action: "action_explicitly_accepted")
        launchResponse { model in
            model.refreshCardDerivedDeltaNarrative()
            await model.generateDialogue(
                state: .summary,
                goal: "produce the final non-blaming summary",
                requiresIntegratedNarrative: true,
                integratedNarrativeAccuracyCheck: true,
                trackingCuesOverride: model.session.condition.usesCard &&
                    model.session.cardMappingConfirmed ? [] : nil
            )
        }
    }

    func chooseNotReady() {
        guard session.stage == .actionSelection,
              session.hasUserAuthoredCardConnection,
              session.hasCompletedAttributionExchange,
              session.hasPresentedIntegratedNarrative else { return }
        session.context.selectedAction = nil
        setWorkflowPhase(.narrativeConfirmation, action: "legacy_action_decline_entered_narrative_review")
        transition(to: .summary, action: "action_declined")
        launchResponse { model in
            model.refreshCardDerivedDeltaNarrative()
            await model.generateDialogue(
                state: .summary,
                goal: "summarize without claiming an accepted action",
                requiresIntegratedNarrative: true,
                integratedNarrativeAccuracyCheck: true,
                trackingCuesOverride: model.session.condition.usesCard &&
                    model.session.cardMappingConfirmed ? [] : nil
            )
        }
    }

    func finishSummary() {
        guard session.stage == .summary else { return }
        session.finalNarrativeConfirmed = true
        setWorkflowPhase(.complete, action: "final_narrative_review_completed")
        transition(to: .completed, action: "session_completed")
        addAssistant("这次反思到这里结束。你可以保存或删除记录。")
    }

    /// Completed reflections are records, not paused sessions. Persist the completed snapshot
    /// before returning the chat tab to its welcome screen so a relaunch never offers it as an
    /// unfinished reflection.
    func returnHomeAfterCompletion() async {
        guard session.stage == .completed else { return }
        cancelActiveResponse(removePartialReply: true)
        syncTask?.cancel()
        let completedSnapshot = session
        do { try await store.save(completedSnapshot) } catch { saveNotice = "完成记录暂未能保存到本机" }

        var completedRemoteID = remoteSessionID
        if cloudSyncEnabled {
            do {
                if completedRemoteID == nil {
                    completedRemoteID = try await RemoteAPIService.shared.createReflectionSession(completedSnapshot)
                }
                if let completedRemoteID {
                    try await RemoteAPIService.shared.syncReflectionSession(
                        id: completedRemoteID,
                        reflection: completedSnapshot,
                        action: "session_completed_returned_home"
                    )
                }
            } catch {
                cloudStatus = "完成记录已保存在本机；云端稍后会重试"
            }
        }
        if let completedRemoteID { rememberCompletedRemoteSession(completedRemoteID) }
        resumeCandidate = nil
        isResumeChoicePresented = false
        resetToNewSession(syncImmediately: false)
        saveNotice = "本次反思已结束并保存"
    }

    func retryLastRequest() {
        guard !isTyping, let retryTarget else { return }
        clearRetry()
        switch retryTarget {
        case .dialogue(
            let state,
            let goal,
            let authority,
            let requiresIntegratedNarrative,
            let integratedNarrativeAccuracyCheck,
            let trackingCuesOverride
        ):
            launchResponse { model in
                await model.generateDialogue(
                    state: state,
                    goal: goal,
                    authority: authority,
                    requiresIntegratedNarrative: requiresIntegratedNarrative,
                    integratedNarrativeAccuracyCheck: integratedNarrativeAccuracyCheck,
                    trackingCuesOverride: trackingCuesOverride
                )
            }
        case .protocolPlanner(
            let correction,
            let permissions,
            let recoveryMessageID,
            let userMessageID
        ):
            removeProtocolRecoveryMessage(recoveryMessageID)
            launchResponse(replyingTo: userMessageID) { model in
                await model.processProtocolTurn(
                    trigger: .protocolCorrection,
                    initialCorrection: correction,
                    initialPermissions: permissions
                )
            }
        case .protocolWriter(
            let request,
            let originalPlan,
            let validatedPlan,
            let recoveryMessageID,
            let userMessageID
        ):
            removeProtocolRecoveryMessage(recoveryMessageID)
            launchResponse(replyingTo: userMessageID) { model in
                await model.resumeValidatedProtocolWriter(
                    request: request,
                    originalPlan: originalPlan,
                    validatedPlan: validatedPlan
                )
            }
        case .protocolCommit(
            let response,
            let appendVisibleReply,
            let continuation,
            let recoveryMessageID,
            let userMessageID
        ):
            removeProtocolRecoveryMessage(recoveryMessageID)
            launchResponse(replyingTo: userMessageID) { model in
                await model.resumeValidatedProtocolCommit(
                    response,
                    appendVisibleReply: appendVisibleReply,
                    continuation: continuation
                )
            }
        }
    }

    func prepareRequiredContextData() async {
        guard !session.usesSimpleGentleControl else {
            contextDataStatus = "本次对照组对话不使用个人追踪数据"
            return
        }
        if didRequestContextData {
            while isPreparingContextData {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            if TrackingRefreshPolicy.shouldRefresh(
                sessionCueCount: session.trackingCues.count,
                refreshedAt: contextDataRefreshedAt
            ) {
                await refreshContextData()
            }
            return
        }
        didRequestContextData = true
        isPreparingContextData = true
        defer { isPreparingContextData = false }
        contextDataStatus = "正在请求健康读取权限…"
        await health.requestAuthorization()
        guard !Task.isCancelled else { return }
        contextDataStatus = "正在请求日历读取权限…"
        await calendar.requestAuthorization()
        guard !Task.isCancelled else { return }
        await refreshContextData()
    }

    /// The tracking window is anchored to a user-supplied event day when one is available. This
    /// is deliberately local and deterministic; no model is asked to infer when an event occurred.
    private func updateTrackingAnchorIfUserSpecifiedDate(in text: String) {
        guard let date = explicitEventDate(in: text) else { return }
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        guard !calendar.isDate(session.context.eventDate, inSameDayAs: normalized)
                || !session.eventDateIsUserSpecified else { return }

        session.context.eventDate = normalized
        session.eventDateIsUserSpecified = true
        // Existing computed cues used the old reference date. They must be recomputed before a
        // tracking review rather than being repurposed as evidence about this event.
        contextDataRefreshedAt = nil
        session.trackingCues.removeAll()
        session.contextualLoadInference = nil
        session.context.confirmedTrackingCues.removeAll()
        session.context.confirmedTrackingInsights = []
        session.context.rejectedTrackingCueIDs.removeAll()
        session.pendingTrackingCueID = nil
        session.pendingTrackingCueIDs = []
        session.studyEvents.append(.init(stage: session.stage, action: "tracking_anchor_updated_from_user_date"))
    }

    private func explicitEventDate(in text: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        if text.contains("前天") { return calendar.date(byAdding: .day, value: -2, to: startOfToday) }
        if text.contains("昨天") { return calendar.date(byAdding: .day, value: -1, to: startOfToday) }
        if text.contains("今天") || text.contains("当天") { return startOfToday }

        // Relative weekdays are a person-supplied event anchor too. Resolve them locally so a
        // model never has to guess which records belong before the event.
        let weekdayNames: [(String, Int)] = [
            ("周日", 1), ("周一", 2), ("周二", 3), ("周三", 4),
            ("周四", 5), ("周五", 6), ("周六", 7),
            ("星期日", 1), ("星期一", 2), ("星期二", 3), ("星期三", 4),
            ("星期四", 5), ("星期五", 6), ("星期六", 7),
        ]
        if let (_, weekday) = weekdayNames.first(where: { text.contains($0.0) }) {
            let currentWeekday = calendar.component(.weekday, from: startOfToday)
            if text.contains("上周") {
                let daysSinceTarget = (currentWeekday - weekday + 7) % 7
                return calendar.date(byAdding: .day, value: -(daysSinceTarget + 7), to: startOfToday)
            }
            if text.contains("本周") || text.contains("这周") {
                let daysSinceWeekStart = currentWeekday - 1
                let weekStart = calendar.date(byAdding: .day, value: -daysSinceWeekStart, to: startOfToday)
                return weekStart.flatMap { calendar.date(byAdding: .day, value: weekday - 1, to: $0) }
            }
        }

        let pattern = #"(?:(\d{4})年)?\s*(\d{1,2})月\s*(\d{1,2})日"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange]) else { return nil }

        let year: Int
        if let yearRange = Range(match.range(at: 1), in: text), let parsed = Int(text[yearRange]) {
            year = parsed
        } else {
            year = calendar.component(.year, from: now)
        }
        guard var date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        // A month/day without a year normally refers to the most recent occurrence, not a future
        // event that has not yet happened.
        if match.range(at: 1).location == NSNotFound, date > startOfToday {
            date = calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
        return date
    }

    func refreshContextData() async {
        guard !session.usesSimpleGentleControl else {
            contextDataStatus = "本次对照组对话不使用个人追踪数据"
            return
        }
        let requestedSessionID = session.id
        if isLoadingContextData {
            while isLoadingContextData {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, session.id == requestedSessionID else { return }
            // A concurrent read for the same session is sufficient. If the completed read
            // belonged to a session that was just replaced, the fresh session still has no
            // timestamp and needs its own read.
            if contextDataRefreshedAt == nil {
                await refreshContextData()
            }
            return
        }
        isLoadingContextData = true
        defer { isLoadingContextData = false }
        contextDataStatus = "正在分析最近 7 天，并检查最多 28 天个人基线…"
        let referenceDate = session.context.eventDate
        async let healthCues = health.fetch(referenceDate: referenceDate)
        async let calendarCues = calendar.fetch(referenceDate: referenceDate)
        let fetchedCues = await healthCues + calendarCues
        guard !Task.isCancelled, session.id == requestedSessionID else { return }
        let previous = session.trackingCues.reduce(into: [String: TrackingCueRelevance]()) { values, cue in
            values[trackingIdentity(for: cue)] = cue.relevance
        }
        session.trackingCues = fetchedCues
        for index in session.trackingCues.indices {
            let identity = trackingIdentity(for: session.trackingCues[index])
            session.trackingCues[index].relevance = previous[identity] ?? .notReviewed
        }
        refreshContextualLoadInference()
        contextDataRefreshedAt = .now
        syncTrackingContext()
        let calendarStatus = await calendar.accessMessage()
        guard !Task.isCancelled, session.id == requestedSessionID else { return }
        let hasHealthCue = session.trackingCues.contains { $0.source != .calendarLoad }
        let healthStatus = hasHealthCue
            ? "已读取健康记录。"
            : "HealthKit 未返回最近 7 天记录；可能没有数据、尚未同步或未授予读取权限。"
        contextDataStatus = session.trackingCues.isEmpty
            ? "\(healthStatus)\(calendarStatus)你仍可不使用这些记录继续反思。"
            : "已读取 \(session.trackingCues.count) 条中性记录。\(healthStatus)\(calendarStatus)只有在对话中得到你确认的背景，才会进入后续反思。"
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        cloudSyncEnabled = enabled
        if enabled {
            cloudStatus = "正在检查未完成的反思…"
            Task { await discoverResumableSession() }
        } else {
            syncTask?.cancel()
            contextRefreshTask?.cancel()
            remoteSessionID = nil
            resumeCandidate = nil
            isResumeChoicePresented = false
            cloudStatus = "尚未连接云端记录"
        }
    }

    func pause() { isPaused.toggle() }
    func end() {
        resumeCandidate = nil
        isResumeChoicePresented = false
        guard session.stage != .welcome, session.stage != .completed else { return }
        let isEndingFromCurrentResponse = ReflectionResponseContext.generationID == activeResponseGenerationID
        if !isEndingFromCurrentResponse {
            cancelActiveResponse(removePartialReply: true)
        }
        if session.usesSimpleGentleControl {
            completeSimpleGentleControl(
                action: "simple_gentle_control_ended_from_menu",
                acknowledgement: "好，这次就先到这里。已经留下的内容会按现在的样子保留。"
            )
            return
        }
        if session.usesLLMTurnController {
            setProtocolStage(.complete, action: "coarse_protocol_session_ended_by_user")
            addAssistant("好，这次就先到这里。已经留下的内容会按现在的样子保留。")
            return
        }
        if session.stage == .safetySupport {
            completeWorkflowEarly(action: "safety_workflow_ended_early")
            transition(to: .completed, action: "safety_session_ended")
            return
        }
        if session.stage != .summary {
            transition(to: .summary, action: "session_ended_by_user")
            addAssistant(deterministicSummary())
        }
        completeWorkflowEarly(action: "reflection_workflow_ended_early")
        if session.stage == .summary {
            transition(to: .completed, action: "session_completed_early_by_user")
        }
    }

    private func endEarly(replyingTo userMessageID: UUID) {
        cancelActiveResponse(removePartialReply: true)
        if session.usesSimpleGentleControl {
            completeSimpleGentleControl(
                action: "simple_gentle_control_ended_by_user_message",
                replyingTo: userMessageID,
                acknowledgement: "好，这次就先到这里。已经留下的内容会按现在的样子保留。"
            )
            return
        }
        if session.usesLLMTurnController {
            setProtocolStage(.complete, action: "coarse_protocol_session_ended_by_user")
            addAssistant(
                "好，这次就先到这里。已经留下的内容会按现在的样子保留。",
                replyingTo: userMessageID
            )
            return
        }
        if session.stage == .safetySupport {
            completeWorkflowEarly(action: "safety_session_ended_by_user")
            transition(to: .completed, action: "safety_session_ended")
        } else {
            if session.stage != .summary {
                transition(to: .summary, action: "session_ended_early_by_user")
            }
            completeWorkflowEarly(action: "reflection_workflow_ended_early")
            if session.stage == .summary {
                transition(to: .completed, action: "session_completed_early_by_user")
            }
        }
        addAssistant("好，这次就先到这里。你可以保存或删除已经留下的记录。", replyingTo: userMessageID)
    }

    func finishSimpleGentleControl() {
        guard canCompleteSimpleGentleControl, !isTyping, !isStreamingResponse else { return }
        cancelActiveResponse(removePartialReply: true)
        completeSimpleGentleControl(
            action: "simple_gentle_control_completion_offer_accepted",
            acknowledgement: "好，这次就先到这里。已经留下的内容会按现在的样子保留。"
        )
    }
    func restart() {
        resumeCandidate = nil
        isResumeChoicePresented = false
        resetToNewSession(syncImmediately: true)
    }

    func pauseAndReturnHome() async {
        guard session.stage != .welcome else { return }
        if session.stage == .completed {
            await returnHomeAfterCompletion()
            return
        }
        cancelActiveResponse(removePartialReply: true)
        syncTask?.cancel()
        session.studyEvents.append(.init(stage: session.stage, action: "session_paused"))
        let snapshot = session
        try? await store.save(snapshot)
        var savedRemoteID = remoteSessionID
        if cloudSyncEnabled {
            do {
                if savedRemoteID == nil { savedRemoteID = try await RemoteAPIService.shared.createReflectionSession(snapshot) }
                if let savedRemoteID {
                    try await RemoteAPIService.shared.syncReflectionSession(id: savedRemoteID, reflection: snapshot, action: "session_paused")
                }
            } catch { cloudStatus = "暂停记录保存在本机；云端稍后可重试" }
        }
        remoteSessionID = savedRemoteID
        resumeCandidate = ResumableReflection(id: savedRemoteID ?? snapshot.id.uuidString, remoteID: savedRemoteID, session: snapshot, updatedAt: .now)
        resetToNewSession(syncImmediately: false)
        isResumeChoicePresented = true
        saveNotice = "已暂停并保存"
    }

    func resume(_ candidate: ResumableReflection) {
        cancelActiveResponse(removePartialReply: true)
        pendingCardReplyToMessageID = nil
        syncTask?.cancel()
        session = candidate.session
        if !session.usesLLMTurnController {
            normalizeLegacyWorkflowForResume()
        }
        remoteSessionID = candidate.remoteID
        resumeCandidate = nil
        isResumeChoicePresented = false
        isPaused = false
        session.studyEvents.append(.init(stage: session.stage, action: "session_resumed"))
        scheduleCloudSync(action: "session_resumed", delay: .zero)
        if session.usesSimpleGentleControl {
            if let last = session.messages.last, last.role == .user,
               !session.messages.contains(where: {
                   $0.role == .assistant && $0.replyToMessageID == last.id
               }) {
                launchResponse(replyingTo: last.id) { model in
                    await model.processSimpleGentleControlTurn(replyingTo: last.id)
                }
            }
            return
        }
        if session.usesLLMTurnController {
            if session.cardDisplayState == .selected || session.cardDisplayState == .loadFailed {
                return
            }
            if session.pendingCardGuidanceTurn,
               session.cardGuidanceShared,
               let lastUser = session.messages.last(where: { $0.role == .user }),
               !session.messages.contains(where: {
                   $0.role == .assistant && $0.replyToMessageID == lastUser.id
               }) {
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "pending_card_guidance_turn_resumed"
                    )
                )
                launchResponse(replyingTo: lastUser.id) { model in
                    await model.processProtocolTurn(trigger: .cardGuidanceAvailable)
                }
                return
            }
            if let last = session.messages.last, last.role == .user,
               !session.messages.contains(where: {
                   $0.role == .assistant && $0.replyToMessageID == last.id
               }) {
                launchResponse(replyingTo: last.id) { model in
                    await model.processProtocolTurn(trigger: .userMessage)
                }
            }
            return
        }
        if session.stage == .trackingPermission {
            enterAutomaticTrackingReview()
        } else if session.stage == .trackingReview {
            if session.workflowPhase == .trackingContextLink,
               session.trackingReviewCompleted,
               !session.trackingContextLinkCompleted {
                addAssistant(trackingSituationLinkQuestion())
                return
            }
            let hasPendingTrackingBundle = !session.pendingTrackingCueIDs.isEmpty ||
                session.pendingTrackingCueID != nil
            let hasCompletePrompt = hasPendingTrackingBundle &&
                session.messages.last(where: { $0.role == .assistant })?.content
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            if !hasCompletePrompt {
                session.pendingTrackingCueID = nil
                session.pendingTrackingCueIDs = []
                launchResponse { model in await model.loadTrackingReviewData() }
            }
        } else if session.stage == .cardIntroduction {
            if session.card == nil {
                if session.workflowPhase == .cardDisplay {
                    setWorkflowPhase(.cardSelection, action: "resumed_card_selection_without_card")
                }
                drawCard()
            } else if session.cardDisplayState == .displayed {
                setWorkflowPhase(.cardObservation, action: "resumed_card_observation")
                transition(to: .cardInterpretation, action: "resumed_existing_card_interpretation")
                if session.messages.last(where: { $0.role == .assistant })?.content
                    .contains("画面里正在发生什么") != true {
                    addAssistant("这张牌没有固定答案，你可以按照自己的感觉来描述。\n\n看到这张牌，你觉得画面里正在发生什么？")
                }
            }
        } else if session.stage == .readinessCheck,
                  session.workflowPhase == .contextConfirmation,
                  !session.contextSummaryConfirmed {
            launchResponse { model in
                await model.beginContextConfirmation(
                    action: "resumed_context_confirmation",
                    managesTyping: true
                )
            }
        } else if session.stage == .readinessCheck,
                  session.workflowPhase == .contextConfirmation,
                  session.contextSummaryConfirmed,
                  !session.condition.usesCard {
            launchResponse { model in await model.beginDirectCandidReflection(managesTyping: true) }
        } else if session.stage == .readinessCheck,
                  session.workflowPhase == .contextConfirmation,
                  session.contextSummaryConfirmed,
                  session.messages.last(where: { $0.role == .assistant })?.content
                    .contains("随机抽一张图卡") != true {
            addAssistant("这段整理已经保留好了。接下来可以随机抽一张图卡，换个角度继续看；如果你想抽，直接说“抽卡”就好。")
        } else if session.stage == .attributionReflection {
            switch session.workflowPhase {
            case .cardMappingConfirmation where !session.cardMappingConfirmed:
                if session.cardCandidateMapping?.isEmpty == false {
                    addAssistant(cardMappingConfirmationMessage(session.cardCandidateMapping ?? ""))
                } else {
                    launchResponse { model in await model.presentCardCandidateMapping(managesTyping: true) }
                }
            case .cardMeaningShift where !session.cardMeaningShiftCompleted:
                launchResponse { model in
                    await model.generateDialogue(
                        state: .attributionReflection,
                        goal: "use only the user's own image description and card-to-life connection. Ask how placing them together changes, sharpens, or complicates how the user understands the original situation or their earlier self-evaluation. Make no change a valid answer and add no symbolic meaning, advice, or action"
                    )
                }
            case .candidCircumstances where !session.candidCircumstancesCompleted:
                launchResponse { model in
                    if !model.session.condition.usesCard {
                        await model.generateDialogue(
                            state: .attributionReflection,
                            goal: "DIRECT CONDITION: no card was drawn and no image interpretation exists. Return only to the confirmed situation and ask one tender, concrete question about a real circumstance, limit, or pain that needs to be acknowledged before the person judges themselves. Do not mention cards, images, symbolism, randomization, or the experimental condition. Do not assign responsibility, advise, summarize, or ask for another disclosure field.",
                            managesTyping: true
                        )
                    } else if model.session.cardConnectionUnavailable {
                        await model.beginCandidCircumstancesWithoutCard(
                            reason: "resumed_no_connection_candid_reflection",
                            managesTyping: true
                        )
                    } else {
                        await model.beginCandidCircumstances(managesTyping: true)
                    }
                }
            case .reflectionNarrativeConfirmation where !session.hasPresentedIntegratedNarrative:
                launchResponse { model in
                    await model.presentIntegratedReflectionNarrative(managesTyping: true, revised: false)
                }
            case .narrativeConfirmation where !session.hasPresentedFinalNarrative:
                launchResponse { model in
                    await model.presentFinalNarrative(managesTyping: true, revised: false)
                }
            case .optionalAction:
                launchResponse { model in await model.presentActionDrafts(managesTyping: true) }
            case .actionConfirmation:
                if let proposed = session.pendingUserAuthoredAction,
                   session.messages.last(where: { $0.role == .assistant })?.content
                    .contains("下一步") != true {
                    addAssistant(actionConfirmationPrompt(for: proposed))
                }
            default:
                break
            }
        }
    }

    private func normalizeLegacyWorkflowForResume() {
        switch session.stage {
        case .tenderExploration:
            if session.cardWasSetAside || session.cardConnectionUnavailable {
                session.stage = .attributionReflection
                session.workflowPhase = .candidCircumstances
                session.cardConnectionUnavailable = true
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "legacy_tender_exploration_resumed_as_no_connection")
                )
            } else {
                // Earlier builds could resume the card/no-card choice from this legacy state
                // without ever showing the authorized contextual records. Do not manufacture a
                // completed review while migrating it: both conditions return to the shared
                // tracking gate before any new card invitation or candid reflection.
                session.stage = .trackingPermission
                session.workflowPhase = .trackingReview
                session.trackingReviewCompleted = false
                session.trackingReviewUnavailable = false
                session.contextSummaryConfirmed = false
                session.studyEvents.append(
                    .init(stage: .trackingPermission, action: "legacy_tender_exploration_resumed_at_tracking_review")
                )
            }
            session.dialogueProgress.currentState = session.stage

        case .actionSelection:
            session.stage = .attributionReflection
            if session.hasPresentedIntegratedNarrative {
                session.integratedNarrativeConfirmed = true
                session.workflowPhase = .optionalAction
            } else {
                session.workflowPhase = .reflectionNarrativeConfirmation
            }
            session.dialogueProgress.currentState = session.stage
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "legacy_action_selection_resumed_in_chat")
            )

        case .summary:
            session.stage = .attributionReflection
            session.workflowPhase = .narrativeConfirmation
            session.hasPresentedFinalNarrative = true
            session.dialogueProgress.currentState = session.stage
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "legacy_summary_resumed_for_text_confirmation")
            )

        case .attributionReflection:
            if session.workflowPhase == .cardMeaningShift,
               session.cardMappingConfirmed,
               !session.candidCircumstancesCompleted {
                session.workflowPhase = .candidCircumstances
                session.studyEvents.append(
                    .init(
                        stage: .attributionReflection,
                        action: "legacy_card_meaning_shift_restored_to_tender_circumstances"
                    )
                )
            }
            if session.workflowPhase == .optionalAction,
                      (!session.hasPresentedIntegratedNarrative || !session.integratedNarrativeConfirmed) {
                session.workflowPhase = .reflectionNarrativeConfirmation
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "legacy_optional_action_resumed_at_narrative_review")
                )
            }
            if session.workflowPhase == .candidCircumstances,
               session.hasUserAuthoredCardConnection,
               !session.candidCircumstancesCompleted {
                session.studyEvents.append(
                    .init(
                        stage: .attributionReflection,
                        action: "legacy_card_connection_resumed_at_circumstances"
                    )
                )
            }

        default:
            break
        }
    }

    func startNewInsteadOfResuming() {
        resumeCandidate = nil
        isResumeChoicePresented = false
        resetToNewSession(syncImmediately: true)
    }

    func presentResumeChoice() {
        guard resumeCandidate != nil else { return }
        isResumeChoicePresented = true
    }

    func dismissResumeChoice() {
        isResumeChoicePresented = false
    }

    func save() {
        Task {
            do { try await store.save(session); saveNotice = "已保存在本机" }
            catch { saveNotice = "保存失败" }
        }
    }

    func delete() {
        let localID = session.id
        let cloudID = remoteSessionID
        resumeCandidate = nil
        isResumeChoicePresented = false
        resetToNewSession(syncImmediately: false)
        Task {
            try? await store.delete(id: localID)
            if let cloudID { try? await RemoteAPIService.shared.deleteReflectionSession(id: cloudID) }
            saveNotice = "本机与云端的本次记录已删除"
        }
    }

    func deleteAllLocalReflectionData() {
        Task {
            try? await store.deleteAll()
            resumeCandidate = nil
            isResumeChoicePresented = false
            session = ReflectionSession()
            resetToNewSession(syncImmediately: false)
            saveNotice = "本机反思、tracking 线索、卡片解释和总结已全部删除"
        }
    }

    func prepareExport() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeyondComfort-\(session.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(session).write(to: url, options: .atomic)
            exportURL = url
            saveNotice = "研究记录已准备好；自由文本仍可能包含个人信息，请导出前确认"
        } catch { saveNotice = "导出准备失败" }
    }

    // MARK: - Prompt-only gentle active control

    private func processSimpleGentleControlTurn(
        replyingTo userMessageID: UUID
    ) async {
        let expectedSessionID = session.id
        let expectedStage = session.stage
        guard session.usesSimpleGentleControl else { return }
        let turnNumber = simpleGentleControlUserTurnCount
        let startedAt = Date()
        session.studyEvents.append(
            .init(
                stage: session.stage,
                action: "simple_gentle_control_turn_\(turnNumber)_requested"
            )
        )
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        do {
            let result = try await simpleGentleReflectionGenerator.generate(
                recentMessages: session.messages
            )
            guard responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage
            ), session.usesSimpleGentleControl else { return }
            addAssistant(result.reply, replyingTo: userMessageID)
            session.studyEvents.append(
                .init(stage: session.stage, action: "simple_gentle_control_reply_presented")
            )
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "simple_gentle_control_turn_\(turnNumber)_reply_presented"
                )
            )
            if result.generationAttempts > 1 {
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "simple_gentle_control_reply_regenerated_once"
                    )
                )
            }
            appendSimpleGentleControlLatencyEvent(since: startedAt)
            if turnNumber == simpleGentleControlCompletionOfferTurn {
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "simple_gentle_control_completion_offer_available"
                    )
                )
            }
            if turnNumber == simpleGentleControlSoftBoundaryTurn {
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "simple_gentle_control_soft_boundary_reached"
                    )
                )
            }
            llmStatus = "AI 反思服务已连接"
        } catch {
            guard responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage
            ), session.usesSimpleGentleControl else { return }
            session.studyEvents.append(
                .init(stage: session.stage, action: "simple_gentle_control_reply_failed")
            )
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "simple_gentle_control_turn_\(turnNumber)_reply_failed"
                )
            )
            appendSimpleGentleControlLatencyEvent(since: startedAt)
            addAssistant(
                "刚才没有顺利接上。你愿意的话，可以换一种方式继续。",
                replyingTo: userMessageID
            )
            llmStatus = "AI 反思服务暂时不可用"
        }
    }

    private var simpleGentleControlUserTurnCount: Int {
        session.messages.lazy.filter { $0.role == .user }.count
    }

    private func appendSimpleGentleControlLatencyEvent(since start: Date) {
        let milliseconds = min(
            120_000,
            max(0, Int(Date().timeIntervalSince(start) * 1_000))
        )
        session.studyEvents.append(
            .init(
                stage: session.stage,
                action: "simple_gentle_control_reply_latency_ms_\(milliseconds)"
            )
        )
    }

    private func completeSimpleGentleControl(
        action: String,
        replyingTo userMessageID: UUID? = nil,
        acknowledgement: String? = nil
    ) {
        guard session.usesSimpleGentleControl,
              session.protocolStage != .complete else { return }
        setProtocolStage(.complete, action: action)
        if let acknowledgement {
            addAssistant(acknowledgement, replyingTo: userMessageID)
        }
    }

    // MARK: - Coarse LLM TurnController protocol

    private func processProtocolTurn(
        trigger: LLMTurnTrigger,
        initialCorrection: String? = nil,
        initialPermissions: ReflectionProtocolPermissions? = nil
    ) async {
        let expectedSessionID = session.id
        let expectedProtocolStage = session.protocolStage
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        let initialRequest = makeProtocolTurnRequest(
            trigger: trigger,
            correction: initialCorrection,
            permissionsOverride: initialPermissions
        )
        let firstResult = await requestValidatedProtocolTurn(initialRequest)
        guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
              session.protocolStage == expectedProtocolStage else { return }

        let validated: LLMTurnControllerResponse
        switch firstResult {
        case .success(let response):
            validated = response
        case .failure(let violation):
            if let attempt = violation as? ProtocolTurnAttemptFailure,
               case .incompletePracticeTransition(let transitionError, let rejectedPlan) = attempt,
               await commitFinalNarrativeAcceptanceForPracticeTransition(rejectedPlan) {
                await repairAcceptedNarrativePracticeTransition(
                    after: transitionError,
                    expectedSessionID: expectedSessionID
                )
                return
            }
            if session.protocolStage == .optionalAction,
               session.semanticMemory.practiceTransition?.proposal == nil,
               session.semanticMemory.practiceTransition?.noActionReason == nil,
               let protocolViolation = violation as? ReflectionProtocolViolation,
               case .incompletePracticeTransition = protocolViolation {
                await repairAcceptedNarrativePracticeTransition(
                    after: violation,
                    expectedSessionID: expectedSessionID
                )
                return
            }
            if let attempt = violation as? ProtocolTurnAttemptFailure,
               case .writerFailedTwice(
                   let writerError,
                   let writerRequest,
                   let originalPlan,
                   let validatedPlan
               ) = attempt {
                guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                      session.protocolStage == expectedProtocolStage else { return }
                presentRecoverableProtocolPause(
                    error: writerError,
                    action: "coarse_protocol_writer_response_failed_twice",
                    retry: .writer(
                        request: writerRequest,
                        originalPlan: originalPlan,
                        validatedPlan: validatedPlan
                    )
                )
                return
            }
            session.studyEvents.append(
                .init(stage: session.stage, action: "coarse_protocol_response_regeneration_requested")
            )
            appendProtocolFailureDiagnostic(
                violation,
                prefix: "coarse_protocol_regeneration_reason"
            )
            let repairPermissions = protocolRepairPermissions(for: violation)
            let correction = structuredProtocolCorrection(
                for: violation,
                permissions: repairPermissions
            )
            let retryRequest = makeProtocolTurnRequest(
                trigger: .protocolCorrection,
                correction: correction,
                permissionsOverride: repairPermissions
            )
            switch await requestValidatedProtocolTurn(retryRequest) {
            case .success(let response):
                validated = response
            case .failure(let finalError):
                guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                      session.protocolStage == expectedProtocolStage else { return }
                if finalError as? ReflectionProtocolViolation == .disclosureShouldAdvance {
                    // A correction may atomically fill the relation that it was originally
                    // authorized to ask about. That is monotonic progress, not another bad user
                    // turn. Give the Planner one final, forward-only contract so the completed
                    // evidence becomes a summary instead of surfacing a technical interruption.
                    session.studyEvents.append(
                        .init(
                            stage: session.stage,
                            action: "coarse_protocol_forward_recovery_requested"
                        )
                    )
                    appendProtocolFailureDiagnostic(
                        finalError,
                        prefix: "coarse_protocol_forward_recovery_reason"
                    )
                    let forwardPermissions = protocolRepairPermissions(for: finalError)
                    let forwardRequest = makeProtocolTurnRequest(
                        trigger: .protocolCorrection,
                        correction: structuredProtocolCorrection(
                            for: finalError,
                            permissions: forwardPermissions
                        ),
                        permissionsOverride: forwardPermissions
                    )
                    switch await requestValidatedProtocolTurn(forwardRequest) {
                    case .success(let response):
                        validated = response
                    case .failure(let recoveryError):
                        guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                              session.protocolStage == expectedProtocolStage else { return }
                        if let attempt = recoveryError as? ProtocolTurnAttemptFailure,
                           case .writerFailedTwice(
                               let writerError,
                               let writerRequest,
                               let originalPlan,
                               let validatedPlan
                           ) = attempt {
                            presentRecoverableProtocolPause(
                                error: writerError,
                                action: "coarse_protocol_forward_writer_failed",
                                retry: .writer(
                                    request: writerRequest,
                                    originalPlan: originalPlan,
                                    validatedPlan: validatedPlan
                                )
                            )
                        } else {
                            let recoveryPermissions = protocolRepairPermissions(
                                for: recoveryError
                            )
                            presentRecoverableProtocolPause(
                                error: recoveryError,
                                action: "coarse_protocol_forward_recovery_failed",
                                retry: .planner(
                                    correction: structuredProtocolCorrection(
                                        for: recoveryError,
                                        permissions: recoveryPermissions
                                    ),
                                    permissions: recoveryPermissions
                                )
                            )
                        }
                        return
                    }
                    break
                }
                if isRecoverableProtocolContractFailure(finalError) {
                    // One final, narrowed LLM repair absorbs malformed typed objects across every
                    // stage instead of exposing an implementation error to a study participant.
                    // This is bounded: provider outages and persistence failures do not loop, and
                    // Swift still validates the repaired operation before anything is committed.
                    session.studyEvents.append(
                        .init(
                            stage: session.stage,
                            action: "coarse_protocol_continuity_recovery_requested"
                        )
                    )
                    appendProtocolFailureDiagnostic(
                        finalError,
                        prefix: "coarse_protocol_continuity_recovery_reason"
                    )
                    let continuityPermissions = protocolRepairPermissions(for: finalError)
                    let continuityRequest = makeProtocolTurnRequest(
                        trigger: .protocolCorrection,
                        correction: structuredProtocolCorrection(
                            for: finalError,
                            permissions: continuityPermissions
                        ),
                        permissionsOverride: continuityPermissions
                    )
                    switch await requestValidatedProtocolTurn(continuityRequest) {
                    case .success(let response):
                        validated = response
                        session.studyEvents.append(
                            .init(
                                stage: session.stage,
                                action: "coarse_protocol_continuity_recovery_succeeded"
                            )
                        )
                    case .failure(let recoveryError):
                        guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                              session.protocolStage == expectedProtocolStage else { return }
                        let recoveryPermissions = protocolRepairPermissions(for: recoveryError)
                        presentRecoverableProtocolPause(
                            error: recoveryError,
                            action: "coarse_protocol_continuity_recovery_failed",
                            retry: .planner(
                                correction: structuredProtocolCorrection(
                                    for: recoveryError,
                                    permissions: recoveryPermissions
                                ),
                                permissions: recoveryPermissions
                            )
                        )
                        return
                    }
                    break
                }
                let diagnosticError: Error
                let failureAction: String
                if let attempt = finalError as? ProtocolTurnAttemptFailure,
                   case .writerFailedTwice(
                       let writerError,
                       let writerRequest,
                       let originalPlan,
                       let validatedPlan
                   ) = attempt {
                    diagnosticError = writerError
                    failureAction = "coarse_protocol_writer_response_failed_twice"
                    presentRecoverableProtocolPause(
                        error: diagnosticError,
                        action: failureAction,
                        retry: .writer(
                            request: writerRequest,
                            originalPlan: originalPlan,
                            validatedPlan: validatedPlan
                        )
                    )
                } else {
                    diagnosticError = finalError
                    failureAction = "coarse_protocol_response_failed_twice"
                    let finalRepairPermissions = protocolRepairPermissions(
                        for: diagnosticError
                    )
                    presentRecoverableProtocolPause(
                        error: diagnosticError,
                        action: failureAction,
                        retry: .planner(
                            correction: structuredProtocolCorrection(
                                for: diagnosticError,
                                permissions: finalRepairPermissions
                            ),
                            permissions: finalRepairPermissions
                        )
                    )
                }
                return
            }
        }

        guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
              session.protocolStage == expectedProtocolStage else { return }

        if session.protocolStage == .narrativeConfirmation,
           validated.replyIntent == .suggestPractice {
            let acceptedPlan = LLMTurnResponsePlan(
                requestedStage: validated.requestedStage,
                localAction: validated.localAction,
                memoryUpdate: validated.memoryUpdate,
                resolvedConfirmation: validated.resolvedConfirmation,
                nextPrompt: validated.nextPrompt,
                replyIntent: validated.replyIntent,
                replyGuidance: "validated Optional Action transition"
            )
            if await commitFinalNarrativeAcceptanceForPracticeTransition(acceptedPlan) {
                let successor = LLMTurnControllerResponse(
                    requestedStage: validated.requestedStage,
                    localAction: validated.localAction,
                    memoryUpdate: validated.memoryUpdate,
                    resolvedConfirmation: nil,
                    nextPrompt: validated.nextPrompt,
                    replyIntent: validated.replyIntent,
                    reply: validated.reply
                )
                do {
                    let revalidated = try protocolController.validate(successor, for: session)
                    await commitValidatedProtocolResponseOrPause(revalidated)
                } catch {
                    await repairAcceptedNarrativePracticeTransition(
                        after: error,
                        expectedSessionID: expectedSessionID
                    )
                }
                return
            }
        }

        let resolvesCardMapping = isCardMappingResolutionTransition(validated)
        if resolvesCardMapping {
            do {
                try await applyValidatedProtocolResponse(
                    validated,
                    appendVisibleReply: false
                )
            } catch {
                presentRecoverableProtocolPause(
                    error: error,
                    action: "card_mapping_resolution_commit_failed",
                    retry: .commit(
                        response: validated,
                        appendVisibleReply: false,
                        continuation: .protocolContinuation
                    )
                )
                return
            }
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "card_mapping_resolution_committed_before_continuation"
                )
            )
            await processProtocolTurn(trigger: .protocolContinuation)
            return
        }

        if validated.localAction.kind == .shareCardGuidance {
            do {
                try await applyValidatedProtocolResponse(
                    validated,
                    appendVisibleReply: false
                )
            } catch {
                presentRecoverableProtocolPause(
                    error: error,
                    action: "card_guidance_authorization_commit_failed",
                    retry: .commit(
                        response: validated,
                        appendVisibleReply: false,
                        continuation: .cardGuidanceAvailable
                    )
                )
                return
            }
            guard session.pendingCardGuidanceTurn else { return }

            let guidanceRequest = makeProtocolTurnRequest(
                trigger: .cardGuidanceAvailable,
                correction: nil,
                permissionsOverride: nil
            )
            switch await requestValidatedProtocolTurn(guidanceRequest) {
            case .success(let guidedResponse):
                await commitValidatedProtocolResponseOrPause(guidedResponse)
            case .failure(let violation):
                session.studyEvents.append(
                    .init(stage: session.stage, action: "card_guidance_response_regeneration_requested")
                )
                appendProtocolFailureDiagnostic(
                    violation,
                    prefix: "card_guidance_regeneration_reason"
                )
                let repairPermissions = protocolRepairPermissions(for: violation)
                let retry = makeProtocolTurnRequest(
                    trigger: .protocolCorrection,
                    correction: structuredProtocolCorrection(
                        for: violation,
                        permissions: repairPermissions
                    ),
                    permissionsOverride: repairPermissions
                )
                switch await requestValidatedProtocolTurn(retry) {
                case .success(let guidedResponse):
                    await commitValidatedProtocolResponseOrPause(guidedResponse)
                case .failure(let finalError):
                    if let attempt = finalError as? ProtocolTurnAttemptFailure,
                       case .writerFailedTwice(
                           let writerError,
                           let writerRequest,
                           let originalPlan,
                           let validatedPlan
                       ) = attempt {
                        presentRecoverableProtocolPause(
                            error: writerError,
                            action: "card_guidance_writer_response_failed_twice",
                            retry: .writer(
                                request: writerRequest,
                                originalPlan: originalPlan,
                                validatedPlan: validatedPlan
                            )
                        )
                    } else {
                        let finalRepairPermissions = protocolRepairPermissions(
                            for: finalError
                        )
                        presentRecoverableProtocolPause(
                            error: finalError,
                            action: "card_guidance_response_failed_twice",
                            retry: .planner(
                                correction: structuredProtocolCorrection(
                                    for: finalError,
                                    permissions: finalRepairPermissions
                                ),
                                permissions: finalRepairPermissions
                            )
                        )
                    }
                }
            }
            return
        }

        await commitValidatedProtocolResponseOrPause(validated)
    }

    /// The Planner has already interpreted the pending final-narrative response. Persist that
    /// accepted boundary before attempting to repair a malformed successor proposal, so a model
    /// formatting failure can never reopen or re-interpret the same confirmation.
    private func commitFinalNarrativeAcceptanceForPracticeTransition(
        _ rejectedPlan: LLMTurnResponsePlan
    ) async -> Bool {
        guard isAcceptedNarrativePracticeAttempt(rejectedPlan),
              let resolution = rejectedPlan.resolvedConfirmation else {
            return false
        }
        let snapshot = session
        let transactionID = session.semanticMemory.practiceTransition?.transactionID
            ?? rejectedPlan.memoryUpdate.practiceTransition?.transactionID
            ?? UUID().uuidString
        let narrativeReferenceID = session.semanticMemory.nextPrompt?.referenceID
        if let revised = rejectedPlan.memoryUpdate.finalNarrative?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !revised.isEmpty {
            session.semanticMemory.finalNarrative = revised
        }
        session.semanticMemory.practiceTransition = TurnPracticeTransition(
            transactionID: transactionID,
            narrativeReferenceID: narrativeReferenceID,
            proposal: nil,
            noActionReason: nil
        )
        session.semanticMemory.nextPrompt = nil
        session.finalNarrativeConfirmed = true
        setProtocolStage(
            .optionalAction,
            action: "final_narrative_\(resolution.decision.rawValue)_committed_before_practice"
        )
        session.studyEvents.append(
            .init(stage: session.stage, action: "practice_transition_awaiting_proposal")
        )
        do {
            try await store.save(session)
            scheduleCloudSync(action: "final_narrative_acceptance_committed")
            return true
        } catch {
            session = snapshot
            session.studyEvents.append(
                .init(stage: session.stage, action: "final_narrative_acceptance_commit_rolled_back")
            )
            return false
        }
    }

    private func isAcceptedNarrativePracticeAttempt(
        _ plan: LLMTurnResponsePlan
    ) -> Bool {
        guard session.protocolStage == .narrativeConfirmation,
              session.semanticMemory.nextPrompt?.target == .finalNarrative,
              plan.replyIntent == .suggestPractice,
              plan.resolvedConfirmation?.target == .finalNarrative,
              let decision = plan.resolvedConfirmation?.decision,
              [.accepted, .revised].contains(decision),
              session.semanticMemory.finalNarrative?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty == false else {
            return false
        }
        let pendingReference = session.semanticMemory.nextPrompt?.referenceID
        return pendingReference == nil
            || plan.resolvedConfirmation?.referenceID == pendingReference
    }

    /// Exactly one Planner call owns repair of an accepted-narrative successor. It cannot revisit
    /// the narrative decision or choose another stage. A second failure ends through the formal
    /// noAction transaction instead of entering the generic continuity Planner.
    private func repairAcceptedNarrativePracticeTransition(
        after error: Error,
        expectedSessionID: UUID
    ) async {
        guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
              session.protocolStage == .optionalAction,
              let transition = session.semanticMemory.practiceTransition,
              transition.proposal == nil,
              transition.noActionReason == nil else {
            return
        }
        session.studyEvents.append(
            .init(stage: session.stage, action: "practice_transition_targeted_repair_requested")
        )
        appendProtocolFailureDiagnostic(
            error,
            prefix: "practice_transition_targeted_repair_reason"
        )
        let base = protocolController.permissions(for: session)
        let permissions = ReflectionProtocolPermissions(
            currentStage: base.currentStage,
            allowedStages: [.optionalAction],
            allowedActions: [.none],
            allowedReplyIntents: [.suggestPractice],
            allowedDisclosurePurposes: [],
            allowedDisclosureTargets: [],
            allowedOperations: base.allowedOperations.filter {
                $0.requestedStage == .optionalAction
                    && $0.localAction == .none
                    && $0.replyIntent == .suggestPractice
            }
        )
        let correction = """
        The finalNarrative confirmation is already committed and must not appear again. Repair only
        its pending Optional Action successor. Reuse transactionID \(transition.transactionID) and
        narrativeReferenceID \(transition.narrativeReferenceID ?? "null"). Return no
        resolvedConfirmation, requestedStage=optionalAction, replyIntent=suggestPractice,
        localAction=none, one complete practiceTransition whose proposal.id equals that transaction
        ID and contains a supported kind, non-empty content, non-empty user-evidence basis,
        status=pendingConfirmation, source=assistantProposed, noActionReason=null, and one
        confirmationRequest nextPrompt targeting practice with the same proposal id. Do not revisit
        the narrative, select another stage, ask an open question, or emit retired practice fields.
        """
        let request = makeProtocolTurnRequest(
            trigger: .protocolCorrection,
            correction: correction,
            permissionsOverride: permissions
        )
        switch await requestValidatedProtocolTurn(request) {
        case .success(let response):
            await commitValidatedProtocolResponseOrPause(response)
            session.studyEvents.append(
                .init(stage: session.stage, action: "practice_transition_targeted_repair_succeeded")
            )
        case .failure(let repairError):
            appendProtocolFailureDiagnostic(
                repairError,
                prefix: "practice_transition_targeted_repair_failed"
            )
            await completeAcceptedNarrativeWithoutPractice()
        }
    }

    private func completeAcceptedNarrativeWithoutPractice() async {
        guard var transition = session.semanticMemory.practiceTransition,
              transition.proposal == nil else { return }
        let snapshot = session
        transition.noActionReason = .insufficientSupportedMaterial
        session.semanticMemory.practiceTransition = transition
        session.semanticMemory.nextPrompt = nil
        session.userAuthoredActionConfirmed = false
        setProtocolStage(.complete, action: "practice_transition_completed_without_proposal")
        appendProtocolAssistant(
            "好，这段反思已经按你确认的内容保留下来。今天先停在这里，不必另外完成一个行动。"
        )
        session.studyEvents.append(
            .init(stage: session.stage, action: "practice_transition_repair_budget_exhausted_no_action")
        )
        do {
            try await store.save(session)
            scheduleCloudSync(action: "practice_transition_no_action_completed")
        } catch {
            session = snapshot
            presentRecoverableProtocolPause(
                error: ProtocolCommitFailure.persistenceFailed,
                action: "practice_transition_no_action_commit_failed",
                retry: .planner(
                    correction: "Resume the already committed Optional Action transaction without reinterpreting the final narrative.",
                    permissions: protocolController.permissions(for: session)
                )
            )
        }
    }

    /// Contract and decoding defects are model-output problems that can usually be repaired with
    /// the same LLM under narrower permissions. Provider availability and persistence errors are
    /// operational failures; retrying the semantic protocol cannot repair them and would only
    /// make the participant wait longer.
    private func isRecoverableProtocolContractFailure(_ error: Error) -> Bool {
        guard session.protocolVersion >= ReflectionSession.currentProtocolVersion else {
            return false
        }
        if error is ReflectionProtocolViolation { return true }
        if error is LLMTurnControllerClientError { return true }
        return false
    }

    private func requestValidatedProtocolTurn(
        _ request: LLMTurnControllerRequest
    ) async -> Result<LLMTurnControllerResponse, Error> {
        var proposedPlan: LLMTurnResponsePlan?
        do {
            let generatedPlan = try await turnController.plan(to: request)
            proposedPlan = generatedPlan
            let validatedPlan = try protocolController.validate(generatedPlan, for: session)
            lockNarrativeReadinessIfRequested(by: validatedPlan)
            let nonBlockingWarnings = protocolController.nonBlockingWarnings(
                originalPlan: generatedPlan,
                validatedPlan: validatedPlan,
                for: session
            )

            if isCardMappingResolutionTransition(validatedPlan) {
                // This is a silent confirmation-only transaction. Writer generation belongs to
                // the fresh protocolContinuation request after the new stage has committed.
                let response = LLMTurnControllerResponse(
                    requestedStage: validatedPlan.requestedStage,
                    localAction: validatedPlan.localAction,
                    memoryUpdate: validatedPlan.memoryUpdate,
                    resolvedConfirmation: validatedPlan.resolvedConfirmation,
                    nextPrompt: validatedPlan.nextPrompt,
                    replyIntent: validatedPlan.replyIntent,
                    reply: "local_card_mapping_resolution"
                )
                return .success(try protocolController.validate(response, for: session))
            }

            func recordNonBlockingWarnings() {
                for warning in nonBlockingWarnings {
                    let action = warning == .redundantConfirmedConnectionPatch
                        ? warning.rawValue
                        : "coarse_protocol_soft_warning_\(warning.rawValue)"
                    session.studyEvents.append(
                        .init(
                            stage: session.stage,
                            action: action
                        )
                    )
                }
            }

            // Local card capability operations are deliberately silent. Drawing first waits for
            // the image to become visible, then the cardDisplayed turn produces the one observation
            // reply. User-grounded relation authorization similarly waits for a fresh reading turn.
            // Generating wording here would create two competing assistant bubbles.
            if [.drawRandomCard, .shareCardGuidance].contains(
                validatedPlan.localAction.kind
            ) {
                let acknowledgement = validatedPlan.localAction.kind == .drawRandomCard
                    ? "local_card_draw_authorization"
                    : "local_card_guidance_authorization"
                let silentAuthorization = LLMTurnControllerResponse(
                    requestedStage: validatedPlan.requestedStage,
                    localAction: validatedPlan.localAction,
                    memoryUpdate: validatedPlan.memoryUpdate,
                    resolvedConfirmation: validatedPlan.resolvedConfirmation,
                    nextPrompt: validatedPlan.nextPrompt,
                    replyIntent: validatedPlan.replyIntent,
                    reply: acknowledgement
                )
                let response = try protocolController.validate(
                    silentAuthorization,
                    for: session
                )
                recordNonBlockingWarnings()
                return .success(response)
            }

            switch await requestValidatedProtocolWriter(
                request: request,
                validatedPlan: validatedPlan
            ) {
            case .success(let response):
                recordNonBlockingWarnings()
                return .success(response)
            case .failure(let writerError):
                return .failure(
                    ProtocolTurnAttemptFailure.writerFailedTwice(
                        error: writerError,
                        request: request,
                        originalPlan: generatedPlan,
                        validatedPlan: validatedPlan
                    )
                )
            }
        } catch {
            if let proposedPlan {
                lockNarrativeReadinessIfRequested(by: proposedPlan)
            }
            if let proposedPlan,
               error is ReflectionProtocolViolation {
                appendRejectedProtocolPlanDiagnostic(proposedPlan)
            }
            if let proposedPlan,
               let violation = error as? ReflectionProtocolViolation,
               case .incompletePracticeTransition = violation,
               isAcceptedNarrativePracticeAttempt(proposedPlan) {
                return .failure(
                    ProtocolTurnAttemptFailure.incompletePracticeTransition(
                        error: error,
                        plan: proposedPlan
                    )
                )
            }
            return .failure(error)
        }
    }

    private func lockNarrativeReadinessIfRequested(
        by plan: LLMTurnResponsePlan
    ) {
        guard session.protocolStage == .directReflection,
              plan.replyIntent == .presentFinalNarrative,
              session.reflectionReadiness != .narrativeReady else {
            return
        }
        // This is a progress lock, not a claim that the candidate narrative was valid. Once the
        // semantic Planner has selected final-narrative generation, a missing object or Writer
        // failure may repair only that same operation; it must not reopen completed questions.
        session.reflectionReadiness = .narrativeReady
        session.studyEvents.append(
            .init(stage: session.stage, action: "reflection_readiness_locked_narrative_ready")
        )
        scheduleCloudSync(action: "reflection_readiness_locked_narrative_ready")
    }

    private func requestValidatedProtocolWriter(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async -> Result<LLMTurnControllerResponse, Error> {
        func materialize(
            using writerRequest: LLMTurnControllerRequest
        ) async throws -> LLMTurnControllerResponse {
            let unvalidatedWording = try await turnController.write(
                request: writerRequest,
                validatedPlan: validatedPlan
            )
            let wording = try protocolController.validate(
                unvalidatedWording,
                for: validatedPlan
            )
            let response = LLMTurnControllerResponse(
                requestedStage: validatedPlan.requestedStage,
                localAction: validatedPlan.localAction,
                memoryUpdate: validatedPlan.memoryUpdate,
                resolvedConfirmation: validatedPlan.resolvedConfirmation,
                nextPrompt: validatedPlan.nextPrompt,
                replyIntent: validatedPlan.replyIntent,
                reply: wording.reply
            )
            return try protocolController.validate(response, for: session)
        }

        do {
            return .success(try await materialize(using: request))
        } catch {
            // The Planner decision is already valid. A Writer-format or wording failure must not
            // re-run semantic planning or change the next stage.
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "coarse_protocol_writer_regeneration_requested"
                )
            )
            appendProtocolFailureDiagnostic(
                error,
                prefix: "coarse_protocol_writer_regeneration_reason"
            )
            let writerRetry = protocolRequest(
                request,
                replacingCorrectionWith: structuredWriterCorrection(
                    for: error,
                    preserving: validatedPlan
                )
            )
            do {
                return .success(try await materialize(using: writerRetry))
            } catch {
                return .failure(error)
            }
        }
    }

    private func resumeValidatedProtocolWriter(
        request: LLMTurnControllerRequest,
        originalPlan: LLMTurnResponsePlan,
        validatedPlan: LLMTurnResponsePlan
    ) async {
        let expectedSessionID = session.id
        let expectedProtocolStage = session.protocolStage
        guard request.protocolStage == expectedProtocolStage else {
            session.studyEvents.append(
                .init(stage: session.stage, action: "protocol_retry_discarded_after_stage_change")
            )
            return
        }
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        switch await requestValidatedProtocolWriter(
            request: request,
            validatedPlan: validatedPlan
        ) {
        case .success(let response):
            guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                  session.protocolStage == expectedProtocolStage else { return }
            for warning in protocolController.nonBlockingWarnings(
                originalPlan: originalPlan,
                validatedPlan: validatedPlan,
                for: session
            ) {
                let action = warning == .redundantConfirmedConnectionPatch
                    ? warning.rawValue
                    : "coarse_protocol_soft_warning_\(warning.rawValue)"
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: action
                    )
                )
            }
            await commitValidatedProtocolResponseOrPause(response)
        case .failure(let error):
            guard responseContextIsCurrent(expectedSessionID: expectedSessionID),
                  session.protocolStage == expectedProtocolStage else { return }
            presentRecoverableProtocolPause(
                error: error,
                action: "coarse_protocol_writer_response_failed_twice",
                retry: .writer(
                    request: request,
                    originalPlan: originalPlan,
                    validatedPlan: validatedPlan
                )
            )
        }
    }

    private func protocolRequest(
        _ request: LLMTurnControllerRequest,
        replacingCorrectionWith correction: String?
    ) -> LLMTurnControllerRequest {
        LLMTurnControllerRequest(
            trigger: .protocolCorrection,
            protocolVersion: request.protocolVersion,
            protocolStage: request.protocolStage,
            condition: request.condition,
            permissions: request.permissions,
            recentMessages: request.recentMessages,
            semanticMemory: request.semanticMemory,
            trackingCandidates: request.trackingCandidates,
            contextualLoadCue: request.contextualLoadCue,
            presentedTrackingCues: request.presentedTrackingCues,
            activeTrackingPresentation: request.activeTrackingPresentation,
            cardMappingConfirmed: request.cardMappingConfirmed,
            card: request.card,
            protocolCorrection: correction
        )
    }

    /// Stores only protocol-shape metadata. It deliberately excludes dialogue, tracking values,
    /// semantic memory text, and Writer output so production diagnostics remain non-sensitive.
    private func appendRejectedProtocolPlanDiagnostic(_ plan: LLMTurnResponsePlan) {
        let target = plan.nextPrompt?.target?.rawValue ?? "none"
        let disclosureTarget = plan.nextPrompt?.disclosureTarget?.rawValue ?? "none"
        let episodeFields = plan.memoryUpdate.episodeStructure?
            .explicitlyProvidedFieldNames.joined(separator: ",") ?? "none"
        let nextKind = plan.nextPrompt?.kind.rawValue ?? "none"
        let resolvedTarget = plan.resolvedConfirmation?.target.rawValue ?? "none"
        let assessmentCount = plan.memoryUpdate.trackingAssessments?.count ?? 0
        let action = [
            "rejected_plan",
            "requested_\(plan.requestedStage.rawValue)",
            "intent_\(plan.replyIntent.rawValue)",
            "action_\(plan.localAction.kind.rawValue)",
            "next_\(nextKind)",
            "disclosure_\(disclosureTarget)",
            "target_\(target)",
            "resolved_\(resolvedTarget)",
            "assessments_\(assessmentCount)",
            "episode_fields_\(episodeFields)",
        ].joined(separator: "_")
        session.studyEvents.append(
            .init(stage: session.stage, action: String(action.prefix(220)))
        )
    }

    private func makeProtocolTurnRequest(
        trigger: LLMTurnTrigger,
        correction: String?,
        permissionsOverride: ReflectionProtocolPermissions? = nil
    ) -> LLMTurnControllerRequest {
        let permissions = permissionsOverride
            ?? protocolController.permissions(for: session)
        // New sessions never create a separate tracking presentation. The measurement-free
        // aggregate below is folded into an ordinary synthesis instead of becoming a relevance
        // question. Keep the legacy array empty so a Planner cannot select presentTrackingCue.
        let trackingCandidates: [LLMTurnTrackingCandidate] = []

        // Presented cues are a separate typed namespace from unused candidates. The Planner may
        // copy these opaque IDs into a later trackingAssessment, but it cannot present them again.
        // Keeping the observation alongside the ID also lets a restored session understand what
        // the latest tracking question referred to without inferring an ID from visible prose.
        let assessedTrackingCueIDs = Set(
            session.semanticMemory.trackingAssessments.map(\.cueID)
        )
        let activeTrackingCueIDs = session.activeTrackingPresentationID
            .flatMap { activeID in
                session.trackingPresentations.first(where: { $0.id == activeID })
            }
            .map { Set($0.cueIDs) }
        let presentedTrackingCues = session.trackingCues
            .filter {
                session.presentedTrackingCueIDs.contains($0.id)
                    && !assessedTrackingCueIDs.contains($0.id)
                    && (activeTrackingCueIDs == nil || activeTrackingCueIDs?.contains($0.id) == true)
            }
            .map {
                LLMTurnTrackingCandidate(
                    id: $0.id,
                    observation: trackingObservationForDialogue($0)
                )
            }
            .filter { !$0.observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.id < $1.id }

        let activeTrackingPresentation = session.activeTrackingPresentationID
            .flatMap { activeID in
                session.trackingPresentations.first(where: { $0.id == activeID })
            }
            .map {
                LLMTurnTrackingPresentationContext(
                    id: $0.id,
                    cueIDs: $0.cueIDs
                )
            }

        let cardContext: LLMTurnCardContext?
        if let card = session.card,
           session.cardDisplayState == .displayed,
           !session.cardWasSetAside {
            let guidance = card.visualGuidance
            let postMappingGuidanceAvailable = session.cardGuidanceShared
                && protocolController.effectiveCardRealityConnection(for: session) != nil
            cardContext = LLMTurnCardContext(
                imageIsDisplayed: true,
                imageDevelopmentTurnCount: session.cardImageDevelopmentTurnCount,
                connectionAttemptCount: session.cardConnectionAttemptCount,
                connectionScaffoldUsed: session.cardConnectionScaffoldUsed,
                connectionUnavailable: session.cardConnectionUnavailable,
                realityAnchor: protocolCardRealityAnchor(),
                visualScaffolds: session.cardConnectionScaffoldUsed
                    ? []
                    : eligibleProtocolCardScaffolds(
                        guidance?.visualScaffolds ?? []
                    ),
                reflectionApproaches: postMappingGuidanceAvailable
                    ? SystemReflectionApproaches.standard
                    : nil,
                referenceGuidance: postMappingGuidanceAvailable
                    ? cards.canonicalReferenceGuidance(for: card)
                    : nil,
                prohibitedClaims: [
                    "画面不能证明现实中的原因、动机、情绪、人格、能力、责任、限制、需求或结果",
                    "在用户接受或修订现实映射前，只能比较用户描述的画面动作或关系与已确认的现实动作、过程或结果；不得使用卡牌内涵深化解释",
                    "Reality Connection 只能使用 realityAnchor 中的当前焦点事件；不得要求用户搜索另一段生活经历来让卡牌成立",
                ]
            )
        } else {
            cardContext = nil
        }

        return LLMTurnControllerRequest(
            trigger: trigger,
            protocolVersion: session.protocolVersion,
            protocolStage: session.protocolStage,
            condition: session.condition,
            permissions: permissions,
            recentMessages: session.messages
                .filter { !session.supersededAssistantMessageIDs.contains($0.id) }
                .suffix(18)
                .map {
                LLMTurnTranscriptItem(role: $0.role, content: $0.content)
            },
            semanticMemory: session.semanticMemory,
            trackingCandidates: trackingCandidates,
            contextualLoadCue: protocolContextualLoadCue(),
            presentedTrackingCues: presentedTrackingCues,
            activeTrackingPresentation: activeTrackingPresentation,
            cardMappingConfirmed: session.cardMappingConfirmed,
            card: cardContext,
            protocolCorrection: correction
        )
    }

    /// Projects only the already committed focal episode into card work. This is a source and
    /// scope boundary, not a semantic choice: the LLM still decides which observable relation is
    /// useful and how to ask about it. Empty, duplicate, and uncommitted material never becomes a
    /// substitute life story for the card.
    private func protocolCardRealityAnchor() -> LLMTurnCardRealityAnchor? {
        guard let episode = session.semanticMemory.episodeStructure else { return nil }

        func cleaned(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.compactMap { value in
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty, seen.insert(clean).inserted else { return nil }
                return clean
            }
        }

        let anchor = LLMTurnCardRealityAnchor(
            concreteFacts: cleaned(episode.concreteFacts),
            eventProcess: cleaned(
                episode.behaviorEvidence
                    + episode.possibleContributors
                    + episode.contextualConstraints
                    + episode.controllableParts
            ),
            impacts: cleaned(episode.impacts)
        )
        return anchor.hasContent ? anchor : nil
    }

    /// Card-specific scaffolds remain local affordances. The model receives only questions whose
    /// own anchor groups are already present in user messages written after the image appeared;
    /// a word from the earlier life story cannot accidentally authorize a new picture element.
    private func eligibleProtocolCardScaffolds(
        _ scaffolds: [CardVisualScaffold]
    ) -> [CardVisualScaffold] {
        let imageNarrative = comparableText(
            session.messages
                .filter { $0.role == .user && $0.state == .cardInterpretation }
                .map(\.content)
                .joined(separator: " ")
        )
        guard !imageNarrative.isEmpty else { return [] }
        return scaffolds.filter { scaffold in
            !scaffold.requiredAnchorGroups.isEmpty &&
            scaffold.requiredAnchorGroups.allSatisfy { group in
                group.contains { anchor in
                    let normalized = comparableText(anchor)
                    return !normalized.isEmpty && imageNarrative.contains(normalized)
                }
            }
        }
    }

    private func commitValidatedProtocolResponseOrPause(
        _ response: LLMTurnControllerResponse
    ) async {
        do {
            try await applyValidatedProtocolResponse(response)
        } catch {
            presentRecoverableProtocolPause(
                error: error,
                action: "coarse_protocol_persistence_commit_failed",
                retry: .commit(
                    response: response,
                    appendVisibleReply: true,
                    continuation: nil
                )
            )
        }
    }

    private func resumeValidatedProtocolCommit(
        _ response: LLMTurnControllerResponse,
        appendVisibleReply: Bool,
        continuation: LLMTurnTrigger?
    ) async {
        do {
            try await applyValidatedProtocolResponse(
                response,
                appendVisibleReply: appendVisibleReply
            )
        } catch {
            presentRecoverableProtocolPause(
                error: error,
                action: "coarse_protocol_persistence_commit_failed",
                retry: .commit(
                    response: response,
                    appendVisibleReply: appendVisibleReply,
                    continuation: continuation
                )
            )
            return
        }
        if let continuation {
            await processProtocolTurn(trigger: continuation)
        }
    }

    private func applyValidatedProtocolResponse(
        _ response: LLMTurnControllerResponse,
        appendVisibleReply: Bool = true
    ) async throws {
        let sessionBeforeCommit = session
        let previousStage = session.protocolStage
        let presentsContextualizedCardReading =
            previousStage == .cardReflection &&
            response.replyIntent == .presentCardReading &&
            (
                session.protocolVersion < ReflectionSession.currentProtocolVersion ||
                response.memoryUpdate.contextCueOffered == true
            ) &&
            protocolContextualLoadCue() != nil
        let committedNextPrompt = applyProtocolMemoryAndTracking(from: response)
        applyCurrentContextRelationship(from: response.memoryUpdate)
        updateProtocolCardConnectionCapabilities(
            after: response,
            previousStage: previousStage
        )
        setProtocolStage(response.requestedStage, action: "llm_requested_protocol_stage")
        session.studyEvents.append(
            .init(
                stage: session.stage,
                action: "protocol_transition_\(previousStage.rawValue)_to_\(response.requestedStage.rawValue)_intent_\(response.replyIntent.rawValue)"
            )
        )
        if presentsContextualizedCardReading {
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "contextualized_card_reading_candidate_presented"
                )
            )
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion,
               session.contextualLoadInference?.relevance == .notReviewed {
                // Presentation alone never confirms relevance. Keep the cue out of the final
                // narrative unless a later user response supplies a typed relationship.
                session.contextualLoadInference?.relevance = .offered
                session.studyEvents.append(
                    .init(stage: session.stage, action: "contextual_cue_offered_after_card_mapping")
                )
            }
        }

        if previousStage == .contextualDisclosure,
           [.cardConsent, .directReflection].contains(response.requestedStage) {
            // The current disclosure boundary is complete once the event, its process, and the
            // person's behavior are present. A brief compassionate bridge may be part of the
            // wording, but it is not a persisted confirmation or a workflow gate.
            session.reflectionReadiness = .reflectionOpen
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "event_disclosure_core_completed"
                )
            )
        }
        if response.requestedStage == .directReflection,
           session.reflectionReadiness == .needsTender {
            session.reflectionReadiness = .reflectionOpen
        }
        if response.replyIntent == .presentFinalNarrative {
            session.reflectionReadiness = .narrativeReady
        }

        switch response.localAction.kind {
        case .none:
            break
        case .presentTrackingCue:
            session.presentedTrackingCueIDs.formUnion(response.localAction.trackingCueIDs)
            session.studyEvents.append(
                .init(stage: session.stage, action: "cleaned_tracking_cue_presented")
            )
        case .drawRandomCard:
            session.stage = .cardIntroduction
            session.workflowPhase = .cardSelection
            session.dialogueProgress.currentState = .cardIntroduction
            drawCard(replyingTo: ReflectionResponseContext.userMessageID)
        case .shareCardGuidance:
            guard protocolController.effectiveCardRealityConnection(for: session) != nil else {
                throw ReflectionProtocolViolation.shareGuidanceWithoutConfirmedConnection
            }
            let transactionID = currentCardGuidanceTransactionID()
            if session.cardGuidanceTransactionID == transactionID,
               session.cardGuidanceShared,
               !session.pendingCardGuidanceTurn {
                session.studyEvents.append(
                    .init(stage: session.stage, action: "duplicate_transaction_ignored")
                )
            } else {
                session.cardGuidanceShared = true
                session.pendingCardGuidanceTurn = true
                session.cardGuidanceTransactionID = transactionID
                session.studyEvents.append(
                    .init(stage: session.stage, action: "card_guidance_context_authorized")
                )
                session.studyEvents.append(
                    .init(stage: session.stage, action: "silent_transaction_committed")
                )
                if response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    == "local_card_guidance_authorization" {
                    session.studyEvents.append(
                        .init(stage: session.stage, action: "silent_empty_reply_accepted")
                    )
                }
            }
        case .completeSession:
            session.finalNarrativeConfirmed =
                session.semanticMemory.finalNarrative?.isEmpty == false
            session.userAuthoredActionConfirmed =
                session.semanticMemory.practiceTransition?.proposal?.status == .confirmed
            session.studyEvents.append(
                .init(stage: session.stage, action: "coarse_protocol_completion_committed")
            )
        }

        if let committedNextPrompt {
            session.studyEvents.append(
                .init(
                    stage: session.stage,
                    action: "next_prompt_committed_\(committedNextPrompt.kind.rawValue)"
                )
            )
        }
        if appendVisibleReply, response.localAction.kind != .drawRandomCard {
            appendProtocolAssistant(response.reply)
        }
        if response.replyIntent == .presentCardReading {
            session.pendingCardGuidanceTurn = false
        }
        do {
            try await store.save(session)
        } catch {
            session = sessionBeforeCommit
            session.studyEvents.append(
                .init(stage: session.stage, action: "coarse_protocol_persistence_rollback")
            )
            throw ProtocolCommitFailure.persistenceFailed
        }
        scheduleCloudSync(action: "coarse_protocol_turn_completed")
    }

    private func currentCardGuidanceTransactionID() -> String {
        let userTurnID = ReflectionResponseContext.userMessageID
            ?? session.messages.last(where: { $0.role == .user })?.id
            ?? session.id
        return "card-guidance-\(session.id.uuidString)-\(userTurnID.uuidString)"
    }

    /// Connection attempts count typed semantic outcomes, never assistant questions or technical
    /// retries. Swift does not inspect dialogue text to decide whether a connection was formed.
    private func updateProtocolCardConnectionCapabilities(
        after response: LLMTurnControllerResponse,
        previousStage: ReflectionProtocolStage
    ) {
        guard previousStage == .cardReflection else { return }

        switch response.replyIntent {
        case .developCardImage:
            if response.memoryUpdate.cardConnectionOutcome == .noConnectionFound
                || session.cardConnectionAttemptCount >= 1 {
                session.cardConnectionScaffoldUsed = true
                session.cardConnectionScaffoldPending = true
            } else {
                session.cardImageDevelopmentTurnCount += 1
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "card_image_development_turn_\(session.cardImageDevelopmentTurnCount)_committed"
                    )
                )
            }
        case .deepenCardConnection:
            session.cardConnectionDeepeningUsed = true
            session.cardConnectionScaffoldPending = false
        case .authorizeCardGuidance, .presentCardReading:
            session.cardConnectionScaffoldPending = false
        case .directCandidReflection
            where response.requestedStage == .directReflection
                && !isCardMappingResolutionTransition(response)
                && protocolController.effectiveCardRealityConnection(for: session) == nil:
            session.cardConnectionUnavailable = true
            session.cardWasSetAside = true
            session.cardConnectionScaffoldPending = false
        default:
            break
        }

        switch response.memoryUpdate.cardConnectionOutcome {
        case .noConnectionFound, .candidateRejected:
            session.cardConnectionAttemptCount += 1
            if session.cardConnectionAttemptCount >= 2 {
                session.cardConnectionScaffoldPending = false
            }
        case .connectionConfirmed:
            session.cardConnectionScaffoldPending = false
            session.cardConnectionScaffoldUsed = false
            session.cardConnectionUnavailable = false
            session.cardWasSetAside = false
        case .userRequestedSkip:
            session.cardConnectionScaffoldPending = false
            session.cardConnectionUnavailable = true
            session.cardWasSetAside = true
        case .partialConnection, .none:
            break
        }
    }

    private func isCardMappingResolutionTransition(
        _ response: LLMTurnControllerResponse
    ) -> Bool {
        guard session.semanticMemory.nextPrompt?.target == .cardMapping,
              response.requestedStage == .directReflection,
              response.replyIntent == .directCandidReflection,
              response.resolvedConfirmation?.target == .cardMapping,
              let decision = response.resolvedConfirmation?.decision else {
            return false
        }
        return [.accepted, .revised, .rejected].contains(decision)
    }

    private func isCardMappingResolutionTransition(
        _ plan: LLMTurnResponsePlan
    ) -> Bool {
        guard session.semanticMemory.nextPrompt?.target == .cardMapping,
              plan.requestedStage == .directReflection,
              plan.replyIntent == .directCandidReflection,
              plan.resolvedConfirmation?.target == .cardMapping,
              let decision = plan.resolvedConfirmation?.decision else {
            return false
        }
        return [.accepted, .revised, .rejected].contains(decision)
    }

    /// Commits the Planner patch only after planning, protocol validation, Writer generation, and
    /// Writer validation have all succeeded. The new pending prompt is assigned its application-
    /// owned reference here, in the same mutation as tracking-batch resolution.
    @discardableResult
    private func applyProtocolMemoryAndTracking(
        from response: LLMTurnControllerResponse
    ) -> TurnNextPrompt? {
        let update = response.memoryUpdate
        var newlyPresentedBatchID: String?

        if response.localAction.kind == .presentTrackingCue {
            let presentation = TurnTrackingPresentation(
                cueIDs: response.localAction.trackingCueIDs,
                presentedAtUserTurnID: ReflectionResponseContext.userMessageID
            )
            session.trackingPresentations.append(presentation)
            session.activeTrackingPresentationID = presentation.id
            session.presentedTrackingCueIDs.formUnion(presentation.cueIDs)
            newlyPresentedBatchID = presentation.id
        }

        if let resolution = response.resolvedConfirmation,
           resolution.target == .trackingRelationship,
           let activeID = session.activeTrackingPresentationID,
           let presentationIndex = session.trackingPresentations.firstIndex(where: {
               $0.id == activeID
           }) {
            session.trackingPresentations[presentationIndex].resolution = resolution.decision
            // The confirmation resolves the application-owned presentation as one batch. Do not
            // manufacture a separate cue-level interpretation for every included metric. The
            // Planner may add individual assessments only when the person's words actually
            // distinguish those cues.
            session.activeTrackingPresentationID = nil
        }

        if let resolution = response.resolvedConfirmation,
           resolution.target == .cardMapping {
            if [.revised, .rejected].contains(resolution.decision),
               let superseded = session.messages.last(where: { $0.role == .assistant }) {
                // Keep the visible message in the research transcript while ensuring that the
                // correction—not the superseded candidate—is the only interpretation available
                // to every later Planner, Writer, and Critic request.
                session.supersededAssistantMessageIDs.insert(superseded.id)
                session.studyEvents.append(
                    .init(
                        stage: session.stage,
                        action: "card_candidate_\(resolution.decision.rawValue)_excluded_from_evidence"
                    )
                )
            }
            switch resolution.decision {
            case .accepted:
                session.cardMappingConfirmed = true
                session.cardWasSetAside = false
                if session.cardConfirmedMapping?.isEmpty != false {
                    session.cardConfirmedMapping = protocolController
                        .effectiveCardRealityConnection(for: session)?.realityMapping
                }
            case .revised:
                session.cardMappingConfirmed = true
                session.cardWasSetAside = false
                session.cardConfirmedMapping = response.memoryUpdate.cardNegotiatedMeaning
                    ?? protocolController.effectiveCardRealityConnection(for: session)?.realityMapping
            case .rejected, .declined:
                session.cardMappingConfirmed = false
                session.cardConfirmedMapping = nil
                session.cardWasSetAside = true
                session.cardConnectionUnavailable = true
                session.cardGuidanceShared = false
                session.cardCandidateMapping = nil
                session.cardGroundingMatch = nil
                session.cardMeaningShiftResponse = nil
                session.cardMeaningShiftCompleted = false
                session.cardDerivedDeltaNarrative = nil
            case .unclear, .related, .partlyRelated, .unrelated, .uncertain:
                break
            }
        }

        let committedNextPrompt: TurnNextPrompt?
        if let proposed = response.nextPrompt {
            switch proposed.kind {
            case .confirmationRequest:
                let referenceID: String
                if proposed.target == .trackingRelationship,
                   let newlyPresentedBatchID {
                    referenceID = newlyPresentedBatchID
                } else if proposed.target == .cardRealityConnection,
                          let pending = update.pendingCardRealityConnection
                            ?? session.semanticMemory.pendingCardRealityConnection,
                          pending.isStructurallyComplete {
                    referenceID = pending.id.uuidString
                } else if proposed.target == .practice,
                          let proposal = update.practiceTransition?.proposal
                            ?? session.semanticMemory.practiceTransition?.proposal {
                    referenceID = proposal.id
                } else {
                    referenceID = UUID().uuidString
                }
                committedNextPrompt = proposed.assigningReferenceID(referenceID)
            case .none, .openQuestion:
                committedNextPrompt = proposed
            }
        } else {
            // A nil prompt is reserved for legacy sessions/plans.
            committedNextPrompt = nil
        }

        session.semanticMemory.apply(
            update,
            committedNextPrompt: committedNextPrompt
        )
        guard let assessments = update.trackingAssessments else {
            return committedNextPrompt
        }

        for assessment in assessments {
            guard let index = session.trackingCues.firstIndex(where: { $0.id == assessment.cueID }) else {
                continue
            }
            switch assessment.relevance {
            case .related:
                session.trackingCues[index].relevance = .relevant
            case .partlyRelated, .uncertain:
                session.trackingCues[index].relevance = .uncertain
            case .unrelated:
                session.trackingCues[index].relevance = .irrelevant
            }
            if let insightID = session.trackingCues[index].insight?.id,
               session.contextualLoadInference?.supportingInsightIDs.contains(insightID) == true {
                session.contextualLoadInference?.relevance = switch assessment.relevance {
                case .related: .relevant
                case .partlyRelated, .uncertain: .uncertain
                case .unrelated: .irrelevant
                }
            }
        }
        syncTrackingContext()
        for assessment in assessments where assessment.relevance == .related {
            guard let cue = session.trackingCues.first(where: { $0.id == assessment.cueID }),
                  let insightID = cue.insight?.id,
                  let interpretation = assessment.userInterpretation else { continue }
            if let index = session.context.confirmedTrackingInsights?
                .firstIndex(where: { $0.insightID == insightID }) {
                session.context.confirmedTrackingInsights?[index] = ConfirmedTrackingContext(
                    insightID: insightID,
                    observation: cue.insight?.neutralObservation ?? cue.neutralDescription,
                    userInterpretation: interpretation,
                    relevance: .relevant
                )
            }
        }
        return committedNextPrompt
    }

    private func trackingObservationForDialogue(_ cue: TrackingCue) -> String {
        if let inference = session.contextualLoadInference,
           inference.hasDialogueCue,
           let insightID = cue.insight?.id,
           inference.supportingInsightIDs.contains(insightID),
           let hypothesis = inference.dialogueHypothesis {
            return hypothesis
        }
        return cue.neutralDescription.isEmpty
            ? (cue.insight?.neutralObservation ?? cue.observation)
            : cue.neutralDescription
    }

    /// Current card sessions keep context silent through disclosure, Tender, consent, image
    /// observation, and the person's first image-to-life mapping. A single measurement-free cue
    /// becomes available only for the post-mapping candidate reading. Presentation changes its
    /// local state to `offered`, never `relevant`; only a later user-authored relationship can
    /// authorize it for the final narrative.
    private func protocolContextualLoadCue() -> DialogueContextCue? {
        guard let inference = session.contextualLoadInference,
              inference.hasDialogueCue,
              let hypothesis = inference.dialogueHypothesis else {
            return nil
        }
        if session.protocolVersion < ReflectionSession.currentProtocolVersion {
            switch inference.relevance {
            case .notReviewed:
                guard session.protocolStage == .contextualDisclosure else { return nil }
            case .offered:
                return nil
            case .relevant:
                switch session.protocolStage {
                case .cardReflection:
                    guard session.condition.usesCard,
                          session.cardGuidanceShared,
                          session.semanticMemory.cardImageRelation?
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                          session.semanticMemory.cardRealityMapping?
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        return nil
                    }
                case .contextualDisclosure, .cardConsent, .complete:
                    return nil
                default:
                    break
                }
            case .uncertain, .irrelevant:
                return nil
            }
            return DialogueContextCue(
                hypothesis: userFacingContextualHypothesis(hypothesis),
                confidence: inference.confidence,
                relevance: inference.relevance,
                usageBoundary: "旧会话兼容：只能保留 hypothesis 的原始语义，不能扩展为原因、诊断、能力、情绪、免责、责任或建议。"
            )
        }
        let effectiveConnection = protocolController.effectiveCardRealityConnection(for: session)
        switch inference.relevance {
        case .notReviewed:
            guard session.protocolStage == .cardReflection,
                  session.condition.usesCard,
                  session.cardGuidanceShared,
                  effectiveConnection != nil else {
                return nil
            }
        case .offered:
            // Expose it once more only while interpreting the response to the card reading that
            // offered it. If the person does not address it, later reflection sees only the
            // stored `offered` state and must not repeat the cue.
            guard session.protocolStage == .cardReflection else {
                return nil
            }
        case .relevant:
            switch session.protocolStage {
            case .cardReflection:
                guard session.condition.usesCard,
                      session.cardGuidanceShared,
                      effectiveConnection != nil else {
                    return nil
                }
            case .contextualDisclosure, .cardConsent, .complete:
                return nil
            default:
                break
            }
        case .uncertain, .irrelevant:
            return nil
        }
        let groundedHypothesis = session.semanticMemory.contextRelationship?.userInterpretation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DialogueContextCue(
            hypothesis: groundedHypothesis?.isEmpty == false
                ? groundedHypothesis!
                : userFacingContextualHypothesis(hypothesis),
            confidence: inference.confidence,
            relevance: inference.relevance,
            usageBoundary: "只有在用户已经建立 confirmed cardRealityConnection 后，才可将这条线索暂定地并置一次。它不能建立或替代图像—现实连接，也不是原因、诊断、能力、情绪、免责、责任或行动证据；不得展示数据来源。没有用户回应时保持 offered，只有 contextRelationship 中 related/partlyRelated 且带有用户解释的关系可进入最终叙事。"
        )
    }

    /// Converts only an explicit typed relationship into later context availability. Merely
    /// mentioning a contextual fact, or accepting a broad summary, never marks it relevant.
    private func applyCurrentContextRelationship(
        from update: TurnSemanticMemoryUpdate
    ) {
        guard session.protocolVersion >= ReflectionSession.structuredTurnProtocolVersion,
              let relationship = update.contextRelationship,
              session.contextualLoadInference?.hasDialogueCue == true else {
            return
        }
        switch relationship.relevance {
        case .related, .partlyRelated:
            session.contextualLoadInference?.relevance = .relevant
        case .unrelated:
            session.contextualLoadInference?.relevance = .irrelevant
        case .uncertain:
            session.contextualLoadInference?.relevance = .uncertain
        }
        session.studyEvents.append(
            .init(
                stage: session.stage,
                action: "context_relationship_\(relationship.relevance.rawValue)_recorded"
            )
        )
    }

    private func trackingRelevance(
        for decision: TurnConfirmationDecision
    ) -> TurnTrackingRelevance {
        switch decision {
        case .related:
            return .related
        case .partlyRelated:
            return .partlyRelated
        case .unrelated:
            return .unrelated
        case .uncertain, .unclear, .accepted, .revised, .rejected, .declined:
            return .uncertain
        }
    }

    private func setProtocolStage(_ stage: ReflectionProtocolStage, action: String) {
        let previousProtocolStage = session.protocolStage
        session.protocolStage = stage
        switch stage {
        case .contextualDisclosure:
            session.stage = .eventDisclosure
            session.workflowPhase = .structuredDisclosure
        case .cardConsent:
            session.stage = session.card == nil ? .readinessCheck : .cardIntroduction
            session.workflowPhase = session.card == nil ? .contextConfirmation : .cardDisplay
        case .cardReflection:
            session.stage = .cardInterpretation
            session.workflowPhase = .cardObservation
        case .directReflection:
            if previousProtocolStage == .cardReflection {
                session.cardWasSetAside = true
            }
            session.stage = .attributionReflection
            session.workflowPhase = .candidCircumstances
        case .narrativeConfirmation:
            session.stage = .attributionReflection
            session.workflowPhase = .reflectionNarrativeConfirmation
        case .optionalAction:
            session.stage = .attributionReflection
            session.workflowPhase = .optionalAction
        case .complete:
            session.stage = .completed
            session.workflowPhase = .complete
        case .safetySupport:
            session.stage = .safetySupport
            session.workflowPhase = .safetySupport
        }
        session.dialogueProgress.currentState = session.stage
        session.studyEvents.append(.init(stage: session.stage, action: action))
    }

    @discardableResult
    private func appendProtocolAssistant(_ text: String) -> UUID? {
        guard responseContextIsCurrent() else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let userMessageID = ReflectionResponseContext.userMessageID
        guard !hasAssistantReply(to: userMessageID) else {
            session.studyEvents.append(
                .init(stage: session.stage, action: "duplicate_user_turn_reply_suppressed")
            )
            return nil
        }
        let messageID = UUID()
        session.messages.append(
            .init(
                id: messageID,
                role: .assistant,
                content: clean,
                state: session.stage,
                replyToMessageID: userMessageID,
                assistantGenerationID: ReflectionResponseContext.generationID
            )
        )
        streamRevision += 1
        return messageID
    }

    private func presentRecoverableProtocolPause(
        error: Error,
        action: String,
        retry route: ProtocolRetryRoute
    ) {
        session.studyEvents.append(.init(stage: session.stage, action: action))
        appendProtocolFailureDiagnostic(
            error,
            prefix: "\(action)_final_failure"
        )
        let recoveryMessageID = appendProtocolAssistant(
            "我已经记下你刚才的回答，当前进度也保留着。这里暂时没有顺利接上；你可以点“重试”从这里继续，不需要重新回答。"
        )
        let userMessageID = ReflectionResponseContext.userMessageID
        switch route {
        case .planner(let correction, let permissions):
            retryTarget = .protocolPlanner(
                correction: correction,
                permissions: permissions,
                recoveryMessageID: recoveryMessageID,
                userMessageID: userMessageID
            )
        case .writer(let request, let originalPlan, let validatedPlan):
            retryTarget = .protocolWriter(
                request: request,
                originalPlan: originalPlan,
                validatedPlan: validatedPlan,
                recoveryMessageID: recoveryMessageID,
                userMessageID: userMessageID
            )
        case .commit(
            let response,
            let appendVisibleReply,
            let continuation
        ):
            retryTarget = .protocolCommit(
                response: response,
                appendVisibleReply: appendVisibleReply,
                continuation: continuation,
                recoveryMessageID: recoveryMessageID,
                userMessageID: userMessageID
            )
        }
        canRetry = true
        scheduleCloudSync(action: action, delay: .zero)
    }

    private func removeProtocolRecoveryMessage(_ messageID: UUID?) {
        guard let messageID else { return }
        let previousCount = session.messages.count
        session.messages.removeAll { $0.id == messageID }
        if session.messages.count != previousCount {
            streamRevision += 1
            session.studyEvents.append(
                .init(stage: session.stage, action: "protocol_recovery_message_removed_for_retry")
            )
        }
    }

    private func protocolRepairPermissions(
        for error: Error
    ) -> ReflectionProtocolPermissions {
        let base = protocolController.permissions(for: session)
        func narrowed(
            stages: [ReflectionProtocolStage],
            actions: [TurnLocalActionKind],
            intents: [TurnReplyIntent],
            disclosurePurposes: [TurnDisclosureQuestionPurpose]? = nil,
            disclosureTargets: [TurnDisclosureQuestionTarget]? = nil
        ) -> ReflectionProtocolPermissions {
            ReflectionProtocolPermissions(
                currentStage: base.currentStage,
                allowedStages: stages,
                allowedActions: actions,
                allowedReplyIntents: intents,
                allowedDisclosurePurposes:
                    disclosurePurposes ?? base.allowedDisclosurePurposes,
                allowedDisclosureTargets:
                    disclosureTargets ?? base.allowedDisclosureTargets,
                allowedOperations: base.allowedOperations.filter {
                    stages.contains($0.requestedStage)
                        && actions.contains($0.localAction)
                        && intents.contains($0.replyIntent)
                }
            )
        }
        guard let violation = error as? ReflectionProtocolViolation else {
            return base
        }

        if session.protocolStage == .cardReflection,
           !session.cardGuidanceShared {
            let repairsConnectionBoundary: Bool
            switch violation {
            case .connectionSourceWithoutContent,
                 .incompleteCardRealityConnection,
                 .shareGuidanceWithoutConfirmedConnection,
                 .legacyCardConnectionPatchNotAllowed:
                repairsConnectionBoundary = true
            default:
                repairsConnectionBoundary = false
            }
            if repairsConnectionBoundary {
                // Recovery can ask one smaller in-scope connection question or set the card aside.
                // A complete connection patch is promoted to the silent guidance successor even
                // though that dependent action is deliberately absent from these initial repair
                // permissions.
                return narrowed(
                    stages: base.allowedStages.filter {
                        [.cardReflection, .directReflection, .safetySupport].contains($0)
                    },
                    actions: [.none],
                    intents: base.allowedReplyIntents.filter {
                        [
                            .developCardImage, .inviteCardConnection,
                            .directCandidReflection, .safetySupport,
                        ].contains($0)
                    }
                )
            }
            if violation == .invalidPreGuidanceConnectionConfirmation {
                return narrowed(
                    stages: base.allowedStages.filter {
                        [.cardReflection, .directReflection, .safetySupport].contains($0)
                    },
                    actions: [.none],
                    intents: base.allowedReplyIntents.filter {
                        [.inviteCardConnection, .directCandidReflection, .safetySupport]
                            .contains($0)
                    }
                )
            }
            let attemptedReadingBeforeAuthorization: Bool
            switch violation {
            case .illegalReplyIntent, .illegalLocalAction, .invalidNextPrompt,
                 .missingRequiredMemoryField(.cardNegotiatedMeaning):
                attemptedReadingBeforeAuthorization = true
            default:
                attemptedReadingBeforeAuthorization = false
            }
            if attemptedReadingBeforeAuthorization {
                // A rejected premature reading must not be retried under the same permissions.
                // Remove only that impossible operation. Existing image-development,
                // connection, set-aside, and safety paths remain available when the latest answer
                // did not actually contain a usable mapping.
                return narrowed(
                    stages: base.allowedStages,
                    actions: base.allowedActions,
                    intents: base.allowedReplyIntents.filter { $0 != .presentCardReading }
                )
            }
        }

        guard session.protocolStage == .contextualDisclosure else { return base }

        if case .repeatedQuestionPurpose(let purpose, let target) = violation {
            return narrowed(
                stages: base.allowedStages,
                actions: base.allowedActions,
                intents: base.allowedReplyIntents,
                disclosurePurposes: base.allowedDisclosurePurposes.filter { $0 != purpose },
                disclosureTargets: base.allowedDisclosureTargets.filter { $0 != target }
            )
        }

        let mustContinueDisclosure: Bool
        switch violation {
        case .incompleteEpisodeStructure:
            mustContinueDisclosure = true
        case .missingRequiredMemoryField(let field):
            if session.protocolVersion >= ReflectionSession.currentProtocolVersion {
                mustContinueDisclosure = field == .episodeStructure
            } else {
                mustContinueDisclosure = [
                    .selfCriticismStatus,
                    .selfCriticalStatement,
                    .selfCriticismLink,
                    .episodeStructure,
                    .contextRelationship,
                ].contains(field)
            }
        default:
            mustContinueDisclosure = false
        }
        if mustContinueDisclosure {
            return narrowed(
                stages: base.allowedStages.filter {
                    [.contextualDisclosure, .safetySupport].contains($0)
                },
                actions: [.none],
                intents: base.allowedReplyIntents.filter {
                    [.exploreContext, .safetySupport].contains($0)
                }
            )
        }

        if case .invalidDisclosureQuestionTarget = violation {
            // Re-evaluate the one canonical disclosure state. The bounded retry may ask the one
            // remaining core relation or advance directly to card consent.
            return narrowed(
                stages: base.allowedStages.filter {
                    [.contextualDisclosure, .cardConsent, .safetySupport].contains($0)
                },
                actions: [.none],
                intents: base.allowedReplyIntents.filter {
                    [.exploreContext, .inviteCardConsent, .safetySupport].contains($0)
                }
            )
        }

        if violation == .disclosureShouldAdvance {
            return narrowed(
                stages: base.allowedStages.filter {
                    $0 == .cardConsent || $0 == .safetySupport
                },
                actions: [.none],
                intents: base.allowedReplyIntents.filter {
                    $0 == .inviteCardConsent || $0 == .safetySupport
                },
                disclosurePurposes: [],
                disclosureTargets: []
            )
        }
        return base
    }

    private func protocolMissingConditions(for error: Error) -> [String] {
        guard let violation = error as? ReflectionProtocolViolation else { return [] }
        switch violation {
        case .incompletePracticeTransition(let requirements):
            return requirements.map { "practiceTransition.\($0.rawValue)" }
        case .incompleteEpisodeStructure(let requirements):
            return requirements.map { "episodeStructure.\($0.rawValue)" }
        case .missingRequiredMemoryField(let field):
            if session.protocolStage == .cardReflection,
               !session.cardGuidanceShared,
               field == .cardNegotiatedMeaning {
                return [
                    "cardGuidanceShared requires a confirmed cardRealityConnection"
                ]
            }
            return ["semanticMemory.\(field.rawValue)"]
        case .invalidDisclosureQuestionTarget(let expected):
            return [
                "committedStatePreferredTarget=\(expected.rawValue)",
                "advanceIfCumulativePatchCompletesDisclosureGate",
            ]
        case .repeatedQuestionPurpose(let purpose, let target):
            return [
                "receivedDisclosurePurpose=\(purpose.rawValue)",
                "completedDisclosureTarget=\(target.rawValue)",
                "duplicateQuestionFunctionForbidden",
            ]
        case .disclosureShouldAdvance:
            return ["conditionBridgeRequired"]
        case .connectionSourceWithoutContent:
            return [
                "cardRealityConnection.imageRelation",
                "cardRealityConnection.realityMapping",
                "cardRealityConnection.source",
                "cardRealityConnection.status=confirmed",
            ]
        case .incompleteCardRealityConnection:
            return ["completeAtomicCardRealityConnection"]
        case .shareGuidanceWithoutConfirmedConnection:
            return ["confirmedCardRealityConnectionRequiredBeforeGuidance"]
        case .invalidPreGuidanceConnectionConfirmation:
            return ["matchingPendingCardRealityConnectionRequired"]
        case .legacyCardConnectionPatchNotAllowed:
            return ["useCanonicalCardRealityConnectionOnly"]
        case .confirmedCardConnectionIsImmutable:
            return ["preserveConfirmedCardRealityConnectionUnchanged"]
        default:
            return []
        }
    }

    private func structuredProtocolCorrection(
        for error: Error,
        permissions: ReflectionProtocolPermissions
    ) -> String {
        let originalPermissions = protocolController.permissions(for: session)
        let currentPrompt = session.semanticMemory.nextPrompt
        var references: [String: String] = [:]
        if let target = currentPrompt?.target {
            references["currentConfirmationTarget"] = target.rawValue
        }
        if let referenceID = currentPrompt?.referenceID {
            references["currentConfirmationReferenceID"] = referenceID
        }
        if let activeID = session.activeTrackingPresentationID {
            references["activeTrackingPresentationID"] = activeID
        }
        if !session.presentedTrackingCueIDs.isEmpty {
            references["presentedTrackingCueIDs"] =
                session.presentedTrackingCueIDs.sorted().joined(separator: ",")
        }
        if let cardID = session.card?.id {
            references["selectedLocalCardID"] = String(cardID)
        }
        if let pendingID = session.semanticMemory.pendingCardRealityConnection?.id {
            references["pendingCardRealityConnectionID"] = pendingID.uuidString
        }
        let allowedDisclosureTargets: [String]
        if let violation = error as? ReflectionProtocolViolation,
           case .invalidDisclosureQuestionTarget(let expected) = violation {
            // The retry contract must narrow the rejected choice itself, not merely describe the
            // problem while continuing to advertise every enum value as allowed.
            allowedDisclosureTargets = [expected.rawValue]
        } else {
            allowedDisclosureTargets = permissions.allowedDisclosureTargets.map(\.rawValue)
        }

        let payload = ProtocolCorrectionPayload(
            component: "planner",
            errorCode: protocolErrorCode(error),
            currentStage: session.protocolStage.rawValue,
            allowedStages: permissions.allowedStages.map(\.rawValue),
            allowedActions: permissions.allowedActions.map(\.rawValue),
            allowedReplyIntents: permissions.allowedReplyIntents.map(\.rawValue),
            missingConditions: protocolMissingConditions(for: error),
            forbiddenOperations: [
                originalPermissions.allowedStages
                    .filter { !permissions.allowedStages.contains($0) }
                    .map { "requestedStage=\($0.rawValue)" },
                originalPermissions.allowedActions
                    .filter { !permissions.allowedActions.contains($0) }
                    .map { "localAction=\($0.rawValue)" },
                originalPermissions.allowedReplyIntents
                    .filter { !permissions.allowedReplyIntents.contains($0) }
                    .map { "replyIntent=\($0.rawValue)" },
            ].flatMap { $0 },
            allowedEnumValues: [
                "nextPrompt.kind": TurnNextPromptKind.allCases.map(\.rawValue),
                "nextPrompt.disclosurePurpose":
                    permissions.allowedDisclosurePurposes.map(\.rawValue),
                "nextPrompt.disclosureTarget": allowedDisclosureTargets,
                "nextPrompt.disclosureReopenReason":
                    TurnDisclosureReopenReason.allCases.map(\.rawValue),
                "eventDisclosureOutcome": TurnEventDisclosureOutcome.allCases.map(\.rawValue),
                "confirmation.target": TurnConfirmationTarget.allCases.map(\.rawValue),
                "confirmation.decision": TurnConfirmationDecision.allCases.map(\.rawValue),
                "practiceTransition.proposal.kind": TurnPracticeKind.allCases
                    .filter { $0 != .noAction }
                    .map(\.rawValue),
                "practiceTransition.noActionReason": TurnNoActionReason.allCases.map(\.rawValue),
                "tracking.relevance": TurnTrackingRelevance.allCases.map(\.rawValue),
                "cardRealityConnection.source": TurnCardRealityMappingSource.allCases.map(\.rawValue),
                "cardRealityConnection.status": TurnCardRealityConnectionStatus.allCases.map(\.rawValue),
                "cardConnectionOutcome": TurnCardConnectionOutcome.allCases.map(\.rawValue),
            ],
            validReferences: references,
            mustPreserve: [
                "latest user message and its answer to the visible prompt",
                "current semanticMemory",
                "current pending confirmation and opaque reference",
                "already completed user confirmations",
                "experiment condition and locally selected card",
            ],
            instruction: protocolCorrectionDescription(error)
        )
        guard let data = try? JSONEncoder().encode(payload),
              let value = String(data: data, encoding: .utf8) else {
            return protocolCorrectionDescription(error)
        }
        return value
    }

    private func structuredWriterCorrection(
        for error: Error,
        preserving plan: LLMTurnResponsePlan
    ) -> String {
        let payload = ProtocolCorrectionPayload(
            component: "writer",
            errorCode: protocolErrorCode(error),
            currentStage: session.protocolStage.rawValue,
            allowedStages: [plan.requestedStage.rawValue],
            allowedActions: [plan.localAction.kind.rawValue],
            allowedReplyIntents: [plan.replyIntent.rawValue],
            missingConditions: [],
            forbiddenOperations: [],
            allowedEnumValues: [:],
            validReferences: [:],
            mustPreserve: [
                "validated requestedStage=\(plan.requestedStage.rawValue)",
                "validated localAction=\(plan.localAction.kind.rawValue)",
                "validated replyIntent=\(plan.replyIntent.rawValue)",
                "validated memoryUpdate, resolvedConfirmation, and nextPrompt",
                "the semantic purpose in replyGuidance",
            ],
            instruction: """
            Regenerate only the user-visible Chinese wording. Do not re-plan, change the stage, \
            alter memory, add a local action, or introduce a later-stage function.
            """
        )
        guard let data = try? JSONEncoder().encode(payload),
              let value = String(data: data, encoding: .utf8) else {
            return "Writer-only regeneration. Preserve the validated plan and regenerate only the user-visible Chinese wording."
        }
        return value
    }

    private func protocolErrorCode(_ error: Error) -> String {
        if error is ProtocolCommitFailure {
            return "persistence_commit_failed"
        }
        if let clientError = error as? LLMTurnControllerClientError {
            switch clientError {
            case .plannerDecoding(let diagnostic):
                return "planner_decode_\(diagnostic.kind)_at_\(diagnostic.keyPath)"
            }
        }
        if let violation = error as? ReflectionProtocolViolation {
            switch violation {
            case .emptyReply: return "empty_reply"
            case .illegalStageTransition: return "illegal_stage_transition"
            case .illegalLocalAction: return "illegal_local_action"
            case .illegalReplyIntent: return "illegal_reply_intent"
            case .missingRequiredMemoryField(let field):
                return "missing_required_memory_\(field.rawValue)"
            case .incompleteEpisodeStructure(let requirements):
                return "incomplete_episode_structure_\(requirements.map(\.rawValue).joined(separator: "_"))"
            case .incompletePracticeTransition(let requirements):
                return "incomplete_practice_transition_\(requirements.map(\.rawValue).joined(separator: "_"))"
            case .writerIntentMismatch: return "writer_intent_mismatch"
            case .unknownTrackingCue: return "unknown_tracking_cue"
            case .duplicateTrackingCue: return "duplicate_tracking_cue"
            case .trackingReviewRequired: return "tracking_review_required"
            case .conflictingMemoryPatch: return "conflicting_memory_patch"
            case .invalidNextPrompt: return "invalid_next_prompt"
            case .repeatedQuestionPurpose: return "resolved_relation_reopened"
            case .invalidDisclosureQuestionTarget(let expected):
                return "invalid_disclosure_question_target_expected_\(expected.rawValue)"
            case .disclosureShouldAdvance: return "disclosure_should_advance"
            case .invalidConfirmationResolution: return "invalid_confirmation_resolution"
            case .unknownConfirmationReference: return "unknown_confirmation_reference"
            case .invalidCardReferenceSelection: return "invalid_card_reference_selection"
            case .connectionSourceWithoutContent:
                return "connection_source_without_content"
            case .incompleteCardRealityConnection:
                return "incomplete_card_reality_connection"
            case .shareGuidanceWithoutConfirmedConnection:
                return "share_guidance_without_confirmed_connection"
            case .invalidPreGuidanceConnectionConfirmation:
                return "invalid_pre_guidance_connection_confirmation"
            case .legacyCardConnectionPatchNotAllowed:
                return "legacy_card_connection_patch_not_allowed"
            case .confirmedCardConnectionIsImmutable:
                return "confirmed_card_connection_is_immutable"
            }
        }
        return "provider_or_unclassified_generation_failure"
    }

    private func protocolCorrectionDescription(_ error: Error) -> String {
        let currentTarget = session.semanticMemory.nextPrompt?.target
        if let clientError = error as? LLMTurnControllerClientError {
            switch clientError {
            case .plannerDecoding(let diagnostic):
                if session.protocolStage == .cardReflection,
                   currentTarget == .cardMapping,
                   session.semanticMemory.cardNegotiatedMeaning?.isEmpty == false {
                    return """
                    The prior Planner JSON for the pending cardMapping could not be decoded at \
                    \(diagnostic.keyPath). Repair the complete confirmation transaction, not only \
                    that one field. \
                    \(ReflectionPromptFactory.pendingCardMappingProtocolCorrection)
                    """
                }
                if diagnostic.invalidTrackingRelevance != nil ||
                    diagnostic.keyPath.contains("trackingAssessments") {
                    return """
                    The prior Planner JSON could not be decoded at \(diagnostic.keyPath). \
                    trackingAssessments must be null or an array of objects with cueID, relevance, \
                    and userInterpretation. relevance must be exactly related, partlyRelated, \
                    unrelated, or uncertain. Keep the current stage and use only allowed actions.
                    """
                }
                if diagnostic.invalidReplyIntent != nil ||
                    diagnostic.keyPath.hasSuffix("replyIntent") {
                    return """
                    The prior Planner replyIntent was not one of allowedReplyIntents. Use one exact \
                    enum from CURRENT PERMISSIONS and put natural-language details in \
                    replyGuidance.
                    """
                }
                if diagnostic.invalidConfirmationTarget != nil ||
                    diagnostic.keyPath.hasSuffix("target") {
                    return """
                    A confirmation target must be exactly trackingRelationship, cardConsent, \
                    cardRealityConnection, cardMapping, finalNarrative, or practice.
                    """
                }
                if diagnostic.invalidNextPromptKind != nil ||
                    diagnostic.keyPath.hasSuffix("nextPrompt.kind") {
                    if session.protocolStage == .contextualDisclosure,
                       diagnostic.invalidNextPromptKind == "inviteCardConsent" {
                        return """
                        inviteCardConsent is a replyIntent, never a nextPrompt.kind. If the episode \
                        evidence gate is complete, return replyIntent=inviteCardConsent, \
                        requestedStage=cardConsent, localAction.kind=none, and \
                        nextPrompt.kind=confirmationRequest with \
                        target=cardConsent. Otherwise remain in contextualDisclosure with exactly \
                        one openQuestion. Do not write or offer a card/exercise inside exploreContext.
                        """
                    }
                    return """
                    nextPrompt.kind must be exactly none, openQuestion, or confirmationRequest, \
                    with only the fields allowed by that tagged shape.
                    """
                }
                if diagnostic.invalidConfirmationDecision != nil ||
                    diagnostic.keyPath.hasSuffix("resolvedConfirmation.decision") {
                    return """
                    resolvedConfirmation.decision must use one exact decision enum allowed for its \
                    target. Do not translate or invent the value.
                    """
                }
                if diagnostic.invalidPracticeProposalKind != nil ||
                    diagnostic.keyPath.hasSuffix("practiceTransition.proposal.kind") {
                    return """
                    practiceTransition.proposal.kind must be exactly care, repair, protect, or \
                    change. Keep the current stage and do not translate or invent this enum.
                    """
                }
                if diagnostic.invalidNoActionReason != nil ||
                    diagnostic.keyPath.hasSuffix("noActionReason") {
                    return """
                    practiceTransition.noActionReason must be null when a proposal exists. For a \
                    noAction transition use exactly userDeclined, userNotReady, or \
                    insufficientSupportedMaterial, and only when the conversation supports it.
                    """
                }
                return """
                The prior Planner JSON could not be decoded at \(diagnostic.keyPath). Return the \
                exact Planner contract, keep the current stage, and use only allowed actions.
                """
            }
        }
        if let violation = error as? ReflectionProtocolViolation {
            if session.protocolStage == .cardReflection,
               !session.cardGuidanceShared {
                switch violation {
                case .illegalReplyIntent, .illegalLocalAction, .invalidNextPrompt,
                     .missingRequiredMemoryField(.cardNegotiatedMeaning):
                    return """
                    A candidate card reading is not authorized yet, so do not use \
                    presentCardReading and do not create cardNegotiatedMeaning or a cardMapping \
                    confirmation. Re-read the latest user answer in relation to the visible card \
                    connection question. If the person supplied an image-to-life relationship, \
                    return one complete memoryUpdate.cardRealityConnection with non-empty \
                    imageRelation and realityMapping, the supported source, and status=confirmed, \
                    without adding a hidden cause or fixed card meaning. Do not request \
                    authorizeCardGuidance or shareCardGuidance; Swift derives that silent successor. \
                    If the latest answer does not \
                    supply a usable relationship, do not invent one; use only another operation \
                    still listed in the narrowed permissions, including setting the card aside \
                    when appropriate.
                    """
                default:
                    break
                }
            }

            if session.protocolStage == .cardReflection,
               currentTarget == .cardMapping,
               session.semanticMemory.cardNegotiatedMeaning?.isEmpty == false {
                switch violation {
                case .illegalReplyIntent,
                     .invalidNextPrompt,
                     .invalidConfirmationResolution,
                     .missingRequiredMemoryField(.cardNegotiatedMeaning):
                    return ReflectionPromptFactory.pendingCardMappingProtocolCorrection
                default:
                    break
                }
            }

            switch violation {
            case .incompletePracticeTransition(let requirements):
                let fields = requirements.map(\.rawValue).joined(separator: ", ")
                return """
                Repair only the complete Optional Action transition. The invalid transaction is \
                missing or conflicts on: \(fields). Preserve the accepted finalNarrative \
                resolution. Return requestedStage=optionalAction, replyIntent=suggestPractice or \
                revisePractice as appropriate, exactly one complete grounded practiceTransition, \
                and a confirmationRequest nextPrompt targeting that proposal's id. For an active \
                proposal its id, kind, content, and basis must be non-empty, its status must be \
                pendingConfirmation, and its source must be assistantProposed or userRevised. Do \
                not return narrativeConfirmation, an openQuestion, or nextPrompt=none.
                """
            case .emptyReply:
                return "The prior reply was empty. Keep the current stage and regenerate one reply."
            case .illegalStageTransition:
                return "The prior requestedStage was not allowed. Use CURRENT PERMISSIONS exactly."
            case .illegalLocalAction:
                return "The prior local action was not allowed in the current stage."
            case .illegalReplyIntent:
                if currentTarget == .trackingRelationship {
                    return """
                    The latest user reply is answering the pending trackingRelationship check. \
                    Put the overall decision in resolvedConfirmation using the exact current target \
                    and referenceID. Add cue-level trackingAssessments only when the person's words \
                    distinguish those cues. If more understanding is needed, use \
                    checkTrackingRelationship and create an openQuestion nextPrompt. Do not create \
                    a second confirmation object or infer a later-stage transition from tracking.
                    """
                }
                if session.protocolStage == .optionalAction,
                   session.semanticMemory.nextPrompt?.target == .practice {
                    return """
                    The latest reply is handling the one pending practice proposal. Acceptance or \
                    revision must update that canonical proposal to status=confirmed, preserve its \
                    id for acceptance or use source=userRevised for a revision, resolve the current \
                    practice reference, and finish with requestedStage=complete, \
                    replyIntent=completeConversation, localAction=completeSession, and \
                    nextPrompt=none. Rejection uses one canonical noAction transition. If the \
                    person remains unclear, stay in optionalAction with one replacement \
                    pendingConfirmation proposal.
                    """
                }
                if session.protocolStage == .narrativeConfirmation {
                    return """
                    Return one complete canonical practiceTransition. For an active offer, its one \
                    proposal must contain id, kind, content, basis, pendingConfirmation status, \
                    and assistantProposed source, and nextPrompt must confirm the same proposal id. \
                    For noAction use proposal=null and one supported typed noActionReason.
                    """
                }
                if session.protocolStage == .cardReflection,
                   session.cardGuidanceShared,
                   protocolController.effectiveCardRealityConnection(for: session) != nil,
                   session.semanticMemory.cardNegotiatedMeaning?.isEmpty != false {
                    return """
                    The user-grounded image-to-reality relation is already authorized. Stay in \
                    cardReflection and use presentCardReading now. Store the \
                    substantive, tentative reading in cardNegotiatedMeaning and create a \
                    cardMapping confirmationRequest. Do not skip to final narrative or emit only \
                    an acknowledgement.
                    """
                }
                if session.protocolStage == .cardReflection,
                   session.semanticMemory.nextPrompt?.target == .cardMapping {
                    return """
                    Resolve the exact pending cardMapping reference, move to directReflection, and \
                    use directCandidReflection with one reality-based openQuestion. Do not repeat \
                    the card reading and do not move directly to final narrative.
                    """
                }
                return """
                The prior replyIntent was not allowed for the current stage, requestedStage, or \
                local action. Choose one exact enum from allowedReplyIntents and obey the CURRENT \
                STAGE CONTRACT. Do not move practice or completion content into an earlier stage.
                """
            case .missingRequiredMemoryField(let field):
                switch field {
                case .situationUnderstanding:
                    if session.protocolStage == .contextualDisclosure {
                        return """
                        The attempted condition bridge omitted a compact real-world \
                        situationUnderstanding. Recompose it only from the confirmed event, \
                        behavior or omission, impact, supplied contributor or constraint, and any \
                        explicit uncertainty already present in the dialogue. In the same plan, \
                        preserve the complete episodeStructure and any supported optional Tender memory, \
                        then use the permitted condition bridge. Do not ask another question and \
                        do not visibly offer a card or exercise through exploreContext.
                        """
                    }
                    return """
                    A user correction to the pending card reading must replace the compact real-world \
                    situationUnderstanding in the same confirmation-only transaction. Use the \
                    person's latest correction, not the rejected candidate, and preserve an unknown \
                    cause as unknown.
                    """
                case .selfCriticismStatus:
                    return """
                    Before leaving contextualDisclosure, classify only what the person actually \
                    expressed as present, absent, or uncertain. Do not infer self-criticism from \
                    other experiences, events, or outcomes. If it remains unresolved, stay \
                    in contextualDisclosure and ask one natural question about what they began \
                    saying to themselves.
                    """
                case .selfCriticalStatement:
                    return """
                    A present selfCriticismStatus requires a compact selfCriticalStatement grounded \
                    in the person's own self-evaluation. Store that proposition without making it \
                    harsher. If the person did not express one, use absent or uncertain instead.
                    """
                case .selfCriticismLink:
                    return """
                    Before using the condition bridge, store selfCriticismLink as the compact, \
                    user-grounded relationship between reported reality and the self-evaluation. \
                    Preserve whether the evaluation is the person's own conclusion, an anticipated \
                    judgment from others, both, or still uncertain, and whether it stays with one \
                    event/action or expands to broader ability, character, or worth. A negative \
                    event label alone is not this link, and another person's observable reaction \
                    does not establish their judgment or the user's internal state. Do not invent \
                    a standard, motive, cause, or hidden belief. If the scope is not available, \
                    stay in contextualDisclosure and ask one easy, situation-responsive \
                    distinction that allows 'only this event/no broader meaning'; do not reopen a \
                    generic event checklist.
                    """
                case .episodeStructure:
                    return """
                    Stay in contextualDisclosure unless the cumulative episodeStructure records \
                    concrete user-supplied facts, a resolved behavior-evidence status, and a \
                    resolved eventProcessStatus. A definite cause is not required: present or \
                    mixed needs a user-grounded process/contributor/constraint/controllable part; \
                    uncertain preserves the person's explicit inability or refusal to know; absent \
                    requires a user-grounded account that no additional process is available. Ask \
                    one concrete process question only while this status is unresolved. Recompose \
                    the compact structure from the dialogue; do not ask a checklist or invent a \
                    cause. If this is a revised or \
                    rejected cardMapping, replace the structure from the user's latest correction \
                    and exclude the superseded candidate.
                    """
                case .contextRelationship:
                    return """
                    The optional contextual background has not yet been grounded by the person. \
                    Stay in contextualDisclosure and ask one everyday, non-causal question about \
                    whether and how it participated in the concrete situation. Store related or \
                    partlyRelated only with their specific interpretation; unrelated and uncertain \
                    are complete answers.
                    """
                case .cardNegotiatedMeaning:
                    return """
                    The prior presentCardReading plan omitted \
                    memoryUpdate.cardNegotiatedMeaning. Set it to the concise candidate reading \
                    that this visible reply will ask the person to accept, revise, or reject. It \
                    is provisional while cardMapping is pending and becomes confirmed material \
                    only after the person's later accepted or revised response. Keep \
                    nextPrompt as a cardMapping confirmationRequest and do not ask another image \
                    or life-connection question.
                    """
                case .cardInterpretiveTension:
                    return """
                    Card guidance requires one user-authored or user-confirmed standard, tension, \
                    contrast, partial-progress judgment, or uncertainty beyond surface similarity. \
                    If the latest mapping already supplies it, store cardInterpretiveTension and \
                    authorize guidance. Otherwise use the one permitted deepenCardConnection \
                    question; never invent catalogue meaning.
                    """
                case .cardRealityMappingSource:
                    return """
                    A non-empty cardRealityMapping requires provenance from the latest response. \
                    Use userAuthored, userAccepted, or userRevised; do not store a system candidate \
                    as the person's fact.
                    """
                case .candidUnderstanding, .fierceUnderstanding:
                    return """
                    The latest user message answered, corrected, rejected, or left uncertain the \
                    pending candid question. Preserve the same semantic decision and return a \
                    non-empty memoryUpdate.candidUnderstanding that reflects that newest answer, \
                    including refusal, no change, or uncertainty when that is what the person said. \
                    Do not keep an older interpretation and do not ask the completed question again.
                    """
                case .finalNarrative:
                    return ReflectionPromptFactory.finalNarrativeObjectProtocolCorrection
                }
            case .incompleteEpisodeStructure(let requirements):
                let names = requirements.map(\.rawValue).joined(separator: ", ")
                return """
                The attempted disclosure bridge is missing these typed episode conditions: \
                \(names). Obey the narrowed CURRENT PERMISSIONS. Stay in contextualDisclosure, \
                preserve every supported relation from the latest answer, and ask at most one \
                concrete, low-burden question for the single missing function that blocks \
                progress. For eventProcessStatus, a definite cause is not required: store present \
                or mixed only with a user-grounded process relation, uncertain with the person's \
                explicit uncertainty, or absent only with a user-grounded account that no \
                additional process is available. Do not invite a card or retry the rejected \
                transition in this repair turn.
                """
            case .writerIntentMismatch:
                return """
                The Writer did not echo the validated Planner replyIntent. Regenerate wording for \
                exactly that intent without adding a practice, completion, or another question \
                purpose.
                """
            case .unknownTrackingCue:
                return """
                The prior response used an invalid tracking cue ID. For trackingAssessments, copy \
                cueID exactly from presentedTrackingCues; those IDs are opaque and must not be \
                translated, shortened, replaced with a metric name, or taken from \
                trackingCandidates. Assess only cues the latest user reply actually addresses. If \
                presentedTrackingCues is empty, do not create a trackingAssessment and do not \
                claim that the tracking relationship was recorded.
                """
            case .duplicateTrackingCue:
                return "The prior response tried to present a tracking cue that was already used."
            case .trackingReviewRequired:
                return """
                Usable cleaned trackingCandidates are available, but this reflection has not yet \
                given the person a tracking opportunity. Stay in contextualDisclosure. Select the \
                smallest coherent candidate batch, use localAction presentTrackingCue with those \
                exact IDs, use replyIntent presentTrackingContext, and create a \
                trackingRelationship confirmationRequest. Present the cues only as tentative \
                background that the person may confirm, qualify, reject, or leave uncertain. Do \
                do not exhaust every candidate.
                """
            case .conflictingMemoryPatch:
                return """
                Use the current interaction contract: put what the latest user reply resolved in \
                resolvedConfirmation, and put only the interaction created by the next visible \
                reply in nextPrompt.
                """
            case .invalidNextPrompt:
                return """
                nextPrompt must be exactly one valid tagged shape: none with all optional fields \
                null; openQuestion with non-empty purpose and focus and, during current contextual \
                disclosure, exactly one allowed disclosurePurpose and its matching disclosureTarget; \
                or confirmationRequest with target only. A reopenReason is allowed only for an \
                actual correction, withdrawal, or new contradiction. Swift assigns the referenceID \
                after the visible reply succeeds.
                """
            case .repeatedQuestionPurpose:
                return """
                The proposed openQuestion repeats a completed semantic function. Do not rename or \
                paraphrase that function. Preserve the answer already in semanticMemory and either \
                ask one materially different unresolved typed purpose still exposed in CURRENT \
                PERMISSIONS or use inviteCardConsent when eventDisclosureOutcome is \
                readyForTenderOrCard. The rejected purpose and target are no longer permitted.
                """
            case .invalidDisclosureQuestionTarget(let expected):
                return """
                The proposed disclosure question targets a relationship that is already resolved \
                or skips the one current prerequisite. Rebuild from committed semanticMemory, not \
                from the rejected patch. Preserve every resolved relation and include only fields \
                newly supported or explicitly corrected by the latest answer; never clear stored \
                evidence with an empty array while its status remains present or mixed. Apply the \
                new patch before choosing the operation. If the cumulative gate remains incomplete, \
                ask one natural, low-burden question for its first unresolved relation (currently \
                \(expected.rawValue)). If the patch completes the gate, use the permitted direct \
                grounding plus inviteCardConsent transition instead and ask no further disclosure \
                question.
                """
            case .disclosureShouldAdvance:
                return """
                The cumulative disclosure evidence gate is complete and the reality account is \
                already established. Do not ask another analytic question or retell its event \
                chain. Preserve any volunteered concern. Add a behavior-versus-whole-person \
                distinction only when the user's own words explicitly contain that whole-person \
                judgment. Otherwise use one brief factual transition in the visible \
                inviteCardConsent reply. Create only the cardConsent confirmation; do not create \
                a Tender confirmation or another disclosure question.
                """
            case .invalidConfirmationResolution:
                return """
                resolvedConfirmation may describe only the confirmationRequest that was visible \
                before this user turn. Copy its exact target and allowed decision; do not use it \
                for an ordinary open question and do not treat a new confirmation as already \
                resolved.
                """
            case .unknownConfirmationReference:
                return """
                resolvedConfirmation.referenceID must copy the exact opaque reference from the \
                current confirmation request. For trackingRelationship it must identify the \
                active tracking presentation batch.
                """
            case .invalidCardReferenceSelection:
                return """
                cardReferenceSelection must be null unless the current request supplies \
                card.referenceGuidance after a confirmed image-to-reality mapping. For one \
                permitted content-forward question, select at most one zero-based relationIndex \
                from that current-card array. Do not return relation text, use another card's \
                reference, copy the relation into memory, or use it in a summary or action turn. \
                Swift checks only this structure, source, and permission; semantic support remains \
                for the plan Critic.
                """
            case .connectionSourceWithoutContent:
                return """
                Do not persist or repair a source by itself. Re-read the latest user answer and the \
                current card observation. If that material supports a connection, return one atomic \
                cardRealityConnection containing non-empty imageRelation and realityMapping, its \
                userAuthored/userAccepted/userRevised source, and status=confirmed. Do not request \
                shareCardGuidance; Swift derives that silent successor after the complete patch. If \
                the material is insufficient, ask one smaller question inside the current focal \
                event or use the legal skip path.
                """
            case .incompleteCardRealityConnection:
                return """
                The prior connection patch was incomplete and was not persisted. Submit either one \
                complete atomic cardRealityConnection or no connection object. Never split relation, \
                mapping, source, or confirmed status across turns. A complete patch is committed \
                silently and Swift opens the one guidance successor; otherwise keep guidance closed \
                and use one permitted in-scope clarification or skip operation.
                """
            case .shareGuidanceWithoutConfirmedConnection:
                return """
                shareCardGuidance depends on a complete confirmed cardRealityConnection and is not \
                currently permitted. Do not repeat authorizeCardGuidance or shareCardGuidance. First \
                return the complete typed connection supported by the latest answer, or ask one \
                smaller current-event connection question when the material is insufficient. Swift \
                alone derives the dependent silent guidance action after a valid connection exists.
                """
            case .invalidPreGuidanceConnectionConfirmation:
                return """
                The returned cardRealityConnection resolution does not match a real pending \
                pre-guidance candidate and was ignored. Do not invent a pending object or reuse the \
                post-guidance cardMapping target. Re-plan from the current canonical connection: \
                submit a complete user-authored connection if the latest answer contains one, ask one \
                legal current-event connection question, or use the legal skip path.
                """
            case .legacyCardConnectionPatchNotAllowed:
                return """
                The current Planner patch used retired cardImageRelation, cardRealityMapping, or \
                cardRealityMappingSource fields. Do not return any of those keys in a current \
                patch. If the pre-guidance evidence supports a connection, return one complete \
                canonical cardRealityConnection; otherwise use one permitted current-event \
                clarification or skip operation. Do not request shareCardGuidance directly.
                """
            case .confirmedCardConnectionIsImmutable:
                return """
                The confirmed cardRealityConnection has already been used for post-guidance \
                reflection and is immutable. Preserve the confirmed cardRealityConnection \
                unchanged. Do not return, clear, revise, or reopen cardRealityConnection or \
                pendingCardRealityConnection in this repair. Repair only the currently permitted \
                Card Reading or later reflection output, action, or nextPrompt.
                """
            }
        }
        return "The prior object could not be parsed or generated. Return the exact contract while keeping the current stage."
    }

    private func appendProtocolFailureDiagnostic(_ error: Error, prefix: String) {
        if let clientError = error as? LLMTurnControllerClientError {
            switch clientError {
            case .plannerDecoding(let diagnostic):
            let safePath = String(
                diagnostic.keyPath.map { character in
                    character.isASCII &&
                    (character.isLetter || character.isNumber || character == "." || character == "_")
                        ? character
                        : "_"
                }
            )
            var action = "\(prefix)_planner_decode_\(diagnostic.kind)_at_\(safePath)"
            if let invalid = diagnostic.invalidTrackingRelevance {
                action += "_invalid_tracking_relevance_\(invalid)"
            }
            if let invalid = diagnostic.invalidReplyIntent {
                action += "_invalid_reply_intent_\(invalid)"
            }
            if let invalid = diagnostic.invalidConfirmationTarget {
                action += "_invalid_confirmation_target_\(invalid)"
            }
            if let invalid = diagnostic.invalidNextPromptKind {
                action += "_invalid_next_prompt_kind_\(invalid)"
            }
            if let invalid = diagnostic.invalidConfirmationDecision {
                action += "_invalid_confirmation_decision_\(invalid)"
            }
            if let invalid = diagnostic.invalidPracticeProposalKind {
                action += "_invalid_practice_kind_\(invalid)"
            }
            if let invalid = diagnostic.invalidNoActionReason {
                action += "_invalid_no_action_reason_\(invalid)"
            }
            session.studyEvents.append(
                .init(stage: session.stage, action: String(action.prefix(220)))
            )
            }
            return
        }
        if let violation = error as? ReflectionProtocolViolation {
            let reason: String
            switch violation {
            case .emptyReply: reason = "empty_reply"
            case .illegalStageTransition: reason = "illegal_stage_transition"
            case .illegalLocalAction: reason = "illegal_local_action"
            case .illegalReplyIntent: reason = "illegal_reply_intent"
            case .missingRequiredMemoryField(let field):
                reason = "missing_required_memory_\(field.rawValue)"
            case .incompleteEpisodeStructure(let requirements):
                reason = "incomplete_episode_structure_\(requirements.map(\.rawValue).joined(separator: "_"))"
            case .incompletePracticeTransition(let requirements):
                reason = "incomplete_practice_transition_\(requirements.map(\.rawValue).joined(separator: "_"))"
            case .writerIntentMismatch: reason = "writer_intent_mismatch"
            case .unknownTrackingCue: reason = "unknown_tracking_cue"
            case .duplicateTrackingCue: reason = "duplicate_tracking_cue"
            case .trackingReviewRequired: reason = "tracking_review_required"
            case .conflictingMemoryPatch: reason = "conflicting_memory_patch"
            case .invalidNextPrompt: reason = "invalid_next_prompt"
            case .repeatedQuestionPurpose: reason = "resolved_relation_reopened"
            case .invalidDisclosureQuestionTarget(let expected):
                reason = "invalid_disclosure_question_target_expected_\(expected.rawValue)"
            case .disclosureShouldAdvance: reason = "disclosure_should_advance"
            case .invalidConfirmationResolution: reason = "invalid_confirmation_resolution"
            case .unknownConfirmationReference: reason = "unknown_confirmation_reference"
            case .invalidCardReferenceSelection: reason = "invalid_card_reference_selection"
            case .connectionSourceWithoutContent:
                reason = "connection_source_without_content"
            case .incompleteCardRealityConnection:
                reason = "incomplete_card_reality_connection"
            case .shareGuidanceWithoutConfirmedConnection:
                reason = "share_guidance_without_confirmed_connection"
            case .invalidPreGuidanceConnectionConfirmation:
                reason = "invalid_pre_guidance_connection_confirmation"
            case .legacyCardConnectionPatchNotAllowed:
                reason = "legacy_card_connection_patch_not_allowed"
            case .confirmedCardConnectionIsImmutable:
                reason = "confirmed_card_connection_is_immutable"
            }
            session.studyEvents.append(
                .init(stage: session.stage, action: "\(prefix)_\(reason)")
            )
        }
    }

    private func processDisclosure(_ text: String, state: ReflectionState) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }
        storeLiteralDisclosure(text, state: state)
        let analysis = await analyzeCurrentUserTurn(for: state)
        guard responseContextIsCurrent(expectedStage: state) else { return }
        mergeAnalysis(analysis)
        if !session.context.emotions.isEmpty {
            session.dialogueProgress.complete(.emotion)
        }
        if !session.context.bodilyResponses.isEmpty {
            session.bodyExplorationCompleted = true
            session.dialogueProgress.complete(.body)
        }
        session.latestAnalysis = analysis
        session.studyEvents.append(.init(stage: state, action: "structured_disclosure_recorded"))

        if analysis.safetyOverride { interruptForSafety(); return }
        if shouldCloseDisclosureAfterBoundaryAnswer(text) {
            closeRemainingDisclosureAsUncertain(reason: "repeated_low_information_answers")
            await beginTenderGrounding(
                action: "structured_disclosure_completed_after_user_boundary",
                managesTyping: false
            )
            return
        }
        if shouldCompleteStructuredDisclosure {
            if session.structuredDisclosureAssistantTurns >= maximumStructuredDisclosureAssistantTurns,
               !structuredDisclosureIsSufficient {
                closeRemainingDisclosureAsUncertain(reason: "structured_disclosure_reached_depth_limit")
            }
            let action = session.structuredDisclosureAssistantTurns >= maximumStructuredDisclosureAssistantTurns
                ? "structured_disclosure_completed_maximum_turns"
                : "structured_disclosure_completed_sufficient"
            await beginTenderGrounding(action: action, managesTyping: false)
            return
        }
        let modelResponsePlan = validatedResponsePlan(
            for: state,
            analysis: analysis
        )
        let responsePlan = modelResponsePlan
            ?? responsePlanValidator.recoverDisclosurePlan(
                analysis: analysis,
                state: state,
                workflowPhase: session.workflowPhase,
                messages: session.messages
            )
        let plannedNext = plannedDisclosureState(from: responsePlan)
        let writerPlan = plannedNext == nil ? nil : responsePlan
        session.studyEvents.append(
            .init(
                stage: state,
                action: writerPlan == nil
                    ? "response_plan_unavailable_emergency_disclosure_path"
                    : modelResponsePlan == nil
                        ? "response_plan_recovered_\(writerPlan!.function.rawValue)"
                        : "response_plan_validated_\(writerPlan!.function.rawValue)"
            )
        )
        let next = plannedNext
            ?? nextDepthDisclosureState()
        guard let next else { return }
        if next == .trackingPermission {
            await beginTenderGrounding(
                action: "structured_disclosure_completed_by_dimensions",
                managesTyping: false
            )
            return
        }
        transition(to: next, action: "structured_disclosure_advanced")
        if next == .selfJudgment {
            session.hasAskedPersonalMeaningQuestion = true
            session.hasAskedProgressMeaningQuestion = true
        }
        recordStructuredDisclosureAssistantTurn(action: "structured_disclosure_question_asked")
        await generateDialogue(
            state: next,
            goal: writerPlan.map(responsePlanGoal)
                ?? structuredDisclosureMissingGoal(fallbackState: next),
            authority: .userMeaning(writerPlan),
            managesTyping: false
        )
    }

    private func processConversationRepair(_ text: String, state: ReflectionState) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        if state == .tenderGrounding || state == .tenderExploration {
            guard responseContextIsCurrent(expectedStage: state) else { return }
            session.studyEvents.append(.init(stage: state, action: "conversation_repetition_flagged_by_user"))
            addAssistant(tenderConversationRepairMessage())
            return
        }

        let analysis = await analyzeCurrentUserTurn(for: state)
        guard responseContextIsCurrent(expectedStage: state) else { return }
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        session.studyEvents.append(.init(stage: state, action: "conversation_repetition_flagged_by_user"))
        if analysis.safetyOverride { interruptForSafety(); return }

        if isDisclosureState(state), hasEnoughDisclosureToStopCollecting {
            closeRemainingDisclosureAsUncertain(reason: "user_flagged_repetition")
            await beginTenderGrounding(
                action: "structured_disclosure_completed_after_conversation_repair",
                managesTyping: false,
                conversationRepair: true
            )
            return
        }

        if isDisclosureState(state) {
            recordStructuredDisclosureAssistantTurn(action: "structured_disclosure_repair_turn")
        }
        await generateDialogue(
            state: state,
            goal: "briefly acknowledge that the user is right about the repetition, stop the current line of questioning, summarize only what is already clear, and ask at most one plainly different, easy question",
            managesTyping: false
        )
    }

    private func processClarificationRequest(state: ReflectionState) async {
        defer { finishTypingForCurrentResponse() }
        guard responseContextIsCurrent(expectedStage: state) else { return }
        session.studyEvents.append(.init(stage: state, action: "abstract_question_clarified_without_advancing"))
        addAssistant(plainClarification(for: state))
    }

    private func processTrackingResponse(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        if session.workflowPhase == .trackingContextLink {
            await processTrackingContextLinkResponse(text)
            return
        }

        let pendingIDs = session.pendingTrackingCueIDs.isEmpty
            ? session.pendingTrackingCueID.map { [$0] } ?? []
            : session.pendingTrackingCueIDs
        var confirmedInsightIDs = Set<UUID>()
        for cueID in pendingIDs {
            guard let index = session.trackingCues.firstIndex(where: { $0.id == cueID }) else {
                continue
            }
            let cue = session.trackingCues[index]
            let relevance = trackingRelevance(
                for: cue,
                from: text,
                bundleCount: pendingIDs.count
            )
            session.trackingCues[index].relevance = relevance
            if relevance == .relevant, let insightID = cue.insight?.id {
                confirmedInsightIDs.insert(insightID)
            }
            session.studyEvents.append(
                .init(
                    stage: .trackingReview,
                    action: "tracking_connection_\(cue.source.rawValue)_\(relevance.rawValue)_in_dialogue"
                )
            )
        }
        if session.contextualLoadInference != nil {
            session.contextualLoadInference?.relevance = trackingRelevance(from: text)
        }
        session.pendingTrackingCueID = nil
        session.pendingTrackingCueIDs = []
        syncTrackingContext()
        let clean = normalizedTrackingContextLinkResponse(text)
        if !confirmedInsightIDs.isEmpty {
            session.context.confirmedTrackingInsights = session.context.confirmedTrackingInsights?.map { item in
                guard confirmedInsightIDs.contains(item.insightID) else { return item }
                return ConfirmedTrackingContext(
                    insightID: item.insightID,
                    observation: item.observation,
                    userInterpretation: clean,
                    relevance: .relevant
                )
            }
        }

        let analysis = await analyzeCurrentUserTurn(for: .trackingReview)
        guard responseContextIsCurrent(expectedStage: .trackingReview) else { return }
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        if analysis.safetyOverride { interruptForSafety(); return }

        session.trackingReviewCompleted = true
        session.studyEvents.append(.init(stage: .trackingReview, action: "tracking_review_completed"))
        if session.context.confirmedTrackingCues.isEmpty {
            session.trackingContextLinkCompleted = true
            session.trackingContextLinkResponse = nil
            await beginContextConfirmation(
                action: "context_confirmation_after_tracking_response",
                managesTyping: false
            )
            return
        }

        // The visible tracking turn already follows the complete sequence:
        // observable change → plausible life context → possible effect in the concrete event.
        // The person's answer is therefore both the relevance judgment and the authored event
        // link. Storing it once avoids a second, nearly identical confirmation question.
        session.trackingContextLinkResponse = clean.isEmpty ? nil : clean
        session.trackingContextLinkCompleted = true
        session.studyEvents.append(
            .init(stage: .trackingReview, action: "tracking_context_link_answered_in_review_turn")
        )
        await beginContextConfirmation(
            action: "context_confirmation_after_integrated_tracking_response",
            managesTyping: false
        )
    }

    private func processTrackingContextLinkResponse(_ text: String) async {
        let analysis = await analyzeCurrentUserTurn(for: .trackingReview)
        guard responseContextIsCurrent(expectedStage: .trackingReview) else { return }
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        if analysis.safetyOverride { interruptForSafety(); return }

        let clean = normalizedTrackingContextLinkResponse(text)
        session.trackingContextLinkResponse = clean.isEmpty ? nil : clean
        session.trackingContextLinkCompleted = true
        session.studyEvents.append(
            .init(stage: .trackingReview, action: "tracking_context_link_answered")
        )

        // This answer is the person's interpretation of relevance, not a property inferred from
        // the record. Preserve it separately so later summaries can say "you felt..." instead of
        // presenting a device-derived cause.
        session.context.confirmedTrackingInsights = session.context.confirmedTrackingInsights?.map {
            ConfirmedTrackingContext(
                insightID: $0.insightID,
                observation: $0.observation,
                userInterpretation: clean.isEmpty ? $0.userInterpretation : clean,
                relevance: $0.relevance
            )
        }

        await beginContextConfirmation(
            action: "context_confirmation_after_tracking_context_link",
            managesTyping: false
        )
    }

    /// A bare “有 / 对得上” is a valid confirmation of the event-impact question that was just
    /// asked, but it is not useful later as a literal sentence. Preserve the *specific impact
    /// the person just affirmed* in plain language, rather than making a later summary guess
    /// whether the answer referred to sleep, stress, or responsibility.
    private func normalizedTrackingContextLinkResponse(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = comparableText(clean)
        let shortAffirmations = ["有", "有的", "对", "对的", "是的", "可能有", "有一点", "有一点影响"]
            .map(comparableText)
        guard shortAffirmations.contains(normalized) else { return clean }
        return "你确认这些近期变化可能让当时的处境更难应对"
    }

    private func processTenderResponse(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }
        let currentStage = session.stage
        let analysis = await analyzeCurrentUserTurn(for: currentStage)
        guard responseContextIsCurrent(expectedStage: currentStage) else { return }
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        if analysis.safetyOverride { interruptForSafety(); return }

        if session.workflowPhase == .tenderGroundingConfirmation {
            if userExplicitlyRequestsCard(text) {
                session.studyEvents.append(
                    .init(
                        stage: currentStage,
                        action: "card_request_deferred_until_tender_confirmation"
                    )
                )
                addAssistant(
                    "可以。抽卡前，先顺着刚才的理解说下去：现在最想补充的是哪一部分？"
                )
                return
            }
            if integratedNarrativeNeedsRevision(text) {
                session.tenderGroundingRevisionCount += 1
                session.studyEvents.append(.init(stage: currentStage, action: "tender_grounding_revised"))
                await generateDialogue(
                    state: .tenderGrounding,
                    goal: "revise the short grounding using the user's correction. Separate concrete events and constraints from any global self-evaluation, preserve uncertainty, add no tracking or card, then ask one content-forward question about the user's experience",
                    managesTyping: false,
                    requiresIntegratedNarrative: true,
                    integratedNarrativeAccuracyCheck: true,
                    trackingCuesOverride: []
                )
                return
            }
            if isSubstantiveSummaryAddition(text) {
                session.tenderGroundingRevisionCount += 1
                session.studyEvents.append(.init(stage: currentStage, action: "tender_grounding_extended_by_user"))
                await generateDialogue(
                    state: .tenderGrounding,
                    goal: "the user added a concrete detail while responding to the grounding. Fold only that confirmed detail into a short revised grounding, keep the event-versus-identity distinction, and ask one content-forward question. Do not say that the user failed to confirm or explain the process",
                    managesTyping: false,
                    requiresIntegratedNarrative: true,
                    integratedNarrativeAccuracyCheck: true,
                    trackingCuesOverride: []
                )
                return
            }
            guard userAffirmsAccuracy(text) else {
                session.studyEvents.append(
                    .init(stage: currentStage, action: "tender_grounding_confirmation_unclear")
                )
                addAssistant("先不急着确认刚才的整理。沿着你自己的经历，接下来最想补充哪一部分？")
                return
            }
            session.tenderGroundingConfirmed = true
            session.studyEvents.append(.init(stage: currentStage, action: "tender_grounding_confirmed"))
            transition(to: .trackingPermission, action: "tender_grounding_completed")
            setWorkflowPhase(.trackingReview, action: "tracking_review_started")
            transition(to: .trackingReview, action: "tracking_review_opened_automatically")
            await loadTrackingReviewData()
            return
        }
        if userIsStillAnswering(text) {
            await generateDialogue(
                state: currentStage,
                goal: "the user says they are still answering; give them room to continue the same thought and do not mention a card, tracking, action, or a new topic",
                managesTyping: false
            )
            return
        }
        if currentStage == .tenderExploration {
            await generateDialogue(
                state: .tenderExploration,
                goal: "respond to the user's latest words and stay with that same thread; the user chose to keep talking or previously set a card aside, so do not invite a card, tracking, or action; ask at most one plain question only if it helps them continue",
                authority: .userMeaning(
                    validatedResponsePlan(for: currentStage, analysis: analysis)
                ),
                managesTyping: false
            )
            return
        }
        session.dialogueProgress.complete(.uncertainty)
        await beginContextConfirmation(action: "legacy_tender_completed", managesTyping: false)
    }

    private func processReadinessResponse(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }

        if userWantsToEnd(text) {
            end()
            return
        }

        guard session.workflowPhase == .contextConfirmation else {
            if userAcceptsCard(text) {
                if await restoreTrackingReviewBeforeCardRequestIfNeeded() { return }
                var analysis = session.latestAnalysis ?? .fallback()
                analysis.consentToCandor = .yes
                acceptCardInvitation(using: analysis)
            } else {
                await deferCardAndContinue()
            }
            return
        }

        let analysis = await analyzeCurrentUserTurn(for: .readinessCheck)
        guard responseContextIsCurrent(expectedStage: .readinessCheck) else { return }
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        if analysis.safetyOverride { interruptForSafety(); return }

        if session.condition.usesCard, session.contextSummaryConfirmed {
            if userAcceptsCard(text) {
                if await restoreTrackingReviewBeforeCardRequestIfNeeded() { return }
                acceptCardInvitation(using: analysis)
                return
            }
            if userDeclinesCard(text) {
                await deferCardAndContinue()
                return
            }
        }

        if integratedNarrativeNeedsRevision(text) {
            if session.contextualLoadInference?.relevance == .notReviewed {
                // A correction to the whole synthesis means the embedded contextual hypothesis
                // was not accepted as written. Remove it conservatively from the revision and
                // every later prompt instead of asking the person to adjudicate it separately.
                session.contextualLoadInference?.relevance = .uncertain
            }
            session.contextConfirmationRevisionCount += 1
            session.studyEvents.append(.init(stage: .readinessCheck, action: "context_confirmation_revised"))
            await generateDialogue(
                state: .readinessCheck,
                goal: "revise the whole short context summary using the user's correction. If the supplied measurement-free contextual hypothesis remains compatible with that correction, keep it only as one tentative clause; otherwise omit it. Mention no measurements, records, or card choice, then ask one content-forward question about the user's experience",
                managesTyping: false,
                requiresIntegratedNarrative: true,
                integratedNarrativeAccuracyCheck: true
            )
            return
        }

        if isSubstantiveSummaryAddition(text) {
            session.contextConfirmationRevisionCount += 1
            session.studyEvents.append(.init(stage: .readinessCheck, action: "context_summary_extended_by_user"))
            await generateDialogue(
                state: .readinessCheck,
                goal: "the user added a concrete detail while responding to the whole context summary. Revise it with that confirmed addition. Keep any supplied measurement-free contextual hypothesis to at most one tentative clause, mention no measurements, records, or card, then ask one content-forward question about the user's experience",
                managesTyping: false,
                requiresIntegratedNarrative: true,
                integratedNarrativeAccuracyCheck: true
            )
            return
        }

        guard userAffirmsAccuracy(text) else {
            session.studyEvents.append(
                .init(stage: .readinessCheck, action: "context_confirmation_unclear")
            )
            addAssistant("先不把这段整理当成结论。放回当时的经历，你最想继续说哪一部分？")
            return
        }

        session.contextSummaryConfirmed = true
        if session.contextualLoadInference?.hasDialogueCue == true,
           session.contextualLoadInference?.relevance == .notReviewed {
            // The person accepted the whole correctable context summary. The tracking-derived
            // clause therefore needs no separate relevance question before later use.
            session.contextualLoadInference?.relevance = .relevant
        }
        lockConfirmedBaselineNarrative()
        session.studyEvents.append(.init(stage: .readinessCheck, action: "context_confirmation_confirmed"))
        var accepted = analysis
        accepted.consentToCandor = .yes
        session.latestAnalysis = accepted
        guard session.condition.usesCard else {
            await beginDirectCandidReflection(managesTyping: false)
            return
        }
        // The context confirmation is not consent to draw. Keep the Swift-owned state at this
        // gate and wait for one explicit, ordinary user confirmation before selecting a card.
        addAssistant("这段整理先放在这里。接下来可以随机抽一张图卡，换个角度继续看；如果你想抽，直接说“抽卡”就好。")
        session.studyEvents.append(.init(stage: .readinessCheck, action: "card_draw_invitation_presented"))
    }

    private func acceptCardInvitation(using analysis: ContextAnalysis) {
        guard session.trackingReviewCompleted else {
            session.studyEvents.append(
                .init(stage: session.stage, action: "card_selection_blocked_until_tracking_review")
            )
            return
        }
        var accepted = analysis
        accepted.consentToCandor = .yes
        session.latestAnalysis = accepted
        if accepted.safetyOverride {
            interruptForSafety()
            return
        }
        session.currentRoute = .explore
        session.dialogueProgress.cardPreference = .available
        if session.workflowPhase == .contextConfirmation {
            session.contextSummaryConfirmed = true
            session.studyEvents.append(.init(stage: .readinessCheck, action: "context_confirmation_confirmed_by_card_request"))
        }
        setWorkflowPhase(.cardSelection, action: "card_selection_started")
        transition(to: .cardIntroduction, action: "readiness_confirmed_in_dialogue")
        drawCard()
    }

    /// A card is never an alternate route around tracking. This recovery path is only reachable
    /// for a legacy/resumed session that has reached the old readiness gate without a completed
    /// review; new sessions arrive here through `processTenderResponse` automatically.
    @discardableResult
    private func restoreTrackingReviewBeforeCardRequestIfNeeded() async -> Bool {
        guard session.condition.usesCard,
              !session.trackingReviewCompleted,
              session.stage == .readinessCheck,
              session.workflowPhase == .contextConfirmation else {
            return false
        }
        session.contextSummaryConfirmed = false
        session.studyEvents.append(
            .init(stage: .readinessCheck, action: "card_request_deferred_until_tracking_review")
        )
        setWorkflowPhase(.trackingReview, action: "card_path_tracking_review_restored")
        transition(to: .trackingReview, action: "card_path_returned_to_tracking_review")
        await loadTrackingReviewData(conversationRepair: true)
        return true
    }

    private func startCardImmediately(replyingTo userMessageID: UUID) {
        guard session.condition.usesCard, session.trackingReviewCompleted else { return }
        let startedAtReadiness = session.stage == .readinessCheck
        if session.stage == .tenderGrounding || session.stage == .tenderExploration {
            transition(to: .readinessCheck, action: "explicit_card_request_received")
        }
        guard session.stage == .readinessCheck else { return }

        var analysis = session.latestAnalysis ?? .fallback()
        analysis.consentToCandor = .yes
        session.latestAnalysis = analysis
        if analysis.safetyOverride {
            interruptForSafety(replyingTo: userMessageID)
            return
        }
        session.currentRoute = .explore
        session.dialogueProgress.cardPreference = .available
        if session.workflowPhase == .contextConfirmation {
            session.contextSummaryConfirmed = true
            session.studyEvents.append(.init(stage: .readinessCheck, action: "context_confirmation_confirmed_by_card_request"))
        }
        setWorkflowPhase(.cardSelection, action: "card_selection_started")
        transition(
            to: .cardIntroduction,
            action: startedAtReadiness
                ? "readiness_confirmed_in_dialogue"
                : "readiness_confirmed_by_explicit_card_request"
        )
        drawCard(replyingTo: userMessageID)
    }

    private func deferCardAndContinue() async {
        var analysis = session.latestAnalysis ?? .fallback()
        analysis.consentToCandor = .no
        session.latestAnalysis = analysis
        session.currentRoute = .tenderStabilize
        session.dialogueProgress.cardPreference = .deferred
        transition(to: .tenderExploration, action: "card_deferred_in_dialogue")
        await generateDialogue(
            state: .tenderExploration,
            goal: "respond directly to what the user just said and continue that same thread; do not mention the card again",
            authority: .userMeaning(nil),
            managesTyping: false
        )
    }

    private func processCardInterpretation(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }
        guard responseContextIsCurrent(expectedStage: .cardInterpretation) else { return }

        switch session.workflowPhase {
        case .cardObservation:
            if userCannotInterpretCard(text) || userHasNoMoreCardDescription(text) || cardDoesNotFit(text) {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_observation_unavailable",
                    managesTyping: false
                )
                return
            }
            appendCardInterpretation(text)
            session.hasAskedCardProjectionFollowUp = true
            session.studyEvents.append(
                .init(stage: .cardInterpretation, action: "card_observation_stored_verbatim")
            )
            setWorkflowPhase(.cardAssociation, action: "card_association_prompted")
            await generateDialogue(
                state: .cardInterpretation,
                goal: "help the user build one short picture narrative in their own words while staying entirely inside the image. Ask exactly one plain, open question about what may be happening next, why a user-named action may be happening, how user-named figures relate, or one uncertainty they named; choose only one. Do not connect it to real life, explain symbolism, infer psychology, or use divination language. The later reality-connection gate must wait for this answer",
                authority: .userMeaning(nil),
                managesTyping: false
            )

        case .cardAssociation:
            if cardDoesNotFit(text) {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_association_explicitly_not_connected",
                    managesTyping: false
                )
                return
            }
            if !(userCannotInterpretCard(text) || userHasNoMoreCardDescription(text)) {
                appendCardInterpretation(text)
                session.studyEvents.append(
                    .init(stage: .cardInterpretation, action: "card_association_stored_verbatim")
                )
            } else {
                session.studyEvents.append(
                    .init(stage: .cardInterpretation, action: "card_association_completed_without_more_detail")
                )
            }
            // Two user-authored image turns are the normal path. A third image-only turn made
            // card use feel scripted; it is now reserved for a single, card-specific scaffold
            // only after the first life-connection invitation is genuinely difficult.
            await inviteCardLifeConnectionAfterImageStory()

        case .cardNarrativeDeepening:
            // Resume-only compatibility for a session saved by an older build. New sessions do
            // not enter this phase, but completing it still leads safely to the same connection
            // gate rather than losing the person's existing image narrative.
            if !(userCannotInterpretCard(text) || userHasNoMoreCardDescription(text) || cardDoesNotFit(text)) {
                appendCardInterpretation(text)
                session.studyEvents.append(
                    .init(stage: .cardInterpretation, action: "card_narrative_deepening_stored_verbatim")
                )
            } else {
                session.studyEvents.append(
                    .init(stage: .cardInterpretation, action: "card_narrative_deepening_completed_without_more_detail")
                )
            }
            await inviteCardLifeConnectionAfterImageStory()

        default:
            session.studyEvents.append(
                .init(stage: .cardInterpretation, action: "card_reply_ignored_outside_interpretation_phase")
            )
        }
    }

    private func inviteCardLifeConnectionAfterImageStory() async {
        var analysis = await analyzeCurrentUserTurn(for: .cardInterpretation)
        guard responseContextIsCurrent(expectedStage: .cardInterpretation) else { return }
        analysis.consentToCandor = .yes
        mergeAnalysis(analysis)
        session.latestAnalysis = analysis
        if analysis.safetyOverride {
            interruptForSafety()
            return
        }
        setWorkflowPhase(.cardConnection, action: "card_connection_prompted")
        transition(to: .attributionReflection, action: "card_association_completed")
        await generateDialogue(
            state: .attributionReflection,
            goal: "briefly use only the user's own picture description and ask whether it brings any specific part of their situation to mind. Make no connection an easy, valid answer. Do not interpret the image, infer a motive, assign responsibility, summarize, advise, or propose action",
            authority: .userMeaning(nil),
            managesTyping: false
        )
    }

    /// A card-to-life association is not yet a shared interpretation. Before applying either
    /// system-wide reflection approach, show one tentative bridge built from the person's own
    /// image relation, their own association, and already confirmed context. The person can
    /// affirm, rewrite, or reject it; Swift owns that gate.
    private func presentCardCandidateMapping(managesTyping: Bool) async {
        guard session.condition.usesCard,
              !session.cardConnectionUnavailable else {
            await beginCandidCircumstancesWithoutCard(
                reason: "card_candidate_mapping_unavailable",
                managesTyping: managesTyping
            )
            return
        }
        let imageRelations = groundedSemanticRelations(
            kinds: [.imageStructure],
            in: session.latestAnalysis
        )
        let realityRelations = groundedSemanticRelations(
            kinds: [.realityStructure],
            in: session.latestAnalysis
        )
        guard !imageRelations.isEmpty, !realityRelations.isEmpty else {
            await beginCandidCircumstancesWithoutCard(
                reason: "card_candidate_mapping_missing_structural_evidence",
                managesTyping: managesTyping
            )
            return
        }
        guard session.contextSummaryConfirmed,
              let card = session.card else {
            await beginCandidCircumstancesWithoutCard(
                reason: "card_candidate_mapping_missing_confirmed_reality_baseline",
                managesTyping: managesTyping
            )
            return
        }
        let groundingMatch = cardGroundingMatcher.match(
            card: card,
            userImageNarrative: session.context.cardInterpretation ?? "",
            semanticRelations: groundedSemanticRelations(
                kinds: Set(SemanticRelationKind.allCases),
                in: session.latestAnalysis
            )
        )
        session.cardGroundingMatch = groundingMatch
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: groundingMatch == nil
                    ? "card_candidate_mapping_without_user_grounding"
                    : "card_candidate_mapping_with_user_grounded_relations"
            )
        )
        let responsePlan = validatedResponsePlan(
            for: .attributionReflection,
            analysis: session.latestAnalysis
        )
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: responsePlan?.function == .connectImageToReality
                    ? "card_mapping_response_plan_validated"
                    : "card_mapping_response_plan_unavailable_emergency_wording"
            )
        )

        if managesTyping { isTyping = true }
        defer { if managesTyping { finishTypingForCurrentResponse() } }
        do {
            let turn = try await dialogueGenerator.generate(
                state: .attributionReflection,
                route: session.currentRoute,
                context: session.context,
                analysis: session.latestAnalysis,
                card: session.card,
                trackingCues: Array(session.context.confirmedTrackingCues.prefix(4)),
                promptEvidence: dialoguePromptEvidence(
                    cardDeltaOnly: false,
                    responsePlan: responsePlan?.function == .connectImageToReality
                        ? responsePlan
                        : nil,
                    state: .attributionReflection
                ),
                nextQuestionGoal: """
                Write only one short tentative card-to-life mapping in the reflection field and
                leave question empty. Rephrase, do not concatenate or quote fields. Use one
                evidence-backed imageStructure relation and one evidence-backed realityStructure
                relation from Analyzer evidence. Explain only how their relationship may be
                similar. The local gate records only the person's visible anchors and semantic
                overlap between those two relations; it supplies no designer interpretation or
                target answer. This is a candidate the person may accept, revise, or reject. Add
                no image element, motive, responsibility, action, or tracking causation.
                \(groundingMatch == nil
                    ? "INTERNAL CARD GROUNDING: no user-grounded relation overlap exists. Do not add any card interpretation; compare only relations explicitly supported by the user's words."
                    : userOwnedCardReflectionPrompt(approach: .mapping))
                """,
                messages: session.messages
            )
            let candidate = turn.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cardCandidateMappingIsUsable(candidate) else {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_candidate_mapping_writer_output_rejected",
                    managesTyping: false
                )
                return
            }
            // Persist just the proposed understanding, never the visible confirmation question.
            // It becomes eligible for later prompts only after the person accepts or rewrites it.
            session.cardCandidateMapping = candidate
            setWorkflowPhase(.cardMappingConfirmation, action: "card_candidate_mapping_presented")
            addAssistant(cardMappingConfirmationMessage(candidate))
        } catch {
            await beginCandidCircumstancesWithoutCard(
                reason: "card_candidate_mapping_writer_unavailable",
                managesTyping: false
            )
        }
    }

    private func cardMappingConfirmationMessage(_ mapping: String) -> String {
        "\(mapping)\n\n沿着这个方向回看刚才的经历，最明显的是哪一部分？也可以直接换一个方向或说没有关系。"
    }

    private func cardCandidateMappingIsUsable(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 12, clean.count <= 260, questionMarkCount(clean) == 0 else {
            return false
        }
        let tentativeFrames = ["可能", "也许", "或许", "像是", "有些相似", "一个方向"]
        return tentativeFrames.contains(where: { clean.contains($0) }) &&
            !containsDivinatoryCardLanguage(clean) &&
            !containsUnsupportedCardSymbolicMeaning(clean) &&
            !containsGlobalIdentityLabel(clean) &&
            !containsVisibleProcessLanguage(clean)
    }

    private func cardMappingIsExplicitlyRejected(_ text: String) -> Bool {
        let clean = comparableText(text)
        if cardConnectionIsExplicitlyAbsent(text) || cardDoesNotFit(text) { return true }
        let hardRejections = [
            "不贴近", "不符合", "不对", "不是这样", "没有关系", "不用这个", "不想这样理解"
        ]
        guard hardRejections.contains(where: { clean.contains(comparableText($0)) }) else {
            return false
        }
        return !isSubstantiveCardMappingRevision(text)
    }

    private func isSubstantiveCardMappingRevision(_ text: String) -> Bool {
        let clean = comparableText(text)
        guard clean.count >= 8 else { return false }
        let revisionMarkers = ["其实", "更像", "准确地说", "应该是", "我觉得", "我想", "不是而是"]
        return revisionMarkers.contains { clean.contains(comparableText($0)) } || clean.count >= 18
    }

    /// A complete mapping is a semantic relation with literal user evidence on both sides. Text
    /// length, connective words, and scenario vocabulary do not decide this gate.
    private func isExplicitUserAuthoredCardMapping(in analysis: ContextAnalysis) -> Bool {
        !groundedSemanticRelations(
            kinds: [.imageRealityMapping],
            in: analysis
        ).isEmpty
    }

    private func activateConfirmedCardMapping(_ mapping: String, action: String) {
        session.cardLifeConnection = mapping
        session.cardConfirmedMapping = mapping
        session.cardMappingConfirmed = true
        session.studyEvents.append(.init(stage: .attributionReflection, action: action))
        session.cardGroundingMatch = session.contextSummaryConfirmed ? session.card.flatMap { card in
            cardGroundingMatcher.match(
                card: card,
                userImageNarrative: session.context.cardInterpretation ?? "",
                semanticRelations: groundedSemanticRelations(
                    kinds: Set(SemanticRelationKind.allCases),
                    in: session.latestAnalysis
                )
            )
        } : nil
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: session.cardGroundingMatch == nil
                    ? "card_grounding_unavailable_after_mapping_confirmation"
                    : "card_grounding_available_after_mapping_confirmation"
            )
        )
    }

    private func processAttributionResponse(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }
        guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }

        if canHonorPracticeSuggestionRequest {
            let analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride {
                interruptForSafety()
                return
            }
            if let plan = validatedResponsePlan(
                for: .attributionReflection,
                analysis: analysis
            ), plan.function == .proposePractice {
                await processExplicitPracticeSuggestionRequest(responsePlan: plan)
                return
            }
        }

        switch session.workflowPhase {
        case .cardConnection:
            if session.cardConnectionScaffoldPending {
                session.cardConnectionScaffoldPending = false
                if userCannotConnectCard(text) || cardDoesNotFit(text) {
                    session.cardConnectionAttemptCount += 1
                    await beginCandidCircumstancesWithoutCard(
                        reason: "card_connection_unavailable_after_visual_scaffold",
                        managesTyping: false
                    )
                    return
                }
                appendCardInterpretation(text)
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "card_visual_scaffold_stored_verbatim")
                )
                addAssistant(cardScaffoldConnectionQuestion(from: text))
                return
            }
            if cardConnectionIsExplicitlyAbsent(text) || cardDoesNotFit(text) {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_connection_explicitly_unavailable",
                    managesTyping: false
                )
                return
            }
            if userCannotConnectCard(text) || !isWorthAnalyzingCardConnectionAnswer(text) {
                session.cardConnectionAttemptCount += 1
                if session.cardConnectionAttemptCount >= 2 {
                    await beginCandidCircumstancesWithoutCard(
                        reason: "card_connection_unavailable_after_limited_attempts",
                        managesTyping: false
                    )
                } else {
                    session.cardConnectionScaffoldPending = true
                    session.studyEvents.append(
                        .init(stage: .attributionReflection, action: "card_connection_retried_once")
                    )
                    addAssistant(cardVisualScaffoldQuestion())
                }
                return
            }
            var analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            analysis.consentToCandor = .yes
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride { interruptForSafety(); return }
            if isExplicitUserAuthoredCardMapping(in: analysis) {
                session.hasUserAuthoredCardConnection = true
                session.cardLifeConnection = text.trimmingCharacters(in: .whitespacesAndNewlines)
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "user_authored_card_connection")
                )
                activateConfirmedCardMapping(
                    text.trimmingCharacters(in: .whitespacesAndNewlines),
                    action: "user_authored_card_mapping_confirmed_directly"
                )
                await beginCandidCircumstances(managesTyping: false)
                return
            }
            let hasImageRelation = !groundedSemanticRelations(
                kinds: [.imageStructure],
                in: analysis
            ).isEmpty
            let hasRealityRelation = !groundedSemanticRelations(
                kinds: [.realityStructure],
                in: analysis
            ).isEmpty
            guard hasImageRelation, hasRealityRelation else {
                session.cardConnectionAttemptCount += 1
                if session.cardConnectionAttemptCount >= 2 {
                    await beginCandidCircumstancesWithoutCard(
                        reason: "card_connection_missing_semantic_mapping_after_limited_attempts",
                        managesTyping: false
                    )
                } else {
                    session.cardConnectionScaffoldPending = true
                    addAssistant(cardVisualScaffoldQuestion())
                }
                return
            }
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "card_candidate_mapping_requested_from_structural_relations")
            )
            await presentCardCandidateMapping(managesTyping: false)

        case .cardMappingConfirmation:
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cardMappingIsExplicitlyRejected(clean) || clean.isEmpty {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_candidate_mapping_rejected",
                    managesTyping: false
                )
                return
            }
            if userAffirmsAccuracy(clean) {
                session.cardConfirmedMapping = session.cardCandidateMapping ?? ""
            } else if isSubstantiveCardMappingRevision(clean) {
                // The revision is the user's wording, not an amendment the system infers.
                session.cardConfirmedMapping = clean
            } else {
                await beginCandidCircumstancesWithoutCard(
                    reason: "card_candidate_mapping_not_confirmed",
                    managesTyping: false
                )
                return
            }
            var analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            analysis.consentToCandor = .yes
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride { interruptForSafety(); return }
            activateConfirmedCardMapping(
                session.cardConfirmedMapping ?? "",
                action: userAffirmsAccuracy(clean)
                    ? "card_candidate_mapping_confirmed"
                    : "card_candidate_mapping_revised_by_user"
            )
            await beginCandidCircumstances(managesTyping: false)

        case .cardMeaningShift:
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            analysis.consentToCandor = .yes
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride { interruptForSafety(); return }
            session.cardMeaningShiftResponse = clean
            session.cardMeaningShiftCompleted = true
            refreshCardDerivedDeltaNarrative()
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "user_authored_card_meaning_shift")
            )
            await advanceAfterCardMeaningShift(managesTyping: false)

        case .candidCircumstances:
            var analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            analysis.consentToCandor = .yes
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride { interruptForSafety(); return }
            let circumstances = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // “没有了 / 想不到” is a valid boundary, but it is not a circumstance to be
            // reworded as if it were evidence in the later narrative.
            let isBroadMindsetLabel = isBroadMindsetAttribution(circumstances)
            session.candidCircumstancesResponse =
                userHasNoAdditionalCircumstances(circumstances) || isBroadMindsetLabel
                    ? nil
                    : circumstances
            session.candidCircumstancesCompleted = true
            session.studyEvents.append(
                .init(
                    stage: .attributionReflection,
                    action: isBroadMindsetLabel
                        ? "broad_mindset_attribution_not_saved_as_circumstance"
                        : session.candidCircumstancesResponse == nil
                            ? "candid_circumstances_completed_without_additional_detail"
                            : "candid_circumstances_completed"
                )
            )
            guard session.condition.usesCard,
                  !session.cardConnectionUnavailable,
                  session.cardMappingConfirmed else {
                guard hasUserSupportedFierceFocus else {
                    await completeCandidReflectionWithoutFierce()
                    return
                }
                setWorkflowPhase(.candidAgency, action: "direct_candid_agency_prompted")
                await generateDialogue(
                    state: .attributionReflection,
                    goal: "NO USABLE CARD CONNECTION: respond briefly to the real circumstances the user named. Tender grounding and the user-confirmed background have already happened. Use candid reflection only around a concrete behaviour, consequence, boundary, responsibility, or controllable part the user already described. Preserve the exact semantic scope of that evidence and make none or not sure valid. Do not mention the card, ask whether it changed understanding, infer a mechanism, or introduce a scenario-specific action. Confirmed tracking is background only, never cause or excuse. Offer no summary or advice.",
                    authority: .userMeaning(nil),
                    managesTyping: false
                )
                return
            }
            if session.cardMeaningShiftCompleted {
                await advanceAfterCardMeaningShift(managesTyping: false)
                return
            }
            setWorkflowPhase(.cardMeaningShift, action: "card_meaning_shift_prompted_after_context")
            await generateDialogue(
                state: .attributionReflection,
                goal: "now that the tender side of the confirmed structural mapping has been explored, ask whether the relationship seen through the image adds one new distinction, sharpens an existing one, or leaves the person's understanding unchanged. Do not replay the baseline event, tracking observations, image inventory, or mapping sentence. Make 'it does not change anything' a complete answer. Do not add symbolic meanings, agency, advice, or action. \(userOwnedCardReflectionPrompt(approach: .mapping))",
                authority: .userMeaning(nil),
                managesTyping: false
            )

        case .candidAgency:
            var analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
            guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
            analysis.consentToCandor = .yes
            mergeAnalysis(analysis)
            session.latestAnalysis = analysis
            if analysis.safetyOverride { interruptForSafety(); return }

            let explicitBoundary = userDeclinesAction(text) || isUncertainAnswer(text)
            let hasGroundedAgency = !groundedSemanticRelations(
                kinds: [.controllablePart, .boundaryNeed, .behaviorImpact],
                in: analysis
            ).isEmpty
            let usableDuringAnalyzerOutage =
                analysis.confidence == 0 && isUsableCandidAgencyResponse(text)
            guard explicitBoundary || hasGroundedAgency || usableDuringAnalyzerOutage else {
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "candid_agency_response_not_usable")
                )
                addAssistant("我没太接上刚才那句。回到这件事，你暂时有想调整的一小部分吗？没有也可以。")
                return
            }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBroadCandidAgencyAnswer(clean),
               !session.studyEvents.contains(where: {
                   $0.action == "broad_candid_agency_clarification_prompted"
               }) {
                session.studyEvents.append(
                    .init(
                        stage: .attributionReflection,
                        action: "broad_candid_agency_clarification_prompted"
                    )
                )
                await generateDialogue(
                    state: .attributionReflection,
                    goal: "the user named a broad desired quality or change. Briefly acknowledge it, then ask what it would look like as one observable response in that concrete situation. Do not infer motive, responsibility, or an action they did not name; make not sure valid",
                    authority: .userMeaning(
                        validatedResponsePlan(
                            for: .attributionReflection,
                            analysis: analysis
                        )
                    ),
                    managesTyping: false
                )
                return
            }
            // “没有 / 不确定” is a valid boundary, not an agency claim to preserve in the later
            // narrative as though the user had chosen it. Any need for further concreteness comes
            // from the Analyzer's controllablePart relation, not a scenario-specific phrase list.
            session.candidAgencyResponse = (userDeclinesAction(clean) || isUncertainAnswer(clean))
                ? nil
                : clean
            session.candidAgencyCompleted = true
            refreshCardDerivedDeltaNarrative()
            session.hasCompletedAttributionExchange = true
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "candid_agency_completed")
            )
            setWorkflowPhase(
                .reflectionNarrativeConfirmation,
                action: "integrated_reflection_narrative_started"
            )
            await presentIntegratedReflectionNarrative(managesTyping: false, revised: false)

        case .reflectionNarrativeConfirmation:
            if integratedNarrativeNeedsRevision(text) {
                let analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
                guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
                mergeAnalysis(analysis)
                session.latestAnalysis = analysis
                if analysis.safetyOverride { interruptForSafety(); return }
                await presentIntegratedReflectionNarrative(managesTyping: false, revised: true)
                return
            }
            guard userAffirmsAccuracy(text) else {
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "integrated_reflection_narrative_confirmation_unclear")
                )
                addAssistant("先不要求你评价这段整理。它让你最想继续谈的是哪一部分？")
                return
            }
            session.integratedNarrativeConfirmed = true
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "integrated_reflection_narrative_confirmed")
            )
            setWorkflowPhase(.optionalAction, action: "optional_action_invited")
            await presentActionDrafts(managesTyping: false)

        case .optionalAction:
            if userDeclinesAction(text) {
                session.context.selectedAction = nil
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "optional_action_declined")
                )
                setWorkflowPhase(.narrativeConfirmation, action: "final_narrative_started_without_action")
                await presentFinalNarrative(managesTyping: false, revised: false)
            } else if actionSelectionIsAmbiguous(text) {
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "optional_action_selection_unclear")
                )
                addAssistant("可以先不急着定。你可以说选第一个或第二个，也可以直接改成更适合你的一小步，两个都不要也可以。")
            } else {
                let proposed = resolvedActionText(from: text)
                guard !actionNeedsNarrowing(proposed) else {
                    session.studyEvents.append(
                        .init(stage: .attributionReflection, action: "broad_action_not_accepted_before_narrowing")
                    )
                    addAssistant("这个方向可以先保留。你愿意把它缩小成今天能完成的一小步吗？也可以先不决定。")
                    return
                }
                await acceptActionAndComplete(proposed)
            }

        case .actionConfirmation:
            if userDeclinesAction(text) {
                session.pendingUserAuthoredAction = nil
                session.context.selectedAction = nil
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "optional_action_declined_during_confirmation")
                )
                setWorkflowPhase(.narrativeConfirmation, action: "final_narrative_started_without_action")
                await presentFinalNarrative(managesTyping: false, revised: false)
                return
            }
            if userAffirmsAccuracy(text), let proposed = session.pendingUserAuthoredAction {
                if actionNeedsNarrowing(proposed) {
                    session.studyEvents.append(
                        .init(stage: .attributionReflection, action: "broad_action_not_accepted_before_narrowing")
                    )
                    addAssistant("可以，那就再缩小一点。今天你愿意先做哪一个小步骤？也可以先不决定。")
                    return
                }
                let selectedDraft = session.actionSuggestions.first { $0.description == proposed }
                session.context.selectedAction = CompassionateAction(
                    category: selectedDraft?.category ?? userAuthoredActionCategory(from: proposed),
                    description: proposed,
                    timing: selectedDraft?.timing,
                    acceptedByUser: true
                )
                session.userAuthoredActionConfirmed = true
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "optional_action_user_confirmed")
                )
                await completeAfterConfirmedAction()
                return
            }
            let revised = resolvedActionText(from: text)
            session.pendingUserAuthoredAction = revised
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "optional_action_user_revised")
            )
            addAssistant(actionConfirmationPrompt(for: revised))

        case .narrativeConfirmation:
            if integratedNarrativeNeedsRevision(text) {
                let analysis = await analyzeCurrentUserTurn(for: .attributionReflection)
                guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
                mergeAnalysis(analysis)
                session.latestAnalysis = analysis
                if analysis.safetyOverride { interruptForSafety(); return }
                await presentFinalNarrative(managesTyping: false, revised: true)
                return
            }
            guard userAffirmsAccuracy(text) else {
                session.studyEvents.append(
                    .init(stage: .attributionReflection, action: "final_narrative_confirmation_unclear")
                )
                addAssistant("先不要求你核对这段记录。回看整个过程，你最想保留的是哪一部分？")
                return
            }
            session.finalNarrativeConfirmed = true
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "final_narrative_confirmed")
            )
            transition(to: .summary, action: "final_narrative_confirmed_before_summary")
            setWorkflowPhase(.complete, action: "reflection_workflow_completed")
            transition(to: .completed, action: "session_completed_after_narrative_confirmation")
            addAssistant("好，这段记录就按你确认的说法保留下来。这次反思到这里结束，你可以保存或删除记录。")

        default:
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "attribution_reply_ignored_outside_workflow_phase")
            )
        }
    }

    private func processActionRevision(_ text: String) async {
        isTyping = true
        defer { finishTypingForCurrentResponse() }
        session.studyEvents.append(.init(stage: .actionSelection, action: "action_options_revision_requested"))
        await generateDialogue(
            state: .actionSelection,
            goal: "revise the action drafts around the user's latest wording; keep them small and realistic",
            authority: .userMeaning(nil),
            managesTyping: false
        )
    }

    private func presentActionDrafts(
        managesTyping: Bool,
        responsePlan: ResponsePlan? = nil,
        practiceOverride: CompassionatePracticeDirection? = nil
    ) async {
        session.actionSuggestions = []
        let practice = practiceOverride ?? recommendedCompassionatePractice()
        if practice == .noAction {
            session.studyEvents.append(
                .init(stage: .attributionReflection, action: "compassionate_practice_no_action_offered")
            )
            addAssistant(
                "这次可以先不设置实践，只把刚才的理解留在这里。你可以回复“就先这样”；如果之后想保留一个很小的做法，也可以直接写出来。"
            )
            return
        }
        let direction = practice.actionCategory?.rawValue ?? "care"
        await generateDialogue(
            state: .actionSelection,
            goal: "using only confirmed facts and relationships, generate ONE concrete low-burden action draft in the Swift-selected direction \(direction). The direction is a support choice, not a diagnosis or workflow requirement. Match the action function to the confirmed need, impact, boundary, behavior, uncertainty, or controllable part. Do not use a card, contextual cue, rejection, or self-evaluation as action evidence, and never import a predefined scenario template. The user may select, modify, or reject the draft; do not imply obligation, fault, or guaranteed outcomes",
            authority: responsePlan.map { .userMeaning($0) } ?? .swiftControlled,
            managesTyping: managesTyping
        )
        guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
        session.studyEvents.append(
            .init(stage: .attributionReflection, action: "optional_action_drafts_presented")
        )
    }

    private func resolvedActionText(from response: String) -> String {
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = comparableText(clean)
        let revisionMarkers = ["改成", "修改为", "换成"]
        if let marker = revisionMarkers.first(where: { clean.contains($0) }),
           let range = clean.range(of: marker) {
            let revised = clean[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !revised.isEmpty { return revised }
        }
        if ["1", "一", "第一个", "选一", "选第一个", "第1个", "第一条"].contains(normalized) ||
            normalized.contains(comparableText("我选第一个")) ||
            normalized.contains(comparableText("第一个可以")) ||
            normalized.contains(comparableText("第一条")),
           let first = session.actionSuggestions.first {
            return first.description
        }
        if ["2", "二", "第二个", "选二", "选第二个", "第2个", "第二条"].contains(normalized) ||
            normalized.contains(comparableText("我选第二个")) ||
            normalized.contains(comparableText("第二个可以")) ||
            normalized.contains(comparableText("第二条")),
           session.actionSuggestions.count > 1 {
            return session.actionSuggestions[1].description
        }
        return clean
    }

    private func beginCandidCircumstancesWithoutCard(reason: String, managesTyping: Bool) async {
        let sourceStage = session.stage
        session.cardConnectionUnavailable = true
        session.cardWasSetAside = true
        session.dialogueProgress.cardPreference = .declined
        // Preserve the chance-drawn stimulus and its draw record for study review and resume.
        // `cardWasSetAside` is the prompt boundary that prevents further interpretation.
        if session.card != nil { session.cardDisplayState = .displayed }
        session.hasUserAuthoredCardConnection = false
        session.cardConnectionScaffoldPending = false
        session.cardCandidateMapping = nil
        session.cardConfirmedMapping = nil
        session.cardMappingConfirmed = false
        session.cardGroundingMatch = nil
        session.cardDerivedDeltaNarrative = nil
        session.actionSuggestions.removeAll()
        session.studyEvents.append(.init(stage: sourceStage, action: reason))
        session.studyEvents.append(
            .init(stage: sourceStage, action: "card_connection_recorded_as_none")
        )
        if sourceStage == .cardInterpretation {
            transition(to: .attributionReflection, action: "card_connection_none_entered_candid_reflection")
        }
        setWorkflowPhase(.candidCircumstances, action: "candid_circumstances_prompted")
        await generateDialogue(
            state: .attributionReflection,
            goal: "accept briefly that this random card did not form a useful connection and do not seek another one. Return only to the already confirmed situation and ask which real circumstance or limitation needs to be acknowledged before the user judges themselves. Do not interpret the card, advise, summarize, or ask for another detail",
            authority: .userMeaning(nil),
            managesTyping: managesTyping
        )
    }

    private func beginCandidCircumstances(managesTyping: Bool) async {
        guard session.cardMappingConfirmed,
              session.cardConfirmedMapping?.isEmpty == false else {
            await beginCandidCircumstancesWithoutCard(
                reason: "card_candid_blocked_without_confirmed_mapping",
                managesTyping: managesTyping
            )
            return
        }
        setWorkflowPhase(.candidCircumstances, action: "candid_circumstances_prompted")
        await generateDialogue(
            state: .attributionReflection,
            goal: "use only the USER-CONFIRMED card-to-life mapping as an interpretive lens, not as a diagnosis or proof. Before asking what the image changes, deepen the real situation around that confirmed mapping. Begin with the user's own picture relation and the confirmed real-life relation, then ask one tender, concrete question about what was happening, which limits or pain mattered, and what made that moment hard to carry. Add no card meaning, agency, action, or summary; tracking may be included only as a user-confirmed background, never as a cause. \(userOwnedCardReflectionPrompt(approach: .tender))",
            authority: .userMeaning(nil),
            managesTyping: managesTyping
        )
    }

    /// Fierce compassion is not a compulsory second half of every reflection. It becomes useful
    /// only when the person supplied a concrete behavior, consequence, or boundary. Keeping this
    /// transition in one function also lets a restored legacy session complete the missing Tender
    /// circumstances turn without asking the already-saved meaning-shift question again.
    private func advanceAfterCardMeaningShift(managesTyping: Bool) async {
        guard hasUserSupportedFierceFocus || cardMeaningShiftProvidesConcreteFocus else {
            await completeCandidReflectionWithoutFierce()
            return
        }
        setWorkflowPhase(.candidAgency, action: "candid_agency_prompted")
        await generateDialogue(
            state: .attributionReflection,
            goal: "respond briefly to the user's own answer about whether the image changed their understanding. The tender grounding and user-confirmed background have already been established. Invite one candid but non-accusing examination of exactly one evidence-supported relationship among behavior, impact, boundary, responsibility, controllability, protection, or change. Keep its scope identical to what the user supplied; do not infer any relationship from another fact or from a self-evaluation alone. Preserve relevant constraints alongside the supported candid fact without turning either into a personality verdict. Use one natural present-focused question, make uncertainty or refusal complete answers, and do not decide motive, fault, or responsibility. Tracking may remain user-confirmed background, never evidence that caused or excused conduct. Offer no advice, action draft, or summary. \(userOwnedCardReflectionPrompt(approach: .fierce))",
            authority: .userMeaning(nil),
            managesTyping: managesTyping
        )
    }

    /// The direct condition enters the same candid portion of the study immediately after the
    /// shared context confirmation. No card, card metadata, or card-specific prompt context is
    /// supplied to the generator.
    private func beginDirectCandidReflection(managesTyping: Bool) async {
        guard !session.condition.usesCard,
              session.stage == .readinessCheck,
              session.workflowPhase == .contextConfirmation else { return }
        // Both study conditions share the tracking gate. This only repairs a resumed legacy
        // direct session that reached context confirmation before its tracking review completed.
        guard session.trackingReviewCompleted else {
            session.contextSummaryConfirmed = false
            setWorkflowPhase(.trackingReview, action: "direct_condition_tracking_review_restored")
            transition(to: .trackingReview, action: "direct_condition_returned_to_tracking_review")
            await loadTrackingReviewData(conversationRepair: true)
            return
        }
        session.currentRoute = .explore
        setWorkflowPhase(.candidCircumstances, action: "direct_candid_circumstances_prompted")
        transition(to: .attributionReflection, action: "direct_candid_reflection_started")
        await generateDialogue(
            state: .attributionReflection,
            goal: "DIRECT CONDITION: no card was drawn and no image interpretation exists. Return only to the confirmed situation and ask one tender, concrete question about a real circumstance, limit, or pain that needs to be acknowledged before the person judges themselves. Do not mention cards, images, symbolism, randomization, or the experimental condition. Do not assign responsibility, advise, summarize, or ask for another disclosure field.",
            authority: .userMeaning(nil),
            managesTyping: managesTyping
        )
    }

    private enum CardReflectionApproach { case mapping, tender, fierce }

    /// After one soft “想不到”, reduce the task by returning to a contrast inside the picture.
    /// The catalogue selects only the shape of the question. The visible words stay anchored to
    /// what the person already described, and their next answer is stored as picture narrative,
    /// not as evidence about their life.
    private func cardVisualScaffoldQuestion() -> String {
        let narrative = session.context.cardInterpretation?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let guidance = session.card?.visualGuidance else {
            return "没关系，先不联系现实。只看你刚才说的画面，你觉得接下来可能会发生什么？"
        }
        if let scaffold = matchingCardVisualScaffold(in: guidance, narrative: narrative) {
            return "没关系，先不联系现实。\(scaffold.question)"
        }

        if let last = narrative
            .split(separator: "；", omittingEmptySubsequences: true)
            .last {
            let clause = String(last.prefix(24))
            return "没关系，先不联系现实。沿着你刚才说的“\(clause)”，你觉得画面接下来可能会发生什么？"
        }
        return "没关系，先不联系现实。只看这个画面，你觉得接下来可能会发生什么？"
    }

    private func cardScaffoldConnectionQuestion(from answer: String) -> String {
        var clause = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if clause.count > 44 {
            clause = String(clause.prefix(44)) + "…"
        }
        guard !clause.isEmpty else {
            return "把刚才补充的画面放回最近这件事里，会让你想到什么吗？想不到的话，我们就回到刚才的事情。"
        }
        return "你刚才补充了“\(clause)”。把这个画面放回刚才那件事里，会让你想到什么吗？想不到也没关系。"
    }

    /// A catalogue scaffold is eligible only when every visual group it refers to is present in
    /// the person's own story. This prevents a card-specific question from introducing an
    /// unseen person, object, or action just because it exists in the card catalogue.
    private func matchingCardVisualScaffold(
        in guidance: CardVisualGuidance,
        narrative: String
    ) -> CardVisualScaffold? {
        let normalizedNarrative = comparableText(narrative)
        guard !normalizedNarrative.isEmpty else { return nil }
        return guidance.visualScaffolds.first { scaffold in
            isAllowedCardVisualScaffold(scaffold.question) &&
            scaffold.requiredAnchorGroups.allSatisfy { group in
                group.contains { anchor in
                    let normalizedAnchor = comparableText(anchor)
                    return !normalizedAnchor.isEmpty && normalizedNarrative.contains(normalizedAnchor)
                }
            }
        }
    }

    /// Defensive validation for catalogue content. Card scaffolds must remain one neutral
    /// picture question; tender/fierce questions and action advice can only appear after a
    /// user-authored card-to-life connection.
    private func isAllowedCardVisualScaffold(_ question: String) -> Bool {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard questionMarkCount(clean) == 1,
              !isForcedCardBinaryQuestion(clean) else { return false }
        let normalized = comparableText(clean)
        let forbidden = [
            "这张牌", "代表", "说明", "象征", "你应该", "现实", "责任", "行动",
            "改变", "小步", "局部可控", "生活", "最近这件事"
        ]
        return !forbidden.contains { normalized.contains(comparableText($0)) }
    }

    /// This text is intentionally internal prompt context. It is added only after the user has
    /// supplied both an image story and a concrete life connection, and only when a deterministic
    /// local overlap exists. The catalogue's designer-authored observable relation is deliberately
    /// absent: it is documentation for visual QA, not a target answer for dialogue.
    private func userOwnedCardReflectionPrompt(
        approach: CardReflectionApproach
    ) -> String {
        guard let match = session.cardGroundingMatch else {
            return "INTERNAL USER-OWNED CARD REFLECTION: No user-grounded relation overlap was found. Use only the person's picture and situation words; do not draw from catalogue meanings."
        }
        let method: String
        switch approach {
        case .mapping:
            method = "Compare only the two user-grounded relations. Offer one tentative, editable, rejectable similarity; do not apply Tender or Fierce yet."
        case .tender:
            method = SystemReflectionApproaches.standard.tender
        case .fierce:
            method = SystemReflectionApproaches.standard.fierce
        }
        let concepts = match.matchedConcepts?.map(\.rawValue).joined(separator: "、") ?? "not available"
        return """
        INTERNAL USER-OWNED CARD REFLECTION — NEVER DISPLAY OR NAME THIS BLOCK:
        User-grounded image relation: \(match.imageRelation ?? "not available").
        User-grounded reality relation: \(match.realityRelation ?? "not available").
        Visual anchors named by the person: \(match.matchedVisualAnchors.joined(separator: "、")).
        Shared concepts found only between those user-grounded relations: \(concepts).
        System-wide response method: \(method)
        Start from the person's exact relations. Do not retrieve, paraphrase, or steer toward the
        catalogue's observable relation, title, former theme, or any card-specific psychological
        conclusion. Compare relationships; never explain what an object symbolizes. Never imply
        that the image proves a cause, motive, emotion, personality, capacity, diagnosis,
        responsibility, constraint, need, action, or future.
        """
    }

    private func acceptActionAndComplete(_ proposed: String) async {
        let selectedDraft = session.actionSuggestions.first { $0.description == proposed }
        session.context.selectedAction = CompassionateAction(
            category: selectedDraft?.category ?? userAuthoredActionCategory(from: proposed),
            description: proposed,
            timing: selectedDraft?.timing,
            acceptedByUser: true
        )
        session.userAuthoredActionConfirmed = true
        session.studyEvents.append(
            .init(stage: .attributionReflection, action: "optional_action_user_confirmed_once")
        )
        await completeAfterConfirmedAction()
    }

    private func completeAfterConfirmedAction() async {
        setWorkflowPhase(.narrativeConfirmation, action: "final_narrative_recorded_after_action")
        refreshCardDerivedDeltaNarrative()
        let cardDeltaOnly = session.condition.usesCard && session.cardMappingConfirmed
        await generateDialogue(
            state: .attributionReflection,
            goal: cardDeltaOnly
                ? "write a brief completion note using the confirmed card-derived delta and the accepted action. Refer to the locked baseline situation only once and do not repeat tracking data, disclosure fields, or the earlier attribution. Preserve the confirmed image relation, reality mapping, user-authored distinction, and actual meaning shift; if the user reported no change, state no change. End with the accepted action. Add no symbolic explanation, new advice, evaluation, or confirmation question"
                : "write a brief completion note after the user's first concrete action choice. Use only the already confirmed integrated understanding and the accepted action. In 2–4 short natural Chinese sentences, preserve the pain, the specific behaviour the user chose to face, any care or protection that remains needed, and any cause or responsibility that remains uncertain. Do not mention a rejected or unavailable card. Do not repeat database-like fields, first-person fragments, or a generic preparation template. End by stating the one accepted action. Add no praise, advice, evaluation, or confirmation question",
            managesTyping: false,
            requiresIntegratedNarrative: true,
            integratedNarrativeAccuracyCheck: false,
            trackingCuesOverride: cardDeltaOnly
                ? []
                : Array(session.context.confirmedTrackingCues.prefix(4))
        )
        guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
        session.finalNarrativeConfirmed = true
        session.studyEvents.append(
            .init(stage: .attributionReflection, action: "final_narrative_saved_after_action_confirmation")
        )
        transition(to: .summary, action: "action_confirmation_completed_reflection")
        setWorkflowPhase(.complete, action: "reflection_workflow_completed")
        transition(to: .completed, action: "session_completed_after_action_confirmation")
    }

    private func presentIntegratedReflectionNarrative(managesTyping: Bool, revised: Bool) async {
        refreshCardDerivedDeltaNarrative()
        let goal: String
        if session.condition.usesCard, session.cardMappingConfirmed {
            goal = """
            \(revised ? "Revise" : "Write") a concise card-derived delta narrative in 2–4 short,
            natural Chinese sentences. The disclosure-and-tracking synthesis is a LOCKED BASELINE:
            refer to the underlying situation in at most one short sentence, then do not repeat
            its event details, emotions, tracking metrics, tracking interpretation, or first-round
            attribution. The remaining sentences must express only: the user-confirmed image
            relation; the accepted or revised reality mapping; the new distinction developed
            through the user's own interpretation; and the user's reported meaning shift. If the user
            reported no change, state that plainly and invent no insight. Tender and fierce
            material may appear only through the user's answers to those evidence-gated turns.
            Do not list fields, replay image observations, append the tracking summary, explain an
            object as a symbol, name card metadata, add action, or offer advice. Ask one easy
            accuracy question.
            """
        } else {
            goal = revised
                ? "revise the integrated reflection using the user's correction. Use only confirmed disclosure, the user-confirmed non-causal tracking cues, and both candid answers. The direct condition or a card without a usable mapping contributes no card meaning. Write 2–4 short, natural Chinese sentences rather than a field recap. Describe tracking as a time-anchored capacity background that may have made the situation harder to carry, never as a cause, excuse, or responsibility verdict. Show self-kindness without erasing a concrete problem, common humanity only when the user said it, and mindfulness by separating the event, current feeling, and identity/future. Include no action or advice, then ask one easy accuracy question"
                : "write one concise integrated reflection in 2–4 short, natural Chinese sentences using only confirmed disclosure, the user-confirmed non-causal tracking cues, and both candid answers. The direct condition or a card without a usable mapping contributes no card meaning. Do not list fields. Describe tracking as a time-anchored capacity background that may have made the situation harder to carry, never as a cause, excuse, or responsibility verdict. Show self-kindness without erasing a concrete problem, common humanity only when the user said it, and mindfulness by separating the event, current feeling, and identity/future. Distinguish circumstances from agency without assigning an unsupported motive. Include no action or advice, then ask one easy accuracy question"
        }
        await generateDialogue(
            state: .attributionReflection,
            goal: goal,
            managesTyping: managesTyping,
            requiresIntegratedNarrative: true,
            integratedNarrativeAccuracyCheck: true,
            trackingCuesOverride: session.condition.usesCard && session.cardMappingConfirmed
                ? []
                : Array(session.context.confirmedTrackingCues.prefix(4))
        )
        guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
        session.hasPresentedIntegratedNarrative = true
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: revised
                    ? "integrated_reflection_narrative_revised"
                    : "integrated_reflection_narrative_presented"
            )
        )
    }

    private func presentFinalNarrative(managesTyping: Bool, revised: Bool) async {
        refreshCardDerivedDeltaNarrative()
        let goal: String
        if session.condition.usesCard, session.cardMappingConfirmed {
            goal = """
            \(revised ? "Revise" : "Write") the final card-derived delta in 2–4 short natural
            Chinese sentences. Refer to the locked baseline situation once at most; do not repeat
            tracking data, prior attribution, emotions, or disclosure fields. Preserve the
            confirmed image relation, corrected reality mapping, the user-authored distinction
            the user accepted, and the user's actual meaning-shift answer. When they reported no
            change, say so without manufacturing an insight. Include an action only if the user
            confirmed it. Do not append the baseline summary, explain symbols, or add advice. Ask
            one easy accuracy question.
            """
        } else {
            goal = revised
                ? "revise the final narrative in 2–4 short natural Chinese sentences using only user-confirmed disclosure, user-confirmed non-causal tracking cues, both candid answers, and only an action the user confirmed. A direct condition or rejected card contributes no card meaning. Keep uncertainty about cause or responsibility and do not repeat raw fields. Add no new advice, then ask one easy accuracy question"
                : "write the final concise narrative in 2–4 short natural Chinese sentences using only user-confirmed disclosure, user-confirmed non-causal tracking cues, both candid answers, and only an action the user confirmed. A direct condition or rejected card contributes no card meaning. Keep uncertainty about cause or responsibility and do not repeat raw fields. Add no new advice, then ask one easy accuracy question"
        }
        await generateDialogue(
            state: .attributionReflection,
            goal: goal,
            managesTyping: managesTyping,
            requiresIntegratedNarrative: true,
            integratedNarrativeAccuracyCheck: true,
            trackingCuesOverride: session.condition.usesCard && session.cardMappingConfirmed
                ? []
                : Array(session.context.confirmedTrackingCues.prefix(4))
        )
        guard responseContextIsCurrent(expectedStage: .attributionReflection) else { return }
        session.hasPresentedIntegratedNarrative = true
        session.hasPresentedFinalNarrative = true
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: revised ? "final_narrative_revised" : "final_narrative_presented"
            )
        )
    }

    private func actionConfirmationPrompt(for proposedAction: String) -> String {
        let clean = String(proposedAction.prefix(80))
        if actionNeedsNarrowing(clean) {
            return "这个方向可以先保留。你愿意把它缩小成今天能完成的一小步吗？也可以先不决定。"
        }
        return "你想把下一步定为“\(clean)”，是这样吗？如果还需要改小一点，可以直接改。"
    }

    private func actionNeedsNarrowing(_ text: String) -> Bool {
        let clean = comparableText(text)
        let broadMarkers = [
            "彻底", "全部", "每天", "以后都", "解决整个问题", "把一切做好",
            "以后不再", "改掉所有", "所有", "一定要", "必须",
        ]
        return clean.count > 56 || broadMarkers.contains { clean.contains(comparableText($0)) }
    }

    private func userAffirmsAccuracy(_ text: String) -> Bool {
        let clean = comparableText(text)
        let negatives = [
            "不是", "不对", "不符合", "不准确", "要改", "需要改", "想改", "不可以",
            "不知道", "不确定", "不清楚", "没看懂", "没有看懂", "不同意", "对不上",
        ]
        if negatives.contains(where: { clean.contains(comparableText($0)) }) { return false }
        let exact = [
            "对", "是", "是的", "对的", "可以", "可以的", "好", "好的", "嗯", "就这样",
            "是这样", "就是这个", "这样就行", "就按这个", "没问题", "符合", "基本符合",
            "差不多", "贴近", "确认",
        ].map(comparableText)
        if exact.contains(clean) { return true }
        let phrases = [
            "就是这样", "差不多是这样", "基本符合", "基本准确", "挺贴近", "就按这个", "符合",
        ]
        if phrases.contains(where: { clean.contains(comparableText($0)) }) { return true }
        let affirmativePrefixes = ["对", "是的", "可以", "好的", "嗯", "确认"]
        return affirmativePrefixes.contains { clean.hasPrefix(comparableText($0)) }
    }

    private func userDeclinesAction(_ text: String) -> Bool {
        let clean = comparableText(text)
        let exact = [
            "没有", "不选", "都不选", "都不要", "先不了", "算了", "就先这样",
            "不设置实践", "不设置行动",
        ].map(comparableText)
        if exact.contains(clean) { return true }
        let phrases = [
            "先不决定", "暂时不决定", "不想决定", "不需要行动", "先不行动", "没有行动",
            "没有下一步", "暂时没有", "现在不想", "先到这里", "两个都不选", "全部不选",
            "都不合适", "都不适合", "这两个不合适", "这两个不适合", "这些不合适",
            "这些不适合", "不想选这些", "我不想选", "暂时不选", "不设置实践",
            "不设置行动", "先不设置行动", "这次先不设置行动",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func actionSelectionIsAmbiguous(_ text: String) -> Bool {
        let clean = comparableText(text)
        return ["可以", "好", "好的", "嗯", "行", "都可以", "随便"]
            .map(comparableText)
            .contains(clean)
    }

    private func userAuthoredActionCategory(from text: String) -> CompassionateActionCategory {
        let clean = comparableText(text)
        if ["休息", "睡", "吃饭", "照顾", "缓一缓"].contains(where: { clean.contains(comparableText($0)) }) {
            return .care
        }
        if ["边界", "拒绝", "暂停", "不接", "保护"].contains(where: { clean.contains(comparableText($0)) }) {
            return .protect
        }
        if ["道歉", "沟通", "解释", "修复", "联系"].contains(where: { clean.contains(comparableText($0)) }) {
            return .repair
        }
        if ["求助", "请教", "支持", "找人", "帮助"].contains(where: { clean.contains(comparableText($0)) }) {
            return .change
        }
        return .change
    }

    private func beginTenderGrounding(
        action: String,
        managesTyping: Bool,
        conversationRepair: Bool = false
    ) async {
        setWorkflowPhase(.tenderGroundingConfirmation, action: "tender_grounding_started")
        transition(to: .tenderGrounding, action: action)
        session.currentRoute = .tenderStabilize
        await generateDialogue(
            state: .tenderGrounding,
            goal: conversationRepair
                ? "briefly acknowledge the earlier repetition, then give one short tender grounding that paraphrases only facts the user has given. Rewrite them into a connected understanding: each sentence should explain the event, its felt impact, or the distinction between a concrete reaction and a global verdict. Never compress, quote, or concatenate user turns in their original order; do not paste whole user sentences or leave first-person wording inside a second-person summary. Add no praise, tracking, card, blame, excuse, or advice, then ask one easy accuracy question"
                : "give one short tender grounding that paraphrases only facts the user has given. Rewrite them into a connected understanding: each sentence should explain the event, its felt impact, or the distinction between a concrete reaction and a global verdict. Never compress, quote, or concatenate user turns in their original order; do not paste whole user sentences or leave first-person wording inside a second-person summary. Preserve uncertainty, add no praise, tracking, card, blame, excuse, or advice, then ask one easy accuracy question",
            managesTyping: managesTyping,
            requiresIntegratedNarrative: true,
            integratedNarrativeAccuracyCheck: true,
            trackingCuesOverride: []
        )
        guard responseContextIsCurrent(expectedStage: .tenderGrounding) else { return }
        session.studyEvents.append(.init(stage: .tenderGrounding, action: "tender_grounding_presented"))
    }

    private func beginContextConfirmation(action: String, managesTyping: Bool) async {
        setWorkflowPhase(.contextConfirmation, action: "context_confirmation_started")
        if session.stage != .readinessCheck {
            transition(to: .readinessCheck, action: action)
        } else {
            session.studyEvents.append(.init(stage: .readinessCheck, action: action))
        }

        let hasContextualHypothesis =
            session.contextualLoadInference?.hasDialogueCue == true &&
            session.contextualLoadInference?.relevance == .notReviewed
        await generateDialogue(
            state: .readinessCheck,
            goal: hasContextualHypothesis
                ? "write one short, coherent, correctable understanding of the disclosed event, pain, concrete limitations, and event-versus-whole-self distinction. Include the supplied measurement-free contextual hypothesis as one tentative clause and never more than one. Do not ask whether that hypothesis fits, do not create a separate tracking turn, and do not mention data, measurements, health domains, records, devices, scores, or a specific emotion. It remains background rather than cause, excuse, blame, responsibility, diagnosis, or advice. Ask only whether the whole understanding is accurate"
                : "write one short, coherent, correctable understanding using only the disclosed event, pain, concrete limitations, and event-versus-whole-self distinction. Do not mention tracking, missing data, measurements, records, devices, or health domains. Ask only whether the whole understanding is accurate",
            managesTyping: managesTyping,
            requiresIntegratedNarrative: true,
            integratedNarrativeAccuracyCheck: true,
            trackingCuesOverride: []
        )
        guard responseContextIsCurrent(expectedStage: .readinessCheck) else { return }
        session.studyEvents.append(.init(stage: .readinessCheck, action: "context_confirmation_presented"))
    }

    private func generateDialogue(
        state: ReflectionState,
        goal: String,
        authority: DialogueAuthority = .swiftControlled,
        managesTyping: Bool = true,
        suppressAcknowledgment: Bool = false,
        requiresIntegratedNarrative: Bool = false,
        integratedNarrativeAccuracyCheck: Bool = false,
        trackingCuesOverride: [TrackingCue]? = nil
    ) async {
        let expectedSessionID = session.id
        let expectedStage = session.stage
        let expectedWorkflowPhase = session.workflowPhase
        guard responseContextIsCurrent(
            expectedSessionID: expectedSessionID,
            expectedStage: expectedStage,
            expectedWorkflowPhase: expectedWorkflowPhase
        ) else { return }
        clearRetry()
        if managesTyping { isTyping = true }
        defer { if managesTyping { finishTypingForCurrentResponse() } }

        let activeResponsePlan: ResponsePlan?
        switch authority {
        case .swiftControlled:
            activeResponsePlan = nil
        case .userMeaning(let suppliedPlan):
            let currentAnalysis = session.latestAnalysis
            if let suppliedPlan,
               let currentAnalysis,
               let validatedSuppliedPlan = responsePlanValidator.validate(
                   suppliedPlan,
                   analysis: currentAnalysis,
                   state: state,
                   workflowPhase: session.workflowPhase,
                   messages: session.messages
               ) {
                // Supplied plans are created or recovered locally for this exact user turn.
                // Literal latest-turn evidence plus phase validation is the currentness check;
                // equality with the raw model plan would incorrectly reject a safe recovered plan.
                activeResponsePlan = validatedSuppliedPlan
            } else {
                let analysis = await analyzer.analyze(
                    context: session.context,
                    messages: session.messages,
                    planningContext: responsePlanningContext(for: state)
                )
                guard responseContextIsCurrent(
                    expectedSessionID: expectedSessionID,
                    expectedStage: expectedStage,
                    expectedWorkflowPhase: expectedWorkflowPhase
                ) else { return }
                mergeAnalysis(analysis)
                session.latestAnalysis = analysis
                if analysis.safetyOverride {
                    interruptForSafety()
                    return
                }
                activeResponsePlan = validatedResponsePlan(for: state, analysis: analysis)
            }
            session.studyEvents.append(
                .init(
                    stage: state,
                    action: activeResponsePlan.map {
                        "open_response_plan_validated_\($0.function.rawValue)"
                    } ?? "open_response_plan_unavailable_emergency_wording"
                )
            )
        }

        do {
            var promptContext = session.context
            if session.cardWasSetAside { promptContext.cardInterpretation = nil }
            let requestedGoal = activeResponsePlan.map(responsePlanGoal) ?? goal
            let goalType = questionGoalType(
                for: state,
                requestedGoal: requestedGoal,
                responsePlan: activeResponsePlan
            )
            let guardedGoal = guardedQuestionGoal(requestedGoal, type: goalType)
            let safeTrackingCues: [TrackingCue]
            if let trackingCuesOverride {
                safeTrackingCues = Array(trackingCuesOverride.prefix(4))
            } else if state == .trackingReview {
                let pendingIDs = session.pendingTrackingCueIDs.isEmpty
                    ? session.pendingTrackingCueID.map { [$0] } ?? []
                    : session.pendingTrackingCueIDs
                safeTrackingCues = pendingIDs.compactMap { pendingID in
                    session.trackingCues.first(where: { $0.id == pendingID })
                }.prefix(4).map { $0 }
            } else {
                safeTrackingCues = Array(session.context.confirmedTrackingCues.prefix(4))
            }
            let useCardDeltaBoundary =
                requiresIntegratedNarrative &&
                session.condition.usesCard &&
                session.cardMappingConfirmed
            let promptEvidence = dialoguePromptEvidence(
                cardDeltaOnly: useCardDeltaBoundary,
                responsePlan: activeResponsePlan,
                state: state
            )
            let workflowEvidence = useCardDeltaBoundary ? "" : workflowEvidenceForPrompt()
            var turn = try await dialogueGenerator.generate(
                state: state,
                route: session.currentRoute,
                context: promptContext,
                analysis: session.latestAnalysis,
                card: session.cardWasSetAside ? nil : session.card,
                trackingCues: safeTrackingCues,
                promptEvidence: promptEvidence,
                nextQuestionGoal: "Workflow phase: \(session.workflowPhase.rawValue). \(workflowEvidence) \(guardedGoal) Recent forbidden goals: \(session.dialogueProgress.forbiddenNextGoals.map(\.rawValue).sorted().joined(separator: ", ")). Card preference: \(session.dialogueProgress.cardPreference.rawValue).",
                messages: session.messages
            )
            guard responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage,
                expectedWorkflowPhase: expectedWorkflowPhase
            ) else { return }
            if state == .trackingReview,
               !safeTrackingCues.isEmpty,
               (containsTechnicalTrackingTerm(turn.visibleText) ||
                isGenericTrackingReply(turn.visibleText) ||
                !containsConcreteTrackingImpactQuestion(turn.visibleText)) {
                let usedTechnicalTerm = containsTechnicalTrackingTerm(turn.visibleText)
                turn = DialogueTurn(
                    reflection: "",
                    question: trackingCandidateFallbackQuestion(),
                    actionOptions: []
                )
                session.studyEvents.append(
                    .init(
                        stage: state,
                        action: usedTechnicalTerm
                            ? "technical_tracking_term_rephrased_for_user"
                            : "tracking_reply_replaced_with_integrated_context_link"
                    )
                )
            }
            if state == .readinessCheck,
               requiresIntegratedNarrative,
               let trackingState = latestUserTrackingStateDescription(),
               !narrativeAcknowledgesTrackingState(turn.reflection, trackingState) {
                turn.reflection = deterministicContextSummary()
                turn.question = accuracyQuestionForCurrentPhase()
                session.studyEvents.append(
                    .init(stage: state, action: "tracking_state_acknowledgment_repaired")
                )
            }
            if questionMarkCount(turn.visibleText) > 1 {
                turn.reflection = ""
                if questionMarkCount(turn.question) != 1 {
                    turn.question = nonRepeatingFallbackQuestion(for: state)
                }
                session.studyEvents.append(.init(stage: state, action: "multiple_visible_questions_suppressed"))
            }
            if expectsVisibleQuestion(
                for: state,
                requiresIntegratedNarrative: requiresIntegratedNarrative,
                integratedNarrativeAccuracyCheck: integratedNarrativeAccuracyCheck
            ), questionMarkCount(turn.visibleText) == 0 {
                if state == .attributionReflection,
                   session.workflowPhase == .cardMeaningShift {
                    // A provider occasionally answers the not-yet-shown perspective question
                    // itself ("没有变化也很正常"). Do not expose that orphaned answer.
                    turn.reflection = ""
                    turn.question = cardMeaningShiftQuestion()
                } else {
                    turn.question = nonRepeatingFallbackQuestion(for: state)
                }
                session.studyEvents.append(
                    .init(stage: state, action: "missing_visible_question_repaired")
                )
            }
            // A synthesis is expected to restate confirmed evidence in a new coherent form. The
            // normal conversational anti-echo filters would otherwise delete exactly the user's
            // card/circumstances/agency wording that the final narrative must preserve.
            if !requiresIntegratedNarrative {
                turn.reflection = removingUserRestatement(from: turn.reflection)
            }
            if !requiresIntegratedNarrative,
               [.cardInterpretation, .attributionReflection].contains(state) {
                turn.reflection = removingUnsupportedCardDescriptor(from: turn.reflection)
            }
            if [.cardInterpretation, .attributionReflection].contains(state),
               containsDivinatoryCardLanguage(turn.visibleText) {
                turn.reflection = ""
                turn.question = nonRepeatingFallbackQuestion(for: state)
                session.studyEvents.append(.init(stage: state, action: "divinatory_card_language_suppressed"))
            }
            if [.cardInterpretation, .attributionReflection].contains(state),
               containsUnsupportedCardSymbolicMeaning(turn.visibleText) {
                if requiresIntegratedNarrative {
                    turn.reflection = deterministicCardIntegrationSummary()
                    turn.question = integratedNarrativeAccuracyCheck
                        ? accuracyQuestionForCurrentPhase()
                        : ""
                } else {
                    turn.reflection = ""
                    turn.question = nonRepeatingFallbackQuestion(for: state)
                }
                session.studyEvents.append(
                    .init(stage: state, action: "unsupported_card_symbolism_suppressed")
                )
            }
            if state == .attributionReflection,
               containsInventedMeaningChangeAfterNoChange(turn.visibleText) {
                if requiresIntegratedNarrative {
                    turn.reflection = deterministicCardIntegrationSummary()
                    turn.question = integratedNarrativeAccuracyCheck
                        ? accuracyQuestionForCurrentPhase()
                        : ""
                } else {
                    turn.reflection = ""
                    turn.question = nonRepeatingFallbackQuestion(for: state)
                }
                session.studyEvents.append(
                    .init(stage: state, action: "invented_card_meaning_change_suppressed")
                )
            }
            if suppressAcknowledgment { turn.reflection = "" }
            if containsUnsupportedVisibleInference(
                turn.visibleText,
                responsePlan: activeResponsePlan
            ) {
                turn.reflection = ""
                turn.question = nonRepeatingFallbackQuestion(for: state)
            }
            if isAbstractChoiceQuestion(turn.question) {
                turn.question = nonRepeatingFallbackQuestion(for: state)
            }
            if state == .cardInterpretation {
                // Image-story turns should feel like a simple continuation of what the person
                // can actually see. A reflective preface easily smuggles in a motive or card
                // meaning, so keep these turns to one neutral question.
                turn.reflection = ""
                if containsUnlicensedCardStoryAssumption(turn.question) {
                    turn.question = openCardStoryQuestion()
                    session.studyEvents.append(
                        .init(stage: state, action: "unlicensed_card_story_assumption_suppressed")
                    )
                }
            }
            if state == .cardInterpretation, isForcedCardBinaryQuestion(turn.question) {
                turn.question = openCardStoryQuestion()
                session.studyEvents.append(
                    .init(stage: state, action: "forced_card_binary_question_reframed")
                )
            }
            if containsVisibleProcessLanguage(turn.visibleText) {
                // Instructions such as “we have already covered this” are useful internal guards,
                // but sound abrupt and expose the dialogue machinery when shown to a person.
                // Keep the forward-moving question and remove the process narration instead.
                turn.reflection = ""
                turn.question = nonRepeatingFallbackQuestion(for: state)
                session.studyEvents.append(.init(stage: state, action: "visible_process_language_suppressed"))
            }
            if containsPressuringOrOrnateLanguage(turn.visibleText) {
                turn.reflection = ""
                turn.question = state == .summary ? "" : nonRepeatingFallbackQuestion(for: state)
            }
            let repeatsPriorAssistantContent =
                isSubstantiallyRepeated(turn.visibleText)
                || (!turn.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && isSubstantiallyRepeated(turn.reflection))
                || (!turn.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && isSubstantiallyRepeated(turn.question))
            if !requiresIntegratedNarrative, repeatsPriorAssistantContent {
                turn.reflection = ""
                turn.question = state == .summary ? "" : nonRepeatingFallbackQuestion(for: state)
                session.studyEvents.append(
                    .init(stage: state, action: "duplicate_assistant_content_reframed")
                )
            }
            if requiresIntegratedNarrative {
                let usedGlobalIdentityLabel = containsGlobalIdentityLabel(turn.visibleText)
                // The model occasionally puts a new exploratory question in `reflection` and
                // leaves `question` empty. The application then appends its accuracy check, which
                // creates two competing questions in one visible turn. A synthesis may contain
                // only prose; the sole question belongs to the application-controlled gate below.
                let embeddedQuestionInNarrative = questionMarkCount(turn.reflection) > 0
                let unusableNarrative = turn.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || looksLikeFieldExportNarrative(turn.reflection)
                    || isGenericIntegratedNarrative(turn.reflection)
                    || hasLongVerbatimUserRun(turn.reflection)
                    || hasMixedNarrativePerspective(turn.reflection)
                    || hasBrokenNarrativeSyntax(turn.reflection)
                    || integratedNarrativeMissesRequiredFunctions(turn.reflection)
                    || cardNarrativeRepeatsLockedBaseline(turn.reflection)
                    || cardDeltaNarrativeMissesRequiredFunctions(turn.reflection)
                    || usedGlobalIdentityLabel
                    || isBroadMindsetAttribution(turn.reflection)
                    || embeddedQuestionInNarrative
                // Keep a natural, evidence-bounded model narrative. The deterministic version is
                // only an outage/quality fallback, rather than the normal source of a stitched
                // field-by-field summary.
                if unusableNarrative {
                    turn.reflection = deterministicNarrativeForCurrentPhase()
                    let replacementAction: String
                    if embeddedQuestionInNarrative {
                        replacementAction = "integrated_narrative_embedded_question_replaced"
                    } else if usedGlobalIdentityLabel {
                        replacementAction = "global_identity_label_suppressed_in_narrative"
                    } else {
                        replacementAction = "field_export_narrative_replaced"
                    }
                    session.studyEvents.append(
                        .init(
                            stage: state,
                            action: replacementAction
                        )
                    )
                }
                turn.question = integratedNarrativeAccuracyCheck
                    ? accuracyQuestionForCurrentPhase()
                    : ""
            }
            if state == .actionSelection {
                let requestedCategory = recommendedCompassionatePractice().actionCategory
                session.actionSuggestions = turn.actionOptions.prefix(1).map {
                    ActionSuggestion(
                        category: $0.category,
                        description: $0.description,
                        timing: $0.timing,
                        rationale: $0.rationale
                    )
                }.filter {
                    actionDraftIsAcceptablySmall($0) &&
                    (requestedCategory == nil || $0.category == requestedCategory)
                }
                if session.actionSuggestions.isEmpty {
                    session.actionSuggestions = fallbackActions()
                }
            }
            let visible: String
            if state == .actionSelection {
                visible = formattedActionDrafts()
            } else {
                visible = state == .summary && turn.visibleText.isEmpty
                    ? deterministicSummary()
                    : turn.visibleText
            }
            if !visible.isEmpty {
                await streamAssistant(visible)
                guard responseContextIsCurrent(
                    expectedSessionID: expectedSessionID,
                    expectedStage: expectedStage,
                    expectedWorkflowPhase: expectedWorkflowPhase
                ) else { return }
                session.dialogueProgress.record(questionGoal: goalType, question: turn.question)
            }
        } catch {
            guard responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage,
                expectedWorkflowPhase: expectedWorkflowPhase
            ) else { return }
            if state == .summary {
                await streamAssistant(deterministicSummary())
                return
            }
            retryTarget = .dialogue(
                state: state,
                goal: goal,
                authority: authority,
                requiresIntegratedNarrative: requiresIntegratedNarrative,
                integratedNarrativeAccuracyCheck: integratedNarrativeAccuracyCheck,
                trackingCuesOverride: trackingCuesOverride
            )
            canRetry = true
            if requiresIntegratedNarrative {
                await streamAssistant(
                    [
                        deterministicNarrativeForCurrentPhase(),
                        integratedNarrativeAccuracyCheck
                            ? accuracyQuestionForCurrentPhase()
                            : "",
                    ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                )
            } else if state == .actionSelection {
                session.actionSuggestions = fallbackActions()
                await streamAssistant(formattedActionDrafts())
            } else {
                await streamAssistant(fallbackQuestion(for: state))
            }
        }
    }

    private func accuracyQuestionForCurrentPhase() -> String {
        switch session.workflowPhase {
        case .tenderGroundingConfirmation:
            return "沿着这段理解回到当时，哪一部分现在最值得继续说？"
        case .contextConfirmation:
            return "把这些情况放回那段时间，哪一部分最影响当时的处境？"
        case .reflectionNarrativeConfirmation:
            return "带着这段整理继续看，你现在最想停留在哪一部分？"
        case .narrativeConfirmation:
            return "回看这段记录，你最想保留下来的是什么？"
        default:
            return "沿着这段理解，你现在最想继续说哪一部分？"
        }
    }

    private func storeLiteralDisclosure(_ text: String, state: ReflectionState) {
        switch state {
        case .eventDisclosure:
            if !isLowInformationBoundaryAnswer(text) {
                session.context.eventDescription = text
            } else {
                appendUnique("事件细节暂不确定", to: &session.context.uncertainties)
            }
            session.dialogueProgress.complete(.event)
        case .emotionDisclosure:
            // This stage is a narrative-detail layer. The analyzer may extract an emotion only
            // when the user's own words support it; the whole answer is not an emotion label.
            session.dialogueProgress.complete(.emotion)
        case .bodilyResponse:
            session.bodyExplorationCompleted = true
            // Keep the full answer in the transcript, but let the typed analyzer extract only
            // short physiological phrases. Storing the whole answer here used to mix emotions
            // (e.g. 羞愧) and actions (e.g. 不敢看别人) into the bodily-response field.
            if isUncertainAnswer(text) || isLowInformationBoundaryAnswer(text) {
                appendUnique("身体感受暂不确定或没有明显变化", to: &session.context.uncertainties)
            }
            session.dialogueProgress.complete(.body)
        case .selfJudgment:
            session.dialogueProgress.complete(.selfJudgment)
            if isUncertainAnswer(text) || isLowInformationBoundaryAnswer(text) {
                session.personalMeaningExplorationCompleted = true
                appendUnique("这件事背后的个人意义暂不确定", to: &session.context.uncertainties)
                session.dialogueProgress.complete(.personalMeaning)
            } else if personalMeaningResponseIsSubstantive(text) {
                session.context.personalMeaning = text.trimmingCharacters(in: .whitespacesAndNewlines)
                session.personalMeaningExplorationCompleted = true
                session.dialogueProgress.complete(.personalMeaning)
            }
        case .contextDisclosure:
            if !isUncertainAnswer(text) { appendUnique(text, to: &session.context.contextualConstraints) }
            else { appendUnique("其他情境因素暂不确定", to: &session.context.uncertainties) }
            session.dialogueProgress.complete(.context)
        default:
            break
        }
    }

    private func mergeAnalysis(_ analysis: ContextAnalysis) {
        let value = analysis.validated
        let userEvidence = comparableText(
            session.messages
                .filter { $0.role == .user }
                .map(\.content)
                .joined(separator: " ")
        )
        let groundedRelations = value.resolvedSemanticRelations.filter { relation in
            [.userStated, .userConfirmed].contains(relation.status) &&
            relation.confidence >= 0.6 &&
            !relation.evidence.isEmpty &&
            relation.evidence.allSatisfy { fragment in
                let clean = comparableText(fragment)
                return clean.count >= 2 && userEvidence.contains(clean)
            }
        }
        func isUserSupported(_ candidate: String) -> Bool {
            let clean = comparableText(candidate)
            guard !clean.isEmpty else { return false }
            if userEvidence.contains(clean) { return true }
            return groundedRelations.contains { relation in
                [relation.source, relation.target].contains { endpoint in
                    let endpointText = comparableText(endpoint)
                    return endpointText.count >= 2 &&
                        (endpointText.contains(clean) || clean.contains(endpointText))
                }
            }
        }

        if session.context.eventDescription == nil,
           let event = value.eventDescription,
           isUserSupported(event) {
            session.context.eventDescription = event
        }
        merge(
            value.emotions.filter {
                userEvidence.contains(comparableText($0)) && isSupportedEmotionExtraction($0)
            },
            into: &session.context.emotions
        )
        merge(
            value.bodilyResponses.filter {
                userEvidence.contains(comparableText($0)) && isSupportedBodyExtraction($0)
            },
            into: &session.context.bodilyResponses
        )
        if session.context.selfJudgment == nil,
           let judgment = value.selfJudgment,
           userEvidence.contains(comparableText(judgment)) {
            session.context.selfJudgment = judgment
        }
        merge(
            value.contextualConstraints.filter(isUserSupported),
            into: &session.context.contextualConstraints
        )
        merge(
            value.personalContributions.filter(isUserSupported),
            into: &session.context.personalContributions
        )
        merge(
            value.possibleImpactOnOthers.filter(isUserSupported),
            into: &session.context.possibleImpactOnOthers
        )
        merge(
            value.possibleBoundaryConcerns.filter(isUserSupported),
            into: &session.context.possibleBoundaryConcerns
        )
        merge(value.possibleUnmetNeeds.filter(isUserSupported), into: &session.context.unmetNeeds)
        merge(
            value.possibleRepeatingPatterns.filter(isUserSupported),
            into: &session.context.repeatingPatterns
        )
        merge(value.uncertainties.filter(isUserSupported), into: &session.context.uncertainties)
        if groundedRelations.contains(where: { $0.kind == .controllablePart }) {
            session.context.presentAgency = value.presentAgency
        }
        if groundedRelations.contains(where: {
            [.eventExperience, .conditionCapacity, .uncertainty].contains($0.kind)
        }) {
            session.context.pastControllability = value.pastControllability
        }
    }

    private func syncTrackingContext() {
        let savedTrackingInterpretations = (session.context.confirmedTrackingInsights ?? []).reduce(
            into: [UUID: String]()
        ) { values, item in
            if let interpretation = item.userInterpretation {
                values[item.insightID] = interpretation
            }
        }
        for index in session.trackingCues.indices {
            guard var insight = session.trackingCues[index].insight else { continue }
            insight.userRelevance = session.trackingCues[index].relevance
            session.trackingCues[index].insight = insight
        }
        session.context.confirmedTrackingCues = session.trackingCues.filter { $0.relevance == .relevant }
        session.context.rejectedTrackingCueIDs = Set(
            session.trackingCues.filter { $0.relevance == .irrelevant }.map(\.id)
        )
        session.context.confirmedTrackingInsights = session.trackingCues.compactMap { cue in
            guard cue.relevance == .relevant, let insight = cue.insight else { return nil }
            return ConfirmedTrackingContext(
                insightID: insight.id,
                observation: cue.neutralDescription,
                userInterpretation: savedTrackingInterpretations[insight.id],
                relevance: .relevant
            )
        }
        session.context.uncertainties.removeAll { $0.hasPrefix("Tracking uncertainty: ") }
        if session.trackingCues.contains(where: { $0.relevance == .uncertain }) {
            appendUnique("Tracking uncertainty: 用户没有确认这条记录与经历相关", to: &session.context.uncertainties)
        }
    }

    /// Recomputes the measurement-free contextual state from local deterministic insights. A
    /// repeated read in the same session preserves a prior user disposition only when the same
    /// coarse state remains available; raw measurements and metric names never enter this object’s
    /// dialogue-facing hypothesis.
    private func refreshContextualLoadInference() {
        let previous = session.contextualLoadInference
        let analysis = SelfTrackingAnalysis(
            insights: session.trackingCues.compactMap(\.insight),
            patternCandidates: []
        )
        var inference = analysis.contextualLoadInference()
        if let previous,
           previous.state == inference.state,
           previous.relevance != .notReviewed {
            inference.relevance = previous.relevance
        }
        session.contextualLoadInference = inference
        session.studyEvents.append(
            .init(
                stage: session.stage,
                action: "contextual_load_inference_\(inference.state.rawValue)_\(inference.confidence.rawValue)"
            )
        )
    }

    private func preferredTrackingCandidates() -> [TrackingCue] {
        if let inference = session.contextualLoadInference {
            guard inference.hasDialogueCue,
                  inference.relevance == .notReviewed else {
                return []
            }
            let supportingIDs = Set(inference.supportingInsightIDs)
            return session.trackingCues
                .filter { cue in
                    guard cue.relevance == .notReviewed,
                          let insightID = cue.insight?.id else { return false }
                    return supportingIDs.contains(insightID)
                }
                .sorted { trackingCandidateScore($0) > trackingCandidateScore($1) }
                .prefix(1)
                .map { $0 }
        }

        // Compatibility for a saved session created before contextual-load inference existed.
        let eligible = session.trackingCues.filter { cue in
            guard cue.relevance == .notReviewed, let insight = cue.insight else {
                return false
            }
            // Fewer items written into EventKit do not mean the person had fewer tasks or less
            // pressure. Unlike a fuller recorded schedule, this direction has no safe contextual
            // reading for the conversation, so retain it in the data view but do not promote it
            // into the bounded reflection bundle.
            if insight.metric == .calendarLoad {
                return insight.validSampleCount > 0 && (insight.absoluteDifference ?? 0) > 0
            }
            return insight.validSampleCount > 0
        }
        return eligible.rankedBackgroundCues(maximumCount: 4, maximumPerDomain: 1)
    }

    private func trackingCandidateScore(_ cue: TrackingCue) -> Int {
        guard let insight = cue.insight else { return 0 }
        let strength: Int = switch insight.strength {
        case .persistentPattern: 30
        case .baselineComparison: 20
        case .descriptiveOnly: 10
        }
        let confidence: Int = switch insight.confidence {
        case .high: 3
        case .moderate: 2
        case .low: 1
        }
        return strength + confidence
    }

    private func trackingIdentity(for cue: TrackingCue) -> String {
        let metric = cue.insight?.metric.rawValue ?? "none"
        let startDay = cue.startDate.map { Int($0.timeIntervalSince1970 / 86_400) } ?? -1
        let endDay = cue.endDate.map { Int($0.timeIntervalSince1970 / 86_400) } ?? -1
        return "\(cue.source.rawValue)|\(metric)|\(startDay)|\(endDay)"
    }

    private func trackingRelevance(from text: String) -> TrackingCueRelevance {
        let clean = comparableText(text)
        let negative = [
            "不相关", "没关系", "没有关系", "不太符合", "不符合", "不贴近", "不太贴近",
            "对不上", "没什么关联", "不觉得有关", "不是这个情况", "不对",
        ]
        if negative.contains(where: { clean.contains(comparableText($0)) }) { return .irrelevant }
        let qualifiedPositive = [
            "有点关系", "有一些关系", "有些关系", "可能相关", "可能有关系", "可能有点关系",
            "部分相关", "有关系但", "相关但", "符合一部分", "有点符合",
        ]
        if qualifiedPositive.contains(where: { clean.contains(comparableText($0)) }) {
            return .relevant
        }
        let authoredEffect = [
            "有影响", "有一点影响", "可能有影响", "可能有一点影响", "让我更难",
            "会让我", "确实更难", "更难", "更难保持", "更难开始", "更难继续", "反应慢",
            "更没精神", "更容易",
        ]
        if authoredEffect.contains(where: { clean.contains(comparableText($0)) }) {
            return .relevant
        }
        let uncertain = [
            "不知道", "不确定", "说不准", "可能", "也许", "不清楚", "还没想好", "不一定",
        ]
        if uncertain.contains(where: { clean.contains(comparableText($0)) }) { return .uncertain }
        let positive = [
            "相关", "有关系", "是的", "对的", "对得上", "符合", "贴近", "确实",
            "差不多", "有点像",
        ]
        if positive.contains(where: { clean.contains(comparableText($0)) }) ||
            ["对", "是", "嗯", "嗯嗯", "有"].contains(clean) {
            return .relevant
        }
        return .uncertain
    }

    private func isUserTrackingStateDescription(_ text: String) -> Bool {
        let clean = comparableText(text)
        let markers = [
            "没劲", "没精神", "没力气", "提不起劲", "疲惫", "疲劳", "很累", "累",
            "紧绷", "压力大", "压力比较大", "睡得少", "睡不好", "睡不稳", "入睡困难",
            "难入睡", "恢复不好", "没有精神", "状态差",
        ]
        return markers.contains { clean.contains(comparableText($0)) }
    }

    private func isHealthTrackingSource(_ source: TrackingSource) -> Bool {
        switch source {
        case .healthSleep, .healthSteps, .healthHeartRate, .healthHRV:
            return true
        case .calendarLoad:
            return false
        }
    }

    private func trackingRelevance(
        for cue: TrackingCue,
        from text: String,
        bundleCount: Int
    ) -> TrackingCueRelevance {
        if bundleCount <= 1 {
            if isUserTrackingStateDescription(text), isHealthTrackingSource(cue.source) {
                return .relevant
            }
            return trackingRelevance(from: text)
        }
        let clean = comparableText(text)
        let broadPositive = [
            "这些都相关", "这些都符合", "都相关", "都符合", "整体相关", "整体符合",
            "全部相关", "全部符合", "整体对得上", "这些对得上",
        ].contains { clean.contains(comparableText($0)) }
            || ["对得上", "符合", "贴近", "确实", "是的", "对"].contains(clean)
        if broadPositive { return .relevant }
        let broadNegative = [
            "这些都不相关", "这些都不符合", "都不相关", "都不符合", "全部不相关",
            "全部不符合", "整体对不上", "这些对不上", "没有影响", "没影响",
            "关系不大", "没什么关系",
        ].contains { clean.contains(comparableText($0)) }
            || ["对不上", "不符合", "不贴近", "不相关"].contains(clean)
        if broadNegative { return .irrelevant }
        let broadEffect = [
            "有影响", "有一点影响", "可能有影响", "可能有一点影响", "让我更难",
            "会让我", "确实更难", "更难", "更难保持", "更难开始", "更难继续", "反应慢",
            "更没精神", "更容易",
        ].contains { clean.contains(comparableText($0)) }

        let sourceWords: [String] = switch cue.source {
        case .healthSleep: ["睡眠", "睡觉", "作息"]
        case .calendarLoad: ["日程", "安排", "会议"]
        case .healthSteps: ["步数", "活动", "运动"]
        case .healthHeartRate: ["静息心率", "心率", "身体记录"]
        case .healthHRV: ["hrv", "心率变异", "身体记录"]
        }
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: "，。；、,;\n"))
        guard let clause = clauses.first(where: { part in
            let normalized = comparableText(part)
            return sourceWords.contains { normalized.contains(comparableText($0)) }
        }) else {
            // A concrete answer to the combined bundle-level impact question applies to the
            // bundle unless the person separately names particular domains. A vague agreement
            // still remains uncertain.
            if isUserTrackingStateDescription(text), isHealthTrackingSource(cue.source) {
                return .relevant
            }
            return broadEffect ? .relevant : .uncertain
        }
        return trackingRelevance(from: clause)
    }

    /// A pending card-consent confirmation is an application capability gate, not an open semantic
    /// reflection question. Resolve an unambiguous acceptance locally so malformed Planner JSON can
    /// never prevent the already-authorized random draw. Ambiguous replies and every refusal still
    /// go through the dialogue path, which can answer questions or continue without a card.
    @discardableResult
    private func acceptExplicitProtocolCardConsentIfNeeded(
        _ text: String,
        replyingTo userMessageID: UUID
    ) -> Bool {
        guard session.usesLLMTurnController,
              session.condition.usesCard,
              session.protocolStage == .cardConsent,
              session.semanticMemory.nextPrompt?.kind == .confirmationRequest,
              session.semanticMemory.nextPrompt?.target == .cardConsent,
              session.card == nil,
              userAcceptsCard(text) else {
            return false
        }
        session.studyEvents.append(
            .init(stage: session.stage, action: "card_consent_acceptance_recognized_locally")
        )
        launchPersistedModelResponse(replyingTo: userMessageID) { model in
            await model.commitExplicitCardConsent()
        }
        return true
    }

    private func commitExplicitCardConsent() async {
        defer { finishTypingForCurrentResponse() }
        let referenceID = session.semanticMemory.nextPrompt?.referenceID
        let plan = LLMTurnResponsePlan(
            requestedStage: .cardConsent,
            localAction: .init(kind: .drawRandomCard),
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardConsent,
                decision: .accepted,
                referenceID: referenceID
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .acknowledgeCardConsent,
            replyGuidance: ""
        )
        do {
            let validatedPlan = try protocolController.validate(plan, for: session)
            let response = LLMTurnControllerResponse(
                requestedStage: validatedPlan.requestedStage,
                localAction: validatedPlan.localAction,
                memoryUpdate: validatedPlan.memoryUpdate,
                resolvedConfirmation: validatedPlan.resolvedConfirmation,
                nextPrompt: validatedPlan.nextPrompt,
                replyIntent: validatedPlan.replyIntent,
                reply: "local_card_draw_authorization"
            )
            let validatedResponse = try protocolController.validate(response, for: session)
            try await applyValidatedProtocolResponse(
                validatedResponse,
                appendVisibleReply: false
            )
            session.studyEvents.append(
                .init(stage: session.stage, action: "card_consent_accepted_locally")
            )
        } catch {
            presentRecoverableProtocolPause(
                error: error,
                action: "card_consent_local_transaction_failed",
                retry: .planner(
                    correction: structuredProtocolCorrection(
                        for: error,
                        permissions: protocolController.permissions(for: session)
                    ),
                    permissions: protocolController.permissions(for: session)
                )
            )
        }
    }

    /// An exact, unqualified acceptance of the currently visible candidate reading resolves an
    /// application-owned confirmation gate. Handling only this narrow case locally avoids a
    /// Planner JSON round trip for a decision the person has already stated plainly. Any added
    /// correction, reservation, rejection, question, or uncertainty still goes through the LLM
    /// so Swift never decides the meaning of a substantive response.
    @discardableResult
    private func acceptExplicitProtocolCardMappingIfNeeded(
        _ text: String,
        replyingTo userMessageID: UUID
    ) -> Bool {
        guard session.usesLLMTurnController,
              session.condition.usesCard,
              session.protocolStage == .cardReflection,
              session.cardGuidanceShared,
              session.semanticMemory.cardNegotiatedMeaning?
                  .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              session.semanticMemory.nextPrompt?.kind == .confirmationRequest,
              session.semanticMemory.nextPrompt?.target == .cardMapping,
              isUnambiguousCardMappingAcceptance(text) else {
            return false
        }

        session.studyEvents.append(
            .init(stage: session.stage, action: "card_mapping_explicit_acceptance_recognized_locally")
        )
        isTyping = true
        launchResponse(replyingTo: userMessageID) { model in
            await model.commitExplicitCardMappingAcceptance()
        }
        return true
    }

    private func isUnambiguousCardMappingAcceptance(_ text: String) -> Bool {
        let clean = comparableText(text)
        let exactAcceptances = [
            "贴切", "贴近", "准确", "对", "是的", "可以", "我同意", "我认可",
            "我觉得贴切", "我觉得贴近", "这个理解贴切", "这个理解贴近",
            "这个方向可以",
        ]
        return exactAcceptances.contains(clean)
    }

    private func commitExplicitCardMappingAcceptance() async {
        let referenceID = session.semanticMemory.nextPrompt?.referenceID
        let plan = LLMTurnResponsePlan(
            requestedStage: .directReflection,
            localAction: .none,
            memoryUpdate: .init(),
            resolvedConfirmation: .init(
                target: .cardMapping,
                decision: .accepted,
                referenceID: referenceID
            ),
            nextPrompt: TurnNextPrompt.none,
            replyIntent: .directCandidReflection,
            replyGuidance: "静默提交用户对当前候选解读的明确接受"
        )

        do {
            let validatedPlan = try protocolController.validate(plan, for: session)
            let response = LLMTurnControllerResponse(
                requestedStage: validatedPlan.requestedStage,
                localAction: validatedPlan.localAction,
                memoryUpdate: validatedPlan.memoryUpdate,
                resolvedConfirmation: validatedPlan.resolvedConfirmation,
                nextPrompt: validatedPlan.nextPrompt,
                replyIntent: validatedPlan.replyIntent,
                reply: "local_card_mapping_explicit_acceptance"
            )
            let validatedResponse = try protocolController.validate(response, for: session)
            try await applyValidatedProtocolResponse(
                validatedResponse,
                appendVisibleReply: false
            )
            session.studyEvents.append(
                .init(stage: session.stage, action: "card_mapping_explicit_acceptance_committed_locally")
            )
            session.studyEvents.append(
                .init(stage: session.stage, action: "card_mapping_resolution_committed_before_continuation")
            )
            await processProtocolTurn(trigger: .protocolContinuation)
        } catch {
            session.studyEvents.append(
                .init(stage: session.stage, action: "card_mapping_local_acceptance_fell_back_to_planner")
            )
            await processProtocolTurn(trigger: .userMessage)
        }
    }

    private func userAcceptsCard(_ text: String) -> Bool {
        let clean = comparableText(text)
        let declines = [
            "不抽", "先别抽", "先不抽", "不要抽", "不想抽", "不用卡", "先不用卡",
            "不愿意", "不想试", "先不试", "不要试",
        ]
        if declines.contains(where: { clean.contains(comparableText($0)) }) { return false }
        if userExplicitlyRequestsCard(text) { return true }
        if ["可以", "好", "好的", "好啊", "好呀", "愿意", "试试"].contains(clean) {
            return true
        }
        return ["我愿意", "愿意试", "想试试", "可以试", "试试看"].contains {
            clean.contains(comparableText($0))
        }
    }

    private func userDeclinesCard(_ text: String) -> Bool {
        let clean = comparableText(text)
        let declines = [
            "不抽", "先别抽", "先不抽", "不要抽", "不想抽", "不用卡", "先不用卡",
            "不愿意", "不想试", "先不试", "不要试",
        ]
        return declines.contains { clean.contains(comparableText($0)) }
    }

    private func userExplicitlyRequestsCard(_ text: String) -> Bool {
        let clean = comparableText(text)
        let declines = [
            "不抽", "先别抽", "先不抽", "不要抽", "不想抽", "不用卡", "先不用卡",
            "不愿意", "不想试", "先不试", "不要试",
        ]
        if declines.contains(where: { clean.contains(comparableText($0)) }) { return false }
        let explicitAccepts = [
            "抽卡", "抽一张", "可以抽", "愿意抽", "来一张", "抽吧", "抽完", "抽个",
            "抽张卡", "抽张", "来张卡", "看张卡", "看一张卡", "选张卡", "换个角度看看",
            "换一张卡", "换张卡", "再抽一张", "再抽张卡", "重新抽一张", "重新抽卡", "重抽",
        ]
        return explicitAccepts.contains { clean.contains(comparableText($0)) }
    }

    private func shouldStartCardImmediately(from text: String) -> Bool {
        guard session.stage == .readinessCheck,
              session.workflowPhase == .contextConfirmation,
              session.contextSummaryConfirmed,
              session.trackingReviewCompleted else { return false }
        return userExplicitlyRequestsCard(text)
    }

    private func userReportsMissingCard(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "没有看到卡片", "没看到卡片", "看不到卡片", "卡片没出来", "卡片没有出来",
            "没有显示卡片", "没显示卡片", "卡片没显示", "卡片没有显示",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func userWantsToEnd(_ text: String) -> Bool {
        let clean = comparableText(text)
        let exact = ["先停", "暂停", "结束", "不聊了", "到这里", "今天先到这里"]
        if exact.contains(clean) { return true }
        return ["我想停下", "这次先到这里", "先结束这次", "今天不聊了"].contains {
            clean.contains(comparableText($0))
        }
    }

    /// A direct request for practical support is an interaction intent, not an answer to the
    private var canHonorPracticeSuggestionRequest: Bool {
        guard session.stage == .attributionReflection else { return false }
        return [
            .reflectionNarrativeConfirmation, .optionalAction, .narrativeConfirmation,
        ].contains(session.workflowPhase)
    }

    private func processExplicitPracticeSuggestionRequest(
        responsePlan: ResponsePlan
    ) async {
        guard canHonorPracticeSuggestionRequest else { return }
        session.studyEvents.append(
            .init(
                stage: .attributionReflection,
                action: "semantic_practice_request_overrode_late_gate"
            )
        )
        setWorkflowPhase(.optionalAction, action: "optional_action_requested_explicitly")

        let resolved = recommendedCompassionatePractice()
        await presentActionDrafts(
            managesTyping: false,
            responsePlan: responsePlan,
            // Asking for support shows readiness for a low-demand option, but not evidence of
            // harm, responsibility, a boundary, or a change target. When no other direction is
            // grounded, Swift permits care only and the Writer still phrases the actual draft.
            practiceOverride: resolved == .noAction ? .care : resolved
        )
    }

    private func userIsStillAnswering(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = ["我还没说完", "还没说完", "我想继续说", "让我再说一点", "先别往下", "先听我说完"]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func integratedNarrativeNeedsRevision(_ text: String) -> Bool {
        let clean = comparableText(text)
        let corrections = [
            "不贴近", "不太贴近", "不准确", "不太准确", "不对", "不太对", "不是这样",
            "不符合", "不太符合", "要改", "需要改", "其实", "更像", "应该是", "准确地说",
        ]
        return corrections.contains { clean.contains(comparableText($0)) }
    }

    /// During an accuracy check, a user may supply missing evidence without explicitly saying
    /// “not accurate”. Preserve that contribution and regenerate the summary instead of asking
    /// them to operate the confirmation flow a second time.
    private func isSubstantiveSummaryAddition(_ text: String) -> Bool {
        let clean = comparableText(text)
        guard clean.count >= 4,
              !userAffirmsAccuracy(text),
              !integratedNarrativeNeedsRevision(text),
              !isLowInformationBoundaryAnswer(text),
              !isClarificationRequest(text),
              !userExplicitlyRequestsCard(text),
              !userDeclinesCard(text) else {
            return false
        }
        return true
    }

    private func plainClarification(for state: ReflectionState) -> String {
        let previousUserText = session.messages.reversed().first {
            $0.role == .user && !isClarificationRequest($0.content)
        }?.content
        let knownFact = session.context.selfJudgment
            ?? session.context.eventDescription
            ?? session.context.contextualConstraints.first
            ?? previousUserText
        let anchor = knownFact.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(42))
        }.flatMap { $0.isEmpty ? nil : $0 }

        switch state {
        case .eventDisclosure:
            return "我刚才问得太绕了。我只是想先知道一件具体发生过的事，不需要分析。你可以从最近一次开始说。"
        case .selfJudgment:
            if let anchor {
                return "我换个直白的说法。你已经说到“\(anchor)”。我想问的只是：当时脑子里最先冒出的那句话是什么？"
            }
            return "我想问的是，当时脑子里最先冒出的那句话，不是让你分析自己。"
        case .contextDisclosure:
            return "我想问的是：当时除了这件事，还有没有别的事也占着你的时间或精力。"
        case .trackingReview:
            return "我只是在问：刚才那条近期记录，和你自己描述的状态是否相关。它不能说明原因，也不能判断责任；你可以说相关、不相关，或者不确定。"
        case .readinessCheck:
            return "刚才那段只是暂时整理。放回当时的经历，你最想接着说哪一部分？"
        case .cardInterpretation:
            if session.workflowPhase == .cardObservation {
                return "我只是想听你描述画面里正在发生什么，不需要解释卡片，也没有标准答案。"
            }
            return "我是在顺着你刚才的画面描述，再问清一个细节；现在还不用联系现实经历。"
        case .attributionReflection:
            switch session.workflowPhase {
            case .cardConnection:
                return "我是在问：按你自己的画面理解，它有没有让你想到刚才那件事里的某一部分。没有联系也可以。"
            case .cardMappingConfirmation:
                return "沿着刚才的画面—现实联系，哪一部分最明显？也可以换成自己的说法或直接说没有关系。"
            case .cardMeaningShift:
                return "我是在问：把你对画面的理解和刚才那件事放在一起后，你现在会不会换一种方式理解那件事或当时的自己。没有变化也可以。"
            case .candidCircumstances:
                return "我是在问：这件事里有哪些现实困难需要被放回来一起看，而不是都变成对自己的批评。"
            case .candidAgency:
                return "我是在问：在已经说清楚的事实里，哪一部分是你认为自己可以负责或改变的。没有或不确定也可以。"
            case .reflectionNarrativeConfirmation, .narrativeConfirmation:
                return "刚才那段整理之后，你最想保留或继续谈的是哪一部分？"
            case .optionalAction, .actionConfirmation:
                return "我给的是一两个很小的备选方向。你可以选一个、直接改掉，也可以都不选。"
            default:
                return "我刚才问得不够直白。你可以只回答眼前这个问题，不需要分析更多。"
            }
        case .emotionDisclosure, .bodilyResponse, .tenderGrounding, .tenderExploration:
            if let anchor {
                return "我刚才说得太抽象了。先不分析原因，就接着你已经说的“\(anchor)”讲后来具体发生了什么。"
            }
            return "我刚才说得太抽象了。先不用分析原因，接着说刚才那件事后来发生了什么就可以。"
        default:
            return "我刚才说得太抽象了。先不用找新的答案，接着说刚才那件事后来发生了什么就可以。"
        }
    }

    private func tenderConversationRepairMessage() -> String {
        if let event = session.context.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !event.isEmpty {
            return "你说得对，我刚才的问题重复了。你已经说到“\(String(event.prefix(42)))”。我先不再追着问这个。"
        }
        return "你说得对，我刚才的问题重复了。我先停在这里。"
    }

    private func lockConfirmedBaselineNarrative() {
        let visible = session.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let prose = visible
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("吗") && !$0.contains("哪里不对") }
            .prefix(5)
            .joined(separator: "。")
        session.lockedBaselineNarrative = prose.isEmpty
            ? deterministicContextSummary()
            : String(prose.prefix(700)) + "。"
        session.studyEvents.append(
            .init(stage: .readinessCheck, action: "tracking_baseline_narrative_locked")
        )
    }

    private func validatedResponsePlan(
        for state: ReflectionState,
        analysis: ContextAnalysis?
    ) -> ResponsePlan? {
        guard let analysis else { return nil }
        return responsePlanValidator.validate(
            analysis.validated.responsePlan,
            analysis: analysis,
            state: state,
            workflowPhase: session.workflowPhase,
            messages: session.messages
        )
    }

    private func responsePlanningContext(for state: ReflectionState) -> ResponsePlanningContext {
        ResponsePlanningContext(
            state: state,
            workflowPhase: session.workflowPhase,
            allowedFunctions: Array(
                responsePlanValidator.allowedFunctions(
                    for: state,
                    workflowPhase: session.workflowPhase
                )
            ),
            shouldAskQuestion: nil
        ).validated
    }

    private func analyzeCurrentUserTurn(for state: ReflectionState) async -> ContextAnalysis {
        await analyzer.analyze(
            context: session.context,
            messages: session.messages,
            planningContext: responsePlanningContext(for: state)
        )
    }

    /// During disclosure, the plan—not an empty legacy field—selects the next conversational
    /// function. Swift still maps that function to an internal state and can reject any phase
    /// advance the plan did not earn.
    private func plannedDisclosureState(from plan: ResponsePlan?) -> ReflectionState? {
        guard let plan else { return nil }
        switch plan.function {
        case .exploreLivedExperience:
            return .emotionDisclosure
        case .clarifyPersonalMeaning:
            return .selfJudgment
        case .clarifyCircumstances:
            return .contextDisclosure
        case .synthesizeTenderUnderstanding:
            return structuredDisclosureIsSufficient ? .trackingPermission : nil
        case .closeWithoutQuestion:
            return nil
        default:
            return nil
        }
    }

    private func responsePlanGoal(_ plan: ResponsePlan) -> String {
        """
        Follow the locally validated ResponsePlan function \(plan.function.rawValue). Its semantic
        focus is supplied in the typed responsePlan and must be paraphrased rather than displayed.
        \(plan.shouldAskQuestion
            ? "Ask exactly one natural question whose function is: \(plan.questionIntent)."
            : "Do not ask a question in this turn.")
        Acknowledge the latest user meaning before moving forward. Use only the cited literal
        evidence and grounded relation kinds. Do not collect a missing field, change phase, add a
        diagnosis, assign responsibility, or substitute a generic question.
        """
    }

    private func questionGoal(for state: ReflectionState) -> String {
        switch state {
        case .emotionDisclosure:
            return "the event is already known. Ask one plain question about the user's felt experience in that moment, using their latest words when possible. Do not ask what the other person said, ask for another event detail, or turn a global self-judgment into a project-progress distinction. Do not force optimism or ask them to choose which topic to answer"
        case .bodilyResponse: return "ask one open, ordinary question about what the user feels when thinking about the event now. Do not require a bodily reaction, ask where a feeling is located, or offer a sensation menu. An emotion, thought, bodily response, or no obvious feeling are all complete answers"
        case .selfJudgment: return "ask one plain question about what the situation led the user to conclude about themselves or what outcome it made them fear. If they used a global label, ask for the concrete concern behind it without repeating it as fact; do not ask for another moment, attempt, adjustment detail, or hoped-for technical result"
        case .contextDisclosure: return "ask what else was taking their attention or energy only if it is genuinely new; never return to technical attempts, adjustment details, or what they expected to work"
        default: return "invite one concrete detail"
        }
    }

    private func workflowEvidenceForPrompt() -> String {
        let cardPhase = session.condition.usesCard &&
            [.cardConnection, .cardMappingConfirmation, .candidCircumstances, .cardMeaningShift,
             .candidAgency, .reflectionNarrativeConfirmation, .optionalAction,
             .actionConfirmation, .narrativeConfirmation]
            .contains(session.workflowPhase)
        var values: [(String, String?)]
        if cardPhase {
            values = [
                ("Locked baseline narrative — reference briefly, never reproduce", session.lockedBaselineNarrative),
                ("Matched image relation", session.cardGroundingMatch?.imageRelation),
                ("Matched reality relation", session.cardGroundingMatch?.realityRelation),
                ("User-confirmed card mapping", session.cardMappingConfirmed ? session.cardConfirmedMapping : nil),
                ("Card-derived delta", session.cardDerivedDeltaNarrative),
                ("User-authored perspective response (which may explicitly be no change)", session.cardMeaningShiftResponse),
                ("User-authored tender distinction", session.candidCircumstancesResponse),
                ("User-authored fierce focus", session.candidAgencyResponse),
                ("Pending user-authored action", session.pendingUserAuthoredAction),
            ]
        } else {
            values = [
                ("User-authored personal meaning", session.context.personalMeaning),
                ("User-confirmed tracking-to-situation link", session.trackingContextLinkResponse),
                ("Pending user-authored action", session.pendingUserAuthoredAction),
            ]
        }
        if session.eventDateIsUserSpecified {
            values.append((
                "Tracking time anchor",
                "The person explicitly dated the event. Use only the event day and preceding days as the tracking window; do not use later records to explain how they entered the event."
            ))
        } else {
            values.append((
                "Tracking time language",
                "No event date was supplied. Say 最近 or 这段时间, never invent a specific day."
            ))
        }
        let evidence = values.compactMap { label, value -> String? in
            guard let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !clean.isEmpty else { return nil }
            return "\(label): \(String(clean.prefix(180)))"
        }
        return evidence.isEmpty ? "" : "Confirmed workflow evidence: [\(evidence.joined(separator: " | "))]."
    }

    private func dialoguePromptEvidence(
        cardDeltaOnly: Bool,
        responsePlan: ResponsePlan?,
        state: ReflectionState
    ) -> DialoguePromptEvidence {
        guard cardDeltaOnly else {
            var evidence = DialoguePromptEvidence.standard
            evidence.responsePlan = responsePlan
            evidence.contextualLoadCue = dialogueContextCue(for: state)
            return evidence
        }
        return DialoguePromptEvidence(
            narrativeMode: .cardDerivedDelta,
            responsePlan: responsePlan,
            lockedBaselineNarrative: session.lockedBaselineNarrative,
            cardDerivedDeltaNarrative: session.cardDerivedDeltaNarrative,
            matchedImageRelation: session.cardGroundingMatch?.imageRelation,
            matchedRealityRelation: session.cardGroundingMatch?.realityRelation,
            confirmedCardMapping: session.cardConfirmedMapping,
            tenderResponse: session.candidCircumstancesResponse,
            meaningShiftResponse: session.cardMeaningShiftResponse,
            fierceResponse: session.candidAgencyResponse,
            pendingAction: session.context.selectedAction?.acceptedByUser == true
                ? session.context.selectedAction?.description
                : session.pendingUserAuthoredAction,
            cardPhaseStartedAt: session.cardDrawRecord?.drawnAt,
            contextualLoadCue: nil
        )
    }

    private func dialogueContextCue(for state: ReflectionState) -> DialogueContextCue? {
        guard let inference = session.contextualLoadInference,
              inference.hasDialogueCue,
              let hypothesis = inference.dialogueHypothesis else {
            return nil
        }

        switch inference.relevance {
        case .notReviewed:
            guard state == .readinessCheck else { return nil }
        case .offered:
            // Current protocol owns this post-card state. The legacy dialogue path must not
            // independently repeat or reinterpret the cue.
            return nil
        case .relevant:
            if state == .cardInterpretation { return nil }
            if state == .attributionReflection,
               session.condition.usesCard,
               !session.cardMappingConfirmed {
                return nil
            }
        case .irrelevant, .uncertain:
            return nil
        }

        return DialogueContextCue(
            hypothesis: userFacingContextualHypothesis(hypothesis),
            confidence: inference.confidence,
            relevance: inference.relevance,
            usageBoundary: "这是可拒绝的不确定背景。只能保留 hypothesis 明确包含的语义范围，不得扩展为其他事实、身体状态、情绪、原因、能力、责任或建议；不得展示测量来源，也不得替用户判断其相关性。"
        )
    }

    private func userFacingContextualHypothesis(_ hypothesis: String) -> String {
        var value = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "用户近期", with: "你最近")
        value = value.replacingOccurrences(of: "用户最近", with: "你最近")
        value = value.replacingOccurrences(of: "用户", with: "你")
        return value
    }

    private func questionGoalType(
        for state: ReflectionState,
        requestedGoal: String,
        responsePlan: ResponsePlan? = nil
    ) -> QuestionGoal? {
        if let responsePlan {
            switch responsePlan.function {
            case .exploreLivedExperience: return .emotionalMeaning
            case .clarifyPersonalMeaning: return .selfTalk
            case .clarifyCircumstances, .deepenTenderUnderstanding: return .contextualPressure
            case .contextualizeTracking: return .trackingImpact
            case .developImageRelation: return .cardDevelopment
            case .connectImageToReality: return .cardConnection
            case .explorePerspectiveShift: return .perspectiveShift
            case .exploreAgencyBoundaryOrChange: return .presentAgency
            case .proposePractice: return .compassionateAction
            case .synthesizeTenderUnderstanding, .synthesizeNarrative,
                 .confirmUnderstanding, .closeWithoutQuestion:
                return nil
            }
        }
        return switch state {
        case .eventDisclosure: .specificEvent
        case .emotionDisclosure: .emotionalMeaning
        case .bodilyResponse: .bodilyExperience
        case .selfJudgment: .selfTalk
        case .contextDisclosure, .trackingPermission: .contextualPressure
        case .trackingReview:
            session.workflowPhase == .trackingContextLink ? .trackingImpact : .trackingRelevance
        case .tenderGrounding, .tenderExploration:
            requestedGoal.localizedCaseInsensitiveContains("uncertain") ? .uncertainty : .selfTalk
        case .readinessCheck: nil
        case .cardInterpretation:
            switch session.workflowPhase {
            case .cardObservation: .cardObservation
            case .cardAssociation, .cardNarrativeDeepening: .cardDevelopment
            default: .cardNarrative
            }
        case .attributionReflection:
            switch session.workflowPhase {
            case .cardConnection: .cardConnection
            case .cardMappingConfirmation: nil
            case .cardMeaningShift: .perspectiveShift
            case .candidCircumstances: .contextualPressure
            case .candidAgency: .presentAgency
            case .optionalAction, .actionConfirmation: .compassionateAction
            case .reflectionNarrativeConfirmation, .narrativeConfirmation: nil
            default: .cardConnection
            }
        case .actionSelection: .compassionateAction
        default: nil
        }
    }

    private func guardedQuestionGoal(_ requested: String, type: QuestionGoal?) -> String {
        guard let type, session.dialogueProgress.forbiddenNextGoals.contains(type) else {
            return requested
        }
        return nextUnresolvedTenderGoal()
    }

    private func nextUnresolvedTenderGoal() -> String {
        let candidates: [(ReflectionDimension, QuestionGoal, String)] = [
            (.selfJudgment, .selfTalk, "ask for the specific sentence the user says to themselves, without assuming it"),
            (.uncertainty, .uncertainty, "ask what remains uncertain without forcing fatigue versus avoidance"),
            (.context, .contextualPressure, "ask about one surrounding pressure not already discussed"),
            (.agency, .presentAgency, "ask what feels different now from what was possible then"),
            (.emotion, .emotionalMeaning, "ask what felt most painful or important in one concrete moment"),
        ]
        if let choice = candidates.first(where: {
            session.dialogueProgress.unresolvedDimensions.contains($0.0) &&
                !session.dialogueProgress.forbiddenNextGoals.contains($0.1)
        }) {
            session.dialogueProgress.nextQuestionGoal = choice.1
            return choice.2
        }
        session.dialogueProgress.nextQuestionGoal = .preferredDirection
        return "ask which direction would feel most useful now, without repeating an earlier question or offering a card"
    }

    private func fallbackQuestion(for state: ReflectionState) -> String {
        let currentPlan = validatedResponsePlan(for: state, analysis: session.latestAnalysis)
            ?? session.latestAnalysis.flatMap {
                responsePlanValidator.recoverDisclosurePlan(
                    analysis: $0,
                    state: state,
                    workflowPhase: session.workflowPhase,
                    messages: session.messages
                )
            }
        if let plan = currentPlan,
           let plannedQuestion = responsePlanFallbackQuestion(plan) {
            return plannedQuestion
        }
        switch state {
        case .emotionDisclosure:
            return emotionExperienceFallbackQuestion()
        case .bodilyResponse: return "想到这件事时，你现在有什么感受？没有特别明显的感觉也可以。"
        case .selfJudgment:
            return personalMeaningFallbackQuestion()
        case .contextDisclosure: return "那段时间，除了这件事，你还在同时处理什么？"
        case .trackingPermission: return "我会看一下已经授权的近期记录，只把它们当作背景。"
        case .trackingReview: return trackingCandidateFallbackQuestion()
        case .readinessCheck: return "把刚才这些放在一起，哪一部分最值得继续说？"
        case .attributionReflection:
            switch session.workflowPhase {
            case .cardConnection:
                return "按你刚才对画面的描述，它有没有让你想到这件事里的某一部分？没有也可以。"
            case .cardMappingConfirmation:
                if let mapping = session.cardCandidateMapping, !mapping.isEmpty {
                    return cardMappingConfirmationMessage(mapping)
                }
                return "我刚才是在提出一种可能的画面—现实联系。你可以确认、修改，或直接说没有关系。"
            case .cardMeaningShift:
                return "把这个画面和刚才那件事放在一起后，你现在会怎样理解那件事或当时的自己？没有变化也可以。"
            case .candidCircumstances:
                return "这件事里，哪些现实困难需要先被承认，而不能只归结成对自己的批评？"
            case .candidAgency:
                return "你觉得自己当时有没有更合适的做法？没有也可以。"
            case .optionalAction:
                return "你现在想为自己选一个很小的下一步吗？也可以先不决定。"
            default:
                return "顺着这段整理，哪一部分最值得继续说？也可以换个方向。"
            }
        case .eventDisclosure: return "你愿意从最近一次发生的情况说起吗？"
        case .tenderGrounding, .tenderExploration:
            return "不用勉强找答案。关于刚才那件事，你现在还想说哪一部分？"
        default: return "你想接着说什么都可以。"
        }
    }

    private func responsePlanFallbackQuestion(_ plan: ResponsePlan) -> String? {
        guard plan.shouldAskQuestion else { return nil }
        switch plan.function {
        case .exploreLivedExperience:
            return "顺着你刚才说的这段经历，现在最难受的部分是什么？"
        case .clarifyPersonalMeaning:
            return "你开始这样看自己时，最担心接下来会发生什么？"
        case .clarifyCircumstances:
            return "除了眼前的结果，当时还有什么现实情况也让这件事更难处理？"
        default:
            return nil
        }
    }

    private func trackingCandidateFallbackQuestion() -> String {
        if let cue = dialogueContextCue(for: .trackingReview) {
            let hypothesis = userFacingContextualHypothesis(cue.hypothesis)
            return "\(hypothesis) 把这个可能性放回刚才那件事里，它有没有让当时更难应对？没有也可以。"
        }
        let pendingIDs = session.pendingTrackingCueIDs.isEmpty
            ? session.pendingTrackingCueID.map { [$0] } ?? []
            : session.pendingTrackingCueIDs
        let cues = pendingIDs.compactMap { cueID in
            session.trackingCues.first(where: { $0.id == cueID })
        }
        guard !cues.isEmpty else {
            return "近期记录没有形成足够清楚的背景线索，我们先不根据它下结论。"
        }
        let observations = Array(cues
            .map(plainTrackingClause)
            .filter { !$0.isEmpty }
            .prefix(3))
        guard !observations.isEmpty else {
            return "近期记录里没有足够可靠的变化可以拿来比较，我们先不根据它下结论。"
        }
        let time = trackingTimeReference()
        let spokenObservations = naturalTrackingObservationList(observations)
        let lifeContext = trackingLifeContextCandidate()
        let stateCandidate = trackingContextLinkCandidate(for: cues)
        let impactQuestion = trackingEventImpactQuestion(candidate: stateCandidate)
        return "\(time)，\(spokenObservations)。\(lifeContext)。这些变化也可能有其他原因。\(impactQuestion)"
    }

    private func trackingSituationLinkQuestion() -> String {
        let candidate = trackingContextLinkCandidate()
        return trackingEventImpactQuestion(candidate: candidate)
    }

    private func naturalTrackingObservationList(_ observations: [String]) -> String {
        observations.enumerated().map { index, observation in
            var clause = observation
            clause = clause.replacingOccurrences(of: "睡眠比平时短一些", with: "睡得比平时短一些")
            clause = clause.replacingOccurrences(of: "睡眠比平时长一些", with: "睡得比平时长一些")
            if index > 0,
               !clause.hasPrefix("也"),
               !clause.hasPrefix("而") {
                clause = "也\(clause)"
            }
            return clause
        }.joined(separator: "，")
    }

    private func trackingLifeContextCandidate() -> String {
        "放回你刚才说的生活状态里，这些变化可能说明那段时间可用的精力、时间或生活节奏和平时不太一样"
    }

    private func trackingEventImpactQuestion(candidate: String) -> String {
        "放回刚才那件事里，你觉得\(candidate)，有没有让当时的处境更难应对？没有也可以。"
    }

    private func trackingConversationEvidence() -> String {
        let parts = session.messages.filter { $0.role == .user }.map(\.content) + [
            session.context.eventDescription,
            session.context.personalMeaning,
            session.context.contextualConstraints.joined(separator: " "),
        ].compactMap { $0 }
        return comparableText(parts.joined(separator: " "))
    }

    private func trackingContextLinkCandidate(for suppliedCues: [TrackingCue]? = nil) -> String {
        if let inference = session.contextualLoadInference,
           inference.hasDialogueCue,
           let hypothesis = inference.dialogueHypothesis {
            return userFacingContextualHypothesis(hypothesis)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        let cues = suppliedCues ?? session.context.confirmedTrackingCues
        let metrics = Set(cues.compactMap(\.insight?.metric))
        let hasShorterSleep = cues.contains {
            $0.insight?.metric == .sleepDuration &&
                ($0.insight?.absoluteDifference ?? 0) < 0
        }
        let hasLaterSleep = cues.contains {
            [.sleepTiming, .sleepWakeTime].contains($0.insight?.metric) &&
                ($0.insight?.absoluteDifference ?? 0) > 0
        }
        let hasMoreFragmentedSleep = cues.contains {
            $0.insight?.metric == .sleepContinuity &&
                ($0.insight?.absoluteDifference ?? 0) < 0
        }
        if hasShorterSleep && hasLaterSleep {
            return "最近睡得晚一些、短一些，可能还没有休息过来"
        }
        if hasShorterSleep {
            return "最近睡得比平时短一些，可能还没有休息过来"
        }
        if hasLaterSleep {
            return "最近入睡或醒来比平时晚一些，作息可能还没有调整过来"
        }
        if hasMoreFragmentedSleep {
            return "最近睡得更零碎一些，可能还没有休息过来"
        }
        if cues.contains(where: {
            $0.insight?.metric == .calendarLoad &&
                ($0.insight?.recentRecordCount ?? 0) > 0 &&
                ($0.insight?.recentTotal ?? 0) > 0
        }) {
            return "最近有一些已经排定、会占用时间的安排"
        }
        if metrics.contains(.steps) {
            return "最近走动少一些、久坐可能多一些"
        }
        let userText = comparableText(
            session.messages.filter { $0.role == .user }.map(\.content).joined(separator: " ")
        )
        if metrics.contains(.screenTime),
           ["刷手机", "刷视频", "看视频", "屏幕"].contains(where: {
               userText.contains(comparableText($0))
           }) {
            return "最近刷手机或看视频的时间多一些"
        }
        if metrics.contains(.restingHeartRate) {
            return "最近身体状态有一些变化"
        }
        return "最近生活节奏有一些变化"
    }

    private func trackingContextCandidate(for cues: [TrackingCue]) -> String {
        let metrics = Set(cues.compactMap(\.insight?.metric))
        let hasShorterSleep = cues.contains {
            guard let insight = $0.insight else { return false }
            return insight.metric == .sleepDuration && (insight.absoluteDifference ?? 0) < 0
        }
        let hasLaterSleep = cues.contains {
            $0.insight?.metric == .sleepTiming && ($0.insight?.absoluteDifference ?? 0) > 0
        }
        let hasMoreFragmentedSleep = cues.contains {
            $0.insight?.metric == .sleepContinuity && ($0.insight?.absoluteDifference ?? 0) < 0
        }
        let hasLowerRecoveryRecord = cues.contains {
            $0.insight?.metric == .heartRateVariability &&
                ($0.insight?.absoluteDifference ?? 0) < 0
        }
        let hasRecordedSchedule = cues.contains {
            $0.insight?.metric == .calendarLoad &&
                ($0.insight?.recentRecordCount ?? 0) > 0 &&
                ($0.insight?.recentTotal ?? 0) > 0
        }
        let hasChangedActivity = metrics.contains(.steps)
        let hasScreenIncrease = cues.contains {
            $0.insight?.metric == .screenTime && ($0.insight?.absoluteDifference ?? 0) > 0
        }
        let userText = comparableText(
            session.messages.filter { $0.role == .user }.map(\.content).joined(separator: " ")
        )
        let userNamedScreenBehavior = ["刷手机", "刷视频", "看视频", "屏幕"]
            .contains { userText.contains(comparableText($0)) }
        if hasRecordedSchedule {
            return "这些已排定的安排占用了一部分时间，但是否挤压了这件事仍由你判断"
        }
        if hasShorterSleep || hasLaterSleep || hasMoreFragmentedSleep {
            return "这些变化可能和最近比较累，或者还没有休息过来有关"
        }
        if hasLowerRecoveryRecord && hasChangedActivity {
            return "这些变化可能和最近比较累、久坐较多，或者还没有休息过来有关"
        }
        if hasLowerRecoveryRecord {
            return "这项变化可能和最近比较累、身体不适、运动情况或测量时间不同有关"
        }
        if hasScreenIncrease && userNamedScreenBehavior {
            return "屏幕使用变多和你说过的刷手机或视频出现在同一段时间，可以一起看看它有没有挤掉原本想留给重要事情的时间"
        }
        if hasChangedActivity {
            return "这可能和最近走动变少、久坐处理事情、身体不适或生活节奏改变有关"
        }
        return "这些变化可能和那段时间的生活节奏或身体状态有关"
    }

    private func nonRepeatingFallbackQuestion(for state: ReflectionState) -> String {
        let candidates: [String]
        switch state {
        case .emotionDisclosure, .bodilyResponse:
            candidates = [
                fallbackQuestion(for: state),
                "这件事最影响你的，是进度本身，还是你开始怎样评价自己？",
                "那次结果仍然不对时，你脑子里先冒出了什么？",
            ]
        case .selfJudgment:
            candidates = [
                fallbackQuestion(for: state),
                "那一刻，你原本希望发生什么？",
                "当时最先闪过的那句话是什么？",
            ]
        case .attributionReflection:
            switch session.workflowPhase {
            case .cardConnection:
                candidates = [
                    fallbackQuestion(for: state),
                    "你刚才说的画面，和这件事里的哪一部分有一点相像？没有也可以。",
                    "如果先不解释，这个画面有没有让你想起刚才说的某一部分？",
                ]
            case .cardMappingConfirmation:
                candidates = [
                    session.cardCandidateMapping.map(cardMappingConfirmationMessage)
                        ?? "把这个画面和现实放在一起后，最明显的是哪一部分？也可以换个方向或说没有关系。"
                ]
            case .cardMeaningShift:
                candidates = [
                    cardMeaningShiftQuestion(),
                    "这个联系让你对原来的经历多看见了什么？没有变化也可以。",
                ]
            case .candidCircumstances:
                candidates = [
                    fallbackQuestion(for: state),
                    "哪些现实情况需要先放回这件事里一起看？",
                ]
            case .candidAgency:
                candidates = [
                    fallbackQuestion(for: state),
                    "你觉得自己当时有没有更合适的做法？没有也可以。",
                ]
            default:
                candidates = [fallbackQuestion(for: state)]
            }
        case .cardInterpretation:
            candidates = [
                "是什么让你对画面里的这个角色有了不同的判断？",
                "画面里哪一点让你开始觉得有些不确定？",
                "沿着你刚才的说法，这个角色接下来可能会做什么？",
            ]
        default:
            candidates = [
                fallbackQuestion(for: state),
                "关于刚才那件事，你现在还想说哪一部分？",
                "刚才哪一部分对你的影响最大？",
            ]
        }
        return candidates.first(where: { !isSubstantiallyRepeated($0) })
            ?? "刚才那件事后来对你有什么影响？"
    }

    private func trackingSourceList(_ cues: [TrackingCue]) -> String {
        let names = cues.prefix(2).map { cue in
            switch cue.source {
            case .healthSleep: "那段时间的睡眠"
            case .healthHeartRate, .healthHRV: "身体记录"
            case .healthSteps: "活动记录"
            case .calendarLoad: "日程安排"
            }
        }
        return Array(Set(names)).sorted().joined(separator: "和")
    }

    private func trackingTimeReference() -> String {
        guard session.eventDateIsUserSpecified else { return "最近" }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: session.context.eventDate)
        let day = calendar.component(.day, from: session.context.eventDate)
        return "\(month)月\(day)日当天及之前几天"
    }

    /// “心态” can be a meaningful starting point, but by itself it is not a circumstance,
    /// cause, or responsibility statement.  Keep it out of the integrated narrative until the
    /// person has translated it into a concrete limitation or behaviour.
    private func isBroadMindsetAttribution(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "主要就是自己心态", "就是自己心态", "主要是心态", "就是心态",
            "心态问题", "自己的心态", "心态不好", "心态吧", "心理状态",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    /// The fierce turn is earned by user material, not by the fact that the workflow has reached
    /// a later phase. A feeling, a harsh self-label, a difficult outcome, or a tracking cue is
    /// never enough on its own. This keeps "acceptance and soothing" available when the person is
    /// still trying to make sense of what hurt, and limits candid change work to something they
    /// have actually placed on the table.
    private var hasUserSupportedFierceFocus: Bool {
        if let analysis = session.latestAnalysis?.validated,
           analysis.confidence > 0 {
            if !groundedSemanticRelations(
                kinds: [.behaviorImpact, .boundaryNeed, .controllablePart],
                in: analysis
            ).isEmpty {
                return true
            }
            if analysis.userAdmittedBehavior,
               analysis.confidence >= 0.65,
               literalEvidenceIsSupported(analysis.behaviorEvidence) {
                return true
            }
            return false
        }

        // Emergency compatibility for a provider outage or a legacy test analyzer with no
        // confidence. Do not classify the situation by topic or behavior keywords; only retain a
        // contribution that is already stored and appears literally in the person's transcript.
        let evidence = comparableText(
            session.messages.filter { $0.role == .user }.map(\.content).joined(separator: " ")
        )
        return session.context.personalContributions.contains { contribution in
            let clean = comparableText(contribution)
            return clean.count >= 2 && evidence.contains(clean)
        }
    }

    private func completeCandidReflectionWithoutFierce() async {
        session.candidAgencyResponse = nil
        session.candidAgencyCompleted = true
        session.hasCompletedAttributionExchange = true
        refreshCardDerivedDeltaNarrative()
        session.studyEvents.append(
            .init(stage: .attributionReflection, action: "fierce_reflection_not_invited_without_user_supported_focus")
        )
        setWorkflowPhase(
            .reflectionNarrativeConfirmation,
            action: "integrated_reflection_narrative_started_without_fierce"
        )
        await presentIntegratedReflectionNarrative(managesTyping: false, revised: false)
    }

    /// A meaning-shift answer can itself name a concrete, editable focus (for example,
    /// not having a comparison standard). It does not prove blame; it only makes one
    /// candid question useful. Broad statements such as “没有变化” remain tender-only.
    private var cardMeaningShiftProvidesConcreteFocus: Bool {
        guard let response = session.cardMeaningShiftResponse,
              !cardMeaningShiftExpressesNoChange(response) else { return false }
        return !groundedSemanticRelations(
            kinds: [.controllablePart, .behaviorImpact, .boundaryNeed],
            in: session.latestAnalysis
        ).isEmpty
    }

    private func groundedSemanticRelations(
        kinds: Set<SemanticRelationKind>,
        in analysis: ContextAnalysis?
    ) -> [SemanticRelation] {
        guard let analysis else { return [] }
        return analysis.validated.resolvedSemanticRelations.filter { relation in
            kinds.contains(relation.kind) &&
            [.userStated, .userConfirmed].contains(relation.status) &&
            relation.confidence >= 0.6 &&
            literalEvidenceIsSupported(relation.evidence)
        }
    }

    private func literalEvidenceIsSupported(_ fragments: [String]) -> Bool {
        guard !fragments.isEmpty else { return false }
        let transcript = comparableText(
            session.messages.filter { $0.role == .user }.map(\.content).joined(separator: " ")
        )
        return fragments.allSatisfy { fragment in
            let clean = comparableText(fragment)
            return clean.count >= 2 && transcript.contains(clean)
        }
    }

    private func recommendedCompassionatePractice() -> CompassionatePracticeDirection {
        let analysis = session.latestAnalysis?.validated
        if let analysis, analysis.confidence > 0 {
            let relations = groundedSemanticRelations(
                kinds: [
                    .behaviorImpact, .boundaryNeed, .controllablePart, .conditionCapacity,
                    .selfEvaluation, .unmetNeed,
                ],
                in: analysis
            )
            return practiceResolver.resolve(
                analysis: analysis,
                groundedRelations: relations
            )
        }

        // During a provider outage, do not guess care/repair/protection from scenario words.
        // A generic, user-supported behavior can still permit a small change; otherwise no
        // practice is safer than assigning the wrong responsibility direction.
        if hasUserSupportedFierceFocus { return .change }
        return .noAction
    }

    private func fallbackActions(
        for requestedPractice: CompassionatePracticeDirection? = nil
    ) -> [ActionSuggestion] {
        let practice = requestedPractice ?? recommendedCompassionatePractice()
        guard let category = practice.actionCategory else { return [] }
        switch practice {
        case .care:
            return [
                ActionSuggestion(
                    category: .care,
                    description: "先留出十分钟写下现在最难受的感受和最需要被照顾的一件事，写完就停，不要求马上解决问题",
                    timing: "今天方便时",
                    rationale: "先为当前的负担留出恢复空间，再决定是否需要行动"
                )
            ]
        case .protection:
            return [
                ActionSuggestion(
                    category: .protect,
                    description: "用两句话写下自己现在能够承担的部分，以及暂时不能承担或需要说明的边界",
                    timing: "下一次回应前",
                    rationale: "把责任范围说清楚，同时保护现实的时间、精力或需要"
                )
            ]
        case .repair:
            return [
                ActionSuggestion(
                    category: .repair,
                    description: "先写一条三句话的修复草稿：承认具体影响、说明现在能补上的部分、给出一个现实的后续安排",
                    timing: "今天方便时",
                    rationale: "只处理已经确认的具体影响，不把修复变成对整个人的否定"
                )
            ]
        case .change:
            let groundedFocus = groundedSemanticRelations(
                kinds: [.controllablePart, .behaviorImpact],
                in: session.latestAnalysis
            ).first
            let focus = groundedFocus.map { relation in
                let candidate = relation.target.isEmpty ? relation.source : relation.target
                return String(situationSpecificText(candidate).prefix(32))
            }
            let description: String
            if let focus, !focus.isEmpty {
                description = "把“\(focus)”缩成一个五分钟内可以开始、只做一次的动作，完成后再决定是否继续"
            } else {
                description = "把刚才确认的可控部分缩成一个五分钟内可以开始、只做一次的动作，完成后再决定是否继续"
            }
            return [
                ActionSuggestion(
                    category: category,
                    description: description,
                    timing: "今天方便时",
                    rationale: "沿用已经确认的可控部分，不额外增加新的目标"
                )
            ]
        case .noAction:
            return []
        }
    }

    private func actionDraftIsAcceptablySmall(_ suggestion: ActionSuggestion) -> Bool {
        let clean = suggestion.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4, clean.count <= 90 else { return false }
        guard [.care, .protect, .repair, .change].contains(suggestion.category) else { return false }
        guard !actionNeedsNarrowing(clean), !containsGlobalIdentityLabel(clean) else { return false }
        return true
    }

    private func formattedActionDrafts() -> String {
        let suggestions = Array(session.actionSuggestions.prefix(2))
        guard !suggestions.isEmpty else {
            return "现在不一定需要定行动。你也可以先停在这段理解上。"
        }
        let lines = suggestions.enumerated().map { index, suggestion in
            let timing = suggestion.timing.map { "（\($0)）" } ?? ""
            return "\(index + 1). \(suggestion.description)\(timing)"
        }.joined(separator: "\n")
        return "根据你刚才确认的情况，可以先考虑这\(suggestions.count == 1 ? "一个" : "两个")很小的方向：\n\(lines)\n\n你可以选一个、直接改小，或者都不选。"
    }

    private func deterministicNarrativeForCurrentPhase() -> String {
        switch session.workflowPhase {
        case .tenderGroundingConfirmation:
            return deterministicTenderGroundingSummary()
        case .contextConfirmation:
            return deterministicContextSummary()
        default:
            return deterministicCardIntegrationSummary()
        }
    }

    private func deterministicTenderGroundingSummary() -> String {
        var sentences: [String] = []
        if let event = session.context.eventDescription,
           let concreteEvent = tenderEventNarrative(event),
           !concreteEvent.isEmpty {
            sentences.append(concreteEvent + "。")
        }

        let feelings = naturalEmotionLabels(
            session.context.emotions.filter(isSupportedEmotionExtraction),
            limit: 2
        )
        let bodily = session.context.bodilyResponses
            .filter(isSupportedBodyExtraction)
            .prefix(2)
        if !feelings.isEmpty, !bodily.isEmpty {
            sentences.append(
                "想到这件事时，你感到\(feelings.joined(separator: "、"))，也注意到\(bodily.joined(separator: "、"))。"
            )
        } else if !feelings.isEmpty {
            sentences.append("想到这件事时，你最明显的是\(feelings.joined(separator: "、"))。")
        } else if !bodily.isEmpty {
            sentences.append("想到这件事时，你注意到\(bodily.joined(separator: "、"))。")
        }

        if let meaning = session.context.personalMeaning,
           let concern = tenderConcernNarrative(meaning),
           !concern.isEmpty {
            if session.context.selfJudgment?.isEmpty == false {
                sentences.append("这件事也让你担心\(concern)，但这个担心还不能据此给整个人下结论。")
            } else {
                sentences.append("这件事也让你担心\(concern)。")
            }
        }
        let constraints = session.context.contextualConstraints
            .prefix(2)
            .compactMap { tenderConstraintNarrative($0) }
        if !constraints.isEmpty {
            sentences.append(
                "当时还要面对\(constraints.joined(separator: "、"))。"
            )
        }
        let contributions = session.context.personalContributions
            .prefix(2)
            .compactMap { tenderContributionNarrative($0) }
        if !contributions.isEmpty {
            sentences.append(tenderContributionSummarySentence(contributions))
        } else if session.context.selfJudgment?.isEmpty == false,
                  session.context.personalMeaning?.isEmpty != false {
            sentences.append("这些具体困难和当时的难受都是真的，但还不能据此给整个人下结论。")
        }

        if sentences.isEmpty {
            return "刚才这件事带来的难受，以及你当时对自己的看法，都可以先放回具体处境里看，不急着变成对整个人的结论。"
        }
        return Array(sentences.prefix(4)).joined(separator: " ")
    }

    private func deterministicContextSummary() -> String {
        var summary = deterministicTenderGroundingSummary()
        if session.trackingReviewUnavailable {
            summary += " 这次没有形成足够可靠的近期状态线索；这可能来自信息不足或状态变化并不一致，并不表示你当时没有现实负担，所以这里不根据缺失线索作判断。"
            return summary
        }
        if let contextualDescription = contextualLoadDescriptionForContextSummary() {
            summary += " \(contextualDescription)"
            summary += " 这可能让当时更难应对，但不能单独解释当时发生了什么。"
            return summary
        }
        let cues = Array(session.context.confirmedTrackingCues.prefix(4))
        guard !cues.isEmpty else { return summary }

        let observations = cues.map(plainTrackingClause).filter { !$0.isEmpty }
        if !observations.isEmpty {
            let time = trackingTimeReference()
            summary += " \(time)，\(observations.joined(separator: "；"))。"
            if let link = session.trackingContextLinkResponse,
               !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary += " \(trackingContextLinkSummary(link))"
            } else {
                summary += " 你觉得这些变化和自己那段时间的状态对得上，但它们还不能解释当时具体发生了什么。"
            }
        }
        return summary
    }

    /// The post-tracking confirmation is a negotiated contextual attribution, not a second
    /// tracking report. It contains only observed changes, the person's confirmed event impact,
    /// and a clearly limited hypothesis about how those conditions may have made the moment
    /// harder. It never turns records into a cause, diagnosis, excuse, or responsibility verdict.
    private func tentativeSituationalAttributionSummary() -> String {
        if session.trackingReviewUnavailable {
            return deterministicContextSummary()
        }

        let cues = Array(session.context.confirmedTrackingCues.prefix(3))
        let contextualDescription = confirmedContextualLoadDescription()
        guard !cues.isEmpty || contextualDescription != nil else {
            return deterministicTenderGroundingSummary()
        }

        let event = session.context.eventDescription
            .flatMap(tenderEventNarrative)
            ?? "刚才那件事"
        let observations = contextualDescription == nil
            ? naturalTrackingObservationList(cues.map(plainTrackingClause).filter { !$0.isEmpty })
            : ""
        let feelings = naturalEmotionLabels(
            session.context.emotions.filter(isSupportedEmotionExtraction),
            limit: 2
        )
        let bodily = session.context.bodilyResponses
            .filter(isSupportedBodyExtraction)
            .prefix(1)
        let constraints = session.context.contextualConstraints
            .compactMap(tenderConstraintNarrative)
            .prefix(1)
        let impact = confirmedTrackingImpactClause()
        let selfEvaluationRelations = groundedSemanticRelations(
            kinds: [.selfEvaluation],
            in: session.latestAnalysis
        )
        let behaviorRelations = groundedSemanticRelations(
            kinds: [.behaviorImpact],
            in: session.latestAnalysis
        )

        var sentences: [String] = [event + "。"]
        if !feelings.isEmpty {
            sentences.append("这件事让你感到\(feelings.joined(separator: "、"))。")
        }
        if !bodily.isEmpty {
            sentences.append("你也注意到自己当时\(bodily.joined(separator: "、"))。")
        }
        if !constraints.isEmpty {
            sentences.append("当时还要面对\(constraints.joined(separator: "、"))。")
        }
        if !selfEvaluationRelations.isEmpty || session.context.selfJudgment?.isEmpty == false {
            sentences.append("这也让你很快把具体处境扩大成了对自己的整体评价；当时遇到的问题和对整个人的判断，需要分开看。")
        }
        if let contextualDescription {
            sentences.append(contextualDescription)
        } else if !observations.isEmpty {
            sentences.append("\(trackingTimeReference())，\(observations)。")
        }
        if let impact {
            sentences.append("你也认为，\(impact)。")
        }

        if impact != nil {
            sentences.append(
                "把已经说清楚的处境和这些近期变化放在一起，一个暂时的理解是：它们可能影响了你当时可用的精力、时间或应对余地，让那一刻更难处理。"
            )
            if let behavior = behaviorRelations.first {
                sentences.append(
                    "这些背景不能证明事情为什么发生，也不能替代对“\(compactNarrativeClause(behavior.source))”及其影响的具体检查。"
                )
            } else {
                sentences.append("这些背景不能证明事情为什么发生，也不能替你决定原因或责任。")
            }
        } else {
            sentences.append("这些记录目前只作为可能的背景保留，还不能说明它们和这件事有什么关系。")
        }
        return sentences.joined(separator: " ")
    }

    private func confirmedTrackingImpactClause() -> String? {
        guard var value = session.trackingContextLinkResponse?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)),
              !value.isEmpty else { return nil }
        for prefix in ["你觉得", "我觉得", "我感觉", "可能", "有一点"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            break
        }
        value = value.replacingOccurrences(of: "让自己", with: "让你")
        if value.hasPrefix("让你") { return value }
        if value.hasPrefix("这让你") { return value }
        return value.hasPrefix("当时") ? "你\(value)" : value
    }

    private func trackingContextLinkSummary(_ response: String) -> String {
        let clean = comparableText(response)
        let noEffect = [
            "没有影响", "没影响", "没有关系", "没关系", "关系不大",
            "没有太大关系", "没什么关系", "没有明显影响",
        ].contains { clean.contains(comparableText($0)) }
        if noEffect {
            return "你觉得这些变化和当时的反应没有明显关系，所以这里不把它们写成原因。"
        }
        let simplePositive = [
            "有", "有影响", "可能有", "有一点影响", "可能有一点影响",
        ].contains(clean)
        if simplePositive {
            if session.contextualLoadInference?.relevance == .relevant {
                return "你觉得这种可能的近期负荷，可能对当时的反应有一点影响。这能帮助理解那一刻为什么更难应对，但不能替你判断原因或责任。"
            }
            return "你觉得\(trackingContextLinkCandidate())，可能对当时的反应有一点影响。这能帮助理解那一刻为什么更难应对，但不能替你判断该由谁负责。"
        }
        // Deterministic fallback preserves the person's authorship and relational direction,
        // but never splices their first-person sentence into an assistant paragraph.
        let sequenceMarkers = ["然后", "接着", "反过来", "循环", "互相", "越来越"]
        if sequenceMarkers.filter({ clean.contains(comparableText($0)) }).count >= 2 {
            return "你认为，当时的难受、这些近期变化和能够投入的精力之间可能彼此影响，让继续应对这件事变得更困难。这个联系来自你的感受，但仍不能单独确定原因或责任。"
        }
        return "你认为，这些近期变化可能让当时更难应对。这个联系来自你的感受，但仍不能单独确定原因或责任。"
    }

    private func confirmedContextualLoadDescription() -> String? {
        guard let inference = session.contextualLoadInference,
              inference.relevance == .relevant,
              inference.hasDialogueCue,
              let hypothesis = inference.dialogueHypothesis else {
            return nil
        }
        return userFacingContextualHypothesis(hypothesis)
    }

    /// The first whole-context summary is the sole place where a not-yet-confirmed hypothesis may
    /// be visible. Its ordinary accuracy check negotiates the entire understanding; every later
    /// prompt still requires `.relevant`.
    private func contextualLoadDescriptionForContextSummary() -> String? {
        guard let inference = session.contextualLoadInference,
              [.notReviewed, .relevant].contains(inference.relevance),
              inference.hasDialogueCue,
              let hypothesis = inference.dialogueHypothesis else {
            return nil
        }
        return userFacingContextualHypothesis(hypothesis)
    }

    private func plainTrackingClause(_ cue: TrackingCue) -> String {
        guard let insight = cue.insight else {
            return cue.neutralDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // An empty calendar does not describe the person's load. It is useful as an internal
        // limitation, but not as one of the visible “background changes” when other records exist.
        if insight.metric == .calendarLoad, insight.validSampleCount == 0 {
            return ""
        }
        let difference = insight.absoluteDifference
        switch insight.metric {
        case .sleepDuration:
            guard let difference else { return "睡眠时长有一些变化" }
            return difference < 0 ? "睡眠比平时短一些" : "睡眠比平时长一些"
        case .sleepTiming:
            guard let difference else { return "入睡时间和个人平时不太一样" }
            return difference > 0 ? "入睡比平时晚一些" : "入睡比平时早一些"
        case .sleepWakeTime:
            guard let difference else { return "醒来时间和个人平时不太一样" }
            return difference > 0 ? "醒来比平时晚一些" : "醒来比平时早一些"
        case .sleepContinuity:
            guard let difference else { return "睡眠中间醒来的情况和个人平时不太一样" }
            return difference < 0
                ? "睡眠中间醒来的次数可能比平时多一些"
                : "睡眠中间醒来的次数可能比平时少一些"
        case .steps:
            guard let difference else { return "运动量和走动时间有一些变化" }
            return difference < 0 ? "运动量和走动比平时少一些" : "运动量和走动比平时多一些"
        case .heartRateVariability:
            // This metric is useful inside the deterministic candidate calculation, but a phrase
            // such as “身体恢复方面的设备记录” is opaque to most people. When sleep/activity are
            // present, describe those directly and let this record only soften the possible
            // fatigue/recovery wording instead of exposing a mysterious extra item.
            return ""
        case .restingHeartRate:
            guard let difference else { return "安静状态下的心率和平时有一些差别" }
            return difference > 0 ? "安静状态下的心率比平时稍快一些" : "安静状态下的心率比平时稍慢一些"
        case .calendarLoad:
            guard let difference else { return "日历中记录到的安排有一些变化" }
            return difference > 0 ? "日历中记录到的安排比平时多一些" : "日历中记录到的安排比平时少一些"
        case .screenTime:
            guard let difference else { return "屏幕使用记录有一些变化" }
            return difference > 0 ? "屏幕使用时长比平时多一些" : "屏幕使用时长比平时少一些"
        case .weather:
            return "外部环境记录有一些变化"
        }
    }

    private func containsTechnicalTrackingTerm(_ text: String) -> Bool {
        let normalized = comparableText(text)
        let terms = [
            "hrv", "心率变异", "sdnn", "bpm", "心跳间隔", "心跳间距",
            "静息心率", "心率", "睡眠数据", "睡眠记录", "步数", "活动记录",
            "设备检测", "系统检测", "数据显示", "记录显示",
        ]
        return terms.contains { normalized.contains(comparableText($0)) }
    }

    /// A provider outage used to return only “these records are background”, which is safe but
    /// hides the actual, program-selected sleep/activity context from both study conditions.
    /// Replace that stock sentence with the same deterministic, non-causal local description.
    private func isGenericTrackingReply(_ text: String) -> Bool {
        let clean = comparableText(text)
        let genericMarkers = [
            "这些记录只能当作背景", "不能说明原因", "不能判断责任",
            "其中哪些和当时的状态对得上", "活动量和身体状态与平时有些不同",
            "身体状态与平时有些不同"
        ]
        return genericMarkers.contains { clean.contains(comparableText($0)) }
    }

    private func containsConcreteTrackingImpactQuestion(_ text: String) -> Bool {
        let clean = comparableText(text)
        let returnsToEvent = ["放回", "那个时刻", "当时", "刚才那件事"].contains {
            clean.contains(comparableText($0))
        }
        let asksTentatively = clean.contains("有没有") || clean.contains("是否")
        let namesPossibleEffect = [
            "更难", "影响", "反应", "耐心", "开始", "继续", "承受", "说清楚",
        ].contains { clean.contains(comparableText($0)) }
        return returnsToEvent && asksTentatively && namesPossibleEffect
    }

    private func latestUserTrackingStateDescription() -> String? {
        guard let latest = session.messages.last(where: { $0.role == .user })?.content,
              isUserTrackingStateDescription(latest) else {
            return nil
        }
        let clean = comparableText(latest)
        let simpleAgreement = [
            "符合", "贴近", "对得上", "相关", "有关系", "是的", "对", "不符合",
            "不贴近", "对不上", "不相关", "没有关系",
        ]
        return simpleAgreement.contains(clean) ? nil : latest
    }

    private func narrativeAcknowledgesTrackingState(_ narrative: String, _ state: String) -> Bool {
        let text = comparableText(narrative)
        let markers = [
            "没劲", "没精神", "没力气", "提不起劲", "疲惫", "疲劳", "很累", "累",
            "紧绷", "压力大", "睡得少", "睡不好", "睡不稳", "入睡困难", "难入睡",
            "恢复不好", "没有精神", "状态差",
        ]
        let stateMarkers = markers.filter { comparableText(state).contains(comparableText($0)) }
        return !stateMarkers.isEmpty && stateMarkers.contains { text.contains(comparableText($0)) }
    }

    /// Tender grounding is spoken *to* the person. The stored disclosure is deliberately literal
    /// for research fidelity, so it cannot be inserted straight into a second-person sentence.
    /// These helpers keep the facts while removing first-person framing and global self-labels.
    private func tenderEventNarrative(_ text: String) -> String? {
        guard var event = concreteEventClause(text) else { return nil }
        // The event can contain a later first-person clause ("…但我已经两天没写").
        // Convert its perspective before the sentence receives the assistant's framing.
        event = event.replacingOccurrences(of: "我", with: "你")
        if event.hasPrefix("你") { return event }
        return "这段时间，\(event)"
    }

    private func tenderConcernNarrative(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingFrames = [
            "我主要怕", "我最担心", "我最怕", "我会担心", "我担心", "我害怕", "我怕",
            "让我最担心的是", "让我最担心", "这让我最担心的是", "这让我最担心",
            "主要是怕", "主要怕", "最担心的是", "最怕的是", "担心的是",
            "都不是，我最介意的是", "都不是最介意的是", "我最介意的是", "最介意的是",
            "我一直觉得", "我一直担心", "我总觉得", "我总担心", "我会觉得",
        ]
        for frame in leadingFrames where value.hasPrefix(frame) {
            value.removeFirst(frame.count)
            break
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !value.isEmpty else { return nil }
        if isSupportedEmotionExtraction(value) ||
            session.context.emotions.contains(where: {
                comparableText($0) == comparableText(value)
            }) {
            return nil
        }

        if containsKnownSelfEvaluation(value) {
            return "这次具体处境会被扩大成对整个人的判断"
        }
        if value.hasPrefix("我的") {
            value = "自己的\(value.dropFirst(2))"
        } else if value.hasPrefix("我") {
            value = "自己\(value.dropFirst())"
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Keep summaries readable when the analyzer returns a short form and its near-synonym
    /// (for example “烦” and “烦躁”) from the same disclosure.
    private func naturalEmotionLabels(_ values: [String], limit: Int) -> [String] {
        var result: [String] = []
        for raw in values {
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = comparableText(label)
            guard !normalized.isEmpty else { continue }
            if let index = result.firstIndex(where: {
                let existing = comparableText($0)
                return existing == normalized ||
                    existing.contains(normalized) ||
                    normalized.contains(existing)
            }) {
                if normalized.count > comparableText(result[index]).count {
                    result[index] = label
                }
                continue
            }
            result.append(label)
            if result.count >= limit { break }
        }
        return result
    }

    private func tenderConstraintNarrative(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !value.isEmpty, !isUncertainAnswer(value) else { return nil }
        let leadingFrames = ["我觉得", "我感觉", "我认为", "就是", "主要是"]
        for frame in leadingFrames where value.hasPrefix(frame) {
            value.removeFirst(frame.count)
            break
        }
        if value.hasPrefix("我") { value = "你\(value.dropFirst())" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func tenderContributionNarrative(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !value.isEmpty else { return nil }
        let paraphrases: [(String, String)] = [
            ("当时没说什么", "没有马上开口回应"),
            ("当时没有说什么", "没有马上开口回应"),
            ("没有说什么", "没有马上开口回应"),
            ("没开口", "没有马上开口回应"),
        ]
        for (source, replacement) in paraphrases {
            value = value.replacingOccurrences(of: source, with: replacement)
        }
        let leadingFrames = ["我可以", "我需要", "我应该", "我没有", "我没"]
        for frame in leadingFrames where value.hasPrefix(frame) {
            value.removeFirst(frame.count)
            break
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func tenderContributionSummarySentence(_ contributions: [String]) -> String {
        let detail = contributions.joined(separator: "、")
        return "你也看见了自己当时\(detail)。这是可以继续理解和处理的具体部分；它造成了什么影响、还有哪些条件参与其中，仍需要和对整个人的判断分开。"
    }

    private func concreteEventClause(_ text: String) -> String? {
        // Strip self-evaluation before applying any label rewrite. Rewriting first used to leave
        // fragments such as “你担心我主要怕……” in a tender summary.
        var value = text
        let boundaries = [
            "，我感觉", "，我觉得", "，我认为", "，我开始觉得", "，甚至",
            "。我感觉", "。我觉得", "。我认为", "。甚至",
            "，我当时", "。我当时", "，当时我", "。当时我",
            "，现在我", "。现在我", "，现在越想", "。现在越想",
        ]
        for boundary in boundaries {
            if let range = value.range(of: boundary) {
                value = String(value[..<range.lowerBound])
                break
            }
        }
        value = situationSpecificText(value)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }

    private func refreshCardDerivedDeltaNarrative() {
        guard session.condition.usesCard,
              session.cardMappingConfirmed,
              let mapping = session.cardConfirmedMapping,
              !mapping.isEmpty else {
            session.cardDerivedDeltaNarrative = nil
            return
        }

        let imageRelation = session.cardGroundingMatch?.imageRelation
            ?? cardNarrativeClauses().last
            ?? cardNarrativeClauses().first
            ?? "画面里刚才形成的关系"
        var sentences = [
            "你在画面里确认了\(compactNarrativeClause(imageRelation))，并把这种关系与\(conciseConfirmedCardMapping(mapping))联系起来。"
        ]
        if let circumstance = session.candidCircumstancesResponse,
           !circumstance.isEmpty {
            sentences.append("沿着这个联系，你进一步注意到\(compactNarrativeClause(circumstance))。")
        }
        if let shift = session.cardMeaningShiftResponse,
           !shift.isEmpty {
            if cardMeaningShiftExpressesNoChange(shift) {
                sentences.append("你也明确说，这个角度没有改变原来的理解。")
            } else {
                sentences.append("这个比较带来的新区别是：\(compactNarrativeClause(shift))。")
            }
        }
        if let agency = session.candidAgencyResponse,
           !agency.isEmpty {
            sentences.append("你愿意诚实面对的具体一面是\(compactNarrativeClause(agency))。")
        }
        session.cardDerivedDeltaNarrative = sentences.joined(separator: "")
    }

    private func deterministicCardDeltaSummary() -> String {
        refreshCardDerivedDeltaNarrative()
        var sentences: [String] = []
        if let event = session.context.eventDescription.flatMap(concreteEventClause),
           !event.isEmpty {
            sentences.append("这次仍以\(String(event.prefix(58)))这段处境为基础。")
        } else {
            sentences.append("这次仍以你前面确认的处境为基础。")
        }
        if let delta = session.cardDerivedDeltaNarrative, !delta.isEmpty {
            sentences.append(delta)
        } else if let shift = session.cardMeaningShiftResponse,
                  cardMeaningShiftExpressesNoChange(shift) {
            sentences.append("卡牌阶段没有改变你原来对这件事的理解，也没有替它补上新的意义。")
        }
        if let action = session.context.selectedAction, action.acceptedByUser {
            sentences.append("你确认先做的一小步是：\(action.description)。")
        }
        return sentences.joined(separator: "")
    }

    private func deterministicCardIntegrationSummary() -> String {
        if session.condition.usesCard, session.cardMappingConfirmed {
            return deterministicCardDeltaSummary()
        }
        var sentences: [String] = []
        if let event = session.context.eventDescription,
           let eventNarrative = tenderEventNarrative(event),
           !eventNarrative.isEmpty {
            var lived = eventNarrative
            let emotions = naturalEmotionLabels(
                session.context.emotions.filter(isSupportedEmotionExtraction),
                limit: 2
            )
            let body = session.context.bodilyResponses.filter(isSupportedBodyExtraction).prefix(2)
            if !emotions.isEmpty { lived += "，当时你感到\(emotions.joined(separator: "、"))" }
            if !body.isEmpty { lived += "，身体上也有\(body.map(situationSpecificText).joined(separator: "、"))" }
            if let meaning = session.context.personalMeaning,
               let concern = tenderConcernNarrative(meaning),
               !concern.isEmpty {
                lived += "，也开始担心\(concern)"
            }
            sentences.append(lived + "。这次的具体表现和对整个人的判断，需要分开看。")
        }
        if !session.context.confirmedTrackingCues.isEmpty {
            if let link = session.trackingContextLinkResponse,
               !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(trackingContextLinkSummary(link))
            } else {
                sentences.append(
                    "你确认\(trackingTimeReference())的记录和当时的状态有些对应，但它们仍只是背景，不能单独解释行为或责任。"
                )
            }
        }
        if session.cardConnectionUnavailable {
            sentences.append("这张图没有自然地连到这次经历，所以这次不替它补一个意义。")
        } else if session.cardMappingConfirmed,
                  let mapping = session.cardConfirmedMapping,
                  !mapping.isEmpty {
            let clauses = cardNarrativeClauses()
            let scene = compactNarrativeClause(clauses.last ?? clauses.first ?? "刚才画面里的关系")
            let mappingClause = conciseConfirmedCardMapping(mapping)
            var cardSentence = "你把画面里的“\(scene)”和“\(mappingClause)”放在一起看；这个联系来自你的解释，不替它补一个固定牌义"
            if let meaningShift = session.cardMeaningShiftResponse, !meaningShift.isEmpty {
                if cardMeaningShiftExpressesNoChange(meaningShift) {
                    cardSentence += "。它帮助你把处境看得更具体，但没有改变你原来的判断"
                } else {
                    cardSentence += "。放在一起后，你开始这样理解：\(compactNarrativeClause(meaningShift))"
                    if expressesCommonHumanity(meaningShift) {
                        cardSentence += "，也让你看到这类困难并不只发生在你身上"
                    }
                }
            }
            sentences.append(cardSentence + "。")
        }
        if let circumstances = session.candidCircumstancesResponse, !circumstances.isEmpty {
            sentences.append("同时，\(compactNarrativeClause(circumstances))是当时需要被放回来看的一部分。")
        }
        let contributions = session.context.personalContributions
            .compactMap { tenderContributionNarrative($0) }
            .prefix(1)
        if !contributions.isEmpty {
            let contribution = contributions.joined(separator: "、")
            let agencyAlreadyContainsContribution = session.candidAgencyResponse.map {
                comparableText($0).contains(comparableText(contribution))
            } ?? false
            if !agencyAlreadyContainsContribution {
                sentences.append(
                    "你也确认了一个具体做法：\(contribution)；这需要被诚实面对，但不等于把全部问题归到自己身上。"
                )
            }
        }
        if let agency = session.candidAgencyResponse, !agency.isEmpty {
            sentences.append("你愿意面对的具体部分是\(compactNarrativeClause(agency))，但这不等于把全部问题都归到自己身上。")
        }
        if let action = session.context.selectedAction, action.acceptedByUser {
            sentences.append("你确认先做的一小步是：\(action.description)。")
        }
        if sentences.isEmpty {
            return "把刚才说到的放在一起，这次发生了什么已经具体了一些。还不能确定的部分，可以先保留，不用急着给自己下结论。"
        }
        return Array(sentences.prefix(4)).joined(separator: " ")
    }

    private func conciseConfirmedCardMapping(_ mapping: String) -> String {
        var value = mapping.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // A system candidate is stored as a complete sentence. Its later narrative role is only
        // to retain the real-life side of the confirmed bridge, never to replay the entire
        // confirmation prompt.
        if let range = value.range(of: "也把它联想到“") {
            let remainder = value[range.upperBound...]
            if let end = remainder.firstIndex(of: "”") {
                value = String(remainder[..<end])
            }
        }
        return compactNarrativeClause(String(value.prefix(78)))
    }

    private func cardNarrativeClauses() -> [String] {
        guard let raw = session.context.cardInterpretation, !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: "；;。\n"))
            .map(compactNarrativeClause)
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { String($0.prefix(64)) }
    }

    private func compactNarrativeClause(_ text: String) -> String {
        var value = situationSpecificText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["我觉得", "我感觉", "我认为", "我想", "可能是", "好像是"] {
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                break
            }
        }
        if value.hasPrefix("我") { value = "你\(value.dropFirst())" }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))
    }

    private func expressesCommonHumanity(_ text: String) -> Bool {
        let clean = comparableText(text)
        return ["大家", "每个人", "很多人", "共同", "不只我", "都要经历", "都会经历", "人都会"]
            .contains { clean.contains(comparableText($0)) }
    }

    private func deterministicSummary() -> String {
        let context = session.context
        var paragraphs: [String] = []
        let supportedEmotions = naturalEmotionLabels(
            context.emotions.filter(isSupportedEmotionExtraction),
            limit: 2
        )
        if let event = context.eventDescription,
           let eventNarrative = tenderEventNarrative(event) {
            let feeling = supportedEmotions.isEmpty ? "" : "。那时你感到\(supportedEmotions.joined(separator: "、"))"
            paragraphs.append("\(eventNarrative)\(feeling)。")
        } else if !supportedEmotions.isEmpty {
            paragraphs.append("这次最明显的感受是\(supportedEmotions.joined(separator: "、"))。")
        }
        if !context.confirmedTrackingCues.isEmpty {
            let observations = (context.confirmedTrackingInsights ?? [])
                .prefix(2)
                .map(\.observation)
                .joined(separator: "；")
            let detail = observations.isEmpty ? trackingSourceList(context.confirmedTrackingCues) : observations
            paragraphs.append("你觉得这些背景值得一起看：\(detail)。它们帮你想起那几天，但不能单独解释原因。")
        }
        let constraints = context.contextualConstraints.compactMap { tenderConstraintNarrative($0) }
        if !constraints.isEmpty {
            paragraphs.append("当时还有这些现实处境：\(constraints.joined(separator: "、"))。")
        }
        let contributions = context.personalContributions.compactMap { tenderContributionNarrative($0) }
        if !contributions.isEmpty {
            paragraphs.append(tenderContributionSummarySentence(contributions))
        } else if context.selfJudgment?.isEmpty == false {
            paragraphs.append("你当时对自己下了一个很重的结论。现在能够确认的是这次经历和当时的反应，它们还不能代替对整个人的判断。")
        }
        if let meaning = context.personalMeaning,
           let concern = tenderConcernNarrative(meaning),
           !concern.isEmpty {
            paragraphs.append("这背后更具体的担心是：\(concern)。")
        }
        if !context.uncertainties.isEmpty {
            paragraphs.append("现在还不用急着弄清的是：\(context.uncertainties.joined(separator: "、"))。")
        }
        if let interpretation = context.cardInterpretation,
           session.cardMappingConfirmed,
           !session.cardWasSetAside {
            paragraphs.append("你从画面里注意到：\(situationSpecificText(interpretation))")
            if let mapping = session.cardConfirmedMapping, !mapping.isEmpty {
                paragraphs.append("你确认它和现实的联系是：\(situationSpecificText(mapping))")
            }
            if let meaningShift = session.cardMeaningShiftResponse, !meaningShift.isEmpty {
                if cardMeaningShiftExpressesNoChange(meaningShift) {
                    paragraphs.append("你说这张图没有改变你原来对这件事的理解。")
                } else {
                    paragraphs.append("它让你这样重新理解原来的经历：\(situationSpecificText(meaningShift))")
                }
            }
        } else if session.cardConnectionUnavailable {
            paragraphs.append("这张随机卡没有自然地连到你的经历，所以没有勉强赋予它意义。")
        }
        if let circumstances = session.candidCircumstancesResponse, !circumstances.isEmpty {
            paragraphs.append("你认为需要被承认的现实情况是：\(situationSpecificText(circumstances))")
        }
        if let agency = session.candidAgencyResponse, !agency.isEmpty {
            paragraphs.append("你认为仍可选择或调整的部分是：\(situationSpecificText(agency))")
        }
        if let action = context.selectedAction, action.acceptedByUser {
            paragraphs.append("你愿意先试试：\(action.description)\(action.timing.map { "（\($0)）" } ?? "")。")
        }
        paragraphs.append("把这些放在一起，不是为了判谁对谁错，而是既看见当时的处境，也保留接下来可以选择的部分。")
        return paragraphs.joined(separator: "\n\n")
    }

    private func transition(to state: ReflectionState, action: String) {
        guard responseContextIsCurrent() else { return }
        guard stateMachine.canTransition(from: session.stage, to: state) else {
            session.studyEvents.append(.init(stage: session.stage, action: "blocked_invalid_transition"))
            return
        }
        session.stage = state
        session.dialogueProgress.currentState = state
        session.studyEvents.append(.init(stage: state, action: action))
        scheduleCloudSync(action: action)
    }

    private func setWorkflowPhase(_ phase: ReflectionWorkflowPhase, action: String) {
        guard responseContextIsCurrent() else { return }
        guard workflowStateMachine.canTransition(from: session.workflowPhase, to: phase) else {
            session.studyEvents.append(
                .init(stage: session.stage, action: "blocked_invalid_workflow_phase_transition")
            )
            return
        }
        session.workflowPhase = phase
        session.studyEvents.append(.init(stage: session.stage, action: action))
        scheduleCloudSync(action: action)
    }

    /// Explicit user termination is the only legal early escape from the canonical phase graph.
    /// It must not be confused with confirmation of a final narrative.
    private func completeWorkflowEarly(action: String) {
        guard responseContextIsCurrent(), session.workflowPhase != .complete else { return }
        session.workflowPhase = .complete
        session.studyEvents.append(.init(stage: session.stage, action: action))
        scheduleCloudSync(action: action)
    }

    private func interruptForSafety(replyingTo userMessageID: UUID? = nil) {
        guard session.stage != .safetySupport else { return }
        if session.usesLLMTurnController {
            session.protocolStage = .safetySupport
        }
        setWorkflowPhase(.safetySupport, action: "safety_workflow_interrupted")
        session.stage = .safetySupport
        session.currentRoute = .tenderStabilize
        session.studyEvents.append(.init(stage: .safetySupport, action: "safety_signal_detected"))
        addAssistant(
            "我很在意你刚才提到的安全风险。请立即联系可信任的人或当地紧急服务；在中国大陆可拨打 120/110。这个应用会先暂停普通反思。",
            replyingTo: userMessageID
        )
    }

    private func clearRetry() { retryTarget = nil; canRetry = false }

    private func finishTypingForCurrentResponse() {
        if ReflectionResponseContext.generationID == nil || responseContextIsCurrent() {
            isTyping = false
        }
    }

    private func cancelActiveResponse(removePartialReply: Bool) {
        let generationID = activeResponseGenerationID
        responseTask?.cancel()
        responseTask = nil
        activeResponseGenerationID = nil
        activeUserTurnGenerations.removeAll()
        if removePartialReply, isStreamingResponse, let generationID {
            session.messages.removeAll {
                $0.role == .assistant && $0.assistantGenerationID == generationID
            }
        }
        isTyping = false
        isStreamingResponse = false
        isOpeningTrackingReview = false
    }

    private func responseContextIsCurrent(
        expectedSessionID: UUID? = nil,
        expectedStage: ReflectionState? = nil,
        expectedWorkflowPhase: ReflectionWorkflowPhase? = nil
    ) -> Bool {
        guard !Task.isCancelled else { return false }
        let responseSessionID = expectedSessionID ?? ReflectionResponseContext.sessionID
        if let responseSessionID, responseSessionID != session.id { return false }
        if let generationID = ReflectionResponseContext.generationID,
           activeResponseGenerationID != generationID {
            return false
        }
        if let userMessageID = ReflectionResponseContext.userMessageID,
           let generationID = ReflectionResponseContext.generationID,
           activeUserTurnGenerations[userMessageID] != generationID {
            return false
        }
        if let expectedStage, session.stage != expectedStage { return false }
        if let expectedWorkflowPhase, session.workflowPhase != expectedWorkflowPhase { return false }
        return true
    }

    private func launchResponse(
        replyingTo userMessageID: UUID? = nil,
        _ operation: @escaping @MainActor (ReflectionViewModel) async -> Void
    ) {
        let expectedSessionID = session.id
        let inheritedUserMessageID = ReflectionResponseContext.userMessageID
        if ReflectionResponseContext.generationID != nil, !responseContextIsCurrent() { return }
        let effectiveUserMessageID = userMessageID ?? inheritedUserMessageID
        if let effectiveUserMessageID,
           session.messages.contains(where: {
               $0.role == .assistant && $0.replyToMessageID == effectiveUserMessageID
           }) {
            session.studyEvents.append(.init(stage: session.stage, action: "duplicate_user_turn_generation_suppressed"))
            return
        }
        let generationID = UUID()
        if let effectiveUserMessageID,
           activeUserTurnGenerations[effectiveUserMessageID] != nil,
           inheritedUserMessageID != effectiveUserMessageID {
            session.studyEvents.append(.init(stage: session.stage, action: "concurrent_user_turn_generation_suppressed"))
            return
        }
        let replacedGenerationID = activeResponseGenerationID
        responseTask?.cancel()
        if isStreamingResponse, let replacedGenerationID {
            session.messages.removeAll {
                $0.role == .assistant && $0.assistantGenerationID == replacedGenerationID
            }
            isStreamingResponse = false
        }
        activeResponseGenerationID = generationID
        if let effectiveUserMessageID {
            activeUserTurnGenerations[effectiveUserMessageID] = generationID
        }
        responseTask = Task { @MainActor [weak self] in
            guard let self, self.session.id == expectedSessionID else { return }
            defer {
                if self.activeResponseGenerationID == generationID {
                    self.activeResponseGenerationID = nil
                    self.responseTask = nil
                }
                if let effectiveUserMessageID,
                   self.activeUserTurnGenerations[effectiveUserMessageID] == generationID {
                    self.activeUserTurnGenerations.removeValue(forKey: effectiveUserMessageID)
                }
            }
            await ReflectionResponseContext.$sessionID.withValue(expectedSessionID) {
                await ReflectionResponseContext.$userMessageID.withValue(effectiveUserMessageID) {
                    await ReflectionResponseContext.$generationID.withValue(generationID) {
                        await operation(self)
                    }
                }
            }
        }
    }

    /// A participant's text is durable before the first model request for that turn. Cloud sync
    /// remains best-effort, but a provider timeout, app suspension, or protocol repair cannot make
    /// the original input depend on a later assistant response completing successfully.
    private func launchPersistedModelResponse(
        replyingTo userMessageID: UUID,
        _ operation: @escaping @MainActor (ReflectionViewModel) async -> Void
    ) {
        launchResponse(replyingTo: userMessageID) { model in
            model.isTyping = true
            model.session.studyEvents.append(
                .init(
                    stage: model.session.stage,
                    action: "user_input_persisting_before_model_turn"
                )
            )
            do {
                try await model.store.save(model.session)
                model.session.studyEvents.append(
                    .init(
                        stage: model.session.stage,
                        action: "user_input_persisted_before_model_turn"
                    )
                )
            } catch {
                model.session.studyEvents.append(
                    .init(
                        stage: model.session.stage,
                        action: "user_input_persistence_failed"
                    )
                )
                model.addAssistant(
                    "这条内容暂时没能安全保存，所以我先不继续处理。请保留当前页面后再试一次。",
                    replyingTo: userMessageID
                )
                model.llmStatus = "本机记录暂时不可写入"
                model.finishTypingForCurrentResponse()
                return
            }
            await operation(model)
        }
    }
    @discardableResult
    private func addUser(_ text: String) -> UUID {
        let id = UUID()
        session.messages.append(.init(id: id, role: .user, content: text, state: session.stage))
        scheduleCloudSync(action: "user_message")
        return id
    }
    private func addAssistant(_ text: String, replyingTo explicitUserMessageID: UUID? = nil) {
        guard responseContextIsCurrent() else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let userMessageID = explicitUserMessageID ?? ReflectionResponseContext.userMessageID
        guard !hasAssistantReply(to: userMessageID) else {
            session.studyEvents.append(.init(stage: session.stage, action: "duplicate_user_turn_reply_suppressed"))
            return
        }
        guard !isSubstantiallyRepeated(clean) else {
            session.studyEvents.append(.init(stage: session.stage, action: "duplicate_assistant_message_suppressed"))
            return
        }
        session.messages.append(
            .init(
                role: .assistant,
                content: clean,
                state: session.stage,
                replyToMessageID: userMessageID,
                assistantGenerationID: ReflectionResponseContext.generationID
            )
        )
        // Immediate local replies (the opening greeting, draw invitation, and completion text)
        // do not pass through streamAssistant. Publish an explicit revision so the chat refreshes
        // and scrolls as soon as the message is appended.
        streamRevision += 1
        scheduleCloudSync(action: "assistant_message")
    }

    private func streamAssistant(_ text: String) async {
        let expectedSessionID = session.id
        let expectedStage = session.stage
        let expectedWorkflowPhase = session.workflowPhase
        guard responseContextIsCurrent(
            expectedSessionID: expectedSessionID,
            expectedStage: expectedStage,
            expectedWorkflowPhase: expectedWorkflowPhase
        ) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let userMessageID = ReflectionResponseContext.userMessageID
        guard !hasAssistantReply(to: userMessageID) else {
            session.studyEvents.append(.init(stage: session.stage, action: "duplicate_user_turn_reply_suppressed"))
            return
        }
        guard !isSubstantiallyRepeated(clean) else {
            session.studyEvents.append(.init(stage: session.stage, action: "duplicate_assistant_message_suppressed"))
            return
        }
        let id = UUID()
        session.messages.append(
            .init(
                id: id,
                role: .assistant,
                content: "",
                state: session.stage,
                replyToMessageID: userMessageID,
                assistantGenerationID: ReflectionResponseContext.generationID
            )
        )
        isStreamingResponse = true
        defer {
            if responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage,
                expectedWorkflowPhase: expectedWorkflowPhase
            ) {
                isStreamingResponse = false
                streamRevision += 1
                scheduleCloudSync(action: "assistant_message")
            }
        }
        let characters = Array(clean)
        let chunkSize = characters.count > 500 ? 6 : 3
        var rendered = ""
        var cursor = 0
        while cursor < characters.count {
            guard responseContextIsCurrent(
                expectedSessionID: expectedSessionID,
                expectedStage: expectedStage,
                expectedWorkflowPhase: expectedWorkflowPhase
            ) else {
                if session.id == expectedSessionID {
                    session.messages.removeAll { $0.id == id }
                }
                return
            }
            let end = min(cursor + chunkSize, characters.count)
            rendered.append(contentsOf: characters[cursor..<end])
            guard let index = session.messages.firstIndex(where: { $0.id == id }) else { return }
            session.messages[index].content = rendered
            streamRevision += 1
            do {
                try await Task.sleep(
                    for: .milliseconds(rendered.last.map { "。！？；\n".contains($0) } == true ? 55 : 20)
                )
            } catch {
                if session.id == expectedSessionID {
                    session.messages.removeAll { $0.id == id }
                }
                return
            }
            cursor = end
        }
    }

    private func hasAssistantReply(to userMessageID: UUID?) -> Bool {
        guard let userMessageID else { return false }
        return session.messages.contains {
            $0.role == .assistant && $0.replyToMessageID == userMessageID
        }
    }

    private func isSubstantiallyRepeated(_ candidate: String) -> Bool {
        let lhs = comparableText(candidate)
        guard lhs.count >= 8 else { return false }
        let recent = session.messages
            .filter { $0.role == .assistant && !$0.content.isEmpty }
            .suffix(10)
        return recent.contains { message in
            let rhs = comparableText(message.content)
            if lhs == rhs { return true }
            guard lhs.count >= 24, rhs.count >= 24 else { return false }
            let leftPairs = characterPairs(lhs)
            let rightPairs = characterPairs(rhs)
            let overlap = leftPairs.intersection(rightPairs).count
            let smaller = min(leftPairs.count, rightPairs.count)
            return Double(overlap) / Double(max(smaller, 1)) >= 0.78
        }
    }

    private func isRedundantUserEcho(_ reflection: String) -> Bool {
        guard let latestUser = session.messages.last(where: { $0.role == .user })?.content else { return false }
        let response = comparableText(reflection)
        let user = comparableText(latestUser)
        guard response.count >= 8, user.count >= 8 else { return false }
        if response == user || response.contains(user) { return true }

        let responsePairs = characterPairs(response)
        let userPairs = characterPairs(user)
        let smaller = min(responsePairs.count, userPairs.count)
        let larger = max(responsePairs.count, userPairs.count)
        guard smaller > 0, Double(larger) / Double(smaller) <= 1.6 else { return false }
        let overlap = responsePairs.intersection(userPairs).count
        return Double(overlap) / Double(smaller) >= 0.82
    }

    /// Removes model-written mirror sentences before they reach the chat UI. This is deliberately
    /// stricter than duplicate-assistant detection: a response should advance the reflection, not
    /// translate the user's first-person answer into a second-person summary.
    private func removingUserRestatement(from reflection: String) -> String {
        let clean = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              let latestUser = session.messages.last(where: { $0.role == .user })?.content else {
            return clean
        }
        let separators = CharacterSet(charactersIn: "。！？!?；;\n")
        let clauses = clean.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let retained = clauses.filter { !isUserRestatementClause($0, latestUser: latestUser) }
        return retained.joined(separator: "。")
    }

    private func isUserRestatementClause(_ clause: String, latestUser: String) -> Bool {
        let candidate = comparableText(clause)
        let user = comparableText(latestUser)
        guard candidate.count >= 4, user.count >= 4 else { return false }
        if candidate == user || candidate.contains(user) || user.contains(candidate) { return true }

        // Catch a long second-person re-narration that merely swaps a few words while retaining a
        // substantial concrete phrase. A five-character floor still permits a warm reply to pick
        // up one short detail (for example “很晚” or “不负责”) without being stripped.
        let mentionsSecondPerson = candidate.contains("你") || candidate.contains("您")
        if candidate.count >= 14, mentionsSecondPerson, sharesRun(candidate, user, minRun: 5) {
            return true
        }

        let mirrorOpenings = ["你说", "你提到", "刚才你说", "听起来你", "你的回答是", "也就是说你"]
        let startsAsMirror = mirrorOpenings.contains { candidate.hasPrefix(comparableText($0)) }
        let candidatePairs = characterPairs(candidate)
        let userPairs = characterPairs(user)
        let overlap = candidatePairs.intersection(userPairs).count
        let candidateCoverage = Double(overlap) / Double(max(candidatePairs.count, 1))
        let userCoverage = Double(overlap) / Double(max(userPairs.count, 1))
        return (startsAsMirror && candidateCoverage >= 0.25) ||
            candidateCoverage >= 0.5 ||
            (candidateCoverage >= 0.42 && userCoverage >= 0.42)
    }

    /// Removes an interpretive descriptor the user never used in their card narrative (e.g. "张力",
    /// "被拉扯") so the post-card reply stays in the user's own words. Reuses the same clause split as
    /// restatement removal; a descriptor is allowed whenever the user's interpretation contains it.
    private func removingUnsupportedCardDescriptor(from reflection: String) -> String {
        let clean = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return clean }
        let interpretation = comparableText(session.context.cardInterpretation ?? "")
        let descriptors = [
            "张力", "被拉扯", "拉扯", "挣扎", "对抗", "撕扯", "权威", "冲突",
            "复杂的可能性", "好坏交织", "矛盾感", "努力和限制", "新的想法", "新想法",
        ]
        let separators = CharacterSet(charactersIn: "。！？!?；;\n")
        let retained = clean.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { clause in
                let c = comparableText(clause)
                return !descriptors.contains { descriptor in
                    let d = comparableText(descriptor)
                    return c.contains(d) && !interpretation.contains(d)
                }
            }
        return retained.joined(separator: "。")
    }

    /// No workflow guard, de-duplication rule, or field-collection decision belongs in a visible
    /// reply. These phrases appeared in test conversations when a model tried to explain why it
    /// was moving on; suppressing them keeps the repair conversational.
    private func containsVisibleProcessLanguage(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "这个方向我们已经说清楚了", "不再继续拆", "我们先不重复追问",
            "不重复追问", "先不重复追问", "字段", "流程", "阶段", "状态机",
            "已经完成这个方向", "收集下一个"
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    /// The model sometimes emits a technically faithful but user-hostile field export. A
    /// deterministic prose summary is safer than asking the user to correct a malformed report.
    private func looksLikeFieldExportNarrative(_ text: String) -> Bool {
        let clean = comparableText(text)
        let paragraphCount = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let sentenceCount = text.filter { "。！？!?".contains($0) }.count
        if text.count > 460 || paragraphCount > 4 || sentenceCount > 7 {
            return true
        }
        if clean.contains(comparableText("担心很伤心")) ||
            clean.contains(comparableText("也觉得自己很担心")) ||
            clean.contains(comparableText("也让你开始担心都不是")) ||
            clean.contains(comparableText("你最介意的是都不是")) ||
            clean.contains(comparableText("担心让我最担心")) ||
            clean.contains(comparableText("烦烦躁")) ||
            clean.contains(comparableText("这个表达有点抽象")) {
            return true
        }
        let markers = [
            "这次具体发生的是", "当时还夹着这些现实情况", "你自己建立的画面联系是",
            "你认为需要被承认的现实情况是", "你认为仍可选择或调整的部分是",
            "当时的自我评价很重", "那张图让你想到"
        ]
        let count = markers.filter { clean.contains(comparableText($0)) }.count
        return count >= 2 || (clean.contains("：") && count >= 1)
    }

    /// Integrated prose must be a rewrite, not a database-safe concatenation of prior turns.
    /// Long literal runs are rejected independently of topic, person, or scenario.
    private func hasLongVerbatimUserRun(_ text: String) -> Bool {
        session.messages
            .filter { $0.role == .user && comparableText($0.content).count >= 18 }
            .contains { sharesRun(text, $0.content, minRun: 16) }
    }

    /// A second-person narrative must not contain an unconverted first-person clause. Direct
    /// quotations are not needed in these summaries, so this is a general perspective check.
    private func hasMixedNarrativePerspective(_ text: String) -> Bool {
        let clean = comparableText(text)
        guard clean.contains("你") else { return false }
        let firstPersonFrames = [
            "我觉得", "我感觉", "我认为", "我担心", "我害怕", "我开始", "我自己",
            "让我", "然后我", "但是我",
        ]
        return firstPersonFrames.contains { clean.contains(comparableText($0)) }
    }

    /// Catch connective collisions and duplicated fragments without enumerating case content.
    private func hasBrokenNarrativeSyntax(_ text: String) -> Bool {
        let clean = comparableText(text)
        let collisions = [
            "可能让有可能", "可能让可能", "也开始担心很", "你也认为有可能就是",
            "让你你", "你你", "也也", "然后然后", "可能可能",
        ]
        if collisions.contains(where: { clean.contains(comparableText($0)) }) {
            return true
        }
        let clauses = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .map(comparableText)
            .filter { $0.count >= 6 }
        return Set(clauses).count != clauses.count
    }

    private func cardNarrativeRepeatsLockedBaseline(_ text: String) -> Bool {
        guard session.condition.usesCard,
              session.cardMappingConfirmed,
              [.reflectionNarrativeConfirmation, .optionalAction, .actionConfirmation,
               .narrativeConfirmation]
                .contains(session.workflowPhase) else {
            return false
        }
        if session.context.confirmedTrackingCues.contains(where: {
            narrativeMentionsTrackingCue($0, text: comparableText(text))
        }) {
            return true
        }
        guard var baseline = session.lockedBaselineNarrative.map(comparableText),
              !baseline.isEmpty else { return false }
        var candidate = comparableText(text)
        if let event = session.context.eventDescription.flatMap(concreteEventClause) {
            let eventText = comparableText(event)
            baseline = baseline.replacingOccurrences(of: eventText, with: "")
            candidate = candidate.replacingOccurrences(of: eventText, with: "")
        }
        guard baseline.count >= 18, candidate.count >= 30 else { return false }
        let characters = Array(baseline)
        for start in 0...(characters.count - 18) {
            let phrase = String(characters[start..<(start + 18)])
            if candidate.contains(phrase) { return true }
        }
        return false
    }

    private func cardDeltaNarrativeMissesRequiredFunctions(_ text: String) -> Bool {
        guard session.condition.usesCard,
              session.cardMappingConfirmed,
              [.reflectionNarrativeConfirmation, .optionalAction, .actionConfirmation,
               .narrativeConfirmation]
                .contains(session.workflowPhase) else {
            return false
        }
        let clean = comparableText(text)
        let relationshipFrames = ["画面", "关系", "联系", "对应", "相似", "放在一起"]
        guard relationshipFrames.contains(where: {
            clean.contains(comparableText($0))
        }) else {
            return true
        }
        if let shift = session.cardMeaningShiftResponse,
           cardMeaningShiftExpressesNoChange(shift) {
            let noChangeFrames = ["没有变化", "没有改变", "没改变", "没有新的理解", "仍然是原来的理解"]
            if !noChangeFrames.contains(where: {
                clean.contains(comparableText($0))
            }) {
                return true
            }
        }
        return false
    }

    /// Quality is evaluated by the functions a narrative must perform, not by whether it matches
    /// a scenario template. Missing evidence causes a safe rewrite before the user is asked to
    /// confirm the text.
    private func integratedNarrativeMissesRequiredFunctions(_ text: String) -> Bool {
        let clean = comparableText(text)
        switch session.workflowPhase {
        case .tenderGroundingConfirmation:
            if !session.context.emotions.isEmpty {
                let emotionIsPresent = session.context.emotions.contains { emotion in
                    let significant = comparableText(emotion).filter {
                        !"很有点的太较些".contains($0)
                    }
                    return !significant.isEmpty && significant.contains {
                        clean.contains(String($0))
                    }
                }
                if !emotionIsPresent { return true }
            }
            let hasSelfEvaluation =
                session.context.selfJudgment?.isEmpty == false ||
                !groundedSemanticRelations(kinds: [.selfEvaluation], in: session.latestAnalysis).isEmpty
            if hasSelfEvaluation {
                let distinctionFrames = [
                    "整个人", "整体评价", "整体判断", "全盘否定", "不等于", "不能据此",
                    "具体处境", "具体表现",
                ]
                if !distinctionFrames.contains(where: {
                    clean.contains(comparableText($0))
                }) {
                    return true
                }
            }
            return false

        case .contextConfirmation:
            let relevantCues = session.context.confirmedTrackingCues.filter {
                !plainTrackingClause($0).isEmpty
            }
            if !relevantCues.isEmpty,
               !relevantCues.contains(where: { narrativeMentionsTrackingCue($0, text: clean) }) {
                return true
            }
            if session.trackingContextLinkResponse?.isEmpty == false {
                let relationFrames = [
                    "你认为", "你觉得", "对你来说", "可能", "相互", "影响", "更难",
                    "更容易", "联系在一起",
                ]
                if !relationFrames.contains(where: {
                    clean.contains(comparableText($0))
                }) {
                    return true
                }
            }
            return false

        default:
            return false
        }
    }

    private func narrativeMentionsTrackingCue(_ cue: TrackingCue, text: String) -> Bool {
        let anchors: [String] = switch cue.insight?.metric {
        case .sleepDuration, .sleepTiming, .sleepWakeTime, .sleepContinuity:
            ["睡", "休息", "作息"]
        case .steps:
            ["活动", "运动", "走动"]
        case .heartRateVariability, .restingHeartRate:
            ["身体", "心率"]
        case .calendarLoad:
            ["日程", "安排", "时间"]
        case .screenTime:
            ["屏幕", "使用"]
        case .weather:
            ["天气", "环境"]
        case nil:
            [plainTrackingClause(cue)]
        }
        return anchors.contains { anchor in
            let normalized = comparableText(anchor)
            return !normalized.isEmpty && text.contains(normalized)
        }
    }

    /// An accuracy gate needs an actual synthesis. A short acknowledgement such as “记下了”
    /// gives the user nothing concrete to confirm and previously allowed a model placeholder to
    /// bypass the natural deterministic summary.
    private func isGenericIntegratedNarrative(_ text: String) -> Bool {
        let clean = comparableText(text)
        if clean.count < 20 { return true }
        let placeholders = [
            "我记下了", "先记下", "这个具体部分", "刚才这些内容", "这部分已经记录",
        ]
        return placeholders.contains { clean.contains(comparableText($0)) }
    }

    private func containsUnsupportedCardSymbolicMeaning(_ text: String) -> Bool {
        let visible = comparableText(text)
        // A word used elsewhere in the life story is not automatically a meaning the user gave
        // the image. Only their own card description, connection, and meaning-shift answer can
        // license interpretive language in the card synthesis.
        let userEvidence = comparableText([
            session.context.cardInterpretation,
            session.cardLifeConnection,
            session.cardMeaningShiftResponse,
        ].compactMap { $0 }.joined(separator: " "))
        let symbolicTerms = [
            "焦灼", "反转", "危险", "压迫", "隐藏", "欺骗", "张力", "被拉扯", "拉扯",
            "挣扎", "对抗", "撕扯", "权威", "冲突", "复杂的可能性", "好坏交织",
            "矛盾感", "努力和限制", "新的想法",
        ]
        return symbolicTerms.contains { term in
            let normalized = comparableText(term)
            return visible.contains(normalized) && !userEvidence.contains(normalized)
        }
    }

    private func containsInventedMeaningChangeAfterNoChange(_ text: String) -> Bool {
        guard let response = session.cardMeaningShiftResponse,
              cardMeaningShiftExpressesNoChange(response) else { return false }
        let visible = comparableText(text)
        let inventedChangeTerms = [
            "重新理解", "新看见", "新的看见", "发生变化", "改变了你的理解",
            "带来新的理解", "有了新的理解", "换了一个角度", "新的角度",
        ]
        return inventedChangeTerms.contains { visible.contains(comparableText($0)) }
    }

    private func knownSelfEvaluationPhrases() -> [String] {
        var candidates: [String] = []
        if let judgment = session.context.selfJudgment {
            candidates.append(judgment)
        }
        for relation in groundedSemanticRelations(
            kinds: [.selfEvaluation],
            in: session.latestAnalysis
        ) {
            candidates.append(relation.target)
            candidates.append(relation.source)
        }
        var result: [String] = []
        for candidate in candidates {
            let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = comparableText(clean)
            guard normalized.count >= 2, normalized.count <= 36 else { continue }
            for phrase in [clean, selfEvaluationCore(from: clean)] {
                let phraseNormalized = comparableText(phrase)
                guard phraseNormalized.count >= 2,
                      !result.contains(where: { comparableText($0) == phraseNormalized }) else {
                    continue
                }
                result.append(phrase)
            }
        }
        return result
    }

    private func selfEvaluationCore(from phrase: String) -> String {
        var value = phrase.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let leadingFrames = [
            "我觉得自己", "我感觉自己", "我认为自己", "我觉得", "我感觉", "我认为",
            "我就是", "我是", "我很", "我太", "自己很", "自己太", "自己就是",
        ]
        if let frame = leadingFrames.first(where: { value.hasPrefix($0) }) {
            value.removeFirst(frame.count)
        }
        let trailingFrames = ["的人", "了"]
        if let frame = trailingFrames.first(where: { value.hasSuffix($0) }) {
            value.removeLast(frame.count)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func containsKnownSelfEvaluation(_ text: String) -> Bool {
        let clean = comparableText(text)
        return knownSelfEvaluationPhrases().contains { phrase in
            let label = comparableText(phrase)
            return !label.isEmpty && clean.contains(label)
        }
    }

    private func containsGlobalIdentityLabel(_ text: String) -> Bool {
        containsKnownSelfEvaluation(text)
    }

    private func situationSpecificText(_ text: String) -> String {
        var value = text
        for phrase in knownSelfEvaluationPhrases() {
            value = value.replacingOccurrences(
                of: phrase,
                with: "把一次具体处境扩大成了对整个人的判断"
            )
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sharesRun(_ candidate: String, _ user: String, minRun: Int) -> Bool {
        let characters = Array(candidate)
        guard characters.count >= minRun, user.count >= minRun else { return false }
        for start in 0...(characters.count - minRun) {
            if user.contains(String(characters[start..<(start + minRun)])) { return true }
        }
        return false
    }

    private func comparableText(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
    private func characterPairs(_ text: String) -> Set<String> {
        let values = Array(text)
        guard values.count > 1 else { return [] }
        return Set((0..<(values.count - 1)).map { String([values[$0], values[$0 + 1]]) })
    }
    private func isUncertainAnswer(_ text: String) -> Bool {
        let clean = comparableText(text)
        return ["不知道", "不确定", "不清楚", "说不出来", "没有", "跳过"].contains { clean.contains($0) }
    }

    private func isForcedCardBinaryQuestion(_ question: String) -> Bool {
        let clean = comparableText(question)
        return clean.contains("还是") && (clean.contains("更") || clean.contains("先") || clean.contains("是"))
    }

    private func openCardStoryQuestion() -> String {
        switch session.workflowPhase {
        case .cardAssociation:
            return "你觉得接下来可能会发生什么？"
        case .cardNarrativeDeepening:
            return "沿着你刚才的想法，这个画面里的故事接下来可能会怎么发展？"
        default:
            return "看到这张牌，你觉得画面里正在发生什么？"
        }
    }

    private func containsUnlicensedCardStoryAssumption(_ text: String) -> Bool {
        let visible = comparableText(text)
        let userImageWords = comparableText(session.context.cardInterpretation ?? "")
        let assumptions = [
            "她", "他", "这个人", "继续这样做", "继续做", "自然的靠近", "靠近",
            "犹豫", "等待", "关系", "冲突", "担心", "着急", "害怕",
        ]
        return assumptions.contains { assumption in
            let normalized = comparableText(assumption)
            return visible.contains(normalized) && !userImageWords.contains(normalized)
        }
    }

    private func userHasNoAdditionalCircumstances(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "没有了", "没有其他", "没别的", "没有更多", "想不到", "说不出来", "不确定", "不知道"
        ]
        return phrases.contains { clean == comparableText($0) || clean.contains(comparableText($0)) }
    }

    /// A candid answer may be “暂时没有” or “不确定”, but a joke or unrelated fragment must not
    /// silently become the person's chosen responsibility, boundary, or change in a saved record.
    private func isUsableCandidAgencyResponse(_ text: String) -> Bool {
        let clean = comparableText(text)
        guard clean.count >= 2 else { return false }
        if isUncertainAnswer(text) || userDeclinesAction(text) { return true }

        let obviousJokes = ["我是大帅哥", "我是美女", "我是天才", "哈哈", "hehe", "lol"]
        if obviousJokes.contains(where: { clean == comparableText($0) }) { return false }

        let actionWords = [
            "改", "调整", "整理", "记录", "写", "问", "请教", "回复", "沟通", "说明",
            "准备", "检查", "测试", "确认", "拆", "分开", "开始", "尝试", "停", "休息",
            "边界", "拒绝", "求助", "减少", "保留", "安排", "计划", "耐心", "冷静",
            "努力", "放慢", "听完"
        ]
        if actionWords.contains(where: { clean.contains(comparableText($0)) }) { return true }

        let knownSituationWords = [
            session.context.eventDescription,
            session.context.personalMeaning,
            session.cardLifeConnection,
            session.cardMeaningShiftResponse,
        ]
        .compactMap { $0 }
        .flatMap { value in
            value.components(separatedBy: CharacterSet(charactersIn: "，。；、！？!? "))
                .filter { comparableText($0).count >= 2 }
        }
        return knownSituationWords.contains { word in
            let normalized = comparableText(word)
            return normalized.count >= 2 && clean.contains(normalized)
        }
    }

    private func isBroadCandidAgencyAnswer(_ text: String) -> Bool {
        let clean = comparableText(text)
        let broadAnswers = [
            "更耐心", "更耐心一点", "更耐心一些", "耐心一点", "耐心一些",
            "更冷静", "更冷静一点", "冷静一点", "更努力", "更努力一点",
            "努力一点", "做好一点", "注意一点",
        ]
        return broadAnswers.contains(clean)
    }

    private func isLowInformationBoundaryAnswer(_ text: String) -> Bool {
        let clean = comparableText(text)
        let exact = [
            "不知道", "不清楚", "不确定", "没有", "没有了", "没有吧", "不太清楚",
            "说不出来", "我也说不出来", "还没想好", "想不到", "不晓得",
        ].map(comparableText)
        if exact.contains(clean) { return true }
        return ["我不知道", "我不清楚", "暂时说不出来", "现在想不到"].contains {
            clean == comparableText($0)
        }
    }

    private func isConversationRupture(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "这个问题有些重复", "这个问题重复了", "问题有些重复", "问题重复了",
            "你已经问过了", "刚才问过了", "怎么又问", "一直在问同一个",
            "不要再问这个", "别再问这个", "又是这个问题",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func isClarificationRequest(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "这是什么意思", "什么意思", "你是什么意思", "这个问题是什么意思",
            "没听懂", "没有听懂", "听不明白", "不明白你在问什么", "我不明白",
            "能说具体一点吗", "可以说具体一点吗", "能说直白一点吗", "可以说简单一点吗",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func isPreCardReflectionState(_ state: ReflectionState) -> Bool {
        isDisclosureState(state) || [
            ReflectionState.tenderGrounding, .tenderExploration, .trackingReview, .readinessCheck,
            .cardInterpretation, .attributionReflection, .actionSelection,
        ].contains(state)
    }

    /// Emergency compatibility path used only when semantic analysis produced no locally
    /// admissible ResponsePlan. Normal disclosure turns are selected from the Analyzer's
    /// grounded semantic relations and typed plan; an empty legacy field must never by itself
    /// determine the visible question. A direct "没有明显感觉" answer still counts as explored.
    private func nextDepthDisclosureState() -> ReflectionState? {
        let hasGroundedSelfEvaluation = !groundedSemanticRelations(
            kinds: [.selfEvaluation],
            in: session.latestAnalysis
        ).isEmpty
        // An explicit self-evaluation is already lived-experience evidence that needs a direct
        // response. Do not ignore it merely because a separate emotion array is empty.
        if !session.personalMeaningExplorationCompleted,
           session.context.selfJudgment?.isEmpty == false || hasGroundedSelfEvaluation {
            return .selfJudgment
        }
        if session.context.emotions.isEmpty,
           session.dialogueProgress.unresolvedDimensions.contains(.emotion) {
            return .emotionDisclosure
        }
        // When a person has already named both a feeling and a global conclusion, asking a
        // second generic “what do you feel now?” merely repeats the same emotion. Clarify the
        // meaning behind that conclusion first. A bodily response remains welcome when offered,
        // but is never a compulsory field before tender grounding can begin.
        if !session.personalMeaningExplorationCompleted {
            return .selfJudgment
        }
        if !session.bodyExplorationCompleted {
            session.bodyExplorationCompleted = true
            session.dialogueProgress.complete(.body)
            appendUnique("身体感受未单独描述", to: &session.context.uncertainties)
        }
        if session.context.contextualConstraints.isEmpty,
           session.context.uncertainties.isEmpty,
           session.context.personalContributions.isEmpty {
            return .contextDisclosure
        }
        return .trackingPermission
    }

    private func personalMeaningResponseIsSubstantive(_ text: String) -> Bool {
        let clean = comparableText(text)
        guard clean.count >= 3 else { return false }
        guard let judgment = session.context.selfJudgment else { return true }
        let knownJudgment = comparableText(judgment)
        return knownJudgment.isEmpty ||
            (clean != knownJudgment && !knownJudgment.contains(clean))
    }

    private var hasEnoughDisclosureToStopCollecting: Bool {
        let substantiveUserTurns = session.messages.filter {
            $0.role == .user && !isLowInformationBoundaryAnswer($0.content) && comparableText($0.content).count >= 6
        }.count
        let hasEvent = session.context.eventDescription.map { !isLowInformationBoundaryAnswer($0) } == true
        let hasExperience = !session.context.emotions.isEmpty ||
            session.context.selfJudgment?.isEmpty == false ||
            !session.context.contextualConstraints.isEmpty ||
            substantiveUserTurns >= 3
        return hasEvent && hasExperience
    }

    private var shouldCompleteStructuredDisclosure: Bool {
        if session.structuredDisclosureAssistantTurns >= maximumStructuredDisclosureAssistantTurns {
            return true
        }
        return session.structuredDisclosureAssistantTurns >= minimumStructuredDisclosureAssistantTurns
            && structuredDisclosureIsSufficient
    }

    /// The decision is deterministic and deliberately does not depend on the model's suggested
    /// next stage. It asks only whether the transcript contains an event, lived experience,
    /// self-appraisal/personal meaning, and at least one real-world condition or remaining
    /// uncertainty. At five assistant turns, missing parts remain explicitly uncertain.
    private var structuredDisclosureIsSufficient: Bool {
        let relations = groundedSemanticRelations(
            kinds: [
                .eventExperience, .conditionCapacity, .behaviorImpact, .selfEvaluation,
                .boundaryNeed, .controllablePart, .uncertainty, .unmetNeed,
            ],
            in: session.latestAnalysis
        )
        let hasEvent = session.context.eventDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasExperience = !session.context.emotions.isEmpty ||
            relations.contains { $0.kind == .eventExperience }
        let bodyExplored = session.bodyExplorationCompleted
        let meaningExplored =
            session.personalMeaningExplorationCompleted &&
            (
                session.context.selfJudgment?.isEmpty == false ||
                session.context.personalMeaning?.isEmpty == false ||
                relations.contains {
                    [.selfEvaluation, .uncertainty, .unmetNeed].contains($0.kind)
                } ||
                !session.context.uncertainties.isEmpty
            )
        let hasCondition = !session.context.contextualConstraints.isEmpty ||
            !session.context.uncertainties.isEmpty ||
            !session.context.personalContributions.isEmpty ||
            relations.contains {
                [
                    .conditionCapacity, .behaviorImpact, .boundaryNeed,
                    .controllablePart, .uncertainty, .unmetNeed,
                ].contains($0.kind)
            }
        return hasEvent && hasExperience && bodyExplored && meaningExplored && hasCondition
    }

    private func recordStructuredDisclosureAssistantTurn(action: String) {
        session.structuredDisclosureAssistantTurns = min(
            session.structuredDisclosureAssistantTurns + 1,
            maximumStructuredDisclosureAssistantTurns
        )
        session.studyEvents.append(.init(stage: session.stage, action: action))
    }

    private func disclosureStateForMinimumTurn(after state: ReflectionState) -> ReflectionState {
        switch state {
        case .eventDisclosure: return .emotionDisclosure
        case .emotionDisclosure, .bodilyResponse: return .selfJudgment
        case .selfJudgment: return .contextDisclosure
        case .contextDisclosure: return .contextDisclosure
        default: return state
        }
    }

    /// Last-resort goal for provider/schema failures. This field-completion policy is deliberately
    /// kept outside the normal Analyzer -> ResponsePlan -> Swift validation -> Writer path.
    private func structuredDisclosureMissingGoal(fallbackState: ReflectionState) -> String {
        let hasGroundedSelfEvaluation = !groundedSemanticRelations(
            kinds: [.selfEvaluation],
            in: session.latestAnalysis
        ).isEmpty
        if !session.personalMeaningExplorationCompleted,
           session.context.selfJudgment?.isEmpty == false || hasGroundedSelfEvaluation {
            return "ask what concrete concern or feared consequence sits behind the self-evaluation the user just expressed. Acknowledge the event and the self-doubt first; do not ask for a missing emotion, another technical detail, or a different incident"
        }
        if session.context.emotions.isEmpty {
            return "ask in plain language what feeling was most present when the event was happening; do not ask for another technical detail or a specific moment"
        }
        if !session.bodyExplorationCompleted {
            return "ask one open, ordinary question about what the user feels when thinking about the event now. Do not require a bodily reaction, ask where a feeling is located, or offer a list of bodily examples. An emotion, thought, bodily response, or no obvious feeling are all complete answers"
        }
        if !session.personalMeaningExplorationCompleted {
            return "ask what the situation led the user to conclude about themselves or what outcome it made them fear. If they used a global label, ask what concrete concern sits behind that label; do not repeat the label as fact, infer an answer, or ask for another project detail"
        }
        if session.context.contextualConstraints.isEmpty && session.context.uncertainties.isEmpty {
            return "ask for one real condition, limit, conflict, or still-uncertain part around the situation; do not investigate technical implementation details"
        }
        return questionGoal(for: fallbackState)
    }

    private func shouldCloseDisclosureAfterBoundaryAnswer(_ text: String) -> Bool {
        guard isLowInformationBoundaryAnswer(text), hasEnoughDisclosureToStopCollecting else { return false }
        let recentUserAnswers = session.messages
            .filter { $0.role == .user }
            .suffix(3)
        return recentUserAnswers.filter { isLowInformationBoundaryAnswer($0.content) }.count >= 2
    }

    private func closeRemainingDisclosureAsUncertain(reason: String) {
        for dimension in [ReflectionDimension.event, .emotion, .body, .selfJudgment, .personalMeaning, .context] {
            if session.dialogueProgress.unresolvedDimensions.contains(dimension) {
                session.dialogueProgress.complete(dimension)
            }
        }
        if !session.bodyExplorationCompleted {
            session.bodyExplorationCompleted = true
            appendUnique("身体感受暂不确定", to: &session.context.uncertainties)
        }
        if !session.personalMeaningExplorationCompleted {
            session.personalMeaningExplorationCompleted = true
            appendUnique("这件事背后的个人意义暂不确定", to: &session.context.uncertainties)
        }
        appendUnique("没有继续追问用户暂时无法或不愿细分的内容", to: &session.context.uncertainties)
        session.studyEvents.append(.init(stage: session.stage, action: reason))
    }

    private func isDisclosureState(_ state: ReflectionState) -> Bool {
        [.eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure].contains(state)
    }

    private func isAskingForScaffolding(_ text: String) -> Bool {
        let clean = comparableText(text)
        return ["不知道怎么说", "不知道怎么回答", "可以具体一点", "能具体一点"].contains {
            clean.contains(comparableText($0))
        }
    }

    private func cardDoesNotFit(_ text: String) -> Bool {
        let clean = comparableText(text)
        return [
            "没什么关系", "没有关系", "没联系", "没有联系", "不相关", "不贴合", "不适合",
            "和我没关系", "和这件事没关系", "对不上", "这张卡不贴合", "这张图不贴合",
        ].contains {
            clean.contains(comparableText($0))
        }
    }

    private func userHasNoMoreCardDescription(_ text: String) -> Bool {
        let clean = comparableText(text)
        return [
            "没有", "没有了", "没了", "没有更多了", "没有别的了", "没有其他了",
            "没什么要补充了", "就这些", "就这样", "暂时没有了",
        ].map(comparableText).contains(clean)
    }

    private func userCannotInterpretCard(_ text: String) -> Bool {
        let clean = comparableText(text)
        let exact = [
            "想不到", "想不出来", "不知道", "看不出来", "看不懂", "没感觉", "没有感觉",
            "没什么感觉", "没有联想", "没联想", "没想法", "不知道怎么说", "不知道怎么解读",
        ].map(comparableText)
        if exact.contains(clean) { return true }
        let phrases = [
            "完全想不到", "实在想不到", "还是想不到", "仍然想不到",
            "有点想不到", "一下子想不到", "一下子有点想不到",
            "有点难想到", "很难想到", "没有任何联想",
            "不知道该怎么解读", "不知道能说什么", "这张图看不懂",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func userCannotConnectCard(_ text: String) -> Bool {
        if cardDoesNotFit(text) || userCannotInterpretCard(text) || userHasNoMoreCardDescription(text) {
            return true
        }
        let clean = comparableText(text)
        let phrases = [
            "难以联想", "联想不到", "想不到和我的关系", "想不到和这件事的关系",
            "没法联系起来", "不知道怎么联系", "没有让我想到什么",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func cardConnectionIsExplicitlyAbsent(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "没有关系", "没什么关系", "没有联系", "没联系", "不相关", "和我没关系",
            "和这件事没关系", "对不上", "完全没有关系", "没有任何联系",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func cardMeaningShiftExpressesNoChange(_ text: String) -> Bool {
        let clean = comparableText(text)
        let phrases = [
            "没有变化", "没变化", "没有改变", "没改变", "和原来一样", "还是原来的理解",
            "没有新的理解", "没什么新理解", "没有新看法", "没带来变化",
            "只是联系起来了", "只是场景有点像", "只是想到这个", "没有别的感觉",
        ]
        return phrases.contains { clean.contains(comparableText($0)) }
    }

    private func appendCardInterpretation(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard let existing = session.context.cardInterpretation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !existing.isEmpty else {
            session.context.cardInterpretation = clean
            return
        }
        guard !comparableText(existing).contains(comparableText(clean)) else { return }
        session.context.cardInterpretation = "\(existing)；\(clean)"
    }

    /// A broad yes/no fit does not establish what the user connected. The workflow waits for at
    /// least one concrete phrase authored by the user before reflection or synthesis can advance.
    private func isWorthAnalyzingCardConnectionAnswer(_ text: String) -> Bool {
        let clean = comparableText(text)
        let vagueAnswers = [
            "有一些类似", "有点类似", "有点像", "比较像", "差不多", "挺像", "很像",
            "是的", "对", "对的", "贴近", "有关系", "可能吧", "也许吧", "不确定",
        ].map(comparableText)
        let withoutHedge = ["我觉得", "我感觉", "感觉", "好像"].reduce(clean) { value, prefix in
            value.hasPrefix(comparableText(prefix))
                ? String(value.dropFirst(comparableText(prefix).count))
                : value
        }
        if vagueAnswers.contains(clean) || vagueAnswers.contains(withoutHedge) ||
            isLowInformationBoundaryAnswer(text) {
            return false
        }
        // This only decides whether the Analyzer should inspect the answer. Completion is decided
        // later by grounded imageStructure / realityStructure / imageRealityMapping relations,
        // never by length, connective words, or a scenario vocabulary.
        return clean.count >= 2
    }

    private func containsUnsupportedVisibleInference(
        _ text: String,
        responsePlan: ResponsePlan? = nil
    ) -> Bool {
        let visible = comparableText(text)
        let userEvidence = comparableText(
            session.messages
                .filter { $0.role == .user }
                .map(\.content)
                .joined(separator: " ")
        )
        let evidenceRequiredTerms = [
            "焦虑", "羞愧", "内疚", "逃避", "躲开", "压抑", "抗拒", "怀疑自己",
            "对自己的担心", "担心自己", "害怕自己不够好", "希望被理解", "说不出口",
            "还有期待", "一丝希望", "难集中注意力", "注意力很难集中", "无法集中注意力",
            "集中不了注意力", "注意力不集中", "难专注", "分心"
        ]
        let planAllowsSelfEvaluationLanguage =
            responsePlan?.relationKinds.contains(.selfEvaluation) == true
        let selfEvaluationTerms = [
            "怀疑自己", "对自己的担心", "担心自己", "害怕自己不够好",
        ]
        if evidenceRequiredTerms.contains(where: { term in
            let normalized = comparableText(term)
            guard visible.contains(normalized), !userEvidence.contains(normalized) else {
                return false
            }
            return !(planAllowsSelfEvaluationLanguage &&
                selfEvaluationTerms.contains(where: {
                    normalized == comparableText($0)
                }))
        }) {
            return true
        }
        let unsupportedBodyPrompt = ["身体哪里", "身体哪个部位", "感觉位于身体"].contains {
            visible.contains(comparableText($0))
        }
        return unsupportedBodyPrompt && session.context.bodilyResponses.isEmpty
    }

    private func containsDivinatoryCardLanguage(_ text: String) -> Bool {
        let visible = comparableText(text)
        let alwaysForbidden = [
            "预示", "命中注定", "命运", "牌在告诉你", "这张牌在告诉你", "牌说明你",
            "这张牌意味着", "象征你的内心", "象征着你的内心", "暗示你的内心",
        ]
        if alwaysForbidden.contains(where: { visible.contains(comparableText($0)) }) { return true }
        // Even when the user used one of these words, the model does not need to restate or extend
        // it in an ordinary card turn. During a synthesis the guard falls back to deterministic
        // assembly, which can preserve the user's exact sentence without inventing a second symbol.
        let interpretiveMarkers = ["象征", "暗示", "意味着", "代表"]
        return interpretiveMarkers.contains { visible.contains(comparableText($0)) }
    }

    private func isAbstractChoiceQuestion(_ text: String) -> Bool {
        let visible = comparableText(text)
        return [
            "最想先回应哪一点", "最想回应哪一点", "哪一点最贴近", "补充哪一点",
            "哪一部分最让你放不下"
        ].contains {
            visible.contains(comparableText($0))
        }
    }

    private func containsPressuringOrOrnateLanguage(_ text: String) -> Bool {
        let visible = comparableText(text)
        let disallowed = [
            "心里最沉", "最难熬", "最难说清", "内心深处", "真正的自己",
            "触动你", "最放不下", "值得被看到", "意味着什么", "这样的坚持确实不容易",
            "带来一丝希望", "完成目标的可能性", "这样的需求很自然", "很多人都会有",
            "特别为难", "这种双重压力", "心态变得更沉重",
            "加重挫败", "这种卡住感", "束手无策", "很难熬", "勇敢的选择",
            "这个想法很实际",
            // Tracking-derived context should remain direct everyday language. These phrases
            // invent a vague bodily experience and made the user unsure what the assistant meant.
            "没有完全放松下来", "一直绷着", "没有真正缓下来", "一直在硬撑",
            "硬撑着", "压力积在身体里", "压力积在身上", "身体在发出信号"
        ]
        return disallowed.contains { visible.contains(comparableText($0)) }
    }

    private func isSimpleGreeting(_ text: String) -> Bool {
        let clean = comparableText(text)
        return ["hello", "hi", "hey", "你好", "嗨", "哈喽", "哈啰", "在吗"].contains(clean)
    }

    private func emotionExperienceFallbackQuestion() -> String {
        return "这件事发生时，你当时最明显的感受是什么？"
    }

    private func personalMeaningFallbackQuestion() -> String {
        return "这件事之后，你最担心的是什么？"
    }

    private func questionMarkCount(_ text: String) -> Int {
        text.filter { $0 == "？" || $0 == "?" }.count
    }

    private func expectsVisibleQuestion(
        for state: ReflectionState,
        requiresIntegratedNarrative: Bool,
        integratedNarrativeAccuracyCheck: Bool
    ) -> Bool {
        if requiresIntegratedNarrative { return integratedNarrativeAccuracyCheck }
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure, .trackingReview, .cardInterpretation:
            return true
        case .attributionReflection:
            return [
                ReflectionWorkflowPhase.cardConnection,
                .cardMappingConfirmation,
                .candidCircumstances,
                .cardMeaningShift,
                .candidAgency,
            ].contains(session.workflowPhase)
        default:
            return false
        }
    }

    private func cardMeaningShiftQuestion() -> String {
        return "把刚才说的现实情况和你对画面的理解放在一起后，你现在会怎么理解那件事或当时的自己？没有变化也可以。"
    }

    private func isSupportedEmotionExtraction(_ candidate: String) -> Bool {
        let clean = comparableText(candidate)
        guard !clean.isEmpty, clean.count <= 24 else { return false }
        guard let judgment = session.context.selfJudgment.map(comparableText),
              !judgment.isEmpty else {
            return true
        }
        return !judgment.contains(clean) && !clean.contains(judgment)
    }

    private func isSupportedBodyExtraction(_ candidate: String) -> Bool {
        let clean = comparableText(candidate)
        guard !clean.isEmpty, clean.count <= 40 else { return false }
        return !session.context.emotions.contains { emotion in
            let value = comparableText(emotion)
            return value.contains(clean) || clean.contains(value)
        }
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, !values.contains(clean) { values.append(clean) }
    }
    private func merge(_ candidates: [String], into values: inout [String]) { candidates.forEach { appendUnique($0, to: &values) } }

    private func discoverResumableSession() async {
        guard cloudSyncEnabled else { return }
        isCheckingForResume = true
        defer { isCheckingForResume = false }
        do {
            let remoteSessions = try await RemoteAPIService.shared.listReflectionSessions()
            for item in remoteSessions where item.stage != ReflectionState.completed.rawValue {
                guard !isRememberedCompletedRemoteSession(item.id) else { continue }
                guard let restored = try? decodeSession(item.payload),
                      restored.stage != .welcome,
                      restored.stage != .completed,
                      restored.workflowPhase != .complete else { continue }
                resumeCandidate = ResumableReflection(id: item.id, remoteID: item.id, session: restored, updatedAt: item.updatedAt)
                isResumeChoicePresented = true
                cloudStatus = "发现一条未完成的反思"
                return
            }
            cloudStatus = "云端已连接"
        } catch { cloudStatus = "暂时无法检查上次反思" }
    }

    private func decodeSession(_ payload: [String: JSONValue]) throws -> ReflectionSession {
        let data = try JSONEncoder().encode(payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReflectionSession.self, from: data)
    }

    private func resetToNewSession(syncImmediately: Bool) {
        cancelActiveResponse(removePartialReply: true)
        syncTask?.cancel()
        contextRefreshTask?.cancel()
        pendingCardReplyToMessageID = nil
        session = makeNewSession()
        invalidateTrackingRefreshForFreshSession()
        remoteSessionID = nil
        isPaused = false
        draft = ""
        saveNotice = ""
        canRetry = false
        isTyping = false
        isStreamingResponse = false
        isOpeningTrackingReview = false
        session.messages = []
        session.studyEvents = [.init(stage: .welcome, action: "session_started")]
        if syncImmediately { scheduleCloudSync(action: "new_reflection", delay: .zero) }
        scheduleHomeTrackingRefresh()
    }

    private func scheduleHomeTrackingRefresh() {
        guard preparesContextDataAutomatically else { return }
        contextRefreshTask?.cancel()
        let expectedSessionID = session.id
        contextRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isPreparingContextData {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  self.session.id == expectedSessionID,
                  self.session.stage == .welcome else { return }
            await self.refreshContextData()
        }
    }

    private func invalidateTrackingRefreshForFreshSession() {
        // Authorization belongs to the app process, while computed cues and their review status
        // belong to one reflection. Keep permission state, but invalidate the old snapshot.
        contextDataRefreshedAt = nil
        contextDataStatus = "新一轮反思将在需要时重新读取健康与日历记录"
    }

    private func makeNewSession() -> ReflectionSession {
        var fresh = ReflectionSession()
        fresh.protocolVersion = ReflectionSession.currentProtocolVersion
        fresh.protocolStage = .contextualDisclosure
        guard let access = studyAccess,
              access.isAvailable,
              let sequence = access.sequence,
              let period = access.period,
              let condition = access.condition else { return fresh }
        fresh.condition = condition
        fresh.studySequence = sequence
        fresh.studyPeriod = period
        return fresh
    }

    private func studyAccessMessage(for access: StudyAccess?) -> String {
        guard let access else { return "暂时无法确认本周安排，请稍后重试。" }
        switch access.status {
        case "active": return "本周反思已开放。"
        case "scheduled":
            if let date = access.availableAt {
                return "本周反思将于 \(date.formatted(date: .abbreviated, time: .shortened)) 开放。"
            }
            return "研究安排已创建，等待管理员开放。"
        case "disabled": return "当前研究安排已暂停，请联系研究人员。"
        default: return "当前尚未安排本周体验，请联系研究人员。"
        }
    }

    private func rememberCompletedRemoteSession(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: completedRemoteSessionDefaultsKey) ?? [])
        ids.insert(id)
        // Bound this local guard; the server remains the source of the completed record itself.
        UserDefaults.standard.set(Array(ids.sorted().suffix(100)), forKey: completedRemoteSessionDefaultsKey)
    }

    private func isRememberedCompletedRemoteSession(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: completedRemoteSessionDefaultsKey) ?? []).contains(id)
    }

    private func scheduleCloudSync(action: String, delay: Duration = .milliseconds(600)) {
        guard cloudSyncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                let snapshot = self.session
                let id: String
                if let existing = self.remoteSessionID { id = existing }
                else {
                    id = try await RemoteAPIService.shared.createReflectionSession(snapshot)
                    guard !Task.isCancelled else { return }
                    self.remoteSessionID = id
                }
                try await RemoteAPIService.shared.syncReflectionSession(id: id, reflection: snapshot, action: action)
                guard !Task.isCancelled else { return }
                self.cloudStatus = "已同步至云端 · \(Date.now.formatted(date: .omitted, time: .shortened))"
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.cloudStatus = "云端同步稍后重试"
            }
        }
    }
}
