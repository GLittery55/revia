from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Literal, Optional, get_args, get_origin
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_-]+$")
    password: str = Field(min_length=10, max_length=128)
    consentAccepted: bool

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.strip().lower()


class LoginIn(BaseModel):
    username: str = Field(min_length=3, max_length=40)
    password: str = Field(min_length=10, max_length=128)


class UserOut(BaseModel):
    id: str
    username: str
    consentVersion: str
    consentedAt: datetime


class StudyAccessOut(BaseModel):
    status: Literal["unassigned", "scheduled", "active", "disabled"]
    isAvailable: bool
    sequence: Optional[Literal["cardFirst", "directFirst"]] = None
    period: Optional[int] = None
    condition: Optional[Literal["cardMediated", "modelAsserted"]] = None
    availableAt: Optional[datetime] = None


class StudyScheduleUpdateIn(BaseModel):
    sequence: Literal["cardFirst", "directFirst"]
    periodOneStartsAt: Optional[datetime] = None
    periodTwoStartsAt: Optional[datetime] = None
    enabled: bool = True


class StudyParticipantOut(BaseModel):
    id: str
    username: str


class StudyScheduleOut(StudyAccessOut):
    userId: str
    username: str
    periodOneStartsAt: Optional[datetime] = None
    periodTwoStartsAt: Optional[datetime] = None
    enabled: bool
    updatedAt: datetime


class SessionCreateIn(BaseModel):
    condition: Literal["cardMediated", "modelAsserted"] = "cardMediated"
    context: dict[str, Any] = Field(default_factory=dict)
    studySequence: Optional[Literal["cardFirst", "directFirst"]] = None
    studyPeriod: Optional[int] = Field(default=None, ge=1, le=2)


class SessionUpdateIn(BaseModel):
    stage: str = Field(min_length=1, max_length=40)
    action: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any] = Field(default_factory=dict)


class SessionCreatedOut(BaseModel):
    sessionId: str
    stage: str


class SessionSummaryOut(BaseModel):
    id: str
    stage: str
    createdAt: datetime
    updatedAt: datetime
    payload: dict[str, Any]


class LLMMessageIn(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str = Field(min_length=1, max_length=50_000)


class LLMChatIn(BaseModel):
    messages: list[LLMMessageIn] = Field(min_length=1, max_length=20)
    maxTokens: int = Field(default=700, ge=50, le=2_000)
    temperature: float = Field(default=0.2, ge=0, le=1)
    agentMode: Literal["fast", "balanced", "deep"] = "balanced"


class LLMTurnPromptIn(BaseModel):
    """Typed current-turn input; trusted prompt text is selected only by the server."""

    promptTask: Literal[
        "planner",
        "plan_critic",
        "writer",
        "writer_critic",
        "writer_revision",
    ]
    promptVersion: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any]
    maxTokens: int = Field(default=700, ge=50, le=2_000)
    temperature: float = Field(default=0.2, ge=0, le=1)


class LLMChatOut(BaseModel):
    content: str


# The provider guarantees JSON syntax. This contract additionally guarantees that a current-v5
# Planner response is decodable by the Swift `CurrentV5PlannerOutput` boundary before the API
# returns HTTP 200. These models are transport validation only: they do not choose an operation,
# interpret evidence, or replace the Swift capability/Gate checks.
class _CurrentV5ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


CurrentV5SemanticOperation = Literal[
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
]


class CurrentV5EpisodeStructurePatch(_CurrentV5ContractModel):
    concreteFacts: Optional[list[str]] = None
    behaviorEvidence: Optional[list[str]] = None
    eventProcess: Optional[list[str]] = None
    possibleContributors: Optional[list[str]] = None
    contextualConstraints: Optional[list[str]] = None
    controllableParts: Optional[list[str]] = None
    impacts: Optional[list[str]] = None
    keyUncertainty: Optional[str] = None


class CurrentV5ContextRelationship(_CurrentV5ContractModel):
    relevance: Literal["related", "partlyRelated", "unrelated", "uncertain"]
    userInterpretation: Optional[str] = None


class CurrentV5TrackingAssessment(_CurrentV5ContractModel):
    cueID: str
    relevance: Literal["related", "partlyRelated", "unrelated", "uncertain"]
    userInterpretation: Optional[str] = None


