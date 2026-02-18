# Info Bar Handoff (2026-02-19)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-19-settings-split-pane-pre.md`
- 更早版本见各 archive 文件

## 1. 当前状态（已完成）

- 四个 Provider 正常运行：`codex`、`zenmux`、`minimax`、`bigmodel`
- Step 2.3 通过：↑/↓ 按钮排序（已被新实现替换）
- **Settings UI Redesign 完成**：Settings 面板完全重新设计为 macOS split-pane 风格

## 2. 本轮关键变更（Settings UI Redesign）

### 2.1 SettingsProviderViewModel 扩展

新增字段：
- `WindowViewModel` — 嵌套 struct：`label`, `usedPercent`, `timeLeft`（"2d"/"3h"/"45m"/"—"）
- `windows: [WindowViewModel]` — 从 snapshot.windows 映射
- `fetchedAt: Date?` — 直接从 snapshot 透传
- 保留：`summary: String`（向后兼容）

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`

### 2.2 SettingsWindowController 完全重写

#### 结构
- **NSPanel** 640×440，titled+closable+nonactivatingPanel
- **NSSplitViewController**（vertical divider）：左 200px 固定，右侧 flexible
- 移除：`ToggleBridge`、`ReorderBridge`、`FlippedStackView`

#### ProviderListViewController（private）
- **NSTableView**，row height 36，无 header
- **ProviderRowView**（NSTableCellView 子类）：⠿ 拖拽手柄 + 20×20 icon + 13pt semibold name + 8px 状态点（绿=可见/灰=隐藏）
- **Drag & Drop**：`NSPasteboardItem` 写入行 index → `acceptDrop` 计算 adjustedRow → `moveRow` 动画 → `onOrderChanged` 回调
- 选中恢复：`reload` 后按 providerID 恢复上次选中行

#### ProviderDetailViewController（private）
- 无选择时：居中显示 "Select a provider"
- 有选中时：
  - **Header**：40×40 icon（圆角 8）+ 18pt bold name + "Updated: Xm ago"
  - **Divider**（NSBox separator）
  - **USAGE 区**（仅有 windows 时显示）：每行 = 12pt mono label + NSProgressIndicator(small) + "XX%" + "(Xd left)"
  - **Divider**
  - **Show in menu bar**：NSSwitch target-action via `ToggleSwitchBridge(@MainActor)`
- 每次 `configure(viewModel:)` 完全重建 subviews

#### 数据流
1. 用户点击 toggle → `detailVC.onVisibilityChanged` → `main.swift` 更新 store → `settingsWindowController.update` → `listVC.reload` → 恢复选中 → `detailVC.configure`（新 isVisible 状态）
2. 用户拖拽行 → `listVC.onOrderChanged` → `main.swift` 写 ProviderOrderStore → `update` 刷新

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.3 新增测试（2 个）

- `SettingsProviderViewModelTests.testWindowsArePopulatedFromSnapshot` — 验证 windows 数组从 snapshot 正确映射，timeLeft="2d"
- `SettingsProviderViewModelTests.testFetchedAtIsSet` — 验证 fetchedAt 透传/nil

关键文件：
- `Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`

## 3. 运行与验证

- `swift test`：**63 passed, 0 failures, 1 skipped**
- `swift build`：**Build complete**
- 手动验证（待确认）：
  1. 打开设置 → 左侧列表显示 4 个 provider（icon + name + 状态点）
  2. 点击 provider → 右侧显示 usage bars + toggle
  3. 切换 "Show in menu bar" toggle → Menu Bar 图标即时显示/隐藏
  4. 拖拽行 → 顺序变化，重启后恢复
  5. ↑/↓ 按钮**已移除**

## 4. 公开 API 保持不变

- `SettingsWindowController.show()`
- `SettingsWindowController.update(viewModels:)`
- `SettingsWindowController.onVisibilityChanged`
- `SettingsWindowController.onOrderChanged`
- `SettingsWindowController.window`
- `SettingsWindowController.viewModels`

## 5. 下轮建议

### Step 2.4 — 手动刷新按钮
- 在 ProviderDetailViewController header 附近加刷新按钮
- 触发该 provider 立即 fetch
- 需要 `QuotaModule` 提供 per-provider 触发接口

## 6. 当前风险

1. `NSStatusItem` 不支持运行时重排；Menu Bar 物理顺序需 unmount + remount 实现（未实现）。
2. `NSSplitView` 左侧宽度固定 200px；右侧宽度由面板总宽决定。
3. Provider icon 加载：SVG via `Bundle.module.url(forResource:withExtension:subdirectory:)`，fallback 为 SF Symbol `circle.fill`。
