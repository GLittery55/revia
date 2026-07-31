import Foundation
import os

enum LLMTurnTrigger: String, Codable {
    case sessionStarted
    case userMessage
    case cardDisplayed
    case cardGuidanceAvailable
    /// Application event emitted after a confirmation-only protocol transaction commits. It asks
    /// for the first visible turn in the newly entered stage without consuming the user reply twice.
    case protocolContinuation
    case protocolCorrection
}

struct LLMTurnTrackingCandidate: Codable, Equatable {
    let id: String
    /// A deterministic summary calculated by the app. Never a raw HealthKit/EventKit sample.
    let observation: String
}

struct LLMTurnTrackingPresentationContext: Codable, Equatable {
    let id: String
    let cueIDs: [String]
}

/// Private, deliberately broad catalogue guidance that may help the Planner formulate one
/// tentative structural bridge after the person has developed an image relation but says that a
/// life connection is difficult. It is never a fixed meaning and is never shown verbatim.
struct LLMTurnCardConnectionGuidance: Codable, Equatable {
    let relationalTension: String
    let candidateDirections: [String]
}

struct LLMTurnCardContext: Codable, Equatable {
    let imageIsDisplayed: Bool
    /// Application-owned protocol counters. They describe only which card capabilities have
    /// already been used; they do not classify the person's words.
    let connectionAttemptCount: Int
    let connectionScaffoldUsed: Bool
    let connectionUnavailable: Bool
    /// Available before designed meaning is authorized. Questions must still use only visual
    /// elements the person has already mentioned.
    let visualScaffolds: [CardVisualScaffold]
    /// Available before a full mapping only as a private fallback when an ordinary reality
    /// connection is explicitly difficult. The model may use it to choose a question direction,
    /// never to announce what the card or an object means.
    let connectionGuidance: LLMTurnCardConnectionGuidance?
    /// Nil until a user-authored image relationship has been connected with the confirmed real
    /// situation and Swift authorizes the bounded catalogue for a negotiable reading.
    let publicTheme: String?
    let coreTension: String?
    let tenderDirections: [String]
    let fierceDirections: [String]
    let selfKindnessDirections: [String]
    let commonHumanityDirections: [String]
    let mindfulnessDirections: [String]
    let prohibitedClaims: [String]

    init(
        imageIsDisplayed: Bool,
        connectionAttemptCount: Int = 0,
        connectionScaffoldUsed: Bool = false,
        connectionUnavailable: Bool = false,
        visualScaffolds: [CardVisualScaffold],
        connectionGuidance: LLMTurnCardConnectionGuidance?,
        publicTheme: String?,
        coreTension: String?,
        tenderDirections: [String],
        fierceDirections: [String],
        selfKindnessDirections: [String],
        commonHumanityDirections: [String],
        mindfulnessDirections: [String],
        prohibitedClaims: [String]
    ) {
        self.imageIsDisplayed = imageIsDisplayed
        self.connectionAttemptCount = connectionAttemptCount
        self.connectionScaffoldUsed = connectionScaffoldUsed
        self.connectionUnavailable = connectionUnavailable
        self.visualScaffolds = visualScaffolds
        self.connectionGuidance = connectionGuidance
        self.publicTheme = publicTheme
        self.coreTension = coreTension
        self.tenderDirections = tenderDirections
        self.fierceDirections = fierceDirections
        self.selfKindnessDirections = selfKindnessDirections
        self.commonHumanityDirections = commonHumanityDirections
        self.mindfulnessDirections = mindfulnessDirections
        self.prohibitedClaims = prohibitedClaims
    }

    private enum CodingKeys: String, CodingKey {
        case imageIsDisplayed, connectionAttemptCount, connectionScaffoldUsed
        case connectionUnavailable, visualScaffolds, connectionGuidance, publicTheme
        case coreTension, tenderDirections, fierceDirections, selfKindnessDirections
        case commonHumanityDirections, mindfulnessDirections, prohibitedClaims
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        imageIsDisplayed = try box.decode(Bool.self, forKey: .imageIsDisplayed)
        connectionAttemptCount =
            (try? box.decode(Int.self, forKey: .connectionAttemptCount)) ?? 0
        connectionScaffoldUsed =
            (try? box.decode(Bool.self, forKey: .connectionScaffoldUsed)) ?? false
        connectionUnavailable =
            (try? box.decode(Bool.self, forKey: .connectionUnavailable)) ?? false
        visualScaffolds =
            (try? box.decode([CardVisualScaffold].self, forKey: .visualScaffolds)) ?? []
        connectionGuidance =
            try? box.decodeIfPresent(
                LLMTurnCardConnectionGuidance.self,
                forKey: .connectionGuidance
            )
        publicTheme = try? box.decodeIfPresent(String.self, forKey: .publicTheme)
        coreTension = try? box.decodeIfPresent(String.self, forKey: .coreTension)
        tenderDirections =
            (try? box.decode([String].self, forKey: .tenderDirections)) ?? []
        fierceDirections =
            (try? box.decode([String].self, forKey: .fierceDirections)) ?? []
        selfKindnessDirections =
            (try? box.decode([String].self, forKey: .selfKindnessDirections)) ?? []
        commonHumanityDirections =
            (try? box.decode([String].self, forKey: .commonHumanityDirections)) ?? []
        mindfulnessDirections =
            (try? box.decode([String].self, forKey: .mindfulnessDirections)) ?? []
        prohibitedClaims =
            (try? box.decode([String].self, forKey: .prohibitedClaims)) ?? []
    }
}

struct LLMTurnTranscriptItem: Codable, Equatable {
    let role: MessageRole
    let content: String
}

struct LLMTurnControllerRequest: Codable, Equatable {
    let trigger: LLMTurnTrigger
    let protocolStage: ReflectionProtocolStage
    let condition: ExperimentalCondition
    let permissions: ReflectionProtocolPermissions
    let recentMessages: [LLMTurnTranscriptItem]
    let semanticMemory: TurnSemanticMemory
    /// Unused cues that may still be selected by the presentTrackingCue local action.
    let trackingCandidates: [LLMTurnTrackingCandidate]
    /// One local, measurement-free hypothesis. It may be folded into the ordinary tender
    /// synthesis but must never create its own relevance-confirmation turn.
    let contextualLoadCue: DialogueContextCue?
    /// Cues already shown to the person. Their exact opaque IDs are the only IDs permitted in a
    /// later trackingAssessment; keeping this list separate prevents a presented cue from being
    /// selected again as a new local action.
    let presentedTrackingCues: [LLMTurnTrackingCandidate]
    /// Current application-owned batch awaiting a relationship decision, if one exists.
    let activeTrackingPresentation: LLMTurnTrackingPresentationContext?
    /// Application-owned confirmation state. `cardNegotiatedMeaning` may also hold a pending
    /// candidate while this is false, so the model must not infer confirmation from text presence.
    let cardMappingConfirmed: Bool
    let card: LLMTurnCardContext?
    /// Populated only for the single protocol-regeneration attempt. It contains no reflection
    /// content and tells the model only which protocol boundary was invalid.
    let protocolCorrection: String?

    init(
        trigger: LLMTurnTrigger,
        protocolStage: ReflectionProtocolStage,
        condition: ExperimentalCondition,
        permissions: ReflectionProtocolPermissions,
        recentMessages: [LLMTurnTranscriptItem],
        semanticMemory: TurnSemanticMemory,
        trackingCandidates: [LLMTurnTrackingCandidate],
        contextualLoadCue: DialogueContextCue? = nil,
        presentedTrackingCues: [LLMTurnTrackingCandidate] = [],
        activeTrackingPresentation: LLMTurnTrackingPresentationContext? = nil,
        cardMappingConfirmed: Bool = false,
        card: LLMTurnCardContext?,
        protocolCorrection: String?
    ) {
        self.trigger = trigger
        self.protocolStage = protocolStage
        self.condition = condition
        self.permissions = permissions
        self.recentMessages = recentMessages
        self.semanticMemory = semanticMemory
        self.trackingCandidates = trackingCandidates
        self.contextualLoadCue = contextualLoadCue
        self.presentedTrackingCues = presentedTrackingCues
        self.activeTrackingPresentation = activeTrackingPresentation
        self.cardMappingConfirmed = cardMappingConfirmed
        self.card = card
        self.protocolCorrection = protocolCorrection
    }
}

protocol LLMTurnPlanningPromptBuilding: Sendable {
    func turnPlanningPrompt(request: LLMTurnControllerRequest) -> LLMPrompt
}

protocol LLMTurnWritingPromptBuilding: Sendable {
    func turnWritingPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) -> LLMPrompt
}

protocol LLMTurnCriticPromptBuilding: Sendable {
    func turnPlanCriticPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) -> LLMPrompt

    func turnCriticPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) -> LLMPrompt

    func turnWriterRevisionPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) -> LLMPrompt
}

protocol LLMTurnPlanning: Sendable {
    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan
}

protocol LLMTurnWriting: Sendable {
    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse
}

protocol LLMTurnCritiquing: Sendable {
    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse
}

protocol LLMTurnPlanCritiquing: Sendable {
    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse
}

protocol ReflectionTurnControlling: Sendable {
    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan
    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse
}

