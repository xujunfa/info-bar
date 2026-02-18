# Info Bar Handoff (2026-02-17)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-17-minimax-before-update.md`
- 更早版本：
  - `.context/archive/HANDOFF-2026-02-17-zenmux-cookie-and-ui.md`
  - `.context/archive/HANDOFF-2026-02-17-pre-quota-refactor.md`

## 1. 当前状态（已完成）

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已接入三个真实 Provider：
  - `codex`（OAuth/Auth 文件 + usage API）
  - `zenmux`（本地浏览器 Cookie + subscription usage API）
  - `minimax`（本地浏览器 Cookie + coding plan remains API）
- 菜单栏保持 Stats 风格：左 icon + 右侧双行文本（`<label>: <used%> <timeLeft>`）

## 2. 本轮关键变更

### 2.1 MiniMax Provider 接入

- `QuotaProviderRegistry.defaultProviders()` 已包含 `codex` + `zenmux` + `minimax`
- `main.swift` 无需改动，按 registry 自动同屏创建菜单栏项

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`

### 2.2 MiniMax 真实 Quota 映射

- 新增 `MiniMaxUsageClient` 实现 `QuotaSnapshotFetching`
- 默认接口：
  - `https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains?GroupId=2015339786063057444`
- 支持环境变量覆盖：
  - `MINIMAX_USAGE_URL`
  - `MINIMAX_GROUP_ID`
- 响应映射：
  - `current_interval_total_count` 作为总额度（默认 1500）
  - `current_interval_usage_count` 作为剩余额度
  - `used = total - remains`
  - `usedPercent = round(used / total * 100)`
  - `remains_time`（毫秒）映射为 `resetAt = fetchedAt + remains_time`

关键文件：
- `Sources/InfoBar/Modules/Quota/MiniMaxUsageClient.swift`

### 2.3 MiniMax 浏览器 Cookie 复用能力

- 新增 `MiniMaxBrowserCookieImporter`
- 复用 `BrowserQuotaCookieCollector`
- MiniMax collector 配置：
  - domains: `www.minimaxi.com`, `.minimaxi.com`, `minimaxi.com`
  - requiredCookieNames: 空集合（带出域下可用 cookie）
  - preferredBrowsers: chrome/safari/firefox

关键文件：
- `Sources/InfoBar/Modules/Quota/MiniMaxBrowserCookieImporter.swift`
- `Sources/InfoBar/Modules/Quota/BrowserQuotaCookieCollector.swift`（复用，无改动）

## 3. 运行与验证

- 构建：`swift build`
- 测试：`swift test`
- 启动：`swift run InfoBarApp`

最新结果（本地）
- `swift build`：通过
- `swift test`：`30 tests`，`0 failures`，`1 skipped`
- `swift run InfoBarApp`：可构建并启动（本轮用后台启动 5 秒验证）

## 4. 关键测试

- `Tests/InfoBarTests/Modules/Quota/MiniMaxUsageClientTests.swift`
  - `testDecodesRemainsPayloadAndMapsSnapshot`
  - `testThrowsApiFailureWhenStatusCodeNonZero`
  - `testThrowsMissingUsageDataWhenModelRemainsUnavailable`
  - `testMiniMaxBrowserCookieImporterUsesReusableCollector`
- `Tests/InfoBarTests/Modules/Quota/QuotaProviderRegistryTests.swift`
  - `testDefaultProvidersContainCodexZenMuxAndMiniMax`

## 5. 下轮建议

1. 新增 provider 级错误状态（auth/network/parse）并透传 UI，替代统一 `-- --`。
2. 将 ZenMux/Codex/MiniMax 失败诊断日志改为 DEBUG/ENV 开关。
3. 如果要展示 MiniMax 的 `used/total`（如 `100/1500`）到菜单栏，建议先抽象 display 文本策略，避免把 provider 语义塞回 `QuotaDisplayModel`。
