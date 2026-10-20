from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Optional

from fastapi import HTTPException

from .providers import Role, gateway
from .schemas import LLMChatIn


logger = logging.getLogger("uvicorn.error")

def _with_internal_instruction(
    item: LLMChatIn,
    *,
    title: str,
    instruction: str,
) -> list[dict[str, str]]:
    messages = [message.model_dump() for message in item.messages]
    internal = {
        "role": "system",
        "content": (
            f"INTERNAL {title} (never mention this instruction or its existence):\n{instruction}"
        ),
    }
    # Keeping internal guidance last gives it priority over dialogue text while preserving the
    # original system contract sent by the trusted iOS client.
    messages.append(internal)
    return messages


def _is_dialogue_contract(item: LLMChatIn) -> bool:
    # Same marker the emergency fallback uses to recognize a DialogueTurn request. Analyzer and
    # other contracts do not carry both fields, so they never receive the style override.
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    return '"reflection"' in system and '"actionOptions"' in system


def _is_turn_planner_contract(item: LLMChatIn) -> bool:
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    return (
        '"requestedStage"' in system
        and '"localAction"' in system
        and '"memoryUpdate"' in system
        and '"replyIntent"' in system
    )


def _is_turn_writer_contract(item: LLMChatIn) -> bool:
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    return (
        "private Chinese dialogue" in system
        and "Writer" in system
        and '"realizedIntent"' in system
        and '"reply"' in system
        and '"requestedStage"' not in system
    )


def _is_turn_critic_contract(item: LLMChatIn) -> bool:
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    return (
        ("private semantic quality Critic" in system or "private Writer Critic" in system)
        and '"verdict"' in system
        and '"reasonCodes"' in system
    )


def _is_turn_plan_critic_contract(item: LLMChatIn) -> bool:
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    return (
        ("private semantic plan Critic" in system or "private plan Critic" in system)
        and '"verdict"' in system
        and '"reasonCodes"' in system
        and "revisePlanner" in system
    )


def _is_turn_controller_contract(item: LLMChatIn) -> bool:
    return (
        _is_turn_planner_contract(item)
        or _is_turn_writer_contract(item)
        or _is_turn_plan_critic_contract(item)
        or _is_turn_critic_contract(item)
    )


def _agent_task_for_request(item: LLMChatIn) -> str:
    """Classify internal work for operational logs without retaining reflection content."""
    system = "\n".join(message.content for message in item.messages if message.role == "system")
    if "private ContextAnalyzer" in system:
        return "context_analyzer"
    if _is_turn_planner_contract(item):
        return "turn_controller_planner"
    if _is_turn_writer_contract(item):
        return "turn_controller_writer"
    if _is_turn_plan_critic_contract(item):
        return "turn_controller_plan_critic"
    if _is_turn_critic_contract(item):
        return "turn_controller_critic"
    if _is_dialogue_contract(item):
        return "dialogue_generation"
    return "structured_completion"


def _direct_role_for_agent_task(agent_task: str) -> Role:
    """Route typed TurnController audits through the configured Critic model.

    Every current contract is one direct provider call. Only the two private semantic Critic
    contracts use the Critic role; Planner, Writer, analyzer, and generic structured completions
    use the Writer role.
    """
    if agent_task in {
        "turn_controller_plan_critic",
        "turn_controller_critic",
    }:
        return "critic"
    return "writer"


async def _direct_completion(item: LLMChatIn, *, request_id: str, agent_task: Optional[str] = None) -> str:
    messages = [message.model_dump() for message in item.messages]
    resolved_agent_task = agent_task or _agent_task_for_request(item)
    result = await gateway.complete(
        role=_direct_role_for_agent_task(resolved_agent_task),
        agent_task=resolved_agent_task,
        request_id=request_id,
        messages=messages,
        max_tokens=item.maxTokens,
        temperature=item.temperature,
    )
    return result.content


