# Info Bar Handoff (2026-02-19)

## 0. 归档记录

- 本轮前版本已归档到：
  - `.context/archive/HANDOFF-2026-02-19-pace-and-refresh-before-update.md`
- 更早版本见 `.context/archive/`。

## 1. 当前状态（已完成 & 已验证）

- Provider 已接入：`codex`、`zenmux`、`minimax`、`bigmodel`
- Menu Bar 两行顺序已固定为：`W` 在上、`H` 在下
- Settings 已支持：
  - 拖拽排序（即时生效）
  - 显示/隐藏切换（保持原顺序）
  - 手动刷新当前 provider（Refresh 按钮）
- 配额颜色已切到 Pace 驱动（不是单纯 usedPercent 驱动）

## 2. 本轮关键变更

### 2.1 Provider & 图标/布局修复

- BigModel 标签映射改为 `H/W`，避免显示 `T/M`
  - `Sources/InfoBar/Modules/Quota/BigModelUsageClient.swift`
  - `Tests/InfoBarTests/Modules/Quota/BigModelUsageClientTests.swift`
- `minimax.svg` 资源改成与其他 icon 一致风格（`fill="white"`）
  - `Sources/InfoBar/Resources/Icons/minimax.svg`
- Menu 项间距收紧（statusWidth 104 -> 100）
  - `Sources/InfoBar/UI/MenuBar/QuotaLayoutMetrics.swift`
  - `Tests/InfoBarTests/UI/MenuBar/QuotaLayoutMetricsTests.swift`

### 2.2 H/W 渲染与顺序语义

- `QuotaDisplayModel` 从“按数组位置渲染”改为“识别 H/W 语义后固定行位”
- 当前规则：`top = W`，`bottom = H`
- 缺失 H 时：显示 `H: -- --`，不再把 W 顶到 H 行
  - `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
  - `Tests/InfoBarTests/Modules/Quota/QuotaDisplayModelTests.swift`

### 2.3 设置页刷新能力

- Settings 右侧 header 新增 `Refresh` 按钮
- 新增回调链路：
  - `SettingsWindowController.onRefreshRequested`
  - `AppDelegate` 接线到 `quotaModulesByID[providerID]?.refresh()`
  - `QuotaModule.refresh()` 触发单次 `reader.read()`
- 相关文件：
  - `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
  - `Sources/InfoBarApp/main.swift`
  - `Sources/InfoBar/Modules/Quota/QuotaModule.swift`
  - `Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`
  - `Tests/InfoBarTests/Modules/Quota/QuotaModuleTests.swift`

### 2.4 顺序漂移修复

- 修复“隐藏后再显示会跑到第一位”问题
- 策略：`onVisibilityChanged` 时按 `orderStore` 全量 remount，保证顺序稳定
  - `Sources/InfoBarApp/main.swift`

### 2.5 Pace 颜色算法（当前生效）

- 字体颜色由 `QuotaDisplayModel.State` 驱动，`QuotaStatusView` 上下两行同色：
  - `normal = labelColor`
  - `warning = systemOrange`
  - `critical = systemRed`
  - `unknown = systemGray`
- Pace 核心：
  - `elapsed = 1 - remain/duration`
  - `expected = 0.8 * elapsed^1.1`
  - `urgency = max(0, expected-used)/0.8 * (0.35 + 0.65 * elapsed^1.6)`
- 当前阈值：
  - `warningThreshold = 0.30`
  - `criticalThreshold = 0.60`
- 特殊规则：
  - **若 W 缺失且 H 存在，则只按 H 计算 Pace 颜色**
- 相关文件：
  - `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
  - `Sources/InfoBar/UI/MenuBar/QuotaStatusView.swift`
  - `Tests/InfoBarTests/Modules/Quota/QuotaDisplayModelTests.swift`

## 3. 当前测试状态

- `swift test`：**71 passed, 0 failed, 1 skipped**
- 新增测试：
  - `QuotaModuleTests.testRefreshPushesLatestSnapshotToWidget`
  - `QuotaDisplayModelTests` 中 Pace 与 H/W 行位相关用例（多条）

## 4. 已知行为与注意事项

- Settings 面板仍是 `NSPanel + nonactivatingPanel`，因此 `Cmd+W` 关闭行为不是标准 app-window 路径
- Pace 颜色目前是“提醒该用优先级”，不是“逼近 100% 用量”
- Pace 仅使用窗口本身 `usedPercent/resetAt`，不依赖 provider 专用字段

## 5. 下轮建议

### 高优先级

1. 为 Pace 增加用户可调参数（至少阈值/目标占比）：
   - `targetUsage`（默认 0.8）
   - `warning/critical` 阈值
2. 处理 `Cmd+W` 关闭设置窗（需要调整 panel 激活/关闭路径）

### 中优先级

1. 在 Settings 中展示 provider 的实时 Pace 分值（便于理解变色原因）
2. Refresh 按钮增加短暂 loading 状态（防重复点击）

## 6. 关键文件索引

- `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
- `Sources/InfoBar/UI/MenuBar/QuotaStatusView.swift`
- `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- `Sources/InfoBarApp/main.swift`
- `Sources/InfoBar/Modules/Quota/QuotaModule.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaDisplayModelTests.swift`
- `Tests/InfoBarTests/Modules/Quota/QuotaModuleTests.swift`