class CurrentV5TrackingMetricEligibility(_CurrentV5ContractModel):
    profileID: str = Field(min_length=1)
    metric: str = Field(min_length=1)
    status: Literal["qualifies", "doesNotQualify"]
    preferred: bool


class CurrentV5ContextualTrackingDecision(_CurrentV5ContractModel):
    # Turn-local Planner meaning only. Swift verifies that every supplied metric appears exactly
    # once, then compiles the one preferred qualifying metric into the existing 3-state review.
    metricEligibility: list[CurrentV5TrackingMetricEligibility] = Field(min_length=1)


class CurrentV5CardConnectionEvidence(_CurrentV5ContractModel):
    imageRelation: Optional[str] = None
    realityMapping: Optional[str] = None


class CurrentV5PendingCardRealityConnection(_CurrentV5ContractModel):
    imageRelation: str
    candidateRealityMapping: str


class CurrentV5CardObservationEvidence(_CurrentV5ContractModel):
    userDescribedElements: list[str]


class CurrentV5CardDevelopmentEvidence(_CurrentV5ContractModel):
    # Development is a cumulative sparse patch across natural Card turns. Earlier actors remain
    # in Swift semantic memory, so a later continuation must not repeat them merely to cross the
    # transport boundary. Swift still validates and merges the candidate evidence deterministically.
    actorsOrElements: list[str] = Field(default_factory=list)
    projectiveFocus: Optional[str] = None
    relationOrAction: Optional[str] = None
    anticipatedChangeOrChoice: Optional[str] = None


class CurrentV5FierceEvidence(_CurrentV5ContractModel):
    behavior: Optional[str] = None
    impact: Optional[str] = None
    direction: Optional[Literal["repair", "protect", "change"]] = None


class CurrentV5ReflectionFrame(_CurrentV5ContractModel):
    # The model supplies only meaning. Swift assigns provenance, mode, action and phase from the
    # authorized current act plus committed state.
    evidenceBasis: list[str] = Field(default_factory=list)
    dimensions: list[Literal["selfKindness", "commonHumanity", "mindfulness"]] = Field(
        default_factory=list
    )
    reflectionDelta: Optional[str] = None
    fierceEvidence: Optional[CurrentV5FierceEvidence] = None


class CurrentV5PracticeProposal(_CurrentV5ContractModel):
    content: str
    basis: str


class CurrentV5PracticeTransition(_CurrentV5ContractModel):
    proposal: Optional[CurrentV5PracticeProposal] = None
    noActionReason: Optional[
        Literal["userDeclined", "userNotReady", "insufficientSupportedMaterial"]
    ] = None


class CurrentV5SemanticMemoryUpdate(_CurrentV5ContractModel):
    situationUnderstanding: Optional[str] = None
    selfCriticalStatement: Optional[str] = None
    # Meaning-only transport. Providers may express the lived-difficulty-to-judgment relation as
    # a legacy string or as JSON structure. The backend deliberately preserves that syntax: Swift
    # owns the canonical stored link and drops any shape whose meaning is not unique.
    selfCriticismLink: Optional[Any] = None
    episodeStructure: Optional[CurrentV5EpisodeStructurePatch] = None
    contextRelationship: Optional[CurrentV5ContextRelationship] = None
    trackingAssessments: Optional[list[CurrentV5TrackingAssessment]] = None
    pendingCardRealityConnection: Optional[CurrentV5PendingCardRealityConnection] = None
    cardObservationEvidence: Optional[CurrentV5CardObservationEvidence] = None
    cardDevelopmentEvidence: Optional[CurrentV5CardDevelopmentEvidence] = None
    reflectionFrame: Optional[CurrentV5ReflectionFrame] = None
    invalidatedInterpretations: Optional[list[str]] = None
    finalNarrative: Optional[str] = None
    practiceTransition: Optional[CurrentV5PracticeTransition] = None


class CurrentV5SemanticEvidencePatch(_CurrentV5ContractModel):
    # An operation may carry no new semantic evidence. Treat an omitted update exactly like the
    # explicit empty sparse patch that Swift already accepts; operation-owned evidence remains
    # required by the Swift Gate when that operation actually needs it.
    memoryUpdate: CurrentV5SemanticMemoryUpdate = Field(
        default_factory=CurrentV5SemanticMemoryUpdate
    )
    cardConnectionEvidence: Optional[CurrentV5CardConnectionEvidence] = None
    contextualTrackingDecision: Optional[CurrentV5ContextualTrackingDecision] = None


