# Info Bar Handoff (2026-02-19)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-19-settings-step2.1.md`
- 更早版本见各 archive 文件

## 1. 当前状态（已完成）

- 四个 Provider 正常运行：`codex`、`zenmux`、`minimax`、`bigmodel`
- 阶段 1 通过：点击 Menu Bar 图标 → 弹出 "InfoBar Settings" 面板（NSPanel）
- Step 2.1 通过：面板内展示 Provider 列表 + 实时 snapshot 数据（只读）
- **Step 2.2 完成**：每行增加 checkbox toggle，持久化到 UserDefaults；隐藏时对应 NSStatusItem 立即消失；重启后恢复上次配置；无效配置回退全展示

## 2. 本轮关键变更（Step 2.2）

### 2.1 ProviderVisibilityStore（新建）

- UserDefaults key：`"InfoBar.providerVisibility"`，存储 `[String: Bool]`
- `isVisible(providerID:)` — 未找到或类型非法时返回 `true`（回退全展示）
- `setVisible(_:providerID:)` — 写入并持久化

关键文件：
- `Sources/InfoBar/UI/Settings/ProviderVisibilityStore.swift`

### 2.2 SettingsProviderViewModel 新增 isVisible

- `init(providerID:snapshot:isVisible:)`，`isVisible` 默认 `true`，向后兼容

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`

### 2.3 SettingsWindowController 新增 onVisibilityChanged

- `public var onVisibilityChanged: ((String, Bool) -> Void)?`
- ProviderListViewController 每行加 checkbox（`NSButton.checkboxWithTitle`）
- checkbox state 由 `vm.isVisible` 初始化；切换时通过 `ToggleBridge` 回调

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.4 MenuBarController 新增 setVisible

- `public func setVisible(_ visible: Bool)` → `item?.isVisible = visible`

关键文件：
- `Sources/InfoBar/UI/MenuBar/MenuBarController.swift`

### 2.5 main.swift 完整接入

- `AppDelegate` 持有 `ProviderVisibilityStore`
- 启动时：`menuBar.start()` 后立即 `setVisible(visibilityStore.isVisible(providerID:))`
- `onVisibilityChanged` 回调：更新 store → 更新 menuBar 可见性 → 刷新设置面板
- `pushSnapshotsToSettings` 现在带 `isVisible` 字段

关键文件：
- `Sources/InfoBarApp/main.swift`

## 3. 运行与验证

- `swift test`：**55 passed, 0 failures, 1 skipped**
- `swift build`：**Build complete**
- 手动验证：
  1. 取消某个 provider 的 checkbox → 对应 Menu Bar 图标立即消失
  2. 重启 app → 消失状态持久化
  3. 重新勾选 → 图标立即恢复

## 4. 关键测试（新增）

- `Tests/InfoBarTests/UI/Settings/ProviderVisibilityStoreTests.swift`（5 个）
  - `testDefaultVisibilityIsTrue`
  - `testSetFalsePersists`
  - `testSetTrueAfterFalsePersists`
  - `testOtherProviderUnaffected`
  - `testInvalidStoredTypeFallsBackToVisible`
- `SettingsProviderViewModelTests.testIsVisibleDefaultsToTrue`
- `SettingsProviderViewModelTests.testIsVisibleCanBeSetFalse`
- `SettingsWindowControllerTests.testOnVisibilityChangedCallbackIsFired`

## 5. 下轮建议（等人工确认 Step 2.2 后继续）

### Step 2.3 — 上移/下移（持久化顺序）
- 每行加 ↑ / ↓ 按钮
- 顺序持久化到 UserDefaults（key: `InfoBar.providerOrder`，存 `[String]`）
- 运行时 Menu Bar 顺序立即跟随

### Step 2.4 — 手动刷新按钮
- 每行加刷新按钮，触发该 provider 立即 read（需要 `QuotaReader` 暴露 `readNow()` 或类似入口）

## 6. 当前风险

1. `NSStatusItem.isVisible = false` 后，该 item 在 Menu Bar 中消失，但 `QuotaModule` 仍在定时 fetch。这是预期行为（数据继续刷新，重新显示时立即有数据），若需彻底省电可扩展 `unmount()`。
2. `ToggleBridge` 使用 `[weak self]` 指向 `ProviderListViewController`，VC 释放后 toggle 回调无效——正常，因为 VC 随 panel 一起存活。
