# Info Bar Handoff (2026-02-17)

## 1. 当前状态

- 项目路径：`/Users/xujunfa/Documents/workspace/github/info-bar`
- 已完成：菜单栏渲染原型可运行，样式为“左侧 Codex icon + 右侧上下两行文本（Stats 风格）”
- 当前数据：模拟数据（每秒变化），用于验证渲染能力
- 尚未完成：真实 Codex quota 数据接入

## 2. 已完成能力

- 可执行入口已就绪：`InfoBarApp`（SwiftPM executable target）
- 菜单栏组件：
  - 左侧图标：优先加载 `codex.svg`，失败回退 SF Symbol
  - 右侧双行：
    - 上行：`R:xxx`（remaining）
    - 下行：`U:yy%`（used ratio，按阈值变色）
- 样式确认：图标尺寸已调到 `16`

## 3. 关键文件

### 渲染/UI

- `Sources/InfoBarApp/main.swift`
- `Sources/InfoBar/UI/MenuBar/MenuBarController.swift`
- `Sources/InfoBar/UI/MenuBar/QuotaStatusView.swift`
- `Sources/InfoBar/UI/MenuBar/QuotaLayoutMetrics.swift`

### Quota 模型与模块骨架（Stats 风格）

- `Sources/InfoBar/Modules/Quota/QuotaSnapshot.swift`
- `Sources/InfoBar/Modules/Quota/QuotaDisplayModel.swift`
- `Sources/InfoBar/Modules/Quota/QuotaModule.swift`
- `Sources/InfoBar/Modules/Quota/QuotaReader.swift`
- `Sources/InfoBar/Modules/Quota/QuotaWidget.swift`
- `Sources/InfoBar/Modules/Quota/QuotaPopup.swift`

### 核心基础层（Stats 风格命名）

- `Sources/InfoBar/Kit/module/module.swift`
- `Sources/InfoBar/Kit/module/reader.swift`
- `Sources/InfoBar/Kit/module/widget.swift`
- `Sources/InfoBar/Kit/module/popup.swift`
- `Sources/InfoBar/Kit/plugins/Repeater.swift`
- `Sources/InfoBar/Kit/plugins/Store.swift`
- `Sources/InfoBar/Kit/infra/cli/CLIRunner.swift`

### 资源

- `Sources/InfoBar/Resources/Icons/codex.svg`
- `Package.swift`（已配置 `.copy("Resources")`）

## 4. 测试与运行命令

- 构建：
  - `cd /Users/xujunfa/Documents/workspace/github/info-bar && swift build`
- 测试：
  - `cd /Users/xujunfa/Documents/workspace/github/info-bar && swift test`
- 启动菜单栏原型：
  - `cd /Users/xujunfa/Documents/workspace/github/info-bar && swift run InfoBarApp`

## 5. Git 状态

- 已初始化并关联远程：
  - `origin = https://github.com/xujunfa/info-bar.git`
- 已有阶段性提交（未 push）：
  - `a7fa81f feat: bootstrap stats-like core and quota module scaffolding`
  - `97c89cd feat: add codex cli runner and quota reader integration`
- 之后关于 icon 与双行渲染的改动仍在工作区（未提交）

## 6. 下一轮会话目标

在保持现有渲染样式不变前提下，接入真实 Codex quota。

- 参考文档：`/Users/xujunfa/Documents/workspace/github/CodexBar/.context/codex.md`
- 重点实现：
  - 使用 `~/.codex/auth.json` 或 `$CODEX_HOME/auth.json` 凭据
  - 请求 usage 端点并解析额度数据
  - 将真实数据接入 `QuotaReader -> QuotaModule -> MenuBarController` 链路

## 7. 实施约束

- 保持 Stats 风格架构：`Module-Reader-Widget-Popup`
- 先不重构 UI 样式与布局
- 先完成单源（Codex）稳定接入，再考虑多源扩展
