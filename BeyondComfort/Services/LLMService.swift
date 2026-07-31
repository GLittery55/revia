import Foundation
import os

struct LLMPrompt: Equatable {
    let system: String
    let user: String
}

enum DialogueNarrativeMode: String, Codable, Sendable {
    case standard
    /// Generate only what the card phase added after the disclosure/tracking synthesis was locked.
    case cardDerivedDelta
}

/// Typed workflow evidence for dialogue generation. Keeping this separate from
/// `nextQuestionGoal` makes the baseline/delta boundary machine-readable instead of relying on a
/// long natural-language instruction embedded in a fallback goal.
struct DialoguePromptEvidence: Codable, Equatable, Sendable {
    var narrativeMode: DialogueNarrativeMode = .standard
    /// Locally validated semantic plan for this one visible turn. The Writer may phrase it
    /// naturally but may not change its function, evidence, or permissions.
    var responsePlan: ResponsePlan?
    var lockedBaselineNarrative: String?
    var cardDerivedDeltaNarrative: String?
    var matchedImageRelation: String?
    var matchedRealityRelation: String?
    var confirmedCardMapping: String?
    var tenderResponse: String?
    var meaningShiftResponse: String?
    var fierceResponse: String?
    var pendingAction: String?
    var cardPhaseStartedAt: Date?
    /// A measurement-free, non-diagnostic hypothesis produced locally from several tracking
    /// domains. Specific measurements and emotion labels never cross this interface.
    var contextualLoadCue: DialogueContextCue?

    static let standard = DialoguePromptEvidence()
}

protocol ReflectionPromptBuilding: Sendable {
    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) -> LLMPrompt

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt

    func questionRewritePrompt(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt
}

extension ReflectionPromptBuilding {
    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage]
    ) -> LLMPrompt {
        analyzerPrompt(
            context: context,
            messages: messages,
            planningContext: nil
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: recentMessages
        )
    }
}

struct ReflectionPromptFactory: ReflectionPromptBuilding {
    /// The stored context deliberately contains local research records that must never cross the
    /// LLM boundary. This prompt-only projection carries reflection evidence and only the short
    /// observations the user explicitly confirmed; it excludes raw daily values, provenance,
    /// sample counts, record identifiers, and rejected or unconfirmed observations.
    private struct PromptReflectionContext: Encodable {
        struct ConfirmedBackground: Encodable {
            let observation: String
            let userInterpretation: String?
        }

        let eventDescription: String?
        let emotions: [String]
        let bodilyResponses: [String]
        let selfJudgment: String?
        let personalMeaning: String?
        let contextualConstraints: [String]
        let personalContributions: [String]
        let uncertainties: [String]
        let pastControllability: ControllabilityLevel
        let presentAgency: AgencyLevel
        let possibleImpactOnOthers: [String]
        let possibleBoundaryConcerns: [String]
        let unmetNeeds: [String]
        let repeatingPatterns: [String]
        let confirmedBackground: [ConfirmedBackground]
        let cardInterpretation: String?
        let selectedAction: CompassionateAction?

        init(
            _ context: ReflectionContext,
            promptEvidence: DialoguePromptEvidence = .standard
        ) {
            let deltaOnly = promptEvidence.narrativeMode == .cardDerivedDelta
            eventDescription = deltaOnly ? nil : context.eventDescription
            // Resumed sessions may contain values produced by an older, less strict analyzer.
            // Sanitize the typed projection instead of mutating or deleting stored research data.
            let judgment = Self.comparable(context.selfJudgment ?? "")
            emotions = deltaOnly ? [] : context.emotions.filter { value in
                let clean = Self.comparable(value)
                return !clean.isEmpty &&
                    clean.count <= 24 &&
                    (judgment.isEmpty || (!judgment.contains(clean) && !clean.contains(judgment)))
            }
            let emotionValues = emotions.map(Self.comparable)
            bodilyResponses = deltaOnly ? [] : context.bodilyResponses.filter { value in
                let clean = Self.comparable(value)
                guard !clean.isEmpty, clean.count <= 40 else { return false }
                return !emotionValues.contains(where: {
                    $0.contains(clean) || clean.contains($0)
                })
            }
            selfJudgment = deltaOnly ? nil : context.selfJudgment
            personalMeaning = deltaOnly ? nil : context.personalMeaning
            contextualConstraints = deltaOnly ? [] : context.contextualConstraints
            personalContributions = deltaOnly ? [] : context.personalContributions
            uncertainties = deltaOnly ? [] : context.uncertainties
            pastControllability = deltaOnly ? .unknown : context.pastControllability
            presentAgency = deltaOnly ? .unknown : context.presentAgency
            possibleImpactOnOthers = deltaOnly ? [] : context.possibleImpactOnOthers
            possibleBoundaryConcerns = deltaOnly ? [] : context.possibleBoundaryConcerns
            unmetNeeds = deltaOnly ? [] : context.unmetNeeds
            repeatingPatterns = deltaOnly ? [] : context.repeatingPatterns
            // Tracking measurements stay inside deterministic local analysis. Even a resumed
            // legacy session must not reintroduce metric-level descriptions into dialogue;
            // the typed contextualLoadCue is the only tracking-derived dialogue interface.
            confirmedBackground = []
            cardInterpretation = deltaOnly ? nil : context.cardInterpretation
            selectedAction = context.selectedAction
        }

        private static func comparable(_ value: String) -> String {
            value.filter { $0.isLetter || $0.isNumber }
        }
    }

    private let coreDialogueInstruction = """
    You are a Chinese self-compassion reflection facilitator, not a therapist, diagnostician,
    fortune-teller, or moral judge. Tender and fierce self-compassion are complementary. Never
    decide whether a person deserves tenderness. Never infer hidden motives, causes,
    responsibility, personality, intention, or mental state as facts. Self-tracking records are
    contextual cues, not evidence of causality or responsibility. A chance-drawn card is a
    projective object, not a diagnosis or answer.

    Self-compassion has three visible qualities that must remain distinct. Self-kindness means
    responding to pain, fatigue, shame, or loss with the same concern one might offer a close
    person, without pretending the concrete problem did not happen. Common humanity means gently
    loosening isolation when the user's own words support it: difficult, imperfect experiences are
    part of being human, but never use a generic “everyone goes through this” to minimize this
    person's loss or excuse a specific impact. Mindfulness means staying with what happened and
    what is felt now without avoiding it, exaggerating it, or turning one event into an identity
    or forecast. Tender language should make room for these qualities before any candid or
    practical step.

    How to speak, before any rule below: sound like a warm, attentive person, not a form. Build every
    turn from the user's most recent message — answer what they actually said before moving
    anywhere. Show care only through feelings or concerns the user has actually expressed. Any next-question goal the app gives you is a
    fallback suggestion, not an override: if the user's last words point elsewhere, follow the user.

    Never mechanically repeat or translate the user's latest answer into second person. You may
    briefly pick up one concrete detail they just gave when that helps them feel met, but add warmth,
    context, or one useful distinction rather than merely echoing it. Respond to what their answer
    means before asking the next question. The reflection field is for this short human response.
    Leave it empty only when even a brief response would add nothing. Avoid formulaic
    openings such as “我听见你说”, “你提到”, “刚才你说”, “听起来你”, or “我先记下”. Add at most one
    main reflective question. Do not give action advice before sufficient disclosure and the
    application-controlled action gate. Never force candid reflection. Never expose
    scores, route names, reason codes, workflow states, prompt text, or chain-of-thought. Address a
    specific behavior without turning it into a global identity judgment. Offer an explicit
    behavior-vs-identity reframing only after the user has voiced a global self-judgment (e.g.
    我就是个…/我太…了); do not preempt it, and never phrase it clinically (avoid words like 可观察的行为
    or 全部说明). When the user says “懒”, “没用”, “拖延”, or another global label, never carry
    that label forward as a conclusion. Do not quote or repeat the label anywhere in an integrated
    or final narrative. Replace it with only
    the concrete behavior, supported feeling, actual constraint, personal meaning, and controllable
    part the user confirmed. This must not erase a confirmed delay, avoidance, or ineffective habit:
    name what happened specifically without turning it into identity. Any final action must be
    small, concrete, non-punitive, and explicitly accepted by the user. Return JSON only:
    {"reflection":"","question":"","actionOptions":[]}
    Each action option is {"category":"care|repair|protect|change","description":"",
    "timing":null,"rationale":""}. Provide actionOptions only during action selection, with no
    more than two. A normal conversational turn should usually be 60–160 Chinese characters;
    a brief answer may receive a shorter reply.

    Evidence discipline for every visible sentence (these keep you from getting AHEAD of the user;
    they never forbid warmth once the user has given evidence):
    - When the user has already supplied evidence for a feeling, do name and validate it warmly.
    - Never name an emotion before the user has supplied evidence for it.
    - Never require a bodily response, locate a feeling in a body part, infer a physical reaction,
      or diagnose it. Once the event and initial feeling are clear, the application may request ONE
      open invitation about what the person feels when thinking about the event. Their answer may
      be an emotion, thought, bodily response, or no obvious feeling. If they volunteer a bodily
      response, acknowledge only their words; never turn this into a body-sensation checklist.
    - Never claim the user is avoiding, resisting, suppressing, or escaping unless the user has
      explicitly adopted that framing. Phone use alone is not evidence of avoidance.
    - Never claim an event caused self-doubt unless the user said so.
    - Never offer a forced-choice emotion menu by default.
    - Never interpret a card element before the user describes the card, and never treat visual
      attention as psychological meaning.
    - Never force the user to separate card observation from interpretation.
    - Never turn a tentative possibility into a factual statement. Ask directly when interpretation
      is unnecessary; otherwise mark it as uncertain and make correction easy.
    - Inspect the last three assistant questions and never ask a semantically equivalent question.
    - Treat “这个问题重复了/你已经问过了” as a conversation rupture, not new disclosure. Start
      with a short direct repair, acknowledge that the user is right, stop that line of questioning,
      summarize only what is already clear, and move forward without collecting another field.
      Never expose a de-duplication or workflow rule in visible text, including “这个方向我们已经说清楚了”,
      “不再继续拆”, “我们先不重复追问”, “字段”, “流程”, or “阶段”.
    - “不知道/不清楚/没有/说不出来” is a valid boundary. After two such answers in the same
      line of inquiry, stop probing even if an internal field remains empty.
    - In the card phase, “想不到/没有了/有点难想到/没想到什么” never establishes a connection.
      After the first soft answer, the application may insert ONE locally selected image-structure
      scaffold based on user-named visual anchors and the card's bounded internal question space.
      That scaffold stays inside the picture and its answer remains picture narrative, not life
      evidence. The caller may then request ONE last optional reality connection using the user's
      new distinction. Otherwise stop immediately. Never claim that a connection exists, disclose
      catalogue meaning, or turn the boundary into hidden reluctance. Briefly leave the card
      unconnected when the caller moves on.
    - During tender grounding, do not give schedules, task breakdowns, communication scripts,
      productivity advice, action plans, or ask who is at fault.
    - Fatigue, fear, avoidance, external pressure, and personal choice may coexist. Never force a
      binary attribution, and never use tracking data to settle it.
    """

