# Info Bar Handoff (2026-02-18)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-18-bigmodel-provider.md`
- 更早版本：
  - `.context/archive/HANDOFF-2026-02-18-bigmodel-before-update.md`
  - `.context/archive/HANDOFF-2026-02-18-minimax-provider-integration.md`
  - `.context/archive/HANDOFF-2026-02-17-minimax-before-update.md`
  - `.context/archive/HANDOFF-2026-02-17-zenmux-cookie-and-ui.md`
  - `.context/archive/HANDOFF-2026-02-17-pre-quota-refactor.md`

## 1. 当前状态（已完成）

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已接入四个真实 Provider：
  - `codex`、`zenmux`、`minimax`、`bigmodel`
- 菜单栏保持 Stats 风格：左 icon + 右侧双行文本（`<label>: <used%> <timeLeft>`）
- 主架构不变：`Module -> Reader -> Widget -> Popup`
- **新增（本轮）**：点击任意 Menu Bar 图标 → 打开 "InfoBar Settings" 窗口（阶段 1 完成）

## 2. 本轮关键变更（阶段 1：最小弹窗）

### 2.1 MenuBarController 新增 onClicked 回调

- 新增 `public var onClicked: (() -> Void)?`
- `start()` 内用私有 `ButtonActionBridge: NSObject` 将 `NSStatusBarButton` 的 target/action 转发给 `onClicked`
- 一条点击通路，无多余兜底

关键文件：
- `Sources/InfoBar/UI/MenuBar/MenuBarController.swift`

### 2.2 SettingsWindowController（新建）

- 新增 `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- `public private(set) var window: NSWindow?`（初始为 nil）
- `show()` 首次调用时创建窗口（标题 "InfoBar Settings"，占位内容 "Settings Coming Soon"）
- 二次调用复用同一窗口（`makeKeyAndOrderFront`）

关键文件：
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`

### 2.3 main.swift 接入

- `AppDelegate` 持有共享 `settingsWindowController`
- 每个 provider 的 `menuBar.onClicked` 均指向 `settingsWindowController.show()`

关键文件：
- `Sources/InfoBarApp/main.swift`

## 3. 运行与验证

- 构建：`swift build`
- 测试：`swift test`
- 启动：`swift run InfoBarApp`

最新结果（本地）：
- `swift test`：`42 tests`，`0 failures`，`1 skipped`
- `swift build`：通过

## 4. 关键测试

- `Tests/InfoBarTests/UI/MenuBar/MenuBarControllerTests.swift`
  - `testOnClickedCallbackCanBeSetAndInvoked`
- `Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`
  - `testShowCreatesWindow`
  - `testWindowHasCorrectTitle`
  - `testCallingShowTwiceReusesSameWindow`

## 5. 下轮建议（阶段 2，等人工确认阶段 1 后再执行）

### Step 2.1 — provider 列表只读展示
- 在 Settings 窗口内显示 provider id + 快照简要信息（只读，无交互）

### Step 2.2 — 显示/隐藏开关（持久化）
- 每个 provider 可切换显示/隐藏，默认全展示
- 持久化到 UserDefaults，无效配置回退全展示

### Step 2.3 — 上移/下移（持久化顺序）
- 运行时顺序立即生效

### Step 2.4 — 手动刷新按钮
- 点击触发该 provider 立即 read

## 6. 当前风险

1. `NSApp.activate(ignoringOtherApps: true)` 在 `.accessory` 激活策略下可能无效，若窗口无法获得焦点，需在 `show()` 内改用 `w.orderFrontRegardless()`。
2. `ButtonActionBridge` 使用 `[weak self]`，如果 `MenuBarController` 被提前释放，点击将无响应——调用方需保持 `MenuBarController` 强引用（`AppDelegate` 已持有 `menuBars` 数组，安全）。
