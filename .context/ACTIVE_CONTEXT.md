# 活跃上下文

## 当前状态

- 阶段：execute
- 里程碑：3 — Provider Usage 映射增强（当前）
- 状态：未开始
- 最后更新：2026-03-02

## 里程碑进度

### 已完成

- [x] 里程碑 1 完成：设置页视觉系统升级（1.1 ~ 1.5 全部完成并在计划中打勾）。
- [x] 里程碑 2 完成：Usage 信息模型扩展（2.1 ~ 2.5 全部完成并在计划中打勾）。
- [x] `QuotaWindow` 扩展字段落地：`used/limit/remaining/unit/windowTitle/metadata`，并补齐边界清洗（nil/负值/超限、字符串去空、metadata 过滤）。
- [x] 新增 `UsageFormatting.swift`，统一处理大数缩写、单位拼接、空值降级与 reset 文案。
- [x] 扩展 `SettingsProviderViewModel.WindowViewModel`，新增 `absoluteUsageText` 与 `resetText`；支持 `windowTitle` 优先显示。
- [x] 更新设置页 usage 行渲染：显示百分比、绝对值、reset 提示。
- [x] `QuotaDisplayModel` 增加窗口 label 为空时的兜底回退。
- [x] 里程碑 2 回归通过：
  - `swift test --filter 'QuotaSnapshotTests|SettingsProviderViewModelTests'`
  - `swift test --filter 'QuotaDisplayModelTests|SettingsWindowControllerTests'`

### 进行中

- 无。

### 待完成

- [ ] 3.1 增强 Codex 映射，补充可推导字段并明确字段缺失时策略。
- [ ] 3.2 增强 MiniMax 映射，输出 total/used/remaining 与周期信息。
- [ ] 3.3 增强 BigModel 映射，覆盖 tokens/time 两类窗口的详细字段。
- [ ] 3.4 增强 ZenMux 映射，尽量解析数组/对象两种 payload 下的补充字段。
- [ ] 3.5 增强 Factory 映射，输出月度 token 维度的 used/limit/remaining 与 resetAt。
- [ ] 3.6 对 Supabase Connector 读取链路补充字段稳定性测试（空记录、字段缺失、格式变化）。

## 交接备注

- 里程碑 2 关键文件：
  - `Sources/InfoBar/Modules/Quota/QuotaSnapshot.swift`
  - `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
  - `Sources/InfoBar/UI/Settings/UsageFormatting.swift`（新增）
  - `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
  - `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
  - `Tests/InfoBarTests/Modules/Quota/QuotaSnapshotTests.swift`
  - `Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`
- 建议里程碑 3 执行顺序：先 `Factory/BigModel`（已有绝对值来源明显），再 `MiniMax/Codex/ZenMux`，最后补齐映射回归测试。
- 当前未跑全量 `swift test`；仅执行了里程碑 2 相关定向测试。

## 最近变更

- 2026-03-02：完成里程碑 2 全部任务并在 `.context/IMPLEMENTATION_PLAN.md` 勾选 2.1~2.5。
- 2026-03-02：推进当前执行里程碑到 `3 — Provider Usage 映射增强`。
- 2026-03-02：修复设置页交互问题：菜单栏点击特定 Provider 时设置页可预选该 Provider；支持 `⌘W` 关闭设置页窗口，并通过 `SettingsWindowControllerTests`（18 项）回归。
- 2026-03-02：修复“菜单栏预选后左侧未高亮”问题：`ProviderListRowView` 在 `rowViewForRow` 创建时同步 selected/hovered 状态，并新增回归测试覆盖。
