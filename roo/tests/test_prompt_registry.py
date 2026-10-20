from __future__ import annotations

import json
import unittest
from pathlib import Path

from fastapi import HTTPException

from app.prompt_registry import (
    CARD_EVIDENCE_RULES,
    CONFIRMATION_RULES,
    DISCLOSURE_MEMORY_CONTRACT,
    GLOBAL_PROTOCOL_INVARIANTS,
    GROUNDING_RULES,
    OUTPUT_DISCIPLINE,
    PLAN_CRITIC_REASON_CODES,
    PLANNER_JSON_SHAPE,
    PLANNER_SEMANTIC_OPERATION_CONTRACT,
    PLANNER_SEMANTIC_OPERATION_SCHEMA,
    PLANNER_SEMANTIC_OPERATION_VALUES,
    RECOVERY_DISCIPLINE,
    RECOVERY_OPERATION_CONTRACTS,
    SELF_COMPASSION_RULES,
    TURN_PROMPT_VERSION,
    WRITER_CRITIC_REASON_CODES,
    WRITER_STYLE,
    build_turn_messages,
    turn_prompt_chat,
    validate_planner_semantic_operation,
)
from app.schemas import LLMTurnPromptIn


def request_payload(*, condition: str = "cardMediated", stage: str = "contextualDisclosure") -> dict:
    request = {
        "trigger": "userMessage",
        "protocolVersion": 5,
        "protocolStage": stage,
        "recoveryOperation": {
            "contextualDisclosure": "eventDisclosure",
            "cardConsent": "cardConsent",
            "cardReflection": "cardOpenExploration",
            "directReflection": "directReflection",
            "narrativeConfirmation": "finalNarrative",
            "optionalAction": "optionalAction",
            "complete": "complete",
            "safetySupport": "safety",
        }.get(stage, "eventDisclosure"),
        "condition": condition,
        "permissions": {
            "currentStage": stage,
            "allowedStages": [stage],
            "allowedActions": ["none"],
            "allowedReplyIntents": ["exploreContext"],
            "allowedDisclosurePurposes": [],
            "allowedDisclosureTargets": [],
            "allowedOperations": [
                {
                    "requestedStage": stage,
                    "replyIntent": "exploreContext",
                    "localAction": "none",
                }
            ],
        },
        "recentMessages": [{"role": "user", "content": "用户提供的一段具体经历"}],
        "semanticMemory": {},
        "trackingCandidates": [],
        "contextualLoadCue": None,
        "presentedTrackingCues": [],
        "activeTrackingPresentation": None,
        "cardMappingConfirmed": False,
        "card": None,
        "protocolCorrection": None,
    }
    if stage == "contextualDisclosure":
        request["permissions"].update(
            {
                "allowedStages": ["contextualDisclosure", "cardConsent"],
                "allowedReplyIntents": ["exploreContext", "inviteCardConsent"],
                "allowedDisclosurePurposes": [
                    "identifyConcreteEpisode",
                    "clarifyBehavior",
                    "clarifyEventProcess",
                ],
                "allowedDisclosureTargets": ["focalEvent", "behavior", "eventProcess"],
                "allowedOperations": [
                    {
                        "requestedStage": "contextualDisclosure",
                        "replyIntent": "exploreContext",
                        "localAction": "none",
                    },
                    {
                        "requestedStage": "cardConsent",
                        "replyIntent": "inviteCardConsent",
                        "localAction": "none",
                    },
                ],
            }
        )
    elif stage == "cardReflection":
        request["permissions"].update(
            {
                "allowedStages": ["cardReflection", "directReflection"],
                "allowedReplyIntents": [
                    "developCardImage",
                    "inviteCardConnection",
                    "presentCardReading",
                    "directCandidReflection",
                ],
                "allowedOperations": [],
            }
        )
        request["card"] = {
            "imageIsDisplayed": True,
            "imageDevelopmentTurnCount": 1,
            "connectionAttemptCount": 0,
            "connectionScaffoldUsed": False,
            "connectionUnavailable": False,
            "connectionInteractionState": "openExploration",
            "realityAnchor": {
                "concreteFacts": ["当前焦点事件"],
                "eventProcess": ["事件发展"],
                "impacts": ["现实结果"],
            },
            "visualScaffolds": [],
            "reflectionApproaches": None,
            "prohibitedClaims": [],
        }
    elif stage == "directReflection":
        request["permissions"].update(
            {
                "allowedStages": ["directReflection", "optionalAction"],
                "allowedReplyIntents": ["directCandidReflection", "suggestPractice"],
                "allowedOperations": [],
            }
        )
    return request


