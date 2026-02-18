你现在在仓库：`/Users/xujunfa/Documents/workspace/github/info-bar`。

开始前请先阅读：
1. `/Users/xujunfa/Documents/workspace/github/info-bar/.claude/CLAUDE.md`
2. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/HANDOFF.md`

本仓库当前背景：
- Quota 维持 Stats 风格架构：`Module -> Reader -> Widget -> Popup`。
- 已接入真实 provider：`codex`、`zenmux`、`minimax`、`bigmodel`。
- `zenmux/minimax/bigmodel` 统一走浏览器 Cookie 导入（复用 `BrowserQuotaCookieCollector`）。
- `bigmodel` 请求使用 quota limit API，并会从 Cookie Header 提取 token（含 `bigmodel_token_production`）补发 `Authorization: Bearer ...`。
- `bigmodel` 图标资源已是 `Sources/InfoBar/Resources/Icons/bigmodel.svg`。

当前建议优先任务（按顺序）：
1. 为 BigModel 增加可控 debug 日志（仅记录命中 cookie key，不记录 token 值）定位鉴权失败。
2. 增加 BigModel live probe（环境变量开关）验证真实接口通路。
3. 统一 provider 失败语义（auth/network/parse）并评估 UI 透出策略，避免统一 `-- --`。

硬性约束：
- 保持 Stats 风格架构（Module-Reader-Widget-Popup）。
- 严格 TDD（先失败测试，再最小实现）。
- 不做无关重构。

完成后请输出：
1) 变更文件清单
2) 运行/测试命令与结果
3) 风险与后续建议