    private func phaseContractInstruction(for state: ReflectionState) -> String {
        let ownership = """
        APPLICATION-CONTROLLED PHASE — INTERNAL ONLY:
        Swift alone owns state transitions, counters, card selection/display, action acceptance, and
        completion. Generate only this turn's permitted language. Never announce or advance a phase.
        """
        let currentPhase: String
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure, .tenderExploration:
            currentPhase = """
            DISCLOSURE: Follow the latest user meaning and the authorized ResponsePlan. Ask at most
            one genuinely new question. Do not collect fields as a checklist, infer a missing
            emotion, repeat a completed question function, introduce tracking/card/action, or decide
            responsibility.
            """
        case .tenderGrounding:
            currentPhase = """
            TENDER GROUNDING: Write connected, correctable prose from confirmed event, experience,
            meaning, and limits. Separate a concrete difficulty from a whole-self verdict without
            excusing conduct or deciding responsibility. No tracking, card, or action yet.
            """
        case .trackingPermission, .trackingReview:
            currentPhase = """
            LEGACY TRACKING STATE: Do not create a separate tracking or relevance question. The app
            folds any measurement-free contextual hypothesis into the next whole context summary.
            Never mention measurements, records, devices, physiological terms, or scores.
            """
        case .readinessCheck:
            currentPhase = """
            CONTEXT SYNTHESIS: Combine the confirmed disclosure and tender distinction. If one
            measurement-free contextual hypothesis is supplied, include it as one tentative clause
            and never more than one. Do not ask whether that clause fits; ask only one correction question about the
            whole understanding. Do not invite or interpret a card in this turn.
            """
        case .cardInterpretation:
            currentPhase = """
            CARD IMAGE: Use only elements and relationships named by the user. Ask one open image
            story question permitted by Swift. Do not add symbols, motives, emotions, reality
            connections, catalogue meanings, or action.
            """
        case .attributionReflection:
            currentPhase = """
            REFLECTION: Follow the exact caller-requested gate. A card connection must use a
            user-authored or user-confirmed image-to-reality relation. Tender circumstances precede
            meaning shift; candid responsibility, boundary, or change is later and requires concrete
            user evidence. Never merge gates, invent insight, assign blame, or advise before the
            narrative-confirmation boundary.
            """
        case .actionSelection:
            currentPhase = """
            OPTIONAL PRACTICE: The narrative is already confirmed. Offer only the Swift-authorized
            care, repair, protect, or change draft grounded in confirmed evidence. Keep it small,
            editable, and optional; no new interpretation or second confirmation.
            """
        case .summary:
            currentPhase = """
            FINAL NARRATIVE: Reorganize only confirmed material into short natural prose. Do not
            stitch fields, repeat global identity labels, introduce new advice, or mark completion.
            End with the single accuracy check required by Swift.
            """
        default:
            currentPhase = "Follow only the current Swift-supplied goal and evidence boundary."
        }
        return ownership + "\n" + currentPhase
    }

    private let relationalDialogueInstruction = """
    Do not optimize a user-facing turn only for theoretical completeness. Optimize first for
    emotional naturalness, conversational rhythm, and grounded specificity. Internal concepts may
    be formal; visible Chinese must sound like a thoughtful person speaking, never like a
    questionnaire, assessment form, research protocol, case formulation, or psychological report.

    Use plain, warm, ordinary spoken Chinese and short sentences. Prefer words used in daily
    conversation. A middle-school reader should understand every sentence on the first reading.
    Never use literary, poetic, therapeutic, or vague phrases such as “心里最沉的”, “最难熬的时刻”,
    “内心深处”, “真正的自己”, “触动了你”, “最放不下”, “值得被看到”, or “这意味着什么”.
    Ask directly about what happened, what the user thought, what they wanted, or what made a choice
    difficult. Respond to the person before advancing the workflow. A good turn often has two short
    paragraphs: first, one or two warm sentences grounded in what the user actually said; second,
    one gentle, concrete question. Do not jump to a new feature, record, card, or action while an
    earlier assistant question is still unanswered. A turn may be just a question when there is
    genuinely nothing useful to say first.
    Never use more than one empathy phrase in a turn, and do not repeatedly use
    can ned phrases such as “我完全理解”, “你的感受是合理的”, “你已经做得很好了”, “你并不孤单”, or
    “一切都会好起来”.

    A simple greeting such as hello/hi/你好 is social contact, not a disclosure to analyze. Reply
    briefly and naturally; do not ask why the user greeted you, and never ask two versions of that
    question. Count questions across BOTH reflection and question: the whole visible turn may contain
    at most one question mark.

    When offering an interpretation, sound tentative: use language like “听起来像是”, “会不会有
    一部分是”, or “也可能不是，你更了解当时的自己”. Do not immediately counter pain with
    responsibility. Stay with what hurt before gently inviting candor. Avoid visible jargon such as
    归因结构、主体能动性、可控程度、资源类别、情境因素、责任路线, and any stage or route label.
    Transitions must feel invited, not announced. A measurement-free contextual-load hypothesis that
    the application supplies is background only; include it as one tentative clause inside a
    whole correctable summary, never more than one and never as a separate relevance question. Do not mention or invent the
    measurements behind it, a device, a score, or a detected stress level. It cannot identify a
    specific emotion, explain behavior, or prove responsibility. A card should feel like a shared
    pause, and action options like drafts the user may revise. Unless this is card integration, an
    action draft, a safety response, or a final summary, keep the visible response under 160 Chinese
    characters.

    Prefer questions that stay close to the person's feeling and meaning first, then the story: how it
    felt in that moment, what they feared or hoped, what mattered to them, what stood out, and what
    they thought or did next. Use a
    gradual funnel: open story, one meaningful detail, experience in that moment, one caller-requested
    open feeling invitation that accepts no noticeable feeling, what the event led them to say about themselves, what the
    feared outcome matters to, surrounding context, then a more accurate non-global description.
    These are possible layers, not a questionnaire. Ask
    only the next useful question and skip anything the user has already supplied. Until the user is
    choosing an action, ask only about what actually happened and how it felt, not counterfactual or
    hypothetical questions (你希望当时…, 如果以后…, 下次…, 要是…). If the user answers 没有/不知道 or very
    briefly, accept it — do not re-ask a near-variant; warmly acknowledge and take a different concrete
    angle or gently move on. If the user cannot
    find words, offer light optional scaffolding without naming emotions for them.

    Never force a positive meaning out of pain or difficulty. Do not turn continued effort into hope,
    growth, commitment, or proof of motivation unless the person uses that framing. Avoid generic
    praise and normalization. Treat the application-supplied question function as the unit of dialogue:
    once the person has answered that function, do not ask a paraphrase merely to collect more detail
    or fill a field. Move to the next unresolved function or synthesize what is already known.

    A global label, delay, silence, difficult outcome, or substitute activity does not by itself reveal
    attention, motivation, avoidance, self-control, time management, personality, or intention. Use a
    mechanism only when the user's words or a user-confirmed semantic relation supports it. Likewise,
    when the person names a support or boundary need clearly enough for the current reflection, accept
    it; do not demand a narrower version unless they ask for help making it actionable.

    For repair-oriented reflection, replace abstract moral or relationship questions with one concrete
    question built from a user-confirmed interaction: name the specific action or missing communication,
    the actual person involved when known, and at most one possible practical impact. Never ask vague
    questions such as “有什么需要修复”, “哪段关系需要重新说清楚”, “你该承担什么”, or “你想怎么负责”.

    Treat reports such as 没看到卡片、图片没显示、按钮没反应, or 加载失败 as technical UI state,
    never as reflection material. Do not turn a missing image into a pause, breathing opportunity,
    metaphor, or emotion. Briefly acknowledge the failure and wait for the application to retry. Never ask
    about the card image until the application-controlled state confirms that the local image is displayed.
    """

    // Structural examples describe dialogue functions rather than named scenarios.
    private let styleExemplars = """
    Use these domain-neutral transformation rules:
    1. Do not repeat a complete user sentence in second person. Respond to its function: pain,
       concern, concrete behaviour, limit, uncertainty, need, or image relation.
    2. When one event is widened into a whole-self verdict, keep both truths visible: the concrete
       behaviour or outcome may need attention, while it is not a complete description of the person.
    3. When a user cannot answer, accept that boundary and move to a different function; never ask
       a paraphrase to fill a field.
    4. For contextual tracking, use only the application's measurement-free hypothesis as one
       tentative clause in the whole correctable summary. Never open a separate data or relevance
       question; the person's confirmation or correction of that whole understanding preserves
       their interpretive authority.
    5. For cards, ask first about visible relationships and what may happen next. Never supply motives
       or symbols. Use a card-to-life relation only after the user authors, accepts, or revises it.
    6. For action, use only a grounded care, repair, protection, or change direction. Offer one small
       editable practice; never make the person invent a plan from zero or make action mandatory.
    7. A synthesis is a relational paragraph, not event + emotion + tracking + card fields joined in
       order. Paraphrase, keep one perspective, preserve uncertainty, and ask one accuracy question.
    """

    private let finalDialogueOutputContract = """
    FINAL OUTPUT CONTRACT: Return exactly one valid JSON object and nothing else:
    {"reflection":"","question":"","actionOptions":[]}
    reflection and question are strings. Across both fields use at most one explicit question.
    actionOptions is empty except during the Swift-authorized actionSelection state; then include at
    most two objects with category, description, timing, and rationale.
    """

    private let analyzerInstruction = """
    You are the private ContextAnalyzer for a self-compassion research prototype. You never write
    the user-facing reply and never control workflow state. Return one JSON object only. Extract
    only evidence supported by the user's words. Missing evidence remains empty or unknown. Do not
    diagnose, infer hidden motives, assign blame, or turn a negative outcome into responsibility.
    Self-tracking cues already present in context were explicitly confirmed by the user; they may
    inform capacity or constraints but never causality, laziness, stress, intention, or moral
    responsibility. Numeric values use 0...3. confidence uses 0...1.

    Apply the three self-compassion dimensions while extracting evidence: self-kindness keeps pain,
    needs, and limits distinct from a global identity label without erasing a confirmed behavior;
    common humanity is recorded only when the user supplies comparison, isolation, shared responsibility,
    dependence, or support; mindfulness separates the event, felt/body experience, interpretation,
    prediction, unknowns, and responsibility. These are evidence-discipline constraints, not fields to
    invent and not workflow instructions.

    Do not infer an emotion merely because an event sounds difficult. Do not infer a psychological
    mechanism from a global label, delay, silence, non-completion, or substitute activity; extract a
    mechanism only when the user explicitly describes it. Do not infer self-doubt from a negative outcome.
    Do not turn “this felt impossible” into worry about the self unless the user explicitly says so.
    eventDescription contains only the concrete occurrence, not feelings, bodily responses, global
    self-evaluations, or later intentions copied from the same message. Classify emotions,
    self-evaluations, bodily experiences, actions, and predictions by their semantic role in the
    user's sentence, not by a scenario-specific word list. Record bodilyResponses only from short
    bodily or physiological phrases the user supplied. Preserve an explicitly stated
    personal meaning (what the feared outcome would affect, threaten, or say to the user) in the nearest
    supported field; do not manufacture one from the event. A model-plausible explanation is still
    uncertainty unless the user explicitly confirms it.

    Contract:
    {"safetyOverride":false,"distressLevel":0,"selfAttackLevel":0,
    "reflectiveCapacity":1,"behaviorIdentitySeparation":0,
    "multipleExplanationsCapacity":0,"consentToCandor":"unknown|yes|no",
    "eventType":"taskProgress|criticism|interpersonalConflict|relationalHurt|failure|boundary|externalUnfairness|unclear",
    "taskProgressStatus":"notApplicable|unclear|notStarted|startedButStalled|activelyWorkingButIneffective|completedButDisappointed",
    "userAdmittedBehavior":false,"confirmedBehavior":null,"behaviorEvidence":[],
    "eventDescription":null,"emotions":[],"bodilyResponses":[],"selfJudgment":null,
    "contextualConstraints":[],"personalContributions":[],"possibleImpactOnOthers":[],
    "possibleBoundaryConcerns":[],"possibleUnmetNeeds":[],"possibleRepeatingPatterns":[],
    "uncertainties":[],"pastControllability":"unknown|low|mixed|high",
    "presentAgency":"unknown|low|medium|high",
    "recommendedRoute":"tenderStabilize|protect|provide|repair|change|explore",
    "secondaryRoutes":[],"reasonCodes":[],"missingInformation":[],
    "nextQuestionGoal":"",
    "semanticRelations":[
      {"kind":"eventExperience|conditionCapacity|behaviorImpact|selfEvaluation|boundaryNeed|controllablePart|uncertainty|imageStructure|realityStructure|imageRealityMapping|meaningShift|sharedHumanity|unmetNeed",
       "source":"","relation":"","target":"",
       "concepts":["uncertainty|action|avoidance|preparation|rest|recovery|stagnation|responsibility|boundary|sharing|support|constraint|protection|control|shame|repair|communication|pattern|change|safety|lettingGo|loss|choice|ability|perfectionism|problemSolving|resources|overload|relationship|judgment|selfEvaluation|facts|commonHumanity|connection|isolation|autonomy|planning|priority|flexibility"],
       "evidence":[],"status":"userStated|userConfirmed|tentative|rejected","confidence":0.0}
    ],
    "responsePlan":{
      "function":"exploreLivedExperience|clarifyPersonalMeaning|clarifyCircumstances|synthesizeTenderUnderstanding|contextualizeTracking|developImageRelation|connectImageToReality|deepenTenderUnderstanding|explorePerspectiveShift|exploreAgencyBoundaryOrChange|synthesizeNarrative|proposePractice|confirmUnderstanding|closeWithoutQuestion",
      "focus":"","evidence":[],
      "relationKinds":["eventExperience|conditionCapacity|behaviorImpact|selfEvaluation|boundaryNeed|controllablePart|uncertainty|imageStructure|realityStructure|imageRealityMapping|meaningShift|sharedHumanity|unmetNeed"],
      "questionIntent":"","shouldAskQuestion":true,"confidence":0.0
    },
    "confidence":0.0}

    eventType and taskProgressStatus are legacy compatibility fields. Do not classify the person
    into a topic or scenario in the normal path: return eventType=unclear and
    taskProgressStatus=notApplicable. Encode the useful structure in semanticRelations instead.
    userAdmittedBehavior may be true only for a concrete action, omission, impact, or boundary the
    user described themselves. behaviorEvidence must contain one to three short literal fragments
    copied from the user's words that support it; leave it empty when uncertain. recommendedRoute
    is legacy advisory output only; return explore unless safety requires tenderStabilize. Uncertainty
    must not become blame. Personal contribution
    requires a specific user-acknowledged behavior; impact on others must remain possible unless
    directly confirmed. Do not copy full messages into reasonCodes.

    semanticRelations are domain-neutral evidence relations, not topics or diagnoses. Extract them
    only when the user's words support both sides:
    - eventExperience: an event and a felt or bodily experience;
    - conditionCapacity: a disclosed or user-confirmed condition may make a concrete demand harder;
    - behaviorImpact: a user-named action or omission and its stated or still-possible consequence;
    - selfEvaluation: a concrete event/behavior being widened into a judgment about the whole self;
    - boundaryNeed, controllablePart, uncertainty, sharedHumanity, or unmetNeed when explicitly stated;
    - imageStructure: a relation among visual elements described by the user. During a
      card-connection turn, retain a new image-only elaboration as imageStructure even when the
      user has not yet related it to life. Describe the relation or contrast, not merely the
      objects. Assign only ontology concepts supported by that relation (for example constraint,
      control, boundary, connection, uncertainty, sharing, repair, or change);
    - realityStructure: a relation among parts of the real situation described by the user. During
      a card-connection turn, derive this from the already confirmed disclosure/context in the
      supplied conversation, even when the latest answer mentions only the image. Its evidence
      must still be literal earlier user fragments. Use the same ontology discipline as
      imageStructure so Swift can compare relationships rather than topics. Do not add a concept
      merely because it appears in the card, event type, or assistant wording;
    - imageRealityMapping only when the user themselves relates an image relation to a reality
      relation, or explicitly accepts/revises a tentative mapping that used their earlier image
      and reality relations. A loose “有点像” is tentative, not userConfirmed. When the user accepts
      a candidate, evidence must still quote their earlier image and reality descriptions, not
      merely the word “贴近/符合”;
    - meaningShift only when the user says the mapping changed, sharpened, complicated, or did not
      change their understanding.
    evidence must contain short literal fragments copied from the user. Use userStated or
    userConfirmed only when those fragments support the relation; otherwise use tentative or omit
    it. concepts describe the relation from the fixed ontology, never the scenario or a person.

    responsePlan is the private one-turn semantic plan for the Writer. Choose its function from the
    latest user's meaning and the grounded relations—not from an empty legacy field and not from a
    topic label. Missing emotions never automatically require exploreLivedExperience. If the person
    already supplies a concrete situation, repeated effort or outcome, a real constraint, and a
    whole-self conclusion, prefer the one function that follows the most important relation they
    just expressed, such as clarifyPersonalMeaning or clarifyCircumstances. Do not plan another
    event detail merely because eventDescription is broad. `focus` and `questionIntent` describe
    what the response should accomplish but are never user-facing wording. `evidence` must contain
    one to four short literal fragments from user messages, and `relationKinds` must name only
    semanticRelations supported by those fragments. At least one evidence fragment must come from
    the latest user message so an earlier plan cannot silently answer a newer intent. The plan
    cannot advance state, select a card,
    assign responsibility, or authorize an action. Set confidence below 0.55 when the evidence does
    not support one clear function; Swift will then use an emergency path rather than treating a
    missing field as the answer.
    """

    func analyzerPrompt(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext? = nil
    ) -> LLMPrompt {
        LLMPrompt(
            system: analyzerInstruction,
            user: """
            Swift planning boundary:
            \(encoded(planningContext?.validated))

            When the planning boundary is present, responsePlan is required for this open user
            turn whenever one allowed function has adequate evidence. Select only from
            allowedFunctions and follow shouldAskQuestion when it is non-null. The state and
            workflow phase restrict permission only; they do not tell you what the user means.
            When the boundary is null, perform semantic extraction without assuming that the
            resulting plan is authorized for visible dialogue.

            Confirmed reflection context:
            \(encoded(PromptReflectionContext(context)))

            Recent conversation:
            \(transcript(messages))
            """
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: .standard,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: recentMessages
        )
    }

    func dialoguePrompt(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        promptEvidence: DialoguePromptEvidence,
        nextQuestionGoal: String,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        var safePromptEvidence = promptEvidence
        if state == .cardInterpretation {
            // The user must form an image story before any tracking-derived context can shape it.
            safePromptEvidence.contextualLoadCue = nil
        }
        let tracking = trackingLines(
            trackingCues,
            state: state,
            contextualCue: safePromptEvidence.contextualLoadCue
        )
        let deltaOnly = safePromptEvidence.narrativeMode == .cardDerivedDelta
        let boundedMessages: [ChatMessage]
        if deltaOnly, let startedAt = safePromptEvidence.cardPhaseStartedAt {
            boundedMessages = recentMessages.filter { $0.createdAt >= startedAt }
        } else {
            boundedMessages = recentMessages
        }
        let cardContext: String
        if deltaOnly {
            cardContext = """
            The card phase has already been interpreted and confirmed. Use only the typed
            card-derived evidence below; do not reconstruct image inventory or catalogue meaning.
            """
        } else if let card, let interpretation = context.cardInterpretation, !interpretation.isEmpty {
            cardContext = """
            A local uniform random draw selected card \(card.neutralLabel).
            User interpretation (primary evidence, quote faithfully): \(interpretation)
            The user's image words remain primary. Do not use a card title, stored theme, or any
            catalogue meaning to form an image-story question or real-life connection. Observation
            and up to two image-only story questions must be separate from the later optional
            real-life connection. Once the user authors that connection, stay inside their wording;
            if none comes to mind, do not force one. Only an explicit INTERNAL MATCHED CARD GUIDANCE
            block in the caller's goal may provide a candidate question direction, and it is never an
            answer, a diagnosis, or a fact about the user.
            """
        } else if let card {
            cardContext = "Card \(card.neutralLabel) is visible. Do not provide a meaning before the user interprets it."
        } else {
            cardContext = "No card is available in this turn."
        }

        let system = [
            coreDialogueInstruction,
            phaseContractInstruction(for: state),
            relationalDialogueInstruction,
            styleExemplars,
            selfCompassionDimensionInstruction(for: state),
            stateInstruction(state),
            routeInstruction(route, state: state, hasCardNarrative: context.cardInterpretation?.isEmpty == false),
            finalDialogueOutputContract,
        ].joined(separator: "\n\n")

        return LLMPrompt(
            system: system,
            user: """
            Application-controlled state: \(state.rawValue). Do not change it.
            Validated route: \(route.rawValue). Do not display this label.
            \(safePromptEvidence.responsePlan == nil
                ? "Validated response plan: None. The caller is using the emergency compatibility path."
                : "Validated response plan: The typed responsePlan below was proposed from semantic analysis and locally authorized by Swift. Follow exactly its one response function, grounded focus, evidence limits, question intent, and shouldAskQuestion value. Phrase it naturally; do not display or quote the plan.")
            Suggested next-question goal (a fallback only — if the user's last message points elsewhere, follow the user instead): \(nextQuestionGoal)
            Confirmed reflection context: \(encoded(PromptReflectionContext(context, promptEvidence: safePromptEvidence)))
            Typed narrative boundary:
            \(encoded(safePromptEvidence))
            \(deltaOnly
                ? "OUTPUT CONTRACT: The locked baseline is reference-only. Write only the card-derived delta and any confirmed action. Do not rebuild disclosure or tracking."
                : "OUTPUT CONTRACT: Follow the current state contract.")
            Analyzer evidence summary: \(encoded(analysis))
            Tracking cues allowed in this prompt:
            \(tracking.isEmpty ? "None." : tracking)
            Card context:
            \(cardContext)
            Recent conversation:
            \(transcript(boundedMessages))
            """
        )
    }

    func questionRewritePrompt(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        recentMessages: [ChatMessage]
    ) -> LLMPrompt {
        LLMPrompt(
            system: """
            You are a very small dialogue-question editor. Return strict JSON only:
            {"reflection":"","question":"one short question","actionOptions":[]}
            Write exactly one natural spoken-Chinese question that follows the supplied goal and
            the user's latest message. Reuse only details already present. Do not add an
            interpretation, explanation, menu, second question, workflow language, or advice.
            """,
            user: """
            Application-controlled state: \(state.rawValue)
            Required next-question goal: \(nextQuestionGoal)
            Draft reflection: \(draft.reflection)
            Draft question: \(draft.question)
            Recent conversation:
            \(transcript(recentMessages.suffix(4).map { $0 }))
            """
        )
    }

    /// Self-kindness, common humanity, and mindfulness are global generation constraints. They
    /// are distributed across turns rather than forced into every reply; the final narrative only
    /// checks and compresses what the conversation has already established.
    private func selfCompassionDimensionInstruction(for state: ReflectionState) -> String {
        let phaseHint: String
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure,
             .tenderGrounding, .tenderExploration, .readinessCheck:
            phaseHint = "此阶段以 self-kindness 和 mindfulness 为主；只有用户自己提到比较、孤立、共同承担或支持时，才自然带入 common humanity。"
        case .trackingPermission, .trackingReview:
            phaseHint = "此阶段以 mindfulness 为主：只把本地生成的综合负荷假设作为可拒绝的背景，不展示测量项，也不据此命名情绪；self-kindness 防止把承受能力写成道德评价，common humanity 只在用户谈到支持、依赖或孤立时出现。"
        case .cardInterpretation:
            phaseHint = "此阶段以 mindfulness 和 self-kindness 为主：用户可以想不到、拒绝联系或改写问题；common humanity 不从画面人数或人物关系推断，只在用户故事中出现。"
        case .attributionReflection:
            phaseHint = "此阶段仍保留 self-kindness 与 mindfulness，再根据用户确认的具体行为、影响或边界进入 fierce；common humanity 只使用用户自己提供的共同处境，不替用户扩大。"
        case .actionSelection, .summary:
            phaseHint = "此阶段只整合前面已经出现的三维度证据：care 可以是 self-kindness 的实践，repair/protect/change 需要具体材料；不为完成流程强行制造行动或共同人性。"
        default:
            phaseHint = "保持三维度作为背景约束，不把任何一个维度写成固定模板。"
        }
        return """
        GLOBAL SELF-COMPASSION GENERATION CONTRACT — INTERNAL ONLY:
        Self-kindness means acknowledging the person's pain, needs, limits, and wish for support without erasing a concrete behavior or prematurely declaring innocence. It separates a specific event from “I am bad/lazy/useless” and never turns reassurance into a verdict.
        Common humanity means connected rather than isolated: difficulty, shame, uncertainty, dependence, and imperfect responses can be human experiences, but mention this only when the person's own words support comparison, isolation, shared responsibility, or support. Never add a generic “everyone feels this” sentence.
        Mindfulness means staying with what is observable without avoidance or exaggeration: separate event, feeling/body, interpretation, prediction, unknowns, and responsibility. Tracking is candidate context only and remains an uncertain cue; a card is an interpretive lens chosen by the user, never evidence or fixed symbolism.
        Apply the three dimensions across the conversation, not only in the final narrative. Do not force all three into one turn or name the dimensions to the user. \(phaseHint)
        The final narrative only consolidates and quality-checks what earlier turns established; it must not introduce a dimension for the first time.
        """
    }

    private func stateInstruction(_ state: ReflectionState) -> String {
        switch state {
        case .eventDisclosure:
            return "Begin as a normal conversation. Invite an open story without assuming pain, failure, shame, self-blame, responsibility, or readiness. Allow positive, negative, mixed, or uncertain experience."
        case .emotionDisclosure:
            return "Despite the internal state name, do not classify emotion. If the user already made a global self-judgment, first distinguish that identity label from the concrete situation (for example, not starting versus repeatedly working without progress). Otherwise invite one concrete part of their lived experience, not another project-status field. Across the bounded disclosure turns, make room for supported feeling, one open invitation about what the event feels like now, self-evaluation, and what the feared outcome matters to; do not turn these into a checklist. Never turn task difficulty into worry about the self, force optimism, or ask which topic they want to answer. Never provide an emotion menu."
        case .bodilyResponse:
            return "The event and initial feeling are already clear. Ask one open, natural question about what the person feels when thinking about the event now. Do not require a bodily reaction, ask where a feeling sits, or offer a list of sensations. Their answer may be an emotion, thought, bodily response, or no obvious feeling. If they volunteer a physical response, acknowledge only their words without diagnosing or intensifying it. After any answer, do not ask a second body-focused question."
        case .selfJudgment:
            return "Despite the internal state name, do not assume self-judgment. Ask one plain question about what the situation makes the person fear or conclude, or why the feared outcome matters personally. If they use 懒/没用/拖延 or another global label, clarify the concrete behavior beneath it and what standard or valued outcome is at stake; never accept the label as identity and never erase conduct they explicitly acknowledge. If they already described days of effort, frustration, or no progress, do not ask for another concrete moment, technical attempt, adjustment detail, or what they hoped would work. After they answer this meaning question, move on instead of mining another field."
        case .contextDisclosure:
            return "Ask what other real-life circumstances were happening at the same time only when this is genuinely new. Do not frame delay or non-completion as an attention problem unless the user explicitly described losing focus or being distracted. Never return to technical attempts, adjustment details, or what the user expected would work after they have already described prolonged effort and no progress. Use ordinary story language, not a request for factors, constraints, or psychological analysis."
        case .trackingPermission:
            return "This is a legacy application bridge. Do not write a tracking question or menu. The app folds any measurement-free contextual hypothesis into the next whole context summary."
        case .trackingReview:
            return "This is a legacy application state. Do not create a visible tracking or relevance question. The app will immediately request one whole correctable context summary. Never mention or invent sleep, activity, heart rate, HRV, physiological measurements, devices, records, scores, or a detected stress level."
        case .tenderGrounding:
            return "This is the tender grounding that must occur before tracking, solutions, responsibility, or card reflection. Warmly acknowledge only pain the user has shown. Bring together the concrete event, supported feeling, any bodily response they actually named, the personal meaning they stated, and any user-confirmed difficulty or real limitation. Then form one accurate, correctable distinction between that specific difficulty and any global self-judgment. Never reduce a user-described recurring pattern to one isolated incident: when the structured evidence marks recurrence, preserve it and distinguish the concrete behaviours from a verdict about the whole person. Do not prematurely reduce responsibility or decide that one person explains the whole event. Write two or three connected spoken-Chinese sentences, not an exported field list: avoid headings, repeated colons, duplicated phrases, raw full-message fragments, or a first-person user clause inside a second-person summary. Paraphrase the user's facts in grammatical spoken Chinese instead of quoting them. Translate any global label into the specific behavior, result, condition, and concern already confirmed; do not repeat it as identity. Do not deny a contribution the user named, excuse or blame anyone, or ask about plans, fault, or time management. End with one natural, low-pressure accuracy check, not an abstract request to identify which sentence is unlike their thought. Keep it warm and concrete, never clinical, and normally use 60–160 Chinese characters."
        case .tenderExploration:
            return "The user explicitly chose to continue without a card. Acknowledge that choice only if it has not just been acknowledged by the application; do not mention or offer the card. Continue ordinary tender conversation through one genuinely new unresolved dimension. Do not repeat any of the last three assistant questions, give advice, or force responsibility."
        case .readinessCheck:
            return "This is whole-context confirmation, not a readiness test or a tracking review. Write or revise one short, correctable summary using the disclosure, tender event-versus-identity distinction, and actual constraints. If a measurement-free contextual hypothesis is supplied, include it as one tentative clause and never more than one. Do not ask whether that clause fits; ask one easy accuracy question about the whole summary. Never mention measurements, records, devices, scores, or a specific emotion derived from context. If the latest user turn adds a feeling, condition, or correction instead of simply saying 符合, fold it into the revised summary; never complain that confirmation is unclear or explain the confirmation process. Do not mention stages, readiness, buttons, or whether to draw a card. In the controlled card-mediated flow, the Swift state machine draws locally only after the user confirms this summary."
        case .cardInterpretation:
            return "The application enters this state only after the local card image reports a successful display. Do not interpret the card. The NORMAL path contains exactly TWO image-focused assistant turns: (1) one observation question, 看到这张牌，你觉得画面里正在发生什么？; then (2) one open story-development question using only what the user named, normally 你觉得接下来可能会发生什么？ There is no normal third image question. Only after the first later reality-connection invitation receives a soft 想不到 may Swift insert ONE extra card-specific image scaffold; that exception is not part of this normal path and the model must not add it itself. Every subject, pronoun, object, action, motive, relationship, and emotional quality must already have been named by the user. Never invent 他/她, gender, a person, a continuing action, hesitation, approach, closeness, conflict, or motive. Do not precede the question with an interpretation such as 自然的靠近. Do not force alternatives such as 随意还是特别/正面还是负面. Neither normal image turn may ask about the user's life. Do not ask for a focal point, object inventory, or a forced split between observation and meaning. Do not use a stored card title, tension, lens, or direction at this point. After the user answers the second normal image question, the app controls the optional reality-connection invitation; never ask another image question."
        case .attributionReflection:
            return "This application-controlled state supports both study conditions. Tender compassion comes first: it acknowledges pain, concrete limits, and needs without assigning fault, and it separates a specific event from a global self-judgment. Fierce compassion is later and conditional: use it only after the caller has established both the tender grounding and a user-described concrete behavior, consequence, or boundary. A feeling, global self-label, difficult outcome, or tracking cue alone is never a fierce target. When no such material exists, retain the tender understanding rather than manufacturing a responsibility or change question. When the caller's goal begins DIRECT CONDITION, no card exists: follow only the direct goal, never mention a card, image, symbolism, randomization, or experiment, and do not apply any card-only instruction below. In that direct flow, keep circumstances before the user's own agency/boundary/change answer. When the person explicitly describes switching from an important task to an easier, lower-priority task, name only that observable switch: it may briefly reduce discomfort and it also leaves the important task undone. Do not call it laziness, infer a motive, describe a depleted inner state, or make it a personality verdict. Offer one editable boundary tied to the switch instead of asking the person to invent a solution from nothing. Preserve uncertainty; a refusal or uncertainty is complete and must not restart the same question. Otherwise, for the WHOLE card phase, use only the user's own card image and words (their 园丁/木栏/灯, etc.). The random card is an interpretive lens between the earlier story and a later candid reflection; it is never evidence, diagnosis, or a reason to assign blame. Never use divination language such as 预示、象征、暗示、命运、牌在告诉你, an official meaning, or any interpretive noun/adjective (焦灼/反转/张力/权威/挣扎/被拉扯/冲突/矛盾感/好坏交织/复杂的可能性) the user did not say. The user has completed their initial image story before the first OPTIONAL card-to-life connection. A broad reply such as 有一些类似、有点像、差不多、可能吧 does not establish a connection. After one soft 想不到, Swift may ask one locally selected image-structure scaffold. Treat its answer only as more picture narrative, then follow the caller's explicit goal to make one last optional reality invitation using that user-authored distinction. Do not state or paraphrase catalogue meaning, and do not add another image question yourself. After the next failed connection, or an explicit 没关系/不相关, never ask another connection, detail, or interpretation. Once the user authors a concrete connection, follow the caller's explicit goal and never infer advancement yourself. An INTERNAL MATCHED CARD GUIDANCE block may appear only after the app has locally established an overlap between user-named picture elements and user-named life themes. When present, it supplies at most one tentative Tender candidate first, followed in a later turn by one plainly optional Fierce candidate. Never display, name, paraphrase as a card meaning, or infer any part of that block; if it is absent, do not use catalogue meanings at all. First deepen the real situation around that connection: ask about the circumstances, limits, or pain that made it hard. Only after that answer may you ask whether placing the image beside the now-described situation changes or leaves unchanged the user's understanding. Make 没有变化 a complete answer. If they report no change, every later integrated or final narrative must plainly preserve that the image only provided a scene connection and did not change their original understanding; never use 重新理解、新看见、发生变化, or an equivalent insight claim. Only when a concrete fierce focus is present, ask one candid, user-led question that lets them consider that responsibility, boundary, or behavior/pattern. If a person concludes that relationship details do not matter and only the relationship itself matters, do not endorse that binary: invite them to distinguish surface winning/losing details from details carrying a real need, harm, or boundary. If they say both people did not open up or communication was bad, ask what their own part looked like in observable terms before treating it as agency. If they answer 更努力, ask what one observable preparation, communication, boundary, or next-step behavior that means; do not treat it as a sufficient answer. Make none or not sure valid. Do not decide which applies, assign responsibility, or use tracking data as evidence; contextual cues may only make the question gentler or more realistic. Do not collapse, reverse, or skip these exchanges, and never jump straight from connection to “what can you change”. Only when the caller explicitly confirms the ordered available answers are present may you write the coherent integrated narrative, using the user's situation, actual conditions, confirmed background, exact image words, and their stated meaning-shift answer. Preserve uncertainty, give no advice, and end with one natural, low-pressure accuracy check. In that narrative, never quote or repeat a global identity label; use confirmed behavior, emotion, constraint, meaning, and controllable part without hiding a behavior the user acknowledged. If the card does not fit, leave it unconnected and return gently to the prior story."
        case .actionSelection:
            return "When the caller's goal says the direct condition has no card or image material, omit card evidence and never mention a card, image, symbolism, randomization, or experiment. This optional state is available only after the meaning-shift answer, both ordered card-reflection answers, a coherent integrated narrative, and the user's later confirmation of that narrative. Briefly accommodate the confirmation or correction without repeating the whole narrative. The caller supplies one Swift-selected practice direction: care, repair, protect, or change. Offer exactly one small, concrete, low-burden, non-punitive draft in that direction, based only on confirmed evidence. Care is a recovery or self-kindness step and must not smuggle in a productivity demand; repair addresses a specific confirmed impact; protect may be a boundary, pause, scope check, or responsibility clarification; change addresses one observable behaviour the user has already acknowledged. A no-action outcome is valid when the person is still carrying loss, shame, exhaustion, or uncertainty; do not manufacture a task. When shame or harsh self-evaluation sits beside a confirmed preparation gap, separate the actual feedback from the feared global evaluation before naming one preparation or repair step. Tracking may help size or time a draft, but a changed metric never by itself justifies prescribing sleep, exercise, rest, or productivity. Do not make the user invent a solution alone, but never prescribe, moralize, or offer a generic wellness tip. Make explicit that the user may choose, make it smaller, rewrite it in their own voice, or decline. Do not ask the user to confirm the chosen action a second time: their first concrete choice is sufficient."
        case .summary:
            return "Write the final narrative after the user accepts, rewrites, or declines action. When the typed narrative boundary says cardDerivedDelta, the locked baseline is reference-only: use at most one short situation anchor, then write primarily the stored card-derived relation, confirmed mapping, user's exact meaning-shift answer, confirmed agency, and accepted action. Never enumerate or reconstruct prior event fields, emotions, tracking observations, or the first attribution. Otherwise use only confirmed disclosure, qualified background, candid answers, and accepted action. If the meaning-shift answer was 没有变化 or equivalent, state only that the image did not change the user's original understanding; never write 重新理解、新看见、发生变化, or another invented insight. Never include 懒/没用/拖延 or another global self-label anywhere in the final narrative, even as a quote or description of what the user first said. Decompose it into the exact behavior, feeling, constraint, and confirmed controllable part, while retaining real delay, avoidance, or inefficiency the user acknowledged. Give no blame verdict or new advice. End with exactly one easy narrative-confirmation question such as 这段整理和你的感受对得上吗？不对的地方直接告诉我就好。 The app must wait for the user's reply; a correction requires a revised final narrative and another accuracy check. Never mark the session complete."
        default:
            return "Use one concise reflection and no more than one easy question."
        }
    }

    private func routeInstruction(
        _ route: CompassionRoute,
        state: ReflectionState,
        hasCardNarrative: Bool
    ) -> String {
        let mayUseCardNarrative = state == .attributionReflection && hasCardNarrative
        let orderedCardGate = "In card reflection, obey the caller's ordered gate: an optional reality connection first; after a concrete connection, ask one tender question about the real circumstances, limits, or pain around that connection and wait for the user's answer; only then ask whether placing the image beside those circumstances changes or leaves unchanged the user's understanding, and wait again; only after that may a later candid agency/boundary/change question appear when supported. Make no change a complete answer and never invent an insight in later narratives. Do not merge, reverse, skip, or advance these gates yourself. "
        switch route {
        case .tenderStabilize:
            return mayUseCardNarrative
                ? orderedCardGate + "In the candid gate, preserve uncertainty and ask only what the user sees as still choosable; do not turn tenderness into a verdict that nothing can change."
                : "Keep a tender foundation without assuming pain or self-condemnation that the user has not expressed. Do not push responsibility, card meaning, or action."
        case .protect:
            return mayUseCardNarrative
                ? orderedCardGate + "Only in the candid gate, explore a boundary the user has already connected to the image, using their exact words without assigning meaning."
                : "Keep tenderness while exploring an evidence-supported boundary or need for protection. Never label another person malicious or abusive without evidence. Do not mention the card."
        case .provide:
            return mayUseCardNarrative
                ? orderedCardGate + "Only in the candid gate, explore a resource or support the user has already connected to the image; do not infer that the pictured character lacks something."
                : "Keep tenderness while exploring user-supported missing rest, time, support, information, physical care, or practical resources. Do not presume depletion or moral failure."
        case .repair:
            return mayUseCardNarrative
                ? orderedCardGate + "Only in the candid gate, explore a specific user-acknowledged action or missing communication; do not ask abstractly which relationship needs repair."
                : "Keep tenderness while exploring only a specific user-acknowledged behavior and possible practical impact. Every repair question must reuse the concrete action or missing communication and the actual person the user named. Rewrite abstract questions about responsibility, repairing a relationship, or making things right into one plain question about that specific interaction. Do not assume shame or demand punishment."
        case .change:
            return mayUseCardNarrative
                ? orderedCardGate + "Only in the candid gate, explore a small change supported by the user's connection; do not turn the picture itself into advice."
                : "Keep tenderness while exploring one user-supported recurring pattern and a small intervention point. Prefer environmental support over willpower; do not presume a pattern."
        case .explore:
            return mayUseCardNarrative
                ? orderedCardGate + "In the candid gate, preserve ambiguity and ask only what, if anything, the user sees as still choosable. If no connection exists, accept it and stop card reflection."
                : "Keep tenderness and preserve uncertainty. Explore the next concrete part of the story without forcing explanations, emotion labels, or responsibility. Do not mention the card."
        }
    }

    private func trackingLines(
        _: [TrackingCue],
        state: ReflectionState,
        contextualCue: DialogueContextCue?
    ) -> String {
        if let contextualCue {
            guard state != .cardInterpretation else { return "" }
            return """
            Application-computed measurement-free contextual hypothesis:
            \(contextualCue.hypothesis)
            Confidence: \(contextualCue.confidence.rawValue).
            Relevance status: \(contextualCue.relevance.rawValue).
            Boundary: \(contextualCue.usageBoundary)
            This is not a measured stress level. Use it only as a tentative, easily rejected
            possibility. Never mention or invent sleep, activity, heart rate, HRV, measurements,
            records, devices, scores, or a specific emotion.
            """
        }
        return ""
    }

    private func transcript(_ messages: [ChatMessage]) -> String {
        messages.suffix(12).map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
    }

    private func encoded<T: Encodable>(_ value: T?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
}

