from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import time
from collections import deque
from dataclasses import dataclass
from typing import Any, Literal, Optional

import httpx
from fastapi import HTTPException

from . import config
from .prompt_registry import (
    CURRENT_V5_PLANNER_JSON_SHAPE,
    PLANNER_JSON_SHAPE,
    PromptLengthMetrics,
    log_prompt_length,
)
from .schemas import (
    CurrentV5PlannerContractError,
    canonicalize_current_v5_planner_contract,
)


logger = logging.getLogger("uvicorn.error")
Role = Literal["planner", "writer", "critic"]


def _current_v5_request(messages: list[dict[str, str]]) -> dict[str, Any]:
    prefix = "CURRENT V5 TURN REQUEST JSON:\n"
    for message in messages:
        content = message.get("content", "")
        if message.get("role") != "user" or not content.startswith(prefix):
            continue
        try:
            request = json.loads(content[len(prefix):])
        except (TypeError, json.JSONDecodeError):
            return {}
        return request if isinstance(request, dict) else {}
    return {}


def _current_v5_allowed_operations(messages: list[dict[str, str]]) -> list[str]:
    operations = _current_v5_request(messages).get("allowedSemanticOperations")
    if not isinstance(operations, list):
        return []
    return [value for value in operations if isinstance(value, str)]


def _current_v5_reflection_mode(messages: list[dict[str, str]]) -> Optional[str]:
    value = _current_v5_request(messages).get("reflectionMode")
    return value if isinstance(value, str) else None


def _current_v5_tracking_profile_summary(
    messages: list[dict[str, str]],
) -> dict[str, Any] | None:
    """Return a bounded diagnostic view of the exact final Planner request.

    The summary deliberately excludes recentDaily values, transcript text, semantic memory, and
    user-facing model fields. Counts and date bounds establish whether a temporal series reached
    the server; aggregate medians and coverage establish whether the profile reached the Planner.
    """
    request = _current_v5_request(messages)
    profiles = request.get("contextualTrackingProfiles")
    if not isinstance(profiles, list) or not profiles:
        return None

    profile_summaries: list[dict[str, Any]] = []
    for profile in profiles:
        if not isinstance(profile, dict):
            continue
        metric_summaries: list[dict[str, Any]] = []
        metrics = profile.get("metrics")
        for metric in metrics if isinstance(metrics, list) else []:
            if not isinstance(metric, dict):
                continue
            recent_daily = metric.get("recentDaily")
            recent_daily = recent_daily if isinstance(recent_daily, list) else []
            dates = [
                point.get("date")
                for point in recent_daily
                if isinstance(point, dict) and isinstance(point.get("date"), str)
            ]
            coverage = metric.get("coverage")
            coverage = coverage if isinstance(coverage, dict) else {}
            metric_summaries.append(
                {
                    "metric": metric.get("metric"),
                    "unit": metric.get("unit"),
                    "recentDailyCount": len(recent_daily),
                    "recentDailyStart": dates[0] if dates else None,
                    "recentDailyEnd": dates[-1] if dates else None,
                    "recentMedian": metric.get("recentMedian"),
                    "baselineMedian": metric.get("baselineMedian"),
                    "coverage": {
                        "recentObservedDays": coverage.get("recentObservedDays"),
                        "recentExpectedDays": coverage.get("recentExpectedDays"),
                        "baselineObservedDays": coverage.get("baselineObservedDays"),
                        "baselineExpectedDays": coverage.get("baselineExpectedDays"),
                    },
                }
            )
        profile_summaries.append(
            {
                "profileID": profile.get("profileID"),
                "domain": profile.get("domain"),
                "metrics": metric_summaries,
            }
        )

    return {
        "protocolStage": request.get("protocolStage"),
        "reflectionMode": request.get("reflectionMode"),
        "profiles": profile_summaries,
    }


def _current_v5_tracking_decision_summary(content: str) -> dict[str, Any]:
    """Extract only canonical and misplaced Tracking selections from a Planner body."""
    try:
        decoded = json.loads(content)
    except (TypeError, json.JSONDecodeError):
        return {"canonicalOwner": "invalidJSON", "misplacedAlias": None}
    if not isinstance(decoded, dict):
        return {"canonicalOwner": "invalidObject", "misplacedAlias": None}

    patch = decoded.get("semanticEvidencePatch")
    patch = patch if isinstance(patch, dict) else {}
    memory = patch.get("memoryUpdate")
    memory = memory if isinstance(memory, dict) else {}

    def metric_classifications(value: Any) -> Any:
        if value is None:
            return None
        if not isinstance(value, dict):
            return "invalidDecision"
        eligibility = value.get("metricEligibility")
        if not isinstance(eligibility, list):
            return "invalidMetricEligibility"
        return [
            {
                "profileID": item.get("profileID"),
                "metric": item.get("metric"),
                "status": item.get("status"),
                "preferred": item.get("preferred"),
            }
            for item in eligibility
            if isinstance(item, dict)
        ]

    return {
        "canonicalOwner": metric_classifications(patch.get("contextualTrackingDecision")),
        "misplacedAlias": metric_classifications(memory.get("contextualTrackingDecision")),
    }


def _log_current_v5_tracking_request(
    *,
    request_id: Optional[str],
    agent_task: str,
    messages: list[dict[str, str]],
) -> bool:
    if (
        not config.CURRENT_V5_TRACKING_DIAGNOSTICS
        or agent_task != "current_v5_core_planner"
    ):
        return False
    summary = _current_v5_tracking_profile_summary(messages)
    if summary is None:
        return False
    logger.info(
        "current_v5_tracking_diag_request request_id=%s summary=%s",
        request_id,
        json.dumps(summary, ensure_ascii=True, separators=(",", ":")),
    )
    return True


