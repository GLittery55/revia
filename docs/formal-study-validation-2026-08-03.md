# BeyondComfort 正式用户实验前验证报告

日期：2026-08-03  
验证范围：当前工作区中的 iOS TurnController、Swift 协议控制、持久化、后端 prompt registry、后端 API/provider fallback，以及 opt-in 真实 LLM 场景运行器。

## 结论

当前版本的确定性协议链路和 mock 端到端链路已明显稳定：用户输入会在第一次模型请求前写入本机；`drawRandomCard` 与 `shareCardGuidance` 不调用 Writer；新形成的 `cardRealityMapping`、来源、guidance 权限和待生成后继状态可以一次提交；App 在静默提交后、可见回复前退出时，可以只恢复一次 card-guidance 后继；固定的 Reality Connection 漂移案例会在同一已验证 intent 内后台重写，不会把非法版本展示给用户。

但本次验证**尚不足以批准正式用户实验，也暂不建议立即开始 3–5 人非正式 pilot**。原因不是现有自动化测试失败，而是三个关键验收项仍缺少生产证据或实现：

1. 真实 Planner / Writer / Critic 的场景矩阵未运行。当前环境没有 live scenario 测试账号，无法得到 5 次重复运行的真实错误率和 bounded fallback 比例。
2. Reality Anchor 当前由 Swift 从本 session 的 `episodeStructure` 投影为受控文本数组，但还没有独立、类型化、可验证归属的 evidence ID，也没有 Planner 回传 evidence ID 的协议字段。
3. 所要求的完整结构化运行统计尚未实现。现有 `StudyEvent` 和 OSLog 能记录部分恢复路径，但没有统一包含 session ID、turn ID、transaction ID、issue type、recovery path 和 result；因此不能可靠计算正式验收要求中的各项比例。

此外，当前 LLM 会话入口仍保留“明确同意抽卡”和“明确接受 card mapping”的中文短语 fast path。它只处理能力门和确认事务，不生成 reflection 语义，但仍与“当前 LLM 路径不以中文关键词表代替语义判断”的严格要求存在冲突；正式 pilot 前应改为 LLM typed decision 或明确的 UI typed action。

## 当前实际调用链

普通可见回合的实际顺序如下：

1. `ReflectionViewModel.send()` 清理输入并通过 `addUser` 加入 session。
2. `launchPersistedModelResponse` 先 `SessionStore.save(session)`；保存失败时不调用模型。
3. `processProtocolTurn` 通过 `makeProtocolTurnRequest` 生成带当前权限、semantic memory、tracking、card context 和 reality anchor 的 typed request。
4. `RemoteReflectionTurnController.plan` 调用 Planner；`RemoteLLMTurnPlanner` 解码 JSON。
5. `normalizeApplicationEventPlan` 处理 card display/guidance 等应用事件的确定性规范化。
6. `deterministicPlanCritique` 只检查当前 permission tuple 和 typed object shape；必要时让同一 Planner 进行有限结构修复。
7. 对需要语义审查的计划调用 plan semantic critic；必要时让 Planner 做一次语义修订。
8. 回到 `ReflectionViewModel.requestValidatedProtocolTurn` 后，`ReflectionProtocolController.validate(plan, for:)` 先执行 `normalizeEquivalentProtocolLabels`，再做阶段、intent/action tuple、confirmation、来源和对象边界校验。规范化会同时读取当前 session 和本次 memory patch，但 patch 此时尚未持久化。
9. 对可见计划调用 Writer。`RemoteReflectionTurnController.write` 先做确定性 Writer shape 检查，再调用 Writer semantic critic；第一次偏移进行定向重写，第二次仍偏移时只在同一 validated plan 内做一次 bounded LLM fallback，不重新规划。
10. Swift 再校验 `realizedIntent`、非空可见 reply，并将 Writer 文本与已验证 Planner 计划组合成 response；response 再经过一次协议校验。
11. `applyValidatedProtocolResponse` 在内存中应用 semantic memory / tracking patch，更新能力计数、stage、local action 和唯一一条 assistant message。
12. 完整 session 通过 `SessionStore.save` 原子写入；失败则恢复 `sessionBeforeCommit`，不保留半提交状态。成功后再进行 best-effort 云同步。

一个重要的实际顺序差异是：**plan semantic critic 当前发生在 ViewModel 的最终 Swift 协议校验之前**，而不是在 effective-state 校验之后。Swift 最终仍会阻止非法提交，但报告和后续设计不能把当前实现描述成“Swift 先校验，再做 plan semantic critic”。

## 静默链路

### 随机抽卡