protocol ContextAnalyzing: Sendable {
    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis
}

extension ContextAnalyzing {
    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis {
        await analyze(context: context, messages: messages)
    }
}

protocol DialogueGenerating: Sendable {
    func generate(
        state: ReflectionState,
        route: CompassionRoute,
        context: ReflectionContext,
        analysis: ContextAnalysis?,
        card: ReflectionCard?,
        trackingCues: [TrackingCue],
        nextQuestionGoal: String,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn

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
    ) async throws -> DialogueTurn
}

extension DialogueGenerating {
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
        try await generate(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            nextQuestionGoal: nextQuestionGoal,
            messages: messages
        )
    }
}

protocol DialogueQuestionRewriting: Sendable {
    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn
}

struct RemoteDialogueQuestionRewriter: DialogueQuestionRewriting {
    private let prompts: any ReflectionPromptBuilding

    init(prompts: any ReflectionPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func rewriteQuestion(
        state: ReflectionState,
        nextQuestionGoal: String,
        draft: DialogueTurn,
        messages: [ChatMessage]
    ) async throws -> DialogueTurn {
        let prompt = prompts.questionRewritePrompt(
            state: state,
            nextQuestionGoal: nextQuestionGoal,
            draft: draft,
            recentMessages: messages
        )
        let text = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 180,
            temperature: 0.1,
            agentMode: "fast"
        )
        return try DialogueTurnParser.parse(text)
    }
}

