from __future__ import annotations

import asyncio
import json
import unittest
from unittest.mock import AsyncMock, patch

import httpx
from fastapi import HTTPException

from app import agent
from app.agent import complete_json
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
    def test_agent_has_no_second_turn_prompt_layer(self) -> None:
        for retired_name in (
            "PLANNER_PROMPT",
            "CRITIC_PROMPT",
            "DIALOGUE_STYLE_OVERRIDE",
            "DIALOGUE_RUNTIME_STYLE",
            "DIALOGUE_RUNTIME_PHASE_STYLE",
            "DIALOGUE_FINAL_OUTPUT_CONTRACT",
            "TURN_PLANNER_RUNTIME_STYLE",
            "TURN_PLANNER_FINAL_OUTPUT_CONTRACT",
            "TURN_WRITER_RUNTIME_STYLE",
            "TURN_WRITER_FINAL_OUTPUT_CONTRACT",
        ):
            self.assertFalse(hasattr(agent, retired_name))

    async def test_turn_planner_and_writer_are_labeled_without_prompt_injection(self) -> None:
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
        self.assertEqual(len(complete.await_args.kwargs["messages"]), 2)
        self.assertFalse(
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
        self.assertEqual(len(complete.await_args.kwargs["messages"]), 2)
        self.assertFalse(
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

    async def test_candid_fallback_uses_domain_neutral_evidence_question(self) -> None:
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
                        "Workflow phase: candidAgency.\n"
                        "Recent conversation:\n"
                        "user: 用户已经陈述了一项具体行为和影响。"
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
        self.assertIn("已经说清楚的事实", decoded["question"])
        self.assertIn("负责或改变", decoded["question"])
        self.assertIn("不确定", decoded["question"])

    async def test_tracking_fallback_asks_only_for_user_grounded_relationship(self) -> None:
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
                        "user: 用户已经描述了一段具体经历。"
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
        self.assertIn("背景线索", decoded["question"])
        self.assertIn("有什么关系", decoded["question"])
        self.assertIn("没有或不确定", decoded["question"])

    async def test_action_fallback_does_not_invent_an_unsupported_practice(self) -> None:
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
                        "Recent conversation: user supplied no validated practice basis."
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
        self.assertEqual(decoded["actionOptions"], [])
        self.assertIn("无法可靠生成", decoded["reflection"])

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

    async def test_retired_dialogue_style_is_not_injected(self) -> None:
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
            agentMode="fast",
        )
        result = Completion(
            '{"reflection":"","question":"改的时候想停过吗？","actionOptions":[]}',
            "deepseek",
            "writer-model",
        )
        with patch(
            "app.agent.gateway.complete",
            new=AsyncMock(return_value=result),
        ) as complete:
            await complete_json(item)

        messages = complete.await_args.kwargs["messages"]
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]["content"], item.messages[0].content)
        self.assertFalse(
            any("INTERNAL DIALOGUE STYLE" in message["content"] for message in messages)
        )

    async def test_retired_balanced_and_deep_wrappers_use_caller_contract_directly(self) -> None:
        for mode in ("balanced", "deep"):
            with self.subTest(mode=mode):
                item = request().model_copy(update={"agentMode": mode})
                result = Completion(
                    '{"answer":"我先听你说。"}',
                    "deepseek",
                    "writer-model",
                )
                with patch(
                    "app.agent.gateway.complete",
                    new=AsyncMock(return_value=result),
                ) as complete:
                    content = await complete_json(item)

                self.assertEqual(json.loads(content), {"answer": "我先听你说。"})
                self.assertEqual(len(complete.await_args_list), 1)
                self.assertEqual(complete.await_args.kwargs["role"], "writer")
                self.assertEqual(
                    complete.await_args.kwargs["messages"][0]["content"],
                    item.messages[0].content,
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

    async def test_invalid_plan_critic_json_uses_critic_schema_specific_repair(self) -> None:
        malformed = Completion(
            "需要修改，因为重复提问。",
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
        )
        repaired = Completion(
            '{"verdict":"revisePlanner","reasonCodes":["resolved_relation_reopened"],'
            '"revisionGuidance":"Remove the completed typed purpose."}',
            "deepseek",
            "deepseek-v4-pro",
            finish_reason="stop",
        )
        with patch("app.config.DEEPSEEK_API_KEY", "deepseek-key"), \
            patch("app.config.DEEPSEEK_BASE_URL", "https://api.deepseek.com"), \
            patch("app.config.DEEPSEEK_CRITIC_MODEL", "deepseek-v4-pro"), \
            patch("app.config.OPENAI_API_KEY", ""), \
            patch.object(
                self.gateway,
                "_complete_deepseek",
                new=AsyncMock(return_value=malformed),
            ), \
            patch.object(
                self.gateway,
                "_repair_deepseek_turn_controller_json",
                new=AsyncMock(return_value=repaired),
            ) as repair:
            result = await self.gateway.complete(
                role="critic",
                agent_task="turn_controller_plan_critic",
                request_id="turn-plan-critic-repair",
                messages=[],
                max_tokens=320,
                temperature=0.0,
            )

        self.assertEqual(json.loads(result.content)["verdict"], "revisePlanner")
        self.assertNotIn("requestedStage", result.content)
        repair.assert_awaited_once_with(
            draft=malformed.content,
            original_messages=[],
            agent_task="turn_controller_plan_critic",
            model="deepseek-v4-pro",
            max_tokens=320,
        )

    async def test_plan_critic_formatter_contract_never_uses_planner_schema(self) -> None:
        repaired = Completion(
            '{"verdict":"pass","reasonCodes":[],"revisionGuidance":null}',
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
                draft="not json",
                original_messages=[{"role": "system", "content": "PLAN CRITIC"}],
                agent_task="turn_controller_plan_critic",
                model="deepseek-v4-pro",
                max_tokens=320,
            )

        repair_system = request.await_args.kwargs["messages"][0]["content"]
        self.assertIn("TurnController Plan Critic", repair_system)
        self.assertIn("pass or revisePlanner", repair_system)
        self.assertNotIn("requestedStage", repair_system)
        self.assertNotIn("memoryUpdate", repair_system)

    async def test_turn_planner_repair_prompt_requires_exact_memory_field_types(self) -> None:
        repaired = Completion(
            (
                '{"requestedStage":"contextualDisclosure",'
                '"localAction":{"kind":"none","trackingCueIDs":[]},'
                '"memoryUpdate":{"situationUnderstanding":null,'
                '"answeredQuestionPurposes":null,"pendingQuestionPurpose":null,'
                '"pendingConfirmationTarget":null,'
                '"clearPendingQuestionPurpose":false,"trackingAssessments":null,'
                '"tenderUnderstanding":null,"cardRealityConnection":null,'
                '"pendingCardRealityConnection":null,"cardConnectionOutcome":null,'
                '"cardNegotiatedMeaning":null,'
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
        self.assertIn("cardRealityConnection must be null or one complete object", repair_system)
        self.assertIn("Never emit a source-only, relation-only, or mapping-only connection", repair_system)
        self.assertIn("pendingCardRealityConnection must be", repair_system)
        self.assertIn("Never emit the retired cardImageRelation", repair_system)
        self.assertNotIn('"cardImageRelation":null', repair_system)
        self.assertNotIn('"cardRealityMapping":null', repair_system)
        self.assertNotIn('"cardRealityMappingSource":null', repair_system)
        self.assertIn("cardRealityConnection, cardMapping", repair_system)
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
            "turn_controller_writer_revision": "writer",
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