async def complete_json(item: LLMChatIn, *, agent_task_override: Optional[str] = None) -> str:
    request_id = uuid.uuid4().hex[:12]
    # The typed turn endpoint already knows the trusted prompt task. Prefer that identity over
    # brittle system-prompt phrase matching; legacy chat requests retain contract detection.
    agent_task = agent_task_override or _agent_task_for_request(item)
    logger.info(
        "llm_request_started request_id=%s agent_task=%s requested_mode=%s",
        request_id,
        agent_task,
        item.agentMode,
    )
    try:
        content = await _complete_json_direct_contract(
            item,
            request_id=request_id,
            agent_task=agent_task,
        )
    except HTTPException as error:
        # The coarse TurnController contract is intentionally not replaced by a semantic server
        # fallback. The iOS ProtocolController performs one constrained regeneration and otherwise
        # keeps the stage unchanged with a neutral technical message.
        if _is_turn_controller_contract(item):
            raise
        # The upstream providers can still be unavailable after bounded retries. Keep the
        # reflection usable with a contract-valid, deliberately modest local response. This
        # fallback never invents an attribution and is logged for operational monitoring.
        logger.error(
            "emergency_contract_fallback request_id=%s agent_task=%s agent_mode=%s status=%s",
            request_id,
            agent_task,
            item.agentMode,
            error.status_code,
        )
        content = _emergency_contract_fallback(item)
    content = await _repair_dialogue_question_count(content, item, request_id=request_id)
    content = _limit_dialogue_action_options(content, item)
    logger.info(
        "llm_response_ready request_id=%s agent_task=%s requested_mode=%s",
        request_id,
        agent_task,
        item.agentMode,
    )
    return content


def _dialogue_question_count(content: str) -> int:
    try:
        payload = json.loads(content)
    except (TypeError, json.JSONDecodeError):
        return 0
    if not isinstance(payload, dict):
        return 0
    visible = "\n".join(
        value for key in ("reflection", "question")
        if isinstance((value := payload.get(key)), str)
    )
    return visible.count("？") + visible.count("?")


def _first_question(text: str) -> str:
    for index, character in enumerate(text):
        if character in "？?":
            return text[: index + 1].strip()
    return ""


def _without_question_clauses(text: str) -> str:
    clauses = re.split(r"(?<=[。！？?!])", text)
    return "".join(
        clause for clause in clauses if "？" not in clause and "?" not in clause
    ).strip()


def _locally_reduce_dialogue_to_one_question(content: str) -> str:
    """Preserve grounded wording if a repair request is unavailable; never insert a generic prompt."""
    try:
        payload = json.loads(content)
    except (TypeError, json.JSONDecodeError):
        return content
    if not isinstance(payload, dict):
        return content
    reflection = payload.get("reflection") if isinstance(payload.get("reflection"), str) else ""
    question = payload.get("question") if isinstance(payload.get("question"), str) else ""
    payload["reflection"] = _without_question_clauses(reflection)
    payload["question"] = _first_question(question) or _first_question(reflection)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