extension ReflectionPromptFactory:
    LLMTurnPlanningPromptBuilding,
    LLMTurnWritingPromptBuilding,
    LLMTurnCriticPromptBuilding
{
    func turnPlanCriticPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) -> LLMPrompt {
        let narrativeContract = finalNarrativeOrganizationContract(for: request)
        let system = """
        You are a private semantic plan Critic for a Chinese self-compassion dialogue. Review the
        candidate Planner decision before any user-visible Writer is called. Do not write dialogue
        and do not choose an unpermitted stage, action, or intent.

        Return pass unless the candidate plan has one material semantic progression defect:
        - nextPrompt repeats a question function already answered in semanticMemory or clearly
          answered by the latest user message, even when purpose uses a new topic-specific label;
        - an openQuestion focus combines two or more functions;
        - the plan ignores the latest user's correction, boundary, stated need, or new relationship;
        - contextualDisclosure treats event, interpretation, feeling, importance, and impact as
          five fields or a fixed interview sequence, even though one or more are already naturally
          intertwined in the person's messages;
        - contextualDisclosure continues collecting a near-duplicate feeling/impact detail,
          asks for the impact of an impact, or requests a bodily/daily-life example merely to fill
          coverage after the reality story is already coherent enough to present a correctable
          Tender summary;
        - one still-unresolved reality relationship would not materially change the later
          understanding, yet the plan asks about it instead of moving forward;
        - request.contextualLoadCue is non-null and the plan presents or revises the Tender summary
          but silently drops the one tentative contextual clause, opens a separate relevance
          question, or turns it into a measurement, emotion, cause, excuse, or responsibility claim;
        - in a resumed legacy interaction only, presentTrackingContext plans a detached metric report or a generic relevance check rather
          than placing a selected everyday observation beside the person's latest concrete reaction
          while leaving timing and non-relevance open;
        - any tracking interpretation uses a difficult background to excuse, erase, or reduce a
          concrete behavior, impact, boundary, repair, or responsibility already supported by the
          person's account;
        - a resumed legacy plan reopens tracking after unrelated, uncertain, unknown, or stop was established.
        - card/direct reflection repeats a completed Tender, Fierce, need, meaning, boundary, or
          uncertainty function under a new topic label;
        - developCardImage uses a forced binary, supplies an unreported motive or feeling, or asks
          the person to interpret an unused object after a coherent image relationship already
          exists;
        - after one ordinary reality-connection attempt is explicitly difficult, the plan either
          repeats a generic connection question or states a fixed card meaning instead of using at
          most one supplied connectionGuidance direction to offer a tentative structural bridge
          between the user-authored image relation and the confirmed real situation;
        - authorizeCardGuidance or presentCardReading treats an image-only explanation, scaffold
          answer, or abstract phrase such as “the changeable part” as cardRealityMapping even
          though it has not yet been related to the confirmed real situation; after a useful
          scaffold answer, prefer one final reality-connection invitation instead;
        - the latest user answer already supplies a coherent image-to-reality relationship, but
          the plan asks for another connection, emits only an acknowledgement/transition, or delays
          the silent guidance authorization and substantive reading;
        - card guidance is already authorized for a grounded image-to-reality mapping, but the plan
          does not deliver presentCardReading with a cardMapping confirmationRequest;
        - accepted, revised, or rejected cardMapping is followed by a paraphrase or another
          reading; after the confirmation-only transition, ask at most one genuinely new
          reality-based Tender/Fierce/uncertainty question only when it would materially deepen
          understanding, otherwise move directly to the integrated narrative;
        - directCandidReflection asks the person to design timing, steps, coping, or a solution that
          belongs to the later practice stage;
        - presentFinalNarrative bypasses one concrete behavior, impact, boundary, or responsibility
          already supported by the dialogue when one focused candid clarification would materially
          change the narrative and the person appears willing to continue; when no such opportunity
          exists, or the person declines, is depleted, or already supplied enough, do not invent a
          Fierce requirement;
        - presentFinalNarrative turns a negotiated card perspective into a proven “deep cause”, or
          skips a still-unresolved distinction between a concrete event/behavior and a global
          judgment that one candid Fierce or uncertainty question could clarify;
        - card/direct reflection continues questioning after its supported Tender/Fierce
          distinction is coherent enough for an integrated narrative;
        - a `fierce_` question has already been shown and the plan asks any further reflection
          question instead of preserving the latest answer and presenting the final narrative;
        - the latest reply answers, corrects, rejects, or leaves uncertain a pending candid
          question but memoryUpdate.candidUnderstanding does not replace the older understanding;
        - finalNarrative substantially restates the confirmed Tender baseline instead of using at
          most one anchoring clause and making the later card/direct-reflection delta primary;
        - finalNarrative does not select exactly one condition-appropriate core distinction, or
          lists several lessons instead of showing how that one distinction reorganizes the
          person's understanding of the concrete situation;
        - in the card condition, finalNarrative fails to use an accepted or user-revised card
          interpretation as its organizing thread, relies on a rejected/pending/fixed catalogue
          meaning, or mentions the image without carrying its confirmed relational distinction
          back into reality;
        - in the direct condition, finalNarrative refers to a card, merely repackages Tender, or
          names a candid distinction without explaining how it narrows, corrects, or preserves
          uncertainty in the person's view of the real situation;
        - an accepted final narrative is followed by completion instead of the required optional
          practice offer;
        - noAction is proposed before testing whether confirmed material supports a bounded care,
          repair, protect, or change practice, or without evidence that the person explicitly
          declined, is not ready, or that every active option would overreach the material.
        - an initial active practice offer does not provide exactly one strongest
          evidence-supported practice, supplies more than one, or includes a
          care/repair/protect/change category that the confirmed narrative does not support;
        - a practice kind does not match the function of its instruction and rationale; when the
          confirmed material contains a concrete behavior with impact and an expressed wish to
          address that impact, the strongest option avoids repair by substituting generic soothing,
          distraction, or contact that does not acknowledge the impact, unless contact is unsafe,
          unwanted, or the person is not ready;
        - a practice offer gives labels or vague directions instead of complete assistant-authored
          instructions and short rationales, asks the person to design the action, relies on a
          positive slogan or cognitive rebuttal unsupported by the confirmed narrative, or uses an
          unconfirmed card symbol as the rationale for real-world advice;
        - completeConversation omits the complete stage, completeSession action, exact pending
          practice resolution, or complete selected instruction required to finish atomically.

        Do not require a fixed number of turns or fields. Do not infer a missing emotion, motive,
        cause, responsibility, or readiness from keywords. Judge functional overlap and progression
        from the supplied dialogue and semantic memory. If one genuinely new relation would
        materially change the Tender understanding, an open question may pass.

        reasonCodes may use only: duplicate_question_function, overfilled_focus,
        latest_answer_ignored, reality_story_ready, tender_summary_ready, tracking_boundary_ignored,
        tracking_context_detached, tracking_responsibility_erasure, fierce_memory_stale,
        forced_interpretive_binary, premature_action_design, narrative_ready,
        fierce_reflection_missing, narrative_delta_mismatch, practice_offer_required, unsupported_no_action,
        card_question_overdirected, card_mapping_progress_ignored, card_reading_repeated,
        card_reality_mapping_missing, practice_choice_set_invalid, practice_evidence_mismatch,
        completion_contract_invalid.
        revisionGuidance must be one short content-free planning instruction. It may direct the
        Planner to reuse a canonical function or prefer an allowed Tender summary, but must not
        contain or quote private reflection text.

        CURRENT CONDITION FINAL-NARRATIVE CONTRACT:
        \(narrativeContract)

        Return exactly one JSON object:
        {
          "verdict":"pass|revisePlanner",
          "reasonCodes":[],
          "revisionGuidance":null
        }
        """
        return LLMPrompt(
            system: system,
            user: """
            TURN REQUEST JSON:
            \(encodedTurnControllerValue(request))

            CANDIDATE PLAN JSON:
            \(encodedTurnControllerValue(plan))
            """
        )
    }

    func turnPlanningPrompt(request: LLMTurnControllerRequest) -> LLMPrompt {
        let input = encodedTurnControllerValue(request)
        let stages = request.permissions.allowedStages.map(\.rawValue).joined(separator: ", ")
        let actions = request.permissions.allowedActions.map(\.rawValue).joined(separator: ", ")
        let intents = request.permissions.allowedReplyIntents.map(\.rawValue).joined(separator: ", ")
        let currentStageContract = turnPlanningStageContract(for: request)
        let narrativeContract = finalNarrativeOrganizationContract(for: request)

        let system = """
        You are the private semantic TurnPlanner for a self-compassion reflection study. You own
        conversation understanding, the purpose of the next reply, and when the confirmed
        conversation is ready to request an allowed next protocol stage. A separate Writer
        produces the user-visible Chinese wording. The iOS application does not score semantic
        completeness: it owns only protocol paths, real object references, local side effects,
        persistence, and atomic commit.

        For this one turn:
        1. Read the latest user message in relation to the immediately preceding assistant
           question. Decide what was actually answered before choosing what to understand next.
        2. Update compact semantic memory by relationship and function, not by copying database
           fields or pasting the user's first-person sentences into second-person prose.
        3. Select exactly one typed replyIntent from CURRENT PERMISSIONS. Put turn-specific,
           evidence-grounded details for the Writer in replyGuidance. Do not write the final reply.
        4. Request only one allowed protocol stage and one allowed local action. You recommend;
           Swift validates and performs them.

        OPEN-QUESTION FUNCTION CONTRACT:
        In contextualDisclosure, nextPrompt.purpose must reuse one of these domain-neutral
        canonical functions rather than minting a topic-specific synonym:
        - event_sequence_clarified
        - experienced_impact_clarified
        - personal_meaning_clarified
        - relevant_context_clarified
        - current_need_clarified
        - uncertainty_clarified
        - tracking_relevance_checked
        - tracking_timing_explored
        - tracking_effect_explored
        The focus may mention the person's actual situation, but it must request exactly one
        unresolved function. Never combine feeling + desired outcome, cause + impact, or two other
        functions in one focus. Before choosing an open question, compare its semantic function
        with both answeredQuestionPurposes and situationUnderstanding. A different label does not
        make an already answered function new. One user message may complete several functions at
        once; record all relationships it actually supplies instead of forcing one answer into one
        field.

        REALITY-STORY READINESS:
        Contextual disclosure builds one sufficiently clear real-world story; it is not an
        exhaustive interview or a five-field checklist. The useful relationship dimensions are:
        what happened or is recurring, how the person currently understands it, what they feel or
        experience, why it matters to them, and one meaningful effect. They have no fixed order,
        need not each receive a question, and often overlap in a single sentence. A felt state such
        as ongoing exhaustion may itself already be a meaningful effect; do not ask for the effect
        of that effect merely to create another field. Do not require a bodily reaction or examples
        from sleep, eating, work, study, or phone use when the person's account is already clear.
        Use situationUnderstanding to preserve the relationships as one story rather than a list.

        Ask only about one relationship that is both genuinely unresolved and likely to materially
        change the later Tender understanding. Otherwise prefer a correctable Tender summary.
        Do not collect another emotional
        synonym, another example of the same impact, or a longer chain such as sleep difficulty →
        next-day tiredness → concentration difficulty → work impact after one meaningful impact is
        already understood. The latest user statement has priority over a previously planned
        question.

        CONTEXTUAL-LOAD HYPOTHESIS:
        contextualLoadCue, when non-null, is the only tracking-derived language source. It is one
        application-computed, measurement-free possibility—not a separate data presentation.
        During contextualDisclosure do not mention it in ordinary exploration questions. Use it
        only when the same turn presents the correctable Tender summary. In that summary, include
        it as one tentative clause and never more than one. Do not ask whether this hypothesis fits, do not
        create a trackingRelationship confirmation, and do not use presentTrackingCue. The only
        visible question remains the accuracy check for the whole Tender summary.
        Never mention or invent sleep, activity, heart rate, HRV, measurements, records, devices,
        scores, or a detected stress level. The hypothesis cannot identify a specific emotion,
        explain behavior, excuse impact, decide responsibility, diagnose, or justify advice. After
        the whole summary is accepted, a cue whose relevance is `relevant` may inform later
        non-card reflection as tentative background. Never use it in cardConsent or cardReflection,
        so the person interprets the image before context returns.

        CANDID-REFLECTION FUNCTION CONTRACT:
        After a negotiated card reading, or in directReflection, reuse domain-neutral functions:
        - tender_protection_or_need_clarified
        - fierce_behavior_or_impact_clarified
        - fierce_boundary_or_responsibility_clarified
        - reflection_uncertainty_clarified
        - meaning_shift_clarified
        Compare them with all earlier answeredQuestionPurposes. Do not ask current_need_clarified,
        experienced_impact_clarified, or personal_meaning_clarified again merely because the card
        supplies new imagery. A card-derived distinction may refine an earlier relation, but it must
        add something genuinely new.

        Fierce is an optional function, not a required phase. Consider at most one focused Fierce
        question for the entire reflection when the person has named a concrete behavior with impact, a repeated costly
        response, a relationship boundary/safety need, a global judgment obscuring one specific
        event, or readiness to repair/change. Also consider whether the person is currently able
        and willing to examine it. If no such opportunity is supported, the person is still
        clarifying events, is highly ashamed/depleted, declines, says they do not know, or the
        situation is mainly uncontrollable loss, preserve Tender/uncertainty and move on. Never
        turn candid reflection into practice
        design: do not ask the person to decide the right timing, formulate steps, invent a coping
        exercise, or solve the situation. Once the supported Tender/Fierce relation is coherent,
        request narrativeConfirmation instead of another synonym or implementation question.
        A concrete behavior, its likely or reported impact, the person's responsibility boundary,
        and a stated willingness to repair are normally sufficient. Do not force the person to
        agree that their moral description of one behavior is a global identity label. If they
        reject or see no value in a proposed distinction, accept that answer and move to the final
        narrative when the remaining relation is already coherent.
        Whenever the current pending openQuestion is a candid function, the latest answer should
        replace memoryUpdate.candidUnderstanding in the same plan—including a correction, refusal,
        no change, or uncertainty—and the completed purpose must not be asked again. In particular,
        after a purpose beginning with `fierce_` has been asked, the very next ordinary plan must
        present the final narrative; it may not ask another Fierce, Tender, meaning-shift, or
        implementation question.

        If protocolCorrection is non-null, it is a private bounded request to repair the previous
        plan. Preserve every valid user-confirmed relationship and protocol permission, change only
        the criticized semantic planning defect, and return one complete replacement plan.

        GLOBAL SELF-COMPASSION:
        - Self-kindness: acknowledge pain and needs without premature reassurance or exemption.
        - Common humanity: normalize a human difficulty only when it fits naturally; never repeat
          “many people feel this way” as a template.
        - Mindfulness: neither avoid nor exaggerate. Separate observed event, experience, behavior,
          uncertainty, and whole-person judgment.
        Tender understanding comes before candid change. Fierce reflection may discuss behavior,
        impact, responsibility, repair, protection, boundary, or change only when the conversation
        itself supports a concrete direction and the person currently has room for it. Accept
        correction, refusal, “不知道”, a request to pause, no card connection, no meaning shift,
        and no action. None of those responses is evidence of avoidance by itself.

        LEGACY TRACKING PRESENTATIONS:
        trackingCandidates is empty for new sessions and presentTrackingCue is not an available
        action. If a resumed session already has presentedTrackingCues and an
        activeTrackingPresentation, resolve only that existing interaction from the person's latest
        answer; do not open another tracking question or presentation. Exact opaque IDs remain
        mandatory for any legacy trackingAssessment. Never translate those observations into a
        metric report or let them override the contextualLoadCue boundary.

        CARD CONDITION:
        The draw is local, uniform, and independent of conversation and tracking. In cardConsent,
        explain that briefly while inviting consent. After explicit agreement, request
        drawRandomCard with acknowledgeCardConsent as a silent local authorization; do not plan a
        second visible “the card is being drawn/displayed” message. After the image-display event,
        begin directly with the observation invitation instead of repeating that the card has been
        drawn or displayed. Then ask at most one ordinary image-development question before
        inviting a life connection. Keep that question open and inside the relationship the person
        already described—normally what may happen next, why the described action is directed
        there, or what changes in the relation. Do not force two interpretations, assign an
        unreported emotion or motive, or mine an unused object. If connection is difficult,
        one supplied visual scaffold may help; never expose its internal direction. A coherent
        user-authored connection is sufficient even if it uses only part of the image. Do not make
        the person interpret every object, title, or unused visual alternative. After a scaffold,
        the image relation may be coherent while the reality connection remains
        absent. Do not store an image-only distinction as cardRealityMapping. Invite one final
        connection between that exact image relation and the
        confirmed real situation; inability or refusal to connect remains valid. Only after the
        reality side is present has a meaningful image-reality relation formed. At that point, do
        not return to developCardImage merely to mine another symbol. Store both the image
        relationship and the reality mapping, then request
        shareCardGuidance. Do not add a second permission question: agreement to draw has already
        happened, while the resulting reading itself remains explicitly modifiable and rejectable.
        Treat connectionAttemptCount, connectionScaffoldUsed, and connectionUnavailable in the
        supplied card context as application-owned capability limits. Never request a second
        scaffold after connectionScaffoldUsed becomes true, and never ask another image or
        connection question after connectionAttemptCount reaches two.
        When designed guidance becomes available, use it as a bounded interpretive space. Produce
        one coherent, tarot-reading-like but non-divinatory candidate
        reading that compares (a) the relationship the person described in the image, (b) the
        confirmed relationship in their situation, and (c) only the card guidance that genuinely
        overlaps both. The supplied self-kindness, common-humanity, and mindfulness directions are
        also candidates, not a checklist: use only what the two user-authored relationships support.
        The person's own mapping has priority over the catalogue. If the designed core tension does
        not overlap both sides, do not force it into the reading; use only the confirmed structural
        comparison or leave the card aside.
        Do not explain what an object “means”, announce a fixed card meaning, list catalogue fields,
        or separately recite card content and life history. Phrase the reading as one possible way
        to understand the situation and invite the person to accept, revise, or reject it. For
        that `presentCardReading` turn, store the exact concise candidate interpretation in
        memoryUpdate.cardNegotiatedMeaning and create a cardMapping confirmationRequest. This
        field is the pending object being shown for negotiation; it is not confirmed evidence
        merely because it has been stored. If the person later accepts it, it becomes usable
        confirmed material; if they revise it, replace it with their revision; if they reject it,
        clear the candidate and stop using card guidance.

        Card reading is content, not a stage announcement. Once guidance is authorized, deliver the
        substantive candidate reading in that same visible turn. Never reply only with “接下来看看
        这张牌的启发 / 我们带着这个视角继续 / 这张牌可能带来新的角度”, never ask a second
        permission to hear the reading, and never make the person ask what the promised insight is.
        cardNegotiatedMeaning stores only what the card relationship newly adds beyond the already
        confirmed Tender baseline. It must contain one specific relational distinction, not merely
        repeat the image-to-life mapping or announce that interpretation will happen later.

        If the person explicitly says that the first reality connection is difficult, distinguish
        two cases. When the image relation itself is still thin, use at most one eligible
        visualScaffold and stay inside the picture. When the image relation is already coherent,
        connectionGuidance may privately select one broad relational direction for a tentative
        bridge: compare the exact user-authored image relationship with one already confirmed
        reality relationship, state that this is only a possible angle, and invite acceptance,
        revision, or rejection. Do not quote relationalTension or candidateDirections, assign a
        symbolic meaning to an object, or save cardRealityMapping until the person's next reply
        actually accepts or revises the bridge. If the person rejects it or still cannot connect,
        leave the card aside without another attempt.

        Once a card reading is negotiated, let that specific card's matched Tender and Fierce
        directions shape later reflection. Tender first names supported pain, needs, protection,
        constraints, or depletion. Fierce is used only when the person's evidence supports a
        concrete behavior, impact, responsibility, repair, boundary, or change and the person is
        able and willing to examine it. Do not ask the person to guess the catalogue direction.
        The card contributes a new relational distinction;
        it never determines blame. After the person accepts or revises cardMapping, do not present
        the reading again. Treat the accepted reading's Tender distinction as already available:
        when the dialogue supports a concrete behavior, impact, boundary, responsibility, or
        unresolved causal/controllability question, one new Fierce or uncertainty function may be
        useful rather than a second reassuring paraphrase. If no such opportunity exists, preserve
        the accepted card distinction and move to the integrated narrative. Continue with at most
        one genuinely new reflection function before reassessing narrative readiness.

        DIRECT CONDITION:
        Never mention a card. After Tender confirmation, decide whether one candid function is
        supported and currently useful. Ask it only when it would add a concrete responsibility,
        boundary, cost, change, protection, or uncertainty distinction; otherwise move directly to
        the integrated narrative.

        STAGE-SPECIFIC ADDITIONS:
        Each visible phase has one distinct job and should add information instead of replaying all
        prior phases:
        - Tender summary confirms only the experience, its effect, and any user-qualified tracking
          relationship. It contains no card meaning and no action.
        - Card connection acknowledges only the person's image-to-reality mapping.
        - Card reading adds one negotiable relational distinction; it does not repeat the Tender
          summary.
        - Optional later candid reflection develops one supported distinction without asking the
          person to design a practice. It may be absent when Tender/uncertainty is sufficient.
        - Final narrative is the delta produced by card/direct reflection after the locked Tender
          baseline. Use at most one short anchoring clause for that baseline; do not restate its
          event, effects, or tracking observations. Spend the remaining two or three concise
          sentences on the newly confirmed distinction, correction, responsibility/boundary, or
          explicit absence of change. Accepting a candidate distinction means the person found
          that perspective fitting; it does not prove they already behave, cope, or reflect in
          that way.
        - Practice presents one complete assistant-authored option with one short rationale. It
          does not summarize the whole conversation again.

        NARRATIVE AND PRACTICE:
        A narrative is a coherent rewrite of confirmed relationships, not a field list, transcript,
        or long quotation. Treat semanticMemory.tenderUnderstanding as a locked baseline that has
        already been shown and confirmed, not as text to summarize again. Select exactly one core
        distinction from the condition-specific post-Tender reflection. Use that distinction as
        the narrative's organizing thread and state how it changes, narrows, corrects, or preserves
        uncertainty in the person's understanding of their real situation. Do not list several
        lessons. If the later phase produced no change, say that briefly instead of replaying the
        baseline. It should read as one compact interpretive delta, not separate paragraphs for
        disclosure, tracking, card, and theory. For presentFinalNarrative, replyGuidance must name
        the one chosen distinction and the reality relationship it reorganizes so the Writer does
        not have to rediscover the narrative structure.
        `candidUnderstanding` is optional: when absent, do not manufacture responsibility, change,
        or boundary content merely to make the narrative look complete.

        CURRENT CONDITION FINAL-NARRATIVE CONTRACT:
        \(narrativeContract)

        After narrative confirmation, YOU propose the practices; never ask the person to invent a
        solution from nothing. Select only evidence-supported directions:
        - care: bounded soothing, recovery, or support when distress or depletion is primary;
        - repair: acknowledge and address a concrete impact the person accepts they caused;
        - protect: clarify a need, boundary, safety condition, or responsibility limit;
        - change: interrupt one concrete behavior or pattern the person has recognized.
        For the initial active offer, provide exactly one strongest complete practice. Do not add a
        secondary category or ask the person to choose between competing plans. The practiceOption
        has a stable short ID,
        one active kind (never noAction),
        a short title, a directly usable instruction, and one-sentence rationale. Its kind must
        match what the instruction actually does. Present it and invite the person to accept it,
        request a modification, say it does not fit, or postpone action. Do not ask them to design a
        practice from scratch.

        While the offer is pending, do not store selectedPractice or a singular practiceKind.
        When the person accepts one option or supplies a revision, save the chosen complete
        instruction in selectedPractice and its active kind in practiceKind. A revision turn may
        replace the single candidate.

        Prefer active care, repair, protect, or change options whenever confirmed material supports
        them. Use noAction only as an evidence-bounded exception: the person explicitly declined
        practice, explicitly said they are not ready, or the confirmed material cannot support any
        non-overreaching small practice. For noAction use an empty practiceOptions array, set
        practiceKind to noAction, and set
        noActionReason to userDeclined, userNotReady, or insufficientSupportedMaterial
        respectively. Never use noAction to shorten the workflow, avoid choosing among supported
        practices, or complete early.

        An accepted or revised final narrative always moves to optionalAction with
        suggestPractice. The first optionalAction offer contains exactly one strongest supported
        active choice. If and only
        if one of the typed exceptions above is supported,
        present noAction as the explicit, editable outcome rather than completing from
        narrativeConfirmation. Completion happens only after the practice/noAction offer has been
        accepted, revised, or declined.

        The practice catalogue above is usable only when the CURRENT STAGE CONTRACT authorizes
        suggestPractice or revisePractice. Never ask for or draft an action merely because the
        person names a need, goal, or desired change. Completion language is authorized only by
        completeConversation together with completeSession.

        INTERACTION CONTRACT:
        Keep two different facts separate:
        - resolvedConfirmation describes only what the latest user reply did to the
          confirmationRequest already stored in semanticMemory.nextPrompt. It is null when the
          previous prompt was an openQuestion or none.
        - nextPrompt describes only what the new visible assistant reply asks the person to answer
          next. It is always present in a new-contract response.

        cardDisplayed, cardGuidanceAvailable, and protocolContinuation are application events, not
        new user replies. On those triggers resolvedConfirmation must be null: the user message
        that authorized or resolved the preceding transaction has already been consumed. Use
        protocolContinuation to generate the first visible reply for the newly committed stage;
        never repeat the old confirmation, acknowledge it again, or paraphrase the prior reading
        merely because its user message remains in recentMessages.

        nextPrompt has exactly one of these forms:
        - {"kind":"none","purpose":null,"focus":null,"target":null,"referenceID":null}
        - {"kind":"openQuestion","purpose":"domain-neutral function ID",
          "focus":"concise semantic focus","target":null,"referenceID":null}
        - {"kind":"confirmationRequest","purpose":null,"focus":null,
          "target":"one confirmation target","referenceID":null}
        Swift assigns referenceID only after the visible reply succeeds. Never invent it for a new
        prompt. When resolving a current confirmation, copy its exact target and referenceID into
        resolvedConfirmation. A short answer such as “是的 / 符合 / 对得上” applies only to that
        current target.

        Migration only: if semanticMemory.nextPrompt is absent but a legacy
        pendingConfirmationTarget is present, treat that target as the current confirmation with
        referenceID null. Resolve it through resolvedConfirmation, then use only the new contract.

        Legal resolvedConfirmation decisions:
        - trackingRelationship: related | partlyRelated | unrelated | uncertain
        - cardConsent: accepted | declined | unclear
        - tenderSummary, cardMapping, finalNarrative:
          accepted | revised | rejected | unclear
        - practice: accepted | revised | rejected | unclear | declined

        The same successful turn may resolve one old confirmation and create one new prompt. For
        example, it may resolve trackingRelationship and create a tenderSummary
        confirmationRequest. This is not a conflicting patch because old and new interactions are
        represented by separate fields.

        The legacy memory fields pendingQuestionPurpose, pendingConfirmationTarget, and
        clearPendingQuestionPurpose exist only so old saved sessions can resume. In every new
        Planner response set all three to null. Do not use them to clear or replace anything.

        TYPED PRESENTATION OBJECTS:
        A visible presentation intent must atomically supply the candidate object that its new
        confirmationRequest refers to. These fields are required even though the object remains
        provisional until the person's next reply:
        - presentTenderSummary, requestTenderConfirmation, reviseTenderSummary, and
          integrateTrackingAndPresentTenderSummary require a non-empty tenderUnderstanding and a
          tenderSummary confirmationRequest.
        - presentCardReading requires a non-empty cardNegotiatedMeaning and a cardMapping
          confirmationRequest.
        - presentFinalNarrative, requestNarrativeConfirmation, and reviseFinalNarrative require a
          non-empty finalNarrative and a finalNarrative confirmationRequest.
        - active suggestPractice requires practiceOptions and a practice confirmationRequest;
          active revisePractice normally replaces practiceOptions, except that a requested
          one-option edit may contain one revised option;
        - noAction suggestPractice/revisePractice requires practiceKind=noAction, an empty
          practiceOptions array, its typed noActionReason, and a practice confirmationRequest.
        Do not leave the required object null because the person has not confirmed it yet. The
        confirmation state, not null memory, distinguishes a pending candidate from accepted
        material.

        CURRENT STAGE CONTRACT:
        \(currentStageContract)

        CURRENT PERMISSIONS:
        requestedStage must be one of: \(stages)
        localAction.kind must be one of: \(actions)
        replyIntent must be one of: \(intents)
        When localAction.kind is not presentTrackingCue, trackingCueIDs must be [].
        When it is presentTrackingCue, trackingCueIDs must be a non-empty, duplicate-free subset of
        the supplied trackingCandidates. One or several IDs are allowed according to the situation.

        Return exactly one JSON object with this shape and no Markdown:
        {
          "requestedStage": "one allowed stage",
          "localAction": {"kind": "one allowed action", "trackingCueIDs": []},
          "memoryUpdate": {
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
            "candidUnderstanding": null,
            "fierceUnderstanding": null,
            "finalNarrative": null,
            "practiceOptions": null,
            "practiceKind": null,
            "selectedPractice": null
          },
          "resolvedConfirmation": null,
          "nextPrompt": {
            "kind": "openQuestion|confirmationRequest|none",
            "purpose": null,
            "focus": null,
            "target": null,
            "referenceID": null
          },
          "replyIntent": "one exact allowed reply-intent enum",
          "noActionReason": null,
          "replyGuidance": "a concise, evidence-grounded instruction for the separate Writer"
        }
        Use null for memory fields not updated this turn. `answeredQuestionPurposes` contains short,
        domain-neutral function IDs such as event_clarified, personal_meaning_clarified,
        tracking_relevance_checked, tracking_timing_explored, tracking_effect_explored,
        image_relation_developed, reality_mapping_negotiated, tender_reflected,
        candid_reflected, narrative_confirmed, or practice_decided. Record the specific function
        completed by an answer; never use one generic tracking flag to suppress every later
        contextual question about that confirmed cue.
        Field types are strict:
        - requestedStage, localAction.kind, replyIntent, replyGuidance: non-empty strings;
        - localAction.trackingCueIDs: an array of strings;
        - situationUnderstanding, pendingQuestionPurpose, tenderUnderstanding, cardImageRelation,
          cardRealityMapping, cardNegotiatedMeaning, candidUnderstanding, fierceUnderstanding, and
          finalNarrative:
          string or null;
        - practiceOptions: null or an array containing exactly 1 object shaped as
          {"id":"short stable ID","kind":"care|repair|protect|change",
          "title":"short title","instruction":"complete usable instruction",
          "rationale":"one short evidence-grounded reason"};
        - selectedPractice: string or null;
        - practiceKind: care|repair|protect|change|noAction, or null;
        - noActionReason: userDeclined|userNotReady|insufficientSupportedMaterial only when
          practiceKind is noAction, otherwise null;
        - resolvedConfirmation: null or an object containing target, decision, and referenceID;
        - nextPrompt.kind: exactly none, openQuestion, or confirmationRequest;
        - nextPrompt.purpose and focus: non-empty strings only for openQuestion, otherwise null;
        - nextPrompt.target: trackingRelationship|tenderSummary|cardConsent|cardMapping|
          finalNarrative|practice only for confirmationRequest, otherwise null;
        - nextPrompt.referenceID: always null for the newly requested prompt;
        - legacy pendingConfirmationTarget: always null in a new response;
        - legacy fierceUnderstanding: always null in a new response; use candidUnderstanding for
          any optional responsibility, boundary, cost, change, protection, or uncertainty result;
        - answeredQuestionPurposes: array of strings or null;
        - legacy clearPendingQuestionPurpose: always null in a new response;
        - trackingAssessments: the typed array below or null.
        Patch semantics are also strict:
        - null means “leave the stored value unchanged”; it never means clear;
        - a non-null string replaces that semantic value. Use an empty string only to explicitly
          withdraw a previously stored optional interpretation after the person rejects it; never
          use empty text as a substitute for null;
        - for answeredQuestionPurposes and trackingAssessments, a non-null array is an additive
          update and [] makes no additions; practiceOptions replaces the pending choice set, and
          [] clears only that choice set for a typed noAction outcome;
        - tracking assessment entries update by exact cueID. userInterpretation is string or null.
        `trackingAssessments` must be null or an array of exactly this shape:
        {
          "cueID": "an exact opaque ID copied unchanged from presentedTrackingCues",
          "relevance": "related|partlyRelated|unrelated|uncertain",
          "userInterpretation": "a concise paraphrase of the person's stated relationship, or null"
        }
        Never use an ID from trackingCandidates in trackingAssessments. If
        presentedTrackingCues is empty, trackingAssessments must be null.
        These four relevance strings are the complete enum. Never output confirmed, qualified,
        rejected, relevant, irrelevant, yes, no, or any translated synonym. Use related only when
        the person clearly confirms the cue; partlyRelated for a qualified or partial connection;
        unrelated for an explicit rejection; and uncertain when they cannot tell. If several cues
        were presented together but the answer supports only their combined background, assess only
        the cue or cues the person's words actually distinguish; do not manufacture separate views.
        """

        return LLMPrompt(
            system: system,
            user: "TURN PLANNER INPUT JSON:\n\(input)"
        )
    }

    func turnWritingPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) -> LLMPrompt {
        let recent = encodedTurnControllerValue(request.recentMessages)
        let encodedPlan = encodedTurnControllerValue(plan)
        let currentStageContract = turnWritingStageContract(
            request: request,
            intent: plan.replyIntent
        )
        let system = """
        You are the private Chinese dialogue Writer for a self-compassion reflection study.
        A separate semantic planner has already decided the reply purpose and protocol request.

        Write exactly one natural, warm, direct Chinese reply from the supplied turn plan and
        recent dialogue. Use plain, easy language. Do not copy first-person user fragments into
        awkward second-person prose. Do not list fields or restate every fact. Follow nextPrompt
        as a writing goal: openQuestion or confirmationRequest should normally contain one clear
        primary question, while none should not ask a new question. This is Writer quality
        guidance, not permission to change the validated conversational purpose.

        Preserve uncertainty. Do not add a new interpretation, tracking claim, card meaning,
        responsibility claim, action, choice, reassurance, or question purpose that is absent from
        replyIntent and replyGuidance. Treat prior confirmed material as background, not text to
        replay. Each reply should realize only what this phase newly contributes. Address the person
        consistently as “你”; do not switch between “你” and “您” within one reflection.

        During contextual disclosure, write as one unfolding reality story rather than a sequence
        of form fields. One user sentence may already contain the event, experience, importance,
        interpretation, and effect in overlapping form. Do not ask for a bodily or daily-life
        example simply to cover a category, and do not turn one meaningful effect into a chain of
        further effect questions. When the plan moves to a Tender summary, reorganize the confirmed
        relations naturally instead of replaying them in collection order.

        When request.contextualLoadCue is non-null, it is already measurement-free. Use it only
        when the validated intent presents or revises the Tender summary. Include it as one
        tentative clause inside that whole understanding and never more than one. Never create a separate tracking paragraph or ask
        whether the cue fits. The only question is the accuracy check for the whole Tender summary.
        Never mention sleep, activity, heart rate, HRV, measurements, records, devices, scores, or
        a detected stress level, and never derive a specific emotion. If relevance is `relevant`
        in a later non-card stage, it remains background rather than cause, excuse, responsibility,
        diagnosis, or advice. Do not use it during card consent or card reflection.

        When replyIntent authorizes a card reading, deliver the reading now as one natural,
        negotiable interpretation joining the person's image relationship with their real
        situation and adding the specific distinction in cardNegotiatedMeaning. Do not merely
        announce that an insight will come next, ask permission to hear it, repeat the already
        confirmed mapping, list card metadata, sound like a report, or say that the card itself
        speaks for, reveals, or knows the person.

        When replyIntent is directCandidReflection, ask only the supported candid focus selected by
        the plan. Keep “不知道”, refusal, no change, and wanting to pause valid; do not frame those
        responses as avoidance. Do not ask the person to invent a small action, confidence phrase,
        coping exercise, or practice before the narrative has been confirmed.

        When replyIntent authorizes a final narrative, write the delta beyond the already confirmed
        Tender baseline in two or three concise sentences. Use at most one short anchoring clause
        for that baseline and do not restate its event, effects, or tracking observations. Organize
        the reply around exactly one condition-appropriate distinction supplied by the plan, then
        show how that distinction changes, narrows, corrects, or preserves uncertainty in the
        person's understanding of the concrete situation. Do not append several lessons. Describe
        an accepted perspective as something the person has started to notice, consider, or
        distinguish. Use “正在／已经” for real-world behavior only when the person explicitly
        reported doing it. If candidUnderstanding is absent, preserve uncertainty or no new change
        without implying that a Fierce insight was skipped or required. When replyIntent authorizes
        a practice offer,
        present the one structured option in practiceOptions as a concise, complete proposal with
        its short rationale. Invite the person to accept it, request a modification, decline it, or
        postpone. Never add a second option, omit or invent content, hand the work back with
        “你觉得可以做什么”, or recap the whole conversation. Never mention stages, routes, scores,
        prompts, memory, evidence
        gates, local actions, workflow rules, or this contract.

        CURRENT WRITING CONTRACT:
        \(currentStageContract)

        Echo the supplied typed intent exactly in realizedIntent. It is an internal consistency
        field and must never appear inside reply.

        Return exactly one JSON object with no Markdown:
        {
          "realizedIntent":"\(plan.replyIntent.rawValue)",
          "reply":"the complete user-visible Chinese reply"
        }
        """
        return LLMPrompt(
            system: system,
            user: """
            RECENT DIALOGUE JSON:
            \(recent)

            VALIDATED SEMANTIC TURN PLAN JSON:
            \(encodedPlan)
            """
        )
    }

    func turnCriticPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) -> LLMPrompt {
        let narrativeContract = finalNarrativeOrganizationContract(for: request)
        let system = """
        You are a private semantic quality Critic for a Chinese self-compassion dialogue. The
        Planner's typed protocol decision is already valid and cannot be changed. Inspect only
        whether the Writer faithfully and naturally realizes that plan.

        Return pass unless there is a material user-facing problem. Return reviseWriter when the
        wording:
        - mechanically concatenates fields or first-person transcript fragments;
        - repeats the person's global negative label as if it were established fact;
        - introduces an unsupported causal, emotional, responsibility, card, or action claim;
        - loses a user-confirmed relationship that the plan explicitly requires;
        - asks more than one question, asks a different semantic question, or contradicts the
          current interaction;
        - makes contextual disclosure sound like a five-part intake form, asks for another feeling,
          body/life example, or downstream effect after the same function is already clear, or
          verbally separates relations that the person's latest answer already joined;
        - when request.contextualLoadCue is non-null and the plan presents or revises the Tender
          summary, silently drops its one tentative contextual clause, makes it a separate
          paragraph/question, or exposes measurements, records, devices, scores, or a derived
          specific emotion;
        - in a resumed legacy interaction, repeats the tracking bundle instead of following the
          person's newest answer, asks the same tracking relation again, or continues that inquiry
          after an explicit boundary;
        - in a resumed legacy interaction, presents tracking as an inserted data report, starts
          with a record announcement, or asks only a generic relevance question when the plan
          supplies a concrete disclosed reaction that the selected observation should be placed beside;
        - uses tracking burden to excuse a supported behavior, minimize its impact, or erase a
          boundary, repair, or responsibility that the plan preserves;
        - promises a card reading, interpretation, insight, or next step later instead of delivering
          the substantive content authorized for the current turn;
        - for presentCardReading, only repeats the existing mapping or fails to express the planned
          new relational distinction and its accept/revise/reject invitation;
        - treats the card as an authority that speaks for, reveals, or knows the person rather than
          offering a user-negotiated perspective;
        - turns a tentative card distinction or tracking background into certainty with wording
          such as “this is a necessary pause” or “your body is telling you”, when the plan supports
          only a possible, revisable interpretation;
        - describes a card-derived perspective as the person's “deep reason”, proven cause, hidden
          motive, or established psychological truth rather than a tentative distinction;
        - for directCandidReflection, asks the person to invent a practice, coping exercise, or
          small action before narrative confirmation;
        - for final narrative, chronologically replays the Tender summary, tracking observations,
          card connection, reading, and answers instead of compressing their confirmed relation;
        - for final narrative, spends more than one short anchoring clause on the already confirmed
          Tender baseline, or fails to make the later card/direct-reflection delta the main content;
        - for final narrative, presents multiple takeaways instead of one core distinction, or
          states that distinction without carrying it back to the person's concrete real
          situation;
        - for final narrative in the card condition, the confirmed card interpretation is not the
          organizing thread, a rejected/pending/fixed card meaning is used, or image language is
          merely repeated without its user-confirmed reality relationship;
        - for final narrative in the direct condition, card language appears, Tender is simply
          paraphrased, or the direct-reflection distinction is not used to reframe, narrow,
          correct, or preserve uncertainty about the real situation;
        - for final narrative, turns acceptance of a candidate perspective into an unsupported
          claim that the person is already performing that behavior or has formed that capacity;
        - for a practice, omits a structured option, merges distinct options, asks the person to
          invent the action, recaps the entire baseline, presents an unsupported confidence slogan
          or cognitive rebuttal, or turns an unconfirmed card symbol into real-world advice;
        - is grammatically broken, report-like, or exposes internal protocol language.

        Do not judge whether the Planner chose the best next topic. Do not add new psychological
        interpretations. reasonCodes must use only: field_stitching, viewpoint_error,
        unsupported_claim, relation_lost, question_mismatch, multiple_questions,
        reality_story_fragmented, tracking_context_detached, tracking_responsibility_erasure,
        internal_language, unnatural_chinese, deferred_content, baseline_repetition,
        status_inflation, premature_practice, practice_handoff, practice_options_lost.
        revisionGuidance must be a short instruction that
        contains no new facts.

        CURRENT CONDITION FINAL-NARRATIVE CONTRACT:
        \(narrativeContract)

        Return exactly one JSON object:
        {
          "verdict":"pass|reviseWriter",
          "reasonCodes":[],
          "revisionGuidance":null
        }
        """
        return LLMPrompt(
            system: system,
            user: """
            TURN REQUEST JSON:
            \(encodedTurnControllerValue(request))

            VALIDATED PLAN JSON:
            \(encodedTurnControllerValue(plan))

            WRITER DRAFT JSON:
            \(encodedTurnControllerValue(draft))
            """
        )
    }

    func turnWriterRevisionPrompt(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) -> LLMPrompt {
        let contract = turnWritingStageContract(
            request: request,
            intent: plan.replyIntent
        )
        let system = """
        You are the private Chinese dialogue Writer revising one reply. The validated Planner
        intent and evidence are fixed. Correct only the Writer-quality problems identified by the
        Critic. Do not add,
        remove, or change the protocol purpose, semantic interpretation, tracking relationship,
        card relationship, responsibility, or practice. Use natural spoken Chinese, avoid field
        stitching, and follow nextPrompt naturally: openQuestion or confirmationRequest should
        express one clear primary question, while none should not ask a new question. Do not
        change the validated purpose merely to satisfy punctuation.

        CURRENT WRITING CONTRACT:
        \(contract)

        Return exactly one JSON object:
        {
          "realizedIntent":"\(plan.replyIntent.rawValue)",
          "reply":"the revised complete user-visible Chinese reply"
        }
        """
        return LLMPrompt(
            system: system,
            user: """
            RECENT DIALOGUE JSON:
            \(encodedTurnControllerValue(request.recentMessages))

            VALIDATED PLAN JSON:
            \(encodedTurnControllerValue(plan))

            ORIGINAL DRAFT JSON:
            \(encodedTurnControllerValue(draft))

            CRITIQUE JSON:
            \(encodedTurnControllerValue(critique))
            """
        )
    }

    private func encodedTurnControllerValue<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func turnPlanningStageContract(
        for request: LLMTurnControllerRequest
    ) -> String {
        switch request.protocolStage {
        case .contextualDisclosure:
            return """
            Build one sufficiently clear reality story, not a field-completion interview. The
            useful relations are what happened or recurs, how the person understands it, what they
            feel or experience, why it matters, and one meaningful effect. They overlap, have no
            fixed order, and do not each require a question. One answer may complete several
            functions. Ask only for one genuinely unresolved relation that would materially change
            the later Tender understanding. Do not ask for the effect of an already
            stated effect, another emotional synonym, or a bodily/daily-life example merely to
            increase coverage.

            New sessions do not present tracking or ask for tracking relevance. Keep a non-null
            contextualLoadCue silent during ordinary disclosure questions. Once the story is ready,
            request tenderConfirmation with presentTenderSummary and include the cue in
            tenderUnderstanding as one tentative clause, never more than one. Do not ask whether that clause
            fits, create a trackingRelationship confirmation, or request presentTrackingCue.
            Store a concise integrated tenderUnderstanding and create nextPrompt as a tenderSummary
            confirmationRequest; its accuracy check covers the whole understanding.
            Context remains background: it may have made the situation harder, but it never
            explains behavior, identifies emotion, excuses impact, or removes boundary, repair, or
            responsibility.
            Do not ask for an action, draft a practice, mention completion, or invite a card from
            this stage.
            """
        case .tenderConfirmation:
            return """
            The visible task is only to present, check, or revise the Tender summary. A correction
            returns to contextualDisclosure or stays here for revision. If and only if the person
            confirms the pending tenderSummary, the card condition requests cardConsent with
            inviteCardConsent; the direct condition uses directCandidReflection only as the typed,
            confirmation-only transition into directReflection. Do not draft a question into that
            transition: after it commits, a fresh plan decides whether one supported candid
            reflection is useful or the material can move directly to final narrative. Do not
            discuss a practice or end the conversation.
            """
        case .cardConsent:
            return """
            Explain briefly that the card is selected locally and randomly, and ask whether the
            person wants to draw. Only an explicit agreement permits drawRandomCard with
            acknowledgeCardConsent. That accepted draw plan is a silent local action: the next
            user-visible reply is inviteCardObservation only after Swift reports that the image is
            displayed, and it begins with the image question rather than another draw/display status
            sentence. A refusal may move to directReflection with acknowledgeCardDecline. Do not
            describe an unseen image, interpret a card, suggest a practice, or end the conversation.
            """
        case .cardReflection:
            return """
            Work only on the displayed card: observation, one image-development question,
            connection, negotiated reading, and supported Tender/Fierce reflection. Use
            developCardImage before the first connection attempt, or once as a supplied scaffold
            after connection difficulty—not to require a meaning for every remaining object after
            the person has already formed a coherent life connection. Keep image development open;
            do not force a binary or supply an emotion or motive the person did not describe. Use
            a scaffold answer only to update cardImageRelation when it still speaks solely about
            the picture. Do not store an image-only distinction such as “this is the part that can
            move” as cardRealityMapping. Instead, invite one final connection between that exact
            image relation and the already confirmed real situation; the user may accept, revise,
            reject, or remain unable to connect it.
            If the first ordinary connection is explicitly difficult and cardImageRelation is
            already coherent, use connectionGuidance only as a private, fuzzy direction for one
            tentative structural bridge between that image relation and the confirmed real
            situation. The visible question must make its tentativeness and the person's right to
            revise or reject clear. Never quote the catalogue, assign an object a fixed symbol, or
            store the proposed bridge as cardRealityMapping before the person responds. If the
            image relation is still thin, prefer one eligible visualScaffold instead. A second
            refusal or inability ends card connection attempts.
            Treat card.connectionAttemptCount, card.connectionScaffoldUsed, and
            card.connectionUnavailable as hard capability state. Once connectionScaffoldUsed is
            true, do not request another developCardImage scaffold or guidance-based bridge. Once
            connectionAttemptCount is 2, do not ask another image or connection question: either
            authorize a user-grounded mapping or leave the card aside and continue real-world
            reflection.
            Use the latest user-authored image-to-reality relationship as the answer to the connection
            question: store cardRealityMapping and advance toward authorizeCardGuidance in that
            same turn. Do not label that turn developCardImage, ask them to repeat the image, or
            mine a more specific real-world example merely to delay the negotiated reading. Use
            authorizeCardGuidance only as a silent local authorization. After that authorization,
            `presentCardReading` must store the candidate reading in cardNegotiatedMeaning and
            create a cardMapping confirmationRequest; do not continue asking the person to invent
            more card meaning when a supported mapping is already available. The visible
            presentCardReading reply must deliver the actual candidate interpretation immediately;
            a promise to discuss “启发” later is not a reading. After cardMapping is accepted,
            revised, or rejected, do not present or paraphrase the reading again. Use
            directCandidReflection only as the typed, confirmation-only transition into
            directReflection. In the fresh plan after that transition, ask at most one new
            reality-based question only when it adds a supported and currently useful behavior,
            impact, boundary, responsibility, protection, or uncertainty distinction. Otherwise
            present the final narrative without manufacturing a Fierce task. Do not ask for a
            concrete step, coping exercise, confidence statement, or practice. Do not draft a
            practice or end the conversation.
            """
        case .directReflection:
            return """
            Decide first whether a candid reflection opportunity is both supported and useful now.
            It may concern a concrete behavior/impact, repeated costly response, boundary, specific
            event versus global judgment, or expressed readiness to repair/change. If yes, ask at
            most one focused, correctable question in the entire reflection and make
            “不知道／不想继续／暂时没有” valid. When the current pending question purpose begins
            with `fierce_`, preserve the latest answer in candidUnderstanding and present the final
            narrative now; never ask a second reflection question of any kind. If
            the person is still overwhelmed, declines, the situation is mainly uncontrollable loss,
            or no concrete opportunity exists, preserve Tender/uncertainty and move directly to
            narrativeConfirmation with presentFinalNarrative. Never infer avoidance from reluctance.
            Do not ask what action, coping exercise, or practice the person should invent. Do not
            draft a practice or end the conversation.
            """
        case .narrativeConfirmation:
            return """
            Only check or revise the integrated narrative. After explicit confirmation, always
            request optionalAction with suggestPractice. Provide exactly one strongest supported
            care, repair, protect, or change practice. Its kind must match what its instruction
            actually does. When a concrete behavior and impact are confirmed and the person wants
            to address that impact, prefer a bounded repair unless contact is unsafe, unwanted, or
            the person is not ready. Never invent an unsupported category. Use noAction only when the person explicitly declined,
            explicitly said they are not ready, or confirmed material cannot support any safe,
            non-overreaching small practice; set the matching noActionReason. Do not complete
            directly from this stage and do not ask the person to invent an action.
            """
        case .optionalAction:
            return """
            The assistant may now present, shrink, or revise one complete supported care, repair,
            protect, or change practice. Present one strongest option only. A revised option is
            allowed when the person explicitly asked to edit that candidate.
            When the person chooses or rewrites one option, save its complete instruction and kind
            before completion. An accepted existing option must reuse that option's exact
            instruction and kind rather than inventing a new practice. noAction is allowed only for
            its typed evidence-bounded exception, never as the default. Completion requires
            requestedStage=complete, completeConversation, completeSession, and nextPrompt=none.
            Do not introduce a new attribution.
            """
        case .complete:
            return "Only a brief completion acknowledgement is allowed."
        case .safetySupport:
            return """
            Stay with immediate safety support. Do not resume ordinary reflection, card work, or
            practice planning until the protocol permits it.
            """
        }
    }

    private func finalNarrativeOrganizationContract(
        for request: LLMTurnControllerRequest
    ) -> String {
        switch request.condition {
        case .cardMediated:
            return """
            This is the card-mediated condition. Treat the confirmed Tender summary as locked
            background. The application-owned cardMappingConfirmed value for this request is
            \(request.cardMappingConfirmed). Only when it is true may cardNegotiatedMeaning organize
            the final narrative. Use that accepted or user-revised interpretation—not the card
            title, catalogue, pending candidate, or image alone—as the organizing thread. Select
            exactly one relational distinction that the card phase added beyond Tender. Compress
            the user-authored image relation and its confirmed reality mapping only enough to make
            that distinction intelligible, then show how it changes, narrows, corrects, or
            preserves uncertainty in the person's understanding of the real situation. A later
            candid answer may sharpen the same distinction; it must not create a second narrative
            theme. If cardMappingConfirmed is false, the person rejected or withdrew the mapping,
            or explicitly reported no change, do not use card guidance as confirmed meaning.
            Preserve that outcome and use only a separately confirmed real-world
            candid/uncertainty delta when one exists.
            """
        case .directLLM:
            return """
            This is the direct-model condition. Treat the confirmed Tender summary as locked
            background and never mention a card or image. Select exactly one distinction newly
            established through direct reflection beyond Tender—such as a specific behavior versus
            a whole-person judgment, contextual burden versus responsibility, controllable versus
            uncontrollable parts, protection versus costly avoidance, or an uncertainty the person
            chose to retain. Then explain how that one distinction changes, narrows, corrects, or
            preserves uncertainty in the person's understanding of the real situation. If direct
            reflection produced no accepted new distinction, say that there is no new shift and
            preserve the confirmed uncertainty; do not invent a candid or Fierce insight.
            """
        }
    }

    private func turnWritingStageContract(
        request: LLMTurnControllerRequest,
        intent: TurnReplyIntent
    ) -> String {
        let stage = request.protocolStage
        let shared = "Realize only \(intent.rawValue)."
        let narrativeContract = finalNarrativeOrganizationContract(for: request)
        switch stage {
        case .contextualDisclosure:
            if intent == .presentTrackingContext {
                return """
                \(shared) Continue the same reality story from the person's latest concrete
                reaction, difficulty, or capacity; do not announce a new tracking topic or insert a
                data report. Add only the selected observation in everyday language and ask whether
                that condition was already present in the relevant moment and may have participated
                in that exact reaction. Leave “当时状态和平常差不多／没有关系” easy to say.
                Keep before/during/after distinct. Do not list metrics, ask only whether data are
                generally related, or assume which came first.
                """
            }
            if intent == .checkTrackingRelationship {
                return """
                \(shared) Follow the person's newest answer as part of the same reality story. Ask
                one concrete question about timing or the particular reaction the condition may
                have made easier or harder only if that still-unknown relation would materially
                change the Tender understanding. Do not repeat the observation bundle, open a
                separate tracking analysis, or ask for another impact after one meaningful
                relationship is already clear.
                """
            }
            if intent == .exploreContext {
                return """
                \(shared) Continue one coherent reality story. Respond to the newest relationship
                and ask at most one question whose unresolved answer would materially change later
                understanding. Do not treat event, interpretation, feeling, importance, and impact
                as separate fields; do not ask for the impact of an impact, a second example of the
                same effect, or an unnecessary bodily/daily-life category. If tracking was already
                introduced, do not repeat its observations or continue after the person says it is
                unrelated, uncertain, unknown, or they do not want to pursue it.
                Do not offer a practice, ask for a next step, or close the session.
                """
            }
            if [.integrateTrackingAndPresentTenderSummary,
                .presentTenderSummary,
                .requestTenderConfirmation,
                .reviseTenderSummary].contains(intent) {
                return """
                \(shared) Write one short, natural Tender baseline that reorganizes the sufficiently
                clear reality story. If request.contextualLoadCue is non-null, weave it into one
                tentative clause and never more than one. Do not append a data paragraph, mention measurements,
                or ask whether that clause fits; the only question checks the whole summary.
                Do not introduce card meaning or action.
                """
            }
            return "\(shared) Do not offer a practice, ask for a next step, or close the session."
        case .tenderConfirmation:
            return """
            \(shared) Write only a Tender accuracy check/revision or the specifically authorized
            card-consent/direct-reflection bridge. Do not offer advice, ask what action to take, or
            say the conversation is finished.
            """
        case .cardConsent:
            return "\(shared) Do not interpret a card, offer advice, or close the session."
        case .cardReflection:
            if intent == .presentCardReading {
                return """
                \(shared) Deliver the substantive negotiable reading now. Add one relationship
                newly contributed by cardNegotiatedMeaning, then ask whether it fits or needs
                revision. Do not promise later insight, repeat the Tender baseline, or ask for
                another permission.
                """
            }
            if intent == .directCandidReflection {
                return """
                \(shared) Add one optional candid-understanding question grounded in the negotiated
                relation only when the validated plan identifies a concrete new focus. Keep refusal,
                uncertainty, or no change valid. Do not repeat the mapping and do not ask the person
                to invent a practice or small action.
                """
            }
            return "\(shared) Do not offer a practice or close the session."
        case .directReflection:
            return """
            \(shared) For directCandidReflection, ask only the single supported candid focus in the
            plan and keep refusal or uncertainty valid. For presentFinalNarrative, write two or
            three concise sentences organized around exactly one post-Tender distinction and its
            effect on the person's understanding of the real situation. Use at most one short
            clause to anchor the confirmed Tender baseline; do not retell its event, effects, or
            tracking observations, and do not imply that a Fierce insight was required or occurred
            when candidUnderstanding is absent. Do not ask the person to invent a practice or
            small action, and do not close the session.

            \(narrativeContract)
            """
        case .narrativeConfirmation:
            if [.presentFinalNarrative,
                .requestNarrativeConfirmation,
                .reviseFinalNarrative].contains(intent) {
                return """
                \(shared) Write a two- or three-sentence delta narrative. The Tender baseline has
                already been confirmed: anchor it in at most one short clause, then express only
                one later confirmed distinction, correction, boundary/responsibility, or explicit
                lack of change and show what it changes in the understanding of reality. Do not
                replay each stage, quote tracking as a list, include several lessons, or include a
                concrete practice.

                \(narrativeContract)
                """
            }
            return """
            \(shared) For suggestPractice, present the single strongest structured practiceOption,
            preserving its instruction and rationale. Its stated kind must match what the action
            actually does. Ask the person to accept it, request a modification, say it does not fit,
            or postpone. Do not ask
            them to invent an action. Use noAction only when the validated plan carries its typed
            exception reason; never present it as a convenient default.
            """
        case .optionalAction:
            return """
            \(shared) Present the single strongest structured practiceOption with a usable
            instruction and brief grounded reason. If the
            person requested a revision, show the
            revised option rather than replaying the narrative. If this validated plan uses
            noAction, state that bounded outcome without inventing a task and preserve the typed
            reason. Ask whether it fits, what should be adjusted, or whether
            they want to postpone; do not recap the whole conversation.
            """
        case .complete:
            return "\(shared) Keep the completion acknowledgement brief."
        case .safetySupport:
            return "\(shared) Prioritize immediate safety language."
        }
    }
}

