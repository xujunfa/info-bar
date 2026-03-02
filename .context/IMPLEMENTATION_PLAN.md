# 实施计划

## 概览

- 项目：InfoBar 设置页 UI 优化与 Usage 信息增强
- 里程碑总数：5
- 创建日期：2026-03-02
- 最近更新：2026-03-02
- 当前执行阶段：里程碑 2
- 参考文档：`.context/DESIGN.md`（总体设计）、`.context/archive/HANDOFF-2026-02-19-settings-redesign-v1.md`（现有设置页实现背景）

---

## 里程碑 1：设置页视觉系统升级

**目标**：将现有设置页升级为更具层次感和信息密度的 macOS 风格界面，建立可复用的视觉规范。

### 任务

- [x] 1.1 抽取设置页主题 Token（颜色、间距、圆角、字号、阴影、状态色）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsTheme.swift`（新增）、`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [x] 1.2 重构 Panel 与 SplitView 的基础视觉（尺寸、背景材质、分割线、边距）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [x] 1.3 升级左侧 Provider 列表行样式（选中态、悬停态、状态点可读性、拖拽提示）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [x] 1.4 升级右侧空状态/无数据状态（引导文案 + 占位样式），避免信息断层
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [x] 1.5 为设置页基础视觉行为补齐回归测试（窗口参数、数据更新后状态稳定）
  - 文件：`Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`

### 验收标准

- 设置页在 640x440 与更大尺寸下保持层级清晰、间距一致。
- 左右区域视觉风格统一，交互态（选中/悬停/禁用）有明确反馈。
- 无选择/无数据时不再出现“空白断层”，有可理解占位信息。

---

## 里程碑 2：Usage 信息模型扩展

**目标**：将当前仅支持百分比的窗口模型扩展为可承载更多 usage 维度的数据结构。

### 任务

- [x] 2.1 扩展 `QuotaWindow` 结构，新增可选字段（used、limit、remaining、unit、windowTitle、metadata）
  - 文件：`Sources/InfoBar/Modules/Quota/QuotaSnapshot.swift`
- [x] 2.2 保持现有调用方兼容，完善默认值与边界处理（nil/负值/超限）
  - 文件：`Sources/InfoBar/Modules/Quota/QuotaSnapshot.swift`、`Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
- [x] 2.3 扩展 `SettingsProviderViewModel.WindowViewModel`，支持展示“百分比 + 绝对值 + 单位 + 重置信息”
  - 文件：`Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
