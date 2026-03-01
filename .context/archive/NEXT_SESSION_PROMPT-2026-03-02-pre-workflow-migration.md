你现在在仓库：`/Users/xujunfa/Documents/workspace/github/info-bar`。

开始前请先阅读：
1. `/Users/xujunfa/Documents/workspace/github/info-bar/.claude/CLAUDE.md`
2. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/HANDOFF.md`
3. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/IMPLEMENTATION_PLAN.md`

当前已完成（本轮）：
1. `factory` provider 已接入，并由 Mac App 通过 Supabase 读取 usage 快照
2. Chrome Extension `info-bar-web-connector`（方式 A）已打通采集链路与 Supabase sink
3. `config.example.json` + `config.local.json` 配置方案已落地（`config.local.json` 已忽略）

当前建议优先任务（按顺序）：
1. 抽象 Mac App 侧 Connector Event Client（减少 provider-specific 逻辑重复）
2. 扩展第二个 provider 的 extension 采集规则，验证通用契约复用
3. 为 Supabase sink 增加可观测性指标（成功率/去重率/失败原因统计）

硬性约束：
1. 保持最小权限原则与域白名单注入
2. 日志不可输出敏感 token / cookie / secret
3. 严格 TDD（先失败测试，再最小实现）

完成后请输出：
1) 变更文件清单
2) 运行/测试命令与结果
3) 风险与后续建议
