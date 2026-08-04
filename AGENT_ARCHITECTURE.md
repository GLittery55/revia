# Beyond Comfort 对话架构

## 新会话：LLM 管语义，Swift 管协议

新建反思使用 `protocolVersion = 2`。普通对话不再由
`.emotionDisclosure`、`.selfJudgment`、`.contextDisclosure` 等细粒度 Swift 状态选择
下一道问题，而是统一经过：

```text
当前粗粒度阶段、最近对话、语义记忆、可用本地能力
                         ↓
LLM TurnPlanner：理解最新回答，更新语义记忆，提出 TurnPlan
                         ↓
Swift ProtocolController：验证阶段和本地动作权限
                         ↓
LLM TurnWriter：只把已验证的 replyIntent 写成自然中文
                         ↓
Swift：执行获准的本地动作、显示一句回复、保存回合
```

TurnPlanner 与 TurnWriter 是两个独立的类型化接口。Writer 看不到改变阶段或申请本地能力
的权限；未经 Swift 验证的计划不会进入 Writer。

## Swift 持有的内容

Swift 只持有粗粒度研究阶段：

- `contextualDisclosure`
- `tenderConfirmation`
- `cardConsent`
- `cardReflection`
- `directReflection`
- `narrativeConfirmation`
- `optionalAction`
- `complete`
- `safetySupport`

Swift 同时负责：

- 服务端分配的实验条件；
- 用户消息与回复的一一对应、取消和重复提交抑制；
- HealthKit/EventKit 数据的授权、清理、确定性计算和个人基线比较；
- 仅向模型提供清理后的候选观察，不提供原始健康样本；
- 本地均匀随机抽卡、图片加载和卡片档案授权；
- 阶段转换、本地动作、安全中断、保存、恢复和完成。

Swift 不判断用户是否已经表达了“足够的情绪”，不根据缺失字段选择问题，也不把模型
回复替换为本地固定语义问题。

## LLM 持有的内容

TurnPlanner 负责判断：

- 用户刚才实际回答了什么；
- 上一道问题是否已经完成；
- 接下来应继续理解经历、个人意义、现实条件，还是可以整理 Tender 理解；
- 一条或数条互补的 tracking 候选是否真的能为当前经历增加背景；
- 卡片画面关系、现实关系和协商式映射；
- 是否存在有用户材料支持的 Tender/Fierce 反思方向；
- 是否适合形成叙事，或提供 care / repair / protect / change / no-action 实践。

这些内容保存在通用 `TurnSemanticMemory` 中，按关系和问题功能记录，不按“论文、导师、
家庭、分手”等主题分支记录。

## Self-tracking

Self-tracking 不是独立问卷阶段。Swift 在后台准备最多数条已清理的候选观察，TurnPlanner
可以在 `contextualDisclosure` 中按当前情境申请一条或数条互补观察。选择遵循“够用的
最小组合”，既不固定为一条，也不为了证明某个故事而挑数据。可见回复把所选观察整合为：

```text
可观察的数据变化 × 用户已经披露的生活情境 × 对具体反应的可能影响
→ 一个不确定、可确认、可拆分或可否认的情境归因
```

模型不能用数据证明情绪、原因、能力、回避、责任或诊断。只有用户在下一轮确认、部分
确认或否认的关系才进入语义记忆；首次展示数据的同一轮不能替用户写入相关性判断。

## 卡片条件

Tender 理解确认后，模型先自然邀请，用户明确同意后才可申请 `drawRandomCard`。Swift
本地随机选择卡片并等待图片真正显示。

卡片显示后，模型先让用户描述画面并发展画面关系，再邀请现实联系。连接困难时，只能
使用一次当前卡片档案中的画面 scaffold；仍无联系就放下卡片。用户形成画面关系与现实
映射后，模型可以申请 `shareCardGuidance`。该授权是无可见气泡的本地动作，不再插入
第二次“是否愿意听牌义”的流程确认。

获得授权后，模型可以像一次协商式卡牌阅读那样，把用户形成的画面关系、已经确认的现实
关系和两者真正相交的核心张力、Tender/Fierce 及 self-compassion 候选方向写成一段完整、
可修改、可拒绝的解读。它不能宣布固定牌义，也不能逐项复述卡牌资料与用户经历。最终
有效意义必须是用户接受或修订后的“画面关系—现实关系”映射；拒绝后不得继续使用候选
牌义。

## 实践建议

叙事得到确认后，Chatbot 先提出一项低负担实践，而不是要求用户从零想办法。候选方向为：

- `care`：当前主要需要恢复、安抚或获得支持；
- `repair`：用户确认的具体行为已经造成需要修复的影响；
- `protect`：需要保护需要、边界、安全或责任范围；
- `change`：用户已经识别出一个具体、可改变的行为或模式。

建议必须来自已确认的叙事，允许用户缩小、改写或拒绝。只有用户接受或改写后才写入
`selectedPractice`；没有足够依据或用户不想行动时，`no-action` 仍是完整结果。

## 失败处理

每个回合先解析 TurnPlan，再由 Swift 验证：

- 当前会话和用户回合仍有效；
- `requestedStage` 是合法相邻阶段；
- `localAction` 在当前阶段获准；
- tracking ID 是本轮提供的清理候选的非空、无重复子集，且未在此前展示；
- 卡片动作满足本地显示和授权条件。

第一次失败时，Swift 把允许的阶段和动作边界交还 TurnPlanner，进行一次受限重生成。
第二次仍失败时，留在原阶段，仅显示中性的技术提示；不从本地问题库补问任何语义问题。

旧会话缺少 `protocolVersion` 时按版本 1 解码，继续走原有兼容路径，不在进行中的反思里
迁移语义状态。
