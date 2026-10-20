from __future__ import annotations

import json
import unittest

from app.prompt_registry import (
    CURRENT_V5_CARD_EVIDENCE_PATCH_SHAPE,
    CURRENT_V5_CORE_PROMPT_VERSION,
    CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE,
    CURRENT_V5_PLANNER_JSON_SHAPE,
    TURN_PROMPT_VERSION,
    build_turn_messages,
)
from app.schemas import LLMTurnPromptIn


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
            "contextualLoadCue": None,
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
            {"semanticOperation", "semanticEvidencePatch", "responseFocus"},
        )
        self.assertNotIn("requestedStage", shape)
        self.assertNotIn("replyIntent", shape)
        self.assertNotIn("nextPrompt", shape)
        self.assertNotIn("localAction", shape)
        self.assertIn("CURRENT V5 TURN REQUEST JSON:", prompt.user)

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
        episode_shape = event_shape["episodeStructure"]
        self.assertEqual(
            set(episode_shape),
            {
                "concreteFacts",
                "eventProcessStatus",
                "eventProcess",
                "behaviorEvidenceStatus",
                "behaviorEvidence",
            },
        )
        self.assertIn(CURRENT_V5_EVENT_EPISODE_PATCH_SHAPE, event_prompt)
        self.assertIn("Swift accumulates", event_prompt)
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
        self.assertIn("REFLECTION STRUCTURE", card_prompt)
        self.assertIn("reflectionFrame=", card_prompt)
        self.assertIn("minimal but complete spontaneous narrative", card_prompt)
        self.assertIn("relationOrAction says how the main user-described elements", card_prompt)
        self.assertIn("anticipatedChangeOrChoice says how that situation may continue", card_prompt)
        self.assertIn("functional judgment, never a keyword", card_prompt)
        self.assertIn("do not repeat inviteRealityConnection", card_prompt)
        self.assertNotIn("OPTIONAL ACTION STRUCTURE", card_prompt)

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

        self.assertIn("current disclosed experience or reflection focus", prompt)
        self.assertIn("Do not ask another image-only question", prompt)
        self.assertIn("Do not repeat or paraphrase", prompt)

    def test_user_authored_connection_receives_complete_tender_frame_contract(self) -> None:
        request = self.request()
        request["protocolStage"] = "cardReflection"
        request["allowedSemanticOperations"] = ["establishUserAuthoredCardConnection"]
        prompt = build_turn_messages(
            LLMTurnPromptIn(
                promptTask="planner",
                promptVersion=CURRENT_V5_CORE_PROMPT_VERSION,
                payload={"request": request},
                maxTokens=900,
                temperature=0.2,
            )
        ).system

        self.assertIn("userAuthoredConnection", prompt)
        self.assertIn('"mode":"tender|fierce"', prompt)
        self.assertIn('"evidenceBasis"', prompt)
        self.assertIn('"dimensions"', prompt)
        self.assertIn('"reflectionDelta"', prompt)
        self.assertIn("same turn can continue visibly", prompt)


if __name__ == "__main__":
    unittest.main()