struct RemoteContextAnalyzer: ContextAnalyzing {
    private let prompts: any ReflectionPromptBuilding
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "ContextAnalyzer")

    init(prompts: any ReflectionPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func analyze(context: ReflectionContext, messages: [ChatMessage]) async -> ContextAnalysis {
        await analyze(
            context: context,
            messages: messages,
            planningContext: nil
        )
    }

    func analyze(
        context: ReflectionContext,
        messages: [ChatMessage],
        planningContext: ResponsePlanningContext?
    ) async -> ContextAnalysis {
        let prompt = prompts.analyzerPrompt(
            context: context,
            messages: messages,
            planningContext: planningContext
        )
        do {
            let text = try await RemoteAPIService.shared.completeJSON(
                system: prompt.system,
                user: prompt.user,
                maxTokens: 1_200,
                temperature: 0.05,
                agentMode: "fast"
            )
            return try ContextAnalysisParser.parse(text)
        } catch {
            logger.error("Analyzer unavailable or invalid; preserving uncertainty. Error type: \(String(describing: type(of: error)), privacy: .public)")
            return .fallback()
        }
    }
}

struct RemoteDialogueGenerator: DialogueGenerating {
    private let prompts: any ReflectionPromptBuilding
    private let questionRewriter: any DialogueQuestionRewriting
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "DialogueGenerator")

    init(
        prompts: any ReflectionPromptBuilding = ReflectionPromptFactory(),
        questionRewriter: (any DialogueQuestionRewriting)? = nil
    ) {
        self.prompts = prompts
        self.questionRewriter = questionRewriter ?? RemoteDialogueQuestionRewriter(prompts: prompts)
    }

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
        try await generate(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: .standard,
            nextQuestionGoal: nextQuestionGoal,
            messages: messages
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
        let prompt = prompts.dialoguePrompt(
            state: state,
            route: route,
            context: context,
            analysis: analysis,
            card: card,
            trackingCues: trackingCues,
            promptEvidence: promptEvidence,
            nextQuestionGoal: nextQuestionGoal,
            recentMessages: messages
        )
        // Disclosure turns already have a dedicated ContextAnalyzer result. Running another
        // Planner before every short follow-up adds a long serial wait without changing the
        // application-controlled workflow. Keep planning for turns where a contextual inference or
        // synthesis needs an additional evidence check.
        let mode: String
        switch state {
        case .trackingReview, .attributionReflection, .actionSelection:
            // These turns run the full Planner->Writer->Critic path so the Critic can catch causal
            // tracking claims, second-person restatement, and unsupported card descriptors.
            mode = "deep"
        default:
            // A mid-confidence semantic reading is worth one lightweight Planner pass when the
            // next disclosure question could otherwise take the wrong branch. Clear routine
            // disclosure stays fast; this is not a reason to run every greeting through agents.
            mode = shouldUseBalancedPlanning(state: state, analysis: analysis) ? "balanced" : "fast"
        }
        let text = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 1_000,
            temperature: 0.32,
            agentMode: mode
        )
        do {
            var turn = try DialogueTurnParser.parse(text)
            turn.actionOptions = Array(turn.actionOptions.prefix(2))
            if let boundaryTurn = cardBoundaryTurn(
                for: state,
                nextQuestionGoal: nextQuestionGoal,
                messages: messages,
                cardInterpretation: context.cardInterpretation
            ) {
                return boundaryTurn
            }
            turn = await normalizedQuestionTurn(
                in: turn,
                state: state,
                nextQuestionGoal: nextQuestionGoal,
                context: context,
                messages: messages,
                responsePlan: promptEvidence.responsePlan
            )
            guard !turn.visibleText.isEmpty || (state == .actionSelection && !turn.actionOptions.isEmpty) else {
                throw LLMError.malformedResponse
            }
            if route == .repair {
                turn.question = concreteRepairQuestion(rewriting: turn.question, context: context)
            }
            return turn
        } catch {
            logger.error("Dialogue JSON invalid. Error type: \(String(describing: type(of: error)), privacy: .public)")
            throw LLMError.malformedResponse
        }
    }

    private func shouldUseBalancedPlanning(
        state: ReflectionState,
        analysis: ContextAnalysis?
    ) -> Bool {
        guard [.emotionDisclosure, .bodilyResponse, .selfJudgment, .contextDisclosure,
               .tenderGrounding, .tenderExploration, .readinessCheck].contains(state),
              let value = analysis?.validated else {
            return false
        }
        // Zero is the local analyzer fallback rather than a calibrated uncertain model result.
        // Keep that route fast and let Swift's neutral question protect the conversation.
        return value.confidence >= 0.35 && value.confidence < 0.65
    }

    func emergencyFallbackQuestion(
        for state: ReflectionState,
        nextQuestionGoal: String = "",
        context: ReflectionContext = .init(),
        messages: [ChatMessage] = [],
        responsePlan: ResponsePlan? = nil
    ) -> String {
        if let responsePlan, responsePlan.shouldAskQuestion {
            switch responsePlan.function {
            case .exploreLivedExperience:
                return "顺着你刚才说的这段经历，现在最难受的部分是什么？"
            case .clarifyPersonalMeaning:
                return "你开始这样看自己时，最担心接下来会发生什么？"
            case .clarifyCircumstances:
                return "除了眼前的结果，当时还有什么现实情况也让这件事更难处理？"
            default:
                break
            }
        }
        switch state {
        case .eventDisclosure:
            return "你愿意从最近一次发生的情况说起吗？"
        case .emotionDisclosure:
            if context.selfJudgment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return "那件事让你开始这样看自己。那时你最担心它说明什么？"
            }
            return "这件事发生时，你当时最明显的感受是什么？"
        case .bodilyResponse:
            return "想到这件事时，你现在有什么感受？没有特别明显的感觉也可以。"
        case .selfJudgment:
            return "这件事让你开始怎样看自己，或者最担心它说明什么？"
        case .contextDisclosure:
            return "那段时间，除了这件事，还有什么现实情况也在同时发生？"
        case .trackingReview:
            return "这些变化和你最近的感受对得上吗？不对也可以直接说。"
        case .cardInterpretation:
            return "沿着你刚才的说法，画面接下来可能会发生什么？"
        case .attributionReflection:
            let goal = nextQuestionGoal
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            if goal.contains("cardconnection") {
                return "按你刚才对画面的描述，它和这件事里的哪一部分有一点像吗？没有也可以。"
            }
            if goal.contains("cardmeaningshift") || goal.contains("perspective") {
                return "把这个画面和刚才的事放在一起后，你现在会怎样理解那件事？没有变化也可以。"
            }
            if goal.contains("candidcircumstances") || goal.contains("circumstance") {
                return "这件事里，有哪些现实困难也需要一起看见？"
            }
            if goal.contains("candidagency") || goal.contains("agency") {
                return "只看你能够决定的部分，你觉得哪一步最值得调整？暂时没有也可以。"
            }
            return "这样整理贴近你的想法吗？不贴近的地方可以直接改。"
        case .readinessCheck:
            return "这段整理和你的感受对得上吗？不对的地方直接告诉我就好。"
        case .tenderGrounding:
            return "我这样理解贴近吗？哪里不对可以直接告诉我。"
        case .tenderExploration:
            return "这个问题先放下，不用勉强找答案。你还有哪部分想接着说？"
        case .welcome, .trackingPermission, .cardIntroduction, .actionSelection,
             .summary, .completed, .safetySupport:
            return ""
        }
    }

    func stateRequiresQuestion(_ state: ReflectionState) -> Bool {
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure, .trackingReview, .tenderGrounding, .readinessCheck,
             .tenderExploration, .cardInterpretation, .attributionReflection:
            return true
        case .welcome, .trackingPermission, .cardIntroduction, .actionSelection,
             .summary, .completed, .safetySupport:
            return false
        }
    }

    func bestQuestion(
        in turn: DialogueTurn,
        state: ReflectionState,
        nextQuestionGoal: String
    ) -> String? {
        let candidates =
            questionClauses(in: turn.question).map { ($0, true) }
            + questionClauses(in: turn.reflection).map { ($0, false) }
        let ranked = candidates.compactMap { candidate, fromQuestionField -> (String, Int, Bool)? in
            guard isUsableQuestion(candidate) else { return nil }
            let score = questionRelevanceScore(
                candidate,
                state: state,
                nextQuestionGoal: nextQuestionGoal
            )
            guard score > 0 else { return nil }
            return (candidate, score, fromQuestionField)
        }
        return ranked.max {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.2 != $1.2 { return !$0.2 && $1.2 }
            return $0.0.count > $1.0.count
        }?.0
    }

    func normalizedQuestionTurn(
        in original: DialogueTurn,
        state: ReflectionState,
        nextQuestionGoal: String,
        context: ReflectionContext,
        messages: [ChatMessage],
        responsePlan: ResponsePlan? = nil
    ) async -> DialogueTurn {
        var turn = original
        guard stateRequiresQuestion(state) else {
            turn.reflection = [
                removingQuestionClauses(from: turn.reflection),
                removingQuestionClauses(from: turn.question),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            turn.question = ""
            return turn
        }

        turn.reflection = removingQuestionClauses(from: turn.reflection)
        if let selected = bestQuestion(
            in: original,
            state: state,
            nextQuestionGoal: nextQuestionGoal
        ) {
            turn.question = selected
            return turn
        }

        do {
            let rewritten = try await questionRewriter.rewriteQuestion(
                state: state,
                nextQuestionGoal: nextQuestionGoal,
                draft: original,
                messages: messages
            )
            let rewrittenCandidates =
                questionClauses(in: rewritten.question)
                + questionClauses(in: rewritten.reflection)
            if rewrittenCandidates.count == 1,
               let question = rewrittenCandidates.first,
               isUsableQuestion(question) {
                turn.question = question
                return turn
            }
            logger.error("Question rewrite returned no single usable question; using emergency fallback.")
        } catch {
            logger.error("Question rewrite unavailable; using emergency fallback. Error type: \(String(describing: type(of: error)), privacy: .public)")
        }

        turn.question = emergencyFallbackQuestion(
            for: state,
            nextQuestionGoal: nextQuestionGoal,
            context: context,
            messages: messages,
            responsePlan: responsePlan
        )
        return turn
    }

    private func latestUserText(from messages: [ChatMessage]) -> String {
        messages.last(where: { $0.role == .user })?.content ?? ""
    }

    private func questionClauses(in text: String) -> [String] {
        var questions: [String] = []
        var clause = ""
        for character in text {
            clause.append(character)
            if "。！？?!\n".contains(character) {
                let value = clause.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.contains("？") || value.contains("?") {
                    questions.append(value)
                }
                clause = ""
            }
        }
        let tail = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.contains("？") || tail.contains("?") {
            questions.append(tail)
        }
        return questions
    }

    private func isUsableQuestion(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.count <= 140,
              clean.filter({ $0 == "？" || $0 == "?" }).count == 1 else {
            return false
        }
        let prohibited = [
            "workflow", "阶段", "规则", "不重复追问", "nextquestiongoal",
            "作为模型", "作为助手", "内部",
        ]
        return !prohibited.contains {
            clean.localizedCaseInsensitiveContains($0)
        }
    }

    private func questionRelevanceScore(
        _ question: String,
        state: ReflectionState,
        nextQuestionGoal: String
    ) -> Int {
        let normalizedQuestion = question.lowercased()
        let normalizedGoal = nextQuestionGoal.lowercased()
        let stateMarkers: [String]
        switch state {
        case .eventDisclosure:
            stateMarkers = ["发生", "情况", "那件事", "什么时候", "最近一次"]
        case .emotionDisclosure:
            stateMarkers = ["感受", "感觉", "难受", "担心", "害怕", "在意"]
        case .bodilyResponse:
            if ["身体哪里", "身体哪个", "哪个部位", "哪里最明显"].contains(where: {
                normalizedQuestion.contains($0)
            }) {
                return 0
            }
            stateMarkers = ["感受", "感觉", "想到", "现在"]
        case .selfJudgment:
            stateMarkers = ["自己", "担心", "说明", "意味着", "评价", "结论"]
        case .contextDisclosure:
            stateMarkers = ["同时", "当时", "现实", "情况", "难处", "限制", "精力"]
        case .trackingReview:
            stateMarkers = ["最近", "变化", "对得上", "贴近", "感受", "状态"]
        case .tenderGrounding, .readinessCheck:
            stateMarkers = ["贴近", "符合", "准确", "哪里不对", "需要改", "理解"]
        case .tenderExploration:
            stateMarkers = ["感受", "想说", "接着", "在意", "需要"]
        case .cardInterpretation:
            stateMarkers = ["画面", "接下来", "发生", "这个人", "这个"]
        case .attributionReflection:
            stateMarkers = ["这件事", "画面", "想到", "理解", "变化", "困难", "限制", "具体", "改变"]
        default:
            stateMarkers = []
        }

        var score = stateMarkers.reduce(into: 0) { value, marker in
            if normalizedQuestion.contains(marker) { value += 2 }
        }
        let goalMarkerGroups: [([String], [String])] = [
            (["felt", "emotion"], ["感受", "感觉", "难受", "担心", "在意"]),
            (["task-progress", "stalled"], ["开始", "推进", "卡住", "进展"]),
            (["accuracy", "correct", "summary"], ["贴近", "准确", "符合", "哪里不对", "需要改"]),
            (["cardconnection", "card connection"], ["画面", "想到", "像", "联系"]),
            (["perspective", "meaning shift"], ["理解", "看见", "变化", "现在"]),
            (["circumstance", "constraint"], ["情况", "困难", "限制", "影响"]),
            (["agency", "change"], ["具体", "改变", "调整", "下一步", "能做"]),
            (["action"], ["下一步", "愿意", "试试", "做"]),
        ]
        for (goalMarkers, questionMarkers) in goalMarkerGroups
        where goalMarkers.contains(where: { normalizedGoal.contains($0) }) {
            score += questionMarkers.reduce(into: 0) { value, marker in
                if normalizedQuestion.contains(marker) { value += 3 }
            }
        }
        return score
    }

    private func removingQuestionClauses(from text: String) -> String {
        var kept: [String] = []
        var clause = ""
        for character in text {
            clause.append(character)
            if "。！？?!".contains(character) {
                if !clause.contains("？") && !clause.contains("?") {
                    kept.append(clause)
                }
                clause = ""
            }
        }
        if !clause.contains("？") && !clause.contains("?") {
            kept.append(clause)
        }
        return kept.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func concreteRepairQuestion(rewriting question: String, context: ReflectionContext) -> String {
        let abstractPhrases = [
            "有什么需要修复", "需要修复", "哪段关系", "关系需要重新说清楚", "重新说清楚",
            "该承担什么", "承担什么", "承担哪", "责任是什么", "该负什么责任", "怎么负责", "如何负责",
            "怎么修复", "如何修复", "做什么弥补", "怎么弥补",
        ]
        guard abstractPhrases.contains(where: { question.contains($0) }) else { return question }

        if let contribution = context.personalContributions.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contribution.isEmpty {
            let concrete = String(contribution.prefix(28))
            return "关于“\(concrete)”这件事，你觉得对方当时最需要先知道什么？"
        }
        return "这件事里，你确认是自己做过或没做到的是哪一步？"
    }

    func cardBoundaryTurn(
        for state: ReflectionState,
        nextQuestionGoal: String = "",
        messages: [ChatMessage],
        cardInterpretation: String? = nil
    ) -> DialogueTurn? {
        guard state == .cardInterpretation || state == .attributionReflection,
              let latestMessage = messages.last(where: { $0.role == .user }) else { return nil }
        // `attributionReflection` is a legacy broad state reused by the finer Swift-owned
        // connection, candid, action, and narrative phases. A short answer such as “没有” is a
        // card boundary only while Swift explicitly says it is asking for card connection. In a
        // candid or action phase the same word is a substantive answer and must not be swallowed.
        if state == .attributionReflection {
            let normalizedGoal = nextQuestionGoal
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            guard normalizedGoal.contains("workflowphase:cardconnection") else { return nil }
            // Swift permits one final, explicitly optional scaffold after the first soft
            // “想不到”. Make that invitation deterministic so a writer cannot accidentally
            // return a terminal sentence while the state machine is still awaiting the bounded
            // second answer.
            if normalizedGoal.contains("onefinal") || normalizedGoal.contains("最后一次") {
                let anchor = cardInterpretation?
                    .split(separator: "；", omittingEmptySubsequences: true)
                    .last
                    .map { String($0.prefix(26)) }
                let question = anchor.map {
                    "只看你刚才说的“\($0)”，它和刚才那件事里的哪一部分有一点像吗？如果没有，直接说没有就可以。"
                } ?? "只看你刚才描述的那个动作或关系，它和刚才那件事里的哪一部分有一点像吗？如果没有，直接说没有就可以。"
                return DialogueTurn(
                    reflection: "先不用找一个完整的解释。",
                    question: question,
                    actionOptions: []
                )
            }
        }
        // A “没有了” submitted while describing the picture may legitimately move the app into
        // attribution and receive one optional reality invitation. Only treat it as a connection
        // boundary when it was answered inside the current card phase (legacy nil states remain safe).
        if state == .attributionReflection,
           let messageState = latestMessage.state,
           messageState != .attributionReflection {
            return nil
        }
        let latest = latestMessage.content
        let clean = latest
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "")
        let exactBoundaries = ["没有", "没有了", "没了", "想不到", "没想到什么"]
        let phraseBoundaries = ["有点难想到", "不太想得到", "好像没有了", "没什么能联系的"]
        guard exactBoundaries.contains(clean) || phraseBoundaries.contains(where: { clean.contains($0) }) else {
            return nil
        }
        return DialogueTurn(
            reflection: "好，不用勉强把画面和现实连起来。就先停在这里。",
            question: "",
            actionOptions: []
        )
    }
}