async def _repair_dialogue_question_count(
    content: str, item: LLMChatIn, *, request_id: str
) -> str:
    """Give the writer one bounded correction before the iOS client needs to apply a safeguard."""
    if not _is_dialogue_contract(item) or _dialogue_question_count(content) <= 1:
        return content

    instruction = json.dumps(
        {
            "previousDraft": json.loads(content),
            "revisionRule": (
                "Return only the original JSON contract. Keep the grounded reflection that responds "
                "to the user's latest message, but leave exactly one Chinese question mark across "
                "reflection and question combined. Do not replace the reply with a generic template."
            ),
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    messages = _with_internal_instruction(
        item,
        title="ONE-QUESTION REPAIR",
        instruction=instruction,
    )
    try:
        repaired = await gateway.complete(
            role="writer",
            agent_task="question_count_repair",
            request_id=request_id,
            messages=messages,
            max_tokens=item.maxTokens,
            temperature=min(item.temperature, 0.15),
        )
    except HTTPException:
        logger.warning("dialogue_question_repair_unavailable_preserving_first_question")
        return _locally_reduce_dialogue_to_one_question(content)

    if _dialogue_question_count(repaired.content) <= 1:
        logger.info("dialogue_question_repaired")
        return repaired.content

    logger.warning("dialogue_question_repair_still_invalid_preserving_first_question")
    return _locally_reduce_dialogue_to_one_question(content)


def _limit_dialogue_action_options(content: str, item: LLMChatIn) -> str:
    """Keep the visible action contract bounded even when a provider ignores the prompt."""
    if not _is_dialogue_contract(item):
        return content
    try:
        payload = json.loads(content)
    except (TypeError, json.JSONDecodeError):
        return content
    options = payload.get("actionOptions")
    if not isinstance(options, list):
        return content
    state_match = re.search(
        r"Application-controlled state:\s*([A-Za-z]+)",
        "\n".join(message.content for message in item.messages if message.role == "user"),
    )
    # The final action taxonomy is deliberately narrow. A boundary/protection step is a valid
    # fierce-compassion practice, but the provider must not invent categories or responsibility
    # judgments outside the application contract.
    if state_match and state_match.group(1) == "actionSelection":
        options = [
            option
            for option in options
            if isinstance(option, dict) and option.get("category") in {"care", "repair", "protect", "change"}
        ]
    if len(options) <= 2 and options == payload.get("actionOptions"):
        return content
    payload["actionOptions"] = options[:2]
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


async def _complete_json_direct_contract(
    item: LLMChatIn,
    *,
    request_id: str,
    agent_task: str,
) -> str:
    # The current iOS protocol already sends separate typed Planner, Writer, plan-Critic,
    # and Writer-Critic requests. Running the retired generic Planner/Critic around those
    # contracts would duplicate semantic ownership and reintroduce obsolete dialogue rules.
    # Older balanced/deep callers still receive a direct completion under their own trusted
    # system contract; no historical payload or caller-owned JSON shape is rewritten here.
    selected_mode = "fast" if item.agentMode == "fast" else "direct_contract"
    logger.info(
        "agent_mode_selected request_id=%s agent_task=%s mode=%s",
        request_id,
        agent_task,
        selected_mode,
    )
    return await _direct_completion(item, request_id=request_id)


def _embedded_conversation_turns(prompt: str) -> list[tuple[str, str]]:
    """Extract the role-prefixed transcript embedded by the iOS prompt factory."""
    if "Recent conversation:" not in prompt:
        return []
    transcript = prompt.rsplit("Recent conversation:", 1)[1]
    turns: list[tuple[str, str]] = []
    role = ""
    content_lines: list[str] = []
    for raw_line in transcript.splitlines():
        match = re.match(r"^\s*(user|assistant):\s*(.*)$", raw_line)
        if match:
            if role:
                turns.append((role, "\n".join(content_lines).strip()))
            role = match.group(1)
            content_lines = [match.group(2)]
        elif role:
            content_lines.append(raw_line.strip())
    if role:
        turns.append((role, "\n".join(content_lines).strip()))
    return turns


def _latest_user_context(prompt: str) -> tuple[str, str]:
    """Return the latest user text and the assistant turn immediately before it."""
    turns = _embedded_conversation_turns(prompt)
    for index in range(len(turns) - 1, -1, -1):
        role, content = turns[index]
        if role != "user":
            continue
        previous_assistant = ""
        for previous_index in range(index - 1, -1, -1):
            previous_role, previous_content = turns[previous_index]
            if previous_role == "assistant":
                previous_assistant = previous_content
                break
        return content.strip(), previous_assistant.strip()
    return "", ""


def _plain_repair_question(previous_assistant: str) -> str:
    """Rephrase known ambiguous questions without exposing dialogue machinery."""
    previous = previous_assistant.strip()
    if "注意力" in previous or "精力" in previous:
        return "那段时间，除了这件事，你还在处理哪些具体事情？"
    if any(term in previous for term in ("没开始", "没有开始", "进展慢", "难推进", "很难推进")):
        return "这件事是还没动手，还是已经开始了，只是进展比较慢？"
    if any(term in previous for term in ("画面", "图卡", "这张牌", "这张图")):
        return "这张图有没有让你想到刚才那件事里的某一段？"
    if "评价自己" in previous:
        return "那一刻，你对自己说了什么？"
    if "怎么想" in previous or "脑子里" in previous:
        return "那一刻，你最先想到的是什么？"
    return "换句直白的话：刚才那件事里，哪一点对你影响最大？"


def _fallback_dialogue_repair(
    *,
    state: str,
    latest_user: str,
    previous_assistant: str,
    allow_final_card_scaffold: bool = False,
) -> Optional[tuple[str, str]]:
    normalized = re.sub(r"[\s。！？!?，,]", "", latest_user)
    if any(term in normalized for term in ("这是什么意思", "没听懂", "能说具体一点吗", "能说具体点吗")):
        return "我刚才问得不够清楚。", _plain_repair_question(previous_assistant)
    if any(term in normalized for term in ("问题重复了", "已经问过了", "怎么又问")):
        return "你说得对，我刚才又问回去了。这个问题先停在这里。", ""
    if any(term in normalized for term in ("想不到", "没有了", "没什么了", "没有联想到", "不想再想了")):
        if state in {"cardInterpretation", "attributionReflection"}:
            if state == "attributionReflection" and allow_final_card_scaffold:
                return (
                    "想不到也没关系，我们只再看一个很简单的方向。",
                    "画面里这个人的状态，有没有一点和刚才的事相似？都没有也可以。",
                )
            return "好，这张图先放在这里，不用勉强把它和刚才的事连起来。", ""
        return "好，这部分先放下，不用再勉强找答案。", ""
    if normalized in {"没开始", "还没开始", "一直没开始", "没有开始"}:
        return "明白，你说的是还没开始。", "你第一次打算动手，是在什么时候？"
    if normalized in {"进展慢", "只是进展慢", "很难推进", "一直很难推进", "已经开始了只是进展慢"}:
        return "明白，是已经开始了，只是进展比较慢。", "现在更让你着急的是时间，还是担心做不出来？"
    return None


def _emergency_contract_fallback(item: LLMChatIn) -> str:
    system = "\n".join(
        message.content for message in item.messages if message.role == "system"
    )
    user = "\n".join(
        message.content for message in item.messages if message.role == "user"
    )
    latest_user, previous_assistant = _latest_user_context(user)

    if '"recommendedRoute"' in system and '"safetyOverride"' in system:
        # A provider outage must preserve uncertainty. This object deliberately contains no
        # attribution, route evidence, or inferred psychological facts; Swift still validates
        # the advisory route and retains control of the workflow.
        return json.dumps(
            {
                "safetyOverride": False,
                "distressLevel": 0,
                "selfAttackLevel": 0,
                "reflectiveCapacity": 1,
                "behaviorIdentitySeparation": 0,
                "multipleExplanationsCapacity": 0,
                "consentToCandor": "unknown",
                "eventDescription": None,
                "emotions": [],
                "bodilyResponses": [],
                "selfJudgment": None,
                "contextualConstraints": [],
                "personalContributions": [],
                "possibleImpactOnOthers": [],
                "possibleBoundaryConcerns": [],
                "possibleUnmetNeeds": [],
                "possibleRepeatingPatterns": [],
                "uncertainties": ["AI analysis temporarily unavailable"],
                "pastControllability": "unknown",
                "presentAgency": "unknown",
                "recommendedRoute": "explore",
                "secondaryRoutes": [],
                "reasonCodes": ["provider_unavailable"],
                "missingInformation": [],
                "nextQuestionGoal": "invite one concrete, easy-to-answer detail",
                "confidence": 0.0,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

    if '"reflection"' in system and '"actionOptions"' in system:
        state_match = re.search(r"Application-controlled state:\s*([A-Za-z]+)", user)
        state = state_match.group(1) if state_match else ""
        phase_match = re.search(r"Workflow phase:\s*([A-Za-z]+)", user)
        workflow_phase = phase_match.group(1) if phase_match else ""
        reflection = ""
        question = "你想接着说什么？"
        action_options: list[dict[str, object]] = []

        repair = _fallback_dialogue_repair(
            state=state,
            latest_user=latest_user,
            previous_assistant=previous_assistant,
            allow_final_card_scaffold="one final" in (system + "\n" + user).lower(),
        )
        if repair is not None:
            reflection, question = repair

        elif state == "eventDisclosure":
            question = "最近有什么事想聊聊吗？可以从一件具体的事说起。"
        elif state == "emotionDisclosure":
            question = "这件事卡住你时，你当时是怎么想的？"
        elif state == "selfJudgment":
            question = "那时你会怎么评价自己？"
        elif state == "contextDisclosure":
            question = "那段时间，除了这件事，你还在处理哪些具体事情？"
        elif state == "trackingReview":
            reflection = "这些记录只能当作背景，需要放回你刚才说的生活状态里一起看。"
            question = "放回刚才那件事里，这条背景线索和你的实际经历有什么关系？没有或不确定也可以。"
        elif state == "readinessCheck":
            if "did not contain enough usable observations" in user:
                reflection = "已经授权的最近记录里，暂时没有足够完整的数据可以和你的个人平时比较，所以这次不把数据当作判断依据。"
            else:
                reflection = "目前先保留你已经说清楚的经历和仍不确定的部分，不用把记录当成原因。"
            question = "这段理解里，有没有哪一句需要改一改？"
        elif state == "cardInterpretation":
            reflection = "这张图没有标准答案，先以你看到的为准。"
            if workflow_phase == "cardAssociation":
                question = "沿着你刚才说的画面，接下来可能会发生什么？"
            elif workflow_phase == "cardNarrativeDeepening":
                question = "画面里这个人为什么会这样做？"
            else:
                question = "看到这张牌，你觉得画面里正在发生什么？"
        elif state == "tenderGrounding":
            reflection = "已经说清楚的部分先留在这里，不需要把每个细节都拆开。"
            question = "你还有哪部分想接着说？"
        elif state == "tenderExploration":
            reflection = "这个问题先放下，不用勉强找答案。"
            question = "你还有哪部分想接着说？"
        elif state == "attributionReflection":
            if workflow_phase == "cardConnection":
                reflection = "先不用急着替这个画面下结论。"
                question = "这个画面有没有让你想到刚才那件事里的某一部分？没有也可以。"
            elif workflow_phase == "cardMeaningShift":
                question = "把这个画面和刚才的事放在一起后，你对那件事的看法有变化吗？没有也可以。"
            elif workflow_phase == "candidCircumstances":
                question = "这件事里，哪些现实困难需要先被承认，而不能只变成对自己的批评？"
            elif workflow_phase == "candidAgency":
                question = "在你已经说清楚的事实里，哪一部分是你认为自己可以负责或改变的？没有或不确定也可以。"
            else:
                reflection = "先把已经说清楚的部分留在这里。"
                question = "这段理解里，有没有哪一句需要改一改？"
        elif state == "actionSelection":
            reflection = "暂时无法可靠生成一项基于本次内容的具体建议，可以稍后重试或先不选择行动。"
            question = ""
            action_options = []
        elif state == "summary":
            reflection = "这次记录保留了当时的处境、仍不确定的部分，以及你愿意选择的下一步。"
            question = "这段记录里，有没有哪一句需要改一改？"

        return json.dumps(
            {
                "reflection": reflection,
                "question": question,
                "actionOptions": action_options,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

    if '"readyForCard"' in system and '"accepted"' in system:
        disclosure_match = re.search(
            r"Latest disclosure:\s*(.*?)(?:\nNarrative so far:|\Z)",
            user,
            flags=re.DOTALL,
        )
        disclosure = disclosure_match.group(1).strip() if disclosure_match else ""
        count_match = re.search(
            r"Accepted substantive disclosures before this answer:\s*(\d+)", user
        )
        prior_count = int(count_match.group(1)) if count_match else 0
        normalized = disclosure.lower().strip("。！？!?.,， ")
        accepted = bool(disclosure) and normalized not in {
            "你好",
            "您好",
            "hello",
            "hi",
            "?",
            "？",
        }
        if not accepted:
            return json.dumps(
                {
                    "accepted": False,
                    "response": "我在。可以从最近的一件小事开始。",
                    "followUpQuestion": "最近哪件小事最让你在意？",
                    "readyForCard": False,
                    "stateSummary": "",
                    "compassionMode": "tender",
                    "event": "",
                    "experience": "",
                    "meaning": "",
                    "selfJudgment": "",
                    "need": "",
                    "constraints": "",
                    "agencyAndUncertainty": "",
                    "emotionalCapacity": "uncertain",
                    "readinessConfidence": 0.0,
                    "missingDimension": "event",
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )

        # Preserve only the user's own words. Rotating the evidence field prevents a temporary
        # outage from erasing disclosure, while avoiding model-like psychological inference.
        event = disclosure if prior_count == 0 else ""
        experience = disclosure if prior_count == 1 else ""
        meaning = disclosure if prior_count >= 2 else ""
        questions = [
            "这件事发生时，你最先想到的是什么？",
            "当时你脑子里最先冒出来的是什么？",
            "那段时间，除了这件事，你还在处理哪些具体事情？",
        ]
        return json.dumps(
            {
                "accepted": True,
                "response": "",
                "followUpQuestion": questions[min(prior_count, 2)],
                "readyForCard": prior_count >= 2,
                "stateSummary": "先保留用户已经说出的内容，不追加推断。",
                "compassionMode": "tender",
                "event": event,
                "experience": experience,
                "meaning": meaning,
                "selfJudgment": "",
                "need": "",
                "constraints": "",
                "agencyAndUncertainty": "",
                "emotionalCapacity": "uncertain",
                "readinessConfidence": 0.6 if prior_count >= 2 else 0.0,
                "missingDimension": "experience" if prior_count == 0 else "meaning",
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

    if '"reflectiveSummary"' in system and '"actionSuggestions"' in system:
        stage_match = re.search(r"stage\s+([A-Za-z]+)", system)
        stage = stage_match.group(1) if stage_match else ""
        hypotheses: list[str] = []
        actions: list[dict[str, str]] = []
        transition = "listen"
        summary = ""
        question = "你想接着说什么？"

        repair = _fallback_dialogue_repair(
            state=stage,
            latest_user=latest_user,
            previous_assistant=previous_assistant,
            allow_final_card_scaffold="one final" in (system + "\n" + user).lower(),
        )
        if repair is not None:
            summary, question = repair

        elif stage in {"tenderGrounding", "tenderExploration"}:
            transition = "deepen"
            question = ""
        elif stage == "candidInquiry":
            transition = "action"
            question = ""
            hypotheses = ["也许可以先看看哪些部分已经有证据，哪些还需要保留不确定。"]
        elif stage == "actionComposer":
            transition = "action"
            question = ""
            summary = "先把下一步缩小到一个不会增加负担的动作。"
            actions = [
                {
                    "type": "care",
                    "text": "先留出一分钟，不急着继续分析或解决。",
                    "rationale": "暂不增加分析任务，也不要求立刻解决问题。",
                }
            ]

        return json.dumps(
            {
                "reflectiveSummary": summary,
                "compassionThread": "",
                "uncertaintyStatement": "",
                "question": question,
                "hypotheses": hypotheses,
                "actionSuggestions": actions,
                "compassionMode": "tender",
                "transitionRecommendation": transition,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

    # Unknown trusted contracts should remain valid JSON instead of leaking an upstream error.
    return '{"ok":false,"temporarilyDegraded":true}'