class CurrentV5ReflectionProgressionDecision(_CurrentV5ContractModel):
    # One turn-local semantic transaction. Understanding/direction content is colocated with the
    # decision; Swift compiles it into the existing frame, operation and phase without a second
    # owner or a second workflow operation.
    meaning: Literal[
        "reviseTender",
        "inspectReality",
        "clarifyFierce",
        "completeFierce",
        "synthesize",
    ]
    # Decode-only compatibility for inspectReality. Active Fierce identity is Swift-owned and is
    # recovered from the pre-turn canonical nextPrompt/candidate projection.
    candidateRef: Optional[str] = None
    reflectionDelta: Optional[str] = None
    fierceDirection: Optional[Literal["repair", "protect", "change"]] = None
    # Decode-only legacy metadata. Swift derives Fierce evidence from the active canonical
    # candidate and latest user answer; this value has no current semantic authority.
    groundedEvidence: Optional[str] = None


class CurrentV5ReflectionTurnOutcome(_CurrentV5ContractModel):
    # A flat semantic report, deliberately not a discriminated union. The backend accepts sparse
    # parseable meaning; Swift validates phase-specific completeness and compiles the operation.
    # Do not reject a parseable semantic report at the provider boundary because its tag is
    # absent or unfamiliar. The Swift compiler/Gate owns the closed vocabulary and the single
    # correction path; the backend owns only JSON shape and alias normalization.
    # All nested values cross the backend as JSON syntax. Swift performs the closed-vocabulary,
    # unique-text, candidate-reference, and phase-completeness checks. This prevents a parseable
    # model response such as {"tenderDelta":{"reflectionDelta":"..."}} from becoming a 502
    # before the semantic compiler can normalize it or request one correction.
    outcome: Optional[Any] = None
    # Exploration-completion relationship meaning. Swift attaches the canonical persisted
    # selfCriticalStatement and compiles the canonical link representation.
    selfCriticismLink: Optional[Any] = None
    tenderDelta: Optional[Any] = None
    synthesisDelta: Optional[Any] = None
    fierceDelta: Optional[Any] = None
    realityCandidate: Optional[Any] = None
    fierceDirection: Optional[Any] = None


class CurrentV5PlannerContract(_CurrentV5ContractModel):
    # Operation authorization and legacy alias resolution belong to Swift. The backend transports
    # the model's semantic act as text and never rewrites it from capability or payload metadata.
    semanticOperation: Optional[str] = None
    semanticEvidencePatch: CurrentV5SemanticEvidencePatch
    reflectionProgressionDecision: Optional[CurrentV5ReflectionProgressionDecision] = None
    reflectionTurnOutcome: Optional[CurrentV5ReflectionTurnOutcome] = None
    # responseFocus shapes language but never owns workflow state. Swift still requires a nonempty
    # focus for operations such as clarifyEvent whose projected question cannot be derived safely.
    responseFocus: Optional[str] = None


class CurrentV5PlannerContractError(ValueError):
    def __init__(self, *, field_path: str, violation: str) -> None:
        super().__init__(f"{field_path}: {violation}")
        self.field_path = field_path
        self.violation = violation


_CURRENT_V5_PROTOCOL_RESIDUE_FIELDS = frozenset(
    {
        "requestedStage",
        "stage",
        "phase",
        "reflectionPhase",
        "reflectionMode",
        "replyIntent",
        "intent",
        "purpose",
        "nextPrompt",
        "latestAnswerContext",
        "localAction",
        "confirmation",
        "resolvedConfirmation",
        "replyGuidance",
        "cardReferenceSelection",
        "pendingQuestionPurpose",
        "pendingConfirmationTarget",
        "clearPendingQuestionPurpose",
        "contextCueOffered",
        "cardImageRelation",
        "cardRealityMapping",
        "cardRealityMappingSource",
        "cardInterpretiveTension",
        "cardNegotiatedMeaning",
        "candidateBridgeResolvedAt",
        "candidUnderstanding",
        "fierceUnderstanding",
        "practiceOptions",
        "practiceKind",
        "selectedPractice",
        # Persisted/read-only summary state. The current-v5 Planner owns only the grounded
        # statement; Swift derives presence deterministically from a nonempty statement.
        "selfCriticismStatus",
    }
)