Planner typed decision 表示接受 card consent 后，`ReflectionProtocolController` 将唯一后继规范化为 `acknowledgeCardConsent + drawRandomCard`。`requestValidatedProtocolTurn` 识别本地 action，构造内部 authorization response，不调用 Writer、不追加空 assistant message。`applyValidatedProtocolResponse` 调用本地 `drawCard` 随机选择真实卡牌并保存 selected 状态。图片显示成功后，`cardDidDisplay` 才进入 card reflection，并显示本地观察邀请。

### Mapping 与 guidance

Planner 从用户回答生成非空 `cardRealityMapping` 和 `cardRealityMappingSource`。当 card 已显示且 guidance 尚未开放时，唯一后继会确定性规范化为：

```text
requestedStage = cardReflection
replyIntent = authorizeCardGuidance
localAction = shareCardGuidance
nextPrompt = none
```

该计划允许 `replyGuidance` 为缺失、null 或空字符串，直接绕过 Writer。提交时一次写入 mapping、mapping source、`cardGuidanceShared`、稳定 transaction ID 和 `pendingCardGuidanceTurn`。提交成功后才触发新的 `cardGuidanceAvailable` 请求；新请求读取已保存的 mapping 与开放后的 reference/context 能力，只生成一条可见 Card Reading。若 App 在两者之间退出，`resume` 只恢复一次待处理后继；相同 transaction 再执行会被忽略。

## 本次补充与修改

- `BeyondComfort/Models/AppModels.swift`
  - 新增 `TurnCardRealityMappingSource`，区分 `userAuthored`、`userAccepted`、`userRevised`。
  - 在 semantic memory/update 中保存 mapping 来源。
  - 为 session 增加 additive 的 `pendingCardGuidanceTurn` 和 `cardGuidanceTransactionID`，旧会话默认安全解码。
- `BeyondComfort/Services/AppServices.swift`
  - `SessionStore` 支持测试目录注入和按 session ID 读取，用于验证请求前持久化。
- `BeyondComfort/Services/ReflectionProtocolController.swift`
  - 当前协议在新 mapping 参与 `shareCardGuidance` 时要求 typed source。
  - 保持可见计划的非空 replyGuidance 校验，同时允许静默 guidance 计划为空。
- `BeyondComfort/ViewModels/ReflectionViewModel.swift`
  - 用户文本在第一次模型调用前 await 本地保存。
  - 可见 response 和静默 transaction 都在一次 session save 中提交；失败回滚内存状态。
  - guidance transaction 增加稳定 ID、pending successor 和恢复幂等。
- `BeyondComfort/Services/LLMTurnController.swift`
  - Writer 连续两次语义边界偏移时，在同一 validated plan 内执行一次 bounded LLM rewrite，不重新调用 Planner。
- `server/app/prompt_registry.py`
  - prompt 版本更新为 `turn-v4-server-v30`。
  - Planner contract 增加 mapping source。
  - plan/writer critic 增加 `generic_life_example_search`、`connection_left_current_episode`、`reality_anchor_not_used`、`image_relation_not_compared_with_focal_episode`。
- `BeyondComfortTests/ReflectionProtocolControllerTests.swift` 与 `server/tests/test_prompt_registry.py`
  - 增加 Reality Connection 定向重写、两次漂移 bounded fallback、输入预持久化、静默 transaction 恢复、mapping source 和 null replyGuidance 等回归测试。

## 关键场景结果

| 场景 | 结果 | 证据 |
|---|---|---|
| 非法 Reality Connection 搜索其他生活经历 | 通过 | critic 返回四类 typed issue；Writer 在相同 plan、anchor、image relation 内重写 |
| 固定输入“有点像，就是希望变好” | 通过 | 保存修订后的 mapping，source=`userRevised`；没有再次确认 |
| mapping + `authorizeCardGuidance/action=none` | 通过 | 唯一后继规范化为 `shareCardGuidance`，不产生 `illegal_reply_intent` |
| `shareCardGuidance` 的 replyGuidance=null/空 | 通过 | 不调用 Writer、不写空 assistant、正常生成下一可见 turn |
| 普通可见计划 replyGuidance 为空 | 通过（正确拒绝） | 仍返回 `emptyReply`，静默放宽没有污染可见计划 |
| 输入在 Planner 前持久化 | 通过 | 测试 Planner 在执行时从独立 SessionStore 读到原始用户消息 |
| 静默提交后退出并恢复 | 通过 | 只运行一个 visible successor；不重复 silent transaction |
| Writer 第一次失败 | 通过 | 复用同一 validated plan 重试；成功前不提交 memory patch |
| Writer 连续语义偏移 | 通过 | 一次 ordinary rewrite + 一次 bounded LLM fallback；Planner 调用数为 0 |
| Planner 非法 stage/intent | 通过 | Writer 不运行；权限被收窄后重新规划；非法状态未提交 |
| referenceGuidance 缺失/不适用 | 通过现有单元路径 | optional selection 可删除/跳过，不改 mapping，不阻断主流程 |
| tracking 缺失、无关、部分缺失、方向冲突 | 通过现有单元路径 | 不把缺失当 0，不把 tracking 当因果或责任，核心阶段可继续 |
| 已知卡牌连接故障重放 | 通过 | scaffold、候选 mapping、静默 authorization、Card Reading 全链路无可见技术中断 |
| 旧会话 additive decode / resume | 通过 | 新字段有默认值；旧 payload 可解码并按已保存阶段恢复 |
| 真实 LLM 14 类脚本 × 5 | **跳过/未达标** | 当前 catalogue 为 12 个综合场景；未实现每场景 5 次运行；环境无测试账号 |

