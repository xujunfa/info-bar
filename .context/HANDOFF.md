# Info Bar Handoff (2026-02-19)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-19-settings-redesign-v1.md`
- 更早版本见各 archive 文件

## 1. 当前状态（已完成 & 已验证）

- 四个 Provider 正常运行：`codex`、`zenmux`、`minimax`、`bigmodel`
- **Settings UI Redesign 完成**：macOS split-pane 风格，拖拽重排、即时反映到 Menu Bar
- **三个 UI Bugfix 完成**：Panel 高度折叠、图标不可见、右侧 detail 布局溢出

## 2. 架构速览

```
AppDelegate (main.swift)
  ├── QuotaProviderRegistry.defaultProviders()
  ├── [MenuBarController]  — NSStatusItem × N，order 由 ProviderOrderStore 驱动
  ├── [QuotaModule]        — Reader + Widget，独立 fetch 循环
  ├── SettingsWindowController (NSPanel 640×440)
  │     ├── ProviderListViewController   — NSTableView + DnD
  │     └── ProviderDetailViewController — header + progress bars + NSSwitch
  ├── ProviderVisibilityStore  — UserDefaults "InfoBar.providerVisibility"
  └── ProviderOrderStore       — UserDefaults "InfoBar.providerOrder"
```

## 3. 本轮关键变更

### 3.1 SettingsProviderViewModel 扩展

| 新字段 | 说明 |
|--------|------|
| `WindowViewModel` (nested struct) | `label`, `usedPercent`, `timeLeft`（"2d"/"3h"/"45m"/"—"） |
| `windows: [WindowViewModel]` | 从 `snapshot.windows` 映射；`resetAt` → `timeLeft` |
| `fetchedAt: Date?` | 直接从 `snapshot.fetchedAt` 透传 |
| `summary: String` | 保留，向后兼容 |

### 3.2 SettingsWindowController 完全重写

**结构**
- NSPanel 640×440，`titled + closable + nonactivatingPanel`
- `preferredContentSize` 在赋值 `contentViewController` 前设置（否则 panel 折叠为标题栏）
- NSSplitViewController：左 200px 固定 / 右 flexible

**ProviderListViewController**
- NSTableView，rowHeight 36，无 header
- `ProviderRowView: NSTableCellView`：drag handle（`line.3.horizontal`）+ 20×20 icon（`isTemplate=true`）+ 13pt semibold name + 8px 状态点
- Drag & Drop：`NSPasteboardItem` 写 row index → `acceptDrop` 计算 `adjustedRow = fromRow < row ? row-1 : row` → `moveRow(at:to:)` 动画 → `onOrderChanged`
- `reload(viewModels:)` 按 providerID 恢复选中行

**ProviderDetailViewController**
- 无选中：居中显示 "Select a provider"
- 有选中：header（40×40 icon + 18pt bold name + "Updated: Xm ago"）→ divider → USAGE 区（`NSProgressIndicator.small` + "XX%" + "(Xd left)"）→ divider → Show in menu bar（`NSSwitch` via `@MainActor ToggleSwitchBridge`）
- 每次 `configure(viewModel:)` 完全 rebuild subviews
- **布局要点**：padding 放在 container 的 anchor offset（`constant: ±20`），不用 `edgeInsets`，使 `container.widthAnchor == 可用内容宽`，所有 `row.widthAnchor = container.widthAnchor` 精确成立

### 3.3 MenuBarController.stop()

```swift
public func stop() {
    if let item {
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        self.actionBridge = nil
    }
}
```
`statusView`（含已有 snapshot 数据）由 controller 持有，remount 时直接复用。

### 3.4 main.swift — mountMenuBars(orderedIDs:)

**两阶段启动**：Phase 1 创建所有 module/widget（不调 `start()`），Phase 2 按 `orderStore.orderedIDs` 顺序 mount。