def item(task: str, payload: dict, *, version: str | None = None) -> LLMTurnPromptIn:
    return LLMTurnPromptIn(
        promptTask=task,
        promptVersion=version or TURN_PROMPT_VERSION,
        payload=payload,
        maxTokens=700,
        temperature=0.2,
    )


def plan(*, stage: str = "contextualDisclosure", intent: str = "exploreContext") -> dict:
    return {
        "requestedStage": stage,
        "localAction": {"kind": "none", "trackingCueIDs": []},
        "memoryUpdate": {},
        "cardConnectionTurnOutcome": None,
        "resolvedConfirmation": None,
        "nextPrompt": {
            "kind": "openQuestion",
            "purpose": "one_typed_function",
            "focus": "one unresolved relation",
            "disclosurePurpose": "clarifyEventProcess" if stage == "contextualDisclosure" else None,
            "disclosureTarget": "eventProcess" if stage == "contextualDisclosure" else None,
            "disclosureReopenReason": None,
            "target": None,
            "referenceID": None,
        },
        "replyIntent": intent,
        "replyGuidance": "realize one typed function",
        "cardReferenceSelection": None,
    }


def prompt_for(task: str, request: dict, candidate: dict | None = None):
    candidate = candidate or plan(stage=request["protocolStage"])
    payload = {"request": request}
    if task != "planner":
        payload["plan"] = candidate
    if task == "writer_critic":
        payload["draft"] = {"realizedIntent": candidate["replyIntent"], "reply": "候选回复"}
    if task == "writer_revision":
        payload.update(
            {
                "draft": {"realizedIntent": candidate["replyIntent"], "reply": "候选回复"},
                "critique": {
                    "verdict": "reviseWriter",
                    "reasonCodes": ["unnatural_chinese"],
                    "revisionGuidance": "revise wording only",
                },
            }
        )
    return build_turn_messages(item(task, payload))