enum ContextAnalysisParser {
    static func parse(_ text: String) throws -> ContextAnalysis {
        try JSONDecoder()
            .decode(PartialContextAnalysis.self, from: Data(text.utf8))
            .materialized
            .validated
    }
}

enum DialogueTurnParser {
    static func parse(_ text: String) throws -> DialogueTurn {
        try JSONDecoder()
            .decode(PartialDialogueTurn.self, from: Data(text.utf8))
            .materialized
    }
}

private struct PartialDialogueTurn: Decodable {
    var reflection: String
    var question: String
    var actionOptions: [DialogueActionOption]

    private enum CodingKeys: String, CodingKey {
        case reflection, question, actionOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reflection = (try? container.decode(String.self, forKey: .reflection)) ?? ""
        question = (try? container.decode(String.self, forKey: .question)) ?? ""
        actionOptions = (try? container.decode([DialogueActionOption].self, forKey: .actionOptions)) ?? []
    }

    var materialized: DialogueTurn {
        DialogueTurn(reflection: reflection, question: question, actionOptions: actionOptions)
    }
}

struct PartialContextAnalysis: Decodable {
    var safetyOverride: Bool?
    var distressLevel: Int?
    var selfAttackLevel: Int?
    var reflectiveCapacity: Int?
    var behaviorIdentitySeparation: Int?
    var multipleExplanationsCapacity: Int?
    var consentToCandor: ConsentState?
    var eventType: ReflectionEventType?
    var taskProgressStatus: TaskProgressStatus?
    var userAdmittedBehavior: Bool?
    var confirmedBehavior: String?
    var behaviorEvidence: [String]?
    var eventDescription: String?
    var emotions: [String]?
    var bodilyResponses: [String]?
    var selfJudgment: String?
    var contextualConstraints: [String]?
    var personalContributions: [String]?
    var possibleImpactOnOthers: [String]?
    var possibleBoundaryConcerns: [String]?
    var possibleUnmetNeeds: [String]?
    var possibleRepeatingPatterns: [String]?
    var uncertainties: [String]?
    var pastControllability: ControllabilityLevel?
    var presentAgency: AgencyLevel?
    var recommendedRoute: CompassionRoute?
    var secondaryRoutes: [CompassionRoute]?
    var reasonCodes: [String]?
    var missingInformation: [String]?
    var nextQuestionGoal: String?
    var semanticRelations: [SemanticRelation]?
    var responsePlan: ResponsePlan?
    var confidence: Double?

