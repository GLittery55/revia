# BeyondComfort TestFlight 外测资料清单与审核模板

> 用于 App Store Connect 创建、TestFlight 外测审核及代上传资料交接。  
> 请将所有“待填写”内容替换为真实信息，并在提交前按最终版本核对。

## 文档信息

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 待补充后交付 |
| 资料负责人 | 待填写 |
| 计划提交日期 | 待填写 |
| 代上传联系人 | 待填写 |

> [!IMPORTANT]
> 隐私与数据收集项目必须依据实际前端、后端和第三方模型服务填写。不要在尚未核实的情况下选择“未收集”。

## 1. App 基本信息

| 项目 | 内容 |
| --- | --- |
| App 名称 | BeyondComfort |
| 平台 | iOS |
| 主语言 | 简体中文 |
| Bundle ID | 待填写，必须与 Xcode 签名一致 |
| Version | 1.0 |
| Build | 1 |
| SKU | `beyondcomfort-ios-001`，可按账号规则调整 |
| 最低 iOS 版本 | 待填写 |
| 开发者团队 | 待填写账号名称及 Team ID |

提交前确认：

- Bundle ID 在首次上传后不应随意更换。
- 后续每次重新上传同一版本时，Build 必须递增，例如 `1`、`2`、`3`。

## 2. TestFlight 展示信息

### 2.1 Beta App Description

可直接复制：

```text
BeyondComfort 是一款结构化反思工具，帮助用户梳理近期经历、关注当下感受，并通过文字引导和图像联想形成个人理解。

应用可以在用户主动授权后读取部分 HealthKit 和日历统计信息，为反思提供可选的状态线索。用户可以拒绝授权，基础反思功能仍然可以使用。
```

### 2.2 Feedback Email

```text
待填写可正常收信的邮箱
```

### 2.3 What to Test

可直接复制：

```text
请重点测试：

1. 首次启动和引导流程是否正常。
2. 输入一段近期经历后，反思流程是否可以完整进行。
3. 允许或拒绝 HealthKit、日历权限时，App 是否都能正常使用。
4. 图像卡片是否正常显示。
5. 网络异常或模型回复失败时，是否能正常提示和恢复。
6. 是否出现崩溃、页面卡住、文字截断或无法继续的情况。
```

## 3. TestFlight 审核资料

### 3.1 审核联系人

| 项目 | 内容 |
| --- | --- |
| 联系人姓名 | 待填写 |
| 联系电话 | 待填写，包含国家或地区代码 |
| 联系邮箱 | 待填写 |
| 是否需要登录 | 无需登录 / 需要登录 |
| 测试账号 | 无需登录则填写“不适用” |
| 测试密码 | 无需登录则填写“不适用” |

### 3.2 审核备注

可直接复制，提交前请根据最终版本核对：

```text
本 App 无需注册或登录即可体验主要功能。

主要测试步骤：
1. 启动 App 并完成初始引导。
2. 输入一段近期经历。
3. 根据页面提示完成反思流程。
4. HealthKit 和日历权限均为可选权限，可以拒绝。
5. 当设备没有相关健康或日历数据时，App 会显示无可用记录，主要功能仍可继续。

HealthKit 使用说明：
App 读取用户授权的睡眠、静息心率和 HRV 信息，并将清理后的个人状态摘要作为可选反思线索。原始 HealthKit 样本不会直接发送给语言模型。

日历使用说明：
App 使用日程数量和时长等统计线索，不使用日程标题或正文作为分析内容。

本 App 的反思内容不构成医疗、心理诊断或治疗建议。
```

## 4. 隐私与合规信息

### 4.1 隐私政策

| 项目 | 内容 |
| --- | --- |
| 隐私政策 URL | 待填写，必须为无需登录即可访问的 HTTPS 页面 |
| 隐私联系邮箱 | 待填写 |
| 数据删除方式 | 待填写页面、邮箱或 App 内入口 |
| 数据保留期限 | 待填写 |

隐私政策核对：

- [ ] 说明收集哪些数据、收集方式和用途。
- [ ] 说明用户反思文字是否上传服务器、是否保存以及保存期限。
- [ ] 说明 HealthKit 和日历数据的使用范围。
- [ ] 说明是否由第三方模型服务处理用户输入。
- [ ] 说明用户如何撤回授权、访问数据和申请删除数据。
- [ ] 确认 App 内存在容易找到的隐私政策入口。

### 4.2 App Privacy 数据核对

#### 用户反思文字