_CURRENT_V5_TOP_LEVEL_OWNERS = frozenset(
    {
        "semanticOperation",
        "reflectionProgressionDecision",
        "reflectionTurnOutcome",
        "responseFocus",
    }
)
_CURRENT_V5_PATCH_OWNERS = frozenset(
    {
        "cardConnectionEvidence",
        # Decode-only alias. It is consumed before typed transport validation and never appears in
        # canonical output.
        "cardConnectionTurnOutcome",
        "contextualTrackingDecision",
    }
)
_CURRENT_V5_MEMORY_OWNERS = frozenset(CurrentV5SemanticMemoryUpdate.model_fields)
_CURRENT_V5_NESTED_MEMORY_FIELDS: dict[str, frozenset[str]] = {
    "episodeStructure": frozenset(CurrentV5EpisodeStructurePatch.model_fields),
    "contextRelationship": frozenset(CurrentV5ContextRelationship.model_fields),
    "pendingCardRealityConnection": frozenset(
        CurrentV5PendingCardRealityConnection.model_fields
    ),
    "cardObservationEvidence": frozenset(CurrentV5CardObservationEvidence.model_fields),
    "cardDevelopmentEvidence": frozenset(CurrentV5CardDevelopmentEvidence.model_fields),
    "reflectionFrame": frozenset(CurrentV5ReflectionFrame.model_fields),
    "practiceTransition": frozenset(CurrentV5PracticeTransition.model_fields),
}


def _merge_unique_value(
    target: dict[str, Any],
    *,
    key: str,
    value: Any,
    field_path: str,
) -> None:
    if key in target and target[key] != value:
        raise CurrentV5PlannerContractError(
            field_path=field_path,
            violation="duplicate_conflict",
        )
    target[key] = value


def _merge_object_candidates(
    candidates: list[dict[str, Any]],
    *,
    field_path: str,
) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for candidate in candidates:
        for key, value in candidate.items():
            _merge_unique_value(
                merged,
                key=key,
                value=value,
                field_path=f"{field_path}.{key}",
            )
    return merged


def _relocate_uniquely_owned_fields(
    *,
    containers: list[dict[str, Any]],
    owner: dict[str, Any],
    owned_fields: frozenset[str],
    owner_path: str,
) -> None:
    for key in owned_fields:
        occurrences: list[Any] = []
        for container in containers:
            if key in container:
                occurrences.append(container.pop(key))
        for value in occurrences:
            _merge_unique_value(
                owner,
                key=key,
                value=value,
                field_path=f"{owner_path}.{key}" if owner_path else key,
            )


def _lift_misnested_owned_fields(memory: dict[str, Any]) -> None:
    """Lift only fields whose current-v5 owner is mechanically unique.

    A nested model keeps its own declared fields. If a provider puts an envelope or memory field
    inside that object, moving the unchanged value is structural canonicalization, not semantic
    inference. Fields with no current-v5 owner are discarded by the final typed projection; a
    supplied value for a known field remains authoritative and is still validated strictly.
    """

    owned = _CURRENT_V5_TOP_LEVEL_OWNERS | _CURRENT_V5_PATCH_OWNERS | _CURRENT_V5_MEMORY_OWNERS
    for container_key, allowed_nested_fields in _CURRENT_V5_NESTED_MEMORY_FIELDS.items():
        nested = memory.get(container_key)
        if not isinstance(nested, dict):
            continue
        for key in list(nested):
            if key in _CURRENT_V5_PROTOCOL_RESIDUE_FIELDS:
                nested.pop(key)
                continue
            if key not in allowed_nested_fields and key in owned:
                _merge_unique_value(
                    memory,
                    key=key,
                    value=nested.pop(key),
                    field_path=f"semanticEvidencePatch.memoryUpdate.{key}",
                )


def _project_optional_patch_owner(
    *,
    patch: dict[str, Any],
    alias_containers: list[dict[str, Any]],
    key: str,
) -> None:
    """Resolve a syntax-only optional patch owner without giving aliases equal authority.

    A value already written at its canonical patch location wins unchanged. Otherwise one
    misplaced value (or several equal misplaced values) can be moved mechanically. Conflicting
    misplaced aliases carry no unique meaning, so the optional field is omitted and Swift keeps
    treating the decision as not supplied.
    """

    owner_is_present = key in patch
    aliases: list[Any] = []
    for container in alias_containers:
        if key in container:
            aliases.append(container.pop(key))

    if owner_is_present or not aliases:
        return

    first = aliases[0]
    if all(alias == first for alias in aliases[1:]):
        patch[key] = first
    else:
        patch.pop(key, None)


