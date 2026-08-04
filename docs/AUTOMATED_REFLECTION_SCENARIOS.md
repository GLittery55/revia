# 自动完整流程案例测试

自动案例测试通过正式的 `ReflectionViewModel`、`RemoteReflectionTurnController`、
Planner、Writer、Critic、Swift 协议验证、阶段转换和原子提交路径运行。测试代码不会
根据 assistant 的固定文案选择回答，而是读取类型化的 `nextPrompt`、confirmation
target 和当前协议阶段。

## 运行

完整配对测试需要两个专门的参与者账号。服务器应把其中一个账号当前分配到
`cardMediated`，另一个分配到 `modelAsserted`。测试不会覆盖服务器分组，也不会让
同一个账号同时进入两种条件；两组会顺序运行，避免共享 Cookie 被另一次登录覆盖。

```bash
# 配对模式：两个账号当前分别处于卡牌组和直接 LLM 对照组。
# 脚本不会打印这些值。
export REFLECTION_SCENARIO_CARD_USERNAME='scenario-card'
export REFLECTION_SCENARIO_CARD_PASSWORD='卡牌组测试账号密码'
export REFLECTION_SCENARIO_DIRECT_USERNAME='scenario-direct'
export REFLECTION_SCENARIO_DIRECT_PASSWORD='对照组测试账号密码'

# 2 个案例 × 卡牌组/对照组，适合先验证连接
./scripts/run-reflection-scenarios.sh --smoke --paired

# 6 个案例 × 两组
./scripts/run-reflection-scenarios.sh --standard --paired

# 12 个案例 × 两组，覆盖完整矩阵
./scripts/run-reflection-scenarios.sh --full --paired
```

如果现在只有一个有权限的账号，可以只测试服务器给该账号分配的当前条件：

```bash
export REFLECTION_SCENARIO_USERNAME='scenario-current'
export REFLECTION_SCENARIO_PASSWORD='当前测试账号密码'

./scripts/run-reflection-scenarios.sh --smoke --assigned
./scripts/run-reflection-scenarios.sh --full --assigned
```

测试会使用 `Config.xcconfig` 中当前配置的后端，因此会产生真实模型调用。完整矩阵
耗时和调用量较大，建议先运行 smoke，再运行 full。如果没有提供上述环境变量，测试
只有在 `--assigned` 模式下才会尝试复用同一 `iPhone 17 Pro` 模拟器中正式 App 已
登录的会话。`--paired` 模式必须显式提供两个账号。

由于 `xcodebuild` 不会自动把 Mac shell 中的自定义环境变量传给模拟器 XCTest，
脚本会在运行前把测试账号变量临时写入同一个 `iPhone 17 Pro` 模拟器的 launchd
环境，并在退出、失败或中断时自动清除。变量不会写入报告或项目文件。

每次登录后，测试都会调用 `/api/study/me` 并验证服务器返回的 `condition`、
`sequence` 和 `period`。`ReflectionViewModel` 通过与正式 App 相同的
`configureStudy()` 创建会话；测试代码不再直接覆盖 `session.condition`。因此：

- 一个账号在一次运行中只执行服务器当前分配的实验条件；
- 两个条件不会并发，共享认证 Cookie 不会串号；
- 配对发生在报告层：用相同案例 ID、相同用户语义脚本和相同 synthetic tracking
  输入比较两个账号的结果；
- 只有一个账号时可以检查完整单组流程，但不能得出两组配对比较结果。

命令行会在测试结束时单独显示服务器实际分配，例如：

```text
=== 服务器实际实验条件 ===
REFLECTION_SCENARIO_ASSIGNMENT label=assigned condition=cardMediated condition_name=随机卡牌组 sequence=cardFirst period=1
```

对照组的持久化值为 `modelAsserted`，显示名称为“直接 LLM 对照组”。输出不会包含
账号或密码。

报告保存在：

```text
tmp/reflection-scenario-results/<时间>-<案例集>/reports/
```

其中 Markdown 报告适合直接阅读，JSON 报告适合后续统计。每轮包含：

- 用户输入和全部 assistant 可见回复；
- 当前协议阶段和 App 阶段；
- Planner intent、requested stage、local action、reply guidance；
- nextPrompt 的 kind、purpose、focus、target 和 reference ID；
- 已解决与新建立的 confirmation；
- Writer realized intent 和输出；
- Swift 阶段提交事件；
- Planner/Writer 重试、协议拒绝、超时和错误。

卡牌组与对照组使用相同的 contextual disclosure、tracking、Tender summary、最终
叙事、Practice 和完成协议。配对报告会检查两组是否都经过这些共享环节，并确认只有
中间反思媒介不同：卡牌组经过本地随机抽卡和协商式卡牌反思，对照组进入直接 LLM
反思。

## Tracking 覆盖矩阵

完整案例集包含九类确定性的 cleaned tracking 输入。它们只用于测试，不读取真实
HealthKit/EventKit 数据：

- `reducedRecovery`：睡眠时长、入睡时间和活动量多项同方向变化；
- `denseSchedule`：日程明显增加，睡眠和活动只有轻微变化；
- `stableRecords`：睡眠、活动和日程没有明显变化；
- `partialAndMissing`：最近窗口覆盖不足，每条 cue 带有低置信度和缺失限制；
- `mixedSignals`：睡眠减少，但活动增加、日程减少，不能合成统一结论；
- `delayedSleepOnly`：入睡和醒来时间推后，但总睡眠时长基本稳定；
- `reducedActivityOnly`：步数下降，睡眠和日程基本稳定；
- `improvingRecovery`：用户经历困难时，睡眠和活动记录反而改善；
- `noUsableData`：不提供任何 cue，系统不得生成 tracking 解释。

Markdown/JSON 报告会记录 profile 名称，以及每条 cue 的 source、metric、自然描述、
覆盖率、置信度和限制。卡牌组与对照组的同一案例始终使用完全相同的 tracking 输入。
