# 活跃上下文

## 当前状态

- 阶段：execute
- 里程碑：5 — 回归验证与文档沉淀（当前）
- 状态：进行中
- 最后更新：2026-03-02

## 里程碑进度

### 已完成

- [x] 里程碑 1 完成：设置页视觉系统升级（1.1 ~ 1.5）。
- [x] 里程碑 2 完成：Usage 信息模型扩展（2.1 ~ 2.5）。
- [x] 里程碑 3 完成：Provider Usage 映射增强（3.1 ~ 3.6）。
- [x] 里程碑 4 完成：设置页信息呈现重构（4.1 ~ 4.6）。
- [x] 里程碑 5.1（阶段性）完成两轮用户反馈修正并通过设置页定向测试。

### 进行中

- 5.1 全量回归收口：设置页定向行为已稳定，待执行全量 `swift test` 验证跨模块无回归。

### 待完成

- [ ] 5.1 执行 quota 相关全量测试并修复回归。
- [ ] 5.2 编写 provider usage 字段映射矩阵文档。
- [ ] 5.3 编写设置页展示规范文档。
- [ ] 5.4 更新扩展与主程序协作文档。
- [ ] 5.5 形成手工验收清单并记录结果。

## 交接备注

- 本轮（用户反馈优化）关键改动文件：
  - `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
  - `Sources/InfoBar/UI/Settings/SettingsTheme.swift`
  - `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
  - `Tests/InfoBarTests/UI/Settings/SettingsProviderViewModelTests.swift`
  - `Tests/InfoBarTests/UI/Settings/SettingsWindowControllerTests.swift`
  - `.context/DECISIONS.md`（追加 DEC-010/DEC-011）
- 已落地的 UI/信息架构调整：
  - 左侧列表仅显示 provider 名称 + `Updated: ...`（移除 `Visible` 与用量摘要）。
  - 右上保留无标签可见性开关 + Refresh，底部开关行已移除。
  - Usage 卡片移除 metadata 噪声信息，仅展示用量与 reset 时间。
  - Refresh 点击反馈：短暂禁用并显示 `Refreshing usage...`。
  - reset 文案升级为绝对时间 + 相对剩余：`resets at MM-dd HH:mm (in X)`。
  - 无数据指标不展示（不再出现 `-` 占位）；tokens 场景新增 `TOKENS (M)`。
  - Header 在 `ID` 同行展示 `Account`（当 metadata 含邮箱/手机号等账号标识时）。
- 本轮新增修正（第二轮反馈）：
  - 5h/周窗口命名统一：`Current interval/H` 统一为 `5-hour usage`，`W` 统一为 `Weekly usage`。
  - 左侧列表行高提升到 46，并恢复可见性状态小圆点（绿色=显示、灰色=隐藏）。
  - Refresh 改为更紧凑按钮，点击显示 spinner 加载态，反馈时长缩短到约 0.45s。
  - 点击列表空白区域不再清空选择；非空列表始终保持至少一个选中项。
- 已执行并通过：`swift test --filter 'SettingsProviderViewModelTests|SettingsWindowControllerTests'`
- 下一步建议：先执行全量 `swift test` 完成 5.1，再推进 5.2~5.5 文档与验收清单。

## 最近变更

- 2026-03-02：完成里程碑 4 全部任务并在 `.context/IMPLEMENTATION_PLAN.md` 勾选 4.1~4.6。
- 2026-03-02：根据用户反馈完成设置页降噪改版（列表改为更新时间、右上开关、移除 metadata 文案）。
- 2026-03-02：刷新按钮增加点击反馈（短暂禁用 + `Refreshing usage...` 提示）。
- 2026-03-02：新增 reset 精确时间展示、隐藏无效 usage 指标、新增 `TOKENS (M)` 展示与顶部 account 信息展示。
- 2026-03-02：设置页定向测试通过（41 tests, 0 failures）。
- 2026-03-02：统一 5h/周窗口命名，提升左侧行高并恢复可见性小圆点状态。
- 2026-03-02：Refresh 增加 spinner 加载态并缩短反馈时长；列表空白点击不再导致取消选中。
- 2026-03-02：设置页定向测试更新并通过（43 tests, 0 failures）。
