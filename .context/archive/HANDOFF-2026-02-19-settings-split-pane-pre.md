# Info Bar Handoff (2026-02-19)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-19-settings-step2.2.md`
- 更早版本见各 archive 文件

## 1. 当前状态（已完成）

- 四个 Provider 正常运行：`codex`、`zenmux`、`minimax`、`bigmodel`
- 阶段 1 通过：点击 Menu Bar 图标 → 弹出 "InfoBar Settings" 面板（NSPanel）
- Step 2.1 通过：面板内展示 Provider 列表 + 实时 snapshot 数据（只读）
- Step 2.2 通过：每行 checkbox toggle，持久化可见性到 UserDefaults
- **Step 2.3 完成**：每行加 ↑/↓ 按钮，持久化顺序到 UserDefaults；设置面板即时刷新；重启后恢复上次顺序

## 2. 本轮关键变更（Step 2.3）

### 2.1 ProviderOrderStore（新建）

- UserDefaults key：`"InfoBar.providerOrder"`，存储 `[String]`
- `orderedIDs(defaultIDs:)` — 仅当存储的 ID 集合与 defaultIDs 完全一致时生效；否则回退 defaultIDs（包含空数组/非法类型）
- `setOrder(_ ids: [String])` — 写入并持久化

关键文件：
- `Sources/InfoBar/UI/Settings/ProviderOrderStore.swift`

### 2.2 SettingsWindowController 新增 onOrderChanged

- `public var onOrderChanged: (([String]) -> Void)?`
- 传递给 `ProviderListViewController`

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.3 ProviderListViewController 新增 ↑/↓ 按钮

- `ReorderBridge: NSObject`，@MainActor 桥接 ↑/↓ button target-action → 闭包
- `currentViewModels` 内部持有当前顺序，`move(from:to:)` 执行 swapAt → callback → rebuildRows
- ↑/↓ 按钮 `isEnabled` 根据当前索引自动置灰（首行禁 ↑，末行禁 ↓）

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.4 main.swift 接入 ProviderOrderStore

- `AppDelegate` 持有 `ProviderOrderStore`
- `pushSnapshotsToSettings(defaultIDs:)` 改用 `orderStore.orderedIDs(defaultIDs:)` 排序
- `onOrderChanged` 回调：写 store → 刷新设置面板

关键文件：
- `Sources/InfoBarApp/main.swift`

## 3. 运行与验证

- `swift test`：**61 passed, 0 failures, 1 skipped**
- `swift build`：**Build complete**
- 手动验证：
  1. 点击 ↑/↓ 按钮 → 设置面板内行顺序立即变化
  2. 重启 app → 顺序持久化恢复
  3. ↑/↓ 按钮在首/末行正确置灰

## 4. 关键测试（新增 6 个）

- `Tests/InfoBarTests/UI/Settings/ProviderOrderStoreTests.swift`（5 个）
  - `testDefaultOrderReturnsDefaultIDs`
  - `testSetOrderPersists`
  - `testOrderWithDifferentIDSetFallsBackToDefault`
  - `testInvalidStoredTypeFallsBackToDefault`
  - `testEmptyStoredOrderFallsBackToDefault`
- `SettingsWindowControllerTests.testOnOrderChangedCallbackIsFired`（1 个）

## 5. 下轮建议（等人工确认 Step 2.3 后继续）

### Step 2.4 — 手动刷新按钮
- 每行加刷新按钮，触发该 provider 立即 read
- 需要 `QuotaReader` 暴露 `readNow()` 或类似入口（或 `QuotaModule` 提供 per-provider 触发接口）

## 6. 当前风险

1. `NSStatusItem` 不支持运行时直接重排，Menu Bar 的物理顺序不随 ↑/↓ 改变；只有设置面板内顺序和下次启动顺序会生效。如需运行时 Menu Bar 重排，需 unmount + remount（复杂，暂不实现）。
2. 同 Step 2.2：隐藏的 provider 仍在定时 fetch，为预期行为。
