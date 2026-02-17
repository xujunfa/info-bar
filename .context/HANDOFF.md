# Info Bar Handoff (2026-02-17)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-17-zenmux-cookie-and-ui.md`
- 更早版本：
  - `.context/archive/HANDOFF-2026-02-17-pre-quota-refactor.md`

## 1. 当前状态（已完成）

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已接入两个真实 Provider：
  - `codex`（OAuth/Auth 文件 + usage API）
  - `zenmux`（本地浏览器 Cookie + subscription usage API）
- 菜单栏保持 Stats 风格：左 icon + 右侧双行文本（`<label>: <used%> <timeLeft>`）
- ZenMux 已同屏展示（独立菜单栏项）并使用独立图标 `zenmux.svg`

## 2. 本轮关键变更

### 2.1 多 Provider 同屏链路

- `QuotaProviderRegistry.defaultProviders()` 已包含 `codex` + `zenmux`
- `main.swift` 遍历 provider 创建：
  - `MenuBarController(providerID:)`
  - `QuotaReader(fetcher:)`
  - `QuotaModule`
  - `QuotaWidget`

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`
- `Sources/InfoBarApp/main.swift`

### 2.2 ZenMux 真实 Quota 接入

- `ZenMuxUsageClient` 实现 `QuotaSnapshotFetching`
- 已适配 ZenMux 真实返回结构：`data[]`, `periodType`, `usedRate`, `cycleEndTime`
- `usedRate`(0~1) -> 百分比映射
- 窗口排序优先级：`hour_5` > `day` > `week` > `month`

关键文件：
- `Sources/InfoBar/Modules/Quota/ZenMuxUsageClient.swift`

### 2.3 浏览器 Cookie 可复用能力（后续可扩展）

- 新增通用收集器 `BrowserQuotaCookieCollector`
- 可配置项：
  - `domains`
  - `requiredCookieNames`
  - `preferredBrowsers`（chrome/safari/firefox）
- `ZenMuxBrowserCookieImporter` 改为配置驱动复用该能力

关键文件：
- `Sources/InfoBar/Modules/Quota/BrowserQuotaCookieCollector.swift`
- `Sources/InfoBar/Modules/Quota/ZenMuxBrowserCookieImporter.swift`

### 2.4 Cookie 优先级修复（解决 401）

- `ZenMuxCookieStore` 当前优先级：
  1. 环境变量（`ZENMUX_COOKIE_HEADER` / `ZENMUX_SESSION_*`）
  2. 浏览器导入器（SweetCookieKit）
  3. 进程内 `HTTPCookieStorage`
- 目的：避免运行时匿名 Cookie 覆盖浏览器已登录 Cookie 导致持续 401

关键文件：
- `Sources/InfoBar/Modules/Quota/ZenMuxUsageClient.swift`

### 2.5 菜单栏图标按 Provider 选择

- `QuotaStatusView` 支持按 `providerID` 加载 `<providerID>.svg`
- 找不到资源时 fallback 到 `codex.svg` 和 SF Symbol

关键文件：
- `Sources/InfoBar/UI/MenuBar/QuotaStatusView.swift`
- `Sources/InfoBar/UI/MenuBar/MenuBarController.swift`
- `Sources/InfoBar/Resources/Icons/zenmux.svg`

### 2.6 剩余时间显示规则更新

- `> 1d`：显示天数（1 位小数），例如 `3.5d`
- `< 1h`：显示分钟，例如 `45min`
- 其余：显示小时（整数或 1 位小数）

关键文件：
- `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`

### 2.7 失败诊断增强

- `ZenMuxUsageClient` 失败路径打印：`status + body 片段`
- `QuotaReader` 失败打印：`fetcher 类型 + error`
- `missingUsageData` 可携带原始 payload 片段

关键文件：
- `Sources/InfoBar/Modules/Quota/ZenMuxUsageClient.swift`
- `Sources/InfoBar/Modules/Quota/QuotaReader.swift`

## 3. 运行与验证

- 构建：`swift build`
- 测试：`swift test`
- 启动：`swift run InfoBarApp`
- ZenMux live probe（可选）：
  - `ZENMUX_LIVE_PROBE=1 swift test --filter ZenMuxUsageClientTests/testLiveProbeFetchesSnapshotWhenEnabled`

最新结果（本地）：
- `swift test`：`26 tests`，`0 failures`，`1 skipped`
- `swift build`：通过
- live probe：通过

## 4. 关键测试

- `Tests/InfoBarTests/Modules/Quota/ZenMuxUsageClientTests.swift`
  - `testMapsRealZenMuxArrayPayload`
  - `testCookieHeaderPrefersBrowserImporterOverRuntimeCookieStorage`
  - `testZenMuxBrowserCookieImporterUsesReusableCollector`
  - `testLiveProbeFetchesSnapshotWhenEnabled`（默认 skip）
- `Tests/InfoBarTests/Modules/Quota/QuotaDisplayModelTests.swift`
  - 天/分钟时间展示规则回归
- `Tests/InfoBarTests/Modules/Quota/QuotaProviderRegistryTests.swift`
  - codex + zenmux 注册回归

## 5. 下轮建议

1. 把诊断日志切到可配置开关（DEBUG/ENV），避免长期 stderr 噪声。
2. 增加 provider 级错误状态（auth/network/parse）并透传到显示层，不再统一 `-- --`。
3. 若继续新增 Provider，复用 `BrowserQuotaCookieCollector`，仅新增 importer 配置 + usage 映射。
