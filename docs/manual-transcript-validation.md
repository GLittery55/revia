# Manual transcript regression

This walkthrough checks the fixed card-mediated condition. Exact LLM wording may vary; ordering,
limits, evidence boundaries, and UI events may not.

**Assistant:** 你好，我在。最近有什么事想聊聊吗？

**User:** 我最近在准备投稿论文，但 App 一直调不好。我觉得自己太拖延了。

**Assistant:** 先别急着把它都归到“拖延”上。你说的是一直没开始，还是一直在做、但很难推进？

**User:** 一直在做，但很多天都没看到进展，很挫败，也担心论文来不及。

**Assistant:** 每次结果还是不对时，你更容易责怪自己效率低，还是开始怀疑自己做不好这个项目？

**User:** 两种都有。我也会刷很久视频，有时确实没有停下来总结问题。

**Tender grounding:** 系统区别“持续投入但进展慢”的事实与“我就是拖延、能力不够”的全局判断，
同时保留用户承认的刷视频和未总结行为，并询问这段理解是否准确。

**User:** 对，技术卡住是真的，我自己也有可以调整的地方。

**Tracking:** 若已授权且存在合格候选，只呈现一个候选。例如：“那几晚你比自己的平时少睡
了一些，这不能说明卡住的原因。你觉得它和当时的疲惫对得上吗？”若无候选，程序直接跳过。

**User:** 有一点关系，但不是全部。

**Context confirmation:** 助手用一小段话整合已披露事实、修正后的 grounding，以及“睡眠也许
增加疲惫但不能解释全部”的限定，并只问哪里需要改。

**User:** 这样比较准确。

**Card UI:** Swift 在本地均匀随机选牌并持久化 `card_id`。图片加载成功之前没有牌面问题；失败
时只显示技术提示，并重新加载同一张牌。

**Assistant after display:** 这张牌是随机抽到的，没有固定答案。你觉得画面里正在发生什么？

**User:** 中间的人像在准备出征，也像在发号施令。

**Assistant:** 在“准备出征”和“发号施令”之间，哪一种感觉更明显？

**User:** 更像一直在催大家行动，但方向还没弄清楚。

**Assistant:** 把这个画面放回刚才的论文经历里，它会让你想到其中哪一部分？没有也没关系。

**User:** 我一直催自己赶快做完，却没有先判断 Prompt 到底哪里有问题。

**Tender circumstances:** 助手只沿用“催自己、方向没弄清楚”，询问哪些现实困难不能简单归结为
拖延。等待用户回答。

**User:** Prompt 本身确实难调，后面的实验又依赖它，时间也越来越紧。

**Candid agency:** 助手随后询问，承认这些困难后，用户仍愿意诚实检查或重新选择什么。等待回答。

**User:** 我可以先停下来总结，不再只重复修改。

**Integrated narrative:** 助手把情境、限定后的 tracking、用户自己的牌面说法、现实限制和可选
部分组成一段叙事，不给行动建议，并询问是否准确。

**User:** 基本准确。

**Optional action:** 先邀请用户说自己的小方向；用户可缩小、改写或说暂时不决定。只有明确接受
的措辞才写入会话。

**User:** 今天先整理三个典型失败输出和对应 Prompt。

**Final narrative:** 助手只用用户确认过的材料和已接受行动生成最终叙事，并询问哪里不准确。
用户确认或修正后的版本再次确认，Swift 才进入 `complete`。

## Required checks

- Disclosure lasts 3–5 assistant turns and does not mine technical details after the four evidence
  dimensions are sufficient.
- Tender grounding precedes tracking.
- No tracking permission menu appears after system authorization; at most one cue is presented as
  non-causal background and only the user's confirmed relevance is retained.
- Context confirmation occurs before the random draw.
- Card selection is local and independent; a load retry keeps the same `card_id`.
- There are at most two image questions and at most two connection invitations.
- A second “没有/想不到” records `card_connection: none` and stops probing.
- Tender circumstances and candid agency are separate turns, both answered by the user.
- No action appears before the integrated narrative accuracy check.
- Action is optional, user-authored, and explicitly accepted.
- Completion waits for final narrative confirmation.
- One user turn persists at most one visible assistant reply.
- A nominal complete path remains within roughly 10–16 assistant turns.
