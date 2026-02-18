# Info Bar Handoff (2026-02-18)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-18-bigmodel-before-update.md`
- 更早版本：
  - `.context/archive/HANDOFF-2026-02-18-minimax-provider-integration.md`
  - `.context/archive/HANDOFF-2026-02-17-minimax-before-update.md`
  - `.context/archive/HANDOFF-2026-02-17-zenmux-cookie-and-ui.md`
  - `.context/archive/HANDOFF-2026-02-17-pre-quota-refactor.md`

## 1. 当前状态（已完成）

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已接入四个真实 Provider：
  - `codex`（OAuth/Auth 文件 + usage API）
  - `zenmux`（浏览器 Cookie + subscription usage API）
  - `minimax`（浏览器 Cookie + coding plan remains API）
  - `bigmodel`（浏览器 Cookie + quota limit API）
- 菜单栏保持 Stats 风格：左 icon + 右侧双行文本（`<label>: <used%> <timeLeft>`）
- 主架构不变：`Module -> Reader -> Widget -> Popup`

## 2. 本轮关键变更

### 2.1 BigModel Provider 接入

- `QuotaProviderRegistry.defaultProviders()` 已包含 `codex` + `zenmux` + `minimax` + `bigmodel`
- `main.swift` 无需改动，按 registry 自动创建菜单栏项

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaProviderRegistryTests.swift`

### 2.2 BigModel 真实 Quota 映射

- 新增 `BigModelUsageClient` 实现 `QuotaSnapshotFetching`
- 默认接口：
  - `https://open.bigmodel.cn/api/monitor/usage/quota/limit`
- 支持环境变量覆盖：
  - `Z_AI_QUOTA_URL`（完整 URL）
  - `Z_AI_API_HOST`（host/base URL）
- 响应映射规则：
  - `TOKENS_LIMIT` -> `QuotaWindow(id: "tokens_limit", label: "T")`
  - `TIME_LIMIT` -> `QuotaWindow(id: "time_limit", label: "M")`
  - 百分比优先按 `usage/currentValue/remaining` 计算，缺失时回退 `percentage`
  - `nextResetTime`（毫秒时间戳）-> `resetAt`

关键文件：
- `Sources/InfoBar/Modules/Quota/BigModelUsageClient.swift`
- `Tests/InfoBarTests/Modules/Quota/BigModelUsageClientTests.swift`

### 2.3 BigModel 鉴权与 Cookie 方案（最终）

- 最终与 ZenMux/MiniMax 一致：走浏览器 Cookie 导入
- 新增 `BigModelBrowserCookieImporter`，复用 `BrowserQuotaCookieCollector`
- domains 配置：
  - `open.bigmodel.cn`, `.bigmodel.cn`, `bigmodel.cn`, `z.ai`, `.z.ai`, `api.z.ai`
- 鉴于服务端报错要求 Header 鉴权，`BigModelUsageClient` 会从 Cookie Header 中提取 token 并补发：
  - `Authorization: Bearer <token>`
- token 提取支持：
  - `authorization`, `access_token`, `access-token`, `token`, `api_key` 等常见键
  - `bigmodel_token*` 前缀（包含 `bigmodel_token_production`）

关键文件：
- `Sources/InfoBar/Modules/Quota/BigModelBrowserCookieImporter.swift`
- `Sources/InfoBar/Modules/Quota/BigModelUsageClient.swift`
- `Tests/InfoBarTests/Modules/Quota/BigModelUsageClientTests.swift`

### 2.4 BigModel 图标

- 新增 provider 图标：`bigmodel.svg`
- `QuotaStatusView` 仍按 providerID 自动加载 `<providerID>.svg`

关键文件：
- `Sources/InfoBar/Resources/Icons/bigmodel.svg`

## 3. 运行与验证

- 构建：`swift build`
- 测试：`swift test`
- 启动：`swift run InfoBarApp`

最新结果（本地）
- `swift test`：`38 tests`，`0 failures`，`1 skipped`
- `swift build`：通过
- `swift run InfoBarApp`：可构建并启动（鉴权是否成功取决于本机浏览器 Cookie 是否包含 BigModel 可用 token）

## 4. 关键测试

- `Tests/InfoBarTests/Modules/Quota/BigModelUsageClientTests.swift`
  - `testThrowsMissingCredentialsWhenCookieUnavailable`
  - `testDecodesQuotaPayloadAndMapsSnapshot`
  - `testThrowsApiFailureWhenResponseIsNotSuccess`
  - `testThrowsMissingUsageDataWhenLimitsEmpty`
  - `testBigModelBrowserCookieImporterUsesReusableCollector`
  - `testExtractsAuthorizationTokenFromCookieHeader`
  - `testExtractsBigModelProductionTokenFromCookieHeader`
- `Tests/InfoBarTests/Modules/Quota/QuotaProviderRegistryTests.swift`
  - `testDefaultProvidersContainCodexZenMuxMiniMaxAndBigModel`

## 5. 当前风险与下轮建议（优先级）

1. BigModel 若浏览器 Cookie 中无可用 token（或 token key 变化）仍会出现鉴权失败，建议加开关日志仅输出“命中哪个 cookie key”，不打印敏感值。
2. 目前 BigModel 默认走 `open.bigmodel.cn`，如果用户账号实际在 global 端，需通过 `Z_AI_API_HOST` / `Z_AI_QUOTA_URL` 覆盖。
3. 建议补一条可控 live probe（环境变量开关）用于 BigModel 联调，减少本地误判。
