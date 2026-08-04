# Beyond Comfort：设计论证与研究方案

> 文档状态：study 前决策稿  
> 适用范围：日常、非危机性的 self-critical episodes；不是诊断、治疗或危机干预系统  
> 核心版本：先锁定 contribution 与机制，再冻结 card deck、prompt、study protocol 和分析计划

---

## 0. 一页结论

### 0.1 一句话 contribution

**中文**

Beyond Comfort 提出 **contextualized projective scaffolding（情境化投射支架）**：在日常自我批评情境中，系统把经过用户确认的近期情境线索与随机抽取的开放图像结合起来，将困难的归因工作从“模型替用户下判断”转化为“用户借助第三物形成、确认、修改或拒绝自己的解释”，从而支持一种既承认痛苦与限制、又不抹去行动、边界与修复空间的 self-compassionate candor。

**English**

> We introduce contextualized projective scaffolding, an LLM-mediated approach for everyday self-critical episodes that combines user-confirmed contextual cues with a chance-drawn ambiguous card to shift difficult attribution work from model assertion to user-authored interpretation. By preserving epistemic agency, the system supports self-compassionate candor: recognizing suffering and circumstances without erasing agency, boundaries, or repair.

### 0.2 为什么普通 wellbeing chatbot 不足以直接解决这个问题

这里不应写成“现有 chatbot 都做不到”，而应准确描述一个 **interactional dilemma**：