def _log_current_v5_tracking_decision(
    *,
    request_id: Optional[str],
    stage: str,
    content: str,
) -> None:
    logger.info(
        "current_v5_tracking_diag_decision request_id=%s stage=%s decision=%s",
        request_id,
        stage,
        json.dumps(
            _current_v5_tracking_decision_summary(content),
            ensure_ascii=True,
            separators=(",", ":"),
        ),
    )


PLANNER_JSON_REPAIR_CONTRACT = (
    "Repair JSON syntax/types only; do not re-plan. Preserve DRAFT values and absence, including "
    "semanticOperation; never infer a missing/unknown operation from legacy fields. Never add, remove, "
    "or reinterpret intent, outcome, evidence, pending state, confirmation, question, action, "
    "responsibility, or card/tracking relation. Optional omissions become null; invalid required values "
    "remain invalid for typed validation. REPAIR_BOUNDS are limits, not content. Card connection uses only "
    "cardConnectionTurnOutcome; episodeStructure is a patch; reflectionFrame/practiceTransition are complete "
    "or null; IDs stay exact. Return only: "
    + PLANNER_JSON_SHAPE
)


def _planner_repair_bounds(original_messages: list[dict[str, str]]) -> dict[str, Any]:
    request: dict[str, Any] = {}
    prefix = "TURN REQUEST JSON:\n"
    for message in original_messages:
        content = message.get("content", "")
        if message.get("role") != "user" or not content.startswith(prefix):
            continue
        try:
            decoded = json.loads(content[len(prefix):].split("\n\n", 1)[0])
        except (TypeError, json.JSONDecodeError):
            break
        if isinstance(decoded, dict):
            request = decoded
        break
    permissions = request.get("permissions")
    permissions = permissions if isinstance(permissions, dict) else {}
    memory = request.get("semanticMemory")
    memory = memory if isinstance(memory, dict) else {}
    next_prompt = memory.get("nextPrompt")
    pending = (
        next_prompt
        if isinstance(next_prompt, dict) and next_prompt.get("kind") == "confirmationRequest"
        else None
    )
    card = request.get("card")
    card = card if isinstance(card, dict) else {}
    return {
        "protocolVersion": request.get("protocolVersion"),
        "protocolStage": request.get("protocolStage"),
        "allowedOperations": permissions.get("allowedOperations", []),
        "pendingConfirmation": pending,
        "cardConnectionInteractionState": card.get("connectionInteractionState"),
        "presentedTrackingCueIDs": [
            cue.get("id")
            for cue in request.get("presentedTrackingCues", [])
            if isinstance(cue, dict) and cue.get("id") is not None
        ],
    }


def _planner_json_repair_messages(
    *, draft: str,
    original_messages: list[dict[str, str]],
) -> list[dict[str, str]]:
    bounds = _planner_repair_bounds(original_messages)
    return [
        {"role": "system", "content": PLANNER_JSON_REPAIR_CONTRACT},
        {
            "role": "user",
            "content": json.dumps(
                {"REPAIR_BOUNDS": bounds, "DRAFT": draft},
                ensure_ascii=False,
                separators=(",", ":"),
            ),
        },
    ]


class ProviderError(Exception):
    def __init__(self, provider: str, reason: str, status_code: Optional[int] = None):
        super().__init__(reason)
        self.provider = provider
        self.reason = reason
        self.status_code = status_code


@dataclass(frozen=True)
class Completion:
    content: str
    provider: str
    model: str
    finish_reason: Optional[str] = None
    prompt_tokens: Optional[int] = None
    completion_tokens: Optional[int] = None