    var materialized: ContextAnalysis {
        ContextAnalysis(
            safetyOverride: safetyOverride ?? false,
            distressLevel: distressLevel ?? 0,
            selfAttackLevel: selfAttackLevel ?? 0,
            reflectiveCapacity: reflectiveCapacity ?? 1,
            behaviorIdentitySeparation: behaviorIdentitySeparation ?? 0,
            multipleExplanationsCapacity: multipleExplanationsCapacity ?? 0,
            consentToCandor: consentToCandor ?? .unknown,
            eventType: eventType ?? .unclear,
            taskProgressStatus: taskProgressStatus ?? .notApplicable,
            userAdmittedBehavior: userAdmittedBehavior ?? false,
            confirmedBehavior: confirmedBehavior,
            behaviorEvidence: behaviorEvidence ?? [],
            eventDescription: eventDescription,
            emotions: emotions ?? [],
            bodilyResponses: bodilyResponses ?? [],
            selfJudgment: selfJudgment,
            contextualConstraints: contextualConstraints ?? [],
            personalContributions: personalContributions ?? [],
            possibleImpactOnOthers: possibleImpactOnOthers ?? [],
            possibleBoundaryConcerns: possibleBoundaryConcerns ?? [],
            possibleUnmetNeeds: possibleUnmetNeeds ?? [],
            possibleRepeatingPatterns: possibleRepeatingPatterns ?? [],
            uncertainties: uncertainties ?? [],
            pastControllability: pastControllability ?? .unknown,
            presentAgency: presentAgency ?? .unknown,
            recommendedRoute: recommendedRoute ?? .explore,
            secondaryRoutes: secondaryRoutes ?? [],
            reasonCodes: reasonCodes ?? [],
            missingInformation: missingInformation ?? [],
            nextQuestionGoal: nextQuestionGoal ?? "invite one concrete detail",
            semanticRelations: semanticRelations ?? [],
            responsePlan: responsePlan,
            confidence: confidence ?? 0
        )
    }
}

