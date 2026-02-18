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
  │           header: 40×40 icon | name | "Updated: Xm ago"
  │           USAGE: [label | NSProgressIndicator | XX% | (Xd left)]
  │           Show in menu bar: [label | spacer | NSSwitch]
  └── 数据流：onOrderChanged → mountMenuBars → NSStatusItem remount
```

**已知 pitfall（不可重蹈）：**

1. **NSPanel + NSSplitViewController 折叠**：`panel.contentViewController = splitVC` 会将窗口 resize 到 `splitVC.preferredContentSize`，默认为 `.zero`，导致窗口折叠为标题栏。**必须在赋值前设** `splitVC.preferredContentSize = NSSize(width: 640, height: 440)`。

2. **SVG isTemplate**：fill:white 的 SVG 在白底 NSImageView 中不可见。加载 provider icon 后必须设 `image.isTemplate = true`，AppKit 才会自动适配选中/未选中背景色。

3. **NSStackView edgeInsets vs widthAnchor**：若 container 设了 `edgeInsets`，`container.widthAnchor` 是外框宽度（含 insets），arranged subview 的 `widthAnchor = container.widthAnchor` 会宽出 `insets.left + insets.right`。**正确做法**：padding 放在 container 的 anchor offset（`constant: ±N`），`edgeInsets` 保持默认，使 `container.widthAnchor == 可用内容宽`。

4. **NSStatusBar 挂载顺序**：`mountMenuBars` 用 `orderedIDs.reversed()` 逐个 `start()`，因为 NSStatusBar 新 item 出现在已有 item 的左侧。若实测顺序相反，删除 `.reversed()` 即可。

## 扩展新 Provider（最小流程）

1. 新建 `<Provider>UsageClient` 实现 `QuotaSnapshotFetching`
2. 将 provider 响应映射到 `QuotaSnapshot + [QuotaWindow]`
3. 在 `QuotaProviderRegistry.defaultProviders()` 注册
4. 补测试：解码/映射/回归

## Menu Bar 顺序管理

- 持久化：`ProviderOrderStore`（UserDefaults key `"InfoBar.providerOrder"`）
- 运行时：`AppDelegate.mountMenuBars(orderedIDs:)` — stop all → reversed start
- 触发时机：启动时（按存储顺序）、`onOrderChanged`（拖拽后即时）

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
  - `/Users/xujunfa/Documents/workspace/github/CodexBar/.context/codex.md`（Codex 接入相关）
  - `.context/archive/*`（仅追溯历史时）
- 默认禁止：一次性全量读取 archive 或无关长文档

## 参考

- 当前交接：`.context/HANDOFF.md`
- 历史交接：`.context/archive/`
