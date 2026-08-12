from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Literal

from fastapi import HTTPException

from .schemas import LLMChatIn, LLMTurnPromptIn


TURN_PROMPT_VERSION = "turn-v4-server-v45"
CURRENT_V5_CORE_PROMPT_VERSION = "turn-v5-core-server-v101"
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
    "continueExploratoryReflection",
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
Tender grounds every reflection in one distinction. Its three dimensions are optional lenses, never
forced questions. Keep fact/inference and event/identity distinct without praise,
denial, excuse, or a positive opposite. Tender may stand alone. Self-criticism judges ability/character/
worth; worry predicts; uncertainty marks missing information. Fierce optionally adds Tender-grounded candor
only for supplied behavior, impact, boundary, support, or caring repair/protect/change; distress alone never requires it.
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
Save one grounded reflectionFrame with a legal action and non-recap delta. selfCriticalStatement is
an exact user-authored evaluative conclusion or explicit self-directed blame, never the behavior or
harm being evaluated. Tender preserves warranted responsibility and limits only unsupported scope;
it does not excuse conduct. Tender has no fierceEvidence; Fierce uses supplied conduct/impact and
caring direction.
synthesizeUnderstanding may create one grounded action/noAction.
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
        "Goal: choose one grounded reflectionFrame. Tender may stand alone. Fierce is optional "
        "and uses behavior/impact plus a caring repair/protect/change focus; never solicit "
        "evidence. For whole-person judgment, distinguish fact/inference from identity and keep worry/"
        "uncertainty separate. Recap or Common Humanity alone is not a delta. v5 synthesis proposes one "
        "grounded action/noAction before final narrative."
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
    '{"semanticOperation":null,"reflectionProgressionDecision":null,'
    '"semanticEvidencePatch":{"memoryUpdate":{},'
    '"cardConnectionEvidence":null,"contextualTrackingDecision":null},'
    '"responseFocus":""}'
)

# Stage-scoped schema for the only Event aggregate accepted by the current v5 Planner. Keeping it
# beside the compact top-level shape makes the sparse-patch contract explicit without restoring
# the retired all-stage Planner tuple.
CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE = (
    '{"selfCriticalStatement":"exact grounded self-judgment or explicit self-directed blame when newly supplied",'
    '"episodeStructure":{"concreteFacts":["grounded focal event"],'
    '"eventProcess":["grounded development"],'
    '"behaviorEvidence":["grounded action or omission"]}}'
)

CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE = (
    '{"cardObservationEvidence":{"userDescribedElements":["visible user-described element"]},'
    '"cardDevelopmentEvidence":{"actorsOrElements":["user-described element"],'
    '"projectiveFocus":"user-selected salient element, uncertainty, tension, or choice",'
    '"relationOrAction":"user-described relation or action",'
    '"anticipatedChangeOrChoice":"user-described possible change or choice"}}'
)