def _canonicalize_current_v5_ownership(decoded: dict[str, Any]) -> dict[str, Any]:
    """Normalize the three current-v5 ownership envelopes in one deterministic pass."""

    root = dict(decoded)
    raw_patch = root.pop("semanticEvidencePatch", {})
    if not isinstance(raw_patch, dict):
        root["semanticEvidencePatch"] = raw_patch
        return root
    patch = dict(raw_patch)

    memory_candidates: list[dict[str, Any]] = []
    invalid_memory: Any = None
    has_invalid_memory = False
    for container in (root, patch):
        if "memoryUpdate" not in container:
            continue
        candidate = container.pop("memoryUpdate")
        if isinstance(candidate, dict):
            memory_candidates.append(dict(candidate))
        elif has_invalid_memory and invalid_memory != candidate:
            raise CurrentV5PlannerContractError(
                field_path="semanticEvidencePatch.memoryUpdate",
                violation="duplicate_conflict",
            )
        else:
            invalid_memory = candidate
            has_invalid_memory = True

    if has_invalid_memory:
        if memory_candidates:
            raise CurrentV5PlannerContractError(
                field_path="semanticEvidencePatch.memoryUpdate",
                violation="duplicate_conflict",
            )
        memory: Any = invalid_memory
    else:
        tracking_alias_containers = [root]
        for candidate in memory_candidates:
            tracking_alias_containers.append(candidate)
            for nested_key in _CURRENT_V5_NESTED_MEMORY_FIELDS:
                nested = candidate.get(nested_key)
                if not isinstance(nested, dict):
                    continue
                nested_copy = dict(nested)
                candidate[nested_key] = nested_copy
                tracking_alias_containers.append(nested_copy)
        _project_optional_patch_owner(
            patch=patch,
            alias_containers=tracking_alias_containers,
            key="contextualTrackingDecision",
        )
        memory = _merge_object_candidates(
            memory_candidates,
            field_path="semanticEvidencePatch.memoryUpdate",
        )

    if isinstance(memory, dict):
        _lift_misnested_owned_fields(memory)
        containers = [root, patch, memory]
        _relocate_uniquely_owned_fields(
            containers=containers,
            owner=root,
            owned_fields=_CURRENT_V5_TOP_LEVEL_OWNERS,
            owner_path="",
        )
        _relocate_uniquely_owned_fields(
            containers=containers,
            owner=patch,
            owned_fields=_CURRENT_V5_PATCH_OWNERS,
            owner_path="semanticEvidencePatch",
        )
        _relocate_uniquely_owned_fields(
            containers=containers,
            owner=memory,
            owned_fields=_CURRENT_V5_MEMORY_OWNERS,
            owner_path="semanticEvidencePatch.memoryUpdate",
        )
        for container in containers:
            for key in _CURRENT_V5_PROTOCOL_RESIDUE_FIELDS:
                container.pop(key, None)
        patch["memoryUpdate"] = memory
    else:
        patch["memoryUpdate"] = memory

    root["semanticEvidencePatch"] = patch
    return root