1. 当模型以安慰和认同为主时，它可能在缺乏证据的情况下附和用户的解释，减弱反思中的行动性或责任辨析。LLM sycophancy 研究已经表明，人类偏好信号可能奖励迎合用户立场的回答，但这并不等于回答真实或有帮助（[Sharma et al., 2023](https://arxiv.org/abs/2310.13548)）。
2. 当模型直接指出“你真正的问题”或挑战用户时，它又超出了自身对情境的认识范围，容易造成被判断、被控制或被误解的体验。心理抗拒研究说明，自由受威胁的表达可能引发 reactance；动机式访谈则强调由来访者形成改变语言和行动理由，而不是由外部替其宣布结论（[Moyers et al., 2017](https://pubmed.ncbi.nlm.nih.gov/29265832/)，[Markland et al., 2005](https://pmc.ncbi.nlm.nih.gov/articles/PMC3330017/)）。

Beyond Comfort 的核心不是“加一张图让聊天更有趣”，而是引入一个 **不替用户说话的中介物**：卡片制造可讨论的距离和多义性，情境数据提供可核验的现实线索，解释权仍由用户掌握。

### 0.3 贯穿系统的理论主线

系统需要一个主线，而不是让多个理论各自解释一段流程：

**主线是 epistemic agency / interpretation ownership（认知自主与解释所有权）。**

- **目标构念**：完整的 self-compassion。系统既帮助用户承认痛苦、限制和共同人性，也保留具体行为、影响、边界与下一步行动。Self-compassion 应作为相互作用的整体来测量，而不是把“温和”和“有力”当作两个已被充分验证的独立量表（[Neff, 2023](https://self-compassion.org/wp-content/uploads/2023/01/Neff-2023.pdf)）。
- **互动机制**：用户生成、确认或拒绝关键理解；模型用提问、复述和不确定表达支持，而不宣布真相。这与 autonomy support 和 motivational interviewing 的 evocation 原则相符。
- **设计材料**：开放但可读的图像提供 projective distance。Ambiguity 可以成为设计资源，使人把自身经验带入解释，但模糊度必须被校准，而不是越模糊越好（[Gaver et al., 2003](https://citeseerx.ist.psu.edu/document?doi=39b22e4b9efa2616224123adcd3bf7f8e8192057&repid=rep1&type=pdf)）。
- **数据角色**：个人数据只是可选择、可质疑的 cue，不是对动机、人格或因果关系的证据。数据必须先由用户确认相关性，才可进入后续反思。

### 0.4 关于 tender / fierce self-compassion 的决定

依据当前 `protocolVersion = 2` 的代码，它是两个实验条件共享的 **self-compassion architecture / design target**，不是当前实验中被操纵的变量，也不应被单独包装成未经验证的双路线因果机制。

- “Tender”是条件分流前必须由用户确认的共同 baseline，对应承认痛苦、需求、限制和当时处境。
- “Fierce”对应在用户已有证据支持时，辨认选择、影响、边界、修复或改变。
- “Fierce”在当前代码中是 optional candid function：整个 session 最多问一次；如果没有具体行为、影响、边界、反复出现且有代价的反应，或用户不愿继续，就直接进入 narrative。
- “Fierce”不能等同于模型挑战用户；它应来自用户确认过的事实和用户自己愿意承担的行动空间。
- 这些内部路线名不出现在 UI 中。论文和系统图可以说明设计逻辑，demo 中则通过 annotated transcript 展示它确实存在。

因此当前系统可以分成三层：

| 层 | 当前代码中的内容 | 在 paper 中的角色 |
|---|---|---|
| Shared grounding | adaptive disclosure、context/tracking 协商、Tender summary confirmation | 两个条件共同的 self-compassion 基础 |
| Experimental mechanism | negotiated card interpretation vs direct textual reflection | 当前 study 真正比较的 intervention |
| Shared closure | optional candid/Fierce question、final narrative confirmation、one optional practice | 确保两组都不只停在安慰，也不强迫行动 |

### 0.5 推荐的研究组合

一篇完整 paper 至少需要两个相互衔接的研究阶段：

1. **Study 0：card calibration pilot**  
   回答卡片是否“可读但不封闭”、是否存在稳定的负面偏向、固定文化 schema 或无法解释的卡。
2. **Study 1：两周 counterbalanced crossover deployment**  
   比较 card-mediated reflection 与 active direct-text reflection。与 contribution 最直接对应的 primary mechanism 是 interpretation ownership / key-distinction provenance；state self-compassion、reactance、perspective shift 和 felt understanding 是体验结果。

当前两条件 study 不能单独识别 contextual data 的因果效果。数据应作为两个条件共享的 cross-cutting contextualization policy，并以行为日志、量表和访谈回答它在不同阶段的作用。如果论文要把 contextual data 的独立因果效应列为核心 contribution，需要额外的 context-on/context-off 操作或 2×2 study。

---

## 1. Paper 的中心论证

### 1.1 问题范围

本项目研究的不是“AI 能否让人感觉更好”，而是：

> 当用户因一次具体事件进行自我批评时，AI 如何在不迎合、也不越权判断的情况下，帮助用户形成一种更完整、更可行动的 self-compassionate account？

一个完整的 account 至少同时容纳：

- 当时的痛苦、需求和真实限制；
- 情境因素，但不把数据误当因果；
- 用户实际拥有和不拥有的控制；
- 行为可能造成的影响；
- 可选择的边界、修复或下一步；
- 对不确定性的保留。

### 1.2 设计 gap

纯文本 LLM 在这里同时承担提问者、解释者和评价者，因而容易落入两个极端：

| 极端 | 用户可能获得什么 | 设计风险 |
|---|---|---|
| 只安慰、只认可 | 即时的被支持感 | 附和未经核验的叙事；回避行为、影响和选择 |
| 模型直接指出问题 | 清晰、强烈的建议 | 模型越过认识边界；引发防御、抗拒或被误解 |

卡片的作用是改变 **谁提出关键解释、解释如何被提出**：

- 模型不直接说“你是在逃避”；
- 用户可以先描述“画面里的人似乎停在门口”；
- 用户再决定这是否与自己的犹豫、休息、边界或其他经验有关；
- 模型只对用户已经提出的连接进行 tentative reflection；
- 用户始终可以修改或拒绝。

但当前 direct condition 本身也被设计成 user-led、tentative 且支持拒绝。因此现有代码对应的严谨比较不是“好卡片 vs 坏 chatbot”，也不能直接证明 card 解决了 model assertion。它检验的是：

> 在相同的 disclosure、context、Tender baseline 和 closure 下，增加一个随机的第三物、用户先行的图像叙事和可协商的 card reading，是否比单纯的开放文本反思更能让关键新理解由用户形成，并带来 perspective shift，同时不增加 reactance 或损害 state self-compassion？

这使“existing chatbot 为什么不够”的答案更准确：纯文本对话即使写得很好，问题空间和候选 distinction 仍主要由模型的语言组织；它缺少一个独立、随机、允许投射和拒绝的 shared object。卡片是否真的改善 interpretation ownership，需要 Study 1 验证，不能在引言中预先当作结论。

### 1.3 可主张的三类 contribution

#### C1. Interaction design contribution

提出并实现 contextualized projective scaffolding：将可确认的个人情境 cue、chance-drawn ambiguous card、user-first interpretation 和 user-confirmed narrative 组合为一个由 Swift 状态机约束的反思流程。

#### C2. Artifact / design-method contribution

提出一套针对反思卡的 ambiguity calibration 方法：同时评估视觉可读性、解释开放性、效价分布、文化 schema、关系/行动 affordance 和安全性。只有在 Study 0 完成并报告迭代证据后，这一项才足以成为独立 contribution。

#### C3. Empirical contribution

通过两周 crossover deployment，说明与 active direct-text reflection 相比，卡片中介如何影响：

- 用户对关键理解的 ownership；
- 关键 distinction 首先由 user、card relation 还是 model wording 引出；
- session-level state self-compassion；
- reactance / epistemic overreach；
- perspective shift；
- contextual cue 的相关性、意外性、帮助与侵扰感；
- 用户何时接受、修改、拒绝或无法连接一张卡。

### 1.4 当前不应主张的内容

- 不声称系统诊断用户为何状态不好。
- 不声称睡眠、日程、天气或屏幕时间导致了某个行为。
- 不声称“随机卡片揭示了潜意识真相”。
- 不声称所有 wellbeing chatbots 都只会 sycophancy。
- 不声称 tender/fierce 是两个已验证且可独立测量的心理变量。
- 不声称当前两条件 study 能识别 contextual data 的独立因果效果。
- 不声称 22 张卡已经验证可用；现有材料只有设计审计，没有用户 pilot 证据。

---

## 2. 精确的交互流程与每一步依据

### 2.1 当前代码的控制结构

新 session 使用 `protocolVersion = 2`。代码把交互分成两个不同责任层：

- `ReflectionProtocolController` / Swift：控制合法 stage、条件分流、tracking/card 本地 action、confirmation object、最多一次 card scaffold、最多两次 connection invitation、最多一次 Fierce/candid question、practice 后才能完成。
- LLM TurnPlanner + Writer：根据用户刚才实际回答的内容，决定下一句的语义功能和自然语言措辞；它可以提出 semantic understanding，但不能选 condition、选牌、绕过 confirmation 或直接完成流程。

当前 coarse protocol 是：

```text
contextualDisclosure
  → tenderConfirmation
  → cardConsent → cardReflection ┐
  └────────────────→ directReflection
                               ↓
                    narrativeConfirmation
                               ↓
                        optionalAction
                               ↓
                            complete
```

安全风险可以从任何未完成阶段进入 `safetySupport`。这张图只表示应用控制的边界；普通 disclosure、tracking relationship 和 card meaning 仍由对话内容决定，不是固定问卷。

### 2.2 两个条件共享的 grounding

| 当前阶段 | 代码实际要求 | 设计功能 | 不能据此主张 |
|---|---|---|---|
| Adaptive disclosure | 形成一个“足够清楚的现实故事”：发生/反复发生什么、用户怎样理解、体验、为何重要及一个有意义的影响；没有固定顺序，也不要求逐字段提问 | 把 global self-judgment 重新锚定到具体 episode 和关系 | 不是临床 intake，也不是 emotion checklist |
| Tracking opportunity | 如果存在可用的 cleaned cue，在进入 Tender summary 前必须至少提供一次机会；可选最小 coherent bundle，当前上限为 4 条 | 把近期状态放到具体反应旁边，检查 before/during/after 与可能参与方式 | 记录不证明情绪、原因、能力、回避或责任 |
| Tracking negotiation | 用户将已展示 cue 判断为 related / partly related / unrelated / uncertain；不相关或不确定后不得继续追问同一关系 | 让用户决定数据是否成为其 lived experience 的一部分 | 系统不是因为“算出来了”就拥有解释权 |
| Tender summary | 把事件、体验、限制以及用户确认或限定的 tracking relationship 写成一个可修改的整体理解 | 建立两个条件共享的 self-compassion baseline | 不能提前减责、分责、给 action 或 card meaning |
| Tender confirmation | 用户接受、修改或拒绝 summary；只有确认后才按 condition 分流 | 明确 baseline 是共同且用户确认的 | 不能把用户的沉默当作确认 |

这说明当前代码不是“先独立展示 data，再开始 reflection”。Tracking 被设计成现实故事中的一条 strand；最终在 Tender summary 中与事件关系一起确认。

### 2.3 Card-mediated condition：当前真实顺序

| 顺序 | 当前代码中的 interaction contract | 对 contribution 的意义 |
|---|---|---|
| 1. Card consent | 说明卡片由本地随机抽取并询问是否愿意抽；拒绝则进入 direct reflection | chance 是设计属性，但不强迫使用 |
| 2. Local draw/display | Swift 本地随机抽卡；图片成功显示后才出现第一句 card question | 模型不能根据用户情绪、数据或路线挑牌 |
| 3. Observation | 直接问画面中正在发生什么，不给标题牌义、不解释 symbol | 用户先提供视觉证据 |
| 4. Image development | 最多一个普通的关系发展问题，例如接下来可能发生什么；只能沿用用户已经命名的对象、动作或关系 | 形成 user-authored image relation，而不是让模型讲牌 |
| 5. Optional life connection | 邀请用户把该关系与已经确认的现实处境连接；“想不到/不相关”是完整答案 | 投射是邀请，不是必须完成的测试 |
| 6. Bounded scaffold | 第一次连接困难时，最多一次、且只能基于用户已说出的 visual anchors；之后最多再邀请一次现实连接 | 校准 ambiguity，而不是通过连续追问强迫意义 |
| 7. Guidance authorization | 只有同时存在 user-authored image relation 与 reality mapping，系统才释放内部 card guidance | 牌义不能先于用户映射进入对话 |
| 8. Negotiated reading | 模型把图像关系、确认过的现实关系和确实重叠的 card guidance 写成一个 non-divinatory candidate reading | 系统贡献一个可讨论的新 distinction，而不是宣布真相 |
| 9. Mapping confirmation | 用户接受、修改或拒绝 reading；拒绝后清除 candidate，不再在 narrative 中使用 | interpretation ownership 在代码中有真实 gate |
| 10. Optional candid reflection | 进入 shared directReflection；只有存在具体行为/影响/边界/责任/保护/不确定性时才问最多一个问题 | Card 不直接决定 blame；完整 self-compassion 仍需现实证据 |
| 11. Final narrative | 以确认过的 card distinction 为唯一组织线索，只写超出 Tender baseline 的 delta；用户再次确认 | 避免把 disclosure、data、card 和理论机械拼接 |
| 12. Optional practice | narrative 确认后，助手提出一个最有证据支持的 care / repair / protect / change practice；用户可修改、拒绝或暂缓 | action 与 interpretation 分开，不由 card symbol 直接推出 |

因此，当前代码中的 card contribution 不是“chatbot 给出卡片，然后用户随便解释”。更准确的说法是：

> **user-first image relation → optional image-to-life mapping → bounded candidate reading → explicit negotiation → reality-based candid reflection**

### 2.4 Direct-text active baseline：当前真实顺序

当前 direct condition 与 card condition 共享全部 grounding。在 Tender summary 确认后，它静默进入 `directReflection`：

1. Planner 判断是否存在一个既有证据、当前也有用的 candid distinction；
2. 若有，只问最多一个聚焦问题，可涉及：
   - 具体行为与影响；
   - 反复且有代价的反应；
   - 边界或保护；
   - 具体事件与 whole-person judgment 的区别；
   - 用户已表达的 repair/change readiness；
   - 仍需保留的不确定性；
3. 若无、用户不愿继续、主要是不可控损失或已经足够清楚，直接进入 final narrative；
4. narrative 同样由用户确认，之后同样给一个 optional practice。

所以 baseline 应正式命名为 **active direct-text reflection**。代码中的 persisted value `modelAsserted` 是 legacy wire value，不能用来描述参与者实际体验。

### 2.5 当前 manipulation 到底是什么

| Shared in both conditions | Added only in card condition |
|---|---|
| adaptive disclosure | local chance draw |
| negotiated contextual data | visible ambiguous third object |
| user-confirmed Tender baseline | user-authored image relation |
| optional one candid question | optional image-to-life mapping |
| final narrative confirmation | bounded card guidance |
| one optional practice | negotiated card reading |

因此研究可以检验 **card-mediated negotiated interpretation as a whole package**，不能声称只隔离了图片视觉刺激，也不能说比较的是“温和 vs fierce”或“chatbot vs card”。Card path 的 turn 数和时长天然更多，必须记录并报告。

### 2.6 Context 在 card path 中的具体融合点

代码已经提供了一个合理的次序：

1. Context 先在现实故事中被用户确认；
2. 确认后的关系进入 locked Tender baseline；
3. Card observation 和 image development 仍保持 image-only，不用数据解释画面；
4. 到 life connection / candidate reading 时，模型可将用户确认过的现实条件作为 reality side；
5. 后续 candid question 中，context 只能让问题更现实、更温和，不能决定 responsibility；
6. final narrative 不再重复 metric，而只保留它对现实 distinction 必要的部分。

这与“睡眠不好时提醒用户观察近期状态”的想法一致，但多了一道必要的用户确认：系统不能直接说睡眠解释了失败，而应先问该状态是否在事件当时存在、是否可能让某个具体反应更难。

### 2.7 出现负面 card interpretation 时，当前系统应怎样理解

当前代码没有、也不应建立一个 `negative interpretation → correction` 状态。负面不等于错误；真正需要检查的是解释来源和形式：

1. 是否来自用户实际描述的 image relation；
2. 是否被错误升级成 whole-person judgment、固定牌义、诊断或命运；
3. 是否与用户确认的现实关系有连接；
4. candidate reading 是否允许接受、修改、拒绝；
5. 是否存在具体行为/影响/边界，足以支持一次 candid question；
6. 如果没有，保留 Tender 或 uncertainty，直接进入 narrative。

例如用户把画面读成“这个人就是失败了”，系统不必强迫他说积极解释；它可以回到具体画面和现实关系，区分“某件事没有完成”与“整个人是失败者”。如果用户认为负面理解准确，final narrative 可以保留困难和后果，但不能把 card 当作证据进一步加重自我定罪。

### 2.8 推荐修改：Context 不是固定阶段，而是贯穿式 policy

不建议把 tracking/context 固定成一个单独的 `ContextBridge` stage。固定节点虽然容易画实验流程，却会让数据变成一次性的插入模块，不能表达真正的 **contextualized reflection**。

更合理的目标是：

> Contextual data 是贯穿反思过程的背景候选；系统可在不同阶段决定是否提出或引用，但必须受到当前阶段目标、数据质量、与用户叙事的可能相关性，以及用户解释权的共同约束。

Context 因而有两种不同身份：

1. **Available contextual candidate**：本地已经计算、可能与当前反思有关，但用户尚未确认；只能被系统以不确定问题提出，不能进入解释或结论。
2. **User-confirmed contextual relation**：用户已经确认、限定或重新解释其与事件的关系；可在后续 card mapping、Tender/Fierce synthesis、narrative 和 action sizing 中继续使用。

推荐流程中不出现独立 context stage：

```text
self-critical episode
→ adaptive grounding
→ card/direct perspective formation
→ negotiated interpretation
→ Tender + conditional Fierce integration
→ final narrative
→ optional practice

Context policy 贯穿上述全过程：
在需要时提出 candidate → 用户确认/限定/拒绝 → 后续只使用确认部分
```

### 2.9 各阶段 context 的不同作用

| 反思阶段 | Context 可以做什么 | Context 不能做什么 |
|---|---|---|
| Event disclosure | 当用户描述容量、时间或状态困难时，提出一个最相关 cue，帮助定位 before/during/after；也可以完全不出现 | 以数据报告开场；从记录推断用户情绪、动机或原因 |
| Self-criticism clarification | 帮助检查 global judgment 是否忽略了现实条件，例如“当时是否比自己的平时更疲惫” | 用疲惫自动推翻用户承认的行为或影响 |
| Card observation / image development | 通常保持静默，保护 image relation 的独立来源 | 用睡眠、日程等数据解释画面或提示用户应该看见什么 |
| Image-life connection | 如果用户的 image relation 与某个 candidate cue 形成可能联系，可以提出一个 tentative question；也可等用户先自行连接 | 为了让 card 显得准确而强行套用 cue |
| Negotiated card reading | 使用 user-confirmed context 使 reading 落回真实处境；保留 context 和行为/影响两边 | 使用未确认 cue；把 context 说成 card 揭示的真相 |
| Tender synthesis | 用确认过的 context 理解痛苦、需要、容量和现实限制 | 直接减责、免责或把困难等同于无能为力 |
| Fierce/candid reflection | 帮助把 agency 设在现实容量内，并区分可控、不可控、边界和修复 | 用数据分配责任；因为某项指标变化就要求休息、运动或提高效率 |
| Final narrative | 只保留对核心 distinction 必要的已确认 context，不重复指标 | 把 session 写成 event + metrics + card 的字段拼接 |
| Optional practice | 调整行动大小、时机或负担，例如把一步做得更现实 | 单凭 tracking cue 生成健康或生产力处方 |

这个设计保留了两个重要边界：

- **Context can be consulted throughout, but not silently converted into truth.**
- **The user confirms the relationship once; later turns may carry that confirmed relationship forward without repeatedly询问。**

### 2.10 Context 的状态而不是 stage

实现和研究记录应追踪 cue 的 epistemic status，而不是只记录“是否经过 ContextBridge”：

```text
available
→ surfaced_as_candidate
→ related / partly_related / unrelated / uncertain
→ incorporated / not_incorporated
```

- `available`：本地存在，但尚未进入对话；
- `surfaced_as_candidate`：在某个阶段以不确定问题出现；
- `related`：用户确认具体关系，可进入后续 prompt；
- `partly_related`：只保存用户限定后的版本；
- `unrelated`：后续不再使用；
- `uncertain`：不能作为解释性事实，可保留“不确定”本身；
- `incorporated`：记录它实际进入了 card reading、Tender/Fierce、narrative 或 practice 的哪一部分。

这种设计比单一 context stage 更能回答研究问题：不是只问“数据有没有出现”，而是分析 **它在什么时候、以什么功能、经过怎样的用户协商，改变或没有改变反思**。

### 2.11 两个 experimental conditions 如何保持可比

两个条件都遵守同一 contextualization policy，但 context 不必机械地出现在同一个 turn：

- Card condition：可在 disclosure、image-life connection 或 negotiated reading 的现实侧提出；
- Direct condition：可在 disclosure、textual perspective formation 或 negotiated direct interpretation 中提出；
- 两组都禁止在 image/text perspective 形成之前，用 context 直接给出最终解释；
- 两组都只把 user-confirmed relation 带入 Tender/Fierce 和 final narrative。

Study 比较的是 card 是否改变 perspective formation 和 interpretation provenance，而不是把“固定时点出现的数据”当作控制变量。分析时需要记录 context 出现阶段，并检查两条件的 exposure frequency 和 function 是否失衡。

---

## 3. Contextual data 在系统中的角色

### 3.1 角色定义

Contextual data 不是：

- 诊断引擎；
- card selector；
- 判断用户责任的证据；
- 用来制造“AI 神秘地知道我”的隐藏 prompt；
- 一个独立于反思流程的 dashboard。

它是：

> 一个有限、可检查、可拒绝的 attention cue，帮助用户回看当时可能被自我批评叙事忽略的现实状态。

### 3.2 为什么必须透明，而不能在后台悄悄使用

“占卜者似乎知道我的近况”可以作为最初的 design inspiration，但不应成为实际交互的隐蔽机制。隐藏使用个人数据会带来三个问题：

1. 用户无法判断模型的推断来自哪里；
2. 错误或缺失数据会被误认为系统对自己有深刻理解；
3. surprise 很容易转化为 surveillance 或 creepiness。

因此，预期的 serendipity 应来自“一个真实但此前未被注意的连接”，而不是来自不透明的数据使用。Serendipity 可探索性地拆成：

- relevance：和当时经历是否有关；
- unexpectedness：是否提供未想到的角度；
- enrichment：是否帮助形成更有用的理解；
- intrusiveness：是否感到越界、被监视或不舒服。

不要把 serendipity 直接当作已成立的设计效果；它需要数据支持。

### 3.3 数据进入对话的 capability rule

数据不绑定某一个 stage，但任何阶段都遵守同一门槛：

```text
本地清洗与个人基线计算
  → 形成 bounded candidate pool
  → 当前阶段是否存在一个 context 可以完成的合法功能？
  → 若有，只提出最小 sufficient cue 和一个可拒绝的问题
  → 用户判断 related / partly related / unrelated / uncertain
  → 后续只携带用户确认或限定后的关系
```

“合法功能”必须与当前反思目标一致，例如：

- 澄清事件当时的容量或时间关系；
- 检查一个 global self-judgment 是否遗漏现实条件；
- 为用户已经形成的 image-life relation 增加一个可检验背景；
- 让 Tender understanding 更具体；
- 让 Fierce/action 保持在用户现实容量内。

以下理由不能触发 context：

- “已经很久没展示数据了”；
- “每次 session 都应该使用 tracking”；
- “这个 cue 可以让 card 看起来更准”；
- “模型需要更多信息”；
- “指标异常，所以用户应该讨论它”。

不确认的数据不能进入后续归因。`unrelated` 后必须停止使用；`uncertain` 可以作为不确定性被保留，但不能变成解释性事实。参与者必须预先知道系统可能在反思的不同位置提出经过清洗的 context cue。

### 3.4 示例

不推荐：

> 你最近睡眠不足，所以你没做好并不是你的能力问题。

如果在事件澄清阶段提出，可以说：

> 过去 7 天的可用记录里，你的睡眠时长比自己的近期基线少一些；其中也有缺失记录，而且它不能说明这件事为什么更难。你觉得休息状态当时有影响吗？

如果此时没有必要，系统可以完全不提。Card observation 阶段继续保持 image-only。用户稍后自己形成 image-life relation 后，也可以在这一关系上提出：

> 你刚才把画面理解成“还在用力，但能调用的东西越来越少”。近期记录里有几晚休息比自己的平时少一些。你觉得这个背景和当时推不动项目有关系吗？没有或不确定也可以。

用户确认后，negotiated reading 可以继续携带这层关系，但不能把它变成 card 的固定意义：

> 一种可能的理解是：项目没有进展是真实的，但“推不动”未必只说明能力不足，也可能和当时可调用的精力比平时少有关。你提到的安排问题仍然需要保留。这个说法符合你吗？

在 optional practice 中不必再次展示睡眠数据，只能用用户已经确认的容量关系调整行动大小：

> 如果你想做一点改变，可以先把下一次任务拆成一个在当前精力下能完成的准备步骤；也可以暂时不定行动。

### 3.5 数据最小化

- Swift 本地计算清洗后的 daily summaries 与个人 baseline。
- 缺失数据保留为 missing，不转成 0。
- 不向 LLM 发送 raw HealthKit、EventKit、screen-time 或天气样本。
- 每次使用最小 sufficient bundle；虽然当前代码允许最多 4 条，但 pilot 应检查 1–2 条是否已足够，避免形成 data report。
- 记录 cue category、窗口、可用性和用户确认结果，不记录不必要的原始值。
- 只有获得单独同意时，研究数据库才保存去标识化 transcript；健康原始记录不进入 transcript。

### 3.6 每个 turn 的 context decision policy

“Context 可以贯穿”不等于 LLM 可以随时自由引用数据。每个 turn 应按同一顺序判断：

```text
1. 当前 reflection function 是什么？
2. 是否存在达到质量门槛的 contextual candidate？
3. 这个 cue 是否能完成一个尚未完成、且会实质改变理解的功能？
4. Cue 是否已经被用户判断过？
5a. 未判断：最多提出一个 tentative relationship question
5b. related / partly related：只携带用户确认或限定后的 relationship
5c. unrelated：禁止再次引用
5d. uncertain：保留不确定，不把它写成解释
6. 当前 reply 是否真的需要提到它？不需要则保持背景静默
```

建议把这些约束做成 typed context interface，而不是只写在长 prompt 中：

- `cueStatus`: available / surfaced / related / partlyRelated / unrelated / uncertain；
- `firstSurfacedFunction`；
- `userConfirmedRelationship`；
- `allowedUses`: clarifyTiming / clarifyCapacity / contextualizeMapping / tenderSynthesis / sizeAgency / sizePractice；
- `prohibitedUses`: inferEmotion / inferCause / assignResponsibility / selectCard / diagnose；
- `incorporatedUses`。

Context Analyzer 可以建议候选关系和 allowed use；Swift 验证 cue 状态、是否重复、是否已被拒绝以及当前 stage 能否使用。Dialogue Writer 只负责把已经获准的功能写成自然语言。

### 3.7 如果 contextual data 必须成为独立 causal contribution

当前 card vs direct 的两条件 crossover 中，两个条件都使用 context，因此只能回答“用户怎样使用和体验 context”，不能回答“context 是否导致 outcome 改变”。

若必须回答后一个问题，可新增：

| 方案 | 设计 | 优点 | 代价 |
|---|---|---|---|
| 2×2 factorial | card / direct × context / no-context | 同时估计两个主效应与交互 | 需要显著更大样本；四种体验和 carryover 更复杂 |
| Session-level micro-randomization | 在有合格 cue 的 session 随机显示或不显示 | 更贴近日常使用；可分析即时效果 | 只有部分 session 有合格 cue；统计和解释更复杂 |
| 单独 lab study | 对固定 vignette 操作有/无 context | 控制强、成本较低 | 外部效度较弱，不等于真实个人数据体验 |

本轮推荐先不扩成 2×2：将 context 作为必要但保守的 design component，用 Study 1 的日志与访谈建立机制证据，再决定是否单独验证。

---

## 4. Reflection card 的 redesign、rationale 与验证

### 4.1 设计目标

目标不是复刻 Tarot，也不是让用户猜设计师设定的“正确含义”。每张卡需要落在一个 **bounded ambiguity window**：

- 足够具体：用户能指出人物、物体、关系、动作或空间变化；
- 足够开放：不同用户能形成多个合理解释；
- 不依赖标题、牌义或 Tarot 文化知识；
- 不预设善恶、命运、人格或诊断；
- 可以承载对处境的温和理解，也可以承载边界、选择或修复；
- 不强迫用户把图像与自己连接。

### 4.2 当前代码对每张卡提出的功能要求

当前 card object 不只是图片；它包含 `coreTension`、`tenderLenses`、`fierceLenses`、`visualAnchors`、`possibleDirections`、`prohibitedClaims`、三维 self-compassion candidates 和可选 `visualScaffolds`。这些内容只有在用户先形成 image relation 和 reality mapping 后，才可成为 candidate reading 的 bounded guidance。

所以 card pilot 不能只测“这张图好不好看/能否解释”，还需要验证整条 interaction：

| 代码中的功能 | Card design / pilot 必须回答 |
|---|---|
| Observation | 不看标题时，用户能否说出一个关系、动作或正在发生的场景？ |
| One image-development turn | 一次开放追问能否让关系变得更具体，而不需要模型补人物动机？ |
| Optional scaffold | scaffold 是否只依赖明显 visual anchors？是否真的帮助继续观察，而不是偷渡牌义？ |
| Life connection | 用户能否自然地选择连接或不连接？连接来自什么视觉关系？ |
| Guidance overlap | internal tension 是否能与多种 user-authored reading 对话，而不是覆盖它？ |
| Negotiated reading | candidate reading 是否新增一个有用 distinction？用户为何接受、修改或拒绝？ |
| Tender/Fierce directions | 两类 lens 是否都是 candidate space，而不是把任何用户引到同一套“休息/行动”结论？ |
| Prohibited claims | 是否仍会诱发命运、诊断、固定性格、受害者责任或道德惩罚？ |

这也意味着 card redesign 的评价对象应包括 **image + prompt/scaffold + internal guidance + negotiated reading**，而不只是静态插画。

### 4.3 应沿哪些维度设计和报告

| 维度 | 设计问题 | 失败表现 |
|---|---|---|
| Scene legibility | 不看标题能否说出发生了什么 | “不知道这是什么”占比高 |
| Interpretability | 用户能否开始讲述 | 长时间无从下手、只能复述物体 |
| Openness | 是否允许多种合理阅读 | 所有人给出同一个固定寓意 |
| Valence plurality | 是否可有温和、困难、中性或行动性阅读 | 绝大多数只能读成失败、危险或惩罚 |
| Relational/action affordance | 是否能谈关系、位置、选择、动作或边界 | 只能形容审美，无法连接经验 |
| Schema neutrality | 是否过度触发 Tarot、宗教、职业或文化定式 | 不懂特定文化就无法解释 |
| Non-diagnostic safety | 是否暗示病理、罪责、死亡或受害者责任 | 图像对脆弱用户造成不必要伤害 |
| Visual distinctness | 卡与卡之间是否具有不同张力 | 多张卡产生同一类故事 |
| Accessibility | 小屏、色觉差异、语言无关观察是否可行 | 关键线索只靠颜色或小字 |

### 4.4 可追溯的设计过程

论文应为每张卡保留一行 design ledger：

```text
card_id
working title（不一定展示给参与者）
visual scene
intended tension，而非固定含义
至少 3 个相互不同的 plausible readings
可能的负面/文化 schema
从上一版修改了什么、为什么
pilot 指标与 qualitative flags
最终 retain / revise / remove
deck_version
```

现有 `card内涵.docx` 已经记录了核心张力、温和/行动性方向、画面和模糊性，这是 design ledger 的起点；但它是设计意图，不是用户可解释性的证据。

### 4.5 Study 0A：expert/design audit

建议 3–5 位 reviewer，至少覆盖：

- HCI / interaction design；
- self-compassion 或 counseling 相关研究；
- 跨文化视觉传播；
- accessibility / safety。

任务：

- 按上述九个维度独立标记；
- 找出伤害、污名、固定寓意和文化依赖；
- 检查卡片是否不当地暗示责任或因果；
- 先独立判断，再讨论，不用共识掩盖分歧。

输出不是效度证明，而是进入用户 pilot 前的 safety/design gate。

### 4.6 Study 0B：cognitive interviews

建议 `n = 12`，有不同 Tarot 熟悉度、视觉表达习惯和文化背景。

每人盲测 6–8 张卡：

1. 不显示标题与设计说明；
2. “先说你看到了什么”；
3. “你觉得正在发生什么？”；
4. “还可能有另一种解释吗？”；
5. 给一个轻量 self-critical vignette，问是否以及怎样连接；
6. 询问哪里太明显、太模糊、太负面、令人不适或像既有符号；
7. 让用户指出他们依赖的具体视觉线索。

重点不是收集漂亮故事，而是发现 misunderstanding、blank response、fixed schema 和 harm。

### 4.7 Study 0C：quantitative calibration

推荐 balanced incomplete block：

- `n = 48`；
- 22 张卡；
- 每位参与者随机看 11 张；
- 总计 528 次 card-rating；
- 每张约 24 个独立 rating；
- 卡片顺序随机，始终盲去标题、牌义和设计目标。

每张卡收集：

- concrete scene/action 能否被描述；
- interpretation ease，1–7；
- openness / “可以有不止一种合理理解”，1–7；
- valence，-3 到 +3；
- emotional discomfort，1–7；
- Tarot / 文化符号识别及其含义；
- 至少一个主要 reading；能否给第二种不同 reading；
- 对 vignette 的 connection ease 与 connection type；
- “不知道 / 无法连接”选项。

### 4.8 Study 0D：interaction pilot

静态 calibration 之后，再用轻度 self-critical vignette 或参与者自选的低风险真实事件测试当前代码对应的 card path。建议 `n = 12–16`，每人体验 2–3 张不同卡：

- first observation 是否无需解释就能开始；
- 一次 image-development question 是否足够；
- 首次 life connection 的形成率；
- soft no-connection 后 scaffold 是帮助观察，还是暗示了意义；
- candidate reading 新增了什么 distinction；
- reading 的 accept / revise / reject；
- 是否感到理解主要由自己形成；
- 是否出现“系统在用牌判断我”的体验；
- no-connection 后回到 direct reflection 是否自然；
- 整段额外需要多少 turn 和时间。

Card design 的最终迭代应同时参考静态分布与这段 interaction evidence。某张卡即使静态解释丰富，如果经常需要系统 bridge、容易让 reading 变成固定牌义，仍不适合进入 study deck。

### 4.9 预注册的 card gate

以下是本项目可采用的 **设计阈值**，不是声称存在普适心理测量标准：

- 至少 80% rating 能给出可识别的 scene/action；
- blank / “不知道”不超过 15%；
- interpretability 中位数至少 5/7；
- openness 中位数落在 4–6/7，避免过度封闭或完全无结构；
- qualitative coding 至少出现 3 个不同 reading family，且每类至少约 15%；
- 单一 reading family 不超过 60%；
- strongly-negative-only reading 不超过 35%，否则进入重点复核；
- 固定 Tarot / 文化 schema 驱动的解释不超过 20%；
- 无 unresolved severe harm、污名或 stereotype flag；
- 关键视觉线索不只依赖颜色和细小文字。

两名 coder 在不知道设计意图的情况下编码 reading family、valence source、agency/circumstance/boundary 等类别；报告 Cohen’s kappa 或 Krippendorff’s alpha、分歧处理方法和 codebook 版本。

未达 gate 的卡：

1. 根据失败维度修改；
2. 以新 card version 重新测；
3. 仍失败则移除；
4. 不以“它本来就很抽象”解释失败。

### 4.10 Deck-level gate

单卡通过还不够，整副牌还需要：

- valence 分布不过度集中在负面或安慰；
- 不同关系结构、行动 affordance 与空间张力有覆盖；
- 视觉上容易区分；
- 随机抽到任何一张都满足最低安全和可解释要求；
- 研究开始后冻结 deck，不在参与者之间悄悄换图。

### 4.11 Study 中的 card no-connection / retry

当前代码允许一次普通 connection invitation；第一次软性“想不到”后最多使用一次 scaffold 并做最后一次 connection invitation，之后就放下该卡。正式 protocol 应保留这个边界：

- 这是 interpretation agency 的一部分，不应算失败；
- 记录 first-attempt connection、scaffold use、second-attempt connection、explicit no-connection 和 decline；
- primary analysis 保持 assigned condition；
- sensitivity analysis 可区分 first-card accepted 与未接受；
- 不允许模型根据用户状态挑一张“更合适”的卡。

当前代码的核心 fallback 是 **leave the card aside and continue direct reflection**，并不是自动重抽。若研究中允许 redraw，就会改变现有 manipulation 和 exposure，应作为明确的 protocol revision，而不能临时加入。

---

## 5. Research Questions 与 hypotheses

### RQ1：关键理解的来源与所有权

与 active direct-text reflection 相比，card-mediated reflection 是否更容易让 session 中最重要的新 distinction 首先由用户的 image relation / life mapping 形成，而不是由模型直接组织？

**H1a**：card condition 的 post-session interpretation ownership 更高。  
**H1b**：在 transcript coding 中，card condition 有更高比例的 core distinction 可追溯到模型 formulation 之前的 user-authored image/reality relation。  
**H1c**：card condition 的 perceived epistemic overreach 更低。

这是与 contribution 最直接对应的 primary mechanism RQ。只测“用户有没有更舒服”而不测 interpretation provenance，无法证明 projective scaffolding 实际发生。

### RQ2：反思结果

两种条件如何影响 perspective shift、state self-compassion、felt understanding 和 state reactance？

**H2a**：card condition 的 perspective shift 更高。  
**H2b**：interpretation ownership 与 state self-compassion change 正相关。  
**H2c**：card condition 不会因为更开放或更 candid 而产生更高 reactance。

是否预注册 “card condition 的 state self-compassion change 更高” 应由 interaction pilot 的 effect estimate 和 paper 最终主张决定。当前代码中的 direct baseline 本身已经包含 Tender 与 autonomy support，因此没有充分依据预设它必然在 state self-compassion 上更差。

### RQ3：完整但不自我攻击的反思

两个条件形成的最终叙事是否都能够同时容纳 circumstances 与 agency / boundary / repair，而不是停在 global self-blame 或无条件免责？Card condition 是否通过不同的 provenance 达到这一结果？

这是 mixed-method RQ，不建议只用一个未经验证的“责任分数”回答。

### RQ4：contextual cue

Contextual cue 在反思的不同阶段承担了什么功能？用户何时认为它准确、相关、意外且有帮助？何时觉得出现过早、打断反思、不相关、侵扰或像系统在替自己解释？

当前设计对这一题提供过程与体验证据，不提供 context 的独立 causal estimate。

### RQ5：卡片机制与失败方式

哪些图像特征帮助用户形成新的连接？何时卡片太明显、太开放、太负面、文化负载过强或完全无法连接？

### 5.1 RQ → evidence 对照

| RQ | 不能只靠什么回答 | 需要的主要 evidence |
|---|---|---|
| RQ1 ownership/provenance | 满意度或 SSCS | ownership items；turn-level transcript provenance；mapping accept/revise/reject |
| RQ2 reflection outcomes | interview preference | pre/post SSCS-S；state reactance；perspective shift；felt understood |
| RQ3 self-compassionate candor | 单一“责任感”题 | final narrative coding：circumstance、specific behavior、impact、agency/boundary/repair、global judgment、uncertainty |
| RQ4 context | cue 是否被展示 | typed relevance；timing/effect relation；usefulness/unexpectedness/intrusiveness；访谈 |
| RQ5 card mechanism/failure | 平均喜欢程度 | observation/connection/scaffold logs；card-level reading codes；no-connection；accept/revise/reject；访谈 |

---

## 6. Study 1：两周 counterbalanced crossover deployment

### 6.1 设计

- 两个条件：`card-mediated reflection` 与 `active direct-text reflection`；
- 每位参与者体验两个条件；
- 顺序随机为 AB 或 BA；
- 每个条件 1 周、2 次 session；
- 两次 session 至少间隔 24 小时；
- 条件切换尽量留出 48 小时；
- 每人共 4 次正式 session；
- 每次选择一个近期、具体、非危机性的 self-critical episode；
- 所有条件共享同一 context policy。

若采用贯穿式 contextualization，正式 study protocol 应对应目标交互，而不是把 context 画成固定一步：

```text
pre-session measure
→ adaptive grounding
→ assigned card/direct perspective formation
→ negotiated interpretation
→ Tender + at most one supported Fierce/candid distinction
→ user-confirmed final narrative
→ one optional practice / no-action
→ post-session measure

Contextual candidates remain available throughout.
Each surfaced cue must have a stage-specific function and user relevance decision.
```

Card condition 的 manipulation check 不是“看见图片”，而是是否实际经过 observation、image relation、optional reality mapping 和 negotiated reading。No-connection session 仍保留在 card assignment 中，但需单独记录实际 exposure。

两条件不要求 context 出现在完全相同的 turn，但需要共享相同的 cue eligibility、data-quality、confirmation 和 later-use rules。分析时报告：

- 每个条件有多少 session 实际 surface 了 cue；
- cue 首次出现在哪个 reflection function；
- 用户如何判断其关系；
- 确认后的 context 是否进入 reading、Tender/Fierce、narrative 或 practice；
- 两条件的 context exposure/function 是否系统性失衡。

### 6.2 样本量

建议按 primary within-person condition effect 做预注册 power simulation，模拟 session 嵌套于 participant、4 次重复测量和预期缺失。主要输入应来自 Study 0D / end-to-end pilot 中的 interpretation-ownership 方差、participant ICC、card no-connection rate 和 transcript provenance 分布，而不是只按 SSCS 估计。

在尚无 pilot ICC 和 effect size 时可用下列 planning target：

- 若只希望检测约 `paired d = 0.50`，约需 34 位 completer；按约 20% 流失招募 44 人。
- 更保守地针对 `paired d = 0.40`，约需 52 位 completer；按约 20% 流失招募 64–66 人。

**在 pilot 参数出现前，推荐 full-paper planning target 仍为招募 64 人、目标至少 52 位完成主要 post-session 数据；这是一项资源规划数，不替代最终 power justification。**

如果资源只能支持约 36 位 completer，应把研究明确写成 exploratory deployment，不宜依赖小的 condition effect 或 mediation claim。

### 6.3 访谈样本

不必对 52 人全部进行一小时访谈。建议：

- 所有人完成简短 exit survey；
- purposive sample `n = 24–30` 做 45–60 分钟访谈；
- 按条件顺序、效果高/低、card connect/no-connect、context accept/reject 和先前 Tarot/LLM 使用经验取样；
- 在达到主题信息充分性后停止，但报告停止规则，不只写“saturation”。

### 6.4 纳入与排除

纳入：

- 18 岁以上；
- 能以 study 使用语言完成对话和问卷；
- 近期有普通日常 self-critical experience；
- 能完成两周手机使用。

排除或转介：

- 当前急性危机或研究不适合的高风险状态；
- 将系统误解为临床治疗且不同意其研究定位；
- 无法给予知情同意。

退出不应影响补偿。安全筛查只用于安全与适配，不用于心理诊断或筛除“不理想”数据。

### 6.5 时间线

| 时间 | 活动 | 数据 |
|---|---|---|
| Enrollment | consent、demographics、技术熟悉度、Tarot/card 熟悉度、self-tracking 熟悉度 | baseline covariates；trait self-compassion 可选 |
| Training | 练习 session，不纳入 primary outcome | 理解检查、技术问题 |
| Week 1 / Session 1 | assigned condition | pre/post measures、日志、可选 transcript |
| Week 1 / Session 2 | 同条件，≥24h | pre/post measures、日志 |
| Week 1 end | condition survey | usability、burden、condition impression |
| Wash/switch | 尽量 48h | carryover check |
| Week 2 / Session 3 | 另一条件 | pre/post measures、日志 |
| Week 2 / Session 4 | 同条件，≥24h | pre/post measures、日志 |
| Week 2 end | condition survey + exit survey | preference、comparison、privacy、overall value |
| Final | purposive interview subset | mechanism、failure cases、context/card experience |

### 6.6 Training 的边界

Training 只教：

- 没有正确牌义；
- 可以描述、拒绝、修改或说“不相关”；
- context 不是因果判断；
- 系统不是治疗或占卜。

不能展示“理想的深刻解释”，否则会训练 demand characteristic。练习图不进入正式 deck。

---

## 7. Measures

### 7.1 Primary measure strategy

Contribution 同时包含一个 interaction mechanism 和一个 wellbeing outcome，因此 measurement 也必须有两层：

**A. Primary mechanism：interpretation ownership / provenance**

- post-session 3–4 item ownership measure；
- transcript-coded `core distinction source`；
- user、card relation、model formulation、context cue 或共同形成的时间顺序；
- card condition 中 mapping accept / revise / reject；
- “模型是否超出已有信息替我判断”的 epistemic-overreach item。

因为 ownership items 是 author-developed，正式 study 前必须做 cognitive interview、internal consistency 和 convergent/discriminant pilot。若 psychometric evidence 不足，不能把一个自制总分作为唯一 primary endpoint；应将 transcript provenance 设为共同的 primary process outcome。

**B. Primary experiential outcome：State Self-Compassion Scale – Short Form（SSCS-S，6 items）**

- 每次 session 前后各一次；
- instruction 锚定“刚才想到的这件具体事情”；
- 使用已授权、验证过的目标语言版本；若没有，按 translation/back-translation 与 cognitive debrief 流程处理；
- outcome 为 post–pre change，或以 post 为 outcome、pre 为 covariate。

SSCS-S 是为 repeated experimental assessment 设计的简短 state measure（[Neff et al., 2021](https://self-compassion.org/wp-content/uploads/2021/03/Neff2021State.pdf)）。不要自行只挑其中“温和”的题来构造 tender score。

若 preregistration 要求唯一 primary endpoint，优先选择与核心 claim 一致的 ownership/provenance；SSCS-S 作为关键 secondary outcome。若 paper 的主 claim 改成“改善 self-compassion outcome”，则反过来，但必须把 ownership 保留为预注册机制检验。

### 7.2 Secondary validated measure

**Salzburg State Reactance Scale（SSR）**

- post-session；
- 使用完整、获准的目标语言版本；
- 不自行翻译两三个题后仍称为 validated SSR；
- 若问卷长度过高，可在 preregistration 中把它降为特定 session 的 secondary measure，而不是无说明删题。

该量表用于评估当下的心理抗拒体验（[Sittenthaler et al., 2015](https://pubmed.ncbi.nlm.nih.gov/27453806/)）。

### 7.3 Author-developed mechanism / exploratory measures

这些题可以直接对应机制，但必须标为 author-developed，并先做 cognitive interview。只有完成预定 psychometric pilot 的 ownership scale 才能升级为 primary mechanism measure；其余仍为 exploratory。

**Interpretation ownership / epistemic agency，建议 3–4 items，1–7**

- “这次反思中的关键理解主要是我自己形成的。”
- “我可以拒绝或修改助手提出的理解。”
- “助手的总结忠实于我表达的意思。”
- “助手对我的情况作出了超出已有信息的判断。”（反向/overreach）

**Perspective shift，建议 2 items**

- “我现在能从一个和开始时不同的角度看这件事。”
- “这次反思让我注意到此前忽略的部分。”

**Self-compassionate candor / responsibility clarity，建议分开问，避免单一价值判断**

- “最后的理解承认了当时真实的困难和限制。”
- “最后的理解也保留了我可以选择、修复或设立边界的部分。”
- “我没有因为这次反思而更全面地否定自己。”

**Felt understood，1–2 items**

- “我感到助手理解了这件事对我的意义。”
- “助手的回应符合我实际表达的处境。”

这些题不是临床量表，也不能用默认中点代替未回答。

### 7.4 Card-only process measures

- card scene 是否容易看懂；
- 开放但不茫然；
- 与事件连接程度；
- 是否产生新角度；
- 是否过度负面；
- 是否触发固定 Tarot / 文化含义；
- 是否想拒绝或换卡；
- card familiarity。

### 7.5 Context-only process measures

每次 cue 后：

- data accuracy：记录是否看起来正确；
- relevance：relevant / partly / not / unsure；
- timing appropriateness：这个时刻出现是否自然、过早或打断反思；
- role clarity：它是在帮助观察，还是像在替用户解释；
- usefulness；
- unexpectedness；
- enrichment / perspective contribution；
- intrusiveness / creepiness；
- 是否改变对事情难度、控制或需求的理解。

没有 cue 的 session 记录 `no_eligible_cue`，不能给默认分。

Session 结束时还应问 context 的总体作用：

- 它在哪个时刻最有帮助或最打断；
- 它是否在后续被重复使用得过多；
- 用户是否仍能分辨“记录观察”“自己的解释”和“模型提出的联系”；
- 如果 context 没有出现，用户是否觉得系统仍能完成有意义的反思。

### 7.6 Weekly / condition-level measures

- usability：每个条件结束时使用 SUS 或事先选定的短量表；
- burden / emotional effort；
- perceived safety；
- willingness to use again；
- condition preference；
- 是否因前一周条件改变后一周的使用方式；
- 过去一周是否在 session 外继续想到卡片或系统提出的问题。

### 7.7 Baseline covariates

只收与分析有明确关系的少量变量：

- prior LLM wellbeing use；
- Tarot / projective card familiarity；
- comfort with visual interpretation；
- self-tracking experience；
- demographic variables required by the sampling argument；
- trait self-compassion 可作为描述性或预注册 covariate。

除非 RQ 明确涉及抑郁、焦虑或临床症状，不应为了“看起来全面”加入 PHQ/GAD。

---

## 8. Logging 与数据结构

### 8.1 每个 session 必须记录

**版本与实验元数据**

- participant pseudonymous ID；
- session ID；
- assigned condition；
- sequence、period、session index；
- app build；
- model identifier；
- prompt version；
- workflow/protocol version；
- deck version；
- card asset version；
- locale；
- session start/end、completion status。

**流程事件**

- stage enter/exit timestamp；
- user/assistant turn count；
- LLM retry、validation failure、fallback；
- safety transition；
- user quit / timeout / technical failure。

**Context**

- cue available / unavailable；
- cue category 与时间窗口；
- missingness / quality flag；
- presented / not presented；
- first surfaced stage / response function；
- why surfaced：capacity/timing、self-judgment clarification、image-life relation、Tender grounding、agency sizing 等；
- relevant / partly / not / unsure；
- whether allowed into later prompt；
- incorporated into card/direct interpretation、Tender、Fierce、narrative、practice 的位置；
- repeated reference count，避免同一 cue 被反复当作新发现；
- 不记录 raw HealthKit/EventKit samples。

**Card**

- randomization event；
- card ID 与 deck version；
- asset successfully displayed；
- observation entered；
- connection / no connection；
- mapping accept / revise / reject；
- scaffold used / card set aside / decline；
- card path completion。

**Narrative/action**

- narrative offered；
- accept / revise / reject；
- action offered；
- accept / modify / decline；
- session completion。

**Measures**

- survey displayed、submitted、skipped；
- missing item 应为 null；
- completion timestamp；
- instrument language/version。

### 8.2 Transcript

研究问题需要分析解释如何形成，因此 transcript 很有价值，但它包含敏感反思：

- 单独征得 transcript research consent；
- 与身份映射表分开、加密保存；
- 导出前去标识化；
- 不把完整反思写入普通 production logs；
- 不保存 authorization header、API key 或完整 raw model body；
- 明确 retention、访问权限和删除流程；
- 质性 coder 只获得完成研究所需的最小文本。

### 8.3 当前代码中 measures 的风险

若未回答的 survey field 被自动序列化为 `4.0`，这些值不能进入研究数据，因为无法区分真实中点和缺失。Study 前应：

- 将 measure 字段改为 optional，或建立独立 survey response record；
- 保存 instrument version 与 item-level missingness；
- 禁止由 UI 缺省值自动提交；
- 在导出脚本中对历史默认值做来源标记，而不是当作真实回答。

---

## 9. Analysis plan

### 9.1 Primary analysis

使用 intention-to-treat 原则：按 assigned condition 分析，不因拒卡或 no-connection 改组。另做 exposure/process analysis，但不能替代 assigned-condition 结果。

**Primary mechanism model**

若 ownership scale 通过 pilot：

```text
interpretation_ownership
  ~ condition
  + period
  + sequence
  + session_index
  + (1 | participant)
```

Transcript provenance 使用预注册 codebook，把“关键新 distinction 在模型明确 formulation 之前是否已有 user-authored source”作为 binary 或 multinomial outcome，用 mixed-effects logistic / multinomial model，或在样本不足时报告 condition-level proportion 与 paired confidence interval。

**State self-compassion model**

```text
post_state_self_compassion
  ~ condition
  + pre_state_self_compassion
  + period
  + sequence
  + session_index
  + (1 | participant)
```

或以 `delta = post - pre` 为 outcome；二者只选一个为 preregistered specification。

报告：

- ownership/provenance 与 state outcome 各自的 condition estimate；
- 95% CI；
- standardized effect；
- participant 与 session 数；
- condition × period / sequence 的 carryover sensitivity；
- model assumptions 与稳健性分析。

如果同时把 ownership 和 SSCS-S 声明为 confirmatory primary outcomes，应预先说明 family-wise error / hierarchical testing。更简洁的方案是以 ownership/provenance 为 primary、SSCS-S 为 key secondary。

### 9.2 Secondary quantitative analysis

- SSR state reactance；
- interpretation ownership；
- perspective shift；
- felt understood；
- circumstances 与 agency/boundary/repair 两个维度；
- session duration、turn count、completion；
- card reject/set-aside/no-connection；
- context relevance、usefulness、unexpectedness、intrusiveness；
- context surface rate by reflection function；
- confirmed cue 的 later-use rate 与 repeated-reference count。

secondary outcomes 应预先分组，并说明 multiplicity 处理；其余标为 exploratory。

### 9.3 Mechanism analysis

只有在样本量和测量可靠性足够时，探索：

```text
condition → interpretation ownership → state self-compassion change
condition → reactance → completion / outcome
context function × user-confirmed relevance → usefulness / perspective shift
```

在 4 session/person、约 52 completer 的规模下，不应把复杂 multilevel mediation 作为唯一核心证据。可以用量化关联加 transcript process evidence 做 triangulation。

### 9.4 Transcript coding

先制定 codebook，再由不知道 session outcome 的 coder 编码：

- 用户是否提出了新的 distinction；
- 关键理解最先由 user / model / context cue / card 引出；
- global identity judgment 是否转成 specific behavior/event；
- 是否识别 circumstance / need / limitation；
- 是否识别 choice / impact / boundary / repair；
- 是否保留 uncertainty；
- 用户接受、修改或拒绝模型总结；
- 卡片是启发、装饰、阻碍还是过度 framing；
- context 在该 turn 的功能是 timing/capacity clarification、mapping enrichment、Tender grounding、agency sizing、practice sizing，还是没有必要；
- context 是 grounding、irrelevant、incorrect、creepy 还是 serendipitous；
- 同一 cue 后续被继续携带时，是形成连贯 understanding 还是变成 overfitting；
- 是否出现 forced positivity、sycophancy 或 overreach。

两名 coder 对一部分或全部样本双编码，报告 agreement、分歧解决和 codebook 迭代。

### 9.5 Missing data

- missing 不等于中点、不等于 0；
- 报告按 condition/period 的 missingness；
- mixed model 使用可用 session，并说明 MAR 假设；
- 对 dropout、技术失败和情绪负担分别报告；
- 做 completer 与 all-usable-session sensitivity；
- 不用删除“没连接到卡片”的 session 来美化效果。

---

## 10. Interview guide

访谈问题按机制组织，避免只问“喜不喜欢”。

### 10.1 关键理解由谁形成

- 请回忆一次让你改变看法的 session。那个改变最先从哪里出现？
- 哪些理解像是你自己形成的，哪些像是助手告诉你的？
- 你有没有想纠正、拒绝或迎合助手？当时发生了什么？

### 10.2 Card

- 描述一次卡片确实帮助你的例子。是哪个视觉元素起作用？
- 有没有卡太明显、太空、太负面或完全无关？
- 你是否觉得存在“正确牌义”？为什么？
- 换卡/拒卡的自由是否真实？
- 一周后你还记得卡片或由它产生的理解吗？

### 10.3 Context

- 看到近期数据时，你觉得它是在帮助观察，还是在替你解释？
- 它出现的那个时刻是否自然？如果早一点或晚一点出现会有什么不同？
- 它在事件理解、卡片连接、Tender/Fierce 或行动中分别起了什么作用？
- 哪条 cue 准确或不准确？你怎样判断？
- 它带来的意外感是有帮助、普通，还是像被监视？
- 当你说 cue 不相关时，系统是否真的放下了它？
- 同一个 context 被后续继续使用时，是形成了连贯理解，还是让你觉得系统抓住一个数据反复套用？

### 10.4 温和与行动性

- 哪些回应让你感到被安慰但没有回避问题？
- 有没有回应让你觉得太安慰、太推动、太判断或太快给行动？
- 最终理解是否同时容纳了处境和你仍有的选择？
- “今天不采取行动”是否被系统允许？

### 10.5 条件比较与 carryover

- 两种方式在形成理解、被理解感、压力和主动性上有什么不同？
- 第一周的方式是否改变了你第二周的使用？
- 你会在什么情境选择卡片，什么情境选择纯文本？

### 10.6 Safety、privacy 与长期使用

- 有无让你不舒服、暴露或被误解的时刻？
- 哪类个人数据绝不应被系统使用？
- 你希望看到怎样的数据来源、解释和删除控制？
- 如果使用一个月，什么会变得有帮助，什么会变得重复或依赖？

---

## 11. 依据当前代码可以怎样回答设计问题

本节只讨论代码所表达的 interaction design，不评估当前 build、图片资产或 card 是否已完成。

### 11.1 当前代码已经形成的 design commitments

- **用户确认先于系统使用**：tracking relationship、Tender summary、card consent、card mapping、final narrative 和 practice 都是不同的 typed confirmation object。
- **第三物先于牌义**：图片成功显示后，用户先观察、发展 image relation、再决定是否连接现实；内部 guidance 不能先进入 visible dialogue。
- **Chance 不承担诊断**：卡片由本地随机抽取，与用户路线、情绪、tracking 和模型推荐无关。
- **Tender 是共享 baseline**：两个条件在分流前都需要用户确认一个包含处境和困难的理解。
- **Fierce 是 optional 且有 turn budget**：只有具体行为、影响、边界、责任或改变证据出现时才允许问；一旦问过，下一步必须进入 narrative，不能连续逼问。
- **Card meaning 是 negotiated object**：candidate reading 被接受、修改后才能进入 final narrative；拒绝后必须撤回。
- **行动不从 symbol 推出**：practice 只能来自确认过的现实 narrative，而且一次只给一个 care / repair / protect / change option。

这些 commitments 共同实现的不是“AI 更聪明地分析人”，而是 **把 AI 的解释权限制在可协商、可拒绝的边界内**。

### 11.2 当前代码还留下的 design choice

#### A. Paper 主张选择

推荐使用与当前 baseline 一致的主张：

> Card-mediated reflection 是否通过一个随机第三物和 negotiated interpretation，提高 user-authored perspective formation，相比一套同样温和、同样 user-led 的 direct-text reflection？

不推荐继续使用：

> Card 是否优于一个 model-asserted / confrontational chatbot？

因为当前 direct condition 并没有实现后一种体验。

#### B. Card 的 candidate reading 应有多“像 reading”

当前 prompt 明确要求 `tarot-reading-like but non-divinatory`，并在用户完成 mapping 后利用 bounded internal guidance。Paper 需要选择并稳定描述这一语气：

- 它不是固定牌义；
- 也不只是复述用户原话；
- 它应新增一个 relational distinction；
- distinction 必须同时贴合 image relation 和 reality relation；
- 用户可接受、修改或拒绝。

这正是 card pilot 最需要测试的 interaction moment。

#### C. Context 是固定 stage 还是贯穿式 policy

当前代码把 tracking opportunity 主要放在 pre-card contextual disclosure。推荐把它改为贯穿式、按阶段限制能力的 policy，而不是增加一个新的固定 ContextBridge：

- cue 在本地可以始终 available；
- 每次 surface 必须有当前阶段的具体功能；
- card observation 阶段保持 context-silent；
- 未确认 cue 不能进入后续解释；
- 确认后的 relationship 可以继续被 later turns 使用，不必重复确认；
- 记录 cue 在哪个阶段以什么功能出现、后来进入了哪一层理解。

代码允许最多 4 个互补 cue，但 contribution 强调“最低充分 context”。Pilot 应比较 1、2 和 3–4 条时的体验，观察何时从 integrated cue 变成 data report。最终 protocol 需要固定 eligibility 和 ranking rule，而不是让模型按故事挑一个最能证明当前叙事的数据。

#### D. Card no-connection 是否重抽

当前设计是不重抽：一次 scaffold、一次 final connection opportunity，仍无法连接就放下 card 并继续 direct reflection。这更能保护随机性和避免“抽到满意为止”，也使 no-connection 成为有意义的 outcome。若未来改成 redraw，必须作为新的 design decision 和 exposure 定义。

#### E. Tender/fierce 是否列为 contribution

可以写成 design rationale 和系统 guardrail，但不应作为本 study 的独立 empirical contribution，因为两个条件都使用同一架构，且 Fierce 不是必经 phase。真正可比较的 contribution 是 card-mediated negotiated interpretation；完整 self-compassion 是它希望支持的 outcome。

### 11.3 当前代码对应的 baseline 命名

- 对外：`active direct-text reflection`；
- 对内：可暂时保留历史 enum / wire value；
- paper method：明确两组共享哪些功能、card condition 多出哪些功能；
- analysis：记录 turn count 和 duration，承认这是 whole-package comparison；
- 不把 direct baseline 描述成 sycophantic、confrontational 或 model-asserted。

---

## 12. Design / Study Go-No-Go checklist

以下只列设计、测量和研究逻辑，不讨论当前系统工程运行状态：

- [ ] 一句话 contribution、RQ、primary mechanism 和 key outcome 冻结；
- [ ] card-mediated 与 active direct-text baseline 的 researcher script 冻结；
- [ ] 最终 study deck 与每张卡的 design ledger 冻结；
- [ ] 每张卡达到预注册 pilot gate，或被修订/移除；
- [ ] contextualization policy 明确每个 reflection function 的 allowed/prohibited use；
- [ ] context cue 的来源、不确定性、首次出现功能、用户确认和后续使用可追踪；
- [ ] card reading 的 accept / revise / reject 与 no-connection 明确定义；
- [ ] ownership items 经过 cognitive interview；transcript provenance codebook 冻结；
- [ ] pre/post/weekly survey time point 和 missing-data rule 冻结；
- [ ] logs 能回答 condition、actual exposure、accept/reject 和来源问题；
- [ ] transcript consent、去标识化、retention 和访问流程通过伦理审查；
- [ ] 完成 card interaction pilot 和至少 4–6 人 protocol pilot；
- [ ] 冻结 preregistration、exclusion、primary model 和 power assumption；

只要 deck、measure 或 condition 定义仍在变，就不应开始正式计入主分析的 recruitment。

---

## 13. Meeting 中可以直接回答的五个问题

### Q1. 我们到底 propose 什么？

我们不是 propose 一个“会安慰人的 tarot chatbot”，而是 propose contextualized projective scaffolding：用随机第三物支持用户先形成 image relation 和 life mapping，同时让经过清洗的 contextual candidates 在不同反思阶段承担受限功能；系统只能基于用户确认过的关系提出可修改、可拒绝的 interpretation。它为纯文本 LLM 提供一种减少解释越权的设计路径；是否确实提高 interpretation ownership，由 active direct-text baseline study 检验。目标是 self-compassionate candor，而不只是短期好受。

### Q2. 流程和贯穿理论是什么？Tender/fierce 去哪里了？

当前代码的真实流程是 adaptive disclosure → pre-card context cue 协商 → Tender summary confirmation → 条件分流。推荐设计不再把 context 固定为某一步，而把它改成贯穿流程、按阶段限制能力的 policy。Card 组经过随机抽卡、image relation、optional life mapping、negotiated reading；两组之后都只在有现实证据时问最多一次 candid/Fierce question，再确认 narrative 和一个 optional practice。贯穿机制是 interpretation ownership；完整 self-compassion 是 outcome。Tender/fierce 是两个条件共享的架构，不是当前 manipulation。

### Q3. Contextual data 到底做什么？

它不选牌、不诊断、不暗中制造“AI 知道我”，也不是固定的 ContextBridge。Cue 可以在 disclosure、self-judgment clarification、image-life connection、Tender/Fierce 或 action sizing 中承担不同作用，但每次提出都必须服务当前阶段目标。未确认 cue 只能作为问题，用户判断 related / partly / unrelated / uncertain；后续只携带确认或限定后的 relationship。Card observation 保持 context-silent，用户说不相关后就停止使用。

### Q4. Card redesign 怎样成为可信 contribution？

先公开设计维度和 ledger，再做 blind cognitive interview、balanced incomplete block calibration 和 interaction pilot。除了“可读、有多种解释、不过度负面、不依赖 Tarot schema”，还要验证一次 image follow-up 是否足够、scaffold 是否偷渡牌义、life connection 怎样形成、candidate reading 是否新增 distinction，以及 accept/revise/reject 的原因。评价对象是 image + scaffold + internal guidance + negotiated reading。

### Q5. Study 如何从 RQ 倒推？

Study 0 先验证 manipulation artifact 和完整 card interaction；Study 1 用 active baseline 的两周 crossover。Primary mechanism 是 interpretation ownership 与 transcript-coded key-distinction provenance，SSCS-S 是关键体验结果。Context 需要额外记录首次出现阶段、当时功能、用户关系判断和后来进入哪一层 synthesis。暂以招募 64、目标 52 completer 做资源规划，最终样本由 Study 0D 的 ownership 方差、ICC 和 no-connection rate 做 power simulation；每人 4 session，并对 24–30 人做 purposive interview。

---

## 14. 建议的 paper structure

1. **Introduction**：self-critical reflection 的 comfort–candor dilemma；一句 contribution。
2. **Related Work**：LLM wellbeing/sycophancy；self-compassion；autonomy/reactance；ambiguity/projective artifacts；personal informatics。
3. **Formative Design Goals**：epistemic agency、context humility、bounded ambiguity、complete self-compassion。
4. **Card Design and Calibration（Study 0）**：ledger、维度、pilot、迭代和最终 deck。
5. **System**：typed LLM interfaces + deterministic Swift controller；两条件流程；privacy/safety。
6. **Deployment Study（Study 1）**：RQ、participants、procedure、measures、logs、analysis。
7. **Results**：interpretation ownership/provenance → state outcome → context/card process → failures。
8. **Discussion**：contextualized projective scaffolding 的边界；何时 ambiguity 帮助/伤害；AI epistemic humility；不透明 personalization 风险。
9. **Limitations**：非临床、短期、self-selection、carryover、文化/语言、card novelty、context coverage、whole-package comparison。

---

## 15. 近期工作顺序

### 第 1 阶段：两天内锁论证

1. PI / team 确认一句 contribution 和非主张边界；
2. 确认当前 paper 主比较是 card-mediated vs active direct text；
3. 决定 context 先作为两个条件共享的 cross-cutting policy，而不是第三个 causal factor；
4. 确认 Study 0 + Study 1 的 paper 结构。

### 第 2 阶段：锁 artifact

1. 完成每张 card 的 image relation、core tension、Tender/Fierce candidates、scaffold 和 prohibited claims ledger；
2. 执行 expert audit、cognitive interview 和 quantitative calibration；
3. 对完整 observation → connection → negotiated reading 做 interaction pilot；
4. 按预注册 gate 修订、重测或移除 card；
5. 冻结 study deck 和 interaction wording。

### 第 3 阶段：锁 protocol 与 instrumentation

1. 完成问卷授权/翻译；
2. 实现 pre/post/weekly survey；
3. 修复 missing default；
4. 补齐 version/process logs；
5. 完成 export、privacy 与 safety rehearsal。

### 第 4 阶段：end-to-end pilot 与 preregistration

1. 4–6 人完整跑两周或压缩版流程；
2. 检查 burden、turn imbalance、carryover、掉线与缺失；
3. 用 pilot 参数做 power simulation；
4. 冻结 preregistration；
5. 再开始正式 recruitment。

---

## 16. 关键依据

- Breines, J. G., & Chen, S. (2012). Self-compassion increases self-improvement motivation. [Personality and Social Psychology Bulletin](https://pubmed.ncbi.nlm.nih.gov/22645164/).
- Gaver, W. W., Beaver, J., & Benford, S. (2003). Ambiguity as a Resource for Design. [CHI 2003 paper](https://citeseerx.ist.psu.edu/document?doi=39b22e4b9efa2616224123adcd3bf7f8e8192057&repid=rep1&type=pdf).
- Markland, D., Ryan, R. M., Tobin, V. J., & Rollnick, S. (2005). Motivational interviewing and self-determination theory. [International Journal of Behavioral Nutrition and Physical Activity](https://pmc.ncbi.nlm.nih.gov/articles/PMC3330017/).
- Moyers, T. B. et al. (2017). A meta-analysis of motivational interviewing process. [Journal of Consulting and Clinical Psychology](https://pubmed.ncbi.nlm.nih.gov/29265832/).
- Neff, K. D. (2023). Self-Compassion: Theory, Method, Research, and Intervention. [Annual Review of Psychology](https://self-compassion.org/wp-content/uploads/2023/01/Neff-2023.pdf).
- Neff, K. D. et al. (2021). The development and validation of the State Self-Compassion Scale. [Mindfulness](https://self-compassion.org/wp-content/uploads/2021/03/Neff2021State.pdf).
- Sharma, M. et al. (2023). Towards Understanding Sycophancy in Language Models. [arXiv](https://arxiv.org/abs/2310.13548).
- Sittenthaler, S. et al. (2015). The Salzburg State Reactance Scale. [Zeitschrift für Psychologie](https://pubmed.ncbi.nlm.nih.gov/27453806/).

---

## 17. 与仓库内现有材料的关系

- `AGENT_ARCHITECTURE.md`：实现约束与 typed control architecture；
- `REFLECTION_CARD_DESIGN.md`：现有 card design procedure；
- `docs/reflection-architecture.md`：流程设计的早期版本；
- `docs/REFLECTION_CARD_READABILITY_AUDIT.md`：内部 card audit；
- `docs/manual-transcript-validation.md`：当前示例对话；
- `docs/interaction-cases.md`：早期比较叙事，需要按 active baseline 更新；
- `docs/BeyondComfort-实验参与者说明与使用教程.md`：现有两周 crossover 参与者流程；
- `card内涵.docx`：22 张卡的设计意图与视觉方向。

本文件负责把上述材料收束成同一条 contribution → mechanism → artifact → RQ → measure → analysis 的逻辑链；它不替代最终 preregistration、IRB 文档或每张卡的 pilot report。