class ProviderGateway:
    """DeepSeek-first routing with an OpenAI fallback and in-process circuit breakers."""

    def __init__(
        self,
        *,
        deepseek_max_concurrency: Optional[int] = None,
        deepseek_queue_timeout_seconds: Optional[float] = None,
        http_client: Optional[httpx.AsyncClient] = None,
    ) -> None:
        max_concurrency = (
            deepseek_max_concurrency
            if deepseek_max_concurrency is not None
            else config.DEEPSEEK_MAX_CONCURRENCY
        )
        self._deepseek_semaphore = asyncio.Semaphore(max(1, max_concurrency))
        self._deepseek_queue_timeout_seconds = max(
            0.01,
            deepseek_queue_timeout_seconds
            if deepseek_queue_timeout_seconds is not None
            else config.DEEPSEEK_QUEUE_TIMEOUT_SECONDS,
        )
        self._deepseek_state_lock = asyncio.Lock()
        self._deepseek_state_changed = asyncio.Event()
        self._deepseek_failure_times: deque[float] = deque()
        self._deepseek_circuit_open = False
        self._deepseek_next_probe_at = 0.0
        self._deepseek_probe_in_flight = False
        self._openai_unavailable_until = 0.0
        self._http_client = http_client
        self._owns_http_client = http_client is None
        self._http_client_lock = asyncio.Lock()

    async def startup(self) -> None:
        """Create the process-wide provider connection pool during application startup."""
        await self._get_http_client()

    async def aclose(self) -> None:
        """Close an internally owned pool during application shutdown.

        An injected client remains owned by its caller, which keeps provider unit tests and custom
        transports deterministic.
        """
        client: Optional[httpx.AsyncClient] = None
        async with self._http_client_lock:
            if self._owns_http_client:
                client = self._http_client
                self._http_client = None
        if client is not None and not client.is_closed:
            await client.aclose()

    async def _get_http_client(self) -> httpx.AsyncClient:
        client = self._http_client
        if client is not None and not client.is_closed:
            return client
        async with self._http_client_lock:
            client = self._http_client
            if client is not None and not client.is_closed:
                return client
            limits = httpx.Limits(
                max_connections=config.PROVIDER_HTTP_MAX_CONNECTIONS,
                max_keepalive_connections=(
                    config.PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS
                ),
                keepalive_expiry=config.PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS,
            )
            client = httpx.AsyncClient(timeout=None, limits=limits)
            self._http_client = client
            self._owns_http_client = True
            logger.info(
                "provider_http_client_started max_connections=%s "
                "max_keepalive_connections=%s keepalive_expiry_seconds=%s",
                config.PROVIDER_HTTP_MAX_CONNECTIONS,
                config.PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS,
                config.PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS,
            )
            return client

    def reset_circuit(self) -> None:
        self._deepseek_failure_times.clear()
        self._deepseek_circuit_open = False
        self._deepseek_next_probe_at = 0.0
        self._deepseek_probe_in_flight = False
        self._deepseek_state_changed.set()
        self._deepseek_state_changed = asyncio.Event()
        self._openai_unavailable_until = 0.0

    async def complete(
        self,
        *,
        role: Role,
        agent_task: str = "unspecified",
        request_id: Optional[str] = None,
        messages: list[dict[str, str]],
        max_tokens: int,
        temperature: float,
        require_json_object: bool = True,
    ) -> Completion:
        last_error: Optional[ProviderError] = None
        deepseek_configured = bool(
            config.DEEPSEEK_API_KEY
            and config.DEEPSEEK_BASE_URL
            and self._model("deepseek", role)
        )
        openai_configured = bool(
            config.OPENAI_API_KEY and config.OPENAI_BASE_URL and self._model("openai", role)
        )
        if deepseek_configured:
            half_open_probe = False
            try:
                permission = await self._deepseek_attempt_permission(
                    wait_when_open=not openai_configured
                )
                if permission is None:
                    last_error = ProviderError("deepseek", "circuit_open")
                    logger.info("deepseek_circuit_open role=%s", role)
                else:
                    half_open_probe = permission
                    await self._acquire_deepseek_slot()
                    try:
                        result = await self._complete_deepseek_request(
                            role=role,
                            agent_task=agent_task,
                            request_id=request_id,
                            messages=messages,
                            max_tokens=max_tokens,
                            temperature=temperature,
                            require_json_object=require_json_object,
                        )
                    finally:
                        self._deepseek_semaphore.release()
                    await self._record_deepseek_availability_success(
                        was_half_open_probe=half_open_probe
                    )
                    logger.info(
                        "agent_role_completed request_id=%s role=%s agent_task=%s "
                        "provider=deepseek model=%s",
                        request_id,
                        role,
                        agent_task,
                        result.model,
                    )
                    return result
            except asyncio.CancelledError:
                if half_open_probe:
                    await self._cancel_deepseek_half_open_probe()
                raise
            except ProviderError as error:
                last_error = error
                availability_failure = self._is_availability_failure(error)
                failure_count = len(self._deepseek_failure_times)
                circuit_open = self._deepseek_circuit_open
                if availability_failure:
                    failure_count, circuit_open = await self._record_deepseek_availability_failure(
                        was_half_open_probe=half_open_probe
                    )
                elif error.reason != "queue_timeout":
                    # A structured-response or request-specific failure still proves that the
                    # upstream service is reachable. It must not preserve an availability outage.
                    await self._record_deepseek_availability_success(
                        was_half_open_probe=half_open_probe
                    )
                    failure_count = 0
                    circuit_open = False
                elif half_open_probe:
                    await self._cancel_deepseek_half_open_probe()
                logger.warning(
                    "deepseek_fallback role=%s reason=%s upstream_status=%s "
                    "failure_count=%s circuit_open=%s half_open_probe=%s",
                    role,
                    error.reason,
                    error.status_code,
                    failure_count,
                    circuit_open,
                    half_open_probe,
                )

        if openai_configured and time.monotonic() >= self._openai_unavailable_until:
            try:
                result = await self._complete_openai(
                    role=role,
                    messages=messages,
                    max_tokens=max_tokens,
                    require_json_object=require_json_object,
                )
                normalized = self._normalize_completion(
                    result,
                    require_json_object=require_json_object,
                    role=role,
                    request_id=request_id,
                )
                normalized = self._validate_current_v5_contract(
                    normalized,
                    provider=result.provider,
                    agent_task=agent_task,
                    request_id=request_id,
                    messages=messages,
                )
                logger.info(
                    "agent_role_completed request_id=%s role=%s agent_task=%s provider=openai model=%s",
                    request_id,
                    role,
                    agent_task,
                    result.model,
                )
                return Completion(
                    content=normalized,
                    provider=result.provider,
                    model=result.model,
                    finish_reason=result.finish_reason,
                    prompt_tokens=result.prompt_tokens,
                    completion_tokens=result.completion_tokens,
                )
            except ProviderError as error:
                last_error = error
                opens_circuit = self._is_availability_failure(error)
                cooldown_seconds = (
                    max(config.OPENAI_FAILURE_COOLDOWN_SECONDS, 0)
                    if opens_circuit
                    else 0.0
                )
                if opens_circuit:
                    self._openai_unavailable_until = (
                        time.monotonic() + cooldown_seconds
                    )
                logger.warning(
                    "openai_unavailable role=%s reason=%s upstream_status=%s cooldown_seconds=%s",
                    role,
                    error.reason,
                    error.status_code,
                    cooldown_seconds,
                )
        elif openai_configured:
            logger.info("openai_circuit_open role=%s", role)

        logger.error(
            "all_providers_failed role=%s last_provider=%s reason=%s upstream_status=%s",
            role,
            last_error.provider if last_error else "none",
            last_error.reason if last_error else "circuit_open_or_not_configured",
            last_error.status_code if last_error else None,
        )
        if not deepseek_configured and not openai_configured:
            raise HTTPException(503, "AI 服务尚未在服务器配置") from last_error
        if last_error and last_error.reason == "timeout":
            raise HTTPException(504, "AI 服务响应超时，请稍后重试") from last_error
        if last_error and last_error.reason == "queue_timeout":
            raise HTTPException(503, "AI 服务当前请求较多，请稍后重试") from last_error
        raise HTTPException(502, "暂时无法连接 AI 服务") from last_error

    async def _complete_deepseek_request(
        self,
        *,
        role: Role,
        agent_task: str,
        request_id: Optional[str],
        messages: list[dict[str, str]],
        max_tokens: int,
        temperature: float,
        require_json_object: bool,
    ) -> Completion:
        result = await self._complete_deepseek(
            role=role,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
        )
        tracking_diagnostic_active = _log_current_v5_tracking_request(
            request_id=request_id,
            agent_task=agent_task,
            messages=messages,
        )
        try:
            normalized = self._normalize_completion(
                result,
                require_json_object=require_json_object,
                role=role,
                request_id=request_id,
            )
            if tracking_diagnostic_active:
                _log_current_v5_tracking_decision(
                    request_id=request_id,
                    stage="raw_initial",
                    content=normalized,
                )
            normalized = self._validate_current_v5_contract(
                normalized,
                provider=result.provider,
                agent_task=agent_task,
                request_id=request_id,
                messages=messages,
            )
            if tracking_diagnostic_active:
                _log_current_v5_tracking_decision(
                    request_id=request_id,
                    stage="canonical_initial",
                    content=normalized,
                )
        except ProviderError as error:
            if (
                error.reason in {
                    "invalid_json",
                    "json_not_object",
                    "current_v5_planner_contract_shape_invalid",
                    "current_v5_planner_contract_invalid",
                }
                and require_json_object
                and not (
                    agent_task == "current_v5_core_planner"
                    and error.reason == "current_v5_planner_contract_invalid"
                )
                and (
                    self._is_repairable_dialogue_writer_task(
                        role=role,
                        agent_task=agent_task,
                    )
                    or self._is_repairable_turn_controller_task(
                        role=role,
                        agent_task=agent_task,
                    )
                )
            ):
                logger.warning(
                    "deepseek_json_repair request_id=%s role=%s agent_task=%s "
                    "model=%s original_finish_reason=%s original_content_chars=%s",
                    request_id,
                    role,
                    agent_task,
                    result.model,
                    result.finish_reason,
                    len(result.content),
                )
                if self._is_repairable_turn_controller_task(
                    role=role,
                    agent_task=agent_task,
                ):
                    result = await self._repair_deepseek_turn_controller_json(
                        draft=result.content,
                        original_messages=messages,
                        agent_task=agent_task,
                        model=result.model,
                        max_tokens=max_tokens,
                    )
                else:
                    result = await self._repair_deepseek_dialogue_json(
                        draft=result.content,
                        model=result.model,
                        max_tokens=max_tokens,
                    )
                normalized = self._normalize_completion(
                    result,
                    require_json_object=True,
                    role=role,
                    request_id=request_id,
                )
                if tracking_diagnostic_active:
                    _log_current_v5_tracking_decision(
                        request_id=request_id,
                        stage="raw_repair",
                        content=normalized,
                    )
                normalized = self._validate_current_v5_contract(
                    normalized,
                    provider=result.provider,
                    agent_task=agent_task,
                    request_id=request_id,
                    messages=messages,
                )
                if tracking_diagnostic_active:
                    _log_current_v5_tracking_decision(
                        request_id=request_id,
                        stage="canonical_repair",
                        content=normalized,
                    )
            else:
                raise
        return Completion(
            content=normalized,
            provider=result.provider,
            model=result.model,
            finish_reason=result.finish_reason,
            prompt_tokens=result.prompt_tokens,
            completion_tokens=result.completion_tokens,
        )

    @staticmethod
    def _validate_current_v5_contract(
        content: str,
        *,
        provider: str,
        agent_task: str,
        request_id: Optional[str],
        messages: list[dict[str, str]],
    ) -> str:
        if agent_task != "current_v5_core_planner":
            return content
        try:
            return canonicalize_current_v5_planner_contract(
                content,
                allowed_semantic_operations=_current_v5_allowed_operations(messages),
                reflection_mode=_current_v5_reflection_mode(messages),
            )
        except CurrentV5PlannerContractError as error:
            # Log only the schema location and violation class. The model body and reflection text
            # remain private, while operations can distinguish contract failures from outages.
            logger.warning(
                "provider_contract_invalid request_id=%s provider=%s agent_task=%s "
                "field_path=%s violation=%s",
                request_id,
                provider,
                agent_task,
                error.field_path,
                error.violation,
            )
            # A missing/malformed outer patch envelope is a formatter defect: the one existing
            # repair pass may restore that shape. The canonicalizer has already restored an
            # operation when Swift supplied exactly one capability; any remaining missing/invalid
            # operation is ambiguous. Provided-invalid typed evidence is authoritative and must
            # not be repaired into a different decision.
            repairable_envelope = (
                error.field_path == "semanticEvidencePatch"
                and error.violation in {"missing", "model_type", "dict_type"}
            )
            reason = (
                "current_v5_planner_contract_shape_invalid"
                if repairable_envelope
                else "current_v5_planner_contract_invalid"
            )
            raise ProviderError(provider, reason) from error

    async def _acquire_deepseek_slot(self) -> None:
        try:
            await asyncio.wait_for(
                self._deepseek_semaphore.acquire(),
                timeout=self._deepseek_queue_timeout_seconds,
            )
        except asyncio.TimeoutError as error:
            logger.warning(
                "deepseek_queue_timeout timeout_seconds=%s",
                self._deepseek_queue_timeout_seconds,
            )
            raise ProviderError("deepseek", "queue_timeout") from error

    async def _deepseek_attempt_permission(
        self,
        *,
        wait_when_open: bool,
    ) -> Optional[bool]:
        """Return False for a normal request, True for the sole half-open probe, or None to fall back.

        With no fallback configured, callers wait for a bounded interval and re-check state rather
        than inheriting another request's failure immediately.
        """
        deadline = time.monotonic() + self._deepseek_queue_timeout_seconds
        while True:
            async with self._deepseek_state_lock:
                now = time.monotonic()
                if not self._deepseek_circuit_open:
                    return False
                if now >= self._deepseek_next_probe_at and not self._deepseek_probe_in_flight:
                    self._deepseek_probe_in_flight = True
                    logger.info("deepseek_half_open_probe_started")
                    return True
                if not wait_when_open:
                    return None
                state_changed = self._deepseek_state_changed
                if self._deepseek_probe_in_flight:
                    wait_seconds = deadline - now
                else:
                    wait_seconds = min(
                        deadline - now,
                        max(0.01, self._deepseek_next_probe_at - now),
                    )
            if wait_seconds <= 0:
                raise ProviderError("deepseek", "queue_timeout")
            try:
                await asyncio.wait_for(state_changed.wait(), timeout=wait_seconds)
            except asyncio.TimeoutError:
                pass
            if time.monotonic() >= deadline:
                raise ProviderError("deepseek", "queue_timeout")

    async def _record_deepseek_availability_success(
        self,
        *,
        was_half_open_probe: bool,
    ) -> None:
        async with self._deepseek_state_lock:
            recovered = self._deepseek_circuit_open or was_half_open_probe
            self._deepseek_failure_times.clear()
            self._deepseek_circuit_open = False
            self._deepseek_next_probe_at = 0.0
            self._deepseek_probe_in_flight = False
            self._notify_deepseek_state_changed()
        if recovered:
            logger.info("deepseek_circuit_closed_after_probe")

    async def _record_deepseek_availability_failure(
        self,
        *,
        was_half_open_probe: bool,
    ) -> tuple[int, bool]:
        async with self._deepseek_state_lock:
            now = time.monotonic()
            window_seconds = max(config.DEEPSEEK_FAILURE_WINDOW_SECONDS, 0.01)
            while (
                self._deepseek_failure_times
                and self._deepseek_failure_times[0] < now - window_seconds
            ):
                self._deepseek_failure_times.popleft()
            self._deepseek_failure_times.append(now)
            failure_count = len(self._deepseek_failure_times)
            threshold = max(2, config.DEEPSEEK_FAILURE_THRESHOLD)
            was_open = self._deepseek_circuit_open
            if was_half_open_probe or was_open or failure_count >= threshold:
                self._deepseek_circuit_open = True
                self._deepseek_next_probe_at = (
                    now + max(config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS, 0.01)
                )
                self._deepseek_probe_in_flight = False
            self._notify_deepseek_state_changed()
            circuit_open = self._deepseek_circuit_open
        if circuit_open and not was_open:
            logger.warning(
                "deepseek_circuit_opened failure_count=%s threshold=%s "
                "half_open_after_seconds=%s",
                failure_count,
                threshold,
                config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS,
            )
        elif circuit_open and was_half_open_probe:
            logger.warning(
                "deepseek_half_open_probe_failed next_probe_after_seconds=%s",
                config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS,
            )
        return failure_count, circuit_open

    async def _cancel_deepseek_half_open_probe(self) -> None:
        async with self._deepseek_state_lock:
            if not self._deepseek_circuit_open:
                return
            self._deepseek_probe_in_flight = False
            self._deepseek_next_probe_at = (
                time.monotonic() + max(config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS, 0.01)
            )
            self._notify_deepseek_state_changed()

    def _notify_deepseek_state_changed(self) -> None:
        previous = self._deepseek_state_changed
        self._deepseek_state_changed = asyncio.Event()
        previous.set()

    @classmethod
    def _normalize_completion(
        cls,
        result: Completion,
        *,
        require_json_object: bool,
        role: Role,
        request_id: Optional[str],
    ) -> str:
        return cls._normalize_content(
            result.content,
            require_json_object,
            provider=result.provider,
            model=result.model,
            role=role,
            request_id=request_id,
            finish_reason=result.finish_reason,
            prompt_tokens=result.prompt_tokens,
            completion_tokens=result.completion_tokens,
        )

    @staticmethod
    def _is_availability_failure(error: ProviderError) -> bool:
        if error.reason in {"timeout", "connection_error"}:
            return True
        return (
            error.reason == "upstream_http_error"
            and error.status_code in {408, 429, 500, 502, 503, 504}
        )

    @staticmethod
    def _normalize_content(
        content: str,
        require_json_object: bool,
        *,
        provider: str,
        model: Optional[str] = None,
        role: Optional[str] = None,
        request_id: Optional[str] = None,
        finish_reason: Optional[str] = None,
        prompt_tokens: Optional[int] = None,
        completion_tokens: Optional[int] = None,
    ) -> str:
        stripped = content.strip()
        if not stripped:
            raise ProviderError(provider, "empty_response")
        if not require_json_object:
            return stripped

        candidates = [stripped]
        if stripped.startswith("```") and stripped.endswith("```"):
            fenced = stripped[3:-3].strip()
            if fenced.lower().startswith("json"):
                fenced = fenced[4:].lstrip()
            candidates.append(fenced)
        first_brace = stripped.find("{")
        last_brace = stripped.rfind("}")
        if first_brace >= 0 and last_brace > first_brace:
            candidates.append(stripped[first_brace : last_brace + 1])

        last_json_error: Optional[json.JSONDecodeError] = None
        for candidate in candidates:
            try:
                decoded = json.loads(candidate)
            except json.JSONDecodeError as error:
                last_json_error = error
                continue
            except (TypeError, ValueError):
                continue
            if isinstance(decoded, dict):
                return json.dumps(decoded, ensure_ascii=False, separators=(",", ":"))
            raise ProviderError(provider, "json_not_object")

        content_hash = hashlib.sha256(stripped.encode("utf-8")).hexdigest()[:12]
        logger.warning(
            "provider_invalid_json request_id=%s role=%s provider=%s model=%s "
            "finish_reason=%s prompt_tokens=%s completion_tokens=%s "
            "content_chars=%s starts_object=%s ends_object=%s starts_fence=%s "
            "open_braces=%s close_braces=%s json_error=%s line=%s column=%s "
            "position=%s content_hash=%s",
            request_id,
            role,
            provider,
            model,
            finish_reason,
            prompt_tokens,
            completion_tokens,
            len(stripped),
            stripped.startswith("{"),
            stripped.endswith("}"),
            stripped.startswith("```"),
            stripped.count("{"),
            stripped.count("}"),
            last_json_error.msg if last_json_error else "unknown",
            last_json_error.lineno if last_json_error else None,
            last_json_error.colno if last_json_error else None,
            last_json_error.pos if last_json_error else None,
            content_hash,
        )
        raise ProviderError(provider, "invalid_json")

    @staticmethod
    def _model(provider: Literal["openai", "deepseek"], role: Role) -> str:
        prefix = provider.upper()
        return getattr(config, f"{prefix}_{role.upper()}_MODEL")

    async def _complete_openai(
        self,
        *,
        role: Role,
        messages: list[dict[str, str]],
        max_tokens: int,
        require_json_object: bool,
    ) -> Completion:
        if not config.OPENAI_API_KEY:
            raise ProviderError("openai", "not_configured")
        model = self._model("openai", role)
        content = await self._request_openai_responses(
            base_url=config.OPENAI_BASE_URL,
            api_key=config.OPENAI_API_KEY,
            model=model,
            messages=messages,
            max_tokens=max_tokens,
            reasoning_effort=getattr(
                config, f"OPENAI_{role.upper()}_REASONING_EFFORT"
            ),
            timeout_seconds=config.OPENAI_TIMEOUT_SECONDS,
            require_json_object=require_json_object,
        )
        return Completion(content=content, provider="openai", model=model)

    async def _complete_deepseek(
        self,
        *,
        role: Role,
        messages: list[dict[str, str]],
        max_tokens: int,
        temperature: float,
    ) -> Completion:
        if not config.DEEPSEEK_API_KEY:
            raise ProviderError("deepseek", "not_configured")
        model = self._model("deepseek", role)
        reasoning_payload = self._deepseek_reasoning_payload(model=model, role=role)
        result = await self._request_openai_compatible(
            provider="deepseek",
            base_url=config.DEEPSEEK_BASE_URL,
            api_key=config.DEEPSEEK_API_KEY,
            model=model,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
            timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
            supports_json_mode=True,
            extra_payload=reasoning_payload,
        )
        if (
            not result.content.strip()
            and reasoning_payload.get("thinking", {}).get("type") == "enabled"
        ):
            logger.warning("deepseek_empty_reasoning_retry role=%s model=%s", role, model)
            result = await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )
        if not result.content.strip():
            # Some DeepSeek V4 responses finish with no final content while strict JSON mode is
            # active. The trusted prompts already require one JSON object, and the gateway's
            # normalizer still validates it, so one retry without response_format is safe.
            logger.warning("deepseek_empty_json_mode_retry role=%s model=%s", role, model)
            result = await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=messages,
                max_tokens=max(max_tokens, 1600),
                temperature=temperature,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=False,
                extra_payload={"thinking": {"type": "disabled"}},
            )
        return result

    async def _repair_deepseek_dialogue_json(
        self,
        *,
        draft: str,
        model: str,
        max_tokens: int,
    ) -> Completion:
        """Convert one already-generated dialogue draft into the strict visible-turn contract.

        This bounded second pass receives only the draft, not the long reflection prompt. It may
        restore structure but may not add content, advice, interpretations, or workflow decisions.
        """
        repair_messages = [
            {
                "role": "system",
                "content": (
                    "You are a strict JSON formatter. Convert DRAFT into exactly one valid JSON "
                    "object and output nothing else. Preserve its language and meaning; do not add "
                    "advice, interpretation, facts, or a second question. Put non-question wording "
                    "in reflection and at most one explicit question in question. Unless DRAFT "
                    "already contains explicit structured action choices, use an empty actionOptions "
                    "array. Required schema: "
                    '{"reflection":"","question":"","actionOptions":[]}. '
                    "If actionOptions are present, keep at most two and encode each as "
                    '{"category":"care|repair|protect|change","description":"",'
                    '"timing":null,"rationale":""}.'
                ),
            },
            {
                "role": "user",
                "content": json.dumps({"DRAFT": draft}, ensure_ascii=False),
            },
        ]
        return await self._request_openai_compatible(
            provider="deepseek",
            base_url=config.DEEPSEEK_BASE_URL,
            api_key=config.DEEPSEEK_API_KEY,
            model=model,
            messages=repair_messages,
            max_tokens=max(320, min(max_tokens, 1000)),
            temperature=0.0,
            timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
            supports_json_mode=True,
            extra_payload={"thinking": {"type": "disabled"}},
        )

    async def _repair_deepseek_turn_controller_json(
        self,
        *,
        draft: str,
        original_messages: list[dict[str, str]],
        agent_task: str,
        model: str,
        max_tokens: int,
    ) -> Completion:
        """Repair structure without allowing a formatter to invent protocol permissions."""
        if agent_task == "current_v5_core_writer":
            repair_messages = [
                {
                    "role": "system",
                    "content": (
                        "You are a strict JSON formatter. Preserve the DRAFT wording exactly and "
                        'return only {"reply":""}. Do not add, remove, answer, or rewrite a question.'
                    ),
                },
                {"role": "user", "content": json.dumps({"DRAFT": draft}, ensure_ascii=False)},
            ]
            return await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=repair_messages,
                max_tokens=max(240, min(max_tokens, 700)),
                temperature=0.0,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )

        if agent_task == "current_v5_core_planner":
            repair_messages = [
                {
                    "role": "system",
                    "content": (
                        "Repair JSON syntax and types only; do not re-plan or infer missing evidence. "
                        "Preserve the DRAFT semanticOperation, sparse memoryUpdate, card connection "
                        "outcome, and responseFocus. Return only: "
                        + CURRENT_V5_PLANNER_JSON_SHAPE
                    ),
                },
                {
                    "role": "user",
                    # Repair sees only the malformed draft. The original request can contain
                    # persisted Swift-owned input context and has no role in syntax formatting.
                    "content": json.dumps({"DRAFT": draft}, ensure_ascii=False),
                },
            ]
            return await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=repair_messages,
                max_tokens=max(500, min(max_tokens, 1300)),
                temperature=0.0,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )

        if agent_task in {"turn_controller_plan_critic", "turn_controller_critic"}:
            permission_context = "\n".join(
                message.get("content", "")
                for message in original_messages
                if message.get("role") in {"system", "user"}
            )
            is_plan_critic = agent_task == "turn_controller_plan_critic"
            allowed_revision = "revisePlanner" if is_plan_critic else "reviseWriter"
            critic_name = "Plan Critic" if is_plan_critic else "Writer Critic"
            repair_messages = [
                {
                    "role": "system",
                    "content": (
                        f"You are a strict JSON formatter for a TurnController {critic_name}. "
                        "Preserve the DRAFT judgment and return exactly one object: "
                        '{"verdict":"pass","reasonCodes":[],"revisionGuidance":null}. '
                        f"verdict must be pass or {allowed_revision}. reasonCodes must be an array of "
                        "strings and revisionGuidance must be a string or null. Do not add new "
                        "interpretations or dialogue content."
                    ),
                },
                {
                    "role": "user",
                    "content": json.dumps(
                        {
                            "ORIGINAL_REQUEST": permission_context,
                            "DRAFT": draft,
                        },
                        ensure_ascii=False,
                    ),
                },
            ]
            return await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=repair_messages,
                max_tokens=max(160, min(max_tokens, 320)),
                temperature=0.0,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )

        if agent_task in {"turn_controller_writer", "turn_controller_writer_revision"}:
            permission_context = "\n".join(
                message.get("content", "")
                for message in original_messages
                if message.get("role") in {"system", "user"}
            )
            repair_messages = [
                {
                    "role": "system",
                    "content": (
                        "You are a strict JSON formatter. Preserve the DRAFT wording and return "
                        'exactly one JSON object: {"realizedIntent":"","reply":""}. Copy '
                        "realizedIntent exactly from VALIDATED SEMANTIC TURN PLAN in "
                        "ORIGINAL_REQUEST. Do not add, remove, answer, or rewrite a question. Do "
                        "not add interpretation, advice, or explanation."
                    ),
                },
                {
                    "role": "user",
                    "content": json.dumps(
                        {
                            "ORIGINAL_REQUEST": permission_context,
                            "DRAFT": draft,
                        },
                        ensure_ascii=False,
                    ),
                },
            ]
            return await self._request_openai_compatible(
                provider="deepseek",
                base_url=config.DEEPSEEK_BASE_URL,
                api_key=config.DEEPSEEK_API_KEY,
                model=model,
                messages=repair_messages,
                max_tokens=max(240, min(max_tokens, 700)),
                temperature=0.0,
                timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )

        repair_messages = _planner_json_repair_messages(
            draft=draft,
            original_messages=original_messages,
        )
        bounds = _planner_repair_bounds(original_messages)
        total_characters = sum(len(message["content"]) for message in repair_messages)
        encoded_draft = json.dumps(draft, ensure_ascii=False, separators=(",", ":"))
        log_prompt_length(
            PromptLengthMetrics(
                component="planner_json_repair",
                stage=str(bounds.get("protocolStage") or "unknown"),
                protocol_version=int(bounds.get("protocolVersion") or 0),
                substate=str(bounds.get("cardConnectionInteractionState") or "none"),
                shared_characters=len(PLANNER_JSON_REPAIR_CONTRACT) - len(PLANNER_JSON_SHAPE),
                stage_characters=0,
                substate_characters=0,
                dynamic_state_characters=len(repair_messages[1]["content"]) - len(encoded_draft),
                schema_characters=len(PLANNER_JSON_SHAPE),
                conversation_characters=0,
                recovery_characters=len(encoded_draft),
                provider_format_characters=0,
                total_characters=total_characters,
                estimated_tokens=(total_characters + 3) // 4,
            )
        )
        return await self._request_openai_compatible(
            provider="deepseek",
            base_url=config.DEEPSEEK_BASE_URL,
            api_key=config.DEEPSEEK_API_KEY,
            model=model,
            messages=repair_messages,
            max_tokens=max(600, min(max_tokens, 1600)),
            temperature=0.0,
            timeout_seconds=config.DEEPSEEK_TIMEOUT_SECONDS,
            supports_json_mode=True,
            extra_payload={"thinking": {"type": "disabled"}},
        )

    @staticmethod
    def _is_repairable_dialogue_writer_task(*, role: Role, agent_task: str) -> bool:
        """Limit the short formatter retry to user-visible dialogue Writer passes.

        Planner/analyzer JSON has a different schema and must fail validation instead of being
        coerced into a dialogue turn. These task names cover the initial Writer, its direct
        planner-fallback path, the critic revision, and the one-question repair pass.
        """
        return role == "writer" and (
            agent_task.startswith("dialogue_generation")
            or agent_task in {"writer_revision", "question_count_repair"}
        )

    @staticmethod
    def _is_repairable_turn_controller_task(*, role: Role, agent_task: str) -> bool:
        expected_roles: dict[str, Role] = {
            "current_v5_core_planner": "writer",
            "current_v5_core_writer": "writer",
            "turn_controller_planner": "writer",
            "turn_controller_plan_critic": "critic",
            "turn_controller_writer": "writer",
            "turn_controller_writer_revision": "writer",
            "turn_controller_critic": "critic",
        }
        return expected_roles.get(agent_task) == role

    @staticmethod
    def _deepseek_reasoning_payload(*, model: str, role: Role) -> dict[str, Any]:
        if not model.startswith("deepseek-v4-"):
            return {}
        thinking = getattr(config, f"DEEPSEEK_{role.upper()}_THINKING")
        if thinking == "disabled":
            return {"thinking": {"type": "disabled"}}
        effort = getattr(config, f"DEEPSEEK_{role.upper()}_REASONING_EFFORT")
        return {
            "thinking": {"type": thinking},
            "reasoning_effort": effort,
        }

    async def _request_openai_compatible(
        self,
        *,
        provider: str,
        base_url: str,
        api_key: str,
        model: str,
        messages: list[dict[str, str]],
        max_tokens: int,
        temperature: float,
        timeout_seconds: float,
        supports_json_mode: bool,
        extra_payload: Optional[dict[str, Any]] = None,
    ) -> Completion:
        payload: dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": messages,
        }
        if supports_json_mode:
            payload["response_format"] = {"type": "json_object"}
        if extra_payload:
            payload.update(extra_payload)
        response = await self._post(
            provider=provider,
            url=f"{base_url}/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            payload=payload,
            timeout_seconds=timeout_seconds,
        )
        try:
            data = response.json()
            choice = data["choices"][0]
            message = choice["message"]
            content = message["content"]
            usage = data.get("usage") or {}
        except (ValueError, KeyError, IndexError, TypeError) as error:
            raise ProviderError(provider, "malformed_response", response.status_code) from error
        if not isinstance(content, str):
            raise ProviderError(provider, "malformed_response", response.status_code)
        if not content.strip():
            reasoning = message.get("reasoning_content")
            logger.warning(
                "provider_empty_content provider=%s model=%s finish_reason=%s reasoning_chars=%s",
                provider,
                model,
                choice.get("finish_reason"),
                len(reasoning) if isinstance(reasoning, str) else 0,
            )
        if not isinstance(usage, dict):
            usage = {}
        return Completion(
            content=content.strip(),
            provider=provider,
            model=model,
            finish_reason=choice.get("finish_reason"),
            prompt_tokens=usage.get("prompt_tokens"),
            completion_tokens=usage.get("completion_tokens"),
        )

    async def _request_openai_responses(
        self,
        *,
        base_url: str,
        api_key: str,
        model: str,
        messages: list[dict[str, str]],
        max_tokens: int,
        reasoning_effort: str,
        timeout_seconds: float,
        require_json_object: bool,
    ) -> str:
        payload: dict[str, Any] = {
            "model": model,
            "input": messages,
            "max_output_tokens": max(max_tokens, 256),
            "store": False,
        }
        # GPT-4o and other non-reasoning models reject the reasoning parameter.
        # Keep one Responses API implementation, but only send reasoning controls
        # to model families that currently support them.
        normalized_model = model.strip().lower()
        supports_reasoning_effort = normalized_model.startswith(
            ("gpt-5", "o1", "o3", "o4")
        )
        if supports_reasoning_effort and reasoning_effort != "none":
            payload["reasoning"] = {"effort": reasoning_effort}
        if require_json_object:
            payload["text"] = {"format": {"type": "json_object"}}

        response = await self._post(
            provider="openai",
            url=f"{base_url}/responses",
            headers={"Authorization": f"Bearer {api_key}"},
            payload=payload,
            timeout_seconds=timeout_seconds,
        )
        try:
            data = response.json()
            output = data["output"]
            content = "".join(
                part.get("text", "")
                for item in output
                if isinstance(item, dict) and item.get("type") == "message"
                for part in item.get("content", [])
                if isinstance(part, dict) and part.get("type") == "output_text"
            )
            refusal = "".join(
                part.get("refusal", "")
                for item in output
                if isinstance(item, dict) and item.get("type") == "message"
                for part in item.get("content", [])
                if isinstance(part, dict) and part.get("type") == "refusal"
            )
        except (ValueError, KeyError, TypeError) as error:
            raise ProviderError("openai", "malformed_response", response.status_code) from error
        if refusal and not content.strip():
            raise ProviderError("openai", "refusal", response.status_code)
        if not isinstance(content, str) or not content.strip():
            raise ProviderError("openai", "empty_response", response.status_code)
        return content.strip()

    async def _post(
        self,
        *,
        provider: str,
        url: str,
        headers: dict[str, str],
        payload: dict[str, Any],
        timeout_seconds: float,
    ) -> httpx.Response:
        attempts = max(1, config.PROVIDER_RETRY_ATTEMPTS)
        timeout = httpx.Timeout(timeout_seconds, connect=min(8.0, timeout_seconds))
        client = await self._get_http_client()
        for attempt in range(attempts):
            try:
                response = await client.post(
                    url,
                    headers=headers,
                    json=payload,
                    timeout=timeout,
                )
            except httpx.ConnectTimeout as error:
                if attempt + 1 >= attempts:
                    raise ProviderError(provider, "timeout") from error
                logger.warning(
                    "provider_transient_retry provider=%s reason=connect_timeout attempt=%s",
                    provider,
                    attempt + 1,
                )
            except httpx.TimeoutException as error:
                # Repeating a full read timeout can double an already long user wait. The
                # agent will instead degrade to a simpler role or a local safe response.
                raise ProviderError(provider, "timeout") from error
            except httpx.HTTPError as error:
                if attempt + 1 >= attempts:
                    raise ProviderError(provider, "connection_error") from error
                logger.warning(
                    "provider_transient_retry provider=%s reason=connection_error attempt=%s",
                    provider,
                    attempt + 1,
                )
            else:
                if response.is_success:
                    return response
                retryable = response.status_code in {408, 429, 500, 502, 503, 504}
                if not retryable or attempt + 1 >= attempts:
                    # Provider bodies are intentionally not logged or forwarded.
                    raise ProviderError(
                        provider, "upstream_http_error", response.status_code
                    )
                logger.warning(
                    "provider_transient_retry provider=%s upstream_status=%s attempt=%s",
                    provider,
                    response.status_code,
                    attempt + 1,
                )
            await asyncio.sleep(
                max(0.0, config.PROVIDER_RETRY_BACKOFF_SECONDS) * (attempt + 1)
            )
        raise ProviderError(provider, "connection_error")


gateway = ProviderGateway()