def _canonicalize_current_v5_semantic_aliases(decoded: dict[str, Any]) -> dict[str, Any]:
    """Move old semantic aliases without compiling any protocol metadata.

    This pass may preserve or merge unchanged semantic text. It never chooses or repairs an
    operation and never creates kind/source/status/mode/action/phase/transaction state.
    """

    patch = decoded.get("semanticEvidencePatch")
    if not isinstance(patch, dict):
        return decoded
    memory = patch.get("memoryUpdate")
    if not isinstance(memory, dict):
        return decoded

    connection_candidates: list[dict[str, Any]] = []
    current = patch.get("cardConnectionEvidence")
    if isinstance(current, dict):
        connection_candidates.append(current)
    legacy_outcome = patch.pop("cardConnectionTurnOutcome", None)
    if isinstance(legacy_outcome, dict):
        nested = legacy_outcome.get("connection")
        connection_candidates.append(nested if isinstance(nested, dict) else legacy_outcome)
    legacy_memory_connection = memory.pop("cardRealityConnection", None)
    if isinstance(legacy_memory_connection, dict):
        connection_candidates.append(legacy_memory_connection)

    semantic_connection: dict[str, Any] = {}
    for candidate in connection_candidates:
        for key in ("imageRelation", "realityMapping"):
            if key in candidate:
                _merge_unique_value(
                    semantic_connection,
                    key=key,
                    value=candidate[key],
                    field_path=f"semanticEvidencePatch.cardConnectionEvidence.{key}",
                )
    if semantic_connection:
        patch["cardConnectionEvidence"] = semantic_connection
    else:
        patch.pop("cardConnectionEvidence", None)

    frame = memory.get("reflectionFrame")
    if isinstance(frame, dict):
        shaped_frame = dict(frame)
        raw_basis = shaped_frame.get("evidenceBasis")
        if isinstance(raw_basis, list):
            shaped_frame["evidenceBasis"] = [
                item.get("content") if isinstance(item, dict) else item
                for item in raw_basis
                if isinstance(item, str)
                or isinstance(item, dict) and "content" in item
            ]
        memory["reflectionFrame"] = shaped_frame

    return decoded


_CURRENT_V5_PROGRESSION_MEANINGS = frozenset(
    {
        "reviseTender",
        "inspectReality",
        "clarifyFierce",
        "completeFierce",
        "synthesize",
    }
)
_CURRENT_V5_PROGRESSION_MEANING_ALIASES = ("decision", "value")

def _canonicalize_current_v5_progression_syntax(decoded: dict[str, Any]) -> dict[str, Any]:
    """Normalize only mechanically unique progression transport syntax.

    The model still decides the progression meaning and Swift still compiles that meaning into an
    operation. This pass only prevents a valid, unambiguous meaning from becoming an HTTP failure
    because a provider returned the enum as a scalar, a one-item list, a JSON-encoded value, or
    under a known syntax alias. Unknown and ambiguous values remain strict validation failures.
    """

    if "reflectionProgressionDecision" not in decoded:
        return decoded

    def normalize(value: Any) -> Any:
        if isinstance(value, str):
            stripped = value.strip()
            if stripped in _CURRENT_V5_PROGRESSION_MEANINGS:
                return {"meaning": stripped}
            try:
                nested = json.loads(stripped)
            except (TypeError, json.JSONDecodeError):
                return value
            if nested == value:
                return value
            return normalize(nested)

        if isinstance(value, list):
            return normalize(value[0]) if len(value) == 1 else value

        if not isinstance(value, dict):
            return value

        shaped = dict(value)
        if "meaning" in shaped:
            for alias in _CURRENT_V5_PROGRESSION_MEANING_ALIASES:
                shaped.pop(alias, None)
            return shaped

        alias_values = [
            shaped[alias]
            for alias in _CURRENT_V5_PROGRESSION_MEANING_ALIASES
            if alias in shaped
        ]
        normalized_aliases = [normalize(alias) for alias in alias_values]
        meanings = [
            candidate.get("meaning")
            for candidate in normalized_aliases
            if isinstance(candidate, dict)
            and candidate.get("meaning") in _CURRENT_V5_PROGRESSION_MEANINGS
        ]
        if meanings and all(meaning == meanings[0] for meaning in meanings[1:]):
            shaped["meaning"] = meanings[0]
            for alias in _CURRENT_V5_PROGRESSION_MEANING_ALIASES:
                shaped.pop(alias, None)
        return shaped

    projected = dict(decoded)
    projected["reflectionProgressionDecision"] = normalize(
        projected["reflectionProgressionDecision"]
    )
    decision = projected.get("reflectionProgressionDecision")
    patch = projected.get("semanticEvidencePatch")
    patch = patch if isinstance(patch, dict) else None
    memory = patch.get("memoryUpdate") if patch is not None else None
    memory = memory if isinstance(memory, dict) else None
    if isinstance(decision, dict):
        meaning = decision.get("meaning")
        if meaning in {"inspectReality", "clarifyFierce"}:
            # Inquiry has no semantic conclusion. These are redundant fields, not another
            # authority capable of turning the inquiry into a completed Reflection act.
            decision.pop("reflectionDelta", None)
            decision.pop("fierceDirection", None)
            decision.pop("groundedEvidence", None)
            if meaning == "clarifyFierce":
                decision.pop("candidateRef", None)
            if memory is not None:
                memory.pop("reflectionFrame", None)
        elif meaning in {"reviseTender", "synthesize", "completeFierce"} and memory is not None:
            legacy_frame = memory.get("reflectionFrame")
            legacy_delta = (
                legacy_frame.get("reflectionDelta")
                if isinstance(legacy_frame, dict)
                else None
            )
            legacy_fierce = (
                legacy_frame.get("fierceEvidence")
                if isinstance(legacy_frame, dict)
                else None
            )
            legacy_direction = (
                legacy_fierce.get("direction")
                if isinstance(legacy_fierce, dict)
                else None
            )
            # The colocated field is canonical. If it is absent, move the unique old semantic
            # alias once; if present (including null/empty), discard the legacy competitor.
            if "reflectionDelta" not in decision and legacy_delta is not None:
                decision["reflectionDelta"] = legacy_delta
            if meaning == "completeFierce":
                # Direction and delta are colocated Planner meaning. A former full frame is a
                # decode-only alias: move its one explicit direction before removing that
                # duplicate container. The canonical owner still wins whenever it is present,
                # including an explicit null; the backend never chooses a direction itself.
                if "fierceDirection" not in decision and legacy_direction is not None:
                    decision["fierceDirection"] = legacy_direction
                decision.pop("candidateRef", None)
                decision.pop("groundedEvidence", None)
            if "reflectionDelta" in decision or (
                meaning == "completeFierce" and "fierceDirection" in decision
            ):
                memory.pop("reflectionFrame", None)
    return projected


