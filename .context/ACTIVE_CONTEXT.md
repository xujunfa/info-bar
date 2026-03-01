# 活跃上下文

## 当前状态

- 阶段：execute
- 里程碑：2 — Usage 信息模型扩展（当前）
- 状态：未开始
- 最后更新：2026-03-02

## 里程碑进度

### 已完成

- [x] 里程碑 1 完成：设置页视觉系统升级（1.1 ~ 1.5 全部完成并在计划中打勾）。
- [x] 新增 `SettingsTheme.swift`，统一设置页颜色、间距、圆角、字号、阴影和状态色 Token。
- [x] 重构 `SettingsWindowController.swift`：Panel/SplitView 材质与边距、左侧列表选中/悬停/拖拽提示、右侧空状态与无 usage 占位。
- [x] 扩展 `SettingsWindowControllerTests.swift`，覆盖窗口参数、分栏布局、空状态与刷新后选择稳定性。
- [x] 回归测试通过：`swift test --filter SettingsWindowControllerTests`（12 passed）。

### 进行中

- 设置页第 2 轮微调准备中：已完成本轮“原生优先”收敛 commit 前整理，下一步按字体权重、左栏宽度、状态点位置继续微调。

### 待完成

- [ ] 设置页第 2 轮微调（字体权重、左栏宽度、状态点位置），完成后再进入里程碑 2 数据模型改造。
- [ ] 2.1 扩展 `QuotaWindow` 结构，新增可选字段（used、limit、remaining、unit、windowTitle、metadata）。
- [ ] 2.2 保持现有调用方兼容，完善默认值与边界处理（nil/负值/超限）。
- [ ] 2.3 扩展 `SettingsProviderViewModel.WindowViewModel`，支持展示“百分比 + 绝对值 + 单位 + 重置信息”。
- [ ] 2.4 增加统一格式化工具（大数缩写、单位拼接、空值降级文案）。
- [ ] 2.5 更新模型测试覆盖新字段映射与格式化输出。

## 交接备注

- 里程碑 1 关键落地文件：
  - `Sources/InfoBar/UI/Settings/SettingsTheme.swift`（新增）
  - `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
  - `Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`
- 当前设置页窗口结构已回归为：`NSPanel -> NSSplitViewController`（移除了自定义容器层）。
- 里程碑 2 建议执行顺序：先改 `QuotaSnapshot` 与相关测试，再推进 `SettingsProviderViewModel` 和 `UsageFormatting.swift`。
- 用户已确认继续进行设置页第 2 轮微调，目标点位：字体权重、左栏宽度、状态点位置。
- 当前仅跑了设置页定向测试；全量 `swift test` 尚未执行。

## 最近变更

- 2026-03-02：完成里程碑 1 全部任务，设置页视觉系统升级落地。
- 2026-03-02：更新 `.context/IMPLEMENTATION_PLAN.md`，里程碑 1 勾选完成并推进当前执行阶段到里程碑 2。
- 2026-03-02：更新 `.context/ACTIVE_CONTEXT.md`，将当前里程碑切换为 `2 — Usage 信息模型扩展`。
- 2026-03-02：根据用户反馈收敛设置页样式，移除非原生重装饰（透明容器边框/重分割线/过重选中态），回归更接近 macOS 原生视觉。