## 测试命令与数量

```bash
# Swift 协议控制器和 TurnController 端到端
xcodebuild test -quiet -project BeyondComfort.xcodeproj -scheme BeyondComfort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BeyondComfortTests/ReflectionProtocolControllerTests \
  -only-testing:BeyondComfortTests/ReflectionTurnControllerIntegrationTests

# 后端 prompt 专项
PYTHONPATH=server server/.venv/bin/python -m unittest \
  server.tests.test_prompt_registry -v

# 后端全量
PYTHONPATH=server server/.venv/bin/python -m unittest discover -s server/tests -v

# iOS 全量
xcodebuild test -quiet -project BeyondComfort.xcodeproj -scheme BeyondComfort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# simulator build
xcodebuild build -quiet -project BeyondComfort.xcodeproj -scheme BeyondComfort \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

结果：

- `ReflectionProtocolControllerTests`：84 通过，0 失败。
- `ReflectionTurnControllerIntegrationTests`：50 通过，0 失败。
- 后端 prompt registry：23 通过，0 失败。
- 后端全量：85 通过，0 失败。
- iOS 全量：352 通过，0 失败，1 跳过。跳过项是 opt-in 的真实生产后端 LLM matrix。
- iOS simulator build：通过。
- `git diff --check`：通过。

## 验收指标

在本次确定性和 mock E2E 测试样本中，用户输入丢失、重复 assistant、重复 mapping、重复 guidance 后继、静默 Writer 调用、静默 empty-reply 失败、无关 Reality Connection、reference/tracking 主流程失败、非法 stage 放行和恢复失败均为 0。

这些数字**不能替代生产率统计**。由于真实 LLM matrix 未运行，以下比例均为 `N/A`：planner repair、writer rewrite、bounded fallback、reference skip、tracking skip、transport failure。也无法确认真实 bounded fallback 使用率是否低于 5%。

## 仍可能出现的用户可见中断

仍可能出现，但应限于：

- 本机 session 无法安全写入；系统会停止处理该条输入，避免数据丢失。
- 模型服务、服务器或网络在现有重试后仍完全不可用。
- 连续无法产生可解码且符合硬协议边界的模型输出。
- 卡牌资源本身无法显示；selected card 状态仍已保存，可恢复后重试显示。

普通一次 Planner 漏字段、一次 Writer timeout、一次 critic timeout、可选 reference/tracking 缺失和普通语言质量问题不应再要求参与者处理。

## Pilot 前必须完成

1. 将 Reality Anchor 升级为带稳定 evidence ID、session ID 和 focal episode ID 的 typed evidence；Planner 只能引用这些 ID，Swift 验证归属与确认状态，但不判断语义相似性。
2. 移除当前 LLM 路径上的中文确认短语 fast path，或将确认改为明确 UI action；自由文本的接受/修订/拒绝全部由 Planner typed decision 处理。
3. 补齐统一结构化 telemetry，并确保每条记录包含 session/turn/transaction 标识、stage、intent、action、issue、recovery 和 result，同时不记录完整反思文本。
4. 将 live scenario catalogue 补到明确覆盖 14 类交互分支，并让每类默认重复 5 次；报告中直接计算可见错误、漂移、重复、repair/rewrite/fallback 和 optional skip 比例。
5. 配置专用卡牌组/对照组测试账号，运行生产 Planner/Writer/Critic matrix。只有可见协议错误为 0、普通错误无需点击重试、重复和丢失为 0、bounded fallback 低于 5% 后，再开始 3–5 人非正式 pilot。

