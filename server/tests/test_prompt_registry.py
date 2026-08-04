from __future__ import annotations

import unittest
from pathlib import Path

from fastapi import HTTPException

from app.prompt_registry import (
    TURN_PROMPT_VERSION,
    build_turn_messages,
    turn_prompt_chat,
)
from app.schemas import LLMTurnPromptIn


def request_payload(*, condition: str = "cardMediated") -> dict:
    return {
        "trigger": "userMessage",
        "protocolStage": "contextualDisclosure",
        "condition": condition,
        "permissions": {
            "currentStage": "contextualDisclosure",
            "allowedStages": [
                "contextualDisclosure",
                "cardConsent",
            ],
            "allowedActions": ["none"],
            "allowedReplyIntents": [
                "exploreContext",
                "inviteCardConsent",
            ],
            "allowedDisclosurePurposes": [
                "identifyConcreteEpisode",
                "clarifyBehavior",
                "clarifyEventProcess",
            ],
            "allowedDisclosureTargets": [
                "focalEvent",
                "behavior",
                "eventProcess",
            ],
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


def item(task: str, payload: dict) -> LLMTurnPromptIn:
    return LLMTurnPromptIn(
        promptTask=task,
        promptVersion=TURN_PROMPT_VERSION,
        payload=payload,
        maxTokens=700,
        temperature=0.2,
    )


def plan() -> dict:
    return {
        "requestedStage": "contextualDisclosure",
        "localAction": {"kind": "none", "trackingCueIDs": []},
        "memoryUpdate": {},
        "resolvedConfirmation": None,
        "nextPrompt": {
            "kind": "openQuestion",
            "purpose": "uncertainty_clarified",
            "focus": "one unresolved semantic relation",
            "disclosurePurpose": "clarifyEventProcess",
            "disclosureTarget": "eventProcess",
            "disclosureReopenReason": None,
            "target": None,
            "referenceID": None,
        },
        "replyIntent": "exploreContext",
        "noActionReason": None,
        "replyGuidance": "clarify one unresolved semantic relation",
    }


class PromptRegistryTests(unittest.TestCase):
    def test_planner_prompt_is_server_owned_and_domain_neutral(self) -> None:
        prompt = build_turn_messages(item("planner", {"request": request_payload()}))
        self.assertIn("private semantic TurnPlanner", prompt.system)
        self.assertIn("CURRENT PERMISSIONS", prompt.system)
        self.assertIn("CURRENT SEMANTIC CONTRACT", prompt.system)
        self.assertIn("episodeStructure", prompt.system)
        self.assertIn("Apply your patch to stored memory before choosing nextPrompt", prompt.system)
        self.assertIn("never reopens present/mixed evidence", prompt.system)
        self.assertIn("behaviorEvidenceStatus", prompt.system)
        self.assertIn("eventProcessStatus", prompt.system)
        self.assertIn("eventProcessStatus records development, not proven cause", prompt.system)
        self.assertIn("selfCriticismLink", prompt.system)
        self.assertIn("eventDisclosureOutcome", prompt.system)
        self.assertIn("disclosurePurpose", prompt.system)
        self.assertIn("clarifyEventProcess→eventProcess", prompt.system)
        self.assertIn("readyForTenderOrCard", prompt.system)
        self.assertIn("impactStatus", prompt.system)
        self.assertIn("are not gates", prompt.system)
        self.assertNotIn("reflectionFocusKind", prompt.system)
        self.assertNotIn("reflection focus", prompt.system.lower())
        self.assertIn("received-and-complete purpose", prompt.system)
        self.assertIn("contextRelationship", prompt.system)
        self.assertIn("rejected material cannot return", prompt.system)
        self.assertIn("Question functions are typed, not lexical", prompt.system)
        self.assertIn("Do not require a fixed number of turns", prompt.system)
        self.assertIn("Intentional choice, practical capacity", prompt.system)
        self.assertIn("Never omit a supplied relation", prompt.system)
        self.assertIn("An observed reaction proves no one's judgment", prompt.system)
        self.assertIn("cardInterpretiveTension is optional", prompt.system)
        self.assertIn(
            "Tender wording is optional and never creates another stage",
            prompt.system,
        )
        self.assertIn("uses inviteCardConsent in the same visible reply", prompt.system)
        self.assertIn("Once these three episode relations are present", prompt.system)
        self.assertIn("REPAIR CONTRACT", prompt.system)
        self.assertIn("forbiddenOperations", prompt.system)
        self.assertIn('"recentMessages"', prompt.user)
        self.assertNotIn("systemPrompt", prompt.user)

        critic = build_turn_messages(
            item("plan_critic", {"request": request_payload(), "plan": plan()})
        )
        self.assertIn("condition bridge before one concrete", critic.system)
        self.assertNotIn("reflection focus", critic.system.lower())

        chat = turn_prompt_chat(item("planner", {"request": request_payload()}))
        self.assertEqual(chat.agentMode, "fast")
        self.assertEqual(len(chat.messages), 2)

    def test_registry_builds_all_current_turn_roles(self) -> None:
        request = request_payload()
        candidate_plan = plan()
        draft = {"realizedIntent": "exploreContext", "reply": "一段候选回复"}
        critique = {
            "verdict": "reviseWriter",
            "reasonCodes": ["unnatural_chinese"],
            "revisionGuidance": "use natural spoken Chinese",
        }
        cases = {
            "planner": {"request": request},
            "plan_critic": {"request": request, "plan": candidate_plan},
            "writer": {"request": request, "plan": candidate_plan},
            "writer_critic": {
                "request": request,
                "plan": candidate_plan,
                "draft": draft,
            },
            "writer_revision": {
                "request": request,
                "plan": candidate_plan,
                "draft": draft,
                "critique": critique,
            },
        }
        for task, payload in cases.items():
            with self.subTest(task=task):
                prompt = build_turn_messages(item(task, payload))
                self.assertTrue(prompt.system)
                self.assertTrue(prompt.user)

    def test_writer_critic_uses_semantic_context_and_targeted_rewrite_rules(self) -> None:
        request = request_payload()
        prompt = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": plan(),
                    "draft": {
                        "realizedIntent": "exploreContext",
                        "reply": "一段候选回复",
                    },
                },
            )
        )

        self.assertIn("unreported subjective state", prompt.system)
        self.assertIn("not tokens,\nprefixes, or a closed phrase list", prompt.system)
        self.assertIn("paraphrase, synonym, indirect implication, or novel wording", prompt.system)
        self.assertIn("unsupported_positive_trait_reframe", prompt.system)
        self.assertIn("unsupported_contextual_inference", prompt.system)
        self.assertIn("premature_card_identity", prompt.system)
        self.assertIn("repeated generic acknowledgement openings", prompt.system)
        self.assertIn("abstract controllable, decidable, or limiting parts", prompt.system)
        self.assertIn("Do not propose new", prompt.system)
        self.assertIn("psychological content or a different next topic", prompt.system)
        self.assertIn("premature_transition_invitation", prompt.system)
        self.assertIn("without first acknowledging, summarizing", build_turn_messages(
            item("writer", {"request": request, "plan": plan()})
        ).system)
        self.assertIn("disclosure_reporting_preface", prompt.system)
        self.assertIn("disclosure_scope_violation", prompt.system)
        self.assertIn("一张随机反思卡", prompt.system)
        self.assertIn("Swift has not selected the card yet", prompt.system)
        self.assertIn("card title", prompt.system)
        self.assertIn("card_visual_overcollection", prompt.system)
        self.assertIn("likely to happen or change next", prompt.system)
        self.assertIn("content-forward question", prompt.system)
        self.assertIn("evaluate the assistant's\noutput", prompt.system)
        self.assertIn("TURN REQUEST JSON", prompt.user)
        self.assertIn("WRITER DRAFT JSON", prompt.user)

    def test_writer_is_surface_only_and_balances_compassion_with_accountability(self) -> None:
        prompt = build_turn_messages(
            item("writer", {"request": request_payload(), "plan": plan()})
        )
        critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request_payload(),
                    "plan": plan(),
                    "draft": {
                        "realizedIntent": "exploreContext",
                        "reply": "一段候选回复",
                    },
                },
            )
        )

        self.assertIn("surface realization only", prompt.system)
        self.assertIn("question presence/count", prompt.system)
        self.assertIn("fair self-compassion without naming its", prompt.system)
        self.assertIn("specific act or result from a whole-person judgment", prompt.system)
        self.assertIn(
            "protective purpose requires user evidence", prompt.system
        )
        self.assertIn("must never erase, justify, or\nexcuse", prompt.system)
        self.assertIn("An episode recap only organizes\nexisting content", prompt.system)
        self.assertIn(
            "generic\nreassurance, praise, normalization, minimization, or excuse",
            critic.system,
        )
        self.assertIn("workflow-field drift", critic.system)
        self.assertIn("protective\npurpose asserted without user evidence", critic.system)

    def test_disclosure_can_bridge_directly_to_optional_card_without_optional_metadata(self) -> None:
        request = request_payload()
        invitation = plan()
        invitation["requestedStage"] = "cardConsent"
        invitation["replyIntent"] = "inviteCardConsent"
        invitation["memoryUpdate"] = {
            "episodeStructure": {
                "concreteFacts": ["a concrete event"],
                "behaviorEvidenceStatus": "present",
                "behaviorEvidence": ["the person's participation"],
                "eventProcessStatus": "present",
                "possibleContributors": [],
                "contextualConstraints": [],
                "controllableParts": [],
                "impactStatus": "unresolved",
                "impacts": [],
                "keyUncertainty": None,
            },
        }
        invitation["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardConsent",
            "referenceID": None,
        }

        writer = build_turn_messages(
            item("writer", {"request": request, "plan": invitation})
        )
        critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": invitation,
                    "draft": {
                        "realizedIntent": "inviteCardConsent",
                        "reply": "一段候选回复",
                    },
                },
            )
        )

        self.assertIn("The event story is coherent", writer.system)
        self.assertIn("brief, restrained bridge", writer.system)
        self.assertIn("一张随机反思卡", writer.system)
        self.assertIn("directly from contextualDisclosure", critic.system)
        self.assertIn("event-versus-whole-person distinction", critic.system)
        self.assertIn("additional introspection", critic.system)
        self.assertIn("deliberate choice without user", writer.system)

    def test_direct_card_bridge_may_hold_one_supported_whole_person_distinction(self) -> None:
        request = request_payload()
        request["semanticMemory"] = {
            "selfCriticismStatus": "present",
            "selfCriticalStatement": "a user-authored whole-person verdict",
        }
        invitation = plan()
        invitation["requestedStage"] = "cardConsent"
        invitation["replyIntent"] = "inviteCardConsent"
        invitation["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardConsent",
            "referenceID": None,
        }

        writer = build_turn_messages(
            item("writer", {"request": request, "plan": invitation})
        )

        self.assertIn("whole-self verdict", writer.system)
        self.assertIn("preserve conduct and impact", writer.system)
        self.assertIn("only question is the optional card-consent question", writer.system)

    def test_v36_disclosure_contract_uses_only_current_core_as_gate(self) -> None:
        prompt = build_turn_messages(item("planner", {"request": request_payload()}))

        self.assertEqual(TURN_PROMPT_VERSION, "turn-v4-server-v36")
        for field in (
            "receivedDisclosureQuestionPurposes",
            "eventDisclosureOutcome",
            "disclosurePurpose",
            "disclosureReopenReason",
        ):
            with self.subTest(field=field):
                self.assertIn(field, prompt.system)
        self.assertIn("impactStatus", prompt.system)
        self.assertIn("are not gates", prompt.system)
        self.assertIn("identifyConcreteEpisode→focalEvent", prompt.system)
        self.assertIn("clarifyBehavior→behavior", prompt.system)
        self.assertIn("clarifyEventProcess→eventProcess", prompt.system)
        for retired in (
            "clarifyImmediateOutcome",
            "clarifyReflectionFocus",
            "reflectionFocusKind",
            "tenderGroundingKind",
        ):
            with self.subTest(retired=retired):
                self.assertNotIn(retired, prompt.system)
        self.assertIn("userCorrectedPreviousFact", prompt.system)
        self.assertIn("userWithdrewPreviousAnswer", prompt.system)
        self.assertIn("newContradictionDetected", prompt.system)

    def test_v36_plan_critic_audits_disclosure_and_bridge_semantics(self) -> None:
        critic = build_turn_messages(
            item(
                "plan_critic",
                {"request": request_payload(), "plan": plan()},
            )
        )

        for code in (
            "episode_structure_misclassified",
            "unsupported_memory_inference",
            "unsupported_decision_premise",
            "unsupported_stop_awareness_premise",
            "negated_premise_reused",
            "unnecessary_event_detail",
            "manufactured_global_self_judgment",
            "unsupported_tender_reframe",
            "consequence_minimized",
            "global_judgment_not_distinguished",
            "unnecessary_tender_confirmation",
        ):
            with self.subTest(code=code):
                self.assertIn(code, critic.system)

    def test_specific_concern_does_not_gain_a_whole_person_distinction(self) -> None:
        request = request_payload()
        request["semanticMemory"] = {
            "selfCriticismStatus": "present",
            "selfCriticalStatement": "a specific concern",
        }
        invitation = plan()
        invitation["requestedStage"] = "cardConsent"
        invitation["replyIntent"] = "inviteCardConsent"
        invitation["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosurePurpose": None,
            "disclosureTarget": None,
            "disclosureReopenReason": None,
            "target": "cardConsent",
            "referenceID": None,
        }

        writer = build_turn_messages(
            item("writer", {"request": request, "plan": invitation})
        )

        self.assertIn("one confirmed fact", writer.system)
        self.assertIn("Only when the person's own messages", writer.system)
        self.assertIn("only question is the optional card-consent question", writer.system)

    def test_failed_card_connection_uses_scaffold_then_optional_candidate(self) -> None:
        request = request_payload()
        request["protocolStage"] = "cardReflection"
        request["permissions"] = {
            "currentStage": "cardReflection",
            "allowedStages": ["cardReflection", "directReflection"],
            "allowedActions": ["none"],
            "allowedReplyIntents": [
                "developCardImage",
                "inviteCardConnection",
                "directCandidReflection",
            ],
            "allowedOperations": [],
        }
        request["semanticMemory"] = {
            "cardImageRelation": "one user-authored image relation"
        }
        request["card"] = {
            "imageIsDisplayed": True,
            "imageDevelopmentTurnCount": 1,
            "connectionAttemptCount": 1,
            "connectionScaffoldUsed": False,
            "connectionUnavailable": False,
            "realityAnchor": {
                "concreteFacts": ["当前焦点事件"],
                "eventProcess": ["用户在该事件中的处理过程"],
                "impacts": ["该事件已经产生的结果"],
            },
            "visualScaffolds": [],
            "reflectionApproaches": None,
            "prohibitedClaims": [],
        }

        planner = build_turn_messages(item("planner", {"request": request}))
        plan_critic = build_turn_messages(
            item("plan_critic", {"request": request, "plan": plan()})
        )
        scaffold_plan = plan()
        scaffold_plan["requestedStage"] = "cardReflection"
        scaffold_plan["replyIntent"] = "developCardImage"
        scaffold_plan["nextPrompt"]["disclosureTarget"] = None
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": scaffold_plan})
        )
        writer_critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": scaffold_plan,
                    "draft": {
                        "realizedIntent": "developCardImage",
                        "reply": "一个待检查的连接问题。",
                    },
                },
            )
        )

        self.assertIn("Inability is not refusal", planner.system)
        self.assertIn("request.card.realityAnchor is the only", planner.system)
        for issue in (
            "generic_life_example_search",
            "connection_left_current_episode",
            "reality_anchor_not_used",
            "image_relation_not_compared_with_focal_episode",
        ):
            self.assertIn(issue, plan_critic.system)
            self.assertIn(issue, writer_critic.system)
        self.assertIn("image relation and a confirmed event action/process/result", planner.system)
        self.assertIn("Before guidance it cannot infer", planner.system)
        self.assertIn("one permitted scaffold pairing", plan_critic.system)
        self.assertIn("has not yet found a life connection", writer.system)
        self.assertIn("authoritative current-event boundary", writer.system)
        self.assertIn("recap the event", writer.system)
        self.assertIn("Ask one easy open question", writer.system)

        request["card"]["connectionScaffoldUsed"] = True
        candidate_plan = dict(scaffold_plan)
        candidate_plan["replyIntent"] = "inviteCardConnection"
        candidate_writer = build_turn_messages(
            item("writer", {"request": request, "plan": candidate_plan})
        )
        self.assertIn("Offer exactly one tentative candidate", candidate_writer.system)
        self.assertIn("develop, redirect, or decline", candidate_writer.system)
        self.assertIn("Do not convert an image role or action", candidate_writer.system)
        self.assertIn("reflectionApproaches is unavailable", candidate_writer.system)
        self.assertIn("never request or introduce a different life episode", candidate_writer.system)
        self.assertIn("Do not save or speak as if", candidate_writer.system)

        candidate_critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": candidate_plan,
                    "draft": {
                        "realizedIntent": "inviteCardConnection",
                        "reply": "one candidate reply",
                    },
                },
            )
        )
        self.assertIn("same two observable sides", candidate_critic.system)
        self.assertIn("does not authorize claiming that the person", candidate_critic.system)

    def test_card_invitation_cannot_invent_a_title_before_local_draw(self) -> None:
        request = request_payload()
        invitation = plan()
        invitation["replyIntent"] = "inviteCardConsent"
        invitation["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardConsent",
            "referenceID": None,
        }

        prompt = build_turn_messages(
            item("writer", {"request": request, "plan": invitation})
        )

        self.assertIn("一张随机反思卡", prompt.system)
        self.assertIn("Before local selection", prompt.system)
        self.assertIn("invent or preview no title", prompt.system)

    def test_condition_contracts_remain_separate(self) -> None:
        card = build_turn_messages(item("planner", {"request": request_payload()}))
        direct = build_turn_messages(
            item("planner", {"request": request_payload(condition="modelAsserted")})
        )
        self.assertIn("Condition=cardMediated", card.system)
        self.assertIn("Condition=modelAsserted", direct.system)
        self.assertIn("Never mention cards or images", direct.system)

    def test_card_consent_contract_uses_silent_swift_owned_draw(self) -> None:
        request = request_payload()
        request["protocolStage"] = "cardConsent"
        request["permissions"] = {
            "currentStage": "cardConsent",
            "allowedStages": ["cardConsent"],
            "allowedActions": ["none", "drawRandomCard"],
            "allowedReplyIntents": [
                "acknowledgeCardConsent",
                "acknowledgeCardDecline",
            ],
            "allowedOperations": [
                {
                    "requestedStage": "cardConsent",
                    "replyIntent": "acknowledgeCardConsent",
                    "localAction": "drawRandomCard",
                },
                {
                    "requestedStage": "cardConsent",
                    "replyIntent": "acknowledgeCardDecline",
                    "localAction": "none",
                },
            ],
        }

        prompt = build_turn_messages(item("planner", {"request": request}))

        self.assertIn("resolvedConfirmation=cardConsent/accepted", prompt.system)
        self.assertIn("localAction.kind=drawRandomCard", prompt.system)
        self.assertIn("This authorization is silent", prompt.system)

    def test_card_reading_negotiation_is_implicit_and_content_forward(self) -> None:
        request = request_payload()
        request["protocolStage"] = "cardReflection"
        request["permissions"] = {
            "currentStage": "cardReflection",
            "allowedStages": ["cardReflection"],
            "allowedActions": ["none"],
            "allowedReplyIntents": ["presentCardReading"],
            "allowedOperations": [
                {
                    "requestedStage": "cardReflection",
                    "replyIntent": "presentCardReading",
                    "localAction": "none",
                }
            ],
        }
        reading = plan()
        reading["requestedStage"] = "cardReflection"
        reading["replyIntent"] = "presentCardReading"
        reading["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardMapping",
            "referenceID": "mapping-reference",
        }

        planner = build_turn_messages(item("planner", {"request": request}))
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": reading})
        )
        critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": reading,
                    "draft": {
                        "realizedIntent": "presentCardReading",
                        "reply": "一段候选解读",
                    },
                },
            )
        )

        self.assertIn("internal, not visible approval checks", planner.system)
        self.assertIn("without\napproval words", planner.system)
        self.assertIn("Natural substantive", planner.system)
        self.assertIn("concrete retrospective", writer.system)
        self.assertIn("not ask the person to judge the reading's fit", writer.system)
        self.assertIn("merely paraphrases the person's mapping", critic.system)
        self.assertIn("develop or redirect the connection", critic.system)
        self.assertIn(
            "Never ask the\nperson to rate, approve, verify, or edit",
            writer.system,
        )
        self.assertIn("For presentFinalNarrative", critic.system)
        self.assertIn("genuine card-consent or practice-choice", critic.system)
        self.assertIn("do not complete a causal chain", planner.system)
        self.assertIn("without completing its cause, lesson, or required change", writer.system)
        self.assertIn("completes a causal\nchain, lesson", critic.system)

    def test_card_reference_relations_are_semantically_selected_only_after_mapping(self) -> None:
        request = request_payload()
        request["protocolStage"] = "cardReflection"
        request["permissions"] = {
            "currentStage": "cardReflection",
            "allowedStages": ["cardReflection"],
            "allowedActions": ["none"],
            "allowedReplyIntents": ["presentCardReading"],
            "allowedOperations": [
                {
                    "requestedStage": "cardReflection",
                    "replyIntent": "presentCardReading",
                    "localAction": "none",
                }
            ],
        }
        request["semanticMemory"] = {
            "cardRealityConnection": {
                "imageRelation": "用户自己形成的一条画面关系",
                "realityMapping": "用户自己确认或修订的现实连接",
                "source": "userAuthored",
                "status": "confirmed",
            }
        }
        request["card"] = {
            "imageIsDisplayed": True,
            "imageDevelopmentTurnCount": 2,
            "connectionAttemptCount": 1,
            "connectionScaffoldUsed": False,
            "connectionUnavailable": False,
            "visualScaffolds": [],
            "reflectionApproaches": {"tender": "system tender", "fierce": "system fierce"},
            "referenceGuidance": {
                "relations": [
                    "开始行动与继续准备之间的关系",
                    "进入未知与保留退路之间的关系",
                ],
                "activationBoundary": "仅在完整用户证据共同支持时使用",
                "prohibitedClaims": ["不能直接解释为用户害怕开始"],
            },
            "prohibitedClaims": [],
        }
        reading = plan()
        reading["requestedStage"] = "cardReflection"
        reading["replyIntent"] = "presentCardReading"
        reading["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardMapping",
            "referenceID": "mapping-reference",
        }
        reading["cardReferenceSelection"] = {"relationIndex": 0}

        planner = build_turn_messages(item("planner", {"request": request}))
        plan_critic = build_turn_messages(
            item("plan_critic", {"request": request, "plan": reading})
        )
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": reading})
        )
        writer_critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": reading,
                    "draft": {
                        "realizedIntent": "presentCardReading",
                        "reply": "一段候选回复",
                    },
                },
            )
        )

        self.assertIn("cardReferenceSelection", planner.system)
        self.assertIn("Judge all evidence", planner.system)
        self.assertIn("never keywords or phrase matching", planner.system)
        self.assertIn("index is zero-based", planner.system)
        self.assertIn("lacks joint support", plan_critic.system)
        self.assertIn("copied into semantic memory", plan_critic.system)
        self.assertIn("silent lens", writer.system)
        self.assertIn("do not quote the reference as a conclusion", writer.system)
        self.assertIn("associated activationBoundary", writer_critic.system)
        self.assertIn("When the selection is null", writer_critic.system)

    def test_context_cue_is_post_mapping_optional_and_never_silently_confirmed(
        self,
    ) -> None:
        request = request_payload()
        request["protocolStage"] = "cardReflection"
        request["contextualLoadCue"] = {
            "hypothesis": "一条测量值已清理后的描述性背景线索",
            "confidence": "moderate",
            "relevance": "notReviewed",
            "usageBoundary": "只能在用户建立现实连接后暂定并置",
        }
        request["semanticMemory"] = {
            "cardRealityConnection": {
                "imageRelation": "用户形成的画面关系",
                "realityMapping": "用户形成的现实连接",
                "source": "userAuthored",
                "status": "confirmed",
            }
        }
        reading = plan()
        reading["requestedStage"] = "cardReflection"
        reading["replyIntent"] = "presentCardReading"
        reading["memoryUpdate"] = {
            "contextCueOffered": True,
            "cardNegotiatedMeaning": "一段候选连接",
        }
        reading["nextPrompt"] = {
            "kind": "confirmationRequest",
            "purpose": None,
            "focus": None,
            "disclosureTarget": None,
            "target": "cardMapping",
            "referenceID": None,
        }

        planner = build_turn_messages(item("planner", {"request": request}))
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": reading})
        )

        self.assertIn("Only after a confirmed\ncardRealityConnection", planner.system)
        self.assertIn("Silence means offered only", planner.system)
        self.assertIn("contextCueOffered=true exactly when", planner.system)
        self.assertIn("include the supplied contextualLoadCue", writer.system)
        self.assertIn("tentative descriptive background", writer.system)
        self.assertIn("Silence never confirms it", writer.system)

    def test_card_reality_connection_contract_is_atomic_and_swift_derives_guidance(self) -> None:
        request = request_payload()
        request["protocolStage"] = "cardReflection"
        planner = build_turn_messages(item("planner", {"request": request}))
        critic = build_turn_messages(
            item("plan_critic", {"request": request, "plan": plan()})
        )

        self.assertIn('"cardRealityConnection":null', planner.system)
        self.assertIn('"pendingCardRealityConnection":null', planner.system)
        self.assertIn('"cardConnectionOutcome":null', planner.system)
        self.assertNotIn('"cardImageRelation":null', planner.system)
        self.assertNotIn('"cardRealityMapping":null', planner.system)
        self.assertNotIn('"cardRealityMappingSource":null', planner.system)
        self.assertIn("Canonical/pending connections are complete or null", planner.system)
        self.assertIn("Swift then derives silent guidance", planner.system)
        self.assertIn("cardImageRelation/cardRealityMapping/cardRealityMappingSource", planner.system)
        self.assertIn("forbidden even when null", planner.system)
        self.assertIn("confirmed value is immutable", planner.system)
        self.assertIn("cardRealityConnection|cardMapping", planner.system)
        for issue in (
            "user_connection_not_committed",
            "incomplete_connection_patch",
            "card_mapping_not_used",
            "connection_source_without_content",
            "legacy_card_connection_patch_not_allowed",
        ):
            with self.subTest(issue=issue):
                self.assertIn(issue, critic.system)

    def test_final_action_is_one_system_proposed_small_step_not_a_menu(self) -> None:
        planner = build_turn_messages(
            item("planner", {"request": request_payload()})
        )

        self.assertIn("propose exactly one", planner.system)
        self.assertIn("care, repair, protect, or change practice", planner.system)
        self.assertIn("The system proposes it", planner.system)
        self.assertIn("Never provide a menu", planner.system)

    def test_post_card_candid_reflection_distinguishes_event_parts_without_replaying_disclosure(
        self,
    ) -> None:
        request = request_payload()
        request["protocolStage"] = "directReflection"
        request["permissions"] = {
            "currentStage": "directReflection",
            "allowedStages": ["directReflection", "narrativeConfirmation"],
            "allowedActions": ["none"],
            "allowedReplyIntents": [
                "directCandidReflection",
                "presentFinalNarrative",
            ],
            "allowedOperations": [
                {
                    "requestedStage": "directReflection",
                    "replyIntent": "directCandidReflection",
                    "localAction": "none",
                },
                {
                    "requestedStage": "narrativeConfirmation",
                    "replyIntent": "presentFinalNarrative",
                    "localAction": "none",
                },
            ],
        }
        request["semanticMemory"] = {
            "situationUnderstanding": "已建立的现实理解",
            "cardNegotiatedMeaning": "用户形成的图像与现实连接",
        }
        request["recentMessages"] = [
            {"role": "user", "content": "用户指出其中一个具体处理确实没有做好"}
        ]
        candid = plan()
        candid["requestedStage"] = "directReflection"
        candid["replyIntent"] = "directCandidReflection"
        candid["nextPrompt"] = {
            "kind": "openQuestion",
            "purpose": "fierce_event_boundary",
            "focus": "事件内可理解部分与需要面对的具体部分",
            "disclosureTarget": None,
            "target": None,
            "referenceID": None,
        }

        planner = build_turn_messages(item("planner", {"request": request}))
        plan_critic = build_turn_messages(
            item("plan_critic", {"request": request, "plan": candid})
        )
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": candid})
        )
        writer_critic = build_turn_messages(
            item(
                "writer_critic",
                {
                    "request": request,
                    "plan": candid,
                    "draft": {
                        "realizedIntent": "directCandidReflection",
                        "reply": "一段候选回复",
                    },
                },
            )
        )

        self.assertIn("Tender has already addressed whole-person self-criticism", planner.system)
        self.assertIn("what experience or constraint merits understanding", planner.system)
        self.assertIn("what supported action, omission, impact, boundary, or choice", planner.system)
        self.assertIn("instead of redirecting to a benign purpose", planner.system)
        self.assertIn("Do not ask for a future solution", planner.system)
        self.assertIn("post-card candid reflection repeats the Tender/global-self", plan_critic.system)
        self.assertIn("Tender is already established", writer.system)
        self.assertIn("Follow a latest correction about mishandling", writer.system)
        self.assertIn("Do not request future action", writer.system)
        self.assertIn("For directCandidReflection", writer_critic.system)
        self.assertIn("rather\nthan dissolve it into a benign motive", writer_critic.system)
        self.assertIn("another global-self rating", writer_critic.system)
        self.assertIn("accountability_correction_ignored", writer_critic.system)
        self.assertIn("uncertainty_overridden", writer_critic.system)

    def test_runtime_prompts_have_no_scenario_template(self) -> None:
        request = request_payload()
        candidate_plan = plan()
        draft = {"realizedIntent": "exploreContext", "reply": "一段候选回复"}
        prompts = [
            build_turn_messages(item("planner", {"request": request})).system,
            build_turn_messages(
                item("plan_critic", {"request": request, "plan": candidate_plan})
            ).system,
            build_turn_messages(
                item("writer", {"request": request, "plan": candidate_plan})
            ).system,
            build_turn_messages(
                item(
                    "writer_critic",
                    {"request": request, "plan": candidate_plan, "draft": draft},
                )
            ).system,
        ]
        runtime = "\n".join(prompts).lower()
        for scenario_phrase in (
            "拖延",
            "procrastination",
            "论文",
            "投稿",
            "重要任务",
            "lower-priority",
            "phone use",
            "园丁",
            "木栏",
            "事情比较多",
            "很忙",
            "waiting for motivation",
            "finding the right direction",
            "我昨天没有按时提交项目方案",
            "我觉得自己什么事情都做不好",
            "我答应帮同事整理材料，后来忘了",
            "伴侣追问我为什么没提前告诉他一件事",
            "最近工作特别糟",
        ):
            with self.subTest(scenario_phrase=scenario_phrase):
                self.assertNotIn(scenario_phrase, runtime)

    def test_production_sources_do_not_embed_acceptance_scenarios(self) -> None:
        root = Path(__file__).resolve().parents[2]
        production_paths = (
            root / "server/app/prompt_registry.py",
            root / "BeyondComfort/Services/ReflectionProtocolController.swift",
            root / "BeyondComfort/Services/LLMTurnController.swift",
            root / "BeyondComfort/ViewModels/ReflectionViewModel.swift",
        )
        production = "\n".join(
            path.read_text(encoding="utf-8")
            for path in production_paths
            if path.exists()
        )
        self.assertTrue(production)
        for sentence in (
            "我昨天没有按时提交项目方案",
            "我觉得自己什么事情都做不好",
            "我答应帮同事整理材料，后来忘了",
            "伴侣追问我为什么没提前告诉他一件事",
            "最近工作特别糟",
        ):
            with self.subTest(sentence=sentence):
                self.assertNotIn(sentence, production)

    def test_current_swift_path_has_no_phrase_list_semantic_quality_detectors(self) -> None:
        root = Path(__file__).resolve().parents[2]
        swift_paths = {
            "controller": root / "BeyondComfort/Services/ReflectionProtocolController.swift",
            "turn_controller": root / "BeyondComfort/Services/LLMTurnController.swift",
            "control": root / "BeyondComfort/Services/LLMService.swift",
            "view_model": root / "BeyondComfort/ViewModels/ReflectionViewModel.swift",
        }
        if not all(path.exists() for path in swift_paths.values()):
            self.skipTest("Swift source guards run only from a complete application checkout")
        controller = swift_paths["controller"].read_text(encoding="utf-8")
        turn_controller = swift_paths["turn_controller"].read_text(encoding="utf-8")
        control = swift_paths["control"].read_text(encoding="utf-8")
        view_model = swift_paths["view_model"].read_text(encoding="utf-8")
        current_path = "\n".join((controller, turn_controller, view_model))
        for removed_detector in (
            "beginsWithDisclosureReportingPreface",
            "containsUnsupportedTenderTraitReframe",
            "containsAbstractContextualBodyMetaphor",
            "containsUnsupportedContextualBusyClaim",
            "containsPrematureCardIdentity",
            "AssistantApprovalLanguageDetector",
            "claimFamilies",
            "busyClaims",
            "sanitizedProtocolReply",
            "premature_card_identity_removed_locally",
        ):
            with self.subTest(detector=removed_detector):
                self.assertNotIn(removed_detector, current_path)
        self.assertNotIn("conditionLeakageMarkers", control)
        self.assertNotIn("overclaimMarkers", control)

    def test_current_prompts_are_bounded_and_not_layered(self) -> None:
        request = request_payload()
        planner = build_turn_messages(item("planner", {"request": request}))
        writer = build_turn_messages(
            item("writer", {"request": request, "plan": plan()})
        )
        self.assertLess(len(planner.system), 13000)
        self.assertLess(len(writer.system), 5000)
        self.assertNotIn("PINNED TURN", planner.system)
        self.assertNotIn("historical protocol", planner.system)

    def test_old_and_unknown_versions_are_rejected(self) -> None:
        for version in (
            "turn-v4-server-v32",
            "turn-v4-server-v30",
            "turn-v4-server-v28",
            "turn-v4-server-v29",
            "turn-v4-server-v27",
            "turn-v4-server-v26",
            "turn-v4-server-v25",
            "turn-v4-server-v24",
            "turn-v4-server-v23",
            "turn-v4-server-v22",
            "turn-v4-server-v21",
            "turn-v4-server-v20",
            "turn-v4-server-v19",
            "turn-v4-server-v18",
            "turn-v4-server-v17",
            "turn-v4-server-v16",
            "turn-v4-server-v15",
            "turn-v4-server-v14",
            "turn-v4-server-v13",
            "turn-v4-server-v12",
            "turn-v4-server-v11",
            "turn-v4-server-v8",
            "turn-v4-server-v9",
            "turn-v4-server-v10",
            "turn-v4-server-v7",
            "turn-v4-server-v6",
            "turn-v4-server-v5",
            "turn-v4-server-v4",
            "turn-v4-server-v3",
            "turn-v4-server-v2",
            "turn-v4-server-v1",
            "turn-v3-server-v4",
            "turn-v3-server-v3",
            "turn-v3-server-v2",
            "turn-v3-server-v1",
            "unknown",
        ):
            with self.subTest(version=version):
                unsupported = item(
                    "planner", {"request": request_payload()}
                ).model_copy(update={"promptVersion": version})
                with self.assertRaises(HTTPException) as raised:
                    build_turn_messages(unsupported)
                self.assertEqual(raised.exception.status_code, 409)

    def test_missing_typed_object_is_rejected(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            build_turn_messages(item("writer", {"request": request_payload()}))
        self.assertEqual(raised.exception.status_code, 422)


if __name__ == "__main__":
    unittest.main()
