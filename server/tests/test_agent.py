from __future__ import annotations

import asyncio
import json
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from fastapi import HTTPException

from app.agent import (
    CRITIC_PROMPT,
    DIALOGUE_FINAL_OUTPUT_CONTRACT,
    DIALOGUE_RUNTIME_PHASE_STYLE,
    DIALOGUE_STYLE_OVERRIDE,
    PLANNER_PROMPT,
    TURN_PLANNER_FINAL_OUTPUT_CONTRACT,
    TURN_PLANNER_RUNTIME_STYLE,
    TURN_WRITER_RUNTIME_STYLE,
    complete_json,
)
from app.providers import Completion, ProviderError, ProviderGateway
from app.schemas import LLMChatIn


def request() -> LLMChatIn:
    return LLMChatIn(
        messages=[
            {"role": "system", "content": "Return JSON: {\"answer\":\"\"}"},
            {"role": "user", "content": "我今天很累"},
        ],
        maxTokens=200,
        temperature=0.2,
        agentMode="deep",
    )


class AgentTests(unittest.IsolatedAsyncioTestCase):
    def test_coarse_turn_runtime_supports_contextual_tracking_card_reading_and_drafted_practice(
        self,
    ) -> None:
        self.assertIn("one sufficiently clear reality story", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("do not each require a separate question", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("One user answer may complete several functions", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("effect of that effect", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("trackingCandidates is empty", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("contextualLoadCue is the only tracking-derived", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("one tentative clause", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("never more than one", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("Never ask whether the contextual hypothesis itself fits", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("ask only whether the whole summary", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("accurate", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("Never use it", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("during cardConsent or cardReflection", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("never excuses a supported behavior", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("replace memoryUpdate.candidUnderstanding", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("one-question budget", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("card.connectionScaffoldUsed", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "Each reply should add only the function authorized",
            TURN_WRITER_RUNTIME_STYLE,
        )
        self.assertIn("one unfolding reality story", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("effect of an effect", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("keep it silent in ordinary disclosure questions", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("whole Tender summary", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("one tentative", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("never more than one", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("Do not create a tracking paragraph", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("the one visible", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("question checks the whole summary", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("Never mention measurements", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("must never excuse a supported", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("New sessions never open a tracking inquiry", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("one meaningful effect", TURN_PLANNER_RUNTIME_STYLE)
        for relevance in ("related", "partlyRelated", "unrelated", "uncertain"):
            self.assertIn(relevance, TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "resolvedConfirmation describes only what the latest user reply did",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("nextPrompt describes only the prompt", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "migration fields and must all be null",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "value means leave stored memory unchanged",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("practiceOptions replaces the pending choice set", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("tentative, modifiable reading", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "do not return to image development",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "substantive candidate reading in the same visible turn",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "After cardMapping is accepted, revised, or rejected, do not paraphrase",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "Each phase has one distinct function",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "must not ask the person to invent a",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("assistant—not the user—drafts", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("present the single structured", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn(
            "deliver the substantive reading now",
            TURN_WRITER_RUNTIME_STYLE,
        )
        self.assertIn("two- or three-sentence delta", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("one short anchoring clause", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("person to invent the action", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("recap the whole", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn("event_sequence_clarified", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("experienced_impact_clarified", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("A new label does not make an", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "not an exhaustive interview",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("emotional", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("synonym", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "merely because a card supplies new imagery",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "steps, coping, or a solution before narrative confirmation",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "Provide exactly one strongest complete care, repair, protect, or change",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "move directly to final narrative",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("private connectionGuidance may select", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("cardDisplayed and cardGuidanceAvailable", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("requestedStage=complete", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("practiceOptions", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("noActionReason", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("Never use noAction", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("filler reply", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("updates cardImageRelation, not cardRealityMapping", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("one final connection", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("one-time silent local action", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn("do not paraphrase the reading again", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "Accepting a candidate perspective does not establish",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "organize everything else around exactly one condition-appropriate distinction",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "cardMappingConfirmed boolean is",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn("only when cardMappingConfirmed is true", TURN_PLANNER_RUNTIME_STYLE)
        self.assertIn(
            "In modelAsserted, Tender is background and no card or image may appear",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "replyGuidance must name the single selected distinction",
            TURN_PLANNER_RUNTIME_STYLE,
        )
        self.assertIn(
            "In cardMediated, use only an accepted or",
            TURN_WRITER_RUNTIME_STYLE,
        )
        self.assertIn("application-owned cardMappingConfirmed value", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn(
            "In modelAsserted, do not mention cards or images",
            TURN_WRITER_RUNTIME_STYLE,
        )
        self.assertIn(
            "changes, narrows, corrects, or preserves uncertainty",
            TURN_WRITER_RUNTIME_STYLE,
        )
        self.assertIn("card speaks for, reveals", TURN_WRITER_RUNTIME_STYLE)
        self.assertIn('"noActionReason":null', TURN_PLANNER_FINAL_OUTPUT_CONTRACT)
        self.assertIn('"candidUnderstanding":null', TURN_PLANNER_FINAL_OUTPUT_CONTRACT)

    async def test_coarse_turn_planner_and_writer_are_separately_labeled(self) -> None:
        planner_item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": (
                        'Return {"requestedStage":"","localAction":{},'
                        '"memoryUpdate":{},"replyIntent":"","replyGuidance":""}'
                    ),
                },
                {"role": "user", "content": "private turn input"},
            ],
            maxTokens=300,
            temperature=0.2,
            agentMode="fast",
        )
        planner_result = Completion(
            (
                '{"requestedStage":"contextualDisclosure",'
                '"localAction":{"kind":"none","trackingCueIDs":[]},'
                '"memoryUpdate":{},"replyIntent":"exploreContext",'
                '"replyGuidance":"承接最新回答"}'
            ),
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(return_value=planner_result),
        ) as complete:
            await complete_json(planner_item)
        self.assertEqual(
            complete.await_args.kwargs["agent_task"],
            "turn_controller_planner",
        )
        self.assertEqual(complete.await_args.kwargs["role"], "writer")
        self.assertTrue(
            any(
                "INTERNAL TURN PLANNER STYLE" in message["content"]
                for message in complete.await_args.kwargs["messages"]
            )
        )

        writer_item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are the private Chinese dialogue Writer. "
                        'Return exactly {"realizedIntent":"","reply":""}'
                    ),
                },
                {"role": "user", "content": "VALIDATED SEMANTIC TURN PLAN JSON"},
            ],
            maxTokens=300,
            temperature=0.2,
            agentMode="fast",
        )
        writer_result = Completion(
            '{"realizedIntent":"exploreContext","reply":"我会沿着你刚才说的部分继续。"}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(return_value=writer_result),
        ) as complete:
            await complete_json(writer_item)
        self.assertEqual(
            complete.await_args.kwargs["agent_task"],
            "turn_controller_writer",
        )
        self.assertEqual(complete.await_args.kwargs["role"], "writer")
        self.assertTrue(
            any(
                "INTERNAL TURN WRITER STYLE" in message["content"]
                for message in complete.await_args.kwargs["messages"]
            )
        )

        critic_item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a private semantic quality Critic. "
                        'Return {"verdict":"pass","reasonCodes":[],'
                        '"revisionGuidance":null}'
                    ),
                },
                {"role": "user", "content": "validated plan and draft"},
            ],
            maxTokens=200,
            temperature=0,
            agentMode="fast",
        )
        critic_result = Completion(
            '{"verdict":"pass","reasonCodes":[],"revisionGuidance":null}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(return_value=critic_result),
        ) as complete:
            await complete_json(critic_item)
        self.assertEqual(
            complete.await_args.kwargs["agent_task"],
            "turn_controller_critic",
        )
        self.assertEqual(complete.await_args.kwargs["role"], "critic")

        plan_critic_item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a private semantic plan Critic. "
                        "Return exactly one JSON object: "
                        '{"verdict":"pass|revisePlanner","reasonCodes":[],'
                        '"revisionGuidance":null}'
                    ),
                },
                {"role": "user", "content": "turn request and candidate plan"},
            ],
            maxTokens=200,
            temperature=0,
            agentMode="fast",
        )
        plan_critic_result = Completion(
            '{"verdict":"pass","reasonCodes":[],"revisionGuidance":null}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(return_value=plan_critic_result),
        ) as complete:
            await complete_json(plan_critic_item)
        self.assertEqual(
            complete.await_args.kwargs["agent_task"],
            "turn_controller_plan_critic",
        )
        self.assertEqual(complete.await_args.kwargs["role"], "critic")

    async def test_fast_mode_calls_writer_only(self) -> None:
        item = request().model_copy(update={"agentMode": "fast"})
        result = Completion('{"answer":"我听见了。"}', "deepseek", "writer-model")
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)) as complete:
            content = await complete_json(item)
        self.assertEqual(json.loads(content), {"answer": "我听见了。"})
        self.assertEqual([call.kwargs["role"] for call in complete.await_args_list], ["writer"])
        self.assertEqual(complete.await_args.kwargs["agent_task"], "structured_completion")

    async def test_analyzer_request_is_labeled_without_logging_reflection_text(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": "You are the private ContextAnalyzer. Return JSON only.",
                },
                {"role": "user", "content": "一段不应进入日志的私人内容"},
            ],
            maxTokens=200,
            temperature=0.1,
            agentMode="fast",
        )
        result = Completion('{"recommendedRoute":"explore"}', "deepseek", "writer-model")
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)) as complete:
            await complete_json(item)
        self.assertEqual(complete.await_args.kwargs["agent_task"], "context_analyzer")
        self.assertIsNotNone(complete.await_args.kwargs["request_id"])

    async def test_balanced_mode_skips_critic(self) -> None:
        item = request().model_copy(update={"agentMode": "balanced"})
        results = [
            Completion('{"goal":"listen"}', "deepseek", "planner-model"),
            Completion('{"answer":"先说最想说的一点。"}', "deepseek", "writer-model"),
        ]
        with patch("app.agent.gateway.complete", new=AsyncMock(side_effect=results)) as complete:
            content = await complete_json(item)
        self.assertEqual(json.loads(content), {"answer": "先说最想说的一点。"})
        self.assertEqual(
            [call.kwargs["role"] for call in complete.await_args_list],
            ["planner", "writer"],
        )

    async def test_planner_failure_degrades_to_direct_writer(self) -> None:
        item = request().model_copy(update={"agentMode": "balanced"})
        results = [
            HTTPException(504, "timeout"),
            Completion('{"answer":"我先听你说。"}', "deepseek", "writer-model"),
        ]
        with patch("app.agent.gateway.complete", new=AsyncMock(side_effect=results)) as complete:
            content = await complete_json(item)
        self.assertEqual(json.loads(content), {"answer": "我先听你说。"})
        self.assertEqual(
            [call.kwargs["role"] for call in complete.await_args_list],
            ["planner", "writer"],
        )

    async def test_all_provider_failure_returns_context_contract_fallback(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"accepted":true,"readyForCard":false}',
                },
                {
                    "role": "user",
                    "content": (
                        "Accepted substantive disclosures before this answer: 0\n"
                        "Latest disclosure: 最近准备论文投稿很焦虑\n"
                        "Narrative so far:\n"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            content = await complete_json(item)
        decoded = json.loads(content)
        self.assertTrue(decoded["accepted"])
        self.assertEqual(decoded["event"], "最近准备论文投稿很焦虑")
        self.assertFalse(decoded["readyForCard"])

    async def test_all_provider_failure_returns_action_contract_fallback(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You support stage actionComposer. Return "
                        '{"reflectiveSummary":"","actionSuggestions":[]}'
                    ),
                },
                {"role": "user", "content": "我现在不知道该怎么办"},
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="deep",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            content = await complete_json(item)
        decoded = json.loads(content)
        self.assertEqual(len(decoded["actionSuggestions"]), 1)
        self.assertEqual(decoded["actionSuggestions"][0]["type"], "care")

    async def test_all_provider_failure_returns_new_analyzer_contract_fallback(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"safetyOverride":false,"recommendedRoute":"explore"}',
                },
                {"role": "user", "content": "Recent conversation: user disclosed a difficult event"},
            ],
            maxTokens=200,
            temperature=0.1,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["recommendedRoute"], "explore")
        self.assertEqual(decoded["consentToCandor"], "unknown")
        self.assertEqual(decoded["personalContributions"], [])

    async def test_all_provider_failure_returns_new_dialogue_contract_fallback(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: cardInterpretation. Do not change it.",
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="balanced",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["actionOptions"], [])
        self.assertIn("画面里正在发生什么", decoded["question"])
        self.assertNotIn("第一眼停在哪里", decoded["question"])

    async def test_direct_condition_fallback_uses_task_boundary_for_explicit_substitution(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: attributionReflection. Do not change it.\n"
                        "Workflow phase: candidAgency. DIRECT CONDITION: no card was drawn.\n"
                        "Recent conversation:\n"
                        "user: 我需要做实验结果分析，但一直在整理不重要的文件。"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertIn("稍后处理", decoded["question"])
        self.assertIn("10 分钟", decoded["question"])
        self.assertNotIn("懒", decoded["question"])

    async def test_tracking_fallback_returns_to_the_concrete_caregiving_reaction(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: trackingReview. Do not change it.\n"
                        "Recent conversation:\n"
                        "user: 最近一直在帮家里处理住院和报销，昨晚妈妈又问了一遍，我语气很冲。"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertIn("更难保持耐心", decoded["question"])
        self.assertIn("没有也可以", decoded["question"])
        self.assertNotIn("其中哪些", decoded["question"])

    async def test_direct_condition_action_fallback_is_change_not_generic_care(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: actionSelection. Do not change it.\n"
                        "DIRECT CONDITION: no card was drawn.\n"
                        "Recent conversation: user keeps整理不重要的文件 instead of实验结果分析。"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["actionOptions"][0]["category"], "change")
        self.assertIn("稍后处理", decoded["actionOptions"][0]["description"])

    async def test_dialogue_contract_bounds_provider_action_drafts_to_two(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: actionSelection. Do not change it.",
                },
            ],
            maxTokens=400,
            temperature=0.2,
            agentMode="fast",
        )
        options = [
            {
                "category": "change",
                "description": f"草案 {index}",
                "timing": None,
                "rationale": "可修改或拒绝",
            }
            for index in range(3)
        ]
        result = Completion(
            json.dumps(
                {"reflection": "", "question": "", "actionOptions": options},
                ensure_ascii=False,
            ),
            "deepseek",
            "writer-model",
        )
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(len(decoded["actionOptions"]), 2)
        self.assertEqual(decoded["actionOptions"][1]["description"], "草案 1")

    async def test_card_action_contract_keeps_care_repair_protect_or_change(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: actionSelection. Do not change it.",
                },
            ],
            maxTokens=400,
            temperature=0.2,
            agentMode="fast",
        )
        options = [
            {"category": "protect", "description": "先拒绝一次", "timing": None, "rationale": "边界"},
            {"category": "care", "description": "先停五分钟", "timing": None, "rationale": "小一步"},
            {"category": "repair", "description": "补发一条说明", "timing": None, "rationale": "小一步"},
        ]
        result = Completion(
            json.dumps({"reflection": "", "question": "", "actionOptions": options}, ensure_ascii=False),
            "deepseek",
            "writer-model",
        )
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)):
            decoded = json.loads(await complete_json(item))
        self.assertEqual([option["category"] for option in decoded["actionOptions"]], ["protect", "care"])

    async def test_dialogue_with_two_questions_is_rewritten_without_losing_context(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "我今天在组会上被导师批评了，感觉自己特别差。",
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        initial = Completion(
            json.dumps(
                {
                    "reflection": "被批评后一下觉得自己很差，确实会很难受。",
                    "question": "当时最让你难受的是什么？你最担心别人会怎么看你？",
                    "actionOptions": [],
                },
                ensure_ascii=False,
            ),
            "deepseek",
            "writer-model",
        )
        repaired = Completion(
            json.dumps(
                {
                    "reflection": "被批评后一下觉得自己很差，确实会很难受。",
                    "question": "当时最让你难受的是什么？",
                    "actionOptions": [],
                },
                ensure_ascii=False,
            ),
            "deepseek",
            "writer-model",
        )
        with patch("app.agent.gateway.complete", new=AsyncMock(side_effect=[initial, repaired])) as complete:
            decoded = json.loads(await complete_json(item))

        visible = decoded["reflection"] + decoded["question"]
        self.assertEqual(visible.count("？") + visible.count("?"), 1)
        self.assertIn("被批评", visible)
        self.assertNotIn("一直没开始", visible)
        self.assertEqual([call.kwargs["role"] for call in complete.await_args_list], ["writer", "writer"])
        self.assertTrue(
            any(
                "ONE-QUESTION REPAIR" in message["content"]
                for message in complete.await_args_list[-1].kwargs["messages"]
            )
        )
        self.assertEqual(
            complete.await_args_list[-1].kwargs["messages"][-1]["content"],
            DIALOGUE_FINAL_OUTPUT_CONTRACT,
        )

    async def test_failed_dialogue_question_rewrite_preserves_first_contextual_question(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {"role": "user", "content": "我今天在组会上被导师批评了。"},
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        initial = Completion(
            '{"reflection":"被批评后很难受。","question":"当时最让你难受的是什么？你最担心什么？","actionOptions":[]}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=[initial, HTTPException(502, "unavailable")]),
        ):
            decoded = json.loads(await complete_json(item))

        visible = decoded["reflection"] + decoded["question"]
        self.assertEqual(visible.count("？") + visible.count("?"), 1)
        self.assertIn("被批评", visible)
        self.assertEqual(decoded["question"], "当时最让你难受的是什么？")

    async def test_readiness_fallback_is_context_confirmation_not_card_menu(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: readinessCheck. Do not change it.",
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        visible = decoded["reflection"] + decoded["question"]
        self.assertIn("需要改一改", visible)
        self.assertNotIn("抽卡", visible)
        self.assertNotIn("图卡", visible)

    async def test_summary_fallback_waits_for_final_narrative_confirmation(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: summary. Do not change it.",
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertIn("需要改一改", decoded["question"])
        self.assertEqual(decoded["actionOptions"], [])

    async def test_dialogue_fallback_does_not_restart_with_generic_later_question(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": "Application-controlled state: emotionDisclosure. Do not change it.",
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertNotIn("后来发生了什么", decoded["question"])
        self.assertIn("怎么想", decoded["question"])

    async def test_dialogue_fallback_default_does_not_expose_internal_retry_rule(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: customDialogue. Do not change it.\n"
                        "Recent conversation:\n"
                        "user: 我还想说一会儿"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["question"], "你想接着说什么？")
        visible = decoded["reflection"] + decoded["question"]
        self.assertNotIn("不重复追问", visible)
        self.assertNotIn("最希望我理解", visible)

    async def test_dialogue_fallback_concretely_repairs_what_does_this_mean(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: contextDisclosure. Do not change it.\n"
                        "Recent conversation:\n"
                        "assistant: 那段时间，还有什么也在占用你的注意力或精力？\n"
                        "user: 这是什么意思？"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["reflection"], "我刚才问得不够清楚。")
        self.assertEqual(decoded["question"], "那段时间，除了这件事，你还在处理哪些具体事情？")
        self.assertNotIn("注意力", decoded["question"])
        self.assertNotIn("不重复追问", decoded["reflection"] + decoded["question"])
        self.assertNotIn("最希望我理解", decoded["reflection"] + decoded["question"])

    async def test_dialogue_fallback_stops_card_link_after_user_cannot_think_of_one(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: attributionReflection. Do not change it.\n"
                        "Recent conversation:\n"
                        "assistant: 这张图让你想到刚才那件事里的哪个时刻？\n"
                        "user: 想不到"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["question"], "")
        self.assertIn("不用勉强", decoded["reflection"])
        self.assertNotIn("哪个时刻", decoded["reflection"])
        self.assertEqual(decoded["actionOptions"], [])

    async def test_dialogue_fallback_uses_card_subphase_instead_of_repeating_observation(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: cardInterpretation. Do not change it.\n"
                        "Workflow phase: cardNarrativeDeepening.\n"
                        "Recent conversation:\n"
                        "assistant: 看到这张牌，你觉得画面里正在发生什么？\n"
                        "user: 一个人拿着玩具等小狗回来\n"
                        "assistant: 小狗为什么暂时不在这里？\n"
                        "user: 它可能受惊跑远了"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertIn("为什么", decoded["question"])
        self.assertNotIn("看到这张牌", decoded["question"])

    async def test_dialogue_fallback_does_not_reask_progress_after_no_more(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: contextDisclosure. Do not change it.\n"
                        "Recent conversation:\n"
                        "assistant: 是还没开始，还是已经开始但进展慢？\n"
                        "user: 还没开始\n"
                        "assistant: 还有别的吗？\n"
                        "user: 没有了"
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(side_effect=HTTPException(502, "unavailable")),
        ):
            decoded = json.loads(await complete_json(item))
        self.assertEqual(decoded["question"], "")
        self.assertIn("先放下", decoded["reflection"])
        self.assertNotIn("没开始", decoded["reflection"] + decoded["question"])
        self.assertNotIn("进展", decoded["reflection"] + decoded["question"])

    def test_planner_and_critic_prohibit_unsupported_psychological_claims(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT):
            self.assertIn("phone use", prompt)
            self.assertTrue("bodily" in prompt.lower() or "body" in prompt.lower())
            self.assertIn("card narrative", prompt)
            self.assertIn("duplicate", prompt.lower())
            self.assertIn("tracking", prompt.lower())

    def test_self_compassion_dimensions_are_global_generation_constraints(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("self-kindness", collapsed)
            self.assertIn("common humanity", collapsed)
            self.assertIn("mindfulness", collapsed)
            self.assertIn("across the whole conversation", collapsed)
            self.assertIn("final narrative only", collapsed)
        style = " ".join(DIALOGUE_STYLE_OVERRIDE.split())
        self.assertIn("很多人都会这样", style)
        self.assertIn("do not force them into every turn", style.lower())

    def test_card_rules_require_user_narrative_before_route_question(self) -> None:
        self.assertIn("Before the user's first card narrative", PLANNER_PROMPT)
        self.assertIn("route-specific card question", CRITIC_PROMPT)
        self.assertIn("set it aside", PLANNER_PROMPT)

    def test_planner_and_critic_forbid_second_person_restatement(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT):
            collapsed = " ".join(prompt.split())
            self.assertIn("in second person", collapsed)
            self.assertIn("paraphrase", collapsed.lower())

    def test_turn_order_gates_tracking_and_card_invitation(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("latest substantive assistant question", collapsed)
            self.assertIn("free-text user answer", collapsed)
        self.assertIn("UI event", PLANNER_PROMPT)
        self.assertIn("do not offer a draw-versus-talk menu", DIALOGUE_STYLE_OVERRIDE)
        self.assertIn("caller performs the local random draw", DIALOGUE_STYLE_OVERRIDE)

    def test_tracking_uses_one_measurement_free_context_hypothesis(self) -> None:
        planner = " ".join(PLANNER_PROMPT.split()).lower()
        critic = " ".join(CRITIC_PROMPT.split()).lower()
        style = " ".join(DIALOGUE_STYLE_OVERRIDE.split()).lower()
        self.assertIn("application-supplied measurement-free contextual-load hypothesis", planner)
        self.assertIn("personal-baseline comparisons", planner)
        self.assertIn("include it as one tentative clause", planner)
        self.assertIn("never more than one", planner)
        self.assertIn("never create a separate tracking turn", planner)
        self.assertIn("one accuracy question checks the whole understanding", planner)
        self.assertIn("single application-supplied measurement-free contextual-load hypothesis", critic)
        self.assertIn("whole correctable tender summary", critic)
        self.assertIn("reject any separate tracking turn", critic)
        self.assertIn("caller supplies one measurement-free contextual-load hypothesis", style)
        self.assertIn("do not ask whether it fits", style)
        self.assertIn("ordinary accuracy question is enough", style)
        for prompt in (planner, critic, style):
            self.assertIn("sleep", prompt)
            self.assertIn("heart rate", prompt)
            self.assertIn("hrv", prompt)
            self.assertIn("specific emotion", prompt)
            self.assertIn("responsibility", prompt)
        self.assertIn("stress score", planner)
        self.assertIn("detected stress level", critic)
        self.assertIn("detected stress level", style)

    def test_card_narrative_and_user_reply_are_required_before_action(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("coherent integrated narrative", collapsed)
            self.assertIn("user", collapsed)
            self.assertIn("action", collapsed)
        self.assertIn("later user response", PLANNER_PROMPT)
        self.assertIn("later user reply", DIALOGUE_STYLE_OVERRIDE)
        self.assertIn("empty action options", CRITIC_PROMPT)

    def test_fixed_phase_contract_orders_tender_tracking_and_context_confirmation(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("tender grounding", collapsed)
            self.assertIn("correctable tender summary", collapsed)
            self.assertIn("10–16 assistant turns", collapsed)
            self.assertIn("structured disclosure -> correctable tender summary", collapsed)
            self.assertIn("with at most one tentative", collapsed)
            self.assertIn("measurement-free contextual", collapsed)
        self.assertIn(
            "tender grounding must happen before any contextual clause",
            " ".join(PLANNER_PROMPT.split()).lower(),
        )
        self.assertIn(
            "tender grounding must happen before any contextual clause",
            " ".join(CRITIC_PROMPT.split()).lower(),
        )
        self.assertIn(
            "tender grounding must happen before any contextual clause",
            " ".join(DIALOGUE_STYLE_OVERRIDE.split()).lower(),
        )

    def test_card_image_story_uses_up_to_three_separate_questions(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("Card observation", collapsed)
            self.assertIn("at most THREE image-focused assistant questions", collapsed)
            self.assertIn("real life", collapsed)
        self.assertIn("image-only follow-up", CRITIC_PROMPT)
        self.assertIn("optional card-to-life connection is a later turn", DIALOGUE_STYLE_OVERRIDE)
        self.assertIn("open-ended", PLANNER_PROMPT)
        self.assertIn("open-ended", DIALOGUE_STYLE_OVERRIDE)
        self.assertIn("do not force a two-option interpretation", DIALOGUE_STYLE_OVERRIDE)

    def test_tender_grounding_forbids_structured_field_stitching(self) -> None:
        for prompt in (PLANNER_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("two or three connected spoken-Chinese sentences", collapsed)
            self.assertIn("你这次说到的是/感受包括/身体上的变化/这背后的担心", collapsed)

    def test_card_connection_requires_context_then_meaning_then_candid_user_answers(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            meaning_index = collapsed.index("meaning shift")
            tender_index = collapsed.index("tender circumstances")
            candid_index = collapsed.index("candid agency")
            self.assertLess(tender_index, meaning_index)
            self.assertLess(tender_index, candid_index)
            self.assertIn("user", collapsed)

    def test_disclosure_invites_one_skippable_nonclinical_body_turn_before_grounding(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("bodily", collapsed)
            self.assertIn("personal meaning", collapsed)
            self.assertIn("global", collapsed)
            self.assertIn("没有明显变化", collapsed)
            self.assertIn("body-sensation", collapsed)
        planner = " ".join(PLANNER_PROMPT.split()).lower()
        critic = " ".join(CRITIC_PROMPT.split()).lower()
        style = " ".join(DIALOGUE_STYLE_OVERRIDE.split()).lower()
        self.assertIn("caller may request one", planner)
        self.assertIn("repeated body question", critic)
        self.assertIn("exactly one non-clinical bodily-experience invitation", style)

    def test_card_circumstances_precede_meaning_shift_and_block_invented_symbols(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertLess(collapsed.index("tender circumstances"), collapsed.index("meaning shift"))
            self.assertIn("焦灼", collapsed)
            self.assertIn("反转", collapsed)
            self.assertIn("user", collapsed)
            self.assertIn("没有变化", collapsed)
            self.assertIn("did not change", collapsed)
            self.assertIn("重新理解", collapsed)
            self.assertIn("新看见", collapsed)
            self.assertIn("发生变化", collapsed)

    def test_narrative_decomposes_global_labels_without_erasing_confirmed_behavior(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("global", collapsed)
            self.assertIn("confirmed behavior", collapsed)
            self.assertTrue(
                "quote or repeat" in collapsed or "quotes or repeats" in collapsed
            )
            self.assertTrue(
                any(
                    phrase in collapsed
                    for phrase in (
                        "without erasing",
                        "without concealing",
                        "do not erase",
                        "not permission to erase",
                    )
                )
            )
            self.assertIn("没用", collapsed)

    def test_action_can_offer_one_or_two_low_burden_editable_drafts(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertTrue("one or two" in collapsed or "one concrete" in collapsed)
            self.assertIn("low-burden", collapsed)
            self.assertIn("decline", collapsed)
            self.assertIn("changed metric", collapsed)

    def test_action_is_optional_and_first_concrete_choice_needs_no_second_confirmation(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split()).lower()
            self.assertIn("coherent integrated narrative", collapsed)
            self.assertIn("action is optional", collapsed)
            self.assertIn("final narrative confirmation", collapsed)
            self.assertIn("complete", collapsed)
        self.assertIn("the application, never the model", " ".join(PLANNER_PROMPT.split()).lower())
        self.assertIn("first concrete action choice", CRITIC_PROMPT)
        self.assertIn("do not ask another", DIALOGUE_STYLE_OVERRIDE)

    def test_card_projection_vague_fit_and_divination_are_hard_blocked(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("有一些类似", collapsed)
            self.assertIn("预示", collapsed)
            self.assertIn("meaning shift", collapsed.lower())
        self.assertIn("image-only follow-up", PLANNER_PROMPT)
        self.assertIn("not a substantive connection", " ".join(CRITIC_PROMPT.split()))

    def test_visible_style_is_plain_warm_and_has_no_process_announcements(self) -> None:
        collapsed = " ".join(DIALOGUE_STYLE_OVERRIDE.split())
        self.assertIn("warm, plain, everyday Chinese", collapsed)
        self.assertIn("Be caring without inventing", collapsed)
        self.assertIn("Never announce", collapsed)
        self.assertIn("心里最沉的", collapsed)
        self.assertIn("值得被看见", collapsed)
        self.assertNotIn("那份疲惫值得被看见", collapsed)

    def test_repetition_boundary_and_forced_positivity_are_explicitly_blocked(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("问题重复", collapsed)
            self.assertIn("不清楚", collapsed)
            self.assertIn("带来一丝希望", collapsed)
        self.assertIn("太拖延", DIALOGUE_STYLE_OVERRIDE)
        self.assertIn("一直在做、但很难推进", DIALOGUE_STYLE_OVERRIDE)

    def test_clarification_boundary_and_procrastination_handoff_rules_are_explicit(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("这是什么意思", collapsed)
            self.assertIn("想不到", collapsed)
            self.assertIn("没有了", collapsed)
            self.assertIn("还没开始", collapsed)
            self.assertIn("进展慢", collapsed)
            self.assertIn("注意力", collapsed)
            self.assertIn("你现在最希望我理解的是哪一部分", collapsed)
        self.assertIn("SAME question", PLANNER_PROMPT)
        self.assertIn("clear stop signal", CRITIC_PROMPT)
        self.assertIn("An open context field is not evidence", DIALOGUE_STYLE_OVERRIDE)

    def test_greeting_and_stalled_progress_rules_stop_field_collection(self) -> None:
        for prompt in (PLANNER_PROMPT, CRITIC_PROMPT, DIALOGUE_STYLE_OVERRIDE):
            collapsed = " ".join(prompt.split())
            self.assertIn("hello/hi/你好", collapsed)
            self.assertIn("特别期待会有效", collapsed)
            self.assertIn("具体的调整过程或细节", collapsed)
            self.assertIn("拖延", collapsed)
            self.assertIn("有没有一个具体的地方让问题特别难以解开", collapsed)
            self.assertIn("技术指导", collapsed)
            self.assertIn("没看到卡片", collapsed)
            self.assertIn("local card image", collapsed)
        self.assertIn("both reflection and question fields", PLANNER_PROMPT)
        self.assertIn("combined reflection and question fields", CRITIC_PROMPT)
        self.assertIn("BOTH reflection and question fields", DIALOGUE_STYLE_OVERRIDE)

    async def test_dialogue_contract_injects_style_override_on_fast(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {"role": "user", "content": "项目负责人又让我加班，我还是答应了"},
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        result = Completion('{"reflection":"","question":"想先说哪一句？"}', "deepseek", "writer-model")
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)) as complete:
            await complete_json(item)
        messages = complete.await_args_list[0].kwargs["messages"]
        self.assertTrue(any("INTERNAL DIALOGUE STYLE" in m["content"] for m in messages))
        # Stage-scoped style is followed by the smallest possible final JSON contract.
        self.assertEqual(messages[-2]["role"], "system")
        self.assertIn("INTERNAL DIALOGUE STYLE", messages[-2]["content"])
        self.assertIn("do not parrot", messages[-2]["content"].lower())
        self.assertEqual(messages[-1]["role"], "system")
        self.assertEqual(messages[-1]["content"], DIALOGUE_FINAL_OUTPUT_CONTRACT)
        self.assertIn("exactly one valid json object", messages[-1]["content"].lower())

    async def test_dialogue_runtime_style_is_scoped_to_current_state(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {
                    "role": "user",
                    "content": (
                        "Application-controlled state: trackingReview. Do not change it.\n"
                        "Synthetic tracking context."
                    ),
                },
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="fast",
        )
        result = Completion(
            '{"reflection":"","question":"对得上吗？","actionOptions":[]}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete", new=AsyncMock(return_value=result)
        ) as complete:
            await complete_json(item)

        messages = complete.await_args_list[0].kwargs["messages"]
        runtime = messages[-2]["content"]
        self.assertIn(DIALOGUE_RUNTIME_PHASE_STYLE["trackingReview"], runtime)
        self.assertNotIn(DIALOGUE_RUNTIME_PHASE_STYLE["cardInterpretation"], runtime)
        self.assertNotIn("Examples (user says", runtime)
        self.assertLess(len(runtime), 3000)

    async def test_analyzer_contract_does_not_inject_style_override(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"safetyOverride":false,"recommendedRoute":"explore"}',
                },
                {"role": "user", "content": "我今天很累"},
            ],
            maxTokens=200,
            temperature=0.1,
            agentMode="fast",
        )
        result = Completion('{"recommendedRoute":"explore"}', "deepseek", "writer-model")
        with patch("app.agent.gateway.complete", new=AsyncMock(return_value=result)) as complete:
            await complete_json(item)
        messages = complete.await_args_list[0].kwargs["messages"]
        self.assertFalse(any("INTERNAL DIALOGUE STYLE" in m["content"] for m in messages))

    async def test_dialogue_style_override_injected_on_balanced_writer(self) -> None:
        item = LLMChatIn(
            messages=[
                {
                    "role": "system",
                    "content": 'Return {"reflection":"","question":"","actionOptions":[]}',
                },
                {"role": "user", "content": "我还是帮他改了"},
            ],
            maxTokens=200,
            temperature=0.2,
            agentMode="balanced",
        )
        results = [
            Completion('{"goal":"listen"}', "deepseek", "planner-model"),
            Completion('{"reflection":"","question":"改的时候想停过吗？"}', "deepseek", "writer-model"),
        ]
        with patch("app.agent.gateway.complete", new=AsyncMock(side_effect=results)) as complete:
            await complete_json(item)
        writer_messages = complete.await_args_list[1].kwargs["messages"]
        self.assertTrue(any("INTERNAL DIALOGUE STYLE" in m["content"] for m in writer_messages))

    async def test_planner_writer_critic_approved_path(self) -> None:
        results = [
            Completion('{"goal":"listen"}', "deepseek", "planner-model"),
            Completion('{"answer":"先停一下也可以。"}', "deepseek", "writer-model"),
            Completion('{"approved":true,"issues":[]}', "deepseek", "critic-model"),
        ]
        with patch("app.config.AGENT_CRITIC_ENABLED", True), \
            patch("app.agent.gateway.complete", new=AsyncMock(side_effect=results)) as complete:
            content = await complete_json(request())
        self.assertEqual(json.loads(content), {"answer": "先停一下也可以。"})
        self.assertEqual([call.kwargs["role"] for call in complete.await_args_list], ["planner", "writer", "critic"])
        self.assertEqual(
            [call.kwargs["agent_task"] for call in complete.await_args_list],
            ["reflection_planner", "dialogue_generation", "safety_critic"],
        )

    async def test_critic_rejection_triggers_one_writer_revision(self) -> None:
        results = [
            Completion('{"goal":"listen"}', "deepseek", "planner-model"),
            Completion('{"answer":"模板化回答"}', "deepseek", "writer-model"),
            Completion('{"approved":false,"issues":["回应最新细节"]}', "deepseek", "critic-model"),
            Completion('{"answer":"你说今天的疲惫已经很具体。"}', "deepseek", "writer-model"),
        ]
        with patch("app.config.AGENT_CRITIC_ENABLED", True), \
            patch("app.agent.gateway.complete", new=AsyncMock(side_effect=results)) as complete:
            content = await complete_json(request())
        self.assertEqual(json.loads(content), {"answer": "你说今天的疲惫已经很具体。"})
        self.assertEqual(
            [call.kwargs["role"] for call in complete.await_args_list],
            ["planner", "writer", "critic", "writer"],
        )
        revision_messages = complete.await_args_list[-1].kwargs["messages"]
        self.assertTrue(
            any("回应最新细节" in message["content"] for message in revision_messages)
        )
        self.assertTrue(
            any(
                "INTERNAL REVISION" in message["content"]
                for message in revision_messages
            )
        )


class ProviderFallbackTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.gateway = ProviderGateway()

    async def asyncTearDown(self) -> None:
        await self.gateway.aclose()

    async def test_gateway_reuses_one_owned_async_client_and_closes_it(self) -> None:
        response = httpx.Response(
            200,
            request=httpx.Request("POST", "https://provider.example/v1/chat"),
            json={"ok": True},
        )
        client = AsyncMock(spec=httpx.AsyncClient)
        client.is_closed = False
        client.post = AsyncMock(side_effect=[response, response])
        client.aclose = AsyncMock()
        gateway = ProviderGateway()

        with patch(
            "app.providers.httpx.AsyncClient",
            return_value=client,
        ) as client_factory:
            await asyncio.gather(gateway.startup(), gateway.startup())
            first = await gateway._post(
                provider="deepseek",
                url="https://provider.example/v1/chat",
                headers={"Authorization": "Bearer test"},
                payload={"message": "first"},
                timeout_seconds=5,
            )
            second = await gateway._post(
                provider="deepseek",
                url="https://provider.example/v1/chat",
                headers={"Authorization": "Bearer test"},
                payload={"message": "second"},
                timeout_seconds=5,
            )
            await gateway.aclose()

        self.assertIs(first, response)
        self.assertIs(second, response)
        client_factory.assert_called_once()
        self.assertEqual(client.post.await_count, 2)
        client.aclose.assert_awaited_once()
        self.assertIsNone(gateway._http_client)

    async def test_gateway_does_not_close_an_injected_async_client(self) -> None:
        client = AsyncMock(spec=httpx.AsyncClient)
        client.is_closed = False
        client.aclose = AsyncMock()
        gateway = ProviderGateway(http_client=client)

        await gateway.startup()
        await gateway.aclose()

        client.aclose.assert_not_awaited()
        self.assertIs(gateway._http_client, client)

    async def test_openai_responses_parses_output_text(self) -> None:
        response = type(
            "Response",
            (),
            {
                "status_code": 200,
                "json": lambda self: {
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {"type": "output_text", "text": '{"ok":true}'}
                            ],
                        }
                    ]
                },
            },
        )()
        with patch.object(
            ProviderGateway, "_post", new=AsyncMock(return_value=response)
        ) as post:
            content = await self.gateway._request_openai_responses(
                base_url="https://api.openai.com/v1",
                api_key="openai-key",
                model="gpt-5-mini",
                messages=[{"role": "user", "content": "Return JSON"}],
                max_tokens=100,
                reasoning_effort="low",
                timeout_seconds=25,
                require_json_object=True,
            )
        self.assertEqual(content, '{"ok":true}')
        payload = post.await_args.kwargs["payload"]
        self.assertEqual(payload["max_output_tokens"], 256)
        self.assertEqual(payload["reasoning"], {"effort": "low"})
        self.assertEqual(payload["text"], {"format": {"type": "json_object"}})
        self.assertFalse(payload["store"])

    async def test_openai_gpt4o_omits_reasoning_parameter(self) -> None:
        response = type(
            "Response",
            (),
            {
                "status_code": 200,
                "json": lambda self: {
                    "output": [
                        {
                            "type": "message",
                            "content": [
                                {"type": "output_text", "text": '{"ok":true}'}
                            ],
                        }
                    ]
                },
            },
        )()
        with patch.object(
            ProviderGateway, "_post", new=AsyncMock(return_value=response)
        ) as post:
            content = await self.gateway._request_openai_responses(
                base_url="https://api.openai.com/v1",
                api_key="openai-key",
                model="gpt-4o",
                messages=[{"role": "user", "content": "Return JSON"}],
                max_tokens=100,
                reasoning_effort="none",
                timeout_seconds=25,
                require_json_object=True,
            )
        self.assertEqual(content, '{"ok":true}')
        payload = post.await_args.kwargs["payload"]
        self.assertEqual(payload["model"], "gpt-4o")
        self.assertNotIn("reasoning", payload)
        self.assertEqual(payload["text"], {"format": {"type": "json_object"}})

    async def test_deepseek_success_does_not_call_openai(self) -> None:
        deepseek_result = Completion(
            '{"ok":true}',
            "deepseek",
            "deepseek-chat",
            finish_reason="stop",
            prompt_tokens=20,
            completion_tokens=5,
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.OPENAI_API_KEY", "openai-key"), \
            patch("app.config.OPENAI_BASE_URL", "https://api.openai.com/v1"), \
            patch("app.config.OPENAI_PLANNER_MODEL", "gpt-5-mini"), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(return_value=deepseek_result),
            ) as deepseek, \
            patch.object(self.gateway, "_complete_openai", new=AsyncMock()) as openai:
            result = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )
        self.assertEqual(result.provider, "deepseek")
        self.assertEqual(result.finish_reason, "stop")
        self.assertEqual(result.prompt_tokens, 20)
        self.assertEqual(result.completion_tokens, 5)
        deepseek.assert_awaited_once()
        openai.assert_not_awaited()

    async def test_invalid_dialogue_json_uses_short_deepseek_repair(self) -> None:
        plain_text = Completion(
            "这次失败很打击你。最担心它说明什么？",
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
            prompt_tokens=11206,
            completion_tokens=33,
        )
        repaired = Completion(
            (
                '{"reflection":"这次失败很打击你。",'
                '"question":"最担心它说明什么？","actionOptions":[]}'
            ),
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
            prompt_tokens=116,
            completion_tokens=42,
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_WRITER_MODEL", "deepseek-v4-pro"), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(return_value=plain_text),
            ), \
            patch.object(
                self.gateway,
                "_repair_deepseek_dialogue_json",
                new=AsyncMock(return_value=repaired),
            ) as repair:
            result = await self.gateway.complete(
                role="writer",
                agent_task="dialogue_generation",
                request_id="repair-request",
                messages=[],
                max_tokens=1000,
                temperature=0.32,
            )

        self.assertEqual(
            json.loads(result.content),
            {
                "reflection": "这次失败很打击你。",
                "question": "最担心它说明什么？",
                "actionOptions": [],
            },
        )
        repair.assert_awaited_once_with(
            draft=plain_text.content,
            model="deepseek-v4-pro",
            max_tokens=1000,
        )
        self.assertFalse(self.gateway._deepseek_circuit_open)
        self.assertEqual(len(self.gateway._deepseek_failure_times), 0)

    async def test_invalid_turn_writer_json_uses_schema_specific_repair(self) -> None:
        plain_text = Completion(
            "我会沿着你刚才说的部分继续。",
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
        )
        repaired = Completion(
            '{"realizedIntent":"exploreContext","reply":"我会沿着你刚才说的部分继续。"}',
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_WRITER_MODEL", "deepseek-v4-pro"), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(return_value=plain_text),
            ), \
            patch.object(
                self.gateway,
                "_repair_deepseek_turn_controller_json",
                new=AsyncMock(return_value=repaired),
            ) as repair:
            result = await self.gateway.complete(
                role="writer",
                agent_task="turn_controller_writer",
                request_id="turn-writer-repair",
                messages=[],
                max_tokens=700,
                temperature=0.42,
            )

        self.assertEqual(
            json.loads(result.content),
            {
                "realizedIntent": "exploreContext",
                "reply": "我会沿着你刚才说的部分继续。",
            },
        )
        repair.assert_awaited_once_with(
            draft=plain_text.content,
            original_messages=[],
            agent_task="turn_controller_writer",
            model="deepseek-v4-pro",
            max_tokens=700,
        )

    async def test_turn_planner_repair_prompt_requires_exact_memory_field_types(self) -> None:
        repaired = Completion(
            (
                '{"requestedStage":"contextualDisclosure",'
                '"localAction":{"kind":"none","trackingCueIDs":[]},'
                '"memoryUpdate":{"situationUnderstanding":null,'
                '"answeredQuestionPurposes":null,"pendingQuestionPurpose":null,'
                '"pendingConfirmationTarget":null,'
                '"clearPendingQuestionPurpose":false,"trackingAssessments":null,'
                '"tenderUnderstanding":null,"cardImageRelation":null,'
                '"cardRealityMapping":null,"cardNegotiatedMeaning":null,'
                '"fierceUnderstanding":null,"finalNarrative":null,'
                '"practiceOptions":null,"selectedPractice":null},'
                '"replyIntent":"exploreContext",'
                '"replyGuidance":"continue"}'
            ),
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch.object(
                self.gateway,
                "_request_openai_compatible",
                new=AsyncMock(return_value=repaired),
            ) as request:
            await self.gateway._repair_deepseek_turn_controller_json(
                draft='{"clearPendingQuestionPurpose":"false"}',
                original_messages=[
                    {"role": "system", "content": "CURRENT PERMISSIONS"},
                ],
                agent_task="turn_controller_planner",
                model="deepseek-v4-pro",
                max_tokens=1600,
            )

        repair_system = request.await_args.kwargs["messages"][0]["content"]
        self.assertIn(
            "resolvedConfirmation is null unless the latest user reply resolves",
            repair_system,
        )
        self.assertIn("nextPrompt must always be one tagged shape", repair_system)
        self.assertIn(
            "exactly related, partlyRelated, unrelated, or uncertain",
            repair_system,
        )
        self.assertIn(
            "copied exactly and unchanged from presentedTrackingCues",
            repair_system,
        )
        self.assertIn("Never use trackingCandidates", repair_system)
        self.assertIn(
            "null always means leave stored memory unchanged",
            repair_system,
        )
        self.assertIn(
            "legacy fields and must all be null",
            repair_system,
        )
        self.assertIn("A confirmation target must be exactly", repair_system)
        self.assertIn("practiceKind must be null or exactly", repair_system)
        self.assertIn("practiceOptions must be null or an array", repair_system)
        self.assertIn("exactly one object", repair_system)
        self.assertIn("noActionReason must be null unless", repair_system)
        self.assertIn('"resolvedConfirmation":null', repair_system)
        self.assertIn('"nextPrompt":{"kind":"none"', repair_system)
        self.assertIn(
            '"replyIntent":"","noActionReason":null,"replyGuidance":""',
            repair_system,
        )

    def test_short_json_repair_covers_every_visible_writer_pass_only(self) -> None:
        for agent_task in (
            "dialogue_generation",
            "dialogue_generation_after_planner_fallback",
            "writer_revision",
            "question_count_repair",
        ):
            with self.subTest(agent_task=agent_task):
                self.assertTrue(
                    self.gateway._is_repairable_dialogue_writer_task(
                        role="writer",
                        agent_task=agent_task,
                    )
                )

        self.assertFalse(
            self.gateway._is_repairable_dialogue_writer_task(
                role="planner",
                agent_task="dialogue_generation",
            )
        )
        self.assertFalse(
            self.gateway._is_repairable_dialogue_writer_task(
                role="writer",
                agent_task="context_analyzer",
            )
        )

    def test_turn_controller_json_repair_includes_plan_critic(self) -> None:
        expected_roles = {
            "turn_controller_planner": "writer",
            "turn_controller_plan_critic": "critic",
            "turn_controller_writer": "writer",
            "turn_controller_critic": "critic",
        }
        for agent_task, role in expected_roles.items():
            with self.subTest(agent_task=agent_task, role=role):
                self.assertTrue(
                    self.gateway._is_repairable_turn_controller_task(
                        role=role,
                        agent_task=agent_task,
                    )
                )
                wrong_role = "critic" if role == "writer" else "writer"
                self.assertFalse(
                    self.gateway._is_repairable_turn_controller_task(
                        role=wrong_role,
                        agent_task=agent_task,
                    )
                )

    async def test_format_failure_does_not_open_deepseek_circuit(self) -> None:
        openai_result = Completion('{"ok":true}', "openai", "gpt-5-mini")
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.OPENAI_API_KEY", "openai-key"), \
            patch("app.config.OPENAI_BASE_URL", "https://api.openai.com/v1"), \
            patch("app.config.OPENAI_PLANNER_MODEL", "gpt-5-mini"), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(
                    side_effect=ProviderError("deepseek", "invalid_json")
                ),
            ) as deepseek, \
            patch.object(
                self.gateway,
                "_complete_openai",
                new=AsyncMock(return_value=openai_result),
            ) as openai:
            first = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )
            second = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )

        self.assertEqual(first.provider, "openai")
        self.assertEqual(second.provider, "openai")
        self.assertEqual(deepseek.await_count, 2)
        self.assertEqual(openai.await_count, 2)
        self.assertFalse(self.gateway._deepseek_circuit_open)
        self.assertEqual(len(self.gateway._deepseek_failure_times), 0)

    async def test_single_deepseek_failure_does_not_suspend_the_next_user(self) -> None:
        deepseek_result = Completion('{"ok":true}', "deepseek", "deepseek-chat")
        openai_result = Completion('{"ok":true}', "openai", "gpt-5-mini")
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.DEEPSEEK_FAILURE_THRESHOLD", 3), \
            patch("app.config.OPENAI_API_KEY", "openai-key"), \
            patch("app.config.OPENAI_BASE_URL", "https://api.openai.com/v1"), \
            patch("app.config.OPENAI_PLANNER_MODEL", "gpt-5-mini"), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(
                    side_effect=[
                        ProviderError("deepseek", "timeout"),
                        deepseek_result,
                    ]
                ),
            ) as deepseek, \
            patch.object(
                self.gateway,
                "_complete_openai",
                new=AsyncMock(return_value=openai_result),
            ) as openai:
            first = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )
            second = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )
        self.assertEqual(first.provider, "openai")
        self.assertEqual(second.provider, "deepseek")
        self.assertEqual(deepseek.await_count, 2)
        self.assertEqual(openai.await_count, 1)
        self.assertFalse(self.gateway._deepseek_circuit_open)

    async def test_deepseek_circuit_opens_only_after_failure_threshold(self) -> None:
        openai_result = Completion('{"ok":true}', "openai", "gpt-5-mini")
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.DEEPSEEK_FAILURE_THRESHOLD", 2), \
            patch("app.config.DEEPSEEK_FAILURE_WINDOW_SECONDS", 30.0), \
            patch("app.config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS", 60.0), \
            patch("app.config.OPENAI_API_KEY", "openai-key"), \
            patch("app.config.OPENAI_BASE_URL", "https://api.openai.com/v1"), \
            patch("app.config.OPENAI_PLANNER_MODEL", "gpt-5-mini"), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(side_effect=ProviderError("deepseek", "timeout")),
            ) as deepseek, \
            patch.object(
                self.gateway,
                "_complete_openai",
                new=AsyncMock(return_value=openai_result),
            ) as openai:
            for _ in range(3):
                result = await self.gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
                self.assertEqual(result.provider, "openai")

        self.assertEqual(deepseek.await_count, 2)
        self.assertEqual(openai.await_count, 3)
        self.assertTrue(self.gateway._deepseek_circuit_open)

    async def test_half_open_allows_only_one_probe_and_success_closes_circuit(self) -> None:
        openai_result = Completion('{"ok":true}', "openai", "gpt-5-mini")
        deepseek_result = Completion('{"ok":true}', "deepseek", "deepseek-chat")
        probe_started = asyncio.Event()
        release_probe = asyncio.Event()
        deepseek_calls = 0

        async def deepseek_side_effect(**_: object) -> Completion:
            nonlocal deepseek_calls
            deepseek_calls += 1
            if deepseek_calls <= 2:
                raise ProviderError("deepseek", "timeout")
            probe_started.set()
            await release_probe.wait()
            return deepseek_result

        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.DEEPSEEK_FAILURE_THRESHOLD", 2), \
            patch("app.config.DEEPSEEK_FAILURE_WINDOW_SECONDS", 30.0), \
            patch("app.config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS", 0.01), \
            patch("app.config.OPENAI_API_KEY", "openai-key"), \
            patch("app.config.OPENAI_BASE_URL", "https://api.openai.com/v1"), \
            patch("app.config.OPENAI_PLANNER_MODEL", "gpt-5-mini"), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(side_effect=deepseek_side_effect),
            ) as deepseek, \
            patch.object(
                self.gateway,
                "_complete_openai",
                new=AsyncMock(return_value=openai_result),
            ) as openai:
            for _ in range(2):
                await self.gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            await asyncio.sleep(0.02)
            probe_task = asyncio.create_task(
                self.gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            )
            await asyncio.wait_for(probe_started.wait(), timeout=1)
            fallback_during_probe = await self.gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )
            release_probe.set()
            probe_result = await probe_task

        self.assertEqual(fallback_during_probe.provider, "openai")
        self.assertEqual(probe_result.provider, "deepseek")
        self.assertEqual(deepseek.await_count, 3)
        self.assertEqual(openai.await_count, 3)
        self.assertFalse(self.gateway._deepseek_circuit_open)

    async def test_no_fallback_waits_for_half_open_probe_instead_of_inheriting_failure(
        self,
    ) -> None:
        gateway = ProviderGateway(
            deepseek_max_concurrency=2,
            deepseek_queue_timeout_seconds=1.0,
        )
        deepseek_result = Completion('{"ok":true}', "deepseek", "deepseek-chat")
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.DEEPSEEK_FAILURE_THRESHOLD", 2), \
            patch("app.config.DEEPSEEK_FAILURE_WINDOW_SECONDS", 30.0), \
            patch("app.config.DEEPSEEK_HALF_OPEN_AFTER_SECONDS", 0.02), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                gateway,
                "_complete_deepseek",
                new=AsyncMock(
                    side_effect=[
                        ProviderError("deepseek", "timeout"),
                        ProviderError("deepseek", "timeout"),
                        deepseek_result,
                    ]
                ),
            ) as deepseek:
            for _ in range(2):
                with self.assertRaises(HTTPException):
                    await gateway.complete(
                        role="planner", messages=[], max_tokens=100, temperature=0
                    )
            recovered = await gateway.complete(
                role="planner", messages=[], max_tokens=100, temperature=0
            )

        self.assertEqual(recovered.provider, "deepseek")
        self.assertEqual(deepseek.await_count, 3)
        self.assertFalse(gateway._deepseek_circuit_open)

    async def test_deepseek_concurrency_queue_limits_upstream_requests(self) -> None:
        gateway = ProviderGateway(
            deepseek_max_concurrency=1,
            deepseek_queue_timeout_seconds=1.0,
        )
        deepseek_result = Completion('{"ok":true}', "deepseek", "deepseek-chat")
        first_started = asyncio.Event()
        release_first = asyncio.Event()
        active = 0
        maximum_active = 0
        calls = 0

        async def deepseek_side_effect(**_: object) -> Completion:
            nonlocal active, maximum_active, calls
            calls += 1
            active += 1
            maximum_active = max(maximum_active, active)
            if calls == 1:
                first_started.set()
                await release_first.wait()
            active -= 1
            return deepseek_result

        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                gateway,
                "_complete_deepseek",
                new=AsyncMock(side_effect=deepseek_side_effect),
            ) as deepseek:
            first = asyncio.create_task(
                gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            )
            await asyncio.wait_for(first_started.wait(), timeout=1)
            second = asyncio.create_task(
                gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            )
            await asyncio.sleep(0.02)
            self.assertEqual(deepseek.await_count, 1)
            release_first.set()
            results = await asyncio.gather(first, second)

        self.assertEqual([result.provider for result in results], ["deepseek", "deepseek"])
        self.assertEqual(deepseek.await_count, 2)
        self.assertEqual(maximum_active, 1)

    async def test_deepseek_queue_timeout_does_not_open_availability_circuit(self) -> None:
        gateway = ProviderGateway(
            deepseek_max_concurrency=1,
            deepseek_queue_timeout_seconds=0.02,
        )
        deepseek_result = Completion('{"ok":true}', "deepseek", "deepseek-chat")
        first_started = asyncio.Event()
        release_first = asyncio.Event()

        async def deepseek_side_effect(**_: object) -> Completion:
            if not first_started.is_set():
                first_started.set()
                await release_first.wait()
            return deepseek_result

        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-chat"), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                gateway,
                "_complete_deepseek",
                new=AsyncMock(side_effect=deepseek_side_effect),
            ):
            first = asyncio.create_task(
                gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            )
            await asyncio.wait_for(first_started.wait(), timeout=1)
            with self.assertRaises(HTTPException) as raised:
                await gateway.complete(
                    role="planner", messages=[], max_tokens=100, temperature=0
                )
            release_first.set()
            await first

        self.assertEqual(raised.exception.status_code, 503)
        self.assertFalse(gateway._deepseek_circuit_open)
        self.assertEqual(len(gateway._deepseek_failure_times), 0)

    async def test_failures_outside_window_do_not_open_deepseek_circuit(self) -> None:
        gateway = ProviderGateway()
        with patch("app.config.DEEPSEEK_FAILURE_THRESHOLD", 2), \
            patch("app.config.DEEPSEEK_FAILURE_WINDOW_SECONDS", 30.0), \
            patch("app.providers.time.monotonic", side_effect=[100.0, 131.0]):
            first_count, first_open = await gateway._record_deepseek_availability_failure(
                was_half_open_probe=False
            )
            second_count, second_open = await gateway._record_deepseek_availability_failure(
                was_half_open_probe=False
            )

        self.assertEqual((first_count, first_open), (1, False))
        self.assertEqual((second_count, second_open), (1, False))

    def test_deepseek_v4_enables_role_specific_reasoning(self) -> None:
        with patch("app.config.DEEPSEEK_PLANNER_THINKING", "enabled"), \
            patch("app.config.DEEPSEEK_WRITER_THINKING", "disabled"), \
            patch("app.config.DEEPSEEK_PLANNER_REASONING_EFFORT", "high"):
            self.assertEqual(
                self.gateway._deepseek_reasoning_payload(
                    model="deepseek-v4-pro", role="planner"
                ),
                {"thinking": {"type": "enabled"}, "reasoning_effort": "high"},
            )
            self.assertEqual(
                self.gateway._deepseek_reasoning_payload(
                    model="deepseek-v4-pro", role="writer"
                ),
                {"thinking": {"type": "disabled"}},
            )

    def test_legacy_deepseek_alias_does_not_receive_v4_parameters(self) -> None:
        self.assertEqual(
            self.gateway._deepseek_reasoning_payload(
                model="deepseek-chat", role="planner"
            ),
            {},
        )

    async def test_deepseek_response_preserves_safe_generation_metadata(self) -> None:
        response = type(
            "Response",
            (),
            {
                "status_code": 200,
                "json": lambda self: {
                    "choices": [
                        {
                            "message": {
                                "content": (
                                    '{"reflection":"","question":"继续吗？",'
                                    '"actionOptions":[]}'
                                )
                            },
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": 73,
                        "completion_tokens": 21,
                    },
                },
            },
        )()
        with patch.object(
            ProviderGateway, "_post", new=AsyncMock(return_value=response)
        ):
            result = await self.gateway._request_openai_compatible(
                provider="deepseek",
                base_url="https://api.deepseek.com",
                api_key="deepseek-key",
                model="deepseek-v4-pro",
                messages=[{"role": "user", "content": "Return JSON"}],
                max_tokens=100,
                temperature=0.2,
                timeout_seconds=25,
                supports_json_mode=True,
                extra_payload={"thinking": {"type": "disabled"}},
            )

        self.assertEqual(
            result.content,
            '{"reflection":"","question":"继续吗？","actionOptions":[]}',
        )
        self.assertEqual(result.provider, "deepseek")
        self.assertEqual(result.model, "deepseek-v4-pro")
        self.assertEqual(result.finish_reason, "stop")
        self.assertEqual(result.prompt_tokens, 73)
        self.assertEqual(result.completion_tokens, 21)

    def test_invalid_json_logs_structure_without_response_body(self) -> None:
        private_text = "private-reflection-that-must-not-enter-logs"
        malformed = '{"reflection":"' + private_text

        with self.assertLogs("uvicorn.error", level="WARNING") as captured:
            with self.assertRaises(ProviderError) as raised:
                self.gateway._normalize_content(
                    malformed,
                    True,
                    provider="deepseek",
                    model="deepseek-v4-pro",
                    role="writer",
                    request_id="request-safe-id",
                    finish_reason="length",
                    prompt_tokens=1200,
                    completion_tokens=1000,
                )

        self.assertEqual(raised.exception.reason, "invalid_json")
        diagnostic = "\n".join(captured.output)
        self.assertIn("provider_invalid_json", diagnostic)
        self.assertIn("request_id=request-safe-id", diagnostic)
        self.assertIn("finish_reason=length", diagnostic)
        self.assertIn("completion_tokens=1000", diagnostic)
        self.assertIn("json_error=Unterminated string", diagnostic)
        self.assertNotIn(private_text, diagnostic)

    async def test_empty_thinking_result_retries_without_thinking(self) -> None:
        empty = Completion("", "deepseek", "deepseek-v4-pro", finish_reason="stop")
        valid = Completion(
            '{"ok":true}', "deepseek", "deepseek-v4-pro", finish_reason="stop"
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_PLANNER_MODEL", "deepseek-v4-pro"), \
            patch("app.config.DEEPSEEK_PLANNER_THINKING", "enabled"), \
            patch("app.config.DEEPSEEK_PLANNER_REASONING_EFFORT", "high"), \
            patch.object(
                self.gateway,
                "_request_openai_compatible",
                new=AsyncMock(side_effect=[empty, valid]),
            ) as request:
            result = await self.gateway._complete_deepseek(
                role="planner", messages=[], max_tokens=4096, temperature=0
            )

        self.assertEqual(result.content, '{"ok":true}')
        self.assertEqual(request.await_count, 2)
        self.assertEqual(
            request.await_args_list[1].kwargs["extra_payload"],
            {"thinking": {"type": "disabled"}},
        )

    async def test_empty_nonthinking_result_retries_without_json_mode(self) -> None:
        empty = Completion("", "deepseek", "deepseek-v4-pro", finish_reason="stop")
        valid = Completion(
            '{"ok":true}', "deepseek", "deepseek-v4-pro", finish_reason="stop"
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_WRITER_MODEL", "deepseek-v4-pro"), \
            patch("app.config.DEEPSEEK_WRITER_THINKING", "disabled"), \
            patch.object(
                self.gateway,
                "_request_openai_compatible",
                new=AsyncMock(side_effect=[empty, valid]),
            ) as request:
            result = await self.gateway._complete_deepseek(
                role="writer", messages=[], max_tokens=800, temperature=0.2
            )

        self.assertEqual(result.content, '{"ok":true}')
        self.assertEqual(request.await_count, 2)
        self.assertFalse(request.await_args_list[1].kwargs["supports_json_mode"])
        self.assertEqual(request.await_args_list[1].kwargs["max_tokens"], 1600)

if __name__ == "__main__":
    unittest.main()
