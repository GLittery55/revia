from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Literal

from fastapi import HTTPException

from .schemas import LLMChatIn, LLMTurnPromptIn


TURN_PROMPT_VERSION = "turn-v4-server-v45"
CURRENT_V5_CORE_PROMPT_VERSION = "turn-v5-core-server-v5"
TurnPromptTask = Literal[
    "planner",
    "plan_critic",
    "writer",
    "writer_critic",
    "writer_revision",
]


# Single server-side registry for the current Planner's closed semantic choice. Prompt text,
# repair instructions, fixtures, and contract tests consume this source rather than copying it.
PLANNER_SEMANTIC_OPERATION_VALUES: tuple[str, ...] = (
    "clarifyEvent",
    "advanceToCardConsent",
    "inviteCardConsent",
    "acknowledgeCardConsent",
    "declineCardConsent",
    "continueCardObservation",
    "continueCardDevelopment",
    "inviteRealityConnection",
    "continueOpenCardConnection",
    "offerCardConnectionScaffold",
    "offerCardConnectionCandidate",
    "establishUserAuthoredCardConnection",
    "acceptCardConnectionCandidate",
    "reviseCardConnectionCandidate",
    "rejectCardConnectionCandidate",
    "bypassCardConnectionToDirectReflection",
    "authorizeCardGuidance",
    "presentLegacyCardReading",
    "continueTenderReflection",
    "continueTenderGroundedFierceReflection",
    "synthesizeDirectReflection",
    "proposePractice",
    "resolvePractice",
    "confirmNarrative",
    "reviseNarrative",
    "completeConversation",
    "provideSafetySupport",
)

PLANNER_SEMANTIC_OPERATION_SCHEMA = {
    "type": "string",
    "enum": PLANNER_SEMANTIC_OPERATION_VALUES,
}

PLANNER_SEMANTIC_OPERATION_CONTRACT = (
    "semanticOperation required; choose exactly one permissions.allowedSemanticOperations value; "
    "legacy fields never choose/replace it."
)


def validate_planner_semantic_operation(
    plan: dict[str, Any], *, protocol_version: int, normal_turn: bool
) -> str | None:
    """Validate the server contract without inferring from legacy structural fields."""
    value = plan.get("semanticOperation")
    if protocol_version >= 5:
        if not isinstance(value, str) or not value:
            raise ValueError("missingSemanticOperation")
        if value not in PLANNER_SEMANTIC_OPERATION_VALUES:
            raise ValueError("unknownSemanticOperation")
        return value
    if value is None:
        return None
    if not isinstance(value, str) or value not in PLANNER_SEMANTIC_OPERATION_VALUES:
        raise ValueError("unknownSemanticOperation")
    return value


@dataclass(frozen=True)
class PromptMessages:
    system: str
    user: str
    metrics: "PromptLengthMetrics | None" = None


@dataclass(frozen=True)
class PromptLengthMetrics:
    component: str
    stage: str
    protocol_version: int
    substate: str
    shared_characters: int
    stage_characters: int
    substate_characters: int
    dynamic_state_characters: int
    schema_characters: int
    conversation_characters: int
    recovery_characters: int
    provider_format_characters: int
    total_characters: int
    estimated_tokens: int


logger = logging.getLogger("uvicorn.error")


