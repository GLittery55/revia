from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Annotated, Any, Literal, Optional, Union, get_args, get_origin
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    TypeAdapter,
    ValidationError,
    field_serializer,
    field_validator,
)


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

    @field_serializer("consentedAt")
    def serialize_consented_at(self, value: datetime) -> str:
        """Keep auth responses compatible with older Apple ISO-8601 decoders."""
        normalized = (
            value.replace(tzinfo=timezone.utc)
            if value.tzinfo is None
            else value.astimezone(timezone.utc)
        )
        return normalized.replace(microsecond=0).isoformat().replace("+00:00", "Z")


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
# returns HTTP 200. The backend also checks declared operation-specific semantic branches against
# their branch-owned payload. It never chooses the branch, interprets user prose, or replaces the
# Swift capability/Gate checks.
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
    # Swift-facing evidence after the backend consumes the turn-local Reality decision branch.
    imageRelation: Optional[str] = None
    realityMapping: Optional[str] = None


class CurrentV5RealityConnectionEstablished(_CurrentV5ContractModel):
    branch: Literal["connectionEstablished"]
    imageRelation: Optional[str] = None
    realityMapping: str

    @field_validator("realityMapping")
    @classmethod
    def require_nonempty_reality_mapping(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("realityMapping must be nonempty")
        return value


class CurrentV5RealityConnectionNeedsMoreExploration(_CurrentV5ContractModel):
    branch: Literal["needsMoreExploration"]
    imageRelation: Optional[str] = None
    realityMapping: None = None


CurrentV5RealityConnectionDecision = Annotated[
    Union[
        CurrentV5RealityConnectionEstablished,
        CurrentV5RealityConnectionNeedsMoreExploration,
    ],
    Field(discriminator="branch"),
]

_CURRENT_V5_REALITY_CONNECTION_DECISION_ADAPTER = TypeAdapter(
    CurrentV5RealityConnectionDecision
)


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


class CurrentV5TenderReflectionEstablished(_CurrentV5ContractModel):
    """Planner-owned decision for the one operation that establishes the first Tender frame."""

    branch: Literal["tenderEstablished"]
    reflectionDelta: str

    @field_validator("reflectionDelta")
    @classmethod
    def require_nonempty_reflection_delta(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("reflectionDelta must be nonempty")
        return value


_CURRENT_V5_TENDER_REFLECTION_DECISION_ADAPTER = TypeAdapter(
    CurrentV5TenderReflectionEstablished
)


class CurrentV5PracticeProposal(_CurrentV5ContractModel):
    content: str
    basis: str


_CURRENT_V5_PRACTICE_PROPOSAL_ADAPTER = TypeAdapter(CurrentV5PracticeProposal)


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


class CurrentV5ActiveFierceClarify(_CurrentV5ContractModel):
    """Executable meaning shape while one Swift-owned Fierce candidate is active."""

    meaning: Literal["clarifyFierce"]
    candidateRef: None = None
    reflectionDelta: None = None
    fierceDirection: None = None


class CurrentV5ActiveFierceComplete(_CurrentV5ContractModel):
    """Atomic completion of the already-active Fierce inquiry."""

    meaning: Literal["completeFierce"]
    candidateRef: None = None
    reflectionDelta: str
    fierceDirection: Literal["repair", "protect", "change"]

    @field_validator("reflectionDelta")
    @classmethod
    def require_nonempty_reflection_delta(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("reflectionDelta must be nonempty")
        return value


class CurrentV5ActiveFierceSynthesize(_CurrentV5ContractModel):
    """Explicit decline/no-direction exit from Active Fierce into Synthesis."""

    meaning: Literal["synthesize"]
    candidateRef: None = None
    reflectionDelta: str
    fierceDirection: None = None

    @field_validator("reflectionDelta")
    @classmethod
    def require_nonempty_reflection_delta(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("reflectionDelta must be nonempty")
        return value


CurrentV5ActiveFierceDecision = Annotated[
    Union[
        CurrentV5ActiveFierceClarify,
        CurrentV5ActiveFierceComplete,
        CurrentV5ActiveFierceSynthesize,
    ],
    Field(discriminator="meaning"),
]

_CURRENT_V5_ACTIVE_FIERCE_DECISION_ADAPTER = TypeAdapter(
    CurrentV5ActiveFierceDecision
)


class CurrentV5PlannerContract(_CurrentV5ContractModel):
    # Operation authorization and legacy alias resolution belong to Swift. The backend transports
    # the model's semantic act as text and never rewrites it from capability or payload metadata.
    semanticOperation: Optional[str] = None
    semanticEvidencePatch: CurrentV5SemanticEvidencePatch
    reflectionProgressionDecision: Optional[CurrentV5ReflectionProgressionDecision] = None
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
    {"semanticOperation", "reflectionProgressionDecision", "responseFocus"}
)
_CURRENT_V5_PATCH_OWNERS = frozenset(
    {
        "cardConnectionEvidence",
        "contextualTrackingDecision",
    }
)
_CURRENT_V5_SEMANTIC_ALIAS_FIELDS = frozenset({"cardConnectionTurnOutcome"})
_CURRENT_V5_MEMORY_OWNERS = frozenset(CurrentV5SemanticMemoryUpdate.model_fields)
_CURRENT_V5_NESTED_MEMORY_FIELDS: dict[str, frozenset[str]] = {
    "episodeStructure": frozenset(CurrentV5EpisodeStructurePatch.model_fields),
    "contextRelationship": frozenset(CurrentV5ContextRelationship.model_fields),
    "pendingCardRealityConnection": frozenset(
        CurrentV5PendingCardRealityConnection.model_fields
    ),
    "cardObservationEvidence": frozenset(CurrentV5CardObservationEvidence.model_fields),
    "cardDevelopmentEvidence": frozenset(CurrentV5CardDevelopmentEvidence.model_fields),
    # `branch` is a Planner-only operation decision. Ownership must preserve it until the
    # operation-specific validator runs; the generic Swift-facing projection never retains it.
    "reflectionFrame": frozenset(CurrentV5ReflectionFrame.model_fields) | {"branch"},
    "practiceTransition": frozenset(CurrentV5PracticeTransition.model_fields),
}


def _relocate_uniquely_owned_fields(
    *,
    containers: list[dict[str, Any]],
    owner: dict[str, Any],
    owned_fields: frozenset[str],
) -> None:
    """Move a unique alias only when the canonical owner has not supplied the field.

    Canonical placement is authoritative. Misplaced copies are syntax aliases, not peers: they
    are discarded when the owner is present, moved when they agree, and omitted when they
    conflict. No alias conflict is allowed to reject the complete Planner response.
    """

    for key in owned_fields:
        owner_is_present = key in owner
        aliases: list[Any] = []
        for container in containers:
            if container is owner:
                continue
            if key in container:
                aliases.append(container.pop(key))
        if owner_is_present or not aliases:
            continue
        first = aliases[0]
        if all(alias == first for alias in aliases[1:]):
            owner[key] = first
        else:
            owner.pop(key, None)


def _lift_misnested_owned_fields(memory: dict[str, Any]) -> None:
    """Lift only fields whose current-v5 owner is mechanically unique.

    A nested model keeps its own declared fields. If a provider puts an envelope or memory field
    inside that object, moving the unchanged value is structural canonicalization, not semantic
    inference. Fields with no current-v5 owner are discarded by the final typed projection; a
    supplied value for a known field remains syntax-only input for the final lossy projection.
    """

    owned = (
        _CURRENT_V5_TOP_LEVEL_OWNERS
        | _CURRENT_V5_PATCH_OWNERS
        | _CURRENT_V5_MEMORY_OWNERS
        | _CURRENT_V5_SEMANTIC_ALIAS_FIELDS
    )
    aliases_by_key: dict[str, list[Any]] = {}
    for container_key, allowed_nested_fields in _CURRENT_V5_NESTED_MEMORY_FIELDS.items():
        nested = memory.get(container_key)
        if not isinstance(nested, dict):
            continue
        for key in list(nested):
            if key in _CURRENT_V5_PROTOCOL_RESIDUE_FIELDS:
                nested.pop(key)
                continue
            if key not in allowed_nested_fields and key in owned:
                aliases_by_key.setdefault(key, []).append(nested.pop(key))
    for key, aliases in aliases_by_key.items():
        if key in memory:
            continue
        first = aliases[0]
        if all(alias == first for alias in aliases[1:]):
            memory[key] = first


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
    patch = dict(raw_patch) if isinstance(raw_patch, dict) else {}

    raw_canonical_memory = patch.pop("memoryUpdate", {})
    memory = dict(raw_canonical_memory) if isinstance(raw_canonical_memory, dict) else {}
    memory_aliases: list[dict[str, Any]] = []
    raw_root_memory = root.pop("memoryUpdate", None)
    if isinstance(raw_root_memory, dict):
        memory_aliases.append(dict(raw_root_memory))

    memory_containers = [memory, *memory_aliases]
    tracking_alias_containers = [root, *memory_containers]
    for candidate in memory_containers:
        for nested_key in _CURRENT_V5_NESTED_MEMORY_FIELDS:
            nested = candidate.get(nested_key)
            if not isinstance(nested, dict):
                continue
            nested_copy = dict(nested)
            candidate[nested_key] = nested_copy
            tracking_alias_containers.append(nested_copy)
        _lift_misnested_owned_fields(candidate)

    _project_optional_patch_owner(
        patch=patch,
        alias_containers=tracking_alias_containers,
        key="contextualTrackingDecision",
    )

    containers = [root, patch, *memory_containers]
    _relocate_uniquely_owned_fields(
        containers=containers,
        owner=root,
        owned_fields=_CURRENT_V5_TOP_LEVEL_OWNERS,
    )
    _relocate_uniquely_owned_fields(
        containers=containers,
        owner=patch,
        owned_fields=_CURRENT_V5_PATCH_OWNERS,
    )
    _relocate_uniquely_owned_fields(
        containers=containers,
        owner=memory,
        owned_fields=_CURRENT_V5_MEMORY_OWNERS,
    )
    for container in containers:
        for key in _CURRENT_V5_PROTOCOL_RESIDUE_FIELDS:
            container.pop(key, None)
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

    current_is_present = "cardConnectionEvidence" in patch
    current = patch.get("cardConnectionEvidence")
    semantic_connection = dict(current) if isinstance(current, dict) else {}

    legacy_values: list[Any] = []
    for container in (decoded, patch, memory):
        if "cardConnectionTurnOutcome" in container:
            legacy_values.append(container.pop("cardConnectionTurnOutcome"))
    if "cardRealityConnection" in memory:
        legacy_values.append(memory.pop("cardRealityConnection"))

    # The canonical envelope wins even when one of its leaves is malformed; the final syntax
    # projector drops that leaf rather than allowing a legacy alias to replace it. Without a
    # canonical owner, legacy aliases are usable only when their complete values agree.
    if not current_is_present and legacy_values:
        first = legacy_values[0]
        if all(alias == first for alias in legacy_values[1:]) and isinstance(first, dict):
            nested = first.get("connection")
            candidate = nested if isinstance(nested, dict) else first
            semantic_connection = {
                key: candidate[key]
                for key in ("imageRelation", "realityMapping")
                if key in candidate
            }
            # Decode-only legacy compatibility: a legacy envelope carrying an explicit mapping
            # already has the unique established meaning. Current Planner output must still emit
            # the branch in its canonical owner.
            if "realityMapping" in semantic_connection:
                semantic_connection["branch"] = "connectionEstablished"
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


def _canonicalize_current_v5_progression_syntax(
    decoded: dict[str, Any],
    *,
    preserve_active_fierce_payload: bool = False,
) -> dict[str, Any]:
    """Normalize only mechanically unique progression transport syntax.

    The model still decides the progression meaning and Swift still compiles that meaning into an
    operation. This pass only prevents a valid, unambiguous meaning from becoming an HTTP failure
    because a provider returned the enum as a scalar, a one-item list, a JSON-encoded value, or
    under a known syntax alias. Unknown and ambiguous optional values are later omitted so Swift
    receives the remaining semantic material and decides whether the turn can progress.
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
            if meaning == "inspectReality" or not preserve_active_fierce_payload:
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
            # The colocated field is canonical. If it is absent, move the unique old semantic
            # alias once; if present (including null/empty), discard the legacy competitor.
            if "reflectionDelta" not in decision and legacy_delta is not None:
                decision["reflectionDelta"] = legacy_delta
            if "reflectionDelta" in decision:
                memory.pop("reflectionFrame", None)
            if meaning == "completeFierce":
                # Direction/delta are model meaning. Candidate and evidence identity are compiled
                # deterministically from Swift-owned pre-turn state and cannot compete here.
                if not preserve_active_fierce_payload:
                    decision.pop("candidateRef", None)
                    decision.pop("groundedEvidence", None)
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


_CURRENT_V5_DROP = object()
_CURRENT_V5_UNOWNED_WRAPPER_METADATA_FIELDS = frozenset(
    {
        "kind",
        "source",
        "status",
        "mode",
        "action",
        "phase",
        "transactionID",
        "id",
        "confidence",
    }
)


def _current_v5_unique_wrapper_payload(
    value: Any,
    *,
    allowed_payload_keys: frozenset[str],
) -> Any:
    """Return one mechanically unique payload after deleting known legacy metadata."""

    if not isinstance(value, dict):
        return _CURRENT_V5_DROP
    payloads = [
        (key, item)
        for key, item in value.items()
        if key not in _CURRENT_V5_UNOWNED_WRAPPER_METADATA_FIELDS
    ]
    if not payloads or any(key not in allowed_payload_keys for key, _ in payloads):
        return _CURRENT_V5_DROP
    first = payloads[0][1]
    return (
        first
        if all(payload == first for _, payload in payloads[1:])
        else _CURRENT_V5_DROP
    )


def _unwrap_current_v5_scalar_syntax(
    value: Any,
    *,
    field_name: Optional[str],
) -> Any:
    """Unwrap nested one-value scalar envelopes without selecting among meanings."""

    candidate = value
    for _ in range(8):
        if isinstance(candidate, list) and len(candidate) == 1:
            candidate = candidate[0]
            continue
        keys = {"value", "text", "content"}
        if field_name:
            keys.add(field_name)
        payload = _current_v5_unique_wrapper_payload(
            candidate,
            allowed_payload_keys=frozenset(keys),
        )
        if payload is not _CURRENT_V5_DROP:
            candidate = payload
            continue
        break
    return candidate


def _unwrap_current_v5_string_syntax(
    value: Any,
    *,
    field_name: Optional[str],
    depth: int = 0,
) -> Any:
    """Decode a string from authoritative text keys without treating metadata as meaning.

    Providers sometimes wrap one string in a richer object. Only the field's own name and the
    conventional content/text/value keys can own that scalar. Unknown siblings are metadata and
    do not compete. Multiple authoritative keys are safe only when their nonempty string values
    normalize to exactly the same text; conflicting text remains ambiguous and is dropped.
    """

    if isinstance(value, str):
        # A directly supplied string already has the schema's scalar shape and remains unchanged.
        # Empty strings inside a wrapper are not evidence that the wrapper carries text.
        return value if depth == 0 or value.strip() else _CURRENT_V5_DROP
    if depth >= 8:
        return _CURRENT_V5_DROP
    if isinstance(value, list):
        if len(value) != 1:
            return _CURRENT_V5_DROP
        return _unwrap_current_v5_string_syntax(
            value[0],
            field_name=field_name,
            depth=depth + 1,
        )
    if not isinstance(value, dict):
        return _CURRENT_V5_DROP

    authority_keys: list[str] = []
    for key in (field_name, "content", "text", "value"):
        if key and key not in authority_keys:
            authority_keys.append(key)

    candidates: list[str] = []
    for key in authority_keys:
        if key not in value:
            continue
        candidate = _unwrap_current_v5_string_syntax(
            value[key],
            field_name=field_name,
            depth=depth + 1,
        )
        if isinstance(candidate, str) and candidate not in candidates:
            candidates.append(candidate)
    return candidates[0] if len(candidates) == 1 else _CURRENT_V5_DROP


def _unwrap_current_v5_container_syntax(
    value: Any,
    *,
    declared_fields: Optional[set[str]] = None,
    field_name: Optional[str],
) -> Any:
    """Remove an outer one-value envelope while preserving the expected container itself."""

    candidate = value
    for _ in range(8):
        if isinstance(candidate, list):
            if declared_fields is not None and len(candidate) == 1:
                candidate = candidate[0]
                continue
            break
        if not isinstance(candidate, dict):
            break
        if declared_fields is not None and any(key in declared_fields for key in candidate):
            break
        keys = (
            {"value", "data", "payload"}
            if declared_fields is not None
            else {"items", "values", "content"}
        )
        if field_name:
            keys.add(field_name)
        payload = _current_v5_unique_wrapper_payload(
            candidate,
            allowed_payload_keys=frozenset(keys),
        )
        if payload is _CURRENT_V5_DROP:
            break
        candidate = payload
    return candidate


def _project_current_v5_decodable_value(
    value: Any,
    annotation: Any,
    *,
    field_name: Optional[str] = None,
) -> Any:
    """Lossily project one value onto syntax Swift can decode without coercing meaning.

    Invalid optional leaves disappear at the smallest typed boundary. Required malformed content
    makes only its containing optional model disappear. Lists retain independently valid members.
    This is deliberately not semantic repair: no text is extracted from objects, no enum is
    guessed, and no absent workflow decision is created.
    """

    if annotation is Any:
        return value

    model = _current_v5_model_from_annotation(annotation)
    origin = get_origin(annotation)

    if origin is Union:
        members = get_args(annotation)
        if value is None and type(None) in members:
            return None
        for member in members:
            if member is type(None):
                continue
            projected = _project_current_v5_decodable_value(
                value,
                member,
                field_name=field_name,
            )
            if projected is not _CURRENT_V5_DROP:
                return projected
        return _CURRENT_V5_DROP

    if origin is Literal:
        value = _unwrap_current_v5_scalar_syntax(value, field_name=field_name)
        for allowed in get_args(annotation):
            if type(value) is type(allowed) and value == allowed:
                return value
        return _CURRENT_V5_DROP

    if origin is list:
        value = _unwrap_current_v5_container_syntax(
            value,
            field_name=field_name,
        )
        if not isinstance(value, list):
            return _CURRENT_V5_DROP
        arguments = get_args(annotation)
        member_annotation = arguments[0] if arguments else Any
        members = []
        for item in value:
            projected = _project_current_v5_decodable_value(item, member_annotation)
            if projected is not _CURRENT_V5_DROP:
                members.append(projected)
        return members

    if model is not None:
        value = _unwrap_current_v5_container_syntax(
            value,
            declared_fields=set(model.model_fields),
            field_name=field_name,
        )
        if not isinstance(value, dict):
            return _CURRENT_V5_DROP
        projected_model: dict[str, Any] = {}
        for key, field in model.model_fields.items():
            if key not in value:
                if field.is_required():
                    return _CURRENT_V5_DROP
                continue
            projected = _project_current_v5_decodable_value(
                value[key],
                field.annotation,
                field_name=key,
            )
            if projected is _CURRENT_V5_DROP:
                if field.is_required():
                    return _CURRENT_V5_DROP
                continue
            projected_model[key] = projected
        try:
            validated = model.model_validate(projected_model)
        except ValidationError:
            return _CURRENT_V5_DROP
        return validated.model_dump(mode="json", exclude_unset=True)

    if annotation is str:
        value = _unwrap_current_v5_string_syntax(value, field_name=field_name)
        return value if isinstance(value, str) else _CURRENT_V5_DROP
    if annotation is bool:
        value = _unwrap_current_v5_scalar_syntax(value, field_name=field_name)
        return value if type(value) is bool else _CURRENT_V5_DROP
    if annotation is int:
        value = _unwrap_current_v5_scalar_syntax(value, field_name=field_name)
        return value if type(value) is int else _CURRENT_V5_DROP
    if annotation is float:
        value = _unwrap_current_v5_scalar_syntax(value, field_name=field_name)
        return value if type(value) is float else _CURRENT_V5_DROP
    if annotation is type(None):
        return None if value is None else _CURRENT_V5_DROP

    return value


def _project_current_v5_decodable_contract(projected: dict[str, Any]) -> dict[str, Any]:
    """Make every parseable object a Swift-decodable sparse Planner response."""

    shaped = dict(projected)
    patch = shaped.get("semanticEvidencePatch")
    if not isinstance(patch, dict):
        shaped["semanticEvidencePatch"] = {"memoryUpdate": {}}
    elif not isinstance(patch.get("memoryUpdate"), dict):
        patch["memoryUpdate"] = {}

    decision = shaped["semanticEvidencePatch"].get("contextualTrackingDecision")
    eligibility = decision.get("metricEligibility") if isinstance(decision, dict) else None
    if isinstance(eligibility, list):
        for item in eligibility:
            if isinstance(item, dict):
                # Missing preference is transport syntax, not a semantic no-use decision. Swift
                # still decides whether a supplied set is coherent and authorized for this turn.
                item.setdefault("preferred", False)

    decodable = _project_current_v5_decodable_value(shaped, CurrentV5PlannerContract)
    if decodable is _CURRENT_V5_DROP:
        # Ownership normalization always constructs this required sparse envelope. Keep a safe
        # invariant fallback so a provider's optional typed mistake cannot become HTTP 502.
        return {"semanticEvidencePatch": {"memoryUpdate": {}}}
    return decodable


_CURRENT_V5_REALITY_CONNECTION_OPERATIONS = frozenset(
    {"continueOpenCardConnection", "offerCardConnectionScaffold"}
)


def _enforce_current_v5_reality_connection_contract(
    projected: dict[str, Any],
) -> dict[str, Any]:
    """Enforce the first operation-specific semantic transaction.

    The branch is Planner-owned turn-local meaning. The backend verifies only that the declared
    branch and its payload agree; it does not infer a connection from the user's prose or advance
    the workflow. Swift continues to own the state transition from the canonical mapping.
    """

    raw_operation = projected.get("semanticOperation")
    operation = _unwrap_current_v5_string_syntax(
        raw_operation,
        field_name="semanticOperation",
    )
    if operation not in _CURRENT_V5_REALITY_CONNECTION_OPERATIONS:
        return projected
    projected["semanticOperation"] = operation

    patch = projected.get("semanticEvidencePatch")
    evidence = patch.get("cardConnectionEvidence") if isinstance(patch, dict) else None
    if not isinstance(evidence, dict):
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.cardConnectionEvidence",
            violation="reality_connection_branch_required",
        )

    branch = _unwrap_current_v5_string_syntax(
        evidence.get("branch"),
        field_name="branch",
    )
    if branch not in {"connectionEstablished", "needsMoreExploration"}:
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.cardConnectionEvidence.branch",
            violation="invalid_reality_connection_branch",
        )
    evidence["branch"] = branch

    raw_image_relation = evidence.get("imageRelation")
    if raw_image_relation is not None:
        image_relation = _unwrap_current_v5_string_syntax(
            raw_image_relation,
            field_name="imageRelation",
        )
        if isinstance(image_relation, str) and image_relation.strip():
            evidence["imageRelation"] = image_relation
        else:
            evidence.pop("imageRelation", None)

    mapping_is_present = "realityMapping" in evidence
    raw_mapping = evidence.get("realityMapping")
    if branch == "connectionEstablished":
        mapping = _unwrap_current_v5_string_syntax(
            raw_mapping,
            field_name="realityMapping",
        )
        if not isinstance(mapping, str) or not mapping.strip():
            raise CurrentV5PlannerContractError(
                field_path="semanticEvidencePatch.cardConnectionEvidence.realityMapping",
                violation="required_for_connection_established",
            )
        evidence["realityMapping"] = mapping
    elif mapping_is_present and raw_mapping is not None:
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.cardConnectionEvidence.realityMapping",
            violation="must_be_null_for_needs_more_exploration",
        )
    else:
        evidence.pop("realityMapping", None)

    try:
        _CURRENT_V5_REALITY_CONNECTION_DECISION_ADAPTER.validate_python(
            {
                key: evidence[key]
                for key in ("branch", "imageRelation", "realityMapping")
                if key in evidence
            }
        )
    except ValidationError as error:
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.cardConnectionEvidence",
            violation="invalid_reality_connection_payload",
        ) from error
    # Branch is a backend-consumed turn-local decision, not persisted evidence or Swift workflow
    # state. The canonical response keeps only the existing Swift-compatible evidence surface.
    evidence.pop("branch", None)
    return projected


def _enforce_current_v5_tender_reflection_contract(
    projected: dict[str, Any],
) -> dict[str, Any]:
    """Require the first Tender meaning to be atomically bound to its operation.

    Choosing ``continueTenderReflection`` means the Planner has finished Exploration and is
    establishing the first bounded Tender understanding. The backend checks only that declared
    meaning and its required delta agree. It does not decide that Tender is warranted, construct
    the frame, or advance Reflection; those remain Swift responsibilities.
    """

    raw_operation = projected.get("semanticOperation")
    operation = _unwrap_current_v5_string_syntax(
        raw_operation,
        field_name="semanticOperation",
    )
    if operation != "continueTenderReflection":
        return projected
    projected["semanticOperation"] = operation

    patch = projected.get("semanticEvidencePatch")
    memory = patch.get("memoryUpdate") if isinstance(patch, dict) else None
    frame = memory.get("reflectionFrame") if isinstance(memory, dict) else None
    if not isinstance(frame, dict):
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.memoryUpdate.reflectionFrame",
            violation="tender_reflection_branch_required",
        )

    branch = _unwrap_current_v5_string_syntax(
        frame.get("branch"),
        field_name="branch",
    )
    if branch != "tenderEstablished":
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.memoryUpdate.reflectionFrame.branch",
            violation="invalid_tender_reflection_branch",
        )

    reflection_delta = _unwrap_current_v5_string_syntax(
        frame.get("reflectionDelta"),
        field_name="reflectionDelta",
    )
    if not isinstance(reflection_delta, str) or not reflection_delta.strip():
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta",
            violation="required_for_tender_established",
        )
    if frame.get("fierceEvidence") is not None:
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.memoryUpdate.reflectionFrame.fierceEvidence",
            violation="must_be_null_for_tender_established",
        )

    try:
        _CURRENT_V5_TENDER_REFLECTION_DECISION_ADAPTER.validate_python(
            {
                "branch": branch,
                "reflectionDelta": reflection_delta,
            }
        )
    except ValidationError as error:
        raise CurrentV5PlannerContractError(
            field_path="semanticEvidencePatch.memoryUpdate.reflectionFrame",
            violation="invalid_tender_reflection_payload",
        ) from error

    frame["reflectionDelta"] = reflection_delta
    # The branch is turn-local Planner meaning, not persisted Reflection evidence. Preserve the
    # existing Swift wire surface and let Swift construct provenance/mode/action from its state.
    frame.pop("branch", None)
    return projected


def _enforce_current_v5_active_fierce_contract(
    projected: dict[str, Any],
    *,
    reflection_mode: Optional[str],
) -> dict[str, Any]:
    """Validate the Planner-owned branch while Swift owns one active Fierce candidate.

    This contract does not infer which branch the latest answer means. It verifies that the
    Planner's declared clarify/complete/synthesize meaning carries exactly the payload that Swift
    can execute. Candidate identity and evidence remain recoverable only from Swift's pre-turn
    state, so a provider cannot repeat or replace them here.
    """

    if reflection_mode != "fierce":
        return projected

    decision = projected.get("reflectionProgressionDecision")
    if not isinstance(decision, dict):
        raise CurrentV5PlannerContractError(
            field_path="reflectionProgressionDecision",
            violation="active_fierce_progression_required",
        )

    meaning = _unwrap_current_v5_string_syntax(
        decision.get("meaning"),
        field_name="meaning",
    )
    if meaning in {"inspectReality", "reviseTender"}:
        raise CurrentV5PlannerContractError(
            field_path="reflectionProgressionDecision.meaning",
            violation="invalid_for_active_fierce",
        )
    if meaning not in {"clarifyFierce", "completeFierce", "synthesize"}:
        raise CurrentV5PlannerContractError(
            field_path="reflectionProgressionDecision.meaning",
            violation="invalid_active_fierce_branch",
        )
    decision["meaning"] = meaning

    expected_operation = (
        "synthesizeDirectReflection"
        if meaning == "synthesize"
        else "continueTenderGroundedFierceReflection"
    )
    raw_operation = projected.get("semanticOperation")
    if raw_operation is not None:
        operation = _unwrap_current_v5_string_syntax(
            raw_operation,
            field_name="semanticOperation",
        )
        if operation != expected_operation:
            raise CurrentV5PlannerContractError(
                field_path="semanticOperation",
                violation="conflicts_with_active_fierce_branch",
            )
        projected["semanticOperation"] = operation

    for field_name in ("candidateRef", "groundedEvidence"):
        if decision.get(field_name) is not None:
            raise CurrentV5PlannerContractError(
                field_path=f"reflectionProgressionDecision.{field_name}",
                violation="swift_owned_during_active_fierce",
            )
        decision.pop(field_name, None)

    raw_delta = decision.get("reflectionDelta")
    raw_direction = decision.get("fierceDirection")
    raw_focus = projected.get("responseFocus")

    if meaning == "clarifyFierce":
        if raw_delta is not None:
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.reflectionDelta",
                violation="must_be_null_for_clarify_fierce",
            )
        if raw_direction is not None:
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.fierceDirection",
                violation="must_be_null_for_clarify_fierce",
            )
        focus = _unwrap_current_v5_string_syntax(
            raw_focus,
            field_name="responseFocus",
        )
        if not isinstance(focus, str) or not focus.strip():
            raise CurrentV5PlannerContractError(
                field_path="responseFocus",
                violation="required_for_clarify_fierce",
            )
        decision.pop("reflectionDelta", None)
        decision.pop("fierceDirection", None)
        projected["responseFocus"] = focus

    elif meaning == "completeFierce":
        delta = _unwrap_current_v5_string_syntax(
            raw_delta,
            field_name="reflectionDelta",
        )
        if not isinstance(delta, str) or not delta.strip():
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.reflectionDelta",
                violation="required_for_complete_fierce",
            )
        direction = _unwrap_current_v5_string_syntax(
            raw_direction,
            field_name="fierceDirection",
        )
        if direction not in {"repair", "protect", "change"}:
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.fierceDirection",
                violation="required_for_complete_fierce",
            )
        if raw_focus is not None:
            focus = _unwrap_current_v5_string_syntax(
                raw_focus,
                field_name="responseFocus",
            )
            if not isinstance(focus, str) or focus.strip():
                raise CurrentV5PlannerContractError(
                    field_path="responseFocus",
                    violation="must_be_empty_for_complete_fierce",
                )
        decision["reflectionDelta"] = delta
        decision["fierceDirection"] = direction
        projected["responseFocus"] = ""

    else:
        delta = _unwrap_current_v5_string_syntax(
            raw_delta,
            field_name="reflectionDelta",
        )
        if not isinstance(delta, str) or not delta.strip():
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.reflectionDelta",
                violation="required_for_active_fierce_synthesis",
            )
        if raw_direction is not None:
            raise CurrentV5PlannerContractError(
                field_path="reflectionProgressionDecision.fierceDirection",
                violation="must_be_null_for_active_fierce_synthesis",
            )
        decision["reflectionDelta"] = delta
        decision.pop("fierceDirection", None)

    try:
        _CURRENT_V5_ACTIVE_FIERCE_DECISION_ADAPTER.validate_python(decision)
    except ValidationError as error:
        raise CurrentV5PlannerContractError(
            field_path="reflectionProgressionDecision",
            violation="invalid_active_fierce_payload",
        ) from error
    return projected


def _enforce_current_v5_propose_practice_contract(
    projected: dict[str, Any],
) -> dict[str, Any]:
    """Normalize a complete proposal without turning an incomplete act into transport failure.

    The backend validates only the operation-owned wire shape. Whether the proposed Chinese text
    stays within the user's grounded direction is Planner meaning and remains outside this
    structural validator. A parseable ``proposePractice`` decision must still reach Swift when its
    optional payload is absent or malformed: the semantic compiler/Gate already owns
    ``practiceProposalMissing``/``practiceProposalIncomplete`` correction. A decodable semantic
    conflict, such as a complete proposal plus ``noActionReason``, is preserved rather than
    rewritten as missing. Swift also validates the exact candidate basis and owns transaction,
    source, status, category, and workflow progression.
    """

    operation = _unwrap_current_v5_string_syntax(
        projected.get("semanticOperation"),
        field_name="semanticOperation",
    )
    if operation != "proposePractice":
        return projected
    projected["semanticOperation"] = operation

    patch = projected.get("semanticEvidencePatch")
    memory = patch.get("memoryUpdate") if isinstance(patch, dict) else None
    transition = memory.get("practiceTransition") if isinstance(memory, dict) else None
    if not isinstance(transition, dict):
        return projected

    def omit_incomplete_transition() -> dict[str, Any]:
        if isinstance(memory, dict):
            memory.pop("practiceTransition", None)
        return projected

    proposal = transition.get("proposal")
    if not isinstance(proposal, dict):
        return omit_incomplete_transition()

    content = _unwrap_current_v5_string_syntax(
        proposal.get("content"),
        field_name="content",
    )
    if not isinstance(content, str) or not content.strip():
        return omit_incomplete_transition()
    basis = _unwrap_current_v5_string_syntax(
        proposal.get("basis"),
        field_name="basis",
    )
    if not isinstance(basis, str) or not basis.strip():
        return omit_incomplete_transition()

    try:
        _CURRENT_V5_PRACTICE_PROPOSAL_ADAPTER.validate_python(
            {"content": content, "basis": basis}
        )
    except ValidationError:
        return omit_incomplete_transition()

    proposal["content"] = content
    proposal["basis"] = basis
    if transition.get("noActionReason") is None:
        transition.pop("noActionReason", None)
    return projected


def canonicalize_current_v5_planner_contract(
    content: str,
    *,
    allowed_semantic_operations: Optional[list[str]] = None,
    reflection_mode: Optional[str] = None,
) -> str:
    """Project every parseable object onto the Swift-decodable current-v5 sparse surface.

    The backend owns JSON syntax, legacy alias movement, and removal of unowned metadata. Ordinary
    malformed optional syntax is removed at the smallest boundary. Complete operation-owned payloads
    are normalized atomically; incomplete optional payloads are omitted while their parseable semantic
    operation is preserved for the Swift compiler/Gate. Swift remains the sole workflow authority.
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
    projected = _canonicalize_current_v5_progression_syntax(
        projected,
        preserve_active_fierce_payload=reflection_mode == "fierce",
    )
    projected = _enforce_current_v5_reality_connection_contract(projected)
    projected = _enforce_current_v5_tender_reflection_contract(projected)
    projected = _enforce_current_v5_active_fierce_contract(
        projected,
        reflection_mode=reflection_mode,
    )
    projected = _enforce_current_v5_propose_practice_contract(projected)
    projected = _project_current_v5_decodable_contract(projected)

    try:
        validated = CurrentV5PlannerContract.model_validate(projected)
    except ValidationError as error:
        # Reaching this branch is a projector implementation defect, not a provider contract
        # violation. Keep the public error type for observability without blaming a user turn.
        raise CurrentV5PlannerContractError(
            field_path="root",
            violation="canonical_projection_invalid",
        ) from error
    return json.dumps(
        validated.model_dump(mode="json", exclude_unset=True),
        ensure_ascii=False,
        separators=(",", ":"),
    )


def validate_current_v5_planner_contract(content: str) -> None:
    """Validate structure only; Swift remains the sole semantic capability authority."""

    canonicalize_current_v5_planner_contract(content)