- [ ] 不上传
- [ ] 上传但不保存
- [ ] 上传并保存
- 用途：待填写

#### HealthKit 数据

- [ ] 仅在设备端使用
- [ ] 上传清理后的摘要
- [ ] 上传其他数据
- 说明：待填写

#### 日历数据

- [ ] 仅在设备端使用
- [ ] 上传清理后的摘要
- [ ] 上传其他数据
- 说明：待填写

#### 标识符

- [ ] 不收集
- [ ] 收集会话 ID
- [ ] 收集设备或账号标识
- 说明：待填写

#### 诊断信息

- [ ] 不收集
- [ ] 收集崩溃日志
- [ ] 收集性能数据
- [ ] 收集其他诊断信息
- 说明：待填写

#### 第三方服务

- 模型服务：待填写
- 分析服务：待填写
- 托管服务：待填写
- 错误监控服务：待填写

#### 广告与追踪

- [ ] 不用于广告或追踪
- [ ] 存在其他用途
- 说明：待填写

#### 研究用途

- [ ] 不用于研究
- [ ] 用于研究
- 用户同意与退出机制：待填写

### 4.3 加密出口合规

- [ ] 仅使用 Apple 系统提供的 HTTPS/TLS。
- [ ] 使用其他标准加密算法。
- [ ] 包含自研或非标准加密。
- [ ] 包含 VPN 或加密通信功能。
- 其他说明：待填写。

### 4.4 HealthKit 与内容权利

- [ ] Developer 后台的 App ID 已启用 HealthKit。
- [ ] Xcode 工程已包含 HealthKit entitlement。
- [ ] HealthKit 权限说明与实际用途一致。
- [ ] 已确认 App 图标、卡片图片和塔罗素材为自有内容或具有合法许可。
- [ ] 已确认其他第三方内容具有使用授权。

## 5. 外测分发计划

| 项目 | 内容 |
| --- | --- |
| 内部测试组 | 待填写，创建外部组前先创建 |
| 外部测试组名称 | BeyondComfort External Beta |
| 邀请方式 | 公开链接 / 邮箱邀请 / 两者均使用 |
| 预计测试人数 | 待填写 |
| 设备条件 | 不限制 / 待填写限制条件 |
| 系统条件 | iOS 待填写版本或更高 |
| 自动通知测试者 | 是 / 否 |
| 反馈收集方式 | TestFlight 反馈 / 邮箱 / 问卷 |

## 6. 交付给代上传人员的文件

- [ ] App Store Connect 类型的 `BeyondComfort.ipa`。
- [ ] 本资料文档的最终填写版本。
- [ ] 最终 Bundle ID、Version、Build 和开发者团队信息。
- [ ] 隐私政策 URL 与 App Privacy 数据收集说明。
- [ ] 测试账号及密码，如 App 需要登录。
- [ ] 可访问的公网 HTTPS 后端地址及可用性确认。
- [ ] dSYM 或 xcarchive，可选，用于后续崩溃符号化。

### 不要交付

- Apple Account 密码
- 双重认证验证码
- Apple Distribution 证书私钥
- 后端 `.env`
- 模型 API Key
- 真实用户数据
- 研究参与者原始数据

## 7. 最终提交检查

- [ ] IPA 使用最终开发者团队的 Apple Distribution 签名。
- [ ] Xcode、Developer 后台和 App Store Connect 的 Bundle ID 完全一致。
- [ ] Version 与 Build 未重复，Build 已按需要递增。
- [ ] HealthKit entitlement 和 provisioning profile 均有效。
- [ ] App 图标、卡片资源和权限说明完整。
- [ ] 后端可从公网访问，审核员无需连接本地网络。
- [ ] 拒绝 HealthKit 或日历权限时，App 不会崩溃或卡住。
- [ ] Beta App Description、What to Test 和 Feedback Email 已填写。
- [ ] 审核联系人、测试账号和审核备注已填写。
- [ ] 隐私政策、数据收集声明与实际行为一致。
- [ ] 加密出口合规问题已按实际情况回答。
- [ ] 已创建内部测试组。
- [ ] 已创建外部测试组并添加正确 Build。
- [ ] 已提交 TestFlight App Review。

## 8. Apple 官方参考

- [提供 TestFlight 测试信息](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- [邀请外部测试者](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [管理 App 隐私信息](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

---

该模板用于准备 TestFlight 外部测试资料，不替代 Apple 最新规则或针对具体数据实践的法律判断。