def _canonicalize_current_v5_reflection_outcome_syntax(
    decoded: dict[str, Any],
) -> dict[str, Any]:
    """Normalize mechanically unique phase-outcome syntax without choosing its meaning."""

    if "reflectionTurnOutcome" not in decoded:
        return decoded

    def normalize(value: Any) -> Any:
        if isinstance(value, str):
            stripped = value.strip()
            try:
                nested = json.loads(stripped)
            except (TypeError, json.JSONDecodeError):
                # Any nonempty scalar is mechanically unique syntax. Swift decides whether it is
                # a known semantic outcome; an empty scalar remains an invalid sparse object.
                return {"outcome": stripped} if stripped else {}
            return normalize(nested) if nested != value else value
        if isinstance(value, list):
            return normalize(value[0]) if len(value) == 1 else value
        if not isinstance(value, dict):
            return value

        shaped = dict(value)
        if "outcome" not in shaped:
            aliases = [shaped.get(key) for key in ("kind", "decision") if key in shaped]
            aliases = [item.strip() for item in aliases if isinstance(item, str) and item.strip()]
            if aliases and all(item == aliases[0] for item in aliases[1:]):
                shaped["outcome"] = aliases[0]
        shaped.pop("kind", None)
        shaped.pop("decision", None)
        candidate = shaped.get("realityCandidate")
        if isinstance(candidate, dict):
            candidate = dict(candidate)
            if "reference" not in candidate and isinstance(candidate.get("referenceID"), str):
                candidate["reference"] = candidate["referenceID"]
            candidate.pop("referenceID", None)
            shaped["realityCandidate"] = candidate
        return shaped

    projected = dict(decoded)
    projected["reflectionTurnOutcome"] = normalize(projected["reflectionTurnOutcome"])
    canonical_outcome = projected["reflectionTurnOutcome"]
    if isinstance(canonical_outcome, dict) and "selfCriticismLink" in canonical_outcome:
        patch = projected.get("semanticEvidencePatch")
        memory = patch.get("memoryUpdate") if isinstance(patch, dict) else None
        if isinstance(memory, dict):
            # Exploration completion has one canonical relationship owner. Removing the parallel
            # alias is mechanical ownership projection; the backend does not interpret its text.
            memory.pop("selfCriticismLink", None)
    # The phase-local outcome is the canonical meaning owner. A concurrently returned legacy
    # progression object is duplicate transport residue and cannot compete with it.
    projected.pop("reflectionProgressionDecision", None)
    return projected


def _current_v5_model_from_annotation(annotation: Any) -> Optional[type[BaseModel]]:
    try:
        if isinstance(annotation, type) and issubclass(annotation, BaseModel):
            return annotation
    except TypeError:
        pass
    for member in get_args(annotation):
        nested = _current_v5_model_from_annotation(member)
        if nested is not None:
            return nested
    return None