CURRENT_V5_CONTEXT_HYPOTHESIS_PATCH_SHAPE = (
    'semanticEvidencePatch.contextualTrackingDecision={"metricEligibility":['
    '{"profileID":"exact supplied profileID","metric":"exact supplied metric",'
    '"status":"qualifies|doesNotQualify","preferred":false}]}; '
    'classify every supplied metric exactly once; when any metric qualifies exactly one qualifying '
    'metric has preferred=true, and when none qualifies every preferred value is false; '
    'after a reveal, '
    '{"contextRelationship":{"relevance":"related|partlyRelated|unrelated|uncertain",'
    '"userInterpretation":"user-authored natural relationship or revision, otherwise null"}}'
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


def _reflection_frame_contract(*, sparse_tender_lineage: bool) -> str:
    if sparse_tender_lineage:
        return """
Reflection output carries meaning only. Exploration emits selfCriticismLink and no reflectionFrame.
Tender/Synthesis meaning uses reflectionFrame.reflectionDelta except at committed Tender or active
Fierce progression, where reflectionProgressionDecision is the sole meaning owner. Fierce completion
colocates only reflectionDelta and fierceDirection in that decision. Swift recovers the active candidate,
latest user answer, and committed evidence lineage. responseFocus is only a
current-turn Writer presentation instruction: it is never persistent evidence and Swift never
uses it as a reflectionDelta fallback. Never copy an Assistant question, earlier reply, or Writer
instruction into reflectionDelta. Optional new user-grounded evidence is
reflectionFrame.evidenceBasis=["exact user-grounded proposition"]. dimensions may contain
selfKindness/commonHumanity/mindfulness. Never also emit a reflectionFrame for a Fierce progression
decision. behavior/impact are retired at that boundary; support/provision maps to protect. Card,
tracking, reference guidance, Assistant wording, and model inference are never Fierce evidence.
Never emit mode, action, phase, source, or committed lineage; Swift supplies them and joins reality.
""".strip()

    opening_contract = (
        "Unresolved Fierce inquiry uses responseFocus for one grounded "
        "clarification and omits reflectionFrame/fierceEvidence."
    )
    fierce_completion_contract = (
        "Completing Fierce may add fierceEvidence with behavior/impact and direction=repair|protect|change; "
        "at least behavior or impact must come from the user."
    )
    return f"""
Reflection output carries meaning only. Put the grounded Tender distinction or Synthesis in
responseFocus and optionally repeat that same meaning in reflectionFrame.reflectionDelta. Never
emit mode, action, phase, evidence source, or committed lineage; Swift owns them. Optional new
user-grounded evidence is reflectionFrame.evidenceBasis=["exact user-grounded proposition"].
dimensions may contain selfKindness/commonHumanity/mindfulness as semantic emphasis only.
{opening_contract} {fierce_completion_contract}
Card, tracking, reference guidance, and assistant inference are never Fierce evidence. Swift alone
chooses internal mode/action and preserves provenance.
""".strip()


PLANNER_REFLECTION_FRAME_CONTRACT = _reflection_frame_contract(
    sparse_tender_lineage=False
)
CURRENT_V5_PLANNER_REFLECTION_FRAME_CONTRACT = _reflection_frame_contract(
    sparse_tender_lineage=True
)


PLANNER_PRACTICE_CONTRACT = """
practiceTransition=null or {"transactionID":"","narrativeReferenceID":null,"proposal":{"id":"","kind":"care|repair|protect|change|noAction","content":"","basis":"","status":"pendingConfirmation|confirmed","source":"assistantProposed|userRevised"},"noActionReason":null}. noAction needs content+basis; proposal IDs match transaction and practice-confirmation IDs. Current directReflection uses narrativeReferenceID=null; legacy preserves it. Retired practice arrays/scalars are forbidden.
""".strip()

CURRENT_V5_PRACTICE_CONTRACT = """
For proposePractice, practiceTransition is {"proposal":{"content":"one small action",
"basis":"one exact groundedRealityCandidates.id"},"noActionReason":null}. For resolvePractice,
include only a revised proposal's content/basis, or noActionReason when the person declines/is not
ready; omission means acceptance of the active proposal. Do not emit memoryUpdate.finalNarrative on
resolvePractice: Swift compiles the final narrative from the committed Synthesis and resolved Action.
Never emit kind,
transactionID, narrativeReferenceID, proposal.id, status, or source. Swift derives the internal
category and owns all transaction/provenance metadata. Retired arrays, menus, and scalar practice
fields are forbidden.
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
            "Event Disclosure decides whether the current reality is sufficiently concrete to reflect on. The semantic "
            "operation names the act performed under the committed pre-turn state, not the phase that will begin after "
            "this evidence is merged. While the committed Event core is incomplete, choose clarifyEvent even when the "
            "latest answer completes it; save every grounded function and let Swift project the post-turn Card Consent "
            "state. Choose advanceToCardConsent only when the committed pre-turn Event core was already complete. "
            "Merge committed memory with every grounded function in the latest answer. A usable episode "
            "contains: the focal experience, one basic process relation beyond its endpoint, and the "
            "person's relevant action, response, or omission. These are semantic functions, not a fixed "
            "question checklist, and one answer may provide several. A reported outcome plus an emotion or "
            "broad self-judgment is not enough: never copy the endpoint into eventProcess. If either "
            "function is missing, choose clarifyEvent and ask one natural, easy question for the single missing "
            "function most likely to make this episode reflectable. Prioritize the person's concrete action/response "
            "over error codes, other people's reactions, or extra outcome detail; never combine interview questions. "
            "When the focal experience, one genuine development relation, and relevant action/response/omission become "
            "usable in the current clarifyEvent act, stop adding Event questions; responseFocus should support a brief "
            "transition rather than supply another missing-field question. Do not continue into implementation, troubleshooting, hypothetical alternatives, "
            "or what the person should have done differently. Impact, importance, motive, responsibility, and "
            "self-judgment are optional context and never disclosure gates. In episodeStructure emit only new "
            "grounded items from the latest user message; Swift accumulates them with committed memory. A "
            "non-empty eventProcess or behaviorEvidence is enough; omit an unchanged relation and never "
            "emit status metadata or an empty list for it. The typed "
            "self-criticism statement is separate from episode impacts: when the person states an evaluative "
            "self-judgment or explicit self-directed blame, copy its exact grounded wording only to memoryUpdate.selfCriticalStatement, "
            "as a sibling of episodeStructure rather than a member inside it. Swift derives the persisted "
            "presence summary. A concrete behavior such as ‘I said something hurtful’ is behaviorEvidence, not "
            "selfCriticalStatement; do not turn the conduct into its own judgment endpoint. Never store a "
            "free-floating emotion, worry, self-evaluation, repair response, or intended action as an episode "
            "impact. An explicitly user-described effect on another person or relationship—such as the other "
            "person becoming upset or the relationship remaining in conflict—is a concrete impact and must be "
            "preserved without upgrading it into a verified mental state or causal claim. "
            "memoryUpdate fragment is: "
            + CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE
        )
    if stage == "cardConsent":
        return (
            "Resolve only the pending card consent. Clear acceptance selects "
            "acknowledgeCardConsent; clear refusal selects declineCardConsent; otherwise use "
            "inviteCardConsent. An unqualified affirmative response to the active consent question "
            "resolves consent even when it is brief; brevity is not ambiguity and must never trigger "
            "another invitation. Use inviteCardConsent only for a genuinely unresolved answer, question, "
            "or hesitation. The model never selects a card."
        )
    if stage == "cardReflection":
        return (
            "GOAL: obtain a perceptually understandable but interpretively open scene, then connect it with the current "
            "episode. Choose the act under committed pre-turn Card state; Swift derives the next act after merging. Evidence: "
            + CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE
            + ". OBSERVATION: choose continueCardObservation for the first account and save user-described visible content. "
            "Once the scene is roughly understandable, do not ask what else is visible; Swift opens Development. DEVELOPMENT "
            "is one broad, concrete image-only question about what may happen next. Do not ask what is still open, unresolved, "
            "or hanging, locate an uncertainty, or combine elements into a new interpretation. When latestAnswerContext.purpose="
            "cardDevelopment, choose continueCardDevelopment and extract any supplied evidence; Swift then opens Reality "
            "Connection after this one answer, including a simple possibility or inability to tell. Never seek another ambiguity "
            "or enrich the image. REALITY CONNECTION: first ask one unpresupposed bridge placing the whole user-authored scene "
            "beside the focal episode; do not state an analogy or preselect a similarity, difference, tension, element, or target. "
            "While that invitation is active, judge only whether the answer gives a grounded relation, continuation, difference, "
            "or tension inside the focal reality. The invitation supplies the conversational link: no Card mention, image "
            "restatement, explicit comparison, or fit is required. Never judge Card fit. If the reality relation exists, keep the "
            "current Reality act and emit its realityMapping. cardDevelopmentEvidence is optional enrichment, never a prerequisite; "
            "Swift supplies the committed Card anchor. Emit imageRelation only when the latest user answer revises/adds the image "
            "side. An object/property correspondence alone is not a reality relation; continue once in lived-reality language. "
            "A first no-connection answer permits one scaffold using only user-authored image-side openness and no proposed reality "
            "meaning. Establish and exit once the reality relation exists. Do not seek Card meaning, psychology, responsibility, "
            "solution, or action, and never emit outcome/source/status/confirmation/phase metadata."
        )
    if stage == "directReflection":
        contextual_profiles = request.get("contextualTrackingProfiles")
        contextual_profiles = (
            contextual_profiles if isinstance(contextual_profiles, list) else []
        )
        latest_answer_context = request.get("latestAnswerContext")
        latest_answer_context = (
            latest_answer_context if isinstance(latest_answer_context, dict) else {}
        )
        is_answering_contextual_cue = (
            latest_answer_context.get("purpose") == "contextRelationship"
        )
        grounded_candidates = request.get("groundedRealityCandidates")
        grounded_candidates = (
            grounded_candidates if isinstance(grounded_candidates, list) else []
        )
        grounded_candidate_contract = (
            " GROUNDED REALITY CANDIDATES are a read-only Swift projection of canonical user "
            "evidence: "
            + _encoded(grounded_candidates)
            + ". Their field paths and provenance are facts; they are not preclassified as support, "
            "responsibility, change, or importance. Use one exact candidate id only when its reality "
            "content warrants inspectReality. A correction invalidates only the rejected relation at "
            "its stated scope; it does not erase the candidate's underlying fact."
            if grounded_candidates
            else " No canonical grounded reality candidate is currently projected."
        )
        contextual_contract = (
            " Compact temporal Tracking profiles contain cleaned daily aggregates, personal baselines, units, and coverage. When "
            "eventAnchorDate is present, classify a metric from that exact recentDaily day, or an adjacent observed day only when the exact "
            "day is unobserved; a different day elsewhere in the weekly window cannot make it qualify. When eventAnchorDate is absent, read "
            "the supported recent pattern beside the episode's own recent-period wording. They may add "
            "one concrete, non-redundant background condition around the focal episode; they never establish current state, cause, "
            "diagnosis, capacity, responsibility, excuse, or self-criticism meaning. Lived evidence says what happened; Tracking does "
            "not compete with it. Review the supplied profiles now on every unreviewed eligible exposure. Return exactly one "
            "contextualTrackingDecision and classify every supplied (profileID, metric) pair exactly once in metricEligibility. "
            "Use only status=qualifies|doesNotQualify and a boolean preferred; this is classification, not chain-of-thought. Review is mandatory "
            "in the normal Planner response, while an accidental omission remains pending and must never delay Reflection progression. "
            "Classify each metric independently. A metric qualifies when its timing overlaps or is adjacent to the episode, coverage supports a real pattern rather "
            "than isolated noise, it adds one concrete contextual dimension even if partly overlapping lived description, and it can "
            "be placed beside the episode without first inferring cause, psychology, ability, or responsibility. No direct link to the "
            "event, Card connection, or self-criticism is required. Uncertainty about influence is a reason to let the person judge, "
            "not a reason to mark the metric doesNotQualify. Use doesNotQualify only when timing does not match, coverage is insufficient, "
            "the metric adds no contextual specificity, or showing it would require an unsupported inference. If one or more metrics qualify, "
            "mark exactly one qualifying metric preferred=true; that is the Planner's sole reveal choice. If none qualify, every preferred is false. Omission means unreviewed, "
            "keeps the window open through Tender, and never makes Exploration incomplete or blocks Tender. "
            "Evaluate concrete event-window evidence first: use same-day or adjacent recentDaily values for a dated episode, and the "
            "supported recentDaily pattern across the described period for an episode such as 'recently' or 'these days'. Use "
            "recentMedian as a compact summary and baselineMedian only as secondary context; neither baseline difference nor lack of a "
            "large baseline difference decides relevance by itself. A profile is eligible when one of its metrics supplies a clear "
            "event-window condition; stable sibling metrics in the same grouped profile do not cancel it. "
            "All metrics marked doesNotQualify means reviewed/not used; missing observations stay unknown. A preferred qualifying metric may accompany "
            "the warranted Reflection act. Prefer the clearest ordinary-life pattern when profiles overlap; HRV is eligible but not "
            "a diagnosis or numerical explanation. Writer reveals the selected pattern once in ordinary language and asks only whether "
            "the person sees it as related, partly related, unrelated, or uncertain, without source, coverage, raw series, or analysis. "
            "Only the person's resulting interpretation may enter later Reflection. Context never gates progress or delays Tender."
            if contextual_profiles
            else " No new contextual tracking profile is available; omit contextualTrackingDecision."
        )
        return (
            "Use Swift's read-only reflectionMode and preserve canonical lineage: cardRealityConnection -> "
            "selfCriticismLink -> reflectionFrame -> optional fierceEvidence -> synthesis -> practice. "
            "selfCriticismLink carries the user-grounded difficulty-to-judgment relationship, preferably "
            "{\"groundedDifficulty\":\"difficulty or pattern\"}; Swift joins it to the current judgment and owns metadata. "
            "EXPLORATORY. A user-grounded difficulty-to-judgment relation is enough; sufficiency, not maximum detail, "
            "ends Exploration. Greater specificity is not greater reflective value. Cumulative, gradual, situational, "
            "outcome-based, comparative, explicit-standard, and loose user-described relations all qualify without a cause, "
            "trigger, or precise onset. Keep continueExploratoryReflection as the current act when its patch completes the link; "
            "emit no Tender frame and let Swift project post-turn Tender. Continue only when the relation is absent, revised, "
            "rejected, or assistant-inferred, with one easy clarification. Card, Tracking, referenceGuidance, emotion, impact, "
            "and blockage cannot replace the link; Tracking cannot delay it. referenceGuidance may select an adjacent question "
            "but is never evidence. CONTEXT AND EPISODE. Tracking is an optional, once-only event-context cue, never causation. "
            "Save contextRelationship only from the person's "
            "explicit relation, revision, rejection, or uncertainty. "
            + (
                "This answer addresses the displayed cue: save contextRelationship without changing reflectionMode. If Tender has "
                "no frame, atomically provide its first delta; use related context only as one condition. Do not revise committed "
                "Tender or choose progression solely because the cue was answered. "
                if is_answering_contextual_cue
                else ""
            )
            + "Always emit every new user-grounded episode fact in the same turn, whatever progression does. Include behavior, "
            "process, condition, consequence, constraint, or controllable part; exclude Card, Tracking, guidance, inference, "
            "free-floating emotion, self-evaluation, solutions, and the whole link. A user-described effect on a person or relationship "
            "is an impact, including an emotional effect; preserve its uncertainty. "
            "TENDER. Form a bounded compassionate understanding that keeps difficulty, impact, limits, and responsibility visible "
            "while limiting only unsupported judgment scope. Do not substitute a cause, ability claim, positive function, or ‘不是 X，"
            "而是 Y’. For behavior-specific remorse/blame, use compassionate accountability: keep conduct and impact at their actual "
            "scope; add no global verdict, loss-of-control, unintended-act, hidden-motive, excuse, or opposite positive. Its "
            "reflectionDelta is declarative and requests no new material. The first proposal is not completion. Tender completes on a user-authored account, "
            "acceptance/qualification, or decline; emotional improvement is not required. Only "
            "explicit rejection, misunderstanding, or material revision continues it. Extra detail, distress, uncertainty, '不知道/想不到', "
            "or a dangling-question answer is not revision; do not reconfirm or challenge where the judgment is weakest. "
            "At committed Tender/active Fierce, reflectionProgressionDecision alone owns meaning and semanticOperation is null. Use "
            "{\"meaning\":\"reviseTender\",\"reflectionDelta\":\"revision\"}, "
            "{\"meaning\":\"inspectReality\",\"candidateRef\":\"exact id\"}, or "
            "{\"meaning\":\"synthesize\",\"reflectionDelta\":\"explicit synthesis\"}; omit reflectionFrame. "
            "After accepted Tender, inspectReality is preferred when any committed behavior, impact, responsibility, boundary, support, "
            "repair, protection, or change remains meaningful. One fact suffices; no causal pair or proposed action is required. "
            "responseFocus asks only to confirm, revise, reject, or qualify that candidate; synthesize only when none remains. "
            "FIERCE. Keep latestAnswerContext.referenceID read-only. The active candidate anchors inquiry but does not erase other "
            "canonical user-authored evidence. Before clarifying, inspect the committed episode, user-authored Reality Connection, "
            "confirmed context, and latest answer. Any connected repair/protect/change direction completes Fierce without repetition. "
            "One concrete impact is enough; do not subdivide, rank, or redefine it. Return clarifyFierce plus one concrete responseFocus "
            "only if clarification remains; otherwise completeFierce with nonempty reflectionDelta and fierceDirection, or synthesize "
            "with an explicit delta on decline/no direction. Grounded repair/protect/change ends Fierce; Swift opens Synthesis. "
            "Protection must be user-authored; non-user material cannot ground Fierce or Action. "
            "SYNTHESIS. Integrate only canonical link, Tender, grounded/declined Fierce, and confirmed context. First Synthesis requires "
            "an explicit nonempty delta; Swift never fills it. It may preserve accepted Tender/Fierce meaning but cannot copy the "
            "committed delta verbatim. Revise committed Synthesis only for explicit correction/qualification; "
            "natural acceptance/readiness chooses proposePractice without a second confirmation. "
            "PRACTICE. Propose one small executable experiment grounded by one exact candidate id. noAction requires refusal or no "
            "responsible concrete step. Swift compiles the resolved action and committed Synthesis into Final Narrative. "
            + grounded_candidate_contract
            + " "
            "context patch is: "
            + CURRENT_V5_CONTEXT_HYPOTHESIS_PATCH_SHAPE
            + contextual_contract
        )
    if stage == "optionalAction":
        return (
            "Resolve only the active small action. Preserve the user's accept, revision, or refusal without "
            "adding a second plan. Do not provide memoryUpdate.finalNarrative. Swift atomically compiles Final Narrative "
            "from the already committed Synthesis and the resolved action/noAction. This is one Action→Final Narrative boundary."
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
        rejected_operation = str(correction.get("rejectedOperation") or "unknown")
        payload_failure = str(correction.get("payloadFailure") or "none")
        projection_failure = str(correction.get("projectionFailure") or "none")
        issue = correction.get("issue")
        issue = issue if isinstance(issue, dict) else {}
        field_path = str(issue.get("fieldPath") or "semanticEvidencePatch")
        violation = str(issue.get("violation") or "invalidValue")
        required_conditions = issue.get("requiredConditions")
        required_conditions = required_conditions if isinstance(required_conditions, list) else []
        recovery_policy = str(correction.get("recoveryPolicy") or "repairSameOperation")
        rejected_draft = correction.get("rejectedDraft")
        rejected_draft = rejected_draft if isinstance(rejected_draft, dict) else {}
        rejected_progression = rejected_draft.get("reflectionProgressionDecision")
        rejected_progression = (
            rejected_progression if isinstance(rejected_progression, dict) else {}
        )
        rejected_progression_meaning = str(rejected_progression.get("meaning") or "")
        semantic_memory = request.get("semanticMemory")
        semantic_memory = semantic_memory if isinstance(semantic_memory, dict) else {}
        committed_reflection = semantic_memory.get("reflectionFrame")
        committed_reflection = (
            committed_reflection if isinstance(committed_reflection, dict) else {}
        )
        has_committed_synthesis = (
            str(request.get("reflectionMode") or "") == "synthesis"
            and str(committed_reflection.get("action") or "") == "synthesizeUnderstanding"
        )
        exact_issue_repair = ""
        if (
            str(request.get("reflectionMode") or "") == "tender"
            and rejected_progression_meaning in {"reviseTender", "synthesize"}
            and projection_failure
            in {"tenderFrameMissing", "tenderDeltaMissing", "synthesisFrameMissing", "synthesisDeltaMissing"}
        ):
            exact_issue_repair = (
                " REQUIRED ATOMIC PROGRESSION REPAIR: keep reflectionProgressionDecision.meaning="
                + rejected_progression_meaning
                + ", candidateRef=null, and put the complete revised Tender or explicit Synthesis meaning in that same "
                "object's nonempty reflectionDelta. Omit semanticOperation and memoryUpdate.reflectionFrame. Do not change "
                "the decision or reuse responseFocus as meaning. A first Synthesis may preserve the same bounded semantic "
                "meaning as the committed Tender, but it must express the integration in different wording rather than copy "
                "the committed reflectionDelta, and the Planner must still submit it explicitly in reflectionDelta."
            )
        elif "provideTenderFrame" in required_conditions:
            exact_issue_repair = (
            " REQUIRED TENDER REPAIR: keep the compiled current act and put the actual grounded distinction "
                "in semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta. responseFocus may only tell the Writer how to present that committed meaning; Swift never uses it as semantic fallback. Swift constructs the Tender frame shape and "
            "restores committed provenance; do not reconstruct it. The distinction may limit what the facts "
            "support but cannot assert an opposite positive "
            "conclusion, praise, unaffected ability, or a ruled-out unknown cause. It must preserve the exact "
            "domain, target, time range, degree, certainty, and judgment level of the user's grounded "
            "selfCriticalStatement; never substitute a nearby self-critical proposition."
            )
        elif projection_failure == "reflectionProgressionInvalid":
            if str(request.get("reflectionMode") or "") == "fierce":
                exact_issue_repair = (
                    " REQUIRED FIERCE PROGRESSION REPAIR: return exactly one reflectionProgressionDecision and omit "
                    "semanticOperation and memoryUpdate.reflectionFrame. clarifyFierce keeps the exact "
                    "active Swift-owned candidate, uses null delta/direction, and provides one concrete "
                    "responseFocus. completeFierce colocates nonempty reflectionDelta and "
                    "fierceDirection=repair|protect|change; responseFocus is empty. Swift recovers candidate identity "
                    "and evidence from the active candidate, latest answer, and committed lineage. "
                    "Use synthesize with candidateRef=null and an explicit delta only when the direction is declined "
                    "or no meaningful Fierce direction remains."
                )
            else:
                exact_issue_repair = (
                    " REQUIRED TENDER PROGRESSION REPAIR: return exactly one reflectionProgressionDecision. "
                    "reviseTender and synthesize have candidateRef=null plus a nonempty colocated reflectionDelta. "
                    "inspectReality uses one exact supplied groundedRealityCandidates.id and reflectionDelta=null. "
                    "Omit semanticOperation and memoryUpdate.reflectionFrame because Swift compiles the decision."
                )
        elif projection_failure == "fierceFrameIncomplete":
            exact_issue_repair = (
                " REQUIRED FIERCE REPAIR: replace the partial frame with one atomic reflectionProgressionDecision. "
                "Use completeFierce with nonempty reflectionDelta and fierceDirection when the latest answer grounds "
                "a direction; otherwise use clarifyFierce with one responseFocus. Do not repeat candidateRef or "
                "groundedEvidence; Swift recovers both from canonical state. Omit semanticOperation and "
                "memoryUpdate.reflectionFrame; Swift constructs the existing Fierce frame and post-turn phase."
            )
        elif "provideContextualTrackingDecision" in required_conditions:
            exact_issue_repair = (
            " REQUIRED CONTEXT REVIEW REPAIR: contextual tracking profiles are supplied and this one-shot review "
            "is still pending. Return semanticEvidencePatch.contextualTrackingDecision.metricEligibility and classify "
            "every supplied (profileID, metric) pair exactly once. Use qualifies or doesNotQualify; when any qualifies, "
            "exactly one qualifying metric is preferred=true, otherwise every preferred is false. "
            "Do not invent an ID or postpone the decision. A preferred metric may accompany "
            "continueExploratoryReflection or continueTenderReflection and must preserve the otherwise appropriate operation."
            )
        synthesis_repair_failures = {
            "synthesisFrameMissing",
            "synthesisActionInvalid",
            "synthesisDeltaMissing",
            "synthesisModeInvalid",
            "synthesisEvidenceInvalid",
            "unexpectedFierceEvidence",
        }
        if (
            not exact_issue_repair
            and rejected_operation == "synthesizeDirectReflection"
            and projection_failure == "synthesisDeltaMissing"
            and has_committed_synthesis
        ):
            exact_issue_repair = (
                " REQUIRED SYNTHESIS DISPOSITION REPAIR: re-evaluate only the latest answer against the already committed "
                "Synthesis. If it naturally accepts, affirms, acknowledges, or is ready to continue, choose proposePractice now "
                "and provide one complete semanticEvidencePatch.memoryUpdate.practiceTransition with proposal.content and "
                "proposal.basis. If it explicitly doubts, corrects, rejects, or qualifies the "
                "Synthesis, choose synthesizeDirectReflection and provide a materially different reflectionDelta grounded in "
                "that latest answer. Do not paraphrase or replay the committed Synthesis, and do not require another confirmation."
            )
        if (
            not exact_issue_repair
            and field_path == "semanticEvidencePatch.memoryUpdate.selfCriticismLink"
        ):
            exact_issue_repair = (
                " REQUIRED LINEAGE REPAIR: preserve the warranted current operation and replace only "
                "memoryUpdate.selfCriticismLink with one user-grounded relationship meaning, preferably as "
                "{\"groundedDifficulty\":\"difficulty or pattern in the person's account\"}. Do not reproduce the "
                "canonical endpoint; Swift attaches the current exact selfCriticalStatement. Card mapping, emotion, "
                "blockage, outcome, and paraphrased judgment are not substitutes. If the user evidence does not yet "
                "ground that relation, omit the link and remain in the "
                "current Reflection phase; do not manufacture it."
            )
        if (
            not exact_issue_repair
            and rejected_operation == "synthesizeDirectReflection"
            and projection_failure in synthesis_repair_failures
        ):
            exact_issue_repair = (
                " REQUIRED SYNTHESIS REPAIR: keep semanticOperation=synthesizeDirectReflection and repair only "
                + field_path
                + " according to its violation. Put the actual compact synthesis in semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta; responseFocus is presentation guidance only. "
                "Swift constructs mode, action, committed lineage, dimensions, and Fierce inheritance. The synthesis "
                "must be explicitly supplied by the Planner and use only the committed "
                "selfCriticismLink and Tender understanding; do not introduce a new interpretation, "
                "responsibility, positive opposite, or action. For a first Synthesis it may preserve the same bounded "
                "Tender/Fierce meaning and need not manufacture a different conclusion. Do not reconstruct or paraphrase committed "
                "evidence merely to fill JSON. Do not choose another operation."
            )
        if (
            not exact_issue_repair
            and "followCardEvidenceProgression" in required_conditions
            and payload_failure == "cardObservationEvidenceMissing"
        ):
            exact_issue_repair = (
            " REQUIRED CARD OBSERVATION REPAIR: the latest user message already answers the initial "
            "visible-image invitation. Save its user-described visible people, objects, setting, or action "
            "as a nonempty semanticEvidencePatch.memoryUpdate.cardObservationEvidence.userDescribedElements "
            "array. Keep semanticOperation=continueCardObservation; this correction repairs the current act, and "
            "Swift projects Development afterward. Do not request more inventory or open a new visual dimension."
            )
        correction_contract = (
            "\nONE EXACT STRUCTURAL CORRECTION\nThe preceding draft was not executable. reason="
            + str(correction.get("reason") or "payloadInvalid")
            + "; rejectedOperation="
            + rejected_operation
            + "; payloadFailure="
            + payload_failure
            + "; projectionFailure="
            + projection_failure
            + "; recoveryPolicy="
            + recovery_policy
            + "; issue.fieldPath="
            + field_path
            + "; issue.violation="
            + violation
            + "; issue.requiredConditions="
            + _encoded(required_conditions)
            + ". Repair exactly one semantic act within the narrowed authoritative ALLOWED list above. At a Tender "
            "progression boundary, reflectionProgressionDecision remains the sole semantic authority and Swift compiles "
            "the operation. Otherwise, first determine whether "
            "the executable operation remains rejectedOperation. If it remains the same operation, repair only issue.fieldPath "
            "and the structural dependencies explicitly named by requiredConditions; preserve every other valid "
            "operation-owned field from request.correction.rejectedDraft and do not invent evidence. If the selected "
            "semanticOperation differs from rejectedOperation, this is operation substitution and therefore re-planning, not "
            "field repair: every semantic field owned by the rejected operation is non-authoritative. Discard that old "
            "operation payload and generate the complete sparse semantic payload required by the replacement operation, using "
            "only the latest user answer and committed evidence. Do not preserve an incompatible responseFocus, reflection "
            "contribution, practice contribution, Card contribution, or question merely because it appeared in rejectedDraft. "
            "Repair only the rejected operation when the narrowed "
            "ALLOWED list contains that single operation. When recoveryPolicy=remainInCurrentPhase, "
            "do not recreate the rejected operation or emit a reflectionFrame. Rebuild responseFocus solely "
            "for the corrected operation and discard every question or task from the rejected operation."
            + exact_issue_repair
        )
    reflection_contract = (
        "\nREFLECTION STRUCTURE\n" + CURRENT_V5_PLANNER_REFLECTION_FRAME_CONTRACT
        if stage == "directReflection"
        else ""
    )
    practice_contract = (
        "\nOPTIONAL ACTION STRUCTURE\n" + CURRENT_V5_PRACTICE_CONTRACT
        if stage in {"optionalAction", "narrativeConfirmation"}
        or stage == "directReflection"
        and any(operation in {"proposePractice", "resolvePractice"} for operation in allowed)
        else ""
    )
    card_connection_contract = ""
    if stage == "cardReflection":
        card_connection_contract = """
CARD CONNECTION SHAPE
cardConnectionEvidence is null unless this turn contributes an image-side or reality-side relation. When present it
contains only imageRelation and/or realityMapping. Never emit outcome kind, source, status, confirmation,
phase, or transaction metadata. Swift merges this semantic evidence with committed user evidence and
derives whether the current Card act completes, remains open, accepts, revises, or rejects a candidate.
During an active Reality Connection invitation, a grounded reality-side relation, continuation, difference,
or tension is enough for realityMapping even when the answer never mentions the Card. Do not judge Card fit.
Development evidence is optional enrichment; do not withhold realityMapping because it is absent.
"""
    semantic_memory = request.get("semanticMemory")
    semantic_memory = semantic_memory if isinstance(semantic_memory, dict) else {}
    reflection_mode = request.get("reflectionMode")
    uses_tender_progression = (
        stage == "directReflection"
        and reflection_mode == "tender"
        and isinstance(semantic_memory.get("reflectionFrame"), dict)
    )
    uses_fierce_progression = (
        stage == "directReflection"
        and reflection_mode == "fierce"
        and isinstance(semantic_memory.get("reflectionFrame"), dict)
    )
    uses_synthesis_progression = (
        stage == "directReflection"
        and reflection_mode == "synthesis"
        and "synthesizeDirectReflection" in allowed
    )
    uses_reflection_progression = uses_tender_progression or uses_fierce_progression
    authority_contract = (
        "At this committed Tender boundary, choose exactly one reflectionProgressionDecision from "
        "reviseTender, inspectReality, or synthesize and omit semanticOperation. Swift compiles that decision into one allowed operation."
        if uses_tender_progression
        else (
            "At this active Fierce boundary, choose exactly one reflectionProgressionDecision from "
            "clarifyFierce, completeFierce, or synthesize and omit semanticOperation. Swift compiles that decision into the existing operation."
            if uses_fierce_progression
            else (
                "At committed Synthesis, an explicit correction or qualification uses "
                "reflectionProgressionDecision={\"meaning\":\"synthesize\",\"reflectionDelta\":\"materially revised synthesis\"} "
                "and omits semanticOperation. Natural acceptance/readiness uses semanticOperation=proposePractice and no progression decision."
                if uses_synthesis_progression
                else "Choose one allowed current act in semanticOperation."
            )
        )
    )
    output_operation_contract = (
        "reflectionProgressionDecision is required and semanticOperation is null at this Reflection "
        "boundary."
        if uses_reflection_progression
        else (
            "For a Synthesis correction, reflectionProgressionDecision is required and semanticOperation is null; "
            "for accepted Synthesis, semanticOperation=proposePractice and reflectionProgressionDecision is null."
            if uses_synthesis_progression
            else "semanticOperation is required and reflectionProgressionDecision is null."
        )
    )
    output_reflection_delta_contract = (
        "At committed Tender or active Fierce progression, all progression meaning belongs only to "
        "reflectionProgressionDecision; do not also emit semanticEvidencePatch.memoryUpdate.reflectionFrame. "
        "responseFocus is Writer guidance only for reviseTender or clarifyFierce, and must be empty for completeFierce."
        if uses_reflection_progression or uses_synthesis_progression
        else ""
    )
    system = f"""
CURRENT_V5_CORE_PLANNER

ROLE
Understand the latest user turn and choose the single most useful next conversational operation.
Return semantic evidence, not workflow instructions and not user-facing prose.

AUTHORITY
Allowed semantic operations are exactly: {_encoded(allowed)}.
{authority_contract} Swift alone derives and persists workflow effects.
Emit only the positive JSON shape below.

EVIDENCE
Use user messages and confirmed typed memory only. The latest answer may add several typed relations.
Preserve uncertainty; infer no emotion, motive, personality, diagnosis, responsibility, causality, or
an actual Tracking relationship. The Planner may select one supplied, temporally plausible Tracking
profile as a contextual cue for the person to evaluate, but must not assert that it is related or
causal. memoryUpdate is sparse: omit unchanged fields and never overwrite evidence with
empty/default values. selfCriticalStatement is the sole writable self-criticism evidence: copy the
exact nonempty new evaluative self-judgment or explicit self-directed blame, never an inferred trait
and never the concrete behavior or harm being evaluated; Swift derives presence.
invalidatedInterpretations contains only assistant interpretations explicitly rejected by the person;
append that correction and never reuse it as evidence.

STAGE
{_current_v5_stage_contract(request)}
{reflection_contract}{practice_contract}{card_connection_contract}

OUTPUT
Return exactly one JSON object shaped as:
{CURRENT_V5_PLANNER_JSON_SHAPE}
{output_operation_contract} semanticEvidencePatch.memoryUpdate is an object and may be empty.
Never emit kind, source, status, mode, action, phase, transactionID, confirmation state, or other
protocol metadata; Swift compiles them from the act, committed state, and evidence provenance.
responseFocus is a concise instruction for the Writer; it may contain the one useful question goal
but never a second operation, a task from a rejected or previous operation, an ungrounded
interpretation, or a protocol field. It is current-turn-only Writer guidance, not persistent
semantic state. {output_reflection_delta_contract}{correction_contract}
""".strip()
    user = "CURRENT V5 TURN REQUEST JSON:\n" + _encoded(request)
    return PromptMessages(system=system, user=user)


def _current_v5_writer(payload: dict[str, Any]) -> PromptMessages:
    request = _required_object(payload, "request")
    directive = _required_object(payload, "directive")
    next_prompt = directive.get("nextPrompt")
    next_prompt = next_prompt if isinstance(next_prompt, dict) else {}
    prompt_kind = str(next_prompt.get("kind") or "none")
    reflection_realization = str(directive.get("reflectionRealization") or "standard")
    may_ask_question = directive.get("mayAskQuestion")
    if not isinstance(may_ask_question, bool):
        may_ask_question = prompt_kind in {"openQuestion", "confirmationRequest"}
    question_contract = (
        "End with exactly one natural, easy-to-answer question serving the supplied focus."
        if may_ask_question
        else "Do not add a question."
    )
    rewrite_reason = directive.get("rewriteReason")
    rewrite_contract = (
        "This is a wording-only retry. Keep the same operation, evidence, focus, and question count."
        if isinstance(rewrite_reason, str) and rewrite_reason
        else ""
    )
    operation = str(directive.get("semanticOperation") or "")
    reflection_mode = str(request.get("reflectionMode") or "")
    destination_stage = str(directive.get("destinationStage") or "")
    directive_memory = directive.get("memoryUpdate")
    directive_memory = directive_memory if isinstance(directive_memory, dict) else {}
    projected_reflection_phase = str(directive_memory.get("reflectionPhase") or "")
    next_purpose = str(next_prompt.get("purpose") or "")
    selected_contextual_metric_ref = directive.get("contextualTrackingMetricRef")
    selected_contextual_metric_ref = (
        selected_contextual_metric_ref
        if isinstance(selected_contextual_metric_ref, dict)
        else None
    )
    selected_contextual_metric = directive.get("contextualTrackingMetricEvidence")
    selected_contextual_metric = (
        selected_contextual_metric
        if isinstance(selected_contextual_metric, dict)
        else None
    )
    contextual_tracking_language_contract = ""
    if selected_contextual_metric_ref and selected_contextual_metric:
        contextual_tracking_language_contract = (
            "Write one brief contextual cue in warm, observant, everyday Chinese. It should sound like a thoughtful "
            "companion noticing part of the person's lived context, not like a dashboard reporting a result. Compose it "
            "freshly for this turn in three moves: translate the selected metric into one personal-relative life pattern; "
            "place that pattern beside one concrete, already-grounded part of the focal episode; then ask one simple open "
            "question about what effect the person themselves noticed. The question completes the reply. "
            "Use the metric's actual direction and these everyday semantic targets: sleepDuration becomes sleeping a little "
            "less or more than usual; sleepTiming becomes going to sleep later or earlier than usual; sleepWakeTime becomes "
            "the daily rhythm shifting later or earlier; sleepContinuity becomes sleep being less or more continuous; steps "
            "becomes everyday activity being lower or higher; calendarLoad and calendarEventCount become days feeling fuller, "
            "lighter, or more fragmented; calendarLongestFreeBlock becomes having less or more uninterrupted time; "
            "calendarBackToBackPairs becomes commitments following one another more tightly; calendarEveningScheduled becomes "
            "scheduled demands extending further into the evening. For heartRateVariability, describe only that the recent body "
            "state has differed from the person's usual pattern, and invite them to notice whether pressure or tension felt "
            "different during the grounded episode. "
            "Make the episode clause specific to this conversation by using the person's own concrete activity, object, or "
            "situation from the grounded episode rather than substituting a generic work problem. Vary the opening, rhythm, "
            "and sentence structure so the observation feels "
            "situated rather than templated. Use approximate personal-relative wording such as ‘最近’, ‘那阵子’, and ‘比自己平时……一些’ "
            "only where it sounds natural. "
            "Keep the measurement work backstage. The visible reply contains no technical source or analysis, exact date or "
            "number, calculation, causal claim, diagnosis, or asserted stress conclusion. Never name HRV, heart-rate variability, "
            "autonomic activity, or a physiological score. Present exactly the selected metric, ask only the person's appraisal, "
            "and finish without an answer menu, disclaimer, second reflection question, or later replay of the cue."
        )
    unsupported_positive_function_contract = (
        " Never assign a difficulty, painful experience, self-critical thought, recurring concern, mistake, "
        "limitation, or consequence a beneficial function, positive intention, virtue, lesson, strength, "
        "protection, reminder, motivation, or hidden benefit unless the person explicitly authored that exact function."
    )
    tender_language_contract = (
        "Realize one declarative bounded understanding; request no new material and never retell chronology. Name one concrete "
        "difficulty and its grounded connection to the judgment, then limit only unsupported scope without praise. Revise only an "
        "explicit rejection, correction, or qualification. Otherwise do not replay it or ask about weakness, meaning, emotion, truth, "
        "standards, more pressures, or another confirmation. A question-shaped responseFocus cannot reopen inquiry; at most invite "
        "acceptance, correction, rejection, or qualification. Do not assert that the response is natural, episode-only, unreal, or "
        "unrepresentative of ability unless user-authored. Refer neutrally instead of repeating self-criticism. For behavior-specific "
        "remorse/blame, keep warranted conduct, responsibility, and impact visible; never call it uncontrolled, unintended, protective, "
        "excusable, or evidence of an unaffected ability or positive self."
    )
    tender_language_contract += unsupported_positive_function_contract
    tender_language_contract += (
        " Insufficient evidence only bounds what facts establish; it cannot supply an alternative explanation or unaffected ability. "
        "Never use an exclusive alternative such as ‘不是 X，而是 Y’, or enlarge workload, responsibility, motive, or context beyond "
        "the person's account. Card, referenceGuidance, and tracking cannot supply the Tender understanding."
    )
    if contextual_tracking_language_contract:
        tender_language_contract += (
            " The Planner selected exactly this contextual metric reference "
            + _encoded(selected_contextual_metric_ref)
            + " with this supplied factual metric "
            + _encoded(selected_contextual_metric)
            + ". "
            + contextual_tracking_language_contract
            + " This turn realizes the independent contextual cue only; leave the committed Tender understanding for its own turn."
        )
    operation_contracts = {
        "clarifyEvent": (
            "Ask directly for the one missing focal event, development, or concrete action named by "
            "the directive. When action/response is missing, ask what the person did or did not do; do not substitute an error code, "
            "another person's reaction, emotion detail, or a combined either-or question. Do not ask a meta-conversation question."
        ),
        "advanceToCardConsent": (
            "Use the completed episode for one short grounded bridge, then invite one random reflection card. "
            "If an explicit broad self-critical statement exists in committed memory or this directive's "
            "memoryUpdate, the bridge must acknowledge the specific difficulty or result and distinguish what "
            "it establishes from that broader verdict. Preserve uncertainty: do not deny the verdict as a fact, "
            "supply a positive opposite, praise, reassure, excuse, or infer an unreported emotion. If no broad "
            "self-judgment exists, use only a brief factual bridge. Do not add an Event-analysis question before "
            "or after the invitation, even if responseFocus contains one. The consent question is the only "
            "question in the reply. The card has not been drawn: never describe or predict its image, text, "
            "message, meaning, advice, or likely connection to the episode."
        ),
        "inviteCardConsent": (
            "Clarify only a genuine ambiguity, question, or hesitation about the pending invitation. "
            "Never repeat the invitation after the person has already given an unqualified affirmative "
            "answer, and never turn a brief answer into a request for stronger confirmation."
        ),
        "continueCardObservation": (
            "Invite one free account of what is visibly happening. Do not ask for more inventory after the person has "
            "already described an understandable scene, and do not select posture, gesture, orientation, expression, "
            "emotion, motive, responsibility, importance, symbolism, or another unmentioned dimension for them. Do not "
            "preface the invitation with a summary, abstraction, or interpretation."
        ),
        "continueCardDevelopment": (
            "Ask the sole direct, open image-only question about how the scene may continue or what may happen next. "
            "Use no visible object, setting, or action that the person did not already supply; normally ask directly with no scene inventory. "
            "Use ordinary concrete language. Do not ask what feels open, unresolved, hanging, or equivalent; do not ask "
            "which part, where, or what step is unresolved; do not combine their elements into a new narrative relation; "
            "and do not choose why, cause, "
            "responsibility, feeling, intention, choice, or final outcome as the ambiguity. "
            "Do not preface it with a summary, abstraction, or interpretation. Do not request more objects, action "
            "mechanics, posture, gesture, orientation, body detail, expression, emotion, motive, importance, meaning, or "
            "symbolism; do not introduce examples, dimensions, candidate answers, or a preferred outcome. The person's "
            "answer need not resolve anything. This operation must not be repeated after that answer."
        ),
        "inviteRealityConnection": (
            "Ask one unpresupposed bridge question that places the just-discussed scene back in the focal lived situation "
            "and asks what comes first to the person's mind. In natural Chinese, use the functional shape of ‘把刚才这段画面放回当时的情境里，"
            "你最先想到什么？’, adapting only the factual episode anchor rather than copying it mechanically. "
            "Refer to the scene as a whole; do not restate an individual image property, describe an abstract inner feeling, "
            "or ask whether the image made them feel a particular way. Do not state an analogy before the question, interpret "
            "or summarize the scene, choose an image element, name its real counterpart, preselect a similarity/difference/tension, or "
            "target a particular episode element. Do not ask another "
            "image-only question, introduce another life episode, or offer an example, lesson, solution, or candidate "
            "frame. The person authors the first connection."
        ),
        "continueOpenCardConnection": (
            "Handle the current Reality task. If the person has now offered a plausible reality-internal relation, "
            "preserve it without evaluating it, let the Card recede, and ask one neutral lived-reality Exploration "
            "question about whether and how the grounded difficulty became connected to the exact self-critical "
            "statement. Do not ask for insight, fit, confirmation, lesson, or action. If their latest material remains "
            "only an object or "
            "property correspondence, ask one concrete question entirely in lived-reality language about the focal "
            "episode; do not mention Card elements, similarity, correspondence, or metaphor. If they report no meaningful "
            "connection, keep the existing difficulty handling bounded and do not manufacture one."
        ),
        "offerCardConnectionScaffold": (
            "Do not supply a connection. If the person offered only an object/property correspondence or a generic "
            "shared-property claim, leave image language completely: ask one concrete, easy question about how the "
            "grounded facts, actions, results, constraints, or handling relate inside the focal lived episode. Do not "
            "mention Card elements, ask what is most similar, or improve the analogy. After a first no-connection answer, "
            "offer one open scaffold using only an uncertainty, unresolved relation, or possible development the person "
            "already authored inside the scene. Preserve their modality; add no object, condition, action, channel, or "
            "scene fact. Name only the image-side openness, then ask whether that open structure brings anything to mind "
            "in the focal episode. Do not assign it a reality meaning or suggest an object correspondence, symbolic role, "
            "external help, emotion, lesson, cause, solution, action, or candidate frame."
        ),
        "bypassCardConnectionToDirectReflection": (
            "Accept that no connection came naturally and let the Card recede without interpreting it. Add no scene "
            "element, hypothetical detail, symbol, analogy, candidate mapping, or explanation. Ask the authorized one "
            "neutral, easy question about the focal lived episode so Reflection can continue without the Card."
        ),
        "establishUserAuthoredCardConnection": (
            "Preserve the stated relation as the person's own without evaluating or deepening it, then let the Card "
            "recede. The Reality Connection is complete as soon as a plausible reality-internal relation exists; it "
            "does not need a self-criticism insight. Ask one neutral lived-reality Exploration question about whether "
            "and how the grounded difficulty became connected to the self-critical statement; do not assume a cause or "
            "default to a specific trigger moment. Do not name Card elements, reopen comparison, explain what the "
            "connection means, ask whether it fits, or add an insight, action, Tender interpretation, motive, trait, "
            "or card meaning. Do not recap it as a breakthrough."
        ),
        "acceptCardConnectionCandidate": (
            "Use the accepted frame only to ask neutrally whether and how the grounded difficulty became connected to "
            "the current self-critical statement, without assuming a cause or specific trigger. Do not deepen Card content, solve the real-world task, or add "
            "Tender, personality, motive, advice, or card meaning."
        ),
        "reviseCardConnectionCandidate": (
            "Use the revised frame only to ask neutrally whether and how the grounded difficulty became connected to "
            "the current self-critical statement, without assuming a cause or specific trigger. Do not deepen Card content, solve the real-world task, or "
            "interpret it as Tender, personality, motive, advice, or card meaning."
        ),
        "authorizeCardGuidance": (
            "Use the confirmed frame only to ask neutrally whether and how the grounded difficulty became connected to "
            "the current self-critical statement, without assuming a cause or specific trigger. Do not deepen Card content, solve the real-world task, or add "
            "Tender, personality, motive, advice, or card meaning."
        ),
        "continueExploratoryReflection": (
            "Use the person's projective frame only to help them discover whether and how the exact self-critical "
            "statement became connected to the grounded difficulty. Do not fill a missing relation. Sufficiency, not "
            "maximal specificity, is the stopping criterion. Cumulative, gradual, situational, outcome-based, comparative, "
            "explicit-standard, and user-described loose relations are sufficient when they explain the connection in the "
            "person's own terms. Never convert a cumulative pattern into a demand for one moment, attempt, bug, step, or "
            "exact threshold. When the operation is legitimately still exploratory, ask one easy neutral question only for "
            "the relationship that remains unclear; do not default to onset precision. Never use a "
            "causal-presupposing question that asks how or why a candidate fact made, caused, or led to the judgment, "
            "or whether the judgment happened because of that fact. "
            "Keep attempts separate from their effectiveness, accumulated blockage, and later judgment. Never word "
            "an isolated action as causing self-criticism unless the person explicitly made that link; ignore any "
            "responseFocus that does so and ask from the grounded overall result or pattern instead. "
            "Do not reopen Card meaning, collect a new topic, seek complete causes, soften the judgment, troubleshoot, "
            "or ask about action. If the person says there was no specific trigger and describes accumulated lack of "
            "progress instead, preserve that correction as the relationship and do not rephrase the onset question. If a "
            "dispensable link is unknown, do not rephrase it. referenceGuidance is silent "
            "question-selection support, never reply content or evidence. Honor corrections at their exact scope. "
            + (
                "The Planner selected exactly this contextual metric reference "
                + _encoded(selected_contextual_metric_ref)
                + " with this supplied factual metric "
                + _encoded(selected_contextual_metric)
                + ". "
                + contextual_tracking_language_contract
                + " This contextual question is the whole visible reply; continue Reflection after the person's appraisal. "
                if selected_contextual_metric_ref and selected_contextual_metric
                else (
                    "Exploration has completed and the projected phase is Tender. Briefly carry forward only the grounded "
                    "difficulty-to-judgment relationship and invite the person to continue; do not state a Tender distinction yet. "
                    if projected_reflection_phase == "tender"
                    else "No contextual profile was selected; do not mention tracking or its review. "
                )
            )
            + "Keep Exploration centered on the one unresolved difficulty-to-judgment relationship and do not repeat a recorded relationship."
        ),
        "continueTenderReflection": tender_language_contract,
        "continueTenderGroundedFierceReflection": (
            "Keep the committed Tender understanding present without explaining it again. For an opening or unresolved Fierce act, carry it into one "
            "user-grounded Protect, Provide, Repair, or Motivate inquiry. "
            "When this directive opens Fierce from Tender, responseFocus is the exact Swift-validated groundedRealityCandidate content. "
            "When request.reflectionMode is fierce and this directive contains no new reflectionFrame, the inquiry is legally continuing: "
            "latestAnswerContext.referenceID preserves that same candidate and responseFocus identifies the one remaining clarification. "
            "Use the active candidate only to anchor a genuinely unresolved question; do not expose the reference. The Planner has already "
            "considered other committed evidence before authorizing this question, so use the latest answer and candidate to ask about one "
            "narrow reality-facing part; do not imply that a direction has already formed, switch the inquiry topic, or recap Tender. This may be one behavior, impact, boundary, support condition, repair, protection, or possible "
            "change; a tentative relation between two facts is optional, never required. Make the question answerable by confirming, "
            "revising, rejecting, or qualifying that concrete part. Keep it compact, without a ‘you said/mentioned’ preface or chronology recap. Name the actual "
            "action, condition, person, or result; do not ask the person to identify an abstract issue, "
            "responsibility, boundary, need, behavior pattern, or change from scratch. Once an impact has been named, do not ask the person "
            "to rank its parts, choose which consequence matters more, restate it more specifically, or define ordinary words such as "
            "sadness, disappointment, delay, or conflict. Do not use protocol or therapy language such as "
            "whole-person judgment, reality tension, something worth facing, or a handling approach worth revisiting. When a complete "
            "Fierce frame is present, reflect only the direction the person has now grounded. That direction completes Fierce: do not ask "
            "another Fierce question, request more detail, or open a second repair/protect/change direction. Use one short natural bridge that "
            "lets the next turn put the existing reflection together, while leaving room for a spontaneous correction. Do not quote, emphasize, paraphrase, or otherwise "
            "replay the person's self-critical judgment, replay the Tender distinction, or repackage either through the Card "
            "metaphor. Protection names only a direction the person has explicitly grounded; never assign it as a beneficial "
            "function or positive intention of the difficulty or painful experience. Use ordinary reality language and preserve care "
            "and agency together. Do not state the answer or assign responsibility. Do not produce a plan, step, menu, or "
            "solution; Action comes later and owns what to do next. Card material, "
            "referenceGuidance, and tracking remain background; model inference cannot become need, responsibility, or action evidence."
        ),
        "synthesizeDirectReflection": (
            "Realize the committed reflectionDelta as one compact, negotiable synthesis of the committed reality–self-criticism relation and canonical "
            "Tender distinction. Add Fierce only when its Protect/Provide/Repair/Motivate material was already committed. "
            "Use contextual material only in the person's confirmed wording. Keep every Card object, scene, relation, and "
            "metaphor out of the visible reply; the Card is provenance only. Never quote or paraphrase the self-critical "
            "statement. Add no new fact, motive, trait, diagnosis, "
            "responsibility, positive opposite, advice, or action; referenceGuidance is not synthesis material. "
            "A statement that the evidence does not establish a global judgment must remain that limited statement: never "
            "turn it into a claim that the real explanation is complexity, circumstances, normal difficulty, or unaffected "
            "ability unless that exact alternative was already grounded by the person. "
            "Preserve uncertainty. Use at most three short sentences and do not replay the chronology or list every earlier "
            "answer. An initial Synthesis may preserve the already accepted Tender/Fierce meaning; it does not need a novel conclusion, "
            "but it must realize the explicit nonempty synthesisDelta supplied by the Planner and must not reproduce the committed "
            "Tender/Fierce reflectionDelta verbatim. An in-place "
            "revision states only the changed qualification supported by the latest answer; it must not restate the full prior "
            "Synthesis or the same Tender conclusion. Do not ask what the distinction means or ask the person to judge again whether "
            "their self-criticism is true, weak, or less convincing. Ask only for acceptance, correction, or qualification of this synthesis; "
            "do not invite an Action in the same reply. When revising an already committed Synthesis, never repeat or paraphrase the committed "
            "reflectionDelta or the previous reply as if that were a revision."
        ),
        "proposePractice": (
            "Start directly with exactly the one authorized small action and one short grounded reason for it. Do not "
            "repeat or paraphrase Tender, Synthesis, or the self-critical statement; do not offer a menu, add steps, or "
            "introduce another action. proposal.basis is an exact groundedRealityCandidates.id; resolve it against the request's candidate list and use only "
            "that candidate's reality content as the reason. Never display the internal id. Its reason must "
            "continue the same accepted synthesis relationship and target a confirmed difficulty, goal, behavior, impact, support need, "
            "or constraint. The method may be a new assistant proposal, but it must remain a tentative small experiment rather than a "
            "known solution, and cannot invent a fresh problem or psychological explanation. Never use Card objects or metaphors in the "
            "proposal or basis. Prefer the episode's unresolved reality problem over rehearsing the reflection. The action must be an "
            "observable response in a concrete situation, not writing, repeating, or rehearsing a kinder sentence unless the person "
            "already chose that method. Use noAction only when the person declined action or no responsible concrete step is available; "
            "missing a user-authored method is not a reason for noAction. Keep it easy to "
            "negotiate: ask one natural question that lets the person accept it, make it smaller or revise it, "
            "or decline it without pressure. Ask one open invitation; do not phrase acceptance as an A-or-B choice. "
            "Do not claim that the action will solve the underlying problem."
        ),
        "resolvePractice": (
            "Swift has compiled directive.memoryUpdate.finalNarrative from the already committed Synthesis and resolved Action. Realize those "
            "two components once as a compact final account; do not decide or reconstruct them from transcript, and do not negotiate the action again. "
            "Use no Card material, self-critical wording, new interpretation, or new action, "
            "and invite only correction or confirmation of the narrative. On acceptance, never repeat the proposal or its earlier "
            "confirmation question; move directly to the final narrative. The accepted action appears once as one component, never as "
            "another proposal or negotiation."
        ),
        "completeConversation": (
            "Give one short, warm closing acknowledgment for the completed reflection. Do not summarize the reflection, restate the final "
            "narrative, mention the Card, replay the accepted practice, add advice, suggest a next step, or ask any question. The conversation "
            "is already complete; this reply has no second task. Do not praise, congratulate, or evaluate the person's courage, effort, "
            "progress, insight, or how difficult the reflection was."
        ),
    }
    operation_contract = operation_contracts.get(
        operation,
        "Follow the authorized operation without adding a second conversational task.",
    )
    if operation == "clarifyEvent" and destination_stage == "cardConsent":
        operation_contract = (
            "The current Event act is complete and Swift has projected Card Consent for the next turn. Use at most one "
            "short factual bridge, then invite one random reflection card. Do not ask another Event question, add a "
            "Tender distinction, explain a cause, or preview Card content. The consent question is the only question."
        )
    elif operation == "continueCardObservation" and next_purpose == "cardDevelopment":
        operation_contract = operation_contracts["continueCardDevelopment"]
    elif operation in {"continueCardObservation", "continueCardDevelopment"} and next_purpose == "cardRealityConnection":
        operation_contract = operation_contracts["inviteRealityConnection"]
    elif operation == "continueTenderGroundedFierceReflection" and next_purpose == "synthesisReflection":
        operation_contract = operation_contract + " " + (
            "The person has now grounded one repair, protect, or change direction and Swift has closed Fierce. State only that committed "
            "reality-facing direction in ordinary language, then use one short natural transition toward putting the existing understanding "
            "together. Do not ask another Fierce question, request a reason, implication, detail, confirmation, or action, and do not create "
            "the Synthesis yourself. Leave room only for a spontaneous correction; never expose route names."
        )
    if reflection_realization == "askFierceClarification":
        operation_contract = operation_contract + " " + (
            "This is the one authorized active-Fierce clarification. Ask only the concrete remaining "
            "question in responseFocus; do not close Fierce or bridge ahead."
        )
    elif reflection_realization == "bridgeToSynthesis":
        operation_contract = (
            "The latest answer has completed Fierce and the post-turn phase is Synthesis. State the "
            "committed repair, protection, or change direction once in ordinary language, then add one "
            "short declarative bridge toward putting the existing understanding together. Ask no question, "
            "seek no reason or confirmation, do not reconnect the direction to earlier material, and do not "
            "create Synthesis or Action content. Ignore any stale responseFocus or earlier Fierce task."
        )
    system = f"""
CURRENT_V5_CORE_WRITER

Write one concise, natural Chinese reply for the authorized operation. Do not change its state,
evidence, question purpose, permission, or action. Return only the reply wrapper. responseFocus is a
goal, not evidence; the operation contract outranks it. Ignore incompatible or second tasks and never
infer facts, Card meaning, psychology, cause, or solutions from the focus.

Write warm, idiomatic, unforced Chinese in one to three short sentences. Keep difficulty, limitation,
mistake, and impact visible without reassurance, virtue reframing, excuse, diagnosis, or whole-person
judgment. Hide internal state. Begin with the conversational content, not a fixed acknowledgment or
"you mentioned/said" preface. Do not paraphrase the latest answer merely to demonstrate listening or
narrate progress. Use at most one necessary factual anchor or one compact relation between two grounded facts. Avoid recap–progress–question templates,
"new understanding" claims, meta imagery, and em-dash reveals. Once a relation is stated, use it rather
than renaming it. After Reality Connection, Card material is silent provenance and never appears in
later replies. Never quote or paraphrase stored self-criticism. Committed Tender/Synthesis is context,
not wording to replay, decorate, or translate into a new metaphor.{unsupported_positive_function_contract}

The reply must contain substantive content, never filler. Ask exactly the one required open, low-burden
question without forced either-or choices, candidate answers, or examples; otherwise ask none. Do not repeat the
preceding question or switch to bodily sensations unless introduced and necessary. In reflective turns,
self-compassion acknowledges difficulty without turning it into an unsupported global verdict.

OPERATION-SPECIFIC LANGUAGE
{operation_contract}
{question_contract}
{rewrite_contract}

Return exactly {{"reply":""}}.
""".strip()
    writer_request = request
    if selected_contextual_metric_ref and selected_contextual_metric:
        # Swift has already compiled the exact event-window evidence slice. Withhold the wider
        # profile so Writer cannot drift to another day or sibling metric while verbalizing it.
        writer_request = dict(request)
        writer_request["contextualTrackingProfiles"] = []
    if operation in {"resolvePractice", "completeConversation"}:
        # These operations must not replay a prior proposal from dialogue history. Their complete
        # authorized content is already in the directive (or, for completion, deliberately empty).
        # Keep only the latest user response so the Writer can acknowledge its tone without seeing
        # an earlier action wording as another task.
        recent = writer_request.get("recentMessages")
        recent = recent if isinstance(recent, list) else []
        latest_user = next(
            (
                item
                for item in reversed(recent)
                if isinstance(item, dict) and item.get("role") == "user"
            ),
            None,
        )
        writer_request = dict(writer_request)
        writer_request["recentMessages"] = [latest_user] if latest_user else []
    user = (
        "CURRENT V5 TURN REQUEST JSON:\n"
        + _encoded(writer_request)
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
