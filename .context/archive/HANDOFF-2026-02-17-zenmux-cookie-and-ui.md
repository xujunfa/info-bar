# Info Bar Handoff (2026-02-17)

## 0. 归档记录

- 上一版（重构前）已归档到：
  - `.context/archive/HANDOFF-2026-02-17-pre-quota-refactor.md`

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

## 8. 2026-02-17 增量（ZenMux Provider）

- 已接入第 2 个真实 Provider：`zenmux`
  - 新增 `ZenMuxUsageClient`，实现 `QuotaSnapshotFetching`
  - 映射到通用窗口模型：默认 `M`（主窗口）+ 可选 `W`（周窗口）
  - 保持 `Module -> Reader -> Widget -> Popup` 链路不变
- 已在 `QuotaProviderRegistry.defaultProviders()` 注册 `zenmux`，与 `codex` 同屏展示（每个 provider 一个菜单栏项）
- 新增 cookie 获取策略（尝试）：
  - 环境变量直传：`ZENMUX_COOKIE_HEADER`
  - 环境变量拼装：`ZENMUX_SESSION_ID` / `ZENMUX_SESSION_SIG` / `ZENMUX_CTOKEN`
  - 尝试读取系统 Cookie 存储与 Chrome/Chromium SQLite（仅可读明文 value 的场景）
- 新增测试并全量通过：
  - `ZenMuxUsageClientTests`（解码/映射/错误分支/cookie header）
  - `QuotaProviderRegistryTests` 扩展为 codex + zenmux 断言
- 本轮验证命令：
  - `swift test`（20 tests, 0 failures）
  - `swift build`（success）
  - `swift run InfoBarApp`（启动成功，短时运行验证）

## 9. 2026-02-17 增量（ZenMux Cookie 真链路验证）

- ZenMux 浏览器 Cookie 导入改为参考 CodexBar 方案：
  - 新增 `SweetCookieKit` 依赖
  - 新增 `ZenMuxBrowserCookieImporter`（优先 Chrome，其次 Safari/Firefox）
  - `ZenMuxCookieStore` 优先级：
    1. 环境变量 `ZENMUX_COOKIE_HEADER` / `ZENMUX_SESSION_*`
    2. `HTTPCookieStorage.shared`
    3. 浏览器导入器（支持 Chrome 加密 Cookie 解密链路）
- 修复 ZenMux 真实响应映射：
  - 支持 `data` 为数组结构（真实返回）
  - 支持字段：`periodType`, `usedRate`, `cycleEndTime`
  - `usedRate`(0~1) 映射为百分比
  - `cycleEndTime`（带毫秒 ISO8601）正确解析
  - 按窗口优先级排序（`hour_5` 在 `week` 前）
- 新增/更新测试：
  - `testCookieHeaderFallsBackToBrowserImporter`
  - `testMapsRealZenMuxArrayPayload`
  - `testLiveProbeFetchesSnapshotWhenEnabled`（默认 skip，`ZENMUX_LIVE_PROBE=1` 触发）
- 本机实测结果：
  - `ZENMUX_LIVE_PROBE=1 swift test --filter ZenMuxUsageClientTests/testLiveProbeFetchesSnapshotWhenEnabled`
  - 结果：通过，确认可通过本地浏览器 Cookie 获取 ZenMux quota 并映射为 `QuotaSnapshot`

## 10. 2026-02-17 增量（可复用 Cookie Quota 能力）

- 新增通用能力：`BrowserQuotaCookieCollector`
  - 文件：`Sources/InfoBar/Modules/Quota/BrowserQuotaCookieCollector.swift`
  - 提供可配置抽象：
    - `domains`
    - `requiredCookieNames`
    - `preferredBrowsers`（chrome/safari/firefox）
  - 通过 `SweetCookieKit` 统一读取浏览器 Cookie（含 Chrome 解密链路）
- `ZenMuxBrowserCookieImporter` 改为配置驱动复用该能力：
  - 文件：`Sources/InfoBar/Modules/Quota/ZenMuxBrowserCookieImporter.swift`
  - 仅负责提供 ZenMux 配置，不再自带浏览器读取实现
- 菜单栏更新链路保持与 Codex一致并已联通：
  - `QuotaProviderRegistry` 注册 `zenmux`
  - `main.swift` 遍历 provider 创建 `MenuBarController + QuotaReader + QuotaModule + QuotaWidget`
  - ZenMux quota 会按同一链路更新到 Menu Bar（左 icon + 右双行风格保持不变）
- 新增测试：
  - `testZenMuxBrowserCookieImporterUsesReusableCollector`

## 11. 2026-02-17 增量（ZenMux 失败诊断增强）

- 为排查菜单栏 `H: -- -- / W: -- --` 增加可观测性：
  - `ZenMuxUsageClient` 在失败路径输出诊断日志（stderr）：
    - 401/403：打印 `status + body` 片段
    - 5xx/其他：打印 `status + body` 片段
    - 2xx 但 decode/map 失败：打印错误 + body 片段
  - `QuotaReader` 在 fetch 失败时输出 `fetcher 类型 + error`，不再静默吞掉错误
- 解析失败错误增强：
  - `ZenMuxUsageClientError.missingUsageData` 现在携带原始 payload 片段（若可序列化），便于判断字段不匹配
  - 对应测试已更新：`testThrowsWhenUsageFieldsMissing`
- 验证：
  - `swift test` 全量通过（24 tests，1 skipped）
  - `ZENMUX_LIVE_PROBE=1` live probe 通过