def _current_v5_list_member_model(annotation: Any) -> Optional[type[BaseModel]]:
    if get_origin(annotation) is list:
        arguments = get_args(annotation)
        return _current_v5_model_from_annotation(arguments[0]) if arguments else None
    for member in get_args(annotation):
        nested = _current_v5_list_member_model(member)
        if nested is not None:
            return nested
    return None


def _strip_unowned_current_v5_fields(value: Any, model: type[BaseModel]) -> Any:
    """Keep only declared fields while preserving every supplied authoritative value unchanged."""

    if not isinstance(value, dict):
        return value
    projected: dict[str, Any] = {}
    for key, item in value.items():
        field = model.model_fields.get(key)
        if field is None:
            continue
        annotation = field.annotation
        member_model = _current_v5_list_member_model(annotation)
        nested_model = _current_v5_model_from_annotation(annotation)
        if member_model is not None and isinstance(item, list):
            projected[key] = (
                [_strip_unowned_current_v5_fields(member, member_model) for member in item]
            )
        elif nested_model is not None:
            projected[key] = _strip_unowned_current_v5_fields(item, nested_model)
        else:
            projected[key] = item
    return projected


def canonicalize_current_v5_planner_contract(
    content: str,
    *,
    allowed_semantic_operations: Optional[list[str]] = None,
) -> str:
    """Project parseable output onto the one writable current-v5 surface, then validate it.

    Fields without a current-v5 owner are discarded, while malformed or conflicting values for
    known authoritative fields remain strict contract failures. `exclude_unset` preserves
    sparse-patch omission rather than expanding absent fields into destructive defaults.
    """

    try:
        decoded = json.loads(content)
    except (TypeError, json.JSONDecodeError) as error:
        raise CurrentV5PlannerContractError(
            field_path="root",
            violation="invalid_json",
        ) from error
    if not isinstance(decoded, dict):
        raise CurrentV5PlannerContractError(
            field_path="root",
            violation="json_not_object",
        )

    projected = _canonicalize_current_v5_ownership(decoded)
    # Kept in the public function signature for call-site compatibility only. Capability and
    # operation resolution belong exclusively to Swift and are deliberately not consulted here.
    _ = allowed_semantic_operations
    projected = _canonicalize_current_v5_semantic_aliases(projected)
    projected = _canonicalize_current_v5_reflection_outcome_syntax(projected)
    projected = _canonicalize_current_v5_progression_syntax(projected)
    projected = _strip_unowned_current_v5_fields(projected, CurrentV5PlannerContract)
    # A decision containing only retired, unowned metadata has no remaining semantic content.
    # Drop the optional envelope instead of turning legacy syntax into a required-field failure.
    projected_patch = projected.get("semanticEvidencePatch")
    if isinstance(projected_patch, dict) and projected_patch.get(
        "contextualTrackingDecision"
    ) == {}:
        projected_patch.pop("contextualTrackingDecision", None)
    elif isinstance(projected_patch, dict):
        decision = projected_patch.get("contextualTrackingDecision")
        eligibility = decision.get("metricEligibility") if isinstance(decision, dict) else None
        if isinstance(eligibility, list):
            for item in eligibility:
                if isinstance(item, dict):
                    # Missing preference is syntax, not a semantic no-use decision. Swift may
                    # compile the sole qualifying metric; ambiguous multi-qualifier output still
                    # follows the existing one-correction Gate path.
                    item.setdefault("preferred", False)

    try:
        validated = CurrentV5PlannerContract.model_validate(projected)
    except ValidationError as error:
        first = error.errors(include_url=False, include_input=False)[0]
        location = first.get("loc") or ("root",)
        field_path = ".".join(str(part) for part in location)
        raise CurrentV5PlannerContractError(
            field_path=field_path,
            violation=str(first.get("type") or "invalid"),
        ) from error
    return json.dumps(
        validated.model_dump(mode="json", exclude_unset=True),
        ensure_ascii=False,
        separators=(",", ":"),
    )


def validate_current_v5_planner_contract(content: str) -> None:
    """Validate structure only; Swift remains the sole semantic capability authority."""

    canonicalize_current_v5_planner_contract(content)