struct TurnPlannerDecodingDiagnostic: Equatable, Sendable {
    let kind: String
    let keyPath: String
    let invalidTrackingRelevance: String?
    let invalidReplyIntent: String?
    let invalidConfirmationTarget: String?
    let invalidNextPromptKind: String?
    let invalidConfirmationDecision: String?
    let invalidPracticeKind: String?
    let invalidNoActionReason: String?

    init(
        kind: String,
        keyPath: String,
        invalidTrackingRelevance: String? = nil,
        invalidReplyIntent: String? = nil,
        invalidConfirmationTarget: String? = nil,
        invalidNextPromptKind: String? = nil,
        invalidConfirmationDecision: String? = nil,
        invalidPracticeKind: String? = nil,
        invalidNoActionReason: String? = nil
    ) {
        self.kind = kind
        self.keyPath = keyPath
        self.invalidTrackingRelevance = invalidTrackingRelevance
        self.invalidReplyIntent = invalidReplyIntent
        self.invalidConfirmationTarget = invalidConfirmationTarget
        self.invalidNextPromptKind = invalidNextPromptKind
        self.invalidConfirmationDecision = invalidConfirmationDecision
        self.invalidPracticeKind = invalidPracticeKind
        self.invalidNoActionReason = invalidNoActionReason
    }