```swift
private func mountMenuBars(orderedIDs: [String]) {
    // 停止所有现有 item
    for id in menuBarsByID.keys { menuBarsByID[id]?.stop() }
    // 倒序 mount：NSStatusBar 新 item 出现在最左侧
    for id in orderedIDs.reversed() {
        bar.start(); bar.setVisible(...); bar.update(snapshot: ...)
    }
}
```

`onOrderChanged` 现在直接调 `mountMenuBars(orderedIDs: newOrder)`，拖拽后 Menu Bar 即时响应。

### 3.5 SVG 图标 isTemplate

所有 provider SVG（`codex`/`bigmodel` = fill:white 路径，在白底不可见）统一设 `image.isTemplate = true`：
- 未选中行（白底）：渲染为深色
- 选中行（蓝底）：AppKit 自动渲染为白色

影响位置：`ProviderRowView.configure` 和 `ProviderDetailViewController.makeHeader`。

## 4. Bugfix 记录（本轮修复）

| # | 症状 | 根因 | 修复 |
|---|------|------|------|
| 1 | Panel 打开只显示标题栏 | `contentViewController = splitVC` 时 `preferredContentSize` 为 `.zero`，窗口折叠 | 赋值前设 `splitVC.preferredContentSize = NSSize(640, 440)` |
| 2 | codex/bigmodel 图标不可见 | SVG fill:white，白底透明 | `image.isTemplate = true` |
| 3 | 右侧 detail 布局溢出（progress bar 超出右边界） | `edgeInsets(20,20,20,20)` + `row.width = container.width` 导致 row 宽出 40px | padding 改为 anchor constant，`edgeInsets` 清零 |

## 5. 测试状态

- `swift test`：**63 passed, 0 failures, 1 skipped**
- `swift build`：**Build complete**

新增测试（本轮）：
- `SettingsProviderViewModelTests.testWindowsArePopulatedFromSnapshot`
- `SettingsProviderViewModelTests.testFetchedAtIsSet`

## 6. 公开 API（未变）

```swift
// SettingsWindowController
show()
update(viewModels: [SettingsProviderViewModel])
onVisibilityChanged: ((String, Bool) -> Void)?
onOrderChanged: (([String]) -> Void)?
window: NSPanel?
viewModels: [SettingsProviderViewModel]

// MenuBarController（新增）
stop()
```

## 7. 下轮建议

### 优先级高
- **Step 2.4 手动刷新**：detail 右上角加刷新按钮，触发该 provider 单次立即 fetch。需 `QuotaModule` 暴露 `triggerRead()` 或 `QuotaReader.readNow()`。

### 优先级中
- **Menu Bar 顺序方向校验**：当前用 `orderedIDs.reversed()` 假设 NSStatusBar 新 item 出现最左。如实测方向相反，删除 `.reversed()` 即可。
- **初始无数据状态**：provider 首次 fetch 前，detail 右侧 USAGE 区为空，考虑显示 loading placeholder。

### 优先级低
- **NSStatusItem 可见性 vs 顺序**：隐藏的 provider 仍在 fetch（预期行为）；remount 时隐藏 item 会短暂出现再隐藏，极低概率可见。

## 8. 关键文件索引

| 文件 | 职责 |
|------|------|
| `Sources/InfoBar/UI/Settings/SettingsWindowController.swift` | 全部 Settings UI（Panel + List + Detail） |
| `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift` | 设置面板数据模型 |
| `Sources/InfoBar/UI/Settings/ProviderOrderStore.swift` | 顺序持久化 |
| `Sources/InfoBar/UI/Settings/ProviderVisibilityStore.swift` | 可见性持久化 |
| `Sources/InfoBar/UI/MenuBar/MenuBarController.swift` | NSStatusItem 生命周期（含 stop()） |
| `Sources/InfoBarApp/main.swift` | 两阶段启动 + mountMenuBars |
| `Tests/InfoBarTests/UI/Settings/` | Settings 相关测试 |
