# CLAUDE.md

## 目标

Info Bar：macOS 菜单栏应用，同屏展示多个 Coding Agent 的 Quota/Usage、一些其他必要的信息。

## 不可破坏约束

- Menu Bar 风格固定：左 icon + 右侧两行文本（Stats 风格）
- 两行格式：`<label>: <used%> <timeLeft>`
- 架构固定：`Module -> Reader -> Widget -> Popup`
- 领域模型固定：
  - `QuotaWindow(id, label, usedPercent, resetAt)`
  - `QuotaSnapshot(providerID, windows[], fetchedAt)`
- `QuotaDisplayModel` 仅按窗口渲染，不引入 provider 专用字段
- Settings UI 结构固定（见下方）

## Settings UI 架构

```
SettingsWindowController (NSPanel 640×440)
  ├── NSSplitViewController
  │     ├── ProviderListViewController  [左 200px fixed]
  │     │     └── NSTableView + ProviderRowView (NSTableCellView)
  │     │           drag handle | icon(isTemplate) | name | status dot
  │     └── ProviderDetailViewController  [右 flexible]
  │           header: 40×40 icon | name | "Updated: Xm ago" | Refresh
  │           USAGE: [label | NSProgressIndicator | XX% | (Xd left)]
  │           Show in menu bar: [label | spacer | NSSwitch]
  └── 数据流：
        onOrderChanged -> mountMenuBars -> NSStatusItem remount
        onRefreshRequested -> QuotaModule.refresh() -> QuotaReader.read()
```

## QuotaDisplayModel 语义（当前）

- H/W 场景固定行位：`top = W`, `bottom = H`
- 若 H 缺失：显示 `H: -- --`
- Pace 颜色算法（状态来源）：
  - `elapsed = 1 - remain/duration`
  - `expected = 0.8 * elapsed^1.1`
  - `urgency = max(0, expected-used)/0.8 * (0.35 + 0.65 * elapsed^1.6)`
  - `warning >= 0.30`, `critical >= 0.60`
- 特殊规则：**若 W 缺失且 H 存在，只按 H 计算 Pace 颜色**

## 已知 pitfall（不可重蹈）

1. **NSPanel + NSSplitViewController 折叠**：`panel.contentViewController = splitVC` 会将窗口 resize 到 `splitVC.preferredContentSize`，默认为 `.zero`，导致窗口折叠为标题栏。必须在赋值前设 `splitVC.preferredContentSize = NSSize(width: 640, height: 440)`。

2. **SVG isTemplate**：fill:white 的 SVG 在白底 NSImageView 中不可见。加载 provider icon 后必须设 `image.isTemplate = true`。

3. **NSStackView edgeInsets vs widthAnchor**：若 container 设了 `edgeInsets`，`container.widthAnchor` 是外框宽度（含 insets），arranged subview 的 `widthAnchor = container.widthAnchor` 会超出可用宽度。正确做法：padding 放在 container 的 anchor offset，`edgeInsets` 保持默认。

4. **NSStatusBar 挂载顺序**：`mountMenuBars` 用 `orderedIDs.reversed()` 逐个 `start()`，因为新 item 出现在已有 item 左侧。

5. **显示/隐藏导致顺序漂移**：切换可见性后必须按持久化顺序 remount，不能仅 `setVisible()`。

## 扩展新 Provider（最小流程）

1. 新建 `<Provider>UsageClient` 实现 `QuotaSnapshotFetching`
2. 将 provider 响应映射到 `QuotaSnapshot + [QuotaWindow]`
3. 在 `QuotaProviderRegistry.defaultProviders()` 注册
4. 补测试：解码/映射/回归

## Menu Bar 顺序管理

- 持久化：`ProviderOrderStore`（UserDefaults key `InfoBar.providerOrder`）
- 运行时：`AppDelegate.mountMenuBars(orderedIDs:)` — stop all -> reversed start
- 触发时机：
  - 启动时（按存储顺序）
  - `onOrderChanged`（拖拽后即时）
  - `onVisibilityChanged`（可见性切换后重挂载，确保顺序不漂移）

## 开发与提交规范

- 强制 TDD：RED -> GREEN -> REFACTOR
- 完成后至少执行：
  - `swift build`
  - `swift test`
  - `swift run InfoBarApp`
- Commit 使用 Conventional Commits
- 未明确要求时不 push

## 文档规则

- 每轮更新 `.context/HANDOFF.md`
- 覆盖 HANDOFF 前先归档到 `.context/archive/`
- 在新 HANDOFF 顶部写归档指针

## 文档读取策略

- 每轮必读：
  1. `.claude/CLAUDE.md`
  2. `.context/HANDOFF.md`
- 按需读：
  - `.context/DESIGN.md`（UI/交互改动时）
  - `.context/archive/*`（仅追溯历史时）
- 默认禁止：一次性全量读取 archive 或无关长文档

## 参考

- 当前交接：`.context/HANDOFF.md`
- 历史交接：`.context/archive/`
