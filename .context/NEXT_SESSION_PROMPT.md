你现在在仓库：`/Users/xujunfa/Documents/workspace/github/info-bar`。

开始前请先阅读：
1. `/Users/xujunfa/Documents/workspace/github/info-bar/.claude/CLAUDE.md`
2. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/HANDOFF.md`

当前已完成：
- Settings：拖拽排序、显示隐藏、手动 Refresh
- Menu Bar：W/H 行位稳定，隐藏后恢复不乱序
- Pace 字体颜色：已接入（warning/critical）

当前建议优先任务（按顺序）：
1. 给 Pace 参数做可配置（至少 targetUsage + warning/critical 阈值）
2. 修复设置窗 `Cmd+W` 关闭行为
3. 为 Refresh 增加 loading/禁用态，避免重复请求

硬性约束：
- 保持 Stats 风格架构（Module-Reader-Widget-Popup）
- 严格 TDD（先失败测试，再最小实现）
- 不做无关重构

完成后请输出：
1) 变更文件清单
2) 运行/测试命令与结果
3) 风险与后续建议