def _encoded(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _pending_confirmation(request: dict[str, Any]) -> bool:
    memory = request.get("semanticMemory")
    prompt = memory.get("nextPrompt") if isinstance(memory, dict) else None
    return isinstance(prompt, dict) and prompt.get("kind") == "confirmationRequest"


def _card_substate(request: dict[str, Any]) -> str:
    if request.get("protocolStage") != "cardReflection":
        return "none"
    card = request.get("card")
    if not isinstance(card, dict):
        return "observation"
    if request.get("trigger") == "cardDisplayed":
        return "observation"
    if card.get("reflectionApproaches") is not None or request.get("cardMappingConfirmed") is True:
        return "guidance"
    if card.get("connectionInteractionState") == "awaitingCandidateResolution":
        return "awaitingCandidateResolution"
    if (
        int(card.get("connectionAttemptCount") or 0) > 0
        or card.get("connectionScaffoldUsed") is True
        or int(card.get("imageDevelopmentTurnCount") or 0) > 1
    ):
        return "openExploration"
    if int(card.get("imageDevelopmentTurnCount") or 0) == 0:
        return "development"
    return "openExploration"


def _is_card_guidance_reflection_entry(request: dict[str, Any]) -> bool:
    if request.get("protocolStage") != "directReflection":
        return False
    card = request.get("card")
    if not isinstance(card, dict) or card.get("reflectionApproaches") is None:
        return False
    if request.get("trigger") == "cardGuidanceAvailable":
        return True
    memory = request.get("semanticMemory")
    return bool(request.get("protocolCorrection")) and (
        not isinstance(memory, dict) or memory.get("reflectionFrame") is None
    )


def _prompt_messages(
    *,
    component: str,
    request: dict[str, Any],
    system: str,
    user: str,
    stage_contract: str = "",
    substate_contract: str = "",
    schema_contract: str = "",
    recovery_contract: str = "",
) -> PromptMessages:
    conversation = _encoded(request.get("recentMessages", []))
    conversation_characters = len(conversation) if conversation in user else 0
    correction = request.get("protocolCorrection")
    encoded_correction = _encoded(correction) if correction is not None else ""
    recovery_payload_characters = (
        len(encoded_correction) if encoded_correction and encoded_correction in user else 0
    )
    stage_characters = len(stage_contract)
    substate_characters = len(substate_contract)
    schema_characters = len(schema_contract)
    recovery_characters = len(recovery_contract) + recovery_payload_characters
    dynamic_state_characters = max(
        0,
        len(user) - conversation_characters - recovery_payload_characters,
    )
    shared_characters = max(
        0,
        len(system)
        - stage_characters
        - substate_characters
        - schema_characters
        - len(recovery_contract),
    )
    total_characters = len(system) + len(user)
    metrics = PromptLengthMetrics(
        component=component,
        stage=str(request.get("protocolStage", "unknown")),
        protocol_version=int(request.get("protocolVersion") or 0),
        substate=_card_substate(request),
        shared_characters=shared_characters,
        stage_characters=stage_characters,
        substate_characters=substate_characters,
        dynamic_state_characters=dynamic_state_characters,
        schema_characters=schema_characters,
        conversation_characters=conversation_characters,
        recovery_characters=recovery_characters,
        provider_format_characters=0,
        total_characters=total_characters,
        estimated_tokens=(total_characters + 3) // 4,
    )
    return PromptMessages(system=system, user=user, metrics=metrics)


def log_prompt_length(metrics: PromptLengthMetrics) -> None:
    logger.info(
        "turn_prompt_length component=%s stage=%s protocol_version=%s substate=%s "
        "shared_characters=%s stage_characters=%s substate_characters=%s "
        "dynamic_state_characters=%s schema_characters=%s conversation_characters=%s "
        "recovery_characters=%s provider_format_characters=%s total_characters=%s "
        "estimated_tokens=%s estimate=characters_div_4",
        metrics.component,
        metrics.stage,
        metrics.protocol_version,
        metrics.substate,
        metrics.shared_characters,
        metrics.stage_characters,
        metrics.substate_characters,
        metrics.dynamic_state_characters,
        metrics.schema_characters,
        metrics.conversation_characters,
        metrics.recovery_characters,
        metrics.provider_format_characters,
        metrics.total_characters,
        metrics.estimated_tokens,
    )


def _required_object(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict):
        raise HTTPException(422, f"turn prompt payload requires object field: {key}")
    return value


def _permissions_text(request: dict[str, Any]) -> str:
    permissions = request.get("permissions")
    if not isinstance(permissions, dict):
        raise HTTPException(422, "turn request requires permissions")
    catalogues = {
        "requestedStage": permissions.get("allowedStages", []),
        "localAction.kind": permissions.get("allowedActions", []),
        "replyIntent": permissions.get("allowedReplyIntents", []),
        "disclosurePurpose": permissions.get("allowedDisclosurePurposes", []),
        "disclosureTarget": permissions.get("allowedDisclosureTargets", []),
    }
    if int(request.get("protocolVersion") or 0) >= 5:
        if request.get("trigger") == "protocolCorrection":
            # Recovery receives the same closed semantic capability set, but none of the legacy
            # tuple catalogues can affect execution. Omitting those diagnostic-only catalogues
            # keeps the repair request compact and avoids suggesting a second authority.
            return (
                "ALLOWED SEMANTIC OPERATIONS (authoritative; choose one exact value):\n"
                f"{_encoded(permissions.get('allowedSemanticOperations', []))}"
            )
        return (
            "ALLOWED SEMANTIC OPERATIONS (authoritative; choose one exact value):\n"
            f"{_encoded(permissions.get('allowedSemanticOperations', []))}\n"
            "LEGACY STRUCTURAL FIELDS (diagnostic compatibility only; never choose operation):\n"
            f"{_encoded(permissions.get('allowedOperations', []))}\n"
            "ENUM CATALOGUES (diagnostic only):\n"
            f"{_encoded(catalogues)}"
        )
    return (
        "ALLOWED LEGACY OPERATIONS (authoritative for legacy execution):\n"
        f"{_encoded(permissions.get('allowedOperations', []))}\n"
        "ENUM CATALOGUES (diagnostic only; not a Cartesian product):\n"
        f"{_encoded(catalogues)}"
    )


def _condition_contract(request: dict[str, Any]) -> str:
    if request.get("condition") == "cardMediated":
        confirmed = "true" if request.get("cardMappingConfirmed") is True else "false"
        if request.get("protocolStage") in {
            "directReflection",
            "narrativeConfirmation",
            "optionalAction",
            "complete",
        }:
            return (
                f"cardMediated; cardMappingConfirmed={confirmed}. Later synthesis may use only a "
                "confirmed user-accepted/revised mapping and preserves rejection or uncertainty."
            )
        return (
            f"cardMediated; cardMappingConfirmed={confirmed}. Unconfirmed assistant card material is "
            "not user evidence."
        )
    return (
        "modelAsserted. Never mention cards or images. Use only distinctions established through "
        "direct reflection and preserve their absence or uncertainty."
    )


# Shared prompt prose is advisory only. Typed state, AppModels, structured output, Swift
# capabilities, and persisted memory remain the protocol truth sources.
GLOBAL_PROTOCOL_INVARIANTS = """
Capability: choose one complete operation from CURRENT PERMISSIONS. Do not recombine enum catalogues,
advance workflow, select a card, or perform another local action; Swift owns and validates those
mechanics. Progress: interpret the latest answer, commit every supported relation, and either add
material understanding or make one legal transition. Do not repeat an answered function, revive
rejected material, fill optional slots, or collect low-value detail.
""".strip()


GROUNDING_RULES = """
Grounding: use only the person's words and confirmed persisted evidence. Keep reported fact,
behavior/non-action, impact, present experience, future prediction, possible contributor,
constraint, agency, and unknown information distinct. A card, tracking cue, external result, or
assistant hypothesis cannot establish a personal fact, cause, motive, feeling, trait, diagnosis,
responsibility, need, capacity, or excuse. Preserve corrections, refusal, and uncertainty.
Contextual data keeps its measured/user-authored scope; never turn it into an unreported schedule,
bodily state, emotion, motive, diagnosis, causal explanation, or relief response. Only a user-confirmed
related/partlyRelated interpretation may enter later synthesis; silence means offered, not confirmed.
""".strip()


CONFIRMATION_RULES = """
Confirmation: resolvedConfirmation only resolves the matching confirmationRequest visible before
this user turn and copies its target/referenceID. It never means an object formed, an openQuestion
was answered, or the workflow may advance. nextPrompt is only the interaction created by the new
visible reply. Without a matching pending target, resolvedConfirmation is null.
""".strip()


CARD_EVIDENCE_RULES = """
Card evidence: the person interprets the visible image first. Use only visual elements and relations
they supplied; internal references are closed, question-only lenses, never card meaning or the
person's answer. Before a confirmed Card Reality Connection, keep every comparison inside
request.card.realityAnchor and infer no psychology or responsibility. Rejected or superseded card
material cannot return.
""".strip()

CARD_TYPED_EVIDENCE_CONTRACT = """
Typed card evidence: cardObservationEvidence saves user-described visible elements as
{"userDescribedElements":["element or action","..."]}. cardDevelopmentEvidence saves a
development relation as {"actorsOrElements":[""],"relationOrAction":null,"anticipatedChangeOrChoice":null}
with at least one non-empty field when present. Both are null until the person supplies that
content. candidateBridgeResolvedAt is always null—Swift sets it internally.
""".strip()


SELF_COMPASSION_RULES = """
Tender grounds every reflection by reducing whole-person attack and distinguishing fact, experience,
prediction, inference, and unknown without praise, excuse, or denial. Common Humanity may support but
never replace a concrete distinction. Fierce optionally adds Tender-grounded candor only for existing
related behavior, impact, readiness, and a caring repair/protect/change basis. Self-criticism judges
ability/character/worth; worry predicts; uncertainty marks missing information. None alone is Fierce evidence.
""".strip()


OUTPUT_DISCIPLINE = """
Output discipline: return exactly the requested JSON object and nothing else. Preserve enum and field
spelling. null leaves memory unchanged; a patch contains only newly supported or explicitly corrected
values. Empty arrays do not clear or reopen established evidence.
""".strip()


WRITER_STYLE = """
Write one concise, natural Chinese response to “你” that realizes only the validated plan. Do not
expose labels/fields, replay the episode, mechanically seek approval, or repeat generic acknowledgements.
Continue the newest concrete meaning. Ask one easy content question exactly when required; otherwise
none. Add no fact, explanation, responsibility, action, or function. No generic reassurance, praise,
normalization, minimization, excuse, or unsupported negation. Realize reflectionFrame without naming
its theory or dimensions. A protective purpose needs user evidence and tentative wording; it never
erases or excuses supported impact.
""".strip()


RECOVERY_DISCIPLINE = """
Recovery: choose exactly one permissions.allowedSemanticOperations value and rebuild one grounded
semantic patch from the last committed typed state plus the latest user turn. protocolCorrection is
diagnosis only: do not repeat the rejected operation when it remains illegal, and copy none of its
uncommitted patch. Do not repair stage, intent, action, prompt, confirmation, outcome, or transition;
Swift projects those fields. Return one complete standalone plan and preserve the latest answer.
""".strip()


RECOVERY_OPERATION_CONTRACTS: dict[str, str] = {
    "eventDisclosure": (
        "Event recovery: consume the latest answer once. Either ask one still-needed permitted "
        "event/process/behavior question, or atomically complete the episode bridge and card invitation."
    ),
    "cardConsent": (
        "Card-consent recovery: resolve only the pending consent interaction or answer its immediate "
        "question; card selection remains local and no card content may be invented."
    ),
    "cardOpenExploration": (
        "Open-card recovery: continue only the permitted observation/development/current-event "
        "connection operation; do not import guidance or a fixed card meaning."
    ),
    "cardCandidateResolution": (
        "Candidate recovery: resolve the persisted candidate interaction from the latest answer; "
        "do not create a second candidate or reuse rejected content."
    ),
    "legacyCardReading": (
        "Legacy v4 recovery: preserve the negotiated reading path and its pending cardMapping "
        "confirmation; do not use the v5 direct-guidance transition."
    ),
    "currentCardGuidance": (
        "Current v5 recovery: the canonical connection is committed. Move through authorized "
        "guidance into Direct Reflection; do not recreate a reading or cardMapping confirmation."
    ),
    "directReflection": (
        "Direct-reflection recovery: produce one permitted grounded reflection delta or question "
        "from committed evidence; do not jump to action or reopen the card connection."
    ),
    "directSynthesis": (
        "Synthesis recovery: atomically produce the complete grounded synthesis operation required "
        "by current permissions; do not add another exploration question."
    ),
    "optionalAction": (
        "Optional-action recovery: resolve or create only the canonical single action transaction "
        "allowed by current state; never manufacture noAction merely because a prior plan failed."
    ),
    "finalNarrative": (
        "Final-narrative recovery: resolve or present the one canonical narrative transaction and "
        "its complete permitted successor atomically; do not pre-commit either half."
    ),
    "complete": "Completion recovery: acknowledge only the already-complete state.",
    "safety": "Safety recovery: remain in immediate safety support and do not resume reflection.",
}


def _recovery_contract(request: dict[str, Any]) -> str:
    if not request.get("protocolCorrection"):
        return ""
    operation = str(request.get("recoveryOperation") or "")
    operation_contract = RECOVERY_OPERATION_CONTRACTS.get(
        operation,
        "Use only the current typed operation and capability set; do not infer a replacement operation from the rejected plan.",
    )
    return f"{RECOVERY_DISCIPLINE}\n{operation_contract}"


DISCLOSURE_MEMORY_CONTRACT = """
Patch the cumulative episodeStructure. concreteFacts identify the event; eventProcess records how it
developed without claiming cause; behaviorEvidence records explicit action/non-action and is non-empty
when its status is present. Grounded content and status are one truth: non-empty behavior/process/impact
evidence requires present or mixed, and present/mixed requires content. Use uncertain only when the
relation is genuinely unavailable, never as omission beside supplied evidence. One answer may support
several relations. Optional impact, constraint, contributor, agency, emotion, or self-criticism material
is saved only when volunteered and never delays completion.
""".strip()


DIRECT_REFLECTION_MEMORY_CONTRACT = """
Save one complete grounded reflectionFrame with a legal action and non-recap delta. Preserve and
address an explicit selfCriticalStatement through a fact/inference or event/whole-person distinction;
never invent one. Tender has no fierceEvidence; Fierce uses only supplied conduct, impact, and caring
direction. synthesizeUnderstanding may create one grounded action/noAction.
""".strip()


CARD_STAGE_CONTRACT = """
Goal: move only the current visible-card interaction forward. Swift owns card selection, typed
connection projection, guidance authorization, confirmation resolution, and stage transition. Use
request.card.realityAnchor as the only reality episode and current permissions as the operation set.
""".strip()


CARD_SUBSTATE_CONTRACTS: dict[str, str] = {
    "observation": (
        "Observation: invite the person to describe what is visibly happening. Refer only to elements "
        "they named; do not introduce symbols, fixed meaning, psychology, motive, responsibility, or diagnosis."
    ),
    "development": (
        "Development: ask one question about what may happen or change next. Do not prescribe one "
        "development, collect more static detail, or connect the image to reality for them. If the "
        "person independently supplied a complete image–reality mapping, commit it without confirmation."
    ),
    "openExploration": (
        "Open connection: compare one user-authored image action/relation with the current event through "
        "similarity, difference, contrast, or absence. A complete user-authored mapping commits directly "
        "without confirmation; inability returns connectionStillUnclear. Use only the currently allowed "
        "scaffold/candidate capability and do not search another life episode or infer inner meaning."
    ),
    "awaitingCandidateResolution": (
        "Candidate resolution: the persisted pending candidate is the only candidate. Substantive "
        "acceptance returns candidateAccepted; a correction returns candidateRevised with the user's "
        "complete mapping; rejection returns candidateRejected and withdraws the candidate. Do not reopen "
        "image exploration or require an approval word."
    ),
    "guidance": (
        "Guidance: a canonical connection is complete and never creates another mapping/meaning "
        "confirmation. Move directly into the permitted reflection, using the image relation and reality "
        "mapping only as a brief bridge to one new grounded distinction. Card material cannot establish "
        "personality, motive, responsibility, diagnosis, or Fierce evidence. contextualLoadCue may be "
        "offered once as non-causal background; silence is not confirmation. cardReferenceSelection is "
        "null or one jointly supported question lens within activationBoundary/prohibitedClaims."
    ),
}


LEGACY_CARD_GUIDANCE_CONTRACT = (
    "Legacy guidance only: use the confirmed connection to present the currently permitted negotiable "
    "reading in cardNegotiatedMeaning and preserve its existing cardMapping confirmation contract. "
    "Do not alter v4 ordering."
)


_PLANNING_STAGE_CONTRACTS: dict[str, str] = {
    "contextualDisclosure": (
        "Goal: establish a reality chain sufficient for card reflection: focal event, development, and "
        "relevant user action/non-action. Each turn asks at most one highest-value unanswered typed pair: "
        "identifyConcreteEpisode→focalEvent, clarifyEventProcess→eventProcess, or "
        "clarifyBehavior→behavior; do not repeat a completed function or seek low-value date/name/category "
        "detail. Behavior is clarified only when needed to understand the process and never presumes blame. "
        "External-result episodes may be complete through preparation, submission, waiting, and receipt "
        "without a known cause or omission. Set eventDisclosureOutcome every turn. Once the chain is clear, "
        "use readyForTenderOrCard and inviteCardConsent with one brief factual/Tender bridge. Emotion, impact, "
        "importance, self-judgment, motive, responsibility, and reflectionFocus are optional, never gates."
    ),
    "cardConsent": (
        "Goal: invite or resolve optional card consent. Swift selects/displays the card. Accepted "
        "pending consent returns cardConsent/accepted, acknowledgeCardConsent, drawRandomCard, "
        "requestedStage=cardConsent, nextPrompt=none; this authorization is silent. Never describe an "
        "unseen image."
    ),
    "cardReflection": CARD_STAGE_CONTRACT,
    "directReflection": (
        "Goal: choose one grounded legal reflectionFrame. Tender is every mode's basis and may stand alone; "
        "Fierce optionally adds one evidence-supported, discussable, caring behavior/impact/repair/protect/"
        "change focus without soliciting evidence. Address explicit whole-person judgment through a concrete "
        "fact/inference or event/identity distinction; keep worry and uncertainty separate. Common Humanity "
        "alone and recap are not deltas. In v5 synthesizeUnderstanding proposes one grounded action/noAction "
        "before final narrative."
    ),
    "narrativeConfirmation": (
        "Goal: resolve the visible narrative. If a pre-narrative action is already resolved, accepted/"
        "revised narrative completes. Otherwise preserve the narrative resolution and atomically create "
        "one optionalAction practiceTransition: grounded proposal, matching transaction/proposal/prompt "
        "IDs, and practice confirmation; never stay here or create none/openQuestion."
    ),
    "optionalAction": (
        "Goal: resolve one pending proposal. Acceptance confirms it unchanged; a complete user revision "
        "keeps its id, grounded basis, and source=userRevised; rejection clears it with userDeclined. If "
        "narrativeReferenceID is null, present final narrative next; an already-confirmed narrative "
        "completes. Only an unclear request for another offer may revisePractice."
    ),
    "complete": "Return one brief completion acknowledgement.",
    "safetySupport": "Stay with immediate safety support; do not resume ordinary reflection.",
}


def _planning_stage_contract(request: dict[str, Any]) -> str:
    contract = _PLANNING_STAGE_CONTRACTS.get(
        str(request.get("protocolStage", "")),
        "Remain in the supplied stage and use only current permissions.",
    )
    if _is_card_guidance_reflection_entry(request):
        return (
            contract
            + " First visible turn after canonical Card Reality Connection: combine one brief Card "
            "Guidance bridge with this reflectionFrame. The connection is not pending, so do not use "
            "presentCardReading, cardNegotiatedMeaning, cardMapping confirmation, resolvedConfirmation, "
            "or a fit check. Guidance must add a grounded distinction rather than restate the connection."
        )
    return contract


def _semantic_contract(request: dict[str, Any]) -> str:
    stage = request.get("protocolStage")
    if stage == "contextualDisclosure":
        return DISCLOSURE_MEMORY_CONTRACT
    if stage == "directReflection":
        return DIRECT_REFLECTION_MEMORY_CONTRACT
    return "Use semanticMemory as a patch; update only evidence supported by the latest answer."


def _planner_shared_contract(request: dict[str, Any]) -> str:
    # RECOVERY_DISCIPLINE already states the same current-operation/Swift-authority boundary.
    # Do not repeat GLOBAL_PROTOCOL_INVARIANTS in a correction request; the grounded evidence,
    # confirmation, card, and reflection contracts remain identical to a normal turn.
    parts = [GROUNDING_RULES]
    if request.get("trigger") != "protocolCorrection":
        parts.insert(0, GLOBAL_PROTOCOL_INVARIANTS)
    if _pending_confirmation(request) or request.get("protocolStage") in {
        "cardConsent",
        "narrativeConfirmation",
        "optionalAction",
    }:
        parts.append(CONFIRMATION_RULES)
    if request.get("protocolStage") == "cardReflection":
        parts.append(CARD_EVIDENCE_RULES)
    if request.get("protocolStage") == "directReflection":
        parts.append(SELF_COMPASSION_RULES)
    return "\n\n".join(parts)


def _planner_substate_contract(request: dict[str, Any]) -> str:
    if request.get("protocolStage") != "cardReflection":
        return ""
    substate = _card_substate(request)
    if substate == "guidance" and int(request.get("protocolVersion") or 0) < 5:
        return LEGACY_CARD_GUIDANCE_CONTRACT
    return CARD_SUBSTATE_CONTRACTS[substate]


CARD_CONNECTION_COMMON_OUTPUT = """
Swift derives raw connection projections and confirmation. Never write cardRealityConnection,
cardConnectionOutcome, either clear-card field, or a cardRealityConnection confirmation.
Retired cardImageRelation/cardRealityMapping/cardRealityMappingSource keys are forbidden.
""".strip()


CARD_CONNECTION_OUTPUT_CONTRACTS: dict[str, str] = {
    "observation": "cardConnectionTurnOutcome is null for image observation.",
    "development": (
        'cardConnectionTurnOutcome is null for image-only development, or exactly '
        '{"kind":"userAuthoredConnection","connection":{"imageRelation":"","realityMapping":"",'
        '"source":"userAuthored","status":"confirmed"}} when the latest answer independently contains '
        "that complete mapping."
    ),
    "openExploration": (
        'cardConnectionTurnOutcome is exactly {"kind":"userAuthoredConnection","connection":'
        '{"imageRelation":"","realityMapping":"","source":"userAuthored","status":"confirmed"}} '
        'or {"kind":"connectionStillUnclear","connection":null}. Connections are complete or null.'
    ),
    "awaitingCandidateResolution": (
        'cardConnectionTurnOutcome is exactly {"kind":"candidateAccepted","connection":null}, '
        '{"kind":"candidateRevised","connection":{"imageRelation":"","realityMapping":"",'
        '"source":"userRevised","status":"confirmed"}}, or '
        '{"kind":"candidateRejected","connection":null}.'
    ),
    "guidance": "cardConnectionTurnOutcome is null after guidance; the confirmed connection is immutable.",
}


PLANNER_JSON_SHAPE = """{"semanticOperation":"","requestedStage":"","localAction":{"kind":"none","trackingCueIDs":[]},"memoryUpdate":{"situationUnderstanding":null,"answeredQuestionPurposes":null,"receivedDisclosureQuestionPurposes":null,"eventDisclosureOutcome":null,"selfCriticismStatus":null,"selfCriticalStatement":null,"selfCriticismLink":null,"episodeStructure":null,"contextRelationship":null,"contextCueOffered":null,"trackingAssessments":null,"cardRealityConnection":null,"pendingCardRealityConnection":null,"clearPendingCardRealityConnection":null,"clearCardRealityConnection":null,"cardConnectionOutcome":null,"cardInterpretiveTension":null,"cardNegotiatedMeaning":null,"cardObservationEvidence":null,"cardDevelopmentEvidence":null,"candidateBridgeResolvedAt":null,"reflectionFrame":null,"finalNarrative":null,"practiceTransition":null},"cardConnectionTurnOutcome":null,"resolvedConfirmation":null,"nextPrompt":{"kind":"none","purpose":null,"focus":null,"disclosurePurpose":null,"disclosureTarget":null,"disclosureReopenReason":null,"target":null,"referenceID":null},"replyIntent":"","replyGuidance":"","cardReferenceSelection":null}"""

# The rebuilt v5 Planner cannot express workflow instructions. Swift derives stage, prompt,
# confirmation, local capabilities, and user-visible intent from the one semantic operation.
CURRENT_V5_PLANNER_JSON_SHAPE = (
    '{"semanticOperation":"","semanticEvidencePatch":{"memoryUpdate":{},'
    '"cardConnectionTurnOutcome":null},"responseFocus":""}'
)

# Stage-scoped schema for the only Event aggregate accepted by the current v5 Planner. Keeping it
# beside the compact top-level shape makes the sparse-patch contract explicit without restoring
# the retired all-stage Planner tuple.
CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE = (
    '{"episodeStructure":{"concreteFacts":["grounded focal event"],'
    '"eventProcessStatus":"present","eventProcess":["grounded development"],'
    '"behaviorEvidenceStatus":"present",'
    '"behaviorEvidence":["grounded action or omission"]}}'
)

CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE = (
    '{"cardObservationEvidence":{"userDescribedElements":["visible user-described element"]},'
    '"cardDevelopmentEvidence":{"actorsOrElements":["user-described element"],'
    '"relationOrAction":"user-described relation or action",'
    '"anticipatedChangeOrChoice":"user-described possible change or choice"}}'
)


def _planner_base_structural_contract(request: dict[str, Any]) -> str:
    parts = [
        "replyGuidance is operation-specific and may be empty only for silent drawRandomCard/shareCardGuidance."
    ]
    if request.get("protocolStage") == "cardReflection":
        parts.append('cardReferenceSelection is null or {"relationIndex":0}; never return relation text.')
    if _pending_confirmation(request) or request.get("protocolStage") in {
        "cardConsent",
        "narrativeConfirmation",
        "optionalAction",
    }:
        parts.append(
            'resolvedConfirmation is null or {"target":"trackingRelationship|cardConsent|cardMapping|'
            'finalNarrative|practice","decision":"related|partlyRelated|unrelated|uncertain|accepted|'
            'revised|rejected|unclear|declined","referenceID":null}; copy the pending referenceID.'
        )
    return "\n".join(parts)


PLANNER_REFLECTION_FRAME_CONTRACT = """
reflectionFrame={"mode":"tender|fierce","action":"acknowledgeExperience|distinguishFactFromPrediction|softenGlobalSelfJudgment|connectCommonHumanity|acknowledgeBehaviorImpact|clarifyBoundaryOrNeed|identifyRepairDirection|identifyProtectionDirection|identifyChangeDirection|synthesizeUnderstanding","evidenceBasis":[{"source":"episode|latestUserAnswer|cardRealityConnection|confirmedContext","content":""}],"dimensions":["selfKindness|commonHumanity|mindfulness"],"reflectionDelta":"","fierceEvidence":null}. Tender needs a concrete distinction and no fierceEvidence. Fierce includes selfKindness or mindfulness plus episode/latestUserAnswer and {"behavior":"","impact":"","direction":"repair|protect|change"}.
""".strip()


PLANNER_PRACTICE_CONTRACT = """
practiceTransition=null or {"transactionID":"","narrativeReferenceID":null,"proposal":{"id":"","kind":"care|repair|protect|change|noAction","content":"","basis":"","status":"pendingConfirmation|confirmed","source":"assistantProposed|userRevised"},"noActionReason":null}. noAction needs content+basis; proposal IDs match transaction and practice-confirmation IDs. Current directReflection uses narrativeReferenceID=null; legacy preserves it. Retired practice arrays/scalars are forbidden.
""".strip()


def planner_output_contract(request: dict[str, Any]) -> str:
    stage = request.get("protocolStage")
    contracts = [PLANNER_SEMANTIC_OPERATION_CONTRACT, _planner_base_structural_contract(request)]
    if stage == "directReflection":
        contracts.append(PLANNER_REFLECTION_FRAME_CONTRACT)
    operations = request.get("permissions", {}).get("allowedOperations", [])
    may_suggest_practice = any(
        isinstance(operation, dict) and operation.get("replyIntent") == "suggestPractice"
        for operation in operations
    )
    if stage in {"narrativeConfirmation", "optionalAction"} or (
        stage == "directReflection" and may_suggest_practice
    ):
        contracts.append(PLANNER_PRACTICE_CONTRACT)
    if stage == "cardReflection":
        contracts.extend(
            [
                CARD_CONNECTION_COMMON_OUTPUT,
                CARD_CONNECTION_OUTPUT_CONTRACTS[_card_substate(request)],
                CARD_TYPED_EVIDENCE_CONTRACT,
            ]
        )
    else:
        contracts.append("cardConnectionTurnOutcome is null.")
    return "Return exactly this JSON object shape:\n" + PLANNER_JSON_SHAPE + "\n" + "\n".join(contracts)


def _effective_typed_memory_value(
    request: dict[str, Any], plan: dict[str, Any], key: str
) -> Any:
    memory = request.get("semanticMemory")
    memory = memory if isinstance(memory, dict) else {}
    patch = plan.get("memoryUpdate")
    patch = patch if isinstance(patch, dict) else {}
    value = patch.get(key)
    return memory.get(key) if value is None else value


def _writing_stage_contract(request: dict[str, Any], plan: dict[str, Any]) -> str:
    stage = str(request.get("protocolStage", ""))
    intent = str(plan.get("replyIntent", ""))
    shared = f"Realize only replyIntent={intent}."
    if intent == "presentFinalNarrative":
        return (
            f"{shared} Present one concise narrative from confirmed evidence, reflectionDelta, and "
            "resolved action/noAction. Do not present while action is absent/pending, replay workflow, "
            "invent a Tender/Fierce pair, resolve unknowns, or ask anything except the planned narrative question."
        )
    if intent == "suggestPractice":
        return (
            f"{shared} Offer exactly the pending care/repair/protect/change/noAction proposal as one "
            "small, feasible, non-punitive option grounded in its basis. noAction explains why pause, "
            "uncertainty, or waiting is preferable to an unsupported task. Ask only whether to accept, "
            "shrink, revise, or decline it; no menu or second plan."
        )
    if stage == "contextualDisclosure":
        if intent == "inviteCardConsent":
            return (
                f"{shared} Use at most one confirmed fact as a restrained bridge, then invite one "
                "optional ‘一张随机反思卡’. A specific-act/whole-person distinction is allowed only for "
                "an explicit broad self-judgment. Preserve conduct/impact. The only question is consent; "
                "do not continue event analysis, label a deliberate choice, assign responsibility, praise, "
                "infer motive, call it an exercise, or preview card title/image/symbol/theme/meaning."
            )
        return (
            f"{shared} Ask the one planned typed disclosure question directly, without acknowledgement "
            "or paraphrase preface. Stay with focalEvent, eventProcess, or behavior/non-action. Do not ask "
            "for impact, emotion, importance, guilt, self-evaluation, responsibility, motive, meaning, "
            "solution, or low-value date/name/category detail. Do not presuppose choice or stop-awareness."
        )
    if stage == "cardConsent":
        return f"{shared} Keep consent optional; do not interpret an unseen image."
    if stage == "cardReflection":
        return f"{shared} Realize only the current typed card substate and planned question count."
    if stage == "directReflection":
        entry = (
            " Briefly fold the supplied card bridge into this reflection; do not confirm it."
            if _is_card_guidance_reflection_entry(request)
            else ""
        )
        frame = plan.get("memoryUpdate", {}).get("reflectionFrame")
        frame = frame if isinstance(frame, dict) else {}
        mode = frame.get("mode")
        mode_rule = (
            " Fierce wording must first limit whole-person attack, then address only the validated "
            "behavior/impact/caring focus in the same reply."
            if mode == "fierce"
            else " Tender wording must realize a concrete grounded distinction, not reassurance or generic Common Humanity alone."
        )
        context_rule = (
            " Mention contextualLoadCue once as tentative background, never cause; silence does not confirm it."
            if plan.get("memoryUpdate", {}).get("contextCueOffered") is True
            else ""
        )
        reference_rule = (
            " If selected, use the current-card reference only as a silent question lens, never stated meaning."
            if plan.get("cardReferenceSelection") is not None
            else ""
        )
        return (
            f"{shared} Realize only reflectionFrame and its grounded evidence. Match the planned question "
            "count; otherwise express reflectionDelta or transition without recap. Do not name theory or "
            "turn card/outcome/unknown cause into responsibility. If an explicit self-judgment is in the "
            "grounding, visibly distinguish the specific event/result from a whole-person conclusion."
            + entry
            + mode_rule
            + context_rule
            + reference_rule
        )
    if stage == "narrativeConfirmation":
        return f"{shared} Realize only the narrative resolution or permitted structured action successor."
    if stage == "optionalAction":
        return (
            f"{shared} Resolve the one proposal atomically; preserve exact content on acceptance, use "
            "source=userRevised for a user revision, or clear with userDeclined. Do not ask why it was rejected."
        )
    if stage == "complete":
        return f"{shared} Keep the acknowledgement brief."
    if stage == "safetySupport":
        return f"{shared} Prioritize immediate safety language."
    return f"{shared} Follow the validated plan exactly."


def _writing_substate_contract(request: dict[str, Any], plan: dict[str, Any]) -> str:
    if request.get("protocolStage") != "cardReflection":
        return ""
    substate = _card_substate(request)
    card = request.get("card") if isinstance(request.get("card"), dict) else {}
    intent = str(plan.get("replyIntent", ""))
    if substate == "observation":
        return "Ask one easy observable-image question using only elements already named; add no symbol or meaning."
    if substate == "development":
        return "Ask only what may happen/change next; do not prescribe it or collect more static detail."
    if substate == "openExploration":
        if intent == "developCardImage" and card.get("connectionScaffoldUsed") is not True:
            return (
                "Ask one easy similarity/difference/contrast/absence comparison between an established "
                "image relation and one realityAnchor action/process/result. No recap or inferred meaning."
            )
        if intent == "inviteCardConnection" and card.get("connectionScaffoldUsed") is True:
            return (
                "Offer one optional observable image/event candidate, then one question allowing development, "
                "redirection, or rejection; do not present it as the person's view or infer inner meaning."
            )
        return "Invite one same-episode image/reality connection using only realityAnchor; do not search another episode."
    if substate == "awaitingCandidateResolution":
        return "Realize only acceptance, user revision, rejection, or genuine uncertainty about the persisted candidate; no new candidate or fit check."
    if int(request.get("protocolVersion") or 0) >= 5:
        return (
            "The canonical connection is complete. Do not create or word a card meaning/mapping "
            "confirmation; move into the permitted Direct Reflection, where its first visible reply "
            "will combine a brief card bridge with the validated reflection delta."
        )
    context = (
        " Mention contextualLoadCue once as tentative background, never cause; silence does not confirm it."
        if plan.get("memoryUpdate", {}).get("contextCueOffered") is True
        else " Do not mention contextualLoadCue."
    )
    reference = (
        " If selected, use the current-card reference only as a silent question lens, never stated meaning."
        if plan.get("cardReferenceSelection") is not None
        else ""
    )
    return (
        "Use the confirmed mapping for one tentative relational distinction or planned retrospective "
        "question; no fit check, completed cause/lesson/change, psychology, or responsibility."
        + context
        + reference
    )


PLAN_CRITIC_REASON_CODES = """duplicate_question_function, overfilled_focus, latest_answer_ignored,
episode_structure_incomplete, behavioral_fact_erased, premature_tender_bridge,
question_cognitive_load, low_information_loop, latest_answer_not_committed,
abstract_attribution_inventory, generic_disclosure_sequence, disclosure_target_mismatch,
resolved_relation_reopened, self_criticism_link_missing, disclosure_scope_violation,
episode_confirmation_missing, card_visual_overcollection, tender_grounding_repetition,
tender_transition_incomplete, episode_structure_misclassified, unsupported_memory_inference,
unsupported_decision_premise, unsupported_stop_awareness_premise, negated_premise_reused,
unnecessary_event_detail, manufactured_global_self_judgment, unsupported_tender_reframe,
consequence_minimized, global_judgment_not_distinguished, unnecessary_tender_confirmation,
user_correction_not_committed, rejected_card_reused, tracking_boundary_ignored,
tracking_context_detached, card_mapping_progress_ignored, card_connection_underdeveloped,
card_reality_mapping_missing, unsupported_card_claim, fierce_reflection_unsupported,
generic_life_example_search, connection_left_current_episode, reality_anchor_not_used,
image_relation_not_compared_with_focal_episode, unsupported_card_reference_selection,
card_reference_permission_invalid, premature_card_conclusion, candid_delta_repetition,
accountability_correction_ignored, premature_action_design, narrative_delta_mismatch,
uncertainty_overridden, practice_offer_required, reflection_mode_not_grounded,
forced_fierce_material, rejected_premise_reused, future_worry_treated_as_self_criticism,
uncertainty_treated_as_failure_evidence, self_compassion_dimension_forced,
reflection_without_progress, incomplete_practice_transition, practice_evidence_mismatch,
unsupported_no_action, completion_contract_invalid, user_connection_not_committed,
incomplete_connection_patch, card_mapping_not_used, connection_source_without_content,
legacy_card_connection_patch_not_allowed"""


WRITER_CRITIC_REASON_CODES = """field_stitching, unnatural_chinese, unsupported_claim, relation_lost,
behavioral_fact_erased, user_correction_not_committed, rejected_card_reused, question_mismatch,
multiple_questions, tracking_context_detached, card_claim_imposed, mechanical_fit_check,
baseline_repetition, repetitive_acknowledgement, distinction_meta_question,
question_cognitive_load, disclosure_reporting_preface, disclosure_scope_violation,
disclosure_target_mismatch, resolved_relation_reopened, unsupported_decision_premise,
unsupported_stop_awareness_premise, negated_premise_reused, manufactured_global_self_judgment,
unsupported_tender_reframe, consequence_minimized, global_judgment_not_distinguished,
unnecessary_tender_confirmation, episode_confirmation_missing, premature_transition_invitation,
card_visual_overcollection, premature_practice, premature_card_conclusion,
candid_delta_repetition, accountability_correction_ignored, premature_action_design,
uncertainty_overridden, narrative_delta_mismatch, practice_evidence_mismatch,
unsupported_positive_trait_reframe, unsupported_contextual_inference, premature_card_identity,
unsupported_card_reference_selection, card_reference_answer_imposed, generic_life_example_search,
connection_left_current_episode, reality_anchor_not_used,
image_relation_not_compared_with_focal_episode, reflection_without_progress,
future_worry_treated_as_self_criticism, uncertainty_treated_as_failure_evidence,
forced_fierce_material, rejected_premise_reused"""


_PLAN_REASON_CODES_BY_STAGE = {
    "contextualDisclosure": "duplicate_question_function, overfilled_focus, latest_answer_ignored, episode_structure_incomplete, behavioral_fact_erased, latest_answer_not_committed, disclosure_target_mismatch, resolved_relation_reopened, disclosure_scope_violation, episode_structure_misclassified, unsupported_memory_inference, unsupported_decision_premise, unsupported_stop_awareness_premise, negated_premise_reused, unnecessary_event_detail, manufactured_global_self_judgment, unsupported_tender_reframe, consequence_minimized, unnecessary_tender_confirmation",
    "cardConsent": "latest_answer_ignored, completion_contract_invalid, premature_card_conclusion",
    "cardReflection": "latest_answer_ignored, rejected_card_reused, tracking_boundary_ignored, card_mapping_progress_ignored, card_connection_underdeveloped, card_reality_mapping_missing, unsupported_card_claim, generic_life_example_search, connection_left_current_episode, reality_anchor_not_used, image_relation_not_compared_with_focal_episode, unsupported_card_reference_selection, card_reference_permission_invalid, premature_card_conclusion, user_connection_not_committed, incomplete_connection_patch, card_mapping_not_used, connection_source_without_content, legacy_card_connection_patch_not_allowed",
    "directReflection": "latest_answer_ignored, fierce_reflection_unsupported, candid_delta_repetition, accountability_correction_ignored, premature_action_design, uncertainty_overridden, reflection_mode_not_grounded, forced_fierce_material, rejected_premise_reused, future_worry_treated_as_self_criticism, uncertainty_treated_as_failure_evidence, self_compassion_dimension_forced, reflection_without_progress, global_judgment_not_distinguished, practice_evidence_mismatch, unsupported_no_action",
    "narrativeConfirmation": "latest_answer_ignored, narrative_delta_mismatch, incomplete_practice_transition, practice_evidence_mismatch, unsupported_no_action, completion_contract_invalid",
    "optionalAction": "latest_answer_ignored, incomplete_practice_transition, practice_evidence_mismatch, unsupported_no_action, completion_contract_invalid",
}


_WRITER_REASON_CODES_BY_STAGE = {
    "contextualDisclosure": "field_stitching, unnatural_chinese, unsupported_claim, relation_lost, question_mismatch, multiple_questions, repetitive_acknowledgement, question_cognitive_load, disclosure_reporting_preface, disclosure_scope_violation, disclosure_target_mismatch, resolved_relation_reopened, unsupported_decision_premise, unsupported_stop_awareness_premise, negated_premise_reused, manufactured_global_self_judgment, unsupported_tender_reframe, consequence_minimized, unnecessary_tender_confirmation, premature_transition_invitation",
    "cardConsent": "unnatural_chinese, unsupported_claim, question_mismatch, multiple_questions, premature_card_identity, premature_card_conclusion",
    "cardReflection": "field_stitching, unnatural_chinese, unsupported_claim, relation_lost, rejected_card_reused, question_mismatch, multiple_questions, card_claim_imposed, mechanical_fit_check, tracking_context_detached, premature_card_conclusion, unsupported_contextual_inference, unsupported_card_reference_selection, card_reference_answer_imposed, generic_life_example_search, connection_left_current_episode, reality_anchor_not_used, image_relation_not_compared_with_focal_episode",
    "directReflection": "field_stitching, unnatural_chinese, unsupported_claim, relation_lost, behavioral_fact_erased, user_correction_not_committed, question_mismatch, multiple_questions, mechanical_fit_check, candid_delta_repetition, accountability_correction_ignored, premature_action_design, uncertainty_overridden, reflection_without_progress, global_judgment_not_distinguished, future_worry_treated_as_self_criticism, uncertainty_treated_as_failure_evidence, forced_fierce_material, rejected_premise_reused",
    "narrativeConfirmation": "field_stitching, unnatural_chinese, unsupported_claim, narrative_delta_mismatch, practice_evidence_mismatch, mechanical_fit_check",
    "optionalAction": "unnatural_chinese, unsupported_claim, premature_action_design, practice_evidence_mismatch",
}


def _plan_reason_codes(request: dict[str, Any]) -> str:
    return _PLAN_REASON_CODES_BY_STAGE.get(
        str(request.get("protocolStage", "")),
        "latest_answer_ignored, unsupported_memory_inference, completion_contract_invalid",
    )


def _writer_reason_codes(request: dict[str, Any]) -> str:
    return _WRITER_REASON_CODES_BY_STAGE.get(
        str(request.get("protocolStage", "")),
        "unnatural_chinese, unsupported_claim, question_mismatch, multiple_questions",
    )


def _plan_critic_stage_contract(request: dict[str, Any]) -> str:
    stage = str(request.get("protocolStage", ""))
    if stage == "contextualDisclosure":
        if int(request.get("protocolVersion") or 0) >= 5:
            return (
                "Audit semanticOperation and the cumulative focal-event/process/behavior payload. "
                "clarifyEvent is invalid once that candidate snapshot is complete; "
                "advanceToCardConsent requires it complete. Optional psychological fields and legacy "
                "eventDisclosureOutcome/requestedStage/replyIntent/nextPrompt cannot decide progression."
            )
        return (
            "Audit focal event, process, and relevant action/non-action. eventDisclosureOutcome must "
            "match the cumulative patch. Optional psychological fields cannot delay readiness. One "
            "explore question uses an advertised purpose/target, does not reopen a completed relation "
            "without typed correction/withdrawal/contradiction, presume blame or choice, or seek low-value "
            "detail. Once ready, require the same-turn brief bridge and card invitation."
        )
    if stage == "cardConsent":
        return (
            "Accepted pending cardConsent must use the silent Swift draw operation and cannot describe "
            "or interpret an unseen card."
        )
    if stage == "cardReflection":
        return "Audit only the current typed card substate, same-episode grounding, legal question count, and forward progress."
    if stage == "directReflection":
        return (
            "Require one complete grounded reflectionFrame with a currently allowed action and one/two "
            "dimensions. Tender needs a concrete fact/inference, event/identity, pain/self-attack, or similar "
            "distinction and cannot search for responsibility; Common Humanity alone is not progress. Fierce "
            "must remain Tender-grounded and requires existing behavior, impact, readiness, and a caring "
            "direction. Reject card-based responsibility, future worry as global judgment, uncertainty as "
            "failure, rejected premise reuse, forced dimensions, or recap/normalization without progress. "
            "On the first post-guidance turn, require one brief canonical card bridge inside the same "
            "reflection and forbid card meaning confirmation. In v5 synthesizeUnderstanding creates one "
            "grounded action/noAction first."
        )
    if stage in {"narrativeConfirmation", "optionalAction"}:
        return (
            "Audit one atomic proposal transaction. An active care/repair/protect/change/noAction has "
            "non-empty id/content/user-evidence basis, pending/confirmed status, legal source, and matching "
            "transaction/proposal/practice-reference IDs. Proactive noAction has rationale+basis; rejection "
            "uses proposal=null plus supported typed reason. Preserve narrativeReferenceID ordering. "
            "Acceptance keeps exact content; revision keeps id and source=userRevised; decline needs no reason."
        )
    return "Audit only the supplied stage permissions, grounding, confirmation, progress, and output contract."


def _plan_critic_substate_contract(request: dict[str, Any]) -> str:
    if request.get("protocolStage") != "cardReflection":
        return ""
    substate = _card_substate(request)
    contracts = {
        "observation": (
            "Require user-led observable description and stop once an action/relation exists; reject "
            "symbols, fixed meaning, psychology, responsibility, or extra static-detail collection."
        ),
        "development": (
            "Require at most one possible-next-change question; reject a prescribed development, more "
            "static inventory, or assistant-authored reality meaning. Preserve a complete spontaneous "
            "user-authored mapping without a confirmation step."
        ),
        "openExploration": (
            "Require same-episode observable comparison. A direct mapping is one complete userAuthored "
            "outcome; inability is connectionStillUnclear. Enforce only the advertised scaffold/candidate "
            "capability and reject another life example or candidate-as-user-evidence."
        ),
        "awaitingCandidateResolution": (
            "Only the persisted candidate may be accepted, revised, or rejected. Revision saves the "
            "user mapping; rejection withdraws it. Reject open exploration, approval-word requirements, "
            "raw projections, or connection confirmation."
        ),
        "guidance": (
            "Use the canonical mapping and current closed reference boundary only. In v5 require direct "
            "Reflection with no new meaning/mapping confirmation; legacy ordering follows its supplied "
            "capability. Reject completed cause/lesson/change, card-based psychology/responsibility/Fierce "
            "evidence, renewed exploration, mechanical approval, or unsupported contextual/reference use."
        ),
    }
    return contracts[substate]


def _writer_critic_stage_contract(request: dict[str, Any], plan: dict[str, Any]) -> str:
    stage = str(request.get("protocolStage", ""))
    intent = str(plan.get("replyIntent", ""))
    if stage == "contextualDisclosure" and intent == "exploreContext":
        return (
            "Require one direct question for the typed purpose/target with no acknowledgement, summary, "
            "paraphrase, card invitation, or different topic. Reject impact/emotion/importance/guilt/self-"
            "evaluation/responsibility/motive/meaning questions, finer detail after readiness, unsupported "
            "choice/stop-awareness, denied premise, or abstract controllability inventories."
        )
    if intent == "inviteCardConsent":
        return (
            "Require an optional ‘一张随机反思卡’ invitation and at most one brief factual bridge. Reject "
            "extra introspection, full recap, unsupported responsibility/choice/motive/trait, minimized "
            "impact, or previewed card identity/content/meaning. A whole-person distinction requires the "
            "person's explicit broad judgment."
        )
    if stage == "cardReflection":
        return "Audit only the visible function selected by the current typed card substate."
    if stage == "directReflection":
        return (
            "Require the typed reflectionFrame action without internal labels. Tender realizes a grounded "
            "distinction and cannot elicit responsibility; generic acknowledgement or Common Humanity alone "
            "fails. Fierce first limits whole-person attack, then stays inside the validated behavior, impact, "
            "and care-motivated focus. Reject card-based responsibility, punishment, character verdict, "
            "future worry as self-judgment, uncertainty as failure, or restatement without a distinction, "
            "valid question, understanding, or transition. If this is the first post-guidance turn, the card "
            "bridge and reflection must be one reply with no approval check. Match question count to nextPrompt."
        )
    if intent == "presentFinalNarrative":
        return (
            "Require one concise integrated distinction using resolved action/noAction. Reject episode/"
            "workflow replay, repeated Tender defense, new advice, answered uncertainty, global-self question, "
            "or asking whether the assistant narrative is fitting/accurate/correct/approved/editable."
        )
    if intent in {"suggestPractice", "revisePractice"} or stage == "optionalAction":
        return (
            "Require the single grounded proposal/resolution from the plan; reject menus, punishment, generic "
            "or mismatched basis, invented action, or demanding a reason for decline."
        )
    return "Audit natural realization of the typed plan, evidence, question count, and forward progress."


def _writer_critic_card_substate_contract(request: dict[str, Any]) -> str:
    contracts = {
        "observation": "Require one user-led observable image question; reject symbols, fixed meaning, psychology, or static overcollection.",
        "development": "Require one possible-next-change question; reject a prescribed development or reality interpretation.",
        "openExploration": (
            "Require same-episode observable comparison and the planned question. Reject another life "
            "episode, recap instead of progress, inferred inner meaning, or inability treated as refusal."
        ),
        "awaitingCandidateResolution": (
            "Realize only the pending candidate resolution. Reject approval-word demands, a new candidate, "
            "reopened exploration, or rejected content returned as evidence."
        ),
        "guidance": (
            "For v5 expose no separate guidance reply or confirmation; the next Direct Reflection combines "
            "the bridge and delta. Legacy follows its validated operation. Reject fit checks, completed "
            "lessons, or card-based psychology/responsibility."
        ),
    }
    return contracts[_card_substate(request)]


def _planner(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    recovery = _recovery_contract(request) or "No recovery diagnostic."
    shared_contract = _planner_shared_contract(request)
    semantic_contract = _semantic_contract(request)
    condition_contract = _condition_contract(request)
    stage_contract = _planning_stage_contract(request)
    substate_contract = _planner_substate_contract(request)
    permissions_contract = _permissions_text(request)
    output_contract = f"{OUTPUT_DISCIPLINE}\n{planner_output_contract(request)}"
    system = f"""
ROLE
You are the private semantic TurnPlanner. A separate Writer produces visible Chinese. Interpret the
latest answer, update typed memory, and select exactly one permitted operation.

SHARED INVARIANTS
{shared_contract}

STATE MEMORY
{semantic_contract}

CONDITION
{condition_contract}

STAGE GOAL / DELTA
{stage_contract}

CURRENT SUBSTATE
{substate_contract or "No specialized substate delta."}

ALLOWED
{permissions_contract}

RECOVERY
{recovery}

OUTPUT CONTRACT
{output_contract}
""".strip()
    return _prompt_messages(
        component="planner",
        request=request,
        system=system,
        user=f"TURN REQUEST JSON:\n{_encoded(request)}",
        stage_contract=stage_contract + "\n" + semantic_contract,
        substate_contract=substate_contract,
        schema_contract=output_contract,
        recovery_contract=_recovery_contract(request),
    )


def _plan_critic(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    plan = _required_object(payload, "plan")
    stage_rules = [_plan_critic_stage_contract(request)]
    substate_contract = _plan_critic_substate_contract(request)
    if request.get("protocolStage") == "cardReflection":
        stage_rules.insert(0, CARD_EVIDENCE_RULES)
    if request.get("protocolStage") == "directReflection":
        stage_rules.insert(0, SELF_COMPASSION_RULES)
    confirmation_contract = CONFIRMATION_RULES if _pending_confirmation(request) else ""
    stage_contract = " ".join(stage_rules)
    output_contract = (
        'Return exactly {"verdict":"pass|revisePlanner","reasonCodes":[],"revisionGuidance":null}.\n'
        "revisionGuidance is one short, content-free, executable planning correction; never generate "
        "the next question or user-visible wording."
    )
    current_authority = (
        "For protocol v5, review the explicit semanticOperation and its semantic payload. Ignore "
        "conflicting legacy requestedStage, replyIntent, localAction, nextPrompt, confirmation, and "
        "derived outcome fields; Swift Projector owns them and they are never a revision reason. "
        "permissions.allowedSemanticOperations is authoritative."
        if int(request.get("protocolVersion") or 0) >= 5
        else "For legacy protocol, allowedOperations structural tuples remain authoritative."
    )
    system = f"""
ROLE
You are the private plan Critic. Do not write dialogue or choose a replacement operation. Return
revisePlanner only for one material defect in: state legality; grounding; repeated/rejected premise;
confirmation legality; reflection mode/action consistency; progress; or output contract. Swift's
typed capability list is authoritative. Do not impose a fixed turn count, disclosure order, optional
field, or preferred topic.

EXECUTION AUTHORITY
{current_authority}

SHARED AUDIT
{GROUNDING_RULES}
{confirmation_contract}

STAGE AUDIT
{stage_contract}

CURRENT SUBSTATE AUDIT
{substate_contract or "No specialized substate audit."}

ALLOWED REASON CODES
{_plan_reason_codes(request)}

CONDITION
{_condition_contract(request)}

OUTPUT
{output_contract}
""".strip()
    user = f"TURN REQUEST JSON:\n{_encoded(request)}\n\nCANDIDATE PLAN JSON:\n{_encoded(plan)}"
    return _prompt_messages(
        component="plan_critic",
        request=request,
        system=system,
        user=user,
        stage_contract=stage_contract,
        substate_contract=substate_contract,
        schema_contract=output_contract,
    )


def _writer(payload: dict[str, Any], *, revision: bool = False) -> PromptMessages:
    request = _required_object(payload, "request")
    plan = _required_object(payload, "plan")
    intent = str(plan.get("replyIntent", ""))
    role = "Writer revision" if revision else "Writer"
    stage_contract = _writing_stage_contract(request, plan)
    substate_contract = _writing_substate_contract(request, plan)
    output_contract = (
        "Return exactly one JSON object. reply contains only user-visible Chinese, without analysis, "
        "labels, protocol fields, or alternatives:\n"
        f'{{"realizedIntent":"{intent}","reply":"complete user-visible Chinese reply"}}'
    )
    system = f"""
ROLE
You are the private Chinese dialogue {role}. Surface realization only: request and validated plan are
immutable, including stage, intent, action, memory, prompt, progression, and question presence/count.

GROUNDING / STYLE
{GROUNDING_RULES}
{WRITER_STYLE}

CURRENT WRITING TASK
{stage_contract}

CURRENT SUBSTATE
{substate_contract or "No specialized substate wording rule."}

OUTPUT
{output_contract}
""".strip()
    user_parts = [
        f"RECENT DIALOGUE JSON:\n{_encoded(request.get('recentMessages', []))}",
        f"VALIDATED PLAN JSON:\n{_encoded(plan)}",
    ]
    if revision:
        user_parts.extend(
            [
                f"ORIGINAL DRAFT JSON:\n{_encoded(_required_object(payload, 'draft'))}",
                f"CRITIQUE JSON:\n{_encoded(_required_object(payload, 'critique'))}",
            ]
        )
    return _prompt_messages(
        component="writer_revision" if revision else "writer",
        request=request,
        system=system,
        user="\n\n".join(user_parts),
        stage_contract=stage_contract,
        substate_contract=substate_contract,
        schema_contract=output_contract,
    )


def _writer_critic(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    plan = _required_object(payload, "plan")
    draft = _required_object(payload, "draft")
    stage_contract = _writer_critic_stage_contract(request, plan)
    substate_contract = (
        _writer_critic_card_substate_contract(request)
        if request.get("protocolStage") == "cardReflection"
        else ""
    )
    output_contract = (
        'Return exactly {"verdict":"pass|reviseWriter","reasonCodes":[],"revisionGuidance":null}.\n'
        "revisionGuidance is short, executable, and contains no new fact."
    )
    system = f"""
ROLE
You are the private Writer Critic. The request and plan are immutable. Do not write the replacement
reply or select another topic. Return reviseWriter only for a material visible defect: plan/function
drift; changed question presence/count; unnatural or field-stitched Chinese; unsupported/lost
evidence; erased conduct/impact; ignored correction or reused rejection; reassurance, praise,
normalization, minimization, excuse, or whole-person inflation; internal theory labels; unsupported
context/card claim; mechanical approval check; repeated recap/opening; premature advice/action;
generic or basis-mismatched practice; or no distinction, valid question, understanding, or transition.
Judge propositions and conversational functions semantically, including paraphrases and novel wording,
not tokens, prefixes, regexes, or phrase lists. revisionGuidance cannot add facts, psychology, or a new topic.

STAGE AUDIT
{stage_contract}

CURRENT SUBSTATE AUDIT
{substate_contract or "No specialized substate audit."}

ALLOWED REASON CODES
{_writer_reason_codes(request)}

CONDITION
{_condition_contract(request)}

OUTPUT
{output_contract}
""".strip()
    user = (
        f"TURN REQUEST JSON:\n{_encoded(request)}\n\n"
        f"VALIDATED PLAN JSON:\n{_encoded(plan)}\n\n"
        f"WRITER DRAFT JSON:\n{_encoded(draft)}"
    )
    return _prompt_messages(
        component="writer_critic",
        request=request,
        system=system,
        user=user,
        stage_contract=stage_contract,
        substate_contract=substate_contract,
        schema_contract=output_contract,
    )


def _current_v5_stage_contract(request: dict[str, Any]) -> str:
    stage = str(request.get("protocolStage") or "")
    if stage == "contextualDisclosure":
        return (
            "Event Disclosure asks one semantic question: is the current reality sufficiently "
            "concrete to reflect on? The usable anchor includes the experience being discussed, its "
            "basic development, and what the person did or did not do. These are information "
            "functions, not a fixed question checklist; one answer may supply all of them. Merge "
            "current memory with the latest answer. When all three functions exist choose "
            "advanceToCardConsent; otherwise choose clarifyEvent and ask only for the missing part "
            "whose absence actually prevents reflection. A broad ongoing difficulty is not yet a "
            "focal episode. eventProcess must add basic development rather than merely repeat the "
            "result. behaviorEvidence must add a concrete response, action, or omission; merely "
            "participating in the activity is not enough. Consent to keep talking, emotion, or "
            "self-evaluation may be useful context but cannot replace missing Event content. Impact, "
            "importance, motive, responsibility, and "
            "self-judgment are optional evidence and never disclosure gates. In episodeStructure "
            "emit only new grounded items established by the latest user message; Swift accumulates "
            "them with committed memory. A non-empty eventProcess or behaviorEvidence uses status "
            "present; omit an unchanged relation and never emit an empty list for it. The typed "
            "memoryUpdate fragment is: "
            + CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE
        )
    if stage == "cardConsent":
        return (
            "Resolve only the pending card consent. Clear acceptance selects "
            "acknowledgeCardConsent; clear refusal selects declineCardConsent; otherwise use "
            "inviteCardConsent. The model never selects a card."
        )
    if stage == "cardReflection":
        return (
            "Use one forward route: visible observation, a sufficiently clear user-authored image "
            "understanding, then a connection with lived experience. Extract observation and development "
            "evidence from the latest answer using this sparse memory shape: "
            + CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE
            + ". The Card goal is a minimal but complete spontaneous narrative, not a full image "
            "interpretation. cardDevelopmentEvidence is cumulative and records two semantic functions: "
            "relationOrAction says how the main user-described elements participate in one situation, "
            "rather than recording an isolated detail; "
            "anticipatedChangeOrChoice says how that situation may continue, change, or be chosen. "
            "Never invent the second function from the first. If only one is supported, preserve it in "
            "the patch and choose continueCardDevelopment with one open question for the missing "
            "function. When both are supported, the narrative is complete and you must choose "
            "inviteRealityConnection. This is a functional judgment, never a keyword or phrase match. "
            "Ask another Development question only when it is likely to produce materially new "
            "user-authored understanding. If it would merely decompose another object, speculate about character "
            "psychology, seek symbolic meaning, or deepen the same interpretation, Development is "
            "complete and you must choose inviteRealityConnection. Reality Connection asks what this "
            "image understanding brings to mind in the person's current lived experience. Use the "
            "current disclosed experience and reflection focus as an anchor, but let the user define "
            "the connection through a feeling, choice, standard, relationship, behavior pattern, or "
            "circumstance; do not require a one-to-one event-detail mapping. Do not send the user "
            "searching for an unrelated life episode. If the latest answer to a Reality Connection "
            "question contains only more image "
            "material and no mapping, return connectionStillUnclear and choose the available scaffold; "
            "do not repeat inviteRealityConnection. Before a canonical connection exists, use only image "
            "relations the user described and the current disclosed experience/reflection focus; never "
            "use designer meaning, "
            "tracking, motive, diagnosis, or another life episode to create the connection. A direct "
            "user connection uses cardConnectionTurnOutcome userAuthoredConnection with a complete "
            "userAuthored connection. Difficulty uses connectionStillUnclear. A candidate is stored "
            "only in memoryUpdate.pendingCardRealityConnection and remains negotiable. Establishing "
            "a direct connection, accepting/revising a candidate, or authorizing an already committed "
            "connection must also include one grounded Tender reflectionFrame so the same turn can "
            "continue visibly without a silent second Planner call."
        )
    if stage == "directReflection":
        return (
            "Choose the next useful Tender, evidence-grounded Fierce, synthesis, or practice "
            "operation from the allowed list. Tender does not erase conduct or impact; Fierce needs "
            "specific user evidence and stays grounded in compassion. Use one complete reflectionFrame "
            "for reflection operations and one complete practiceTransition for a practice operation."
        )
    if stage == "optionalAction":
        return (
            "Resolve only the active small action, or perform the allowed narrative/completion "
            "operation. Preserve the user's accept, revision, or refusal without adding a second plan."
        )
    if stage == "narrativeConfirmation":
        return (
            "Resolve or revise only the final narrative using confirmed evidence. Do not add a new "
            "motive, card meaning, contextual cause, or action."
        )
    if stage == "safetySupport":
        return "Use only the allowed safety/completion operation and do not carry unrelated patches."
    return "Use exactly one currently allowed semantic operation."


def _current_v5_planner(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    stage = str(request.get("protocolStage") or "")
    allowed = request.get("allowedSemanticOperations")
    allowed = allowed if isinstance(allowed, list) else []
    correction = request.get("correction")
    correction_contract = ""
    if isinstance(correction, dict):
        correction_contract = (
            "\nONE STRUCTURAL CORRECTION\nThe preceding draft was not executable for reason="
            + str(correction.get("reason") or "payloadInvalid")
            + ". Re-read the same latest user evidence and choose only from the unchanged allowed "
            "operations. Do not invent evidence to make an operation legal."
        )
    reflection_contract = (
        "\nREFLECTION STRUCTURE\n" + PLANNER_REFLECTION_FRAME_CONTRACT
        if stage in {"cardReflection", "directReflection"}
        else ""
    )
    practice_contract = (
        "\nOPTIONAL ACTION STRUCTURE\n" + PLANNER_PRACTICE_CONTRACT
        if stage in {"directReflection", "optionalAction", "narrativeConfirmation"}
        else ""
    )
    card_connection_contract = ""
    if stage == "cardReflection":
        card_connection_contract = """
CARD CONNECTION SHAPE
cardConnectionTurnOutcome is null except for a typed connection turn. Its legal shapes are:
{"kind":"userAuthoredConnection","connection":{"imageRelation":"","realityMapping":"",
"source":"userAuthored","status":"confirmed"}},
{"kind":"connectionStillUnclear","connection":null},
{"kind":"candidateAccepted","connection":null},
{"kind":"candidateRevised","connection":{"imageRelation":"","realityMapping":"",
"source":"userRevised","status":"confirmed"}}, or
{"kind":"candidateRejected","connection":null}.
"""
    system = f"""
CURRENT_V5_CORE_PLANNER

ROLE
Understand the latest user turn and choose the single most useful next conversational operation.
Return semantic evidence, not workflow instructions and not user-facing prose.

AUTHORITY
Allowed semantic operations are exactly: {_encoded(allowed)}.
Choose exactly one. Swift alone derives stage changes, prompts, confirmations, card draw/guidance,
and persistence. Do not output requestedStage, replyIntent, nextPrompt, localAction, confirmation,
or any legacy executable field.

EVIDENCE
Use only user messages and already confirmed typed memory. The latest answer may add several typed
relations at once. Preserve uncertainty. Do not infer emotion, motive, personality, diagnosis,
responsibility, causality, or tracking relevance. memoryUpdate is a sparse patch: omit unchanged
fields and never use empty/default values to overwrite grounded prior evidence.

STAGE
{_current_v5_stage_contract(request)}
{reflection_contract}{practice_contract}{card_connection_contract}

OUTPUT
Return exactly one JSON object shaped as:
{CURRENT_V5_PLANNER_JSON_SHAPE}
semanticOperation is required. semanticEvidencePatch.memoryUpdate is an object and may be empty.
responseFocus is a concise instruction for the Writer; it may contain the one useful question goal
but never a second operation or protocol field.{correction_contract}
""".strip()
    user = "CURRENT V5 TURN REQUEST JSON:\n" + _encoded(request)
    return PromptMessages(system=system, user=user)


def _current_v5_writer(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    directive = _required_object(payload, "directive")
    next_prompt = directive.get("nextPrompt")
    next_prompt = next_prompt if isinstance(next_prompt, dict) else {}
    prompt_kind = str(next_prompt.get("kind") or "none")
    question_contract = (
        "End with exactly one natural, easy-to-answer question serving the supplied focus."
        if prompt_kind in {"openQuestion", "confirmationRequest"}
        else "Do not add a question."
    )
    rewrite_reason = directive.get("rewriteReason")
    rewrite_contract = (
        "This is a wording-only retry. Keep the same operation, evidence, focus, and question count."
        if isinstance(rewrite_reason, str) and rewrite_reason
        else ""
    )
    operation = str(directive.get("semanticOperation") or "")
    operation_contracts = {
        "clarifyEvent": (
            "Ask directly for the one missing focal event, development, or concrete action named by "
            "the directive. Do not ask whether the person is willing to explore and do not ask a "
            "meta-conversation question."
        ),
        "advanceToCardConsent": (
            "Use one short grounded sentence, then invite one random reflection card. Do not add an "
            "Event-analysis question before the invitation."
        ),
        "continueCardObservation": (
            "Ask only what the person can see in the image. Do not supply a symbol, emotion, or meaning."
        ),
        "continueCardDevelopment": (
            "Ask for one relationship, action, tension, choice, or possible next change in the image. "
            "Do not ask for exhaustive details or symbolic meaning."
        ),
        "inviteRealityConnection": (
            "Name the user's own image understanding briefly and ask what it brings to mind in the "
            "current disclosed experience or reflection focus. The person may connect it through a "
            "feeling, choice, standard, relationship, behavior pattern, or circumstance; do not "
            "require a one-to-one event-detail mapping. Do not ask another image-only question or "
            "introduce an unrelated life episode."
        ),
        "offerCardConnectionScaffold": (
            "Keep the current disclosed experience as the anchor. Narrow the task by placing one "
            "user-described image relation beside one aspect of that experience the person has already "
            "expressed; do not impose a symbol, motive, or one-to-one answer."
        ),
        "establishUserAuthoredCardConnection": (
            "Preserve the image-to-life connection as the person's own meaning. Express only the "
            "authorized grounded Tender distinction, then ask one concrete question that continues "
            "reflection. Do not ask whether the connection is accurate and do not add a fixed card "
            "meaning, motive, or positive-trait explanation."
        ),
    }
    operation_contract = operation_contracts.get(
        operation,
        "Follow the authorized operation without adding a second conversational task.",
    )
    system = f"""
CURRENT_V5_CORE_WRITER

Write one concise, natural Chinese reply for the authorized semantic turn. You cannot change the
operation, state, evidence patch, question purpose, card permission, or action. Do not output JSON
protocol fields other than the required reply wrapper.

Use the person's words and confirmed facts. Be compassionate without generic reassurance, virtue
reframing, excuse-making, diagnosis, or erasing real impact. Do not expose Tender/Fierce labels,
workflow names, card design references, tracking sources, or internal state. Do not begin with a
fixed acknowledgement formula and do not mechanically ask whether an interpretation is accurate.
Do not repeat or paraphrase the immediately preceding assistant question. Each reply must move to
the new semantic function authorized by Swift.

OPERATION-SPECIFIC LANGUAGE
{operation_contract}
{question_contract}
{rewrite_contract}

Return exactly {{"reply":""}}.
""".strip()
    user = (
        "CURRENT V5 TURN REQUEST JSON:\n"
        + _encoded(request)
        + "\n\nAUTHORIZED SWIFT DIRECTIVE JSON:\n"
        + _encoded(directive)
    )
    return PromptMessages(system=system, user=user)


def build_turn_messages(item: LLMTurnPromptIn) -> PromptMessages:
    if item.promptVersion == CURRENT_V5_CORE_PROMPT_VERSION:
        builders = {
            "planner": _current_v5_planner,
            "writer": _current_v5_writer,
        }
        builder = builders.get(item.promptTask)
        if builder is None:
            raise HTTPException(409, f"unsupported current v5 task: {item.promptTask}")
        return builder(item.payload)
    if item.promptVersion != TURN_PROMPT_VERSION:
        raise HTTPException(409, f"unsupported turn prompt version: {item.promptVersion}")
    builders = {
        "planner": _planner,
        "plan_critic": _plan_critic,
        "writer": _writer,
        "writer_critic": _writer_critic,
        "writer_revision": lambda payload: _writer(payload, revision=True),
    }
    return builders[item.promptTask](item.payload)


def turn_prompt_chat(item: LLMTurnPromptIn) -> LLMChatIn:
    prompt = build_turn_messages(item)
    if prompt.metrics is not None:
        log_prompt_length(prompt.metrics)
    return LLMChatIn(
        messages=[
            {"role": "system", "content": prompt.system},
            {"role": "user", "content": prompt.user},
        ],
        maxTokens=item.maxTokens,
        temperature=item.temperature,
        agentMode="fast",
    )