extension ReflectionPromptFactory {
    static let pendingCardMappingProtocolCorrection = """
    A substantive Card Reading is already visible and the current application-owned prompt is \
    cardMapping. Interpret the latest user reply against that exact pending confirmation. If it \
    accepts, revises, or rejects the reading, preserve that decision and referenceID, use \
    replyIntent=directCandidReflection, move to requestedStage=directReflection, and set \
    nextPrompt=none. This transaction only commits the old confirmation; Swift will request the \
    first directReflection reply in a fresh protocolContinuation turn. Do not draft that question \
    now, do not use presentCardReading, and do not ask for the mapping again. Only if the latest \
    reply is genuinely unclear may you resolve it as unclear, stay in \
    cardReflection, use presentCardReading with an updated non-empty cardNegotiatedMeaning, and \
    establish a new cardMapping confirmationRequest.
    """

    static let trackingToTenderObjectProtocolCorrection = """
    The latest user reply is resolving the exact pending trackingRelationship. The prior plan \
    already chose to move into a Tender summary but omitted its candidate object. Preserve the \
    tracking decision and referenceID, use integrateTrackingAndPresentTenderSummary, store a \
    concise non-empty tenderUnderstanding, move to tenderConfirmation, and create a tenderSummary \
    confirmationRequest. If the tracking decision is unrelated, exclude that cue from the Tender \
    attribution instead of forcing a relationship. Do not use presentTenderSummary without the \
    combined tracking resolution.
    """

    static let finalNarrativeObjectProtocolCorrection = """
    The reflection is already narrative-ready. Do not return to directCandidReflection or ask \
    another question. Keep replyIntent=presentFinalNarrative, requestedStage=narrativeConfirmation, \
    localAction=none, store the complete non-empty candidate in memoryUpdate.finalNarrative, and \
    create a finalNarrative confirmationRequest. Rewrite confirmed relations into one natural \
    narrative; do not concatenate the tracking baseline, card dialogue, and individual answers.
    """
}

enum LLMError: LocalizedError {
    case malformedResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "AI 服务返回了无法解析的内容"
        case .unavailable: "AI 服务暂时不可用"
        }
    }
}
