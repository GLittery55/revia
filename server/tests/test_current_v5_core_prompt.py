from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import get_args

from app.prompt_registry import (
    CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE,
    CURRENT_V5_CONTEXT_HYPOTHESIS_PATCH_SHAPE,
    CURRENT_V5_CORE_PROMPT_VERSION,
    CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE,
    CURRENT_V5_PLANNER_JSON_SHAPE,
    PLANNER_SEMANTIC_OPERATION_VALUES,
    TURN_PROMPT_VERSION,
    build_turn_messages,
)
from app.schemas import (
    CurrentV5PlannerContractError,
    CurrentV5PlannerContract,
    CurrentV5SemanticEvidencePatch,
    CurrentV5SemanticMemoryUpdate,
    CurrentV5SemanticOperation,
    LLMTurnPromptIn,
    canonicalize_current_v5_planner_contract,
    validate_current_v5_planner_contract,
)


class CurrentV5CorePromptTests(unittest.TestCase):
    def request(self) -> dict:
        return {
            "trigger": "userMessage",
            "protocolVersion": 5,
            "protocolStage": "contextualDisclosure",
            "condition": "cardMediated",
            "allowedSemanticOperations": ["clarifyEvent", "advanceToCardConsent"],
            "recentMessages": [
                {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "role": "user",
                    "content": "原来的安排变了，我也没有提前告诉家人。",
                    "replyToMessageID": None,
                }
            ],
            "semanticMemory": {},
            "contextualTrackingProfiles": [],
            "card": None,
            "correction": None,
        }

    def test_planner_contract_has_no_executable_fields(self) -> None:
        item = LLMTurnPromptIn(
            promptTask="planner",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": self.request()},
            maxTokens=900,
            temperature=0.2,
        )
        prompt = build_turn_messages(item)
        shape = json.loads(CURRENT_V5_PLANNER_JSON_SHAPE)

        self.assertIn("CURRENT_V5_CORE_PLANNER", prompt.system)
        self.assertEqual(
            set(shape),
            {
                "semanticOperation",
                "reflectionProgressionDecision",
                "semanticEvidencePatch",
                "responseFocus",
            },
        )
        self.assertNotIn("requestedStage", shape)
        self.assertNotIn("replyIntent", shape)
        self.assertNotIn("nextPrompt", shape)
        self.assertNotIn("localAction", shape)
        self.assertIn("CURRENT V5 TURN REQUEST JSON:", prompt.user)
        for residue in ("nextPrompt", "replyIntent", "localAction", "requestedStage"):
            self.assertNotIn(residue, prompt.system)

    def test_runtime_validator_matches_current_planner_shape_and_operation_registry(self) -> None:
        shape = json.loads(CURRENT_V5_PLANNER_JSON_SHAPE)
        self.assertEqual(set(CurrentV5PlannerContract.model_fields), set(shape))
        self.assertEqual(
            set(CurrentV5SemanticEvidencePatch.model_fields),
            {
                "memoryUpdate",
                "cardConnectionEvidence",
                "contextualTrackingDecision",
            },
        )
        self.assertEqual(
            tuple(get_args(CurrentV5SemanticOperation)),
            tuple(PLANNER_SEMANTIC_OPERATION_VALUES),
        )

    def test_sparse_card_development_continuation_crosses_transport_without_repeating_actors(self) -> None:
        payload = {
            "semanticOperation": "inviteRealityConnection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "cardDevelopmentEvidence": {
                        "relationOrAction": "先扶住架子并把瓷器搬下来",
                        "anticipatedChangeOrChoice": "在架子倒下前降低损失",
                    }
                },
                "cardConnectionEvidence": None,
            },
            "responseFocus": "开放邀请用户把已经形成的画面带回当前经历",
        }
        content = json.dumps(payload, ensure_ascii=False)

        validate_current_v5_planner_contract(content)
        decoded = CurrentV5PlannerContract.model_validate_json(content)
        development = decoded.semanticEvidencePatch.memoryUpdate.cardDevelopmentEvidence
        self.assertIsNotNone(development)
        self.assertEqual(development.actorsOrElements, [])
        self.assertEqual(development.relationOrAction, "先扶住架子并把瓷器搬下来")
        canonical = json.loads(canonicalize_current_v5_planner_contract(content))
        canonical_development = canonical["semanticEvidencePatch"]["memoryUpdate"][
            "cardDevelopmentEvidence"
        ]
        self.assertNotIn("actorsOrElements", canonical_development)

        payload["semanticEvidencePatch"]["memoryUpdate"]["cardDevelopmentEvidence"][
            "actorsOrElements"
        ] = "人物和瓷器"
        with self.assertRaises(CurrentV5PlannerContractError) as failure:
            validate_current_v5_planner_contract(json.dumps(payload, ensure_ascii=False))
        self.assertEqual(
            failure.exception.field_path,
            "semanticEvidencePatch.memoryUpdate.cardDevelopmentEvidence.actorsOrElements",
        )

    def test_nonsemantic_planner_envelope_omissions_default_without_weakening_core_shape(self) -> None:
        payload = {
            "semanticOperation": "continueCardDevelopment",
            "semanticEvidencePatch": {"cardConnectionEvidence": None},
        }
        content = json.dumps(payload)

        validate_current_v5_planner_contract(content)
        decoded = CurrentV5PlannerContract.model_validate_json(content)
        self.assertIsNotNone(decoded.semanticEvidencePatch.memoryUpdate)
        self.assertIsNone(decoded.responseFocus)

        payload.pop("semanticOperation")
        canonical = json.loads(canonicalize_current_v5_planner_contract(json.dumps(payload)))
        self.assertNotIn("semanticOperation", canonical)

    def test_progression_meaning_syntax_is_normalized_only_when_unique(self) -> None:
        base = {
            "semanticOperation": None,
            "semanticEvidencePatch": {"memoryUpdate": {}},
            "responseFocus": "继续当前反思",
        }
        variants = [
            "synthesize",
            ["synthesize"],
            '{"meaning":"synthesize","candidateRef":null}',
            {"decision": "synthesize"},
            {"value": "synthesize"},
        ]

        for value in variants:
            with self.subTest(value=value):
                payload = dict(base, reflectionProgressionDecision=value)
                canonical = json.loads(
                    canonicalize_current_v5_planner_contract(json.dumps(payload))
                )
                self.assertEqual(
                    canonical["reflectionProgressionDecision"]["meaning"],
                    "synthesize",
                )

        canonical_owner = dict(
            base,
            reflectionProgressionDecision={
                "meaning": "reviseTender",
                "decision": "synthesize",
                "candidateRef": None,
            },
        )
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(canonical_owner))
        )
        self.assertEqual(
            canonical["reflectionProgressionDecision"],
            {"meaning": "reviseTender", "candidateRef": None},
        )

    def test_ambiguous_or_unknown_progression_syntax_remains_invalid(self) -> None:
        base = {
            "semanticOperation": None,
            "semanticEvidencePatch": {"memoryUpdate": {}},
            "responseFocus": "继续当前反思",
        }
        for value in (
            ["reviseTender", "synthesize"],
            {"decision": "reviseTender", "value": "synthesize"},
            "moveForward",
        ):
            with self.subTest(value=value):
                with self.assertRaises(CurrentV5PlannerContractError):
                    canonicalize_current_v5_planner_contract(
                        json.dumps(dict(base, reflectionProgressionDecision=value))
                    )

    def test_progression_delta_has_one_atomic_owner_with_legacy_alias_migration(self) -> None:
        canonical_payload = {
            "semanticOperation": None,
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {"reflectionDelta": "旧分离内容"},
                }
            },
            "reflectionProgressionDecision": {
                "meaning": "synthesize",
                "candidateRef": None,
                "reflectionDelta": "原子综合内容",
            },
            "responseFocus": "呈现综合",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(canonical_payload, ensure_ascii=False)
            )
        )
        self.assertEqual(
            canonical["reflectionProgressionDecision"]["reflectionDelta"],
            "原子综合内容",
        )
        self.assertNotIn(
            "reflectionFrame",
            canonical["semanticEvidencePatch"]["memoryUpdate"],
        )

        legacy_payload = dict(canonical_payload)
        legacy_payload["reflectionProgressionDecision"] = {
            "meaning": "synthesize",
            "candidateRef": None,
        }
        legacy = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(legacy_payload, ensure_ascii=False)
            )
        )
        self.assertEqual(
            legacy["reflectionProgressionDecision"]["reflectionDelta"],
            "旧分离内容",
        )
        self.assertNotIn(
            "reflectionFrame",
            legacy["semanticEvidencePatch"]["memoryUpdate"],
        )

        inquiry_payload = dict(canonical_payload)
        inquiry_payload["reflectionProgressionDecision"] = {
            "meaning": "inspectReality",
            "candidateRef": "episodeStructure.impacts.0",
            "reflectionDelta": "不属于询问的内容",
        }
        inquiry = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(inquiry_payload, ensure_ascii=False)
            )
        )
        self.assertNotIn("reflectionDelta", inquiry["reflectionProgressionDecision"])
        self.assertNotIn(
            "reflectionFrame",
            inquiry["semanticEvidencePatch"]["memoryUpdate"],
        )

    def test_fierce_progression_is_one_atomic_semantic_owner(self) -> None:
        payload = {
            "semanticOperation": "continueTenderGroundedFierceReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {
                        "reflectionDelta": "旧的重复内容",
                        "fierceEvidence": {"direction": "change"},
                    }
                }
            },
            "reflectionProgressionDecision": {
                "meaning": "completeFierce",
                "candidateRef": "episodeStructure.controllableParts.0",
                "reflectionDelta": "时间有限时需要先守住原有安排",
                "fierceDirection": "protect",
                "groundedEvidence": "时间有限时要明确拒绝临时工作",
            },
            "responseFocus": "",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )

        self.assertEqual(
            canonical["reflectionProgressionDecision"]["meaning"],
            "completeFierce",
        )
        self.assertEqual(
            canonical["reflectionProgressionDecision"]["fierceDirection"],
            "protect",
        )
        self.assertNotIn(
            "candidateRef",
            canonical["reflectionProgressionDecision"],
        )
        self.assertNotIn(
            "groundedEvidence",
            canonical["reflectionProgressionDecision"],
        )
        self.assertNotIn(
            "reflectionFrame",
            canonical["semanticEvidencePatch"]["memoryUpdate"],
        )

        payload["reflectionProgressionDecision"] = {
            "meaning": "clarifyFierce",
            "candidateRef": "episodeStructure.controllableParts.0",
            "reflectionDelta": "不得保留",
            "fierceDirection": "change",
            "groundedEvidence": "不得保留",
        }
        clarified = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )
        decision = clarified["reflectionProgressionDecision"]
        self.assertNotIn("reflectionDelta", decision)
        self.assertNotIn("fierceDirection", decision)
        self.assertNotIn("groundedEvidence", decision)
        self.assertNotIn(
            "reflectionFrame",
            clarified["semanticEvidencePatch"]["memoryUpdate"],
        )

    def test_card_connection_transport_never_derives_outcome_metadata(self) -> None:
        payload = {
            "semanticOperation": "continueOpenCardConnection",
            "semanticEvidencePatch": {
                "cardConnectionEvidence": {
                    "imageRelation": "一个人独自在房间里",
                    "realityMapping": "汇报失误后感到尴尬，想一个人待着",
                    "kind": "userAuthoredConnection",
                    "source": "userAuthored",
                    "status": "confirmed",
                }
            },
            "responseFocus": "继续当前卡牌连接",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload, ensure_ascii=False))
        )
        self.assertEqual(canonical["semanticOperation"], "continueOpenCardConnection")
        evidence = canonical["semanticEvidencePatch"]["cardConnectionEvidence"]
        self.assertEqual(
            evidence,
            {
                "imageRelation": "一个人独自在房间里",
                "realityMapping": "汇报失误后感到尴尬，想一个人待着",
            },
        )

    def test_connection_protocol_metadata_is_removed_without_rewriting_the_operation(self) -> None:
        payload = {
            "semanticOperation": "establishUserAuthoredCardConnection",
            "semanticEvidencePatch": {
                "cardConnectionTurnOutcome": {
                    "kind": "connectionStillUnclear",
                    "connection": {
                        "imageRelation": "屏风保留了一段边界距离",
                        "realityMapping": "汇报失误后想暂时和现场拉开一点距离",
                        "source": "userRevised",
                        "status": "confirmed",
                    },
                }
            },
            "responseFocus": "继续当前卡牌连接",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload))
        )
        evidence = canonical["semanticEvidencePatch"]["cardConnectionEvidence"]
        self.assertEqual(
            evidence["realityMapping"],
            "汇报失误后想暂时和现场拉开一点距离",
        )
        self.assertEqual(canonical["semanticOperation"], "establishUserAuthoredCardConnection")
        self.assertNotIn("kind", evidence)
        self.assertNotIn("source", evidence)
        self.assertNotIn("status", evidence)

    def test_complete_connection_uses_the_only_connection_carrying_capability(self) -> None:
        payload = {
            "semanticOperation": "continueOpenCardConnection",
            "semanticEvidencePatch": {
                "cardConnectionTurnOutcome": {
                    "kind": "connectionStillUnclear",
                    "connection": {
                        "imageRelation": "屏风保留了一段边界距离",
                        "realityMapping": "尴尬时想躲起来，需要一点距离",
                        "source": "userAccepted",
                        "status": "confirmed",
                    },
                }
            },
            "responseFocus": "沿用户刚形成的连接继续",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False),
                allowed_semantic_operations=[
                    "continueOpenCardConnection",
                    "establishUserAuthoredCardConnection",
                ],
            )
        )

        self.assertEqual(canonical["semanticOperation"], "continueOpenCardConnection")
        self.assertEqual(
            canonical["semanticEvidencePatch"]["cardConnectionEvidence"],
            {
                "imageRelation": "屏风保留了一段边界距离",
                "realityMapping": "尴尬时想躲起来，需要一点距离",
            },
        )

    def test_connection_projection_never_invents_missing_semantic_text(self) -> None:
        payload = {
            "semanticOperation": "establishUserAuthoredCardConnection",
            "semanticEvidencePatch": {
                "cardConnectionTurnOutcome": {
                    "kind": "connectionStillUnclear",
                    "connection": {
                        "imageRelation": "",
                        "realityMapping": "尴尬时想躲起来，需要一点距离",
                    },
                }
            },
            "responseFocus": "进入现实探索",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False),
                allowed_semantic_operations=["continueOpenCardConnection"],
            )
        )
        evidence = canonical["semanticEvidencePatch"]["cardConnectionEvidence"]
        self.assertEqual(evidence["imageRelation"], "")
        self.assertEqual(evidence["realityMapping"], "尴尬时想躲起来，需要一点距离")

    def test_known_non_authoritative_extras_are_projected_without_losing_valid_evidence(self) -> None:
        payload = {
            "semanticOperation": "continueCardDevelopment",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "nextPrompt": {
                        "kind": "openQuestion",
                        "purpose": "cardDevelopment",
                    },
                    "reflectionPhase": "tender",
                    "cardImageRelation": "legacy mirror",
                    "cardObservationEvidence": {
                        "userDescribedElements": ["一个人在扶架子"],
                    },
                },
                "cardConnectionTurnOutcome": None,
            },
            "responseFocus": "让画面继续自然发展",
            "requestedStage": "complete",
            "replyIntent": "completeConversation",
            "localAction": {"kind": "completeSession"},
            "nextPrompt": {"kind": "none"},
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )

        self.assertEqual(
            set(canonical),
            {"semanticOperation", "semanticEvidencePatch", "responseFocus"},
        )
        update = canonical["semanticEvidencePatch"]["memoryUpdate"]
        self.assertEqual(
            update["cardObservationEvidence"]["userDescribedElements"],
            ["一个人在扶架子"],
        )
        self.assertNotIn("nextPrompt", update)
        self.assertNotIn("reflectionPhase", update)
        self.assertNotIn("cardImageRelation", update)

    def test_contextual_tracking_decision_is_typed_and_old_signal_has_no_authority(self) -> None:
        decision = {
            "metricEligibility": [
                {
                    "profileID": "sleep",
                    "metric": "sleepTiming",
                    "status": "doesNotQualify",
                    "preferred": False,
                }
            ]
        }
        payload = {
            "semanticOperation": "continueExploratoryReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {"contextCueOffered": True},
                "contextualTrackingDecision": decision,
            },
            "responseFocus": "继续现实探索",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload))
        )
        patch = canonical["semanticEvidencePatch"]
        self.assertEqual(
            patch["contextualTrackingDecision"],
            decision,
        )
        self.assertNotIn("contextCueOffered", patch["memoryUpdate"])

        payload["semanticEvidencePatch"]["contextualTrackingDecision"] = {
            "metricEligibility": [
                {
                    "profileID": "sleep",
                    "metric": "sleepTiming",
                    "status": "qualifies",
                }
            ]
        }
        canonical_missing_preference = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload))
        )
        self.assertEqual(
            canonical_missing_preference["semanticEvidencePatch"]
            ["contextualTrackingDecision"]["metricEligibility"][0]["preferred"],
            False,
        )

        payload["semanticEvidencePatch"]["contextualTrackingDecision"] = {
            "metricEligibility": "sleep"
        }
        with self.assertRaises(CurrentV5PlannerContractError) as failure:
            validate_current_v5_planner_contract(json.dumps(payload))
        self.assertEqual(
            failure.exception.field_path,
            "semanticEvidencePatch.contextualTrackingDecision.metricEligibility",
        )

    def test_uniquely_owned_fields_are_canonicalized_across_all_envelopes(self) -> None:
        payload = {
            "semanticOperation": "continueExploratoryReflection",
            "memoryUpdate": {
                "selfCriticismLink": "反复受阻以后，逐渐开始怀疑自己的能力",
            },
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    # This was the exact production failure boundary: a valid tracking choice was
                    # nested one level too deep even though its owner is mechanically unique.
                    "contextualTrackingDecision": {
                        "metricEligibility": [
                            {
                                "profileID": "recent-load",
                                "metric": "calendarLoad",
                                "status": "qualifies",
                                "preferred": True,
                            }
                        ],
                    },
                    "episodeStructure": {
                        "selfCriticalStatement": "我怀疑自己不适合开发",
                    },
                },
                "responseFocus": "沿已经形成的现实关系进入反思",
            },
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )

        self.assertEqual(
            canonical["responseFocus"],
            "沿已经形成的现实关系进入反思",
        )
        patch = canonical["semanticEvidencePatch"]
        self.assertEqual(
            patch["contextualTrackingDecision"],
            {
                "metricEligibility": [
                    {
                        "profileID": "recent-load",
                        "metric": "calendarLoad",
                        "status": "qualifies",
                        "preferred": True,
                    }
                ]
            },
        )
        memory = patch["memoryUpdate"]
        self.assertEqual(
            memory["selfCriticismLink"],
            "反复受阻以后，逐渐开始怀疑自己的能力",
        )
        self.assertEqual(memory["selfCriticalStatement"], "我怀疑自己不适合开发")
        self.assertNotIn("contextualTrackingDecision", memory)
        self.assertEqual(memory["episodeStructure"], {})

    def test_sparse_patch_envelope_is_constructed_but_semantic_decision_is_not_invented(self) -> None:
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(
                    {
                        "semanticOperation": "inviteCardConsent",
                        "responseFocus": "邀请随机反思卡",
                    }
                )
            )
        )
        self.assertEqual(canonical["semanticEvidencePatch"]["memoryUpdate"], {})

        missing = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps({"responseFocus": "邀请随机反思卡"})
            )
        )
        self.assertNotIn("semanticOperation", missing)

    def test_missing_or_unknown_operation_uses_the_only_swift_capability(self) -> None:
        missing = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps({"responseFocus": "继续当前唯一流程"}),
                allowed_semantic_operations=["inviteCardConsent"],
            )
        )
        self.assertNotIn("semanticOperation", missing)

        unknown = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(
                    {
                        "semanticOperation": "continueConsentFlow",
                        "responseFocus": "继续当前唯一流程",
                    }
                ),
                allowed_semantic_operations=["inviteCardConsent"],
            )
        )
        self.assertEqual(unknown["semanticOperation"], "continueConsentFlow")

        ambiguous = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps({"responseFocus": "继续"}),
                allowed_semantic_operations=[
                    "inviteCardConsent",
                    "acknowledgeCardConsent",
                ],
            )
        )
        self.assertNotIn("semanticOperation", ambiguous)

    def test_operation_owned_reflection_metadata_is_canonicalized_without_repair(self) -> None:
        tender = {
            "semanticOperation": "continueTenderReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {
                        "action": "clarifyBoundaryOrNeed",
                    }
                }
            },
            "responseFocus": "问题暂时没有解决，不足以直接证明整个人不适合开发",
        }
        canonical_tender = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(tender, ensure_ascii=False)
            )
        )
        tender_frame = canonical_tender["semanticEvidencePatch"]["memoryUpdate"][
            "reflectionFrame"
        ]
        self.assertNotIn("mode", tender_frame)
        self.assertNotIn("action", tender_frame)
        self.assertNotIn("evidenceBasis", tender_frame)
        self.assertNotIn("dimensions", tender_frame)
        self.assertNotIn("reflectionDelta", tender_frame)

        synthesis = {
            "semanticOperation": "synthesizeDirectReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {
                        "mode": "fierce",
                        "action": "identifyChangeDirection",
                        "dimensions": [],
                        "reflectionDelta": "可以把具体受阻和整体能力判断分开",
                    }
                }
            },
            "responseFocus": "形成综合",
        }
        canonical_synthesis = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(synthesis, ensure_ascii=False)
            )
        )
        synthesis_frame = canonical_synthesis["semanticEvidencePatch"][
            "memoryUpdate"
        ]["reflectionFrame"]
        self.assertNotIn("mode", synthesis_frame)
        self.assertNotIn("action", synthesis_frame)
        self.assertEqual(
            synthesis_frame["reflectionDelta"],
            "可以把具体受阻和整体能力判断分开",
        )

    def test_practice_protocol_metadata_is_swift_owned_at_transport_boundary(self) -> None:
        payload = {
            "semanticOperation": "proposePractice",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "practiceTransition": {
                        "proposal": {
                            "kind": "care",
                            "content": "先停十分钟再回来排查",
                            "basis": "持续卡住时压力会增加",
                        }
                    }
                }
            },
            "responseFocus": "提出一个小而具体的照顾行动",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )
        transition = canonical["semanticEvidencePatch"]["memoryUpdate"][
            "practiceTransition"
        ]
        self.assertNotIn("transactionID", transition)
        self.assertNotIn("narrativeReferenceID", transition)
        self.assertNotIn("kind", transition["proposal"])
        self.assertNotIn("id", transition["proposal"])
        self.assertNotIn("status", transition["proposal"])
        self.assertNotIn("source", transition["proposal"])
        self.assertEqual(transition["proposal"]["content"], "先停十分钟再回来排查")

    def test_canonical_tracking_owner_wins_over_conflicting_misplaced_alias(self) -> None:
        decision = {
            "metricEligibility": [
                {
                    "profileID": "sleep",
                    "metric": "sleepTiming",
                    "status": "doesNotQualify",
                    "preferred": False,
                }
            ]
        }
        payload = {
            "semanticOperation": "continueExploratoryReflection",
            "semanticEvidencePatch": {
                "contextualTrackingDecision": decision,
                "memoryUpdate": {"contextualTrackingDecision": decision},
            },
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload))
        )
        self.assertEqual(
            canonical["semanticEvidencePatch"]["contextualTrackingDecision"],
            decision,
        )

        payload["semanticEvidencePatch"]["memoryUpdate"][
            "contextualTrackingDecision"
        ] = {
            "metricEligibility": [
                {
                    "profileID": "activity",
                    "metric": "steps",
                    "status": "qualifies",
                    "preferred": True,
                }
            ]
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(payload))
        )
        self.assertEqual(
            canonical["semanticEvidencePatch"]["contextualTrackingDecision"],
            decision,
        )
        self.assertNotIn(
            "contextualTrackingDecision",
            canonical["semanticEvidencePatch"]["memoryUpdate"],
        )

    def test_conflicting_misplaced_tracking_aliases_are_omitted(self) -> None:
        payload = {
            "semanticOperation": "continueExploratoryReflection",
            "contextualTrackingDecision": {
                "metricEligibility": [
                    {
                        "profileID": "sleep",
                        "metric": "sleepTiming",
                        "status": "qualifies",
                        "preferred": True,
                    }
                ],
            },
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "contextualTrackingDecision": {
                        "metricEligibility": [
                            {
                                "profileID": "activity",
                                "metric": "steps",
                                "status": "qualifies",
                                "preferred": True,
                            }
                        ],
                    },
                    "selfCriticismLink": "反复卡住以后，逐渐开始怀疑自己的能力",
                },
            },
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )

        patch = canonical["semanticEvidencePatch"]
        self.assertNotIn("contextualTrackingDecision", patch)
        self.assertNotIn("contextualTrackingDecision", patch["memoryUpdate"])
        self.assertEqual(
            patch["memoryUpdate"]["selfCriticismLink"],
            "反复卡住以后，逐渐开始怀疑自己的能力",
        )

    def test_self_criticism_statement_has_one_writable_owner(self) -> None:
        payload = {
            "semanticOperation": "clarifyEvent",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "selfCriticismStatus": "present",
                    "episodeStructure": {
                        "concreteFacts": ["登录后的功能反复修改仍有问题"],
                        "selfCriticismStatus": "present",
                        "selfCriticalStatement": "我越来越怀疑自己不适合做开发",
                    },
                }
            },
            "responseFocus": "询问问题如何发展",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )
        memory = canonical["semanticEvidencePatch"]["memoryUpdate"]
        self.assertNotIn("selfCriticismStatus", memory)
        self.assertEqual(
            memory["selfCriticalStatement"],
            "我越来越怀疑自己不适合做开发",
        )
        self.assertEqual(
            memory["episodeStructure"],
            {"concreteFacts": ["登录后的功能反复修改仍有问题"]},
        )

    def test_conflicting_self_criticism_statement_owners_remain_invalid(self) -> None:
        payload = {
            "semanticOperation": "clarifyEvent",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "selfCriticalStatement": "我不适合做开发",
                    "episodeStructure": {
                        "selfCriticalStatement": "我什么都做不好",
                    },
                }
            },
            "responseFocus": "询问问题如何发展",
        }

        with self.assertRaises(CurrentV5PlannerContractError) as failure:
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        self.assertEqual(
            failure.exception.field_path,
            "semanticEvidencePatch.memoryUpdate.selfCriticalStatement",
        )
        self.assertEqual(failure.exception.violation, "duplicate_conflict")

    def test_misnested_card_connection_outcome_moves_to_its_unique_patch_owner(self) -> None:
        outcome = {
            "kind": "userAuthoredConnection",
            "connection": {
                "imageRelation": "两个人可以商量植物放在哪里",
                "realityMapping": "投稿被拒后没有和审稿人商量的余地",
                "source": "userAuthored",
                "status": "confirmed",
            },
        }
        payload = {
            "semanticOperation": "establishUserAuthoredCardConnection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "cardConnectionTurnOutcome": outcome,
                }
            },
            "responseFocus": "从用户形成的现实关系进入探索",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )

        patch = canonical["semanticEvidencePatch"]
        self.assertEqual(
            patch["cardConnectionEvidence"],
            {
                "imageRelation": "两个人可以商量植物放在哪里",
                "realityMapping": "投稿被拒后没有和审稿人商量的余地",
            },
        )
        self.assertNotIn("cardConnectionTurnOutcome", patch["memoryUpdate"])

    def test_conflicting_card_connection_outcome_owners_remain_invalid(self) -> None:
        canonical_outcome = {
            "kind": "connectionStillUnclear",
            "connection": None,
        }
        misplaced_outcome = {
            "kind": "userAuthoredConnection",
            "connection": {
                "imageRelation": "两个人可以商量植物放在哪里",
                "realityMapping": "投稿被拒后没有商量余地",
                "source": "userAuthored",
                "status": "confirmed",
            },
        }
        payload = {
            "semanticOperation": "establishUserAuthoredCardConnection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "cardConnectionTurnOutcome": misplaced_outcome,
                },
                "cardConnectionTurnOutcome": canonical_outcome,
            },
            "responseFocus": "继续",
        }

        with self.assertRaises(CurrentV5PlannerContractError) as failure:
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        self.assertEqual(
            failure.exception.field_path,
            "semanticEvidencePatch.cardConnectionTurnOutcome",
        )
        self.assertEqual(failure.exception.violation, "duplicate_conflict")

    def test_unknown_extras_have_no_authority_but_invalid_typed_evidence_remains_strict(self) -> None:
        unknown = {
            "semanticOperation": "continueCardDevelopment",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "unrecognizedEvidence": "value",
                    "cardObservationEvidence": {
                        "userDescribedElements": ["一个人在看架子"],
                        "confidence": 0.9,
                    },
                },
                "analysis": "not authoritative",
            },
            "responseFocus": "继续",
            "reasoning": "not authoritative",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(unknown))
        )
        self.assertNotIn("reasoning", canonical)
        self.assertNotIn("analysis", canonical["semanticEvidencePatch"])
        memory = canonical["semanticEvidencePatch"]["memoryUpdate"]
        self.assertNotIn("unrecognizedEvidence", memory)
        self.assertEqual(
            memory["cardObservationEvidence"],
            {"userDescribedElements": ["一个人在看架子"]},
        )

        invalid = {
            "semanticOperation": "continueCardDevelopment",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "cardObservationEvidence": {
                        "userDescribedElements": "not-a-list",
                    }
                }
            },
            "responseFocus": "继续",
        }
        with self.assertRaises(CurrentV5PlannerContractError) as invalid_failure:
            canonicalize_current_v5_planner_contract(json.dumps(invalid))
        self.assertEqual(
            invalid_failure.exception.field_path,
            "semanticEvidencePatch.memoryUpdate.cardObservationEvidence.userDescribedElements",
        )

    def test_current_memory_writable_surface_excludes_swift_and_legacy_metadata(self) -> None:
        writable = set(CurrentV5SemanticMemoryUpdate.model_fields)
        self.assertTrue(
            {
                "selfCriticalStatement",
                "episodeStructure",
                "cardObservationEvidence",
                "cardDevelopmentEvidence",
                "reflectionFrame",
                "practiceTransition",
            }.issubset(writable)
        )
        self.assertTrue(
            {
                "nextPrompt",
                "reflectionPhase",
                "candidUnderstanding",
                "fierceUnderstanding",
                "cardInterpretiveTension",
                "cardNegotiatedMeaning",
                "cardImageRelation",
                "cardRealityMapping",
                "cardRealityMappingSource",
                "cardRealityConnection",
                "cardConnectionOutcome",
                "clearCardRealityConnection",
                "clearPendingCardRealityConnection",
                "eventDisclosureOutcome",
                "selfCriticismStatus",
            }.isdisjoint(writable)
        )

    def test_shared_current_v5_planner_fixture_passes_backend_contract(self) -> None:
        fixture_path = (
            Path(__file__).resolve().parents[2]
            / "BeyondComfortTests/Fixtures/current-v5-planner-output-v40.json"
        )
        validate_current_v5_planner_contract(fixture_path.read_text(encoding="utf-8"))
        self.assertEqual(CURRENT_V5_CORE_PROMPT_VERSION, "turn-v5-core-server-v100")

    def test_initial_synthesis_requires_explicit_non_replayed_delta(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "tender"
        request["allowedSemanticOperations"] = [
            "continueTenderReflection",
            "continueTenderGroundedFierceReflection",
            "synthesizeDirectReflection",
        ]
        request["semanticMemory"] = {
            "reflectionFrame": {
                "mode": "tender",
                "action": "softenGlobalSelfJudgment",
                "evidenceBasis": [{"source": "episode", "content": "项目没有按时完成"}],
                "dimensions": [],
                "reflectionDelta": "接下额外任务影响了自己的进度",
                "fierceEvidence": None,
            }
        }
        messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        )
        prompt = messages.system

        self.assertIn("nonempty Planner synthesisDelta", prompt)
        self.assertIn("may preserve the accepted Tender/Fierce meaning", prompt)
        self.assertIn("rather than copy the committed reflectionDelta exactly", prompt)
        self.assertIn("Swift never fills it", prompt)
        self.assertIn("explicit synthesis", prompt)

    def test_writer_receives_swift_directive_and_only_returns_reply(self) -> None:
        directive = {
            "semanticOperation": "advanceToCardConsent",
            "responseFocus": "简短承接并邀请随机反思卡",
            "sourceStage": "contextualDisclosure",
            "destinationStage": "cardConsent",
            "nextPrompt": {
                "kind": "confirmationRequest",
                "purpose": None,
                "focus": None,
                "disclosurePurpose": None,
                "disclosureTarget": None,
                "disclosureReopenReason": None,
                "target": "cardConsent",
                "referenceID": None,
            },
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        item = LLMTurnPromptIn(
            promptTask="writer",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": self.request(), "directive": directive},
            maxTokens=500,
            temperature=0.3,
        )
        prompt = build_turn_messages(item)

        self.assertIn("CURRENT_V5_CORE_WRITER", prompt.system)
        self.assertIn('Return exactly {"reply":""}', prompt.system)
        self.assertIn("AUTHORIZED SWIFT DIRECTIVE JSON:", prompt.user)
        self.assertIn("exactly one natural", prompt.system)
        self.assertIn("not a fixed acknowledgment", prompt.system)
        self.assertIn('"you mentioned/said" preface', prompt.system)
        self.assertIn("Do not paraphrase the latest answer merely", prompt.system)
        self.assertIn("warm, idiomatic, unforced Chinese", prompt.system)
        self.assertIn("without forced either-or choices, candidate answers", prompt.system)
        self.assertIn("switch to bodily sensations unless introduced and necessary", prompt.system)
        self.assertIn("substantive content, never filler", prompt.system)
        self.assertIn("without turning it into an unsupported global verdict", prompt.system)

    def test_legacy_prompt_version_remains_available(self) -> None:
        self.assertNotEqual(TURN_PROMPT_VERSION, CURRENT_V5_CORE_PROMPT_VERSION)

    def test_current_contract_rejects_critic_task(self) -> None:
        item = LLMTurnPromptIn(
            promptTask="plan_critic",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": self.request(), "plan": {}},
            maxTokens=300,
            temperature=0,
        )
        with self.assertRaises(Exception):
            build_turn_messages(item)

    def test_current_v5_contracts_stay_within_compressed_prompt_budgets(self) -> None:
        card_request = self.request()
        card_request["protocolStage"] = "cardReflection"
        card_request["allowedSemanticOperations"] = [
            "continueCardDevelopment",
            "inviteRealityConnection",
        ]
        direct_request = self.request()
        direct_request["protocolStage"] = "directReflection"
        direct_request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        direct_request["semanticMemory"] = {}
        direct_request["reflectionMode"] = "exploratory"
        tender_request = self.request()
        tender_request["protocolStage"] = "directReflection"
        tender_request["allowedSemanticOperations"] = ["continueTenderReflection"]
        tender_request["semanticMemory"] = {}
        tender_request["reflectionMode"] = "tender"
        directive = {
            "semanticOperation": "continueTenderReflection",
            "responseFocus": "承接具体困难并形成有依据的区分",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "none"},
            "localAction": "none",
            "memoryUpdate": {"reflectionPhase": "tender"},
            "rewriteReason": None,
        }

        def system_length(task: str, payload: dict) -> int:
            return len(
                build_turn_messages(
                    LLMTurnPromptIn(
                        promptTask=task,
                        promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                        payload=payload,
                        maxTokens=900,
                        temperature=0.2,
                    )
                ).system
            )

        self.assertLess(system_length("planner", {"request": card_request}), 6000)
        self.assertLess(system_length("planner", {"request": direct_request}), 10000)
        self.assertLess(
            system_length("writer", {"request": tender_request, "directive": directive}),
            4000,
        )

    def test_projection_correction_is_specific_and_stays_in_exploration(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        request["semanticMemory"] = {}
        request["reflectionMode"] = "tender"
        request["correction"] = {
            "rejectedOperation": "continueTenderReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "tenderActionIncompatible",
            "rejectedDraft": {
                "semanticOperation": "continueTenderReflection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "premature tender question",
            },
            "issue": {
                "fieldPath": "semanticOperation",
                "violation": "operationNotAllowed",
                "requiredConditions": ["remainInCurrentPhase", "omitReflectionFrame"],
            },
            "allowedSemanticOperations": ["continueExploratoryReflection"],
            "recoveryPolicy": "remainInCurrentPhase",
        }
        item = LLMTurnPromptIn(
            promptTask="planner",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": request},
            maxTokens=900,
            temperature=0.2,
        )

        messages = build_turn_messages(item)
        prompt = messages.system

        self.assertIn("rejectedOperation=continueTenderReflection", prompt)
        self.assertIn("payloadFailure=none", prompt)
        self.assertIn("projectionFailure=tenderActionIncompatible", prompt)
        self.assertIn("recoveryPolicy=remainInCurrentPhase", prompt)
        self.assertIn('["remainInCurrentPhase","omitReflectionFrame"]', prompt)
        self.assertIn("issue.fieldPath=semanticOperation", prompt)
        self.assertIn("issue.violation=operationNotAllowed", prompt)
        self.assertIn("do not recreate the rejected operation", prompt)
        self.assertIn("discard every question or task from the rejected operation", prompt)
        self.assertIn('["continueExploratoryReflection"]', prompt)

    def test_payload_correction_repairs_only_the_rejected_connection_operation(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["establishUserAuthoredCardConnection"]
        request["correction"] = {
            "rejectedOperation": "establishUserAuthoredCardConnection",
            "reason": "payloadInvalid",
            "payloadFailure": "cardConnectionOutcomeMissing",
            "projectionFailure": None,
            "rejectedDraft": {
                "semanticOperation": "establishUserAuthoredCardConnection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "return to lived reality",
            },
            "issue": {
                "fieldPath": "semanticEvidencePatch.cardConnectionTurnOutcome",
                "violation": "missing",
                "requiredConditions": ["useMatchingCardConnectionOutcome"],
            },
            "allowedSemanticOperations": ["establishUserAuthoredCardConnection"],
            "recoveryPolicy": "repairSameOperation",
        }
        item = LLMTurnPromptIn(
            promptTask="planner",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": request},
            maxTokens=900,
            temperature=0.2,
        )

        messages = build_turn_messages(item)
        prompt = messages.system

        self.assertIn("payloadFailure=cardConnectionOutcomeMissing", prompt)
        self.assertIn(
            "issue.fieldPath=semanticEvidencePatch.cardConnectionTurnOutcome",
            prompt,
        )
        self.assertIn("issue.violation=missing", prompt)
        self.assertIn('issue.requiredConditions=["useMatchingCardConnectionOutcome"]', prompt)
        self.assertIn("Repair only the rejected operation", prompt)
        self.assertIn(
            "preserve every other valid operation-owned field from request.correction.rejectedDraft",
            prompt,
        )
        self.assertIn('"rejectedDraft":{', messages.user)
        self.assertIn('["establishUserAuthoredCardConnection"]', prompt)

    def test_missing_initial_observation_correction_repairs_the_same_act(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = [
            "continueCardDevelopment",
            "inviteRealityConnection",
        ]
        request["latestAnswerContext"] = {
            "purpose": "cardObservation",
            "disclosurePurpose": None,
            "referenceID": None,
        }
        request["correction"] = {
            "rejectedOperation": "continueCardObservation",
            "reason": "payloadInvalid",
            "payloadFailure": "cardObservationEvidenceMissing",
            "projectionFailure": None,
            "rejectedDraft": {
                "semanticOperation": "continueCardObservation",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "ask for more image inventory",
            },
            "issue": {
                "fieldPath": (
                    "semanticEvidencePatch.memoryUpdate.cardObservationEvidence."
                    "userDescribedElements"
                ),
                "violation": "missing",
                "requiredConditions": ["followCardEvidenceProgression"],
            },
            "allowedSemanticOperations": [
                "continueCardObservation",
            ],
            "recoveryPolicy": "repairSameOperation",
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED CARD OBSERVATION REPAIR", prompt)
        self.assertIn("cardObservationEvidence.userDescribedElements", prompt)
        self.assertIn("Keep semanticOperation=continueCardObservation", prompt)
        self.assertIn("Swift projects Development afterward", prompt)
        self.assertNotIn("REQUIRED TENDER REPAIR", prompt)
        self.assertNotIn("REQUIRED SYNTHESIS REPAIR", prompt)
        self.assertNotIn("REQUIRED CONTEXT REVIEW REPAIR", prompt)

    def test_tender_correction_repairs_semantic_delta_without_rebuilding_frame(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueTenderReflection"]
        request["correction"] = {
            "rejectedOperation": "continueTenderReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "tenderFrameMissing",
            "rejectedDraft": {
                "semanticOperation": "continueTenderReflection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "form a grounded tender distinction",
            },
            "issue": {
                "fieldPath": "semanticEvidencePatch.memoryUpdate.reflectionFrame",
                "violation": "missing",
                "requiredConditions": [
                    "provideTenderFrame",
                    "provideConcreteReflectionDelta",
                    "omitFierceEvidence",
                ],
            },
            "allowedSemanticOperations": ["continueTenderReflection"],
            "recoveryPolicy": "repairSameOperation",
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED TENDER REPAIR", prompt)
        self.assertIn("reflectionFrame.reflectionDelta", prompt)
        self.assertIn("responseFocus may only tell the Writer", prompt)
        self.assertIn("Swift constructs the Tender frame shape", prompt)
        self.assertIn("do not reconstruct it", prompt)
        self.assertNotIn("reconstruct reflectionFrame", prompt)
        self.assertIn("cannot assert an opposite positive conclusion", prompt)
        self.assertIn("unaffected ability", prompt)
        self.assertIn("ruled-out unknown cause", prompt)
        self.assertIn("preserve the exact domain, target, time range", prompt)
        self.assertIn("never substitute a nearby self-critical proposition", prompt)
        self.assertNotIn("REQUIRED SYNTHESIS REPAIR", prompt)
        self.assertNotIn("REQUIRED CARD OBSERVATION REPAIR", prompt)
        self.assertNotIn("REQUIRED CONTEXT REVIEW REPAIR", prompt)

    def test_synthesis_correction_requires_one_sparse_frame_at_the_exact_path(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "tender"
        request["allowedSemanticOperations"] = ["synthesizeDirectReflection"]
        request["correction"] = {
            "rejectedOperation": "synthesizeDirectReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "synthesisFrameMissing",
            "rejectedDraft": {
                "semanticOperation": "synthesizeDirectReflection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "synthesize committed understanding",
            },
            "issue": {
                "fieldPath": "semanticEvidencePatch.memoryUpdate.reflectionFrame",
                "violation": "missing",
                "requiredConditions": [
                    "provideSynthesisFrame",
                    "useSynthesisAction",
                    "useSynthesisMode",
                    "provideConcreteReflectionDelta",
                    "preserveCommittedReflectionLineage",
                ],
            },
            "allowedSemanticOperations": ["synthesizeDirectReflection"],
            "recoveryPolicy": "repairSameOperation",
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED SYNTHESIS REPAIR", prompt)
        self.assertIn("reflectionFrame.reflectionDelta", prompt)
        self.assertIn("responseFocus is presentation guidance only", prompt)
        self.assertIn("Swift constructs mode, action, committed lineage", prompt)
        self.assertIn("Do not reconstruct or paraphrase", prompt)
        self.assertIn("Do not choose another operation", prompt)
        self.assertNotIn("REQUIRED TENDER REPAIR", prompt)
        self.assertNotIn("REQUIRED CARD OBSERVATION REPAIR", prompt)
        self.assertNotIn("REQUIRED CONTEXT REVIEW REPAIR", prompt)

    def test_tender_synthesis_progression_correction_repairs_the_atomic_delta(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "tender"
        request["allowedSemanticOperations"] = ["synthesizeDirectReflection"]
        request["correction"] = {
            "rejectedOperation": "synthesizeDirectReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "synthesisFrameMissing",
            "rejectedDraft": {
                "semanticOperation": None,
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "reflectionProgressionDecision": {
                    "meaning": "synthesize",
                    "candidateRef": None,
                    "reflectionDelta": None,
                },
                "responseFocus": "这不是持久化的综合内容",
            },
            "issue": {
                "fieldPath": "reflectionProgressionDecision.reflectionDelta",
                "violation": "missing",
                "requiredConditions": [
                    "provideSynthesisFrame",
                    "provideConcreteReflectionDelta",
                ],
            },
            "allowedSemanticOperations": ["synthesizeDirectReflection"],
            "recoveryPolicy": "repairSameOperation",
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED ATOMIC PROGRESSION REPAIR", prompt)
        self.assertIn("reflectionProgressionDecision.meaning=synthesize", prompt)
        self.assertIn("same object's nonempty reflectionDelta", prompt)
        self.assertIn("Omit semanticOperation and memoryUpdate.reflectionFrame", prompt)
        self.assertIn("may preserve the same bounded semantic meaning", prompt)
        self.assertIn("different wording rather than copy", prompt)
        self.assertIn("must still submit it explicitly", prompt)
        self.assertNotIn("distinct Synthesis meaning", prompt)
        self.assertNotIn("REQUIRED SYNTHESIS REPAIR", prompt)

    def test_fierce_correction_completes_or_removes_a_partial_contribution(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "fierce"
        request["allowedSemanticOperations"] = [
            "continueTenderGroundedFierceReflection",
            "synthesizeDirectReflection",
        ]
        request["latestAnswerContext"] = {
            "purpose": "fierceReflection",
            "disclosurePurpose": None,
            "referenceID": "episodeStructure.behaviorEvidence.0",
        }
        request["correction"] = {
            "rejectedOperation": "continueTenderGroundedFierceReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "fierceFrameIncomplete",
            "rejectedDraft": {
                "semanticOperation": "continueTenderGroundedFierceReflection",
                "semanticEvidencePatch": {
                    "memoryUpdate": {
                        "reflectionFrame": {
                            "reflectionDelta": None,
                            "fierceEvidence": {"direction": "change"},
                        }
                    }
                },
                "responseFocus": "继续看同一个现实候选",
            },
            "issue": {
                "fieldPath": "semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta",
                "violation": "empty",
                "requiredConditions": ["provideConcreteReflectionDelta"],
            },
            "allowedSemanticOperations": [
                "continueTenderGroundedFierceReflection",
                "synthesizeDirectReflection",
            ],
            "recoveryPolicy": "repairSameOperation",
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED FIERCE REPAIR", prompt)
        self.assertIn("replace the partial frame with one atomic reflectionProgressionDecision", prompt)
        self.assertIn("nonempty reflectionDelta", prompt)
        self.assertIn("nonempty reflectionDelta and fierceDirection", prompt)
        self.assertIn("Do not repeat candidateRef or groundedEvidence", prompt)
        self.assertIn("latestAnswerContext.referenceID", prompt)
        self.assertIn("Omit semanticOperation", prompt)

    def test_repeated_existing_synthesis_correction_can_dispose_to_practice(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "synthesis"
        request["allowedSemanticOperations"] = [
            "synthesizeDirectReflection",
            "proposePractice",
        ]
        request["semanticMemory"] = {
            "reflectionFrame": {
                "mode": "tender",
                "action": "synthesizeUnderstanding",
                "evidenceBasis": [{"source": "episode", "content": "项目仍然卡住"}],
                "dimensions": [],
                "reflectionDelta": "当前困难不能单独支持更大的自我判断",
                "fierceEvidence": None,
            }
        }
        request["correction"] = {
            "rejectedOperation": "synthesizeDirectReflection",
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "synthesisDeltaMissing",
            "rejectedDraft": {
                "semanticOperation": "synthesizeDirectReflection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "重复已经提交的综合",
            },
            "issue": {
                "fieldPath": "semanticEvidencePatch.memoryUpdate.reflectionFrame.reflectionDelta",
                "violation": "empty",
                "requiredConditions": [
                    "provideConcreteReflectionDelta",
                    "preserveCommittedReflectionLineage",
                ],
            },
            "allowedSemanticOperations": [
                "synthesizeDirectReflection",
                "proposePractice",
            ],
            "recoveryPolicy": "repairSameOperation",
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED SYNTHESIS DISPOSITION REPAIR", prompt)
        self.assertIn("choose proposePractice now", prompt)
        self.assertIn(
            "semanticEvidencePatch.memoryUpdate.practiceTransition",
            prompt,
        )
        self.assertIn("operation substitution and therefore re-planning", prompt)
        self.assertIn("Discard that old operation payload", prompt)
        self.assertIn("materially different reflectionDelta", prompt)
        self.assertIn("do not require another confirmation", prompt)
        self.assertNotIn("keep semanticOperation=synthesizeDirectReflection", prompt)

    def test_tender_frame_allows_sparse_lineage_but_not_missing_semantic_decisions(self) -> None:
        sparse_tender = {
            "semanticOperation": "continueTenderReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {
                        "mode": "tender",
                        "action": "softenGlobalSelfJudgment",
                        "evidenceBasis": [],
                        "dimensions": ["selfKindness"],
                        "reflectionDelta": "当前问题没有解决不等于整个人不适合开发",
                        "fierceEvidence": None,
                    }
                }
            },
            "responseFocus": "形成不攻击自己的理解",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(sparse_tender, ensure_ascii=False)
            )
        )
        frame = canonical["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"]
        self.assertEqual(frame["evidenceBasis"], [])
        self.assertNotIn("mode", frame)
        self.assertNotIn("action", frame)
        self.assertEqual(
            frame["reflectionDelta"],
            "当前问题没有解决不等于整个人不适合开发",
        )

        omitted_lineage = json.loads(json.dumps(sparse_tender, ensure_ascii=False))
        del omitted_lineage["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"][
            "evidenceBasis"
        ]
        canonical_omission = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(omitted_lineage, ensure_ascii=False)
            )
        )
        self.assertNotIn(
            "evidenceBasis",
            canonical_omission["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"],
        )

        self.assertNotIn("mode", frame)

        missing_delta = json.loads(json.dumps(sparse_tender, ensure_ascii=False))
        del missing_delta["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"]["reflectionDelta"]
        canonical_delta = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(missing_delta, ensure_ascii=False)
            )
        )
        self.assertNotIn(
            "reflectionDelta",
            canonical_delta["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"],
        )

    def test_fierce_protocol_shape_accepts_behavior_or_impact_without_inventing_evidence(self) -> None:
        payload = {
            "semanticOperation": "continueTenderGroundedFierceReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "reflectionFrame": {
                        "evidenceBasis": [
                            {
                                "source": "latestUserAnswer",
                                "content": "着急以后同时改了很多地方",
                            }
                        ],
                        "fierceEvidence": {
                            "behavior": "着急以后同时改了很多地方",
                            "direction": "change",
                        },
                    }
                }
            },
            "responseFocus": "只面对同时改动扩大排查困难的做法",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False)
            )
        )
        frame = canonical["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"]
        self.assertNotIn("mode", frame)
        self.assertNotIn("action", frame)
        self.assertNotIn("dimensions", frame)
        self.assertNotIn("reflectionDelta", frame)
        self.assertEqual(frame["evidenceBasis"], ["着急以后同时改了很多地方"])
        self.assertEqual(frame["fierceEvidence"]["behavior"], "着急以后同时改了很多地方")
        self.assertNotIn("impact", frame["fierceEvidence"])

        malformed_sibling = json.loads(json.dumps(payload, ensure_ascii=False))
        malformed_frame = malformed_sibling["semanticEvidencePatch"]["memoryUpdate"][
            "reflectionFrame"
        ]
        malformed_frame["dimensions"] = ["mindfulness", "unsupported"]
        malformed_frame["fierceEvidence"]["impact"] = {"not": "text"}
        with self.assertRaises(CurrentV5PlannerContractError):
            canonicalize_current_v5_planner_contract(
                json.dumps(malformed_sibling, ensure_ascii=False)
            )

        no_grounded_evidence = json.loads(json.dumps(payload, ensure_ascii=False))
        no_grounded_evidence["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"][
            "fierceEvidence"
        ] = {"direction": "change"}
        canonical_empty = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(no_grounded_evidence, ensure_ascii=False)
            )
        )
        fierce = canonical_empty["semanticEvidencePatch"]["memoryUpdate"]["reflectionFrame"][
            "fierceEvidence"
        ]
        self.assertEqual(fierce, {"direction": "change"})

    def test_protocol_owned_candidate_tracking_practice_and_event_metadata_do_not_block_decode(self) -> None:
        candidate = {
            "semanticOperation": "offerCardConnectionCandidate",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "pendingCardRealityConnection": {
                        "id": "not-a-uuid",
                        "imageRelation": "画面里的人停下来检查文件",
                        "candidateRealityMapping": "可能对应现实中继续前没有核对版本",
                    }
                }
            },
            "responseFocus": "提供一个可以拒绝的候选连接",
        }
        canonical_candidate = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(candidate, ensure_ascii=False)
            )
        )
        pending = canonical_candidate["semanticEvidencePatch"]["memoryUpdate"][
            "pendingCardRealityConnection"
        ]
        self.assertNotIn("id", pending)

        tracking = {
            "semanticOperation": "continueExploratoryReflection",
            "semanticEvidencePatch": {
                "contextualTrackingDecision": {
                    "metricEligibility": [
                        {
                            "profileID": "sleep",
                            "metric": "sleepDuration",
                            "status": "doesNotQualify",
                            "preferred": False,
                        }
                    ]
                }
            },
            "responseFocus": "继续当前现实关系",
        }
        canonical_tracking = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(tracking))
        )
        self.assertEqual(
            canonical_tracking["semanticEvidencePatch"]["contextualTrackingDecision"],
            tracking["semanticEvidencePatch"]["contextualTrackingDecision"],
        )
        tracking["semanticEvidencePatch"]["contextualTrackingDecision"] = {
            "selectedProfileIDs": None
        }
        canonical_null_tracking = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(tracking))
        )
        self.assertNotIn(
            "contextualTrackingDecision",
            canonical_null_tracking["semanticEvidencePatch"],
        )

        resolution = {
            "semanticOperation": "resolvePractice",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "practiceTransition": {},
                    "finalNarrative": "保留已经确认的理解。",
                }
            },
            "responseFocus": "接受当前小步并进入最终叙事",
        }
        canonical_resolution = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(resolution, ensure_ascii=False)
            )
        )
        transition = canonical_resolution["semanticEvidencePatch"]["memoryUpdate"][
            "practiceTransition"
        ]
        self.assertEqual(transition, {})

        event = {
            "semanticOperation": "clarifyEvent",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "eventDisclosureOutcome": "complete",
                    "clearCardRealityConnection": "sometimes",
                    "clearPendingCardRealityConnection": {"invalid": True},
                    "cardConnectionOutcome": "complete",
                    "episodeStructure": {
                        "behaviorEvidenceStatus": "complete",
                        "behaviorEvidence": ["汇报前没有核对图片版本"],
                        "eventProcessStatus": "complete",
                        "eventProcess": ["展示时才发现放错了版本"],
                        "impactStatus": "complete",
                    },
                }
            },
            "responseFocus": "只补足仍缺少的事件事实",
        }
        canonical_event = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(event, ensure_ascii=False)
            )
        )["semanticEvidencePatch"]["memoryUpdate"]
        self.assertNotIn("eventDisclosureOutcome", canonical_event)
        self.assertNotIn("clearCardRealityConnection", canonical_event)
        self.assertNotIn("clearPendingCardRealityConnection", canonical_event)
        self.assertNotIn("cardConnectionOutcome", canonical_event)
        episode = canonical_event["episodeStructure"]
        self.assertNotIn("behaviorEvidenceStatus", episode)
        self.assertNotIn("eventProcessStatus", episode)
        self.assertNotIn("impactStatus", episode)

    def test_direct_memory_connection_is_consolidated_into_the_single_typed_outcome(self) -> None:
        payload = {
            "semanticOperation": "continueOpenCardConnection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "cardRealityConnection": {
                        "imageRelation": "一个人关上门后暂时独处",
                        "realityMapping": "汇报失误后因为尴尬想自己待一会",
                    }
                }
            },
            "responseFocus": "沿用户已经说出的连接进入现实探索",
        }

        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(payload, ensure_ascii=False),
                allowed_semantic_operations=[
                    "continueOpenCardConnection",
                    "establishUserAuthoredCardConnection",
                ],
            )
        )
        self.assertEqual(canonical["semanticOperation"], "continueOpenCardConnection")
        memory = canonical["semanticEvidencePatch"]["memoryUpdate"]
        self.assertNotIn("cardRealityConnection", memory)
        self.assertEqual(
            canonical["semanticEvidencePatch"]["cardConnectionEvidence"],
            {
                "imageRelation": "一个人关上门后暂时独处",
                "realityMapping": "汇报失误后因为尴尬想自己待一会",
            },
        )

    def test_tender_builds_one_bounded_understanding_without_forcing_one_turn(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueTenderReflection"]
        request["semanticMemory"] = {
            "selfCriticismStatus": "present",
            "selfCriticalStatement": "我根本不适合科研",
        }
        request["reflectionMode"] = "exploratory"
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("Form one bounded compassionate understanding", planner_prompt)
        self.assertIn("dimensions may contain", planner_prompt)
        self.assertIn("selfKindness/commonHumanity/mindfulness", planner_prompt)
        self.assertIn("The first proposal is not completion", planner_prompt)
        self.assertIn("authors a bounded account, accepts or qualifies it", planner_prompt)
        self.assertIn("emotional improvement is not required", planner_prompt)
        self.assertIn("Do not ask where the judgment is weakest", planner_prompt)
        self.assertIn("what the distinction means", planner_prompt)
        self.assertIn("Continue only to repair explicit rejection", planner_prompt)
        self.assertIn("Prefer inspectReality when any committed user evidence", planner_prompt)
        self.assertIn("One grounded fact suffices", planner_prompt)
        self.assertIn("two facts, causality, or a user-proposed action are not required", planner_prompt)
        self.assertIn("confirmation, revision, rejection, or qualification", planner_prompt)
        self.assertIn("Use synthesize only when no such part remains", planner_prompt)
        self.assertIn("non-user material cannot ground Fierce or Action", planner_prompt)
        self.assertIn("Use only reflectionProgressionDecision", planner_prompt)
        self.assertIn("latestAnswerContext.referenceID", planner_prompt)
        self.assertIn('"meaning":"clarifyFierce"', planner_prompt)
        self.assertIn('"meaning":"completeFierce"', planner_prompt)
        self.assertNotIn("acknowledgeExperience", planner_prompt)
        self.assertNotIn("connectCommonHumanity", planner_prompt)

        directive = {
            "semanticOperation": "continueTenderReflection",
            "responseFocus": "用户说没有开发经验且不太记得；改问其他成功难题和建议，证明其实有能力也能坚持",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "tenderReflection"},
            "localAction": "none",
            "memoryUpdate": {
                "reflectionFrame": {
                    "mode": "tender",
                    "action": "softenGlobalSelfJudgment",
                    "evidenceBasis": [
                        {"source": "episode", "content": "一次具体困难仍未解决"}
                    ],
                    "dimensions": ["mindfulness"],
                    "reflectionDelta": "当前事实不足以支持整体自我否定",
                    "fierceEvidence": None,
                }
            },
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("without making the person argue against themselves", writer_prompt)
        self.assertIn("show its connection to the broader judgment", writer_prompt)
        self.assertIn("never retell chronology", writer_prompt)
        self.assertIn("revise only that mismatch", writer_prompt)
        self.assertIn("do not replay the understanding", writer_prompt)
        self.assertIn("ask for its weakness, meaning, emotional effect", writer_prompt)
        self.assertIn("Do not say the response is natural", writer_prompt)
        self.assertIn("is not a real measure", writer_prompt)
        self.assertIn("revise only that mismatch", writer_prompt)
        self.assertIn("Use a neutral reference instead of repeating", writer_prompt)
        self.assertIn("Never assign a difficulty, painful experience, self-critical thought", writer_prompt)
        self.assertIn("hidden benefit", writer_prompt)
        self.assertIn("operation contract outranks it", writer_prompt)

    def test_current_reflection_contract_keeps_tender_dialogue_and_fierce_need_oriented(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueTenderReflection",
            "continueTenderGroundedFierceReflection",
            "synthesizeDirectReflection",
        ]
        request["semanticMemory"] = {
            "selfCriticalStatement": "我根本不适合科研",
            "selfCriticismLink": "项目受阻被扩大成不适合科研",
        }
        request["reflectionMode"] = "tender"
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("The first proposal is not completion", planner_prompt)
        self.assertIn("authors a bounded account, accepts or qualifies it", planner_prompt)
        self.assertIn("emotional improvement is not required", planner_prompt)
        self.assertIn("Do not ask where the judgment is weakest", planner_prompt)
        self.assertIn("Continue only to repair explicit rejection", planner_prompt)
        self.assertIn("One grounded fact suffices", planner_prompt)
        self.assertIn("two facts, causality, or a user-proposed action are not required", planner_prompt)
        self.assertIn("confirmation, revision, rejection, or qualification", planner_prompt)
        self.assertIn("concrete candidate", planner_prompt)
        self.assertIn("reflectionDelta\":null", planner_prompt)
        self.assertIn("A grounded/qualified direction returns", planner_prompt)
        self.assertIn("Use only reflectionProgressionDecision", planner_prompt)
        self.assertIn("Protection is user-authored", planner_prompt)
        self.assertIn("Grounded repair/protect/change ends Fierce", planner_prompt)
        self.assertIn("ask no more", planner_prompt)
        self.assertIn("Swift opens Synthesis", planner_prompt)
        self.assertIn("Swift recovers the active candidate", planner_prompt)
        self.assertNotIn('"groundedEvidence":"exact user-grounded direction"', planner_prompt)
        self.assertIn("support/provision maps to protect", planner_prompt)
        self.assertIn("Swift supplies them and joins reality", planner_prompt)
        self.assertNotIn("at least behavior or impact must come from the user", planner_prompt)
        self.assertIn("non-user material cannot ground Fierce or Action", planner_prompt)

        directive = {
            "semanticOperation": "continueTenderGroundedFierceReflection",
            "responseFocus": "理解用户已确认但尚未满足的恢复需要",
            "reflectionRealization": "bridgeToSynthesis",
            "mayAskQuestion": False,
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "synthesisReflection"},
            "localAction": "none",
            "memoryUpdate": {
                "reflectionFrame": {
                    "mode": "fierce",
                    "action": "clarifyBoundaryOrNeed",
                    "evidenceBasis": [
                        {"source": "latestUserAnswer", "content": "我现在需要一点恢复时间"}
                    ],
                    "dimensions": ["selfKindness"],
                    "reflectionDelta": "当前需要恢复时间",
                    "fierceEvidence": {
                        "behavior": "",
                        "impact": "我现在需要一点恢复时间",
                        "direction": "protect",
                    },
                }
            },
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("State the committed repair, protection, or change direction", writer_prompt)
        self.assertIn("do not create Synthesis or Action content", writer_prompt)
        self.assertIn("post-turn phase is Synthesis", writer_prompt)
        self.assertIn("Ask no question", writer_prompt)
        self.assertIn("Ignore any stale responseFocus", writer_prompt)
        self.assertIn("Do not add a question", writer_prompt)

        opening_directive = dict(directive)
        opening_directive["reflectionRealization"] = "askFierceClarification"
        opening_directive["mayAskQuestion"] = True
        opening_directive["memoryUpdate"] = {}
        opening_directive["nextPrompt"] = {
            "kind": "openQuestion",
            "purpose": "fierceReflection",
        }
        opening_directive["responseFocus"] = (
            "用户仍想继续；共同看看现在有什么值得保护、获得、承担或改变"
        )
        opening_writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": opening_directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system
        self.assertIn("one user-grounded Protect, Provide, Repair, or Motivate inquiry", opening_writer_prompt)
        self.assertIn("Keep the committed Tender understanding present", opening_writer_prompt)
        self.assertIn("responseFocus is the exact Swift-validated groundedRealityCandidate content", opening_writer_prompt)
        self.assertIn("Use the latest answer and only that candidate to ask about one narrow reality-facing part", opening_writer_prompt)
        self.assertIn("a tentative relation between two facts is optional, never required", opening_writer_prompt)
        self.assertIn("confirming, revising, rejecting, or qualifying", opening_writer_prompt)
        self.assertIn("without a ‘you said/mentioned’ preface or chronology recap", opening_writer_prompt)
        self.assertIn("Name the actual action, condition, person, or result", opening_writer_prompt)
        self.assertIn("do not ask the person to identify an abstract issue", opening_writer_prompt)
        self.assertIn("whole-person judgment, reality tension, something worth facing", opening_writer_prompt)
        self.assertIn("Do not state the answer", opening_writer_prompt)
        self.assertIn("Action comes later", opening_writer_prompt)
        self.assertIn("the inquiry is legally continuing", opening_writer_prompt)
        self.assertIn("latestAnswerContext.referenceID preserves that same candidate", opening_writer_prompt)

        opening_planner_output = {
            "semanticOperation": "continueTenderGroundedFierceReflection",
            "semanticEvidencePatch": {"memoryUpdate": {}},
            "responseFocus": "沿已有现实材料共同了解值得保护、获得、承担或改变的部分",
        }
        canonical_opening = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(opening_planner_output, ensure_ascii=False)
            )
        )
        self.assertEqual(
            canonical_opening["semanticOperation"],
            "continueTenderGroundedFierceReflection",
        )
        self.assertEqual(
            canonical_opening["semanticEvidencePatch"]["memoryUpdate"],
            {},
        )

    def test_planner_loads_only_the_current_stage_contract(self) -> None:
        event_item = LLMTurnPromptIn(
            promptTask="planner",
            promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
            payload={"request": self.request()},
            maxTokens=900,
            temperature=0.2,
        )
        event_prompt = build_turn_messages(event_item).system
        event_shape = json.loads(CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE)
        self.assertEqual(
            set(event_shape),
            {"selfCriticalStatement", "episodeStructure"},
        )
        episode_shape = event_shape["episodeStructure"]
        self.assertEqual(
            set(episode_shape),
            {
                "concreteFacts",
                "eventProcess",
                "behaviorEvidence",
            },
        )
        self.assertIn(CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE, event_prompt)
        self.assertIn("Swift accumulates", event_prompt)

        self.assertIn("A reported outcome plus an emotion or", event_prompt)
        self.assertIn("broad self-judgment is not enough", event_prompt)
        self.assertIn("never copy the endpoint into eventProcess", event_prompt)
        self.assertIn("Prioritize the person's concrete action/response", event_prompt)
        self.assertIn("never combine interview questions", event_prompt)
        self.assertIn("When the focal experience, one genuine development relation", event_prompt)
        self.assertIn("stop adding Event questions", event_prompt)
        self.assertIn("choose clarifyEvent even when the latest answer completes it", event_prompt)
        self.assertIn("Swift project the post-turn Card Consent", event_prompt)
        self.assertIn("implementation, troubleshooting, hypothetical alternatives", event_prompt)
        self.assertIn("self-criticism statement is separate from episode impacts", event_prompt)
        self.assertIn("memoryUpdate.selfCriticalStatement", event_prompt)
        self.assertIn("as a sibling of episodeStructure", event_prompt)
        self.assertNotIn("selfCriticismStatus", event_prompt)
        self.assertIn("Never store an emotion, worry, self-evaluation", event_prompt)
        self.assertIn("impacts are concrete consequences", event_prompt)
        self.assertNotIn("CARD CONNECTION SHAPE", event_prompt)
        self.assertNotIn("REFLECTION STRUCTURE", event_prompt)
        self.assertNotIn("OPTIONAL ACTION STRUCTURE", event_prompt)

        card_request = self.request()
        card_request["protocolStage"] = "cardReflection"
        card_request["allowedSemanticOperations"] = ["inviteRealityConnection"]
        card_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": card_request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system
        self.assertIn("CARD CONNECTION SHAPE", card_prompt)
        self.assertIn(CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE, card_prompt)
        self.assertNotIn("REFLECTION STRUCTURE", card_prompt)
        self.assertNotIn("reflectionFrame=", card_prompt)
        self.assertIn("perceptually understandable but interpretively open scene", card_prompt)
        self.assertIn("Once the scene is roughly understandable", card_prompt)
        self.assertIn("do not ask what else is visible", card_prompt)
        self.assertIn("DEVELOPMENT is one broad, concrete image-only question", card_prompt)
        self.assertIn("Do not ask what is still open, unresolved", card_prompt)
        self.assertIn("combine elements into a new interpretation", card_prompt)
        self.assertIn("latestAnswerContext.purpose=cardDevelopment", card_prompt)
        self.assertIn("choose continueCardDevelopment", card_prompt)
        self.assertIn("after this one answer", card_prompt)
        self.assertIn("simple possibility or inability to tell", card_prompt)
        self.assertIn("Never seek another ambiguity or enrich the image", card_prompt)
        self.assertIn("REALITY CONNECTION: first ask one unpresupposed bridge", card_prompt)
        self.assertIn("do not state an analogy", card_prompt)
        self.assertIn("preselect a similarity, difference, tension", card_prompt)
        self.assertIn("judge only whether the answer gives", card_prompt)
        self.assertIn("relation, continuation, difference, or tension", card_prompt)
        self.assertIn("no Card mention, image restatement", card_prompt)
        self.assertIn("Never judge Card fit", card_prompt)
        self.assertIn("cardDevelopmentEvidence is optional", card_prompt)
        self.assertIn("Emit imageRelation only when the latest user answer", card_prompt)
        self.assertIn("keep the current Reality act", card_prompt)
        self.assertIn("cardConnectionEvidence", card_prompt)
        self.assertIn("object/property correspondence alone is not a reality relation", card_prompt)
        self.assertIn("continue once in lived-reality language", card_prompt)
        self.assertIn("one scaffold using only user-authored image-side openness", card_prompt)
        self.assertIn("no proposed reality meaning", card_prompt)
        self.assertIn("Establish and exit once the reality relation exists", card_prompt)
        self.assertIn("Do not seek Card meaning, psychology", card_prompt)
        self.assertIn("never emit outcome/source/status/confirmation/phase metadata", card_prompt)
        self.assertNotIn("OPTIONAL ACTION STRUCTURE", card_prompt)

    def test_exploration_writer_has_no_default_recap_progress_question_scaffold(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["semanticMemory"] = {
            "selfCriticalStatement": "我不适合科研",
            "cardRealityConnection": {
                "imageRelation": "人物遇到阻力后停下来重新判断",
                "realityMapping": "实验受阻时我会不断修改",
                "source": "userAuthored",
                "status": "confirmed",
            },
        }
        request["reflectionMode"] = "exploratory"
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "询问不适合科研这个判断在当时何时开始出现",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {
                "kind": "openQuestion",
                "purpose": "exploratoryReflection",
            },
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("ask one easy neutral question only", prompt)
        self.assertIn("Do not paraphrase the latest answer merely", prompt)
        self.assertIn("Avoid recap–progress–question templates", prompt)
        self.assertIn("Once a relation is stated, use it rather", prompt)
        self.assertIn("than renaming it", prompt)
        self.assertIn("Ask exactly the one required open, low-burden", prompt)
        self.assertIn("otherwise ask none", prompt)
        self.assertIn("without forced either-or choices", prompt)
        self.assertIn("em-dash reveals", prompt)

    def test_card_consent_resolves_brief_unqualified_acceptance_once(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardConsent"
        request["allowedSemanticOperations"] = [
            "inviteCardConsent",
            "acknowledgeCardConsent",
            "declineCardConsent",
        ]
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("unqualified affirmative response", prompt)
        self.assertIn("brevity is not ambiguity", prompt)
        self.assertIn("must never trigger another invitation", prompt)
        self.assertIn("genuinely unresolved answer, question, or hesitation", prompt)

    def test_first_connection_scaffold_does_not_supply_a_reality_mapping(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["offerCardConnectionScaffold"]
        directive = {
            "semanticOperation": "offerCardConnectionScaffold",
            "responseFocus": "用封闭、手机和外部帮助解释画面，帮助用户建立联系",
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {
                "kind": "openQuestion",
                "purpose": "cardRealityConnectionScaffold",
            },
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Do not supply a connection", prompt)
        self.assertIn("only an object/property correspondence", prompt)
        self.assertIn("leave image language completely", prompt)
        self.assertIn("inside the focal lived episode", prompt)
        self.assertIn("facts, actions, results, constraints, or handling", prompt)
        self.assertIn("Do not mention Card elements", prompt)
        self.assertIn("ask what is most similar", prompt)
        self.assertIn("improve the analogy", prompt)
        self.assertIn("After a first no-connection answer", prompt)
        self.assertIn("using only an uncertainty, unresolved relation", prompt)
        self.assertIn("Preserve their modality", prompt)
        self.assertIn("add no object, condition, action, channel", prompt)
        self.assertIn("Name only the image-side openness", prompt)
        self.assertIn("Do not assign it a reality meaning", prompt)
        self.assertIn("external help", prompt)
        self.assertIn("operation contract outranks it", prompt)

    def test_no_connection_bypass_adds_no_scene_or_candidate_frame(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["bypassCardConnectionToDirectReflection"]
        directive = {
            "semanticOperation": "bypassCardConnectionToDirectReflection",
            "responseFocus": "接受暂时想不到连接，回到当前现实经历",
            "sourceStage": "cardReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "exploratoryReflection"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Accept that no connection came naturally", prompt)
        self.assertIn("let the Card recede without interpreting it", prompt)
        self.assertIn("Add no scene element, hypothetical detail", prompt)
        self.assertIn("neutral, easy question about the focal lived episode", prompt)

    def test_thin_correspondence_after_a_scaffold_still_returns_to_reality_language(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["continueOpenCardConnection"]
        directive = {
            "semanticOperation": "continueOpenCardConnection",
            "responseFocus": "用户只说论文可能也需要改；回到评审意见询问具体调整关系",
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "cardRealityConnection"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Handle the current Reality task", prompt)
        self.assertIn("plausible reality-internal relation", prompt)
        self.assertIn("entirely in lived-reality language", prompt)
        self.assertIn("do not mention Card elements, similarity, correspondence, or metaphor", prompt)
        self.assertIn("keep the existing difficulty handling bounded", prompt)
        self.assertIn("do not manufacture one", prompt)

    def test_exploration_stops_searching_for_external_reactions_after_source_is_clear(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        request["semanticMemory"] = {
            "cardRealityConnection": {
                "imageRelation": "人物停下来重新安排手中的东西",
                "realityMapping": "我也许需要在继续修改前停下来判断什么已经够用",
                "source": "userAuthored",
                "status": "confirmed",
            },
            "cardDevelopmentEvidence": {
                "actorsOrElements": ["人物", "手中的东西"],
                "projectiveFocus": "停下来重新安排",
                "relationOrAction": "人物重新安排手中的东西",
                "anticipatedChangeOrChoice": "整理后再继续前进",
            },
        }
        request["reflectionMode"] = "exploratory"
        request["card"] = {
            "imageIsDisplayed": True,
            "imageDevelopmentTurnCount": 2,
            "connectionAttemptCount": 0,
            "connectionScaffoldUsed": False,
            "connectionUnavailable": False,
            "connectionInteractionState": "openExploration",
            "realityAnchor": None,
            "visualScaffolds": [],
            "reflectionApproaches": {
                "tender": "system tender boundary",
                "fierce": "system fierce boundary",
            },
            "referenceGuidance": {
                "relations": ["已有资源与实际行动之间的关系"],
                "activationBoundary": "仅在用户自己的连接支持时使用",
                "prohibitedClaims": ["不能把参考关系当作用户答案"],
            },
            "prohibitedClaims": [],
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("cardRealityConnection -> selfCriticismLink", prompt)
        self.assertIn("A user-grounded difficulty-to-judgment relation is enough", prompt)
        self.assertIn(
            "On completion, memoryUpdate contains the aligned link and no Tender reflectionFrame",
            prompt,
        )
        self.assertIn("next Planner act forms the first bounded Tender understanding", prompt)
        self.assertIn("Greater specificity is not greater reflective value", prompt)
        self.assertIn("Do not seek causes, Card meaning, advice", prompt)
        self.assertIn("referenceGuidance may only select an adjacent grounded question", prompt)
        self.assertIn("it is never evidence", prompt)

    def test_writer_language_contract_follows_card_progression(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["inviteRealityConnection"]
        directive = {
            "semanticOperation": "inviteRealityConnection",
            "responseFocus": "把用户说出的画面关系连接到当前事件",
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "cardRealityConnection"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("one unpresupposed bridge question", prompt)
        self.assertIn("just-discussed scene back in the focal lived situation", prompt)
        self.assertIn("what comes first to the person's mind", prompt)
        self.assertIn("把刚才这段画面放回当时的情境里，你最先想到什么", prompt)
        self.assertIn("Refer to the scene as a whole", prompt)
        self.assertIn("do not restate an individual image property", prompt)
        self.assertIn("describe an abstract inner feeling", prompt)
        self.assertIn("Do not state an analogy before the question", prompt)
        self.assertIn("interpret or summarize the scene", prompt)
        self.assertIn("name its real counterpart", prompt)
        self.assertIn("preselect a similarity/difference/tension", prompt)
        self.assertIn("target a particular episode element", prompt)
        self.assertIn("The person authors the first connection", prompt)
        self.assertIn("Do not paraphrase the latest answer merely", prompt)

    def test_writer_does_not_routinely_restate_the_latest_user_answer(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "沿用户已经形成的现实连接探索下一项具体体验",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "exploratoryReflection"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Do not paraphrase the latest answer merely", prompt)
        self.assertIn("referenceGuidance is silent", prompt)
        self.assertIn("never reply content or evidence", prompt)
        self.assertIn("Do not reopen Card meaning", prompt)
        self.assertIn("Use at most one necessary factual anchor", prompt)

    def test_exploration_completion_writer_carries_link_without_tender_distinction(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        request["reflectionMode"] = "exploratory"
        request["semanticMemory"] = {
            "selfCriticalStatement": "我能力不够",
            "selfCriticismLink": "反复卡住以后，逐渐把没有进展解释成能力不够",
        }
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "承接已经形成的累积关系",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "tenderReflection"},
            "localAction": "none",
            "memoryUpdate": {
                "selfCriticismLink": "反复卡住以后，逐渐把没有进展解释成能力不够",
                "reflectionPhase": "tender",
            },
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Exploration has completed", prompt)
        self.assertIn("projected phase is Tender", prompt)
        self.assertIn("Briefly carry forward only the grounded", prompt)
        self.assertIn("invite the person to continue", prompt)
        self.assertIn("do not state a Tender distinction yet", prompt)
        self.assertNotIn("already-authorized first bounded Tender understanding", prompt)
        self.assertNotIn("Express that exact semantic proposition", prompt)

    def test_reference_guidance_cannot_become_later_reflection_content(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["card"] = {
            "imageIsDisplayed": True,
            "imageDevelopmentTurnCount": 2,
            "connectionAttemptCount": 0,
            "connectionScaffoldUsed": False,
            "connectionUnavailable": False,
            "connectionInteractionState": "openExploration",
            "realityAnchor": None,
            "visualScaffolds": [],
            "reflectionApproaches": {
                "tender": "system tender boundary",
                "fierce": "system fierce boundary",
            },
            "referenceGuidance": {
                "relations": ["已有资源与实际行动之间的关系"],
                "activationBoundary": "仅用于共同支持的探索问题",
                "prohibitedClaims": ["不能把参考关系当作用户答案"],
            },
            "prohibitedClaims": [],
        }

        contracts = {
            "continueTenderReflection": (
                "Card, referenceGuidance, and tracking cannot supply"
            ),
            "continueTenderGroundedFierceReflection": (
                "Card material, referenceGuidance, and tracking remain background"
            ),
            "synthesizeDirectReflection": (
                "referenceGuidance is not synthesis material"
            ),
        }
        for operation, expected in contracts.items():
            with self.subTest(operation=operation):
                directive = {
                    "semanticOperation": operation,
                    "responseFocus": "只使用已经 grounded 的用户材料",
                    "sourceStage": "directReflection",
                    "destinationStage": "directReflection",
                    "nextPrompt": {"kind": "none"},
                    "localAction": "none",
                    "memoryUpdate": {},
                    "rewriteReason": None,
                }
                prompt = build_turn_messages(
                    LLMTurnPromptIn(
                        promptTask="writer",
                        promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                        payload={"request": request, "directive": directive},
                        maxTokens=500,
                        temperature=0.3,
                    )
                ).system
                self.assertIn(expected, prompt)

    def test_card_development_writer_asks_one_concrete_future_question(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["continueCardDevelopment"]
        directive = {
            "semanticOperation": "continueCardDevelopment",
            "responseFocus": "继续发展用户指出但尚未处理的画面选择",
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "cardDevelopment"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("sole direct, open image-only question", prompt)
        self.assertIn("how the scene may continue or what may happen next", prompt)
        self.assertIn("Do not ask what feels open, unresolved, hanging", prompt)
        self.assertIn("do not ask which part, where, or what step is unresolved", prompt)
        self.assertIn("do not combine their elements into a new narrative relation", prompt)
        self.assertIn("do not choose why, cause", prompt)
        self.assertIn("Do not preface it with a summary, abstraction, or interpretation", prompt)
        self.assertIn("Do not request more", prompt)
        self.assertIn("posture, gesture, orientation, body detail", prompt)
        self.assertIn("do not introduce examples, dimensions, candidate answers", prompt)
        self.assertIn("answer need not resolve anything", prompt)
        self.assertIn("must not be repeated", prompt)

    def test_completed_development_act_writes_reality_invitation_not_another_image_question(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["continueCardDevelopment"]
        directive = {
            "semanticOperation": "continueCardDevelopment",
            "responseFocus": None,
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "cardRealityConnection"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("one unpresupposed bridge question", prompt)
        self.assertIn("just-discussed scene back in the focal lived situation", prompt)
        self.assertIn("what comes first to the person's mind", prompt)
        self.assertNotIn("sole direct, open image-only question", prompt)
        self.assertNotIn("what feels open, unresolved, hanging", prompt)

    def test_card_observation_writer_does_not_open_unmentioned_dimensions(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["continueCardObservation"]
        directive = {
            "semanticOperation": "continueCardObservation",
            "responseFocus": "开放邀请用户描述画面中正在发生什么",
            "sourceStage": "cardReflection",
            "destinationStage": "cardReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "cardObservation"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("one free account of what is visibly happening", prompt)
        self.assertIn("Do not ask for more inventory", prompt)
        self.assertIn("posture, gesture, orientation, expression", prompt)
        self.assertIn("responsibility, importance, symbolism", prompt)
        self.assertIn("another unmentioned dimension", prompt)
        self.assertIn("summary, abstraction, or interpretation", prompt)

    def test_answering_the_single_development_invitation_closes_card_exploration(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = [
            "continueCardDevelopment",
            "inviteRealityConnection",
        ]
        request["semanticMemory"] = {
            "cardObservationEvidence": {
                "userDescribedElements": ["有人在摆摊，然后下雨了"],
            },
        }
        request["latestAnswerContext"] = {
            "kind": "openQuestion",
            "purpose": "cardDevelopment",
            "disclosurePurpose": None,
            "target": None,
            "referenceID": None,
        }
        request["recentMessages"] = [
            {"role": "assistant", "content": "这里有没有什么地方让你觉得还说不准？"},
            {"role": "user", "content": "不知道"},
        ]
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        )

        self.assertIn("latestAnswerContext.purpose=cardDevelopment", prompt.system)
        self.assertIn("choose continueCardDevelopment", prompt.system)
        self.assertIn("Swift then opens Reality Connection after this one answer", prompt.system)
        self.assertIn("simple possibility or inability to tell", prompt.system)
        self.assertIn('"content":"不知道"', prompt.user)
        self.assertIn('"latestAnswerContext":', prompt.user)
        self.assertNotIn('"nextPrompt":', prompt.user)

    def test_card_consent_writer_cannot_preview_the_random_card(self) -> None:
        request = self.request()
        request["protocolStage"] = "contextualDisclosure"
        request["allowedSemanticOperations"] = ["advanceToCardConsent"]
        directive = {
            "semanticOperation": "advanceToCardConsent",
            "responseFocus": "简短承接并邀请随机反思卡",
            "sourceStage": "contextualDisclosure",
            "destinationStage": "cardConsent",
            "nextPrompt": {"kind": "confirmationRequest", "target": "cardConsent"},
            "localAction": "none",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("The card has not been drawn", prompt)
        self.assertIn("never describe or predict its image, text, message, meaning, advice", prompt)
        self.assertIn("explicit broad self-critical statement", prompt)
        self.assertIn("distinguish what it establishes from that broader verdict", prompt)
        self.assertIn("do not deny the verdict as a fact", prompt)
        self.assertIn("infer an unreported emotion", prompt)
        self.assertIn("responseFocus is a", prompt)
        self.assertIn("goal, not evidence", prompt)
        self.assertIn("Event-analysis question before or after the invitation", prompt)
        self.assertIn("The consent question is the only question", prompt)
        self.assertIn("operation contract outranks it", prompt)

    def test_completed_clarify_event_turn_realizes_card_consent_not_event_exploration(self) -> None:
        request = self.request()
        request["protocolStage"] = "contextualDisclosure"
        request["allowedSemanticOperations"] = ["clarifyEvent"]
        directive = {
            "semanticOperation": "clarifyEvent",
            "responseFocus": None,
            "sourceStage": "contextualDisclosure",
            "destinationStage": "cardConsent",
            "nextPrompt": {
                "kind": "confirmationRequest",
                "target": "cardConsent",
            },
            "localAction": "none",
            "memoryUpdate": {
                "episodeStructure": {
                    "concreteFacts": ["同事临时交来额外工作"],
                    "behaviorEvidence": ["用户接下了额外工作"],
                    "eventProcess": ["接下额外工作后自己的工作没有完成"],
                }
            },
            "rewriteReason": None,
        }

        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Swift has projected Card Consent for the next turn", prompt)
        self.assertIn("invite one random reflection card", prompt)
        self.assertIn("Do not ask another Event question", prompt)
        self.assertIn("The consent question is the only question", prompt)

    def test_user_authored_connection_enters_exploration_without_tender_frame(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["continueOpenCardConnection"]
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("cardConnectionEvidence", prompt)
        self.assertNotIn("REFLECTION STRUCTURE", prompt)
        self.assertIn("Swift merges this semantic evidence with committed user evidence", prompt)
        self.assertIn("derives whether the current Card act completes", prompt)
        self.assertIn("Establish and exit once the reality relation exists", prompt)
        self.assertIn("Do not seek Card meaning, psychology", prompt)
        self.assertIn("responsibility, solution, or action", prompt)
        self.assertNotIn("reflectionFrame", prompt)

    def test_user_authored_connection_writer_cannot_reopen_card_mapping(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["establishUserAuthoredCardConnection"]
        directive = {
            "semanticOperation": "establishUserAuthoredCardConnection",
            "responseFocus": "继续让用户选择照片还是钟，并说明哪一个反差最大",
            "sourceStage": "cardReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {
                "kind": "openQuestion",
                "purpose": "exploratoryReflection",
                "focus": "explore_from_user_authored_connection",
            },
            "localAction": "shareCardGuidance",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Preserve the stated relation as the person's own", prompt)
        self.assertIn("let the Card recede", prompt)
        self.assertIn("complete as soon as a plausible reality-internal relation exists", prompt)
        self.assertIn("does not need a self-criticism insight", prompt)
        self.assertIn("one neutral lived-reality Exploration question", prompt)
        self.assertIn("do not assume a cause or default to a specific trigger", prompt)
        self.assertIn("Do not name Card elements", prompt)
        self.assertIn("reopen comparison", prompt)
        self.assertIn("explain what the connection means", prompt)
        self.assertIn("add an insight, action, Tender interpretation", prompt)
        self.assertIn("operation contract outranks it", prompt)

    def test_direct_reflection_contract_uses_typed_phase_and_invalidates_rejected_meaning(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        request["semanticMemory"] = {
            "invalidatedInterpretations": ["用户面对bug很有耐心"],
        }
        request["reflectionMode"] = "exploratory"
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("Use Swift's read-only reflectionMode", prompt)
        self.assertNotIn("nextPrompt", prompt)
        self.assertIn("continueExploratoryReflection", prompt)
        self.assertIn("Exploration emits selfCriticismLink and no reflectionFrame", prompt)
        self.assertIn("Tender/Synthesis meaning uses reflectionFrame.reflectionDelta", prompt)
        self.assertIn("Swift never", prompt)
        self.assertIn("uses it as a reflectionDelta fallback", prompt)
        self.assertIn("Never also emit a reflectionFrame for a Fierce progression", prompt)
        self.assertIn("colocates only reflectionDelta and fierceDirection", prompt)
        self.assertIn("latest user answer, and committed evidence lineage", prompt)
        self.assertIn("reflectionProgressionDecision is the sole meaning owner", prompt)
        self.assertIn("Canonical lineage is cardRealityConnection -> selfCriticismLink", prompt)
        self.assertIn("A user-grounded difficulty-to-judgment relation is enough", prompt)
        self.assertIn("invalidatedInterpretations", prompt)
        self.assertIn("append to episodeStructure only a newly user-grounded", prompt)
        self.assertIn("exclude Card, Tracking, reference guidance, model inference", prompt)
        self.assertIn("REFLECTION STRUCTURE", prompt)

    def test_self_criticism_link_transport_preserves_meaning_without_backend_compilation(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        request["semanticMemory"] = {}
        request["reflectionMode"] = "exploratory"
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn(
            "selfCriticismLink carries relationship meaning, not Swift's stored protocol string",
            prompt,
        )
        self.assertIn("Canonical lineage", prompt)
        self.assertIn("Swift joins the grounded meaning", prompt)
        self.assertIn("Card material, emotion, impact, or blockage", prompt)

        valid = {
            "semanticOperation": "continueTenderReflection",
            "semanticEvidencePatch": {
                "memoryUpdate": {
                    "selfCriticismLink": "实验修改后的不确定性被扩大成自己不适合科研",
                }
            },
            "responseFocus": "形成有依据的 Tender 区分",
        }
        canonical = json.loads(
            canonicalize_current_v5_planner_contract(
                json.dumps(valid, ensure_ascii=False)
            )
        )
        self.assertEqual(
            canonical["semanticEvidencePatch"]["memoryUpdate"]["selfCriticismLink"],
            "实验修改后的不确定性被扩大成自己不适合科研",
        )

        omitted = {
            "semanticOperation": "continueExploratoryReflection",
            "semanticEvidencePatch": {"memoryUpdate": {}},
            "responseFocus": "继续澄清现实关系",
        }
        canonical_omitted = json.loads(
            canonicalize_current_v5_planner_contract(json.dumps(omitted))
        )
        self.assertNotIn(
            "selfCriticismLink",
            canonical_omitted["semanticEvidencePatch"]["memoryUpdate"],
        )

        for structured_link in (
            {"reality": "等待修改结果", "selfJudgment": "不适合科研"},
            ["等待修改结果", "不适合科研"],
            {"groundedDifficulty": "反复修改仍无法推进"},
            {"unknownProviderShape": {"nested": True}},
        ):
            structured = dict(valid)
            structured["semanticEvidencePatch"] = {
                "memoryUpdate": {"selfCriticismLink": structured_link}
            }
            canonical_structured = json.loads(
                canonicalize_current_v5_planner_contract(
                    json.dumps(structured, ensure_ascii=False)
                )
            )
            self.assertEqual(
                canonical_structured["semanticEvidencePatch"]["memoryUpdate"]
                    ["selfCriticismLink"],
                structured_link,
            )

    def test_self_criticism_link_correction_repairs_only_the_exact_endpoint(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "tender"
        request["allowedSemanticOperations"] = ["continueTenderReflection"]
        request["semanticMemory"] = {
            "selfCriticalStatement": "会觉得自己能力不好",
            "selfCriticismLink": "越急越改 -> 一直不能往下推进",
        }
        request["correction"] = {
            "rejectedOperation": "continueTenderReflection",
            "rejectedDraft": {
                "semanticOperation": "continueTenderReflection",
                "semanticEvidencePatch": {"memoryUpdate": {}},
                "responseFocus": "形成一个有限的理解",
            },
            "reason": "projectionInvalid",
            "payloadFailure": None,
            "projectionFailure": "tenderEvidenceMissing",
            "issue": {
                "fieldPath": "semanticEvidencePatch.memoryUpdate.selfCriticismLink",
                "violation": "invalidValue",
                "requiredConditions": ["citeGroundedUserEvidence"],
            },
            "recoveryPolicy": "repairSameOperation",
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("REQUIRED LINEAGE REPAIR", prompt)
        self.assertIn("Swift attaches the current exact selfCriticalStatement", prompt)
        self.assertIn("Card mapping, emotion, blockage, outcome", prompt)
        self.assertIn("do not manufacture it", prompt)

    def test_existing_synthesis_is_negotiable_until_naturally_accepted(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "synthesizeDirectReflection",
            "proposePractice",
        ]
        request["semanticMemory"] = {
            "reflectionFrame": {
                "mode": "tender",
                "action": "synthesizeUnderstanding",
                "evidenceBasis": [
                    {"source": "episode", "content": "用户连续修改bug但问题继续增加"}
                ],
                "dimensions": ["mindfulness"],
                "reflectionDelta": "用户已经形成了完整的新理解方式",
                "fierceEvidence": None,
            },
        }
        request["reflectionMode"] = "synthesis"
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("Use only canonical link, Tender", planner_prompt)
        self.assertIn("one revisable delta", planner_prompt)
        self.assertIn("A committed Synthesis changes only for explicit correction/qualification", planner_prompt)
        self.assertIn("changes only for explicit correction/qualification", planner_prompt)
        self.assertIn("Natural acceptance, acknowledgment, or readiness chooses proposePractice immediately", planner_prompt)
        self.assertIn("require no action wording or second confirmation", planner_prompt)
        self.assertIn("one exact groundedRealityCandidates.id", planner_prompt)
        self.assertIn("exact groundedRealityCandidates.id as basis", planner_prompt)
        self.assertIn("owns protocol metadata", planner_prompt)

        directive = {
            "semanticOperation": "synthesizeDirectReflection",
            "responseFocus": "降低刚才结论的确定性",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "none"},
            "localAction": "none",
            "memoryUpdate": {
                "reflectionPhase": "synthesis",
                "reflectionFrame": request["semanticMemory"]["reflectionFrame"],
            },
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Ask only for acceptance, correction, or qualification", writer_prompt)
        self.assertIn("do not invite an Action in the same reply", writer_prompt)
        self.assertIn("Preserve uncertainty", writer_prompt)
        self.assertIn("never repeat or paraphrase the committed", writer_prompt)
        self.assertIn("Card is provenance only", writer_prompt)
        self.assertIn("Never quote or paraphrase the self-critical", writer_prompt)
        self.assertIn("states only the changed qualification", writer_prompt)
        self.assertIn("the real explanation is complexity", writer_prompt)
        self.assertIn("Do not add a question", writer_prompt)

    def test_synthesis_cannot_treat_an_action_idea_as_completed_reflection(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueTenderReflection",
            "synthesizeDirectReflection",
        ]
        request["semanticMemory"] = {
            "selfCriticalStatement": "我不适合科研",
            "reflectionFrame": {
                "mode": "tender",
                "action": "distinguishFactFromPrediction",
                "evidenceBasis": [
                    {"source": "episode", "content": "当前实验没有得到预期结果"}
                ],
                "dimensions": ["mindfulness"],
                "reflectionDelta": "当前结果不足以单独确定是否适合科研",
                "fierceEvidence": None,
            },
        }
        request["reflectionMode"] = "tender"
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("Use only canonical link, Tender", planner_prompt)
        self.assertIn("grounded/declined Fierce", planner_prompt)
        self.assertIn("Use synthesize only when no such part remains", planner_prompt)
        self.assertIn("confirmed context in one revisable delta", planner_prompt)
        self.assertIn("add no interpretation or action", planner_prompt)

        directive = {
            "semanticOperation": "synthesizeDirectReflection",
            "responseFocus": "用户想到一个新办法，把它包装成已经完成的新认知",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "none"},
            "localAction": "none",
            "memoryUpdate": {
                "reflectionFrame": request["semanticMemory"]["reflectionFrame"],
            },
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("committed reality–self-criticism relation", writer_prompt)
        self.assertIn("canonical Tender distinction", writer_prompt)
        self.assertIn("Add Fierce only when", writer_prompt)
        self.assertIn("Keep every Card object, scene, relation", writer_prompt)
        self.assertIn("Card is provenance only", writer_prompt)
        self.assertIn("positive opposite, advice, or action", writer_prompt)
        self.assertIn("real explanation is complexity", writer_prompt)
        self.assertIn("normal difficulty", writer_prompt)
        self.assertIn("Avoid recap–progress–question templates", writer_prompt)
        self.assertIn("em-dash reveals", writer_prompt)

    def test_practice_writer_presents_one_negotiable_action(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "synthesizeDirectReflection",
            "proposePractice",
        ]
        request["semanticMemory"] = {}
        request["reflectionMode"] = "synthesis"
        directive = {
            "semanticOperation": "proposePractice",
            "responseFocus": "提出一个小而具体的行动",
            "sourceStage": "directReflection",
            "destinationStage": "optionalAction",
            "nextPrompt": {
                "kind": "confirmationRequest",
                "target": "practice",
                "referenceID": "practice-1",
            },
            "localAction": "none",
            "memoryUpdate": {
                "practiceTransition": {
                    "transactionID": "practice-1",
                    "narrativeReferenceID": None,
                    "proposal": {
                        "id": "practice-1",
                        "kind": "change",
                        "content": "先确认这个bug影响的流程范围",
                        "basis": "用户愿意从整体查看bug的具体影响",
                        "status": "pendingConfirmation",
                        "source": "assistantProposed",
                    },
                    "noActionReason": None,
                }
            },
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("exactly the one authorized small action", prompt)
        self.assertIn("Start directly with exactly the one authorized small action", prompt)
        self.assertIn("Do not repeat or paraphrase Tender, Synthesis", prompt)
        self.assertIn("continue the same accepted synthesis relationship", prompt)
        self.assertIn("The method may be a new assistant proposal", prompt)
        self.assertIn("target a confirmed difficulty, goal, behavior", prompt)
        self.assertIn("tentative small experiment rather than a known solution", prompt)
        self.assertIn("accept it, make it smaller or revise it", prompt)
        self.assertIn("decline it without pressure", prompt)
        self.assertIn("End with exactly one natural", prompt)
        self.assertIn("observable response in a concrete situation", prompt)
        self.assertIn("Prefer the episode's unresolved reality problem", prompt)
        self.assertIn("not writing, repeating, or rehearsing a kinder sentence", prompt)
        self.assertIn("missing a user-authored method is not a reason for noAction", prompt)

    def test_practice_acceptance_never_repeats_the_proposal(self) -> None:
        request = self.request()
        request["protocolStage"] = "optionalAction"
        request["allowedSemanticOperations"] = ["resolvePractice"]
        request["recentMessages"] = [
            {"role": "assistant", "content": "先看看手头安排再回复临时请求，可以吗？"},
            {"role": "user", "content": "可以"},
        ]
        directive = {
            "semanticOperation": "resolvePractice",
            "responseFocus": None,
            "sourceStage": "optionalAction",
            "destinationStage": "narrativeConfirmation",
            "nextPrompt": {"kind": "confirmationRequest", "target": "finalNarrative"},
            "localAction": "none",
            "memoryUpdate": {"finalNarrative": "额外任务挤压了原有安排；下次可以先确认时间再回复。"},
            "rewriteReason": None,
        }
        messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        )
        prompt = messages.system

        self.assertIn("never repeat the proposal", prompt)
        self.assertIn("move directly to the final narrative", prompt)
        self.assertIn("never as another proposal or negotiation", prompt)
        self.assertNotIn("先看看手头安排再回复临时请求", messages.user)
        self.assertIn('"content":"可以"', messages.user)

    def test_completion_writer_has_no_prior_action_or_second_task(self) -> None:
        request = self.request()
        request["protocolStage"] = "narrativeConfirmation"
        request["recentMessages"] = [
            {"role": "assistant", "content": "下次先确认时间再回复临时请求。"},
            {"role": "user", "content": "可以"},
        ]
        directive = {
            "semanticOperation": "completeConversation",
            "responseFocus": None,
            "sourceStage": "narrativeConfirmation",
            "destinationStage": "complete",
            "nextPrompt": {"kind": "none"},
            "localAction": "completeSession",
            "memoryUpdate": {},
            "rewriteReason": None,
        }
        messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=300,
                temperature=0.3,
            )
        )

        self.assertIn("one short, warm closing acknowledgment", messages.system)
        self.assertIn("Do not summarize the reflection", messages.system)
        self.assertIn("Do not add a question", messages.system)
        self.assertNotIn("下次先确认时间再回复临时请求", messages.user)

    def test_contextual_tracking_use_is_decided_by_planner_not_swift(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        request["semanticMemory"] = {
            "episodeStructure": {
                "concreteFacts": ["昨天排查问题时一直没有进展"],
                "eventProcess": ["连续处理后仍然卡住"],
                "behaviorEvidence": ["反复修改了几个地方"],
            },
            "cardRealityConnection": {
                "imageRelation": "user relation",
                "realityMapping": "user mapping",
                "source": "userAuthored",
                "status": "confirmed",
            },
        }
        request["reflectionMode"] = "exploratory"
        request["contextualTrackingProfiles"] = [
            {
                "profileID": "sleep",
                "domain": "sleep",
                "metrics": [
                    {
                        "metric": "sleepDuration",
                        "unit": "hours",
                        "recentDaily": [
                            {"date": "2026-08-07", "value": 6.0, "sampleCount": 4},
                            {"date": "2026-08-08", "value": 6.2, "sampleCount": 3},
                        ],
                        "recentMedian": 6.1,
                        "recentTotal": None,
                        "recentRecordCount": None,
                        "baselineMedian": 6.4,
                        "coverage": {
                            "recentObservedDays": 2,
                            "recentExpectedDays": 7,
                            "recentSampleCount": 7,
                            "baselineObservedDays": 10,
                            "baselineExpectedDays": 28,
                        },
                    }
                ],
            }
        ]
        messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        )
        prompt = messages.system

        self.assertIn(CURRENT_V5_CONTEXT_HYPOTHESIS_PATCH_SHAPE, prompt)
        self.assertIn("Compact temporal Tracking profiles contain cleaned daily aggregates", prompt)
        self.assertIn("When eventAnchorDate is present", prompt)
        self.assertIn("a different day elsewhere in the weekly window cannot make it qualify", prompt)
        self.assertIn("Lived evidence says what happened; Tracking does not compete with it", prompt)
        self.assertIn("concrete, non-redundant background condition", prompt)
        self.assertIn("Review the supplied profiles now on every unreviewed eligible exposure", prompt)
        self.assertIn("classify every supplied (profileID, metric) pair exactly once", prompt)
        self.assertIn("when any metric qualifies exactly one qualifying metric", prompt)
        self.assertIn("accidental omission remains pending", prompt)
        self.assertIn("timing overlaps or is adjacent to the episode", prompt)
        self.assertIn("coverage supports a real pattern rather than isolated noise", prompt)
        self.assertIn("adds one concrete contextual dimension", prompt)
        self.assertIn("without first inferring cause, psychology, ability, or responsibility", prompt)
        self.assertIn("No direct link to the event, Card connection", prompt)
        self.assertIn("Uncertainty about influence is a reason to let the person judge", prompt)
        self.assertIn("Use doesNotQualify only when timing does not match", prompt)
        self.assertIn("keeps the window open through Tender", prompt)
        self.assertIn("never makes Exploration incomplete or blocks Tender", prompt)
        self.assertIn("Evaluate concrete event-window evidence first", prompt)
        self.assertIn("same-day or adjacent recentDaily values", prompt)
        self.assertIn("supported recentDaily pattern across the described period", prompt)
        self.assertIn("baselineMedian only as secondary context", prompt)
        self.assertIn("neither baseline difference nor lack of a large baseline difference", prompt)
        self.assertIn("one of its metrics supplies a clear event-window condition", prompt)
        self.assertIn("stable sibling metrics", prompt)
        self.assertIn("missing observations stay unknown", prompt)
        self.assertIn("HRV is eligible", prompt)
        self.assertIn("optional, once-only event-context cue", prompt)
        self.assertIn("contextualTrackingDecision", prompt)
        self.assertIn("related, partly related, unrelated, or uncertain", prompt)
        self.assertIn("Only the person's resulting interpretation may enter later Reflection", prompt)
        self.assertIn("explicit relation, revision, rejection, or uncertainty", prompt)
        self.assertNotIn("episode and canonical Card–reality connection", prompt)
        self.assertNotIn("contextualLoadCue", messages.user)
        self.assertNotIn("contextualTrackingEvidence", messages.user)
        self.assertNotIn("dialogueHypothesis", messages.user)
        self.assertNotIn("dataQuality", messages.user)
        self.assertNotIn("patternStrength", messages.user)
        self.assertNotIn("Prefer direct lived patterns", prompt)
        self.assertNotIn("Baseline difference alone is insufficient", prompt)

        tender_request = json.loads(json.dumps(request, ensure_ascii=False))
        tender_request["reflectionMode"] = "tender"
        tender_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": tender_request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system
        self.assertIn("Review the supplied profiles now", tender_prompt)
        self.assertIn("must never delay Reflection progression", tender_prompt)
        self.assertIn("every preferred is false", tender_prompt)
        self.assertIn("Omission means unreviewed", tender_prompt)

        context_answer_request = json.loads(json.dumps(tender_request, ensure_ascii=False))
        context_answer_request["latestAnswerContext"] = {
            "kind": "openQuestion",
            "purpose": "contextRelationship",
            "focus": "assess_contextual_cue_relation",
        }
        context_answer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": context_answer_request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system
        self.assertIn("latest answer responds to the displayed contextual cue", context_answer_prompt)
        self.assertIn("atomically provide the first grounded Tender reflectionDelta", context_answer_prompt)
        self.assertIn("If Tender is already committed, do not revise it", context_answer_prompt)
        self.assertIn("never as the sole cause", context_answer_prompt)

    def test_contextual_tracking_writer_fuses_sources_without_exposing_tracking(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        request["semanticMemory"] = {}
        request["reflectionMode"] = "exploratory"
        request["contextualTrackingProfiles"] = [
            {
                "profileID": "sleep",
                "domain": "sleep",
                "metrics": [
                    {
                        "metric": "sleepDuration",
                        "unit": "hours",
                        "recentDaily": [
                            {"date": "2026-08-07", "value": 6.0, "sampleCount": 4},
                            {"date": "2026-08-08", "value": 6.2, "sampleCount": 3},
                        ],
                        "recentMedian": 6.1,
                        "baselineMedian": 6.4,
                        "coverage": {
                            "recentObservedDays": 2,
                            "recentExpectedDays": 7,
                            "recentSampleCount": 7,
                            "baselineObservedDays": 10,
                            "baselineExpectedDays": 28,
                        },
                    }
                ],
            }
        ]
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "形成一次可协商的情境假设",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "contextRelationship"},
            "localAction": "none",
            "memoryUpdate": {"contextCueOffered": True, "reflectionPhase": "tender"},
            "contextualTrackingMetricRef": {
                "profileID": "sleep",
                "metric": "sleepDuration",
            },
            "contextualTrackingMetricEvidence": {
                "metric": "sleepDuration",
                "unit": "hours",
                "recentDaily": [
                    {"date": "2026-08-08", "value": 6.2, "sampleCount": 3}
                ],
                "recentMedian": 6.2,
                "baselineMedian": 6.4,
                "coverage": {
                    "recentObservedDays": 1,
                    "recentExpectedDays": 1,
                    "recentSampleCount": 3,
                    "baselineObservedDays": 10,
                    "baselineExpectedDays": 28,
                },
            },
            "rewriteReason": None,
        }
        messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        )
        prompt = messages.system

        self.assertIn("warm, observant, everyday Chinese", prompt)
        self.assertIn("thoughtful companion noticing part of the person's lived context", prompt)
        self.assertIn("Compose it freshly for this turn in three moves", prompt)
        self.assertIn("personal-relative life pattern", prompt)
        self.assertIn("sleeping a little less or more than usual", prompt)
        self.assertIn("going to sleep later or earlier than usual", prompt)
        self.assertIn("the daily rhythm shifting later or earlier", prompt)
        self.assertIn("sleep being less or more continuous", prompt)
        self.assertIn("everyday activity being lower or higher", prompt)
        self.assertIn("days feeling fuller, lighter, or more fragmented", prompt)
        self.assertIn("having less or more uninterrupted time", prompt)
        self.assertIn("commitments following one another more tightly", prompt)
        self.assertIn("scheduled demands extending further into the evening", prompt)
        self.assertIn("recent body state has differed from the person's usual pattern", prompt)
        self.assertIn("person's own concrete activity, object, or situation", prompt)
        self.assertIn("rather than substituting a generic work problem", prompt)
        self.assertIn("Vary the opening, rhythm, and sentence structure", prompt)
        self.assertIn("Keep the measurement work backstage", prompt)
        self.assertIn("without an answer menu, disclaimer, second reflection question", prompt)
        self.assertIn('"metric":"sleepDuration"', prompt)
        self.assertIn("This contextual question is the whole visible reply", prompt)
        self.assertNotIn("already-authorized first bounded Tender understanding", prompt)
        self.assertNotIn("2026-08-07", messages.user)
        self.assertIn("2026-08-08", messages.user)

        tender_directive = dict(directive)
        tender_directive["semanticOperation"] = "continueTenderReflection"
        tender_directive["nextPrompt"] = {
            "kind": "openQuestion",
            "purpose": "contextRelationship",
        }
        tender_messages = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": tender_directive},
                maxTokens=500,
                temperature=0.3,
            )
        )
        self.assertIn("warm, observant, everyday Chinese", tender_messages.system)
        self.assertIn(
            "This turn realizes the independent contextual cue only",
            tender_messages.system,
        )

    def test_exploratory_writer_does_not_interpret_or_reframe(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "让用户选择接下来先改变哪一种处理方法",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "exploratoryReflection"},
            "localAction": "none",
            "memoryUpdate": {"reflectionPhase": "exploratory"},
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("projective frame only to help them discover", prompt)
        self.assertIn("Do not fill a missing relation", prompt)
        self.assertIn("one easy neutral question", prompt)
        self.assertIn("exact self-critical statement", prompt)
        self.assertIn("Do not reopen Card meaning", prompt)
        self.assertIn("seek complete causes", prompt)
        self.assertIn("troubleshoot, or ask about action", prompt)
        self.assertIn("operation contract outranks it", prompt)
        self.assertIn("do not rephrase it", prompt)
        self.assertIn("Honor corrections at their exact scope", prompt)

    def test_exploration_does_not_turn_an_attempt_into_the_cause_of_self_criticism(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["allowedSemanticOperations"] = [
            "continueExploratoryReflection",
            "continueTenderReflection",
        ]
        request["reflectionMode"] = "exploratory"
        request["semanticMemory"] = {
            "selfCriticalStatement": "我不适合开发",
            "selfCriticismStatus": "present",
        }
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("no cause or trigger precision", planner_prompt)
        self.assertIn("Cumulative, gradual, situational", planner_prompt)
        self.assertIn("Greater specificity is not greater reflective value", planner_prompt)
        self.assertIn("Continue Exploration only when the relation is absent", planner_prompt)
        self.assertIn("Tracking review should accompany the first eligible act", planner_prompt)
        self.assertIn("memoryUpdate contains the aligned link and no Tender reflectionFrame", planner_prompt)
        self.assertIn("next Planner act forms the first bounded Tender understanding", planner_prompt)

        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "询问去求助和搜索如何让用户更觉得自己不适合开发",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {"kind": "openQuestion", "purpose": "exploratoryReflection"},
            "localAction": "none",
            "memoryUpdate": {"reflectionPhase": "exploratory"},
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("Keep attempts separate from their effectiveness", writer_prompt)
        self.assertIn("Never use a causal-presupposing question", writer_prompt)
        self.assertIn("whether the judgment happened because of that fact", writer_prompt)
        self.assertIn("Never word an isolated action as causing self-criticism", writer_prompt)
        self.assertIn("ignore any responseFocus that does so", writer_prompt)
        self.assertIn("Never convert a cumulative pattern into a demand for one moment", writer_prompt)
        self.assertIn("do not default to onset precision", writer_prompt)
        self.assertIn("preserve that correction as the relationship", writer_prompt)

    def test_completed_exploration_writer_defers_first_tender_understanding(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "exploratory"
        request["allowedSemanticOperations"] = ["continueExploratoryReflection"]
        request["recentMessages"] = [
            {
                "id": "00000000-0000-0000-0000-000000000101",
                "role": "user",
                "content": (
                    "如果能力够的话，应该怎么样都至少能推进一些进度，"
                    "而不是卡在这里，代码乱了更急，急了之后更乱。"
                ),
                "replyToMessageID": None,
            }
        ]
        request["semanticMemory"] = {
            "selfCriticalStatement": "是不是自己的能力不够，从而导致代码一直跑不了",
        }
        directive = {
            "semanticOperation": "continueExploratoryReflection",
            "responseFocus": "承接已经形成的现实困难与较大自我判断之间的关系",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {
                "kind": "openQuestion",
                "purpose": "tenderReflection",
                "focus": "offer_bounded_tender_understanding_for_response",
            },
            "localAction": "none",
            "memoryUpdate": {
                "reflectionPhase": "tender",
                "selfCriticismLink": (
                    "bug改完一个又冒一个，事情推不下去 -> "
                    "是不是自己的能力不够，从而导致代码一直跑不了"
                ),
            },
            "rewriteReason": None,
        }
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("projected phase is Tender", prompt)
        self.assertIn("Briefly carry forward only the grounded", prompt)
        self.assertIn("invite the person to continue", prompt)
        self.assertIn("do not state a Tender distinction yet", prompt)
        self.assertNotIn("already-authorized first bounded Tender understanding", prompt)
        self.assertNotIn("Express that exact semantic proposition", prompt)

    def test_tender_contract_rejects_inquiry_frames_and_nonrevision_replies(self) -> None:
        request = self.request()
        request["protocolStage"] = "directReflection"
        request["reflectionMode"] = "tender"
        request["allowedSemanticOperations"] = [
            "continueTenderReflection",
            "continueTenderGroundedFierceReflection",
            "synthesizeDirectReflection",
        ]
        request["recentMessages"] = [
            {
                "id": "00000000-0000-0000-0000-000000000102",
                "role": "user",
                "content": "想不到什么",
                "replyToMessageID": None,
            }
        ]
        request["semanticMemory"] = {
            "selfCriticalStatement": "是不是自己的能力不够，从而导致代码一直跑不了",
            "selfCriticismLink": (
                "bug改完一个又冒一个，事情推不下去 -> "
                "是不是自己的能力不够，从而导致代码一直跑不了"
            ),
            "reflectionFrame": {
                "mode": "tender",
                "action": "softenGlobalSelfJudgment",
                "evidenceBasis": [
                    {
                        "source": "episode",
                        "content": "bug反复出现，进度无法推进",
                    }
                ],
                "dimensions": ["mindfulness"],
                "reflectionDelta": "除了能力判断之外，还有什么压力或感受？",
                "fierceEvidence": None,
            },
        }
        planner_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("Its reflectionDelta is declarative, never a request for new material", planner_prompt)
        self.assertIn("Extra detail, distress, uncertainty", planner_prompt)
        self.assertIn("'不知道/想不到'", planner_prompt)
        self.assertIn("is not a revision", planner_prompt)

        directive = {
            "semanticOperation": "continueTenderReflection",
            "responseFocus": "这种压力下，你会怎么安顿自己？",
            "sourceStage": "directReflection",
            "destinationStage": "directReflection",
            "nextPrompt": {
                "kind": "openQuestion",
                "purpose": "tenderReflection",
                "focus": "respond_to_or_revise_bounded_tender_understanding",
            },
            "localAction": "none",
            "memoryUpdate": {
                "reflectionPhase": "tender",
                "reflectionFrame": request["semanticMemory"]["reflectionFrame"],
            },
            "rewriteReason": None,
        }
        writer_prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="writer",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request, "directive": directive},
                maxTokens=500,
                temperature=0.3,
            )
        ).system

        self.assertIn("content is declarative, never a request for new material", writer_prompt)
        self.assertIn("ignore its inquiry", writer_prompt)
        self.assertIn("还有什么压力或感受", writer_prompt)
        self.assertIn("你会怎么安顿自己", writer_prompt)
        self.assertIn("collect no new evidence", writer_prompt)


if __name__ == "__main__":
    unittest.main()