class PromptRegistryTests(unittest.TestCase):
    def test_registry_builds_every_current_role_and_keeps_call_parameters(self) -> None:
        request = request_payload()
        for task in ("planner", "plan_critic", "writer", "writer_critic", "writer_revision"):
            with self.subTest(task=task):
                prompt = prompt_for(task, request)
                self.assertTrue(prompt.system)
                self.assertTrue(prompt.user)
        chat = turn_prompt_chat(item("planner", {"request": request}))
        self.assertEqual(chat.agentMode, "fast")
        self.assertEqual(chat.maxTokens, 700)
        self.assertEqual(chat.temperature, 0.2)
        self.assertEqual(len(chat.messages), 2)

    def test_v45_uses_shared_fragments_as_single_source(self) -> None:
        self.assertEqual(TURN_PROMPT_VERSION, "turn-v4-server-v45")
        source = (Path(__file__).resolve().parents[1] / "app/prompt_registry.py").read_text(
            encoding="utf-8"
        )
        for name in (
            "GLOBAL_PROTOCOL_INVARIANTS",
            "GROUNDING_RULES",
            "CONFIRMATION_RULES",
            "CARD_EVIDENCE_RULES",
            "SELF_COMPASSION_RULES",
            "OUTPUT_DISCIPLINE",
            "WRITER_STYLE",
            "RECOVERY_DISCIPLINE",
        ):
            with self.subTest(fragment=name):
                self.assertEqual(source.count(f"{name} ="), 1)
        for retired in ("CURRENT_SEMANTIC_CONTRACT", "DIRECT_REFLECTION_SEMANTIC_CONTRACT"):
            self.assertNotIn(retired, source)

    def test_planner_is_state_goal_allowed_forbidden_and_output_only(self) -> None:
        prompt = prompt_for("planner", request_payload())
        for heading in (
            "ROLE",
            "SHARED INVARIANTS",
            "STATE MEMORY",
            "CONDITION",
            "STAGE GOAL / DELTA",
            "ALLOWED",
            "RECOVERY",
            "OUTPUT CONTRACT",
        ):
            self.assertIn(heading, prompt.system)
        self.assertIn(GLOBAL_PROTOCOL_INVARIANTS, prompt.system)
        self.assertIn(GROUNDING_RULES, prompt.system)
        self.assertNotIn(CONFIRMATION_RULES, prompt.system)
        self.assertIn(OUTPUT_DISCIPLINE, prompt.system)
        self.assertIn(PLANNER_JSON_SHAPE, prompt.system)
        self.assertNotIn(WRITER_STYLE, prompt.system)
        self.assertIn('"recentMessages"', prompt.user)
        self.assertNotIn("systemPrompt", prompt.user)

    def test_event_disclosure_delta_keeps_only_three_completion_relations(self) -> None:
        prompt = prompt_for("planner", request_payload())
        self.assertIn(DISCLOSURE_MEMORY_CONTRACT, prompt.system)
        self.assertIn("eventProcess records how it", prompt.system)
        for relation in (
            "identifyConcreteEpisode→focalEvent",
            "clarifyEventProcess→eventProcess",
            "clarifyBehavior→behavior",
        ):
            self.assertIn(relation, prompt.system)
        for optional in ("impact", "emotion", "importance", "self-judgment", "responsibility"):
            self.assertIn(optional, prompt.system)
        self.assertIn("optional, never gates", prompt.system)
        self.assertIn("External-result episodes", prompt.system)
        self.assertIn("never presumes blame", prompt.system)
        for retired in (
            "clarifyImmediateOutcome",
            "clarifyReflectionFocus",
            "reflectionFocusKind",
            "tenderGroundingKind",
        ):
            self.assertNotIn(retired, prompt.system)

    def test_card_connection_delta_preserves_typed_union_and_swift_resolution(self) -> None:
        open_request = request_payload(stage="cardReflection")
        open_request["card"]["imageDevelopmentTurnCount"] = 2
        open_prompt = prompt_for("planner", open_request)
        self.assertIn(CARD_EVIDENCE_RULES, open_prompt.system)
        self.assertIn("userAuthoredConnection", open_prompt.system)
        self.assertIn("connectionStillUnclear", open_prompt.system)
        self.assertNotIn("candidateAccepted", open_prompt.system)

        pending_request = request_payload(stage="cardReflection")
        pending_request["card"]["connectionInteractionState"] = "awaitingCandidateResolution"
        pending_request["semanticMemory"] = {
            "pendingCardRealityConnection": {
                "id": "candidate-1",
                "imageRelation": "one relation",
                "realityMapping": "one mapping",
                "status": "pending",
            }
        }
        pending_prompt = prompt_for("planner", pending_request)
        for outcome in ("candidateAccepted", "candidateRevised", "candidateRejected"):
            self.assertIn(outcome, pending_prompt.system)
        self.assertNotIn("userAuthoredConnection", pending_prompt.system)
        self.assertIn("only candidate", pending_prompt.system)
        self.assertIn("Swift derives raw connection projections", pending_prompt.system)
        self.assertIn("Retired", pending_prompt.system)
        self.assertNotIn(
            '"target":"trackingRelationship|cardConsent|cardRealityConnection|cardMapping',
            pending_prompt.system,
        )

    def test_card_observation_connection_context_and_reference_boundaries_remain(self) -> None:
        observation_request = request_payload(stage="cardReflection")
        observation_request["card"]["imageDevelopmentTurnCount"] = 0
        observation_request["trigger"] = "cardDisplayed"
        observation = prompt_for("planner", observation_request)
        self.assertIn("Observation:", observation.system)
        self.assertNotIn("Candidate resolution:", observation.system)

        development_request = request_payload(stage="cardReflection")
        development_request["card"]["imageDevelopmentTurnCount"] = 0
        development = prompt_for("planner", development_request)
        self.assertIn("Development:", development.system)
        self.assertIn("what may happen or change next", development.system)
        self.assertIn("userAuthoredConnection", development.system)
        self.assertNotIn("candidateAccepted", development.system)

        guidance_request = request_payload(stage="cardReflection")
        guidance_request["card"]["reflectionApproaches"] = {"available": True}
        guidance_request["cardMappingConfirmed"] = True
        guidance = prompt_for("planner", guidance_request)
        self.assertIn("Guidance:", guidance.system)
        self.assertIn("canonical connection is complete", guidance.system)
        self.assertIn("never creates another mapping/meaning confirmation", guidance.system)
        self.assertNotIn("connectionStillUnclear", guidance.system)

    def test_direct_reflection_preserves_tender_fierce_and_action_order(self) -> None:
        request = request_payload(stage="directReflection")
        planner = prompt_for("planner", request)
        critic = prompt_for("plan_critic", request)
        self.assertIn(SELF_COMPASSION_RULES, planner.system)
        self.assertIn("Tender grounds every reflection", planner.system)
        self.assertIn("Self-criticism judges", planner.system)
        self.assertIn("uncertainty marks", planner.system)
        self.assertIn("Fierce optionally adds Tender-grounded candor", planner.system)
        self.assertIn("synthesizeUnderstanding", planner.system)
        self.assertIn("before final narrative", planner.system)
        for code in (
            "reflection_mode_not_grounded",
            "forced_fierce_material",
            "rejected_premise_reused",
            "future_worry_treated_as_self_criticism",
            "uncertainty_treated_as_failure_evidence",
            "self_compassion_dimension_forced",
            "reflection_without_progress",
        ):
            self.assertIn(code, critic.system)

    def test_optional_action_and_no_action_contract_remains_atomic(self) -> None:
        request = request_payload(stage="narrativeConfirmation")
        planner = prompt_for("planner", request)
        critic = prompt_for("plan_critic", request)
        for value in ("care|repair|protect|change|noAction", "transactionID", "narrativeReferenceID"):
            self.assertIn(value, planner.system)
        self.assertIn("proposal IDs match", planner.system)
        self.assertIn("Proactive noAction", critic.system)
        self.assertIn("source=userRevised", critic.system)
        for retired in ("practiceOptions", "selectedPractice"):
            self.assertNotIn(retired, planner.system)

    def test_confirmation_rule_is_shared_and_card_reality_is_not_a_raw_target(self) -> None:
        for stage in ("contextualDisclosure", "cardReflection", "directReflection"):
            with self.subTest(stage=stage):
                request = request_payload(stage=stage)
                request["semanticMemory"] = {
                    "nextPrompt": {
                        "kind": "confirmationRequest",
                        "target": "cardMapping",
                        "referenceID": "pending-1",
                    }
                }
                planner = prompt_for("planner", request)
                self.assertIn(CONFIRMATION_RULES, planner.system)
        ordinary = prompt_for("planner", request_payload())
        self.assertNotIn(CONFIRMATION_RULES, ordinary.system)
        self.assertNotIn("cardRealityConnection|cardMapping", PLANNER_JSON_SHAPE)

    def test_writer_is_surface_only_and_stage_scoped(self) -> None:
        request = request_payload()
        disclosure = prompt_for("writer", request)
        invite = plan(stage="cardConsent", intent="inviteCardConsent")
        invite["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosurePurpose": None,
            "disclosureTarget": None,
            "disclosureReopenReason": None,
            "target": "cardConsent",
            "referenceID": None,
        }
        invitation = prompt_for("writer", request, invite)
        self.assertIn(WRITER_STYLE, disclosure.system)
        self.assertIn("Surface realization only", disclosure.system)
        self.assertIn("without acknowledgement or paraphrase preface", disclosure.system)
        self.assertIn("一张随机反思卡", invitation.system)
        self.assertIn("preview card title/image/symbol/theme/meaning", invitation.system)
        self.assertIn("explicit broad self-judgment", invitation.system)

    def test_writer_critic_is_stage_specific_not_a_second_planner(self) -> None:
        disclosure = prompt_for("writer_critic", request_payload())
        card_request = request_payload(stage="cardReflection")
        card_request["card"]["imageDevelopmentTurnCount"] = 0
        card = prompt_for("writer_critic", card_request)
        self.assertIn("Do not write the replacement", disclosure.system)
        self.assertIn("typed purpose/target", disclosure.system)
        self.assertNotIn("possible-next-change", disclosure.system)
        self.assertIn("possible-next-change", card.system)
        self.assertNotIn(PLANNER_JSON_SHAPE, disclosure.system)
        for code in ("disclosure_reporting_preface", "disclosure_scope_violation"):
            self.assertIn(code, disclosure.system)
        self.assertNotIn("reflection_without_progress", disclosure.system)
        self.assertIn("unsupported_contextual_inference", card.system)

    def test_reason_code_catalogues_preserve_existing_codes(self) -> None:
        for code in (
            "episode_structure_misclassified",
            "unsupported_decision_premise",
            "user_connection_not_committed",
            "legacy_card_connection_patch_not_allowed",
            "practice_evidence_mismatch",
            "completion_contract_invalid",
        ):
            self.assertIn(code, PLAN_CRITIC_REASON_CODES)
        for code in (
            "unsupported_positive_trait_reframe",
            "mechanical_fit_check",
            "card_reference_answer_imposed",
            "future_worry_treated_as_self_criticism",
        ):
            self.assertIn(code, WRITER_CRITIC_REASON_CODES)

    def test_regeneration_uses_shared_recovery_contract_only_when_needed(self) -> None:
        normal = prompt_for("planner", request_payload())
        recovery_request = request_payload()
        recovery_request["trigger"] = "protocolCorrection"
        recovery_request["protocolCorrection"] = {
            "errorCode": "invalid_confirmation_resolution",
            "missingConditions": ["matching pending target"],
            "forbiddenOperations": ["resolvedConfirmation=cardRealityConnection"],
        }
        recovery = prompt_for("planner", recovery_request)
        self.assertNotIn(RECOVERY_DISCIPLINE, normal.system)
        self.assertIn(RECOVERY_DISCIPLINE, recovery.system)
        self.assertIn('"protocolCorrection"', recovery.user)
        self.assertNotIn("CANDIDATE PLAN JSON", recovery.user)
        self.assertIn("permissions.allowedSemanticOperations", recovery.system)
        self.assertIn("uncommitted patch", recovery.system)
        self.assertIn("Swift projects those fields", recovery.system)

    def test_recovery_injects_only_the_current_typed_operation_contract(self) -> None:
        for operation, operation_contract in RECOVERY_OPERATION_CONTRACTS.items():
            with self.subTest(operation=operation):
                request = request_payload()
                request["trigger"] = "protocolCorrection"
                request["protocolCorrection"] = {
                    "component": "planner",
                    "failureCategory": "contract_rejected",
                    "missingConditions": [],
                }
                request["recoveryOperation"] = operation
                prompt = prompt_for("planner", request)
                self.assertIn(RECOVERY_DISCIPLINE, prompt.system)
                self.assertIn(operation_contract, prompt.system)
                for other_operation, other_contract in RECOVERY_OPERATION_CONTRACTS.items():
                    if other_operation != operation:
                        self.assertNotIn(other_contract, prompt.system)

    def test_v4_and_v5_card_recovery_contracts_do_not_mix(self) -> None:
        legacy = request_payload(stage="cardReflection")
        legacy.update(
            trigger="protocolCorrection",
            protocolVersion=4,
            recoveryOperation="legacyCardReading",
            protocolCorrection={"failureCategory": "contract_rejected"},
        )
        current = request_payload(stage="cardReflection")
        current.update(
            trigger="protocolCorrection",
            protocolVersion=5,
            recoveryOperation="currentCardGuidance",
            protocolCorrection={"failureCategory": "contract_rejected"},
        )
        legacy_prompt = prompt_for("planner", legacy)
        current_prompt = prompt_for("planner", current)
        self.assertIn(RECOVERY_OPERATION_CONTRACTS["legacyCardReading"], legacy_prompt.system)
        self.assertNotIn(RECOVERY_OPERATION_CONTRACTS["currentCardGuidance"], legacy_prompt.system)
        self.assertIn(RECOVERY_OPERATION_CONTRACTS["currentCardGuidance"], current_prompt.system)
        self.assertNotIn(RECOVERY_OPERATION_CONTRACTS["legacyCardReading"], current_prompt.system)

    def test_conditions_remain_separate(self) -> None:
        card = prompt_for("planner", request_payload(condition="cardMediated"))
        direct = prompt_for("planner", request_payload(condition="modelAsserted"))
        self.assertIn("cardMediated", card.system)
        self.assertIn("cardMappingConfirmed=false", card.system)
        self.assertIn("modelAsserted", direct.system)
        self.assertIn("Never mention cards or images", direct.system)

    def test_current_prompts_are_compact_and_not_layered(self) -> None:
        ceilings = {
            "planner": 6000,
            "plan_critic": 4000,
            "writer": 2800,
            "writer_critic": 2700,
            "writer_revision": 2900,
        }
        for stage in ("contextualDisclosure", "cardConsent", "cardReflection", "directReflection"):
            request = request_payload(stage=stage)
            for task, ceiling in ceilings.items():
                with self.subTest(stage=stage, task=task):
                    prompt = prompt_for(task, request)
                    self.assertLess(len(prompt.system), ceiling)
                    self.assertNotIn("PINNED TURN", prompt.system)
                    self.assertNotIn("historical protocol", prompt.system)
            recovery_request = request_payload(stage=stage)
            recovery_request["trigger"] = "protocolCorrection"
            recovery_request["protocolCorrection"] = {
                "failureCategory": "contract_rejected"
            }
            recovery = prompt_for("planner", recovery_request)
            self.assertLess(len(recovery.system), ceilings["planner"])
            self.assertLess(recovery.metrics.recovery_characters, 1800)
            self.assertNotIn("ENUM CATALOGUES", recovery.system)

    def test_assembled_prompt_metrics_partition_actual_request_without_content_logging(self) -> None:
        request = request_payload(stage="cardReflection")
        request["card"]["imageDevelopmentTurnCount"] = 2
        prompt = prompt_for("planner", request)
        metrics = prompt.metrics
        self.assertIsNotNone(metrics)
        assert metrics is not None
        self.assertEqual(metrics.component, "planner")
        self.assertEqual(metrics.stage, "cardReflection")
        self.assertEqual(metrics.protocol_version, 5)
        self.assertEqual(metrics.substate, "openExploration")
        self.assertEqual(metrics.total_characters, len(prompt.system) + len(prompt.user))
        self.assertEqual(
            metrics.total_characters,
            metrics.shared_characters
            + metrics.stage_characters
            + metrics.substate_characters
            + metrics.dynamic_state_characters
            + metrics.schema_characters
            + metrics.conversation_characters
            + metrics.recovery_characters
            + metrics.provider_format_characters,
        )
        self.assertEqual(metrics.estimated_tokens, (metrics.total_characters + 3) // 4)

        private_phrase = "用户提供的一段具体经历"
        with self.assertLogs("uvicorn.error", level="INFO") as captured:
            turn_prompt_chat(item("planner", {"request": request}))
        line = " ".join(captured.output)
        self.assertIn("turn_prompt_length component=planner", line)
        self.assertIn("substate=openExploration", line)
        self.assertIn("provider_format_characters=0", line)
        self.assertIn("estimate=characters_div_4", line)
        self.assertNotIn(private_phrase, line)

    def test_runtime_prompts_have_no_scenario_template(self) -> None:
        prompts = []
        for stage in ("contextualDisclosure", "cardReflection", "directReflection"):
            request = request_payload(stage=stage)
            prompts.extend(prompt_for(task, request).system for task in (
                "planner", "plan_critic", "writer", "writer_critic"
            ))
        runtime = "\n".join(prompts).lower()
        for phrase in (
            "拖延",
            "procrastination",
            "论文",
            "投稿",
            "phone use",
            "园丁",
            "waiting for motivation",
            "我昨天没有按时提交项目方案",
            "我觉得自己什么事情都做不好",
        ):
            self.assertNotIn(phrase, runtime)

    def test_current_sources_have_no_phrase_list_quality_detector_or_old_prompt(self) -> None:
        root = Path(__file__).resolve().parents[2]
        paths = (
            root / "server/app/prompt_registry.py",
            root / "BeyondComfort/Services/ReflectionProtocolController.swift",
            root / "BeyondComfort/Services/LLMTurnController.swift",
            root / "BeyondComfort/ViewModels/ReflectionViewModel.swift",
        )
        production = "\n".join(path.read_text(encoding="utf-8") for path in paths)
        for detector in (
            "beginsWithDisclosureReportingPreface",
            "containsUnsupportedTenderTraitReframe",
            "containsUnsupportedContextualBusyClaim",
            "AssistantApprovalLanguageDetector",
            "claimFamilies",
            "busyClaims",
            "sanitizedProtocolReply",
        ):
            self.assertNotIn(detector, production)
        self.assertNotIn("turn-v4-server-v41", production)

    def test_planner_shape_keeps_current_business_fields(self) -> None:
        shape = json.loads(PLANNER_JSON_SHAPE)
        self.assertEqual(
            set(shape),
            {
                "semanticOperation",
                "requestedStage",
                "localAction",
                "memoryUpdate",
                "cardConnectionTurnOutcome",
                "resolvedConfirmation",
                "nextPrompt",
                "replyIntent",
                "replyGuidance",
                "cardReferenceSelection",
            },
        )
        for field in (
            "episodeStructure",
            "contextRelationship",
            "cardRealityConnection",
            "pendingCardRealityConnection",
            "reflectionFrame",
            "finalNarrative",
            "practiceTransition",
        ):
            self.assertIn(field, shape["memoryUpdate"])

    def test_old_and_unknown_versions_are_rejected(self) -> None:
        for version in (
            "turn-v4-server-v44",
            "turn-v4-server-v41",
            "turn-v4-server-v40",
            "turn-v4-server-v36",
            "turn-v3-server-v1",
            "unknown",
        ):
            with self.subTest(version=version):
                with self.assertRaises(HTTPException) as raised:
                    build_turn_messages(item("planner", {"request": request_payload()}, version=version))
                self.assertEqual(raised.exception.status_code, 409)

    def test_explicit_semantic_operation_registry_matches_shared_fixture(self) -> None:
        fixture_path = (
            Path(__file__).resolve().parents[2]
            / "BeyondComfortTests/Fixtures/turn-v45-explicit-semantic-operation.json"
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.assertEqual(fixture["contractVersion"], TURN_PROMPT_VERSION)
        self.assertEqual(fixture["semanticOperations"], list(PLANNER_SEMANTIC_OPERATION_VALUES))
        self.assertEqual(len(set(PLANNER_SEMANTIC_OPERATION_VALUES)), 27)
        for example in fixture["plannerExamples"]:
            self.assertEqual(
                validate_planner_semantic_operation(
                    example, protocol_version=5, normal_turn=True
                ),
                example["semanticOperation"],
            )

    def test_current_semantic_operation_contract_rejects_missing_and_unknown(self) -> None:
        with self.assertRaisesRegex(ValueError, "missingSemanticOperation"):
            validate_planner_semantic_operation({}, protocol_version=5, normal_turn=True)
        with self.assertRaisesRegex(ValueError, "missingSemanticOperation"):
            validate_planner_semantic_operation({}, protocol_version=5, normal_turn=False)
        with self.assertRaisesRegex(ValueError, "unknownSemanticOperation"):
            validate_planner_semantic_operation(
                {"semanticOperation": "inventedOperation"},
                protocol_version=5,
                normal_turn=True,
            )
        with self.assertRaisesRegex(ValueError, "unknownSemanticOperation"):
            validate_planner_semantic_operation(
                {"semanticOperation": "inventedOperation"},
                protocol_version=5,
                normal_turn=False,
            )
        self.assertIn("semanticOperation required", PLANNER_SEMANTIC_OPERATION_CONTRACT)
        self.assertEqual(
            tuple(PLANNER_SEMANTIC_OPERATION_SCHEMA["enum"]),
            PLANNER_SEMANTIC_OPERATION_VALUES,
        )

    def test_missing_typed_object_is_rejected(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            build_turn_messages(item("writer", {"request": request_payload()}))
        self.assertEqual(raised.exception.status_code, 422)

    def test_writer_revision_reuses_writer_contract_and_only_adds_revision_inputs(self) -> None:
        request = request_payload(stage="directReflection")
        draft_plan = plan(stage="directReflection", intent="directCandidReflection")
        writer = prompt_for("writer", request, draft_plan)
        revision = prompt_for("writer_revision", request, draft_plan)
        self.assertEqual(
            writer.system.replace("dialogue Writer.", "dialogue Writer revision."),
            revision.system,
        )
        self.assertIn("ORIGINAL DRAFT JSON", revision.user)
        self.assertIn("CRITIQUE JSON", revision.user)
        self.assertNotIn("ORIGINAL DRAFT JSON", writer.user)
        self.assertNotIn("CRITIQUE JSON", writer.user)

    def test_stage_deltas_do_not_load_unrelated_specialized_rules(self) -> None:
        disclosure = prompt_for("planner", request_payload())
        direct = prompt_for("planner", request_payload(stage="directReflection"))
        self.assertNotIn(CARD_EVIDENCE_RULES, disclosure.system)
        self.assertNotIn(SELF_COMPASSION_RULES, disclosure.system)
        self.assertNotIn(CARD_EVIDENCE_RULES, direct.system)
        self.assertIn(SELF_COMPASSION_RULES, direct.system)

    def test_contextual_cue_remains_post_connection_tentative_and_optional(self) -> None:
        request = request_payload(stage="directReflection")
        request["trigger"] = "cardGuidanceAvailable"
        request["card"] = {
            "reflectionApproaches": {"available": True},
        }
        request["card"]["reflectionApproaches"] = {"available": True}
        request["cardMappingConfirmed"] = True
        candidate = plan(stage="directReflection", intent="directCandidReflection")
        candidate["memoryUpdate"] = {"contextCueOffered": True}
        writer = prompt_for("writer", request, candidate)
        without_cue = prompt_for(
            "writer",
            request,
            plan(stage="directReflection", intent="directCandidReflection"),
        )
        self.assertIn("tentative background", writer.system)
        self.assertIn("silence does not confirm", writer.system)
        self.assertNotIn("Mention contextualLoadCue", without_cue.system)

    def test_current_card_guidance_enters_direct_reflection_without_second_confirmation(self) -> None:
        request = request_payload(stage="directReflection")
        request["trigger"] = "cardGuidanceAvailable"
        request["cardMappingConfirmed"] = True
        request["card"] = {"reflectionApproaches": {"available": True}}
        planner = prompt_for("planner", request)
        self.assertIn("First visible turn after canonical Card Reality Connection", planner.system)
        self.assertIn("combine one brief Card Guidance bridge", planner.system)
        self.assertIn("do not use presentCardReading", planner.system)
        self.assertIn("cardNegotiatedMeaning", planner.system)
        self.assertIn("cardMapping confirmation", planner.system)

    def test_legacy_card_guidance_keeps_negotiated_reading_confirmation(self) -> None:
        request = request_payload(stage="cardReflection")
        request["protocolVersion"] = 4
        request["card"]["reflectionApproaches"] = {"available": True}
        request["cardMappingConfirmed"] = True
        planner = prompt_for("planner", request)
        self.assertIn("currently permitted negotiable reading", planner.system)
        self.assertIn("cardNegotiatedMeaning", planner.system)
        self.assertIn("cardMapping confirmation", planner.system)

    def test_card_candidate_is_observable_rejectable_and_not_user_evidence(self) -> None:
        request = request_payload(stage="cardReflection")
        request["card"]["connectionScaffoldUsed"] = True
        candidate = plan(stage="cardReflection", intent="inviteCardConnection")
        writer = prompt_for("writer", request, candidate)
        critic = prompt_for("plan_critic", request, candidate)
        self.assertIn("optional observable image/event candidate", writer.system)
        self.assertIn("development, redirection, or rejection", writer.system)
        self.assertIn("do not present it as the person's view", writer.system)
        self.assertIn("candidate-as-user-evidence", critic.system)

    def test_final_narrative_requires_resolved_action_material(self) -> None:
        request = request_payload(stage="narrativeConfirmation")
        candidate = plan(stage="narrativeConfirmation", intent="presentFinalNarrative")
        writer = prompt_for("writer", request, candidate)
        critic = prompt_for("writer_critic", request, candidate)
        self.assertIn("resolved action/noAction", writer.system)
        self.assertIn("resolved action/noAction", critic.system)
        self.assertIn("proposal IDs match", prompt_for("planner", request).system)

    def test_card_consent_keeps_local_draw_silent(self) -> None:
        request = request_payload(stage="cardConsent")
        candidate = plan(stage="cardConsent", intent="acknowledgeCardConsent")
        planner = prompt_for("planner", request, candidate)
        critic = prompt_for("plan_critic", request, candidate)
        self.assertIn("Swift selects/displays the card", planner.system)
        self.assertIn("silent", planner.system)
        self.assertIn("cannot describe or interpret an unseen card", critic.system)

    def test_plan_critic_uses_whole_allowed_operation_not_enum_product(self) -> None:
        critic = prompt_for("plan_critic", request_payload())
        self.assertIn("permissions.allowedSemanticOperations is authoritative", critic.system)
        self.assertIn("Ignore conflicting legacy requestedStage", critic.system)
        self.assertNotIn(PLANNER_JSON_SHAPE, critic.system)
        self.assertEqual(critic.system.count("STAGE AUDIT"), 1)

    def test_compaction_has_material_aggregate_system_prompt_ceiling(self) -> None:
        total = 0
        for stage in (
            "contextualDisclosure",
            "cardConsent",
            "cardReflection",
            "directReflection",
            "narrativeConfirmation",
            "optionalAction",
            "complete",
            "safetySupport",
        ):
            request = request_payload(stage=stage)
            total += sum(
                len(prompt_for(task, request).system)
                for task in ("planner", "plan_critic", "writer", "writer_critic")
            )
        self.assertLess(total, 180_000)


if __name__ == "__main__":
    unittest.main()
