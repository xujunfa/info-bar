# Info Bar Handoff (2026-02-17)

## 1. 当前状态（已完成）

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已接入真实 Codex quota：读取 `~/.codex/auth.json` / `$CODEX_HOME/auth.json`，请求 usage API，并展示到 MenuBar。
- 菜单栏样式保持不变：左侧 `codex.svg` + 右侧双行文本。
- 展示文案已改为窗口化：
  - 第一行：`H: <used%> <timeLeft>`
  - 第二行：`W: <used%> <timeLeft>`
  - 示例：`H: 14% 2h` / `W: 21% 2d3.5h`

## 2. 本轮关键重构（为多 Agent 扩展做准备）

### 2.1 通用 Quota 领域模型（去 Codex 专用字段）

- 引入：`QuotaWindow(id, label, usedPercent, resetAt)`
- `QuotaSnapshot` 改为：`providerID + windows[] + fetchedAt`
- 影响：显示层不再依赖固定 `fiveHour/weekly` 字段，后续可接任意 provider 的窗口数据。

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaSnapshot.swift`

### 2.2 展示层改为通用窗口驱动

- `QuotaDisplayModel` 读取 `windows[0]`、`windows[1]` 作为两行展示。
- 仍保留当前风格；默认 label fallback 为 `H/W`。
- 支持非 Codex 标签（如 `D/M`）测试已覆盖。

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`

### 2.3 Provider 注册机制（可同屏多 Agent）

- 新增 `QuotaProviderRegistry`，统一注册 provider fetcher。
- App 启动改为遍历 provider 列表，逐个创建：
  - `MenuBarController`
  - `QuotaReader`
  - `QuotaModule`
  - `QuotaWidget`
- 当前默认仅注册 `codex`，但结构已支持快速增加更多 agent。

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`
- `Sources/InfoBarApp/main.swift`

### 2.4 Codex 适配层

- `CodexUsageClient` 将 API 的 primary/secondary window 映射到通用 `windows[]`。
- 读取 auth/config 与 URL 解析逻辑已就位。

关键文件：
- `Sources/InfoBar/Modules/Quota/CodexAuthStore.swift`
- `Sources/InfoBar/Modules/Quota/CodexUsageClient.swift`

## 3. UI 与布局现状

- `statusWidth` 已增至 `104`，避免 `2d3.5h` 时长被裁剪。

关键文件：
- `Sources/InfoBar/UI/MenuBar/QuotaLayoutMetrics.swift`

## 4. 测试现状

- 全量测试通过：`16 tests, 0 failures`。
- 已覆盖：
  - Auth 解析
  - Codex usage 解码与映射
  - Reader 回调行为
  - 通用窗口展示与时长格式
  - Provider registry 默认项
  - 布局宽度防回归

关键测试：
- `Tests/InfoBarTests/Modules/Quota/CodexAuthStoreTests.swift`
- `Tests/InfoBarTests/Modules/Quota/CodexUsageClientTests.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaSnapshotTests.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaDisplayModelTests.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaReaderTests.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaProviderRegistryTests.swift`
- `Tests/InfoBarTests/UI/MenuBar/QuotaLayoutMetricsTests.swift`

## 5. 下一轮优先建议（按顺序）

1. 接入第 2 个真实 Agent（建议先选结构简单者）
   - 新增 `<Agent>UsageClient` 实现 `QuotaSnapshotFetching`
   - 在 `QuotaProviderRegistry.defaultProviders()` 注册
   - 补映射与展示测试
2. 改进错误语义（避免失败统一显示 nil）
   - 为 snapshot 增加状态字段（ok / authExpired / networkError / parseError）
3. 将 Reader 改成非阻塞 async 拉取（当前是同步 fetch）

## 6. 运行命令

- `swift build`
- `swift test`
- `swift run InfoBarApp`

## 7. 参考文档

- Codex 方案参考：`/Users/xujunfa/Documents/workspace/github/CodexBar/.context/codex.md`