    static func make(error: Error, content: String) -> TurnPlannerDecodingDiagnostic {
        let kind: String
        let codingPath: [any CodingKey]
        switch error {
        case DecodingError.typeMismatch(_, let context):
            kind = "type_mismatch"
            codingPath = context.codingPath
        case DecodingError.valueNotFound(_, let context):
            kind = "value_not_found"
            codingPath = context.codingPath
        case DecodingError.keyNotFound(let key, let context):
            kind = "key_not_found"
            codingPath = context.codingPath + [key]
        case DecodingError.dataCorrupted(let context):
            kind = "data_corrupted"
            codingPath = context.codingPath
        default:
            kind = "unknown"
            codingPath = []
        }

        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return TurnPlannerDecodingDiagnostic(
            kind: kind,
            keyPath: path.isEmpty ? "root" : String(path.prefix(180)),
            invalidTrackingRelevance: invalidTrackingRelevance(in: content),
            invalidReplyIntent: invalidReplyIntent(in: content),
            invalidConfirmationTarget: invalidConfirmationTarget(in: content),
            invalidNextPromptKind: invalidNextPromptKind(in: content),
            invalidConfirmationDecision: invalidConfirmationDecision(in: content),
            invalidPracticeKind: invalidPracticeKind(in: content),
            invalidNoActionReason: invalidNoActionReason(in: content)
        )
    }

