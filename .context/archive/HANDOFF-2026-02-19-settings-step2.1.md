# Info Bar Handoff (2026-02-18)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-18-settings-stage1.md`
- 更早版本见该文件内的归档记录

## 1. 当前状态（已完成）

- 四个 Provider 正常运行：`codex`、`zenmux`、`minimax`、`bigmodel`
- 菜单栏保持 Stats 风格
- **阶段 1 通过**：点击任意 Menu Bar 图标 → 弹出 "InfoBar Settings" 面板
- **Step 2.1 完成**：设置面板内展示 Provider 列表（只读）

## 2. 本轮关键变更（Step 2.1）

### 2.1 SettingsProviderViewModel（新建）

- 纯数据模型，输入 `providerID + QuotaSnapshot?`，输出 `providerID + summary`
- summary 格式：`"T: 45%  M: 30%"`；无 snapshot 或 windows 为空时显示 `"—"`

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`

### 2.2 SettingsWindowController 更新

- 新增 `public private(set) var viewModels: [SettingsProviderViewModel]`
- 新增 `public func update(viewModels:)` — 存储并刷新 UI
- 占位 `SettingsPlaceholderViewController` 替换为 `ProviderListViewController`
  - 使用 `NSStackView` 逐行展示：左 provider ID（等宽粗体）+ 右 summary（次级颜色）
  - `reload(viewModels:)` 清空重建行，空时显示占位文字

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.3 main.swift 数据流接入

- `AppDelegate` 维护 `[String: QuotaSnapshot?]` 字典（初始全为 nil）
- 每次 `widget.onSnapshot` 回调时更新字典并调用 `pushSnapshotsToSettings`
- `pushSnapshotsToSettings` 按 registry 顺序构建 viewModels 推送给设置面板

关键文件：
- `Sources/InfoBarApp/main.swift`

## 3. 运行与验证

- 构建：`swift build`
- 测试：`swift test`（47 passed, 0 failures, 1 skipped）
- 启动：`swift run InfoBarApp`，点击图标 → 面板内展示 4 个 provider 行

## 4. 关键测试

新增：
- `Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`
  - `testNilSnapshotShowsDash`
  - `testSnapshotWithSingleWindowShowsFormatted`
  - `testSnapshotWithMultipleWindowsJoinsWithSpaces`
  - `testEmptyWindowsShowsDash`
- `SettingsWindowControllerTests.testUpdateStoresViewModels`

## 5. 下轮建议（等人工确认 Step 2.1 后继续）

### Step 2.2 — 显示/隐藏开关（持久化）
- 每个 provider 可切换显示/隐藏，默认全展示
- 持久化到 `UserDefaults`；无效配置回退全展示
- 隐藏的 provider MenuBarController 从状态栏移除（或 hide）

### Step 2.3 — 上移/下移（持久化顺序）
- 运行时顺序立即生效

### Step 2.4 — 手动刷新按钮
- 点击触发该 provider 立即 read

## 6. 当前风险

1. `ProviderListViewController` 未加 `NSScrollView`，provider 数量多时内容可能被截断（当前 4 个无问题）。
2. `AppDelegate.snapshots` 为 `[String: QuotaSnapshot?]`，dict 内 value 是双重 optional（`QuotaSnapshot??`），`pushSnapshotsToSettings` 中用 `?? nil` 展开，逻辑正确但稍显绕。
