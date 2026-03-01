# 下一会话提示（Workflow 模式）

你现在在仓库：`/Users/xujunfa/Documents/workspace/github/info-bar`。

推荐启动方式：

1. 执行 `/workflow`（自动检测并进入当前阶段）
2. 或执行 `/workflow execute 3`（直接进入当前里程碑）

开始前请先阅读（按顺序）：

1. `/Users/xujunfa/Documents/workspace/github/info-bar/.claude/CLAUDE.md`
2. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/ACTIVE_CONTEXT.md`
3. `/Users/xujunfa/Documents/workspace/github/info-bar/.context/IMPLEMENTATION_PLAN.md` 中「里程碑 3」段落（不要整文件通读）

当前优先目标（里程碑 3）：

1. 抽象 Mac App 侧 Connector Event Client（减少 provider-specific 逻辑重复）
2. 保持 `factory` 行为与测试结果不回归
3. 为里程碑 4（第二 provider 接入）准备可复用接口

硬性约束：

1. 保持最小权限原则与域白名单注入
2. 日志不可输出敏感 token / cookie / secret
3. 严格 TDD（先失败测试，再最小实现）

完成后请输出：

1. 变更文件清单
2. 运行/测试命令与结果
3. 风险与后续建议