    private static func invalidTrackingRelevance(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memory = root["memoryUpdate"] as? [String: Any],
              let assessments = memory["trackingAssessments"] as? [[String: Any]] else {
            return nil
        }
        let allowed = Set(["related", "partlyRelated", "unrelated", "uncertain"])
        guard let raw = assessments
            .compactMap({ $0["relevance"] as? String })
            .first(where: { !allowed.contains($0) }) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidReplyIntent(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["replyIntent"] as? String,
              !Set(TurnReplyIntent.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidConfirmationTarget(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = (
                  (root["resolvedConfirmation"] as? [String: Any])?["target"]
                  ?? (root["nextPrompt"] as? [String: Any])?["target"]
                  ?? (root["memoryUpdate"] as? [String: Any])?["pendingConfirmationTarget"]
              ) as? String,
              !Set(TurnConfirmationTarget.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidNextPromptKind(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nextPrompt = root["nextPrompt"] as? [String: Any],
              let raw = nextPrompt["kind"] as? String,
              !Set(TurnNextPromptKind.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidConfirmationDecision(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resolved = root["resolvedConfirmation"] as? [String: Any],
              let raw = resolved["decision"] as? String,
              !Set(TurnConfirmationDecision.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidPracticeKind(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memory = root["memoryUpdate"] as? [String: Any],
              let raw = memory["practiceKind"] as? String,
              !Set(TurnPracticeKind.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func invalidNoActionReason(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["noActionReason"] as? String,
              !Set(TurnNoActionReason.allCases.map(\.rawValue)).contains(raw) else {
            return nil
        }
        return safeEnumValue(raw)
    }

    private static func safeEnumValue(_ raw: String) -> String {
        let safeASCII = raw.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
        return safeASCII ? String(raw.prefix(40)) : "non_contract_value"
    }
}

enum LLMTurnControllerClientError: Error {
    case plannerDecoding(TurnPlannerDecodingDiagnostic)
}

enum LLMTurnCriticVerdict: String, Codable, Sendable {
    case pass
    case reviseWriter
}

enum LLMTurnPlanCriticVerdict: String, Codable, Sendable {
    case pass
    case revisePlanner
}

struct LLMTurnPlanCriticResponse: Codable, Equatable, Sendable {
    let verdict: LLMTurnPlanCriticVerdict
    let reasonCodes: [String]
    let revisionGuidance: String?
}

struct LLMTurnCriticResponse: Codable, Equatable, Sendable {
    let verdict: LLMTurnCriticVerdict
    let reasonCodes: [String]
    let revisionGuidance: String?
}

struct RemoteLLMTurnPlanner: LLMTurnPlanning {
    private let prompts: any LLMTurnPlanningPromptBuilding
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "TurnController")

    init(prompts: any LLMTurnPlanningPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func planTurn(_ request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        let prompt = prompts.turnPlanningPrompt(request: request)
        let content = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 1_600,
            temperature: 0.28,
            // This typed planner replaces the obsolete fine-grained workflow planner. The
            // separate TurnWriter below cannot change its protocol decision.
            agentMode: "fast"
        )
        guard let data = content.data(using: .utf8) else { throw LLMError.malformedResponse }
        do {
            return try JSONDecoder().decode(LLMTurnResponsePlan.self, from: data)
        } catch {
            let diagnostic = TurnPlannerDecodingDiagnostic.make(
                error: error,
                content: content
            )
            let invalidRelevance = diagnostic.invalidTrackingRelevance ?? "none"
            let invalidIntent = diagnostic.invalidReplyIntent ?? "none"
            let invalidConfirmation = diagnostic.invalidConfirmationTarget ?? "none"
            let invalidPromptKind = diagnostic.invalidNextPromptKind ?? "none"
            let invalidDecision = diagnostic.invalidConfirmationDecision ?? "none"
            let invalidPractice = diagnostic.invalidPracticeKind ?? "none"
            let invalidNoActionReason = diagnostic.invalidNoActionReason ?? "none"
            logger.error(
                "TurnPlanner JSON invalid kind=\(diagnostic.kind, privacy: .public) key_path=\(diagnostic.keyPath, privacy: .public) invalid_tracking_relevance=\(invalidRelevance, privacy: .public) invalid_reply_intent=\(invalidIntent, privacy: .public) invalid_confirmation_target=\(invalidConfirmation, privacy: .public) invalid_next_prompt_kind=\(invalidPromptKind, privacy: .public) invalid_confirmation_decision=\(invalidDecision, privacy: .public) invalid_practice_kind=\(invalidPractice, privacy: .public) invalid_no_action_reason=\(invalidNoActionReason, privacy: .public)"
            )
            throw LLMTurnControllerClientError.plannerDecoding(diagnostic)
        }
    }
}

struct RemoteLLMTurnWriter: LLMTurnWriting {
    private let prompts: any LLMTurnWritingPromptBuilding
    private let logger = Logger(subsystem: "com.wj.BeyondComfort", category: "TurnWriter")

    init(prompts: any LLMTurnWritingPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func writeTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        let prompt = prompts.turnWritingPrompt(request: request, plan: plan)
        let content = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 700,
            temperature: 0.42,
            agentMode: "fast"
        )
        guard let data = content.data(using: .utf8) else { throw LLMError.malformedResponse }
        do {
            return try JSONDecoder().decode(LLMTurnWriterResponse.self, from: data)
        } catch {
            logger.error(
                "TurnWriter JSON invalid. Error type: \(String(describing: type(of: error)), privacy: .public)"
            )
            throw LLMError.malformedResponse
        }
    }

    func reviseTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse,
        critique: LLMTurnCriticResponse
    ) async throws -> LLMTurnWriterResponse {
        guard let criticPrompts = prompts as? any LLMTurnCriticPromptBuilding else {
            throw LLMError.malformedResponse
        }
        let prompt = criticPrompts.turnWriterRevisionPrompt(
            request: request,
            plan: plan,
            draft: draft,
            critique: critique
        )
        let content = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 700,
            temperature: 0.32,
            agentMode: "fast"
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnWriterResponse.self,
                  from: data
              ) else {
            logger.error("TurnWriter revision JSON invalid")
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteLLMTurnPlanCritic: LLMTurnPlanCritiquing {
    private let prompts: any LLMTurnCriticPromptBuilding

    init(prompts: any LLMTurnCriticPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func critiquePlan(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan
    ) async throws -> LLMTurnPlanCriticResponse {
        let prompt = prompts.turnPlanCriticPrompt(request: request, plan: plan)
        let content = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 320,
            temperature: 0.0,
            agentMode: "fast"
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnPlanCriticResponse.self,
                  from: data
              ) else {
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteLLMTurnCritic: LLMTurnCritiquing {
    private let prompts: any LLMTurnCriticPromptBuilding

    init(prompts: any LLMTurnCriticPromptBuilding = ReflectionPromptFactory()) {
        self.prompts = prompts
    }

    func critiqueTurn(
        request: LLMTurnControllerRequest,
        plan: LLMTurnResponsePlan,
        draft: LLMTurnWriterResponse
    ) async throws -> LLMTurnCriticResponse {
        let prompt = prompts.turnCriticPrompt(
            request: request,
            plan: plan,
            draft: draft
        )
        let content = try await RemoteAPIService.shared.completeJSON(
            system: prompt.system,
            user: prompt.user,
            maxTokens: 320,
            temperature: 0.0,
            agentMode: "fast"
        )
        guard let data = content.data(using: .utf8),
              let response = try? JSONDecoder().decode(
                  LLMTurnCriticResponse.self,
                  from: data
              ) else {
            throw LLMError.malformedResponse
        }
        return response
    }
}

struct RemoteReflectionTurnController: ReflectionTurnControlling {
    private let planner: any LLMTurnPlanning
    private let planCritic: any LLMTurnPlanCritiquing
    private let writer: any LLMTurnWriting
    private let critic: any LLMTurnCritiquing
    private let protocolController = ReflectionProtocolController()
    private let logger = Logger(
        subsystem: "com.wj.BeyondComfort",
        category: "TurnController"
    )

    init(
        planner: any LLMTurnPlanning = RemoteLLMTurnPlanner(),
        planCritic: any LLMTurnPlanCritiquing = RemoteLLMTurnPlanCritic(),
        writer: any LLMTurnWriting = RemoteLLMTurnWriter(),
        critic: any LLMTurnCritiquing = RemoteLLMTurnCritic()
    ) {
        self.planner = planner
        self.planCritic = planCritic
        self.writer = writer
        self.critic = critic
    }

    func plan(to request: LLMTurnControllerRequest) async throws -> LLMTurnResponsePlan {
        let initial = normalizeApplicationEventPlan(
            try await planner.planTurn(request),
            request: request
        )
        guard requiresSemanticPlanCritic(initial, request: request) else {
            return initial
        }

        // Semantic progression remains LLM-owned. Swift only invokes one bounded plan audit and
        // carries its content-free correction back to the Planner; it does not decide whether the
        // user's answer is emotionally complete or which topic should come next.
        do {
            let firstCritique = try await planCritic.critiquePlan(
                request: request,
                plan: initial
            )
            guard firstCritique.verdict == .revisePlanner else {
                return initial
            }
            let revisedRequest = requestWithPlanCorrection(
                request,
                critique: firstCritique
            )
            let revised = normalizeApplicationEventPlan(
                try await planner.planTurn(revisedRequest),
                request: request
            )
            let finalCritique = try await planCritic.critiquePlan(
                request: request,
                plan: revised
            )
            if finalCritique.verdict != .pass {
                logger.warning(
                    "turn_planner_semantic_quality_unresolved reason_count=\(finalCritique.reasonCodes.count, privacy: .public)"
                )
            }
            return revised
        } catch {
            logger.warning("turn_planner_semantic_critic_unavailable")
            return initial
        }
    }

    /// Card display and guidance availability are application events. They carry the previous
    /// user turn for conversational context, but that turn's confirmation was already consumed by
    /// the local action that produced this event. Removing an echoed resolution is protocol
    /// normalization, not semantic interpretation, and prevents a stale “好/贴切” from being
    /// applied twice.
    private func normalizeApplicationEventPlan(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> LLMTurnResponsePlan {
        guard [.cardDisplayed, .cardGuidanceAvailable, .protocolContinuation]
                .contains(request.trigger),
              plan.resolvedConfirmation != nil else {
            return plan
        }
        return LLMTurnResponsePlan(
            requestedStage: plan.requestedStage,
            localAction: plan.localAction,
            memoryUpdate: plan.memoryUpdate,
            resolvedConfirmation: nil,
            nextPrompt: plan.nextPrompt,
            replyIntent: plan.replyIntent,
            noActionReason: plan.noActionReason,
            replyGuidance: plan.replyGuidance
        )
    }

    private func requiresSemanticPlanCritic(
        _ plan: LLMTurnResponsePlan,
        request: LLMTurnControllerRequest
    ) -> Bool {
        switch request.protocolStage {
        case .contextualDisclosure:
            if [.presentTrackingContext, .integrateTrackingAndPresentTenderSummary,
                .presentTenderSummary].contains(plan.replyIntent) {
                return true
            }
            return [.exploreContext, .checkTrackingRelationship].contains(plan.replyIntent)
                && request.semanticMemory.answeredQuestionPurposes.count >= 2
        case .cardReflection:
            return [
                .developCardImage,
                .inviteCardConnection,
                .authorizeCardGuidance,
                .presentCardReading,
                .directCandidReflection,
                .presentFinalNarrative,
            ].contains(plan.replyIntent)
        case .directReflection:
            return [.directCandidReflection, .presentFinalNarrative].contains(plan.replyIntent)
                && request.semanticMemory.tenderUnderstanding?.isEmpty == false
        case .narrativeConfirmation:
            return plan.replyIntent == .completeConversation
                || plan.replyIntent == .suggestPractice
        case .optionalAction:
            return [.suggestPractice, .revisePractice, .completeConversation]
                .contains(plan.replyIntent)
        default:
            return false
        }
    }

    private func requestWithPlanCorrection(
        _ request: LLMTurnControllerRequest,
        critique: LLMTurnPlanCriticResponse
    ) -> LLMTurnControllerRequest {
        let reasons = critique.reasonCodes
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .joined(separator: ",")
        let guidance = critique.revisionGuidance?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240) ?? ""
        let correction = """
        Semantic plan audit requested one bounded revision.
        reasonCodes=\(reasons.isEmpty ? "semantic_progression" : reasons)
        revisionGuidance=\(guidance.isEmpty ? "Remove the duplicated function or use an allowed Tender summary when ready." : String(guidance))
        Preserve permissions, confirmed relationships, tracking dispositions, and the latest answer.
        """
        return LLMTurnControllerRequest(
            trigger: .protocolCorrection,
            protocolStage: request.protocolStage,
            condition: request.condition,
            permissions: request.permissions,
            recentMessages: request.recentMessages,
            semanticMemory: request.semanticMemory,
            trackingCandidates: request.trackingCandidates,
            contextualLoadCue: request.contextualLoadCue,
            presentedTrackingCues: request.presentedTrackingCues,
            activeTrackingPresentation: request.activeTrackingPresentation,
            card: request.card,
            protocolCorrection: correction
        )
    }

    func write(
        request: LLMTurnControllerRequest,
        validatedPlan: LLMTurnResponsePlan
    ) async throws -> LLMTurnWriterResponse {
        var draft = try await writer.writeTurn(
            request: request,
            plan: validatedPlan
        )

        // Natural-language conformance is a soft Writer concern. Keep the Planner decision
        // fixed, ask the Writer to polish it once, and never re-plan the conversation merely
        // because punctuation or wording did not perfectly mirror `nextPrompt`.
        let qualityIssues = protocolController.writerQualityIssues(
            draft,
            for: validatedPlan
        )
        if !qualityIssues.isEmpty {
            let critique = LLMTurnCriticResponse(
                verdict: .reviseWriter,
                reasonCodes: qualityIssues.map(\.rawValue),
                revisionGuidance: softWriterRevisionGuidance(
                    issues: qualityIssues,
                    plan: validatedPlan
                )
            )
            do {
                draft = try await writer.reviseTurn(
                    request: request,
                    plan: validatedPlan,
                    draft: draft,
                    critique: critique
                )
            } catch {
                logger.warning(
                    "turn_writer_soft_revision_unavailable issue_count=\(qualityIssues.count, privacy: .public)"
                )
            }
        }

        guard requiresSemanticCritic(validatedPlan.replyIntent, request: request) else {
            return draft
        }

        // The Critic is an advisory quality pass, not a second workflow controller. If it is
        // unavailable, or still recommends polishing after one revision, keep the legal
        // Planner turn instead of converting a semantic quality concern into a protocol failure.
        var semanticCandidate = draft
        do {
            let firstCritique = try await critic.critiqueTurn(
                request: request,
                plan: validatedPlan,
                draft: draft
            )
            guard firstCritique.verdict == .reviseWriter else {
                return draft
            }
            let revised = try await writer.reviseTurn(
                request: request,
                plan: validatedPlan,
                draft: draft,
                critique: firstCritique
            )
            semanticCandidate = revised
            let finalCritique = try await critic.critiqueTurn(
                request: request,
                plan: validatedPlan,
                draft: revised
            )
            if finalCritique.verdict != .pass {
                logger.warning(
                    "turn_writer_semantic_quality_unresolved reason_count=\(finalCritique.reasonCodes.count, privacy: .public)"
                )
            }
            return revised
        } catch {
            logger.warning("turn_writer_semantic_critic_unavailable")
            return semanticCandidate
        }
    }

    private func softWriterRevisionGuidance(
        issues: [TurnWriterQualityIssue],
        plan: LLMTurnResponsePlan
    ) -> String {
        var guidance: [String] = [
            "Keep the validated Planner meaning, stage, and replyIntent unchanged.",
            "Revise only the visible Chinese wording.",
        ]
        if issues.contains(.realizedIntentMismatch) {
            guidance.append(
                "Return realizedIntent exactly \(plan.replyIntent.rawValue) and remove any later-stage function."
            )
        }
        if issues.contains(.expectedSingleQuestion) {
            guidance.append(
                "Express one natural primary question. Avoid stacked questions; punctuation is a wording preference, not a new semantic purpose."
            )
        }
        if issues.contains(.expectedNoQuestion) {
            guidance.append(
                "This turn establishes no next question. Rewrite it as a brief acknowledgement without asking anything."
            )
        }
        return guidance.joined(separator: " ")
    }

    private func requiresSemanticCritic(
        _ intent: TurnReplyIntent,
        request: LLMTurnControllerRequest
    ) -> Bool {
        switch intent {
        case .exploreContext, .checkTrackingRelationship:
            return request.semanticMemory.answeredQuestionPurposes.count >= 2
        case .directCandidReflection,
             .presentTrackingContext,
             .integrateTrackingAndPresentTenderSummary,
             .presentTenderSummary,
             .requestTenderConfirmation,
             .reviseTenderSummary,
             .presentCardReading,
             .presentFinalNarrative,
             .requestNarrativeConfirmation,
             .reviseFinalNarrative,
             .suggestPractice,
             .revisePractice:
            return true
        default:
            return false
        }
    }
}