- [x] 2.4 增加统一格式化工具（大数缩写、单位拼接、空值降级文案）
  - 文件：`Sources/InfoBar/UI/Settings/UsageFormatting.swift`（新增）、`Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
- [x] 2.5 更新模型测试覆盖新字段映射与格式化输出
  - 文件：`Tests/InfoBarTests/Modules/Quota/QuotaSnapshotTests.swift`、`Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`

### 验收标准

- `QuotaWindow` 能表达“百分比 + 绝对值 + 单位 + 周期”信息且不破坏现有路径。
- ViewModel 在字段缺失/半缺失情况下仍能输出稳定、可读文案。
- 现有菜单栏显示逻辑无行为回归。

---

## 里程碑 3：Provider Usage 映射增强

**目标**：按各 Provider 实际返回能力，尽可能提取更多 usage 信息并写入扩展模型。

### 任务

- [ ] 3.1 增强 Codex 映射，补充可推导字段并明确字段缺失时策略
  - 文件：`Sources/InfoBar/Modules/Quota/CodexUsageClient.swift`、`Tests/InfoBarTests/Modules/Quota/CodexUsageClientTests.swift`
- [ ] 3.2 增强 MiniMax 映射，输出 total/used/remaining 与周期信息
  - 文件：`Sources/InfoBar/Modules/Quota/MiniMaxUsageClient.swift`、`Tests/InfoBarTests/Modules/Quota/MiniMaxUsageClientTests.swift`
- [ ] 3.3 增强 BigModel 映射，覆盖 tokens/time 两类窗口的详细字段
  - 文件：`Sources/InfoBar/Modules/Quota/BigModelUsageClient.swift`、`Tests/InfoBarTests/Modules/Quota/BigModelUsageClientTests.swift`
- [ ] 3.4 增强 ZenMux 映射，尽量解析数组/对象两种 payload 下的补充字段
  - 文件：`Sources/InfoBar/Modules/Quota/ZenMuxUsageClient.swift`、`Tests/InfoBarTests/Modules/Quota/ZenMuxUsageClientTests.swift`
- [ ] 3.5 增强 Factory 映射，输出月度 token 维度的 used/limit/remaining 与 resetAt
  - 文件：`Sources/InfoBar/Modules/Quota/FactoryUsageClient.swift`、`Tests/InfoBarTests/Modules/Quota/FactoryUsageClientTests.swift`
- [ ] 3.6 对 Supabase Connector 读取链路补充字段稳定性测试（空记录、字段缺失、格式变化）
  - 文件：`Sources/InfoBar/Modules/Quota/SupabaseConnectorEventClient.swift`、`Tests/InfoBarTests/Modules/Quota/FactoryUsageClientTests.swift`

### 验收标准

- 五个 provider 的 snapshot 映射都能输出“可获取到的最大 usage 信息”。
- 字段缺失时按降级策略回退，不抛出无谓错误、不影响刷新链路。
- 所有 provider 映射测试通过。

---

## 里程碑 4：设置页信息呈现重构

**目标**：基于扩展后的 usage 数据，重构设置页详情区与列表摘要，显著提升信息丰富度和可读性。

### 任务

- [ ] 4.1 重构右侧 Header（Provider 标识、更新时间、刷新动作、状态标识）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [ ] 4.2 将 Usage 区升级为信息卡（进度条 + used/remaining/limit + 单位 + reset）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [ ] 4.3 增加窗口级补充信息展示（如模型/窗口类型/数据来源字段）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`、`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- [ ] 4.4 升级左侧列表摘要（主标题 + 次要 usage 摘要 + 可见性状态）
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`、`Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
- [ ] 4.5 保持现有交互能力（拖拽排序、显示开关、手动刷新）并修复潜在 UI 回归
  - 文件：`Sources/InfoBar/UI/Settings/SettingsWindowController.swift`、`Sources/InfoBarApp/main.swift`
- [ ] 4.6 补齐设置页展示层测试（ViewModel 输出、回调链路、关键文案）
  - 文件：`Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`、`Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`

### 验收标准

- 详情区能稳定展示多维 usage 信息，而非仅百分比。
- 列表与详情信息一致，不出现旧数据残留或切换错位。
- 拖拽、刷新、可见性开关仍可用且回调链路正确。

---

## 里程碑 5：回归验证与文档沉淀

**目标**：完成跨 provider 回归，沉淀字段映射规范与设置页展示规则，支持后续新增 provider 快速接入。

### 任务

- [ ] 5.1 执行 quota 相关全量测试并修复回归
  - 文件：`Tests/InfoBarTests/Modules/Quota/*`、`Tests/InfoBarTests/UI/Settings/*`
- [ ] 5.2 编写 provider usage 字段映射矩阵（字段来源、优先级、降级策略）
  - 文件：`docs/provider-usage-mapping.md`（新增）
- [ ] 5.3 编写设置页展示规范（卡片结构、文案规则、空态规则）
  - 文件：`docs/settings-ui-spec.md`（新增）
- [ ] 5.4 更新扩展与主程序协作文档（usage 丰富字段如何从采集端传递到 UI）
  - 文件：`extensions/info-bar-web-connector/README.md`、`docs/`
- [ ] 5.5 形成手工验收清单并记录结果
  - 文件：`docs/settings-qa-checklist.md`（新增）

### 验收标准

- `swift test` 全绿，重点模块（Quota/Settings）无回归失败。
- 文档能够指导新增 provider 按统一方式映射并在 UI 呈现。
- 设置页在视觉质量和信息密度上达到可交付状态。
