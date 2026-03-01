# 活跃上下文

## 当前状态

- 阶段：execute
- 里程碑：3 — Mac App Connector Event Client 抽象（当前）
- 状态：未开始
- 最后更新：2026-03-02

## 里程碑进度

### 已完成

- [x] 里程碑 1：Extension 采集链路（方式 A）
- [x] 里程碑 2：标准化、持久化与 Supabase 集成
- [x] Workflow 文档迁移（新增 `ACTIVE_CONTEXT.md` / `DECISIONS.md`，并重写 `IMPLEMENTATION_PLAN.md`）

### 进行中

- 尚未开始里程碑 3 代码改造（本次会话仅完成文档迁移）。

### 待完成

- [ ] 3.1 设计通用 Connector Event -> `QuotaSnapshot` 映射接口
- [ ] 3.2 重构 `FactoryUsageClient` 使用通用抽象
- [ ] 3.3 补齐抽象层单元测试
- [ ] 3.4 更新 Provider 注册/依赖注入
- [ ] 3.5 更新文档约束与扩展步骤

## 交接备注

- 代码现状：
  - 扩展 `info-bar-web-connector` 已支持 Factory 采集、去重、本地持久化、Supabase 写入与 read-back。
  - Mac App 已通过 `SupabaseConnectorEventClient` + `FactoryUsageClient` 从 Supabase 读取 factory usage。
- 关键约束：
  - 保持最小权限与域白名单注入策略。
  - 日志不得输出 token/cookie/secret。
  - 执行代码改动时遵循 TDD（先失败测试，再最小实现）。
- 下一步建议（直接可执行）：
  1. 打开 `SupabaseConnectorEventClient.swift`，抽取通用映射协议/类型。
  2. 改造 `FactoryUsageClient.swift`，仅保留 factory payload 语义映射。
  3. 先补失败测试，再完成最小重构，最后 `swift test` 回归。
- 参考文件：
  - `.context/IMPLEMENTATION_PLAN.md`（当前里程碑定义）
  - `.context/HANDOFF.md`（历史细节，已迁移但保留）
  - `extensions/info-bar-web-connector/README.md`（运行与安全策略）

## 最近变更

- 2026-03-01：完成方式 A + Factory + Supabase sink + Mac App factory provider 切换。
- 2026-03-02：`.context` 迁移为 workflow 结构；新增 `ACTIVE_CONTEXT.md` 与 `DECISIONS.md`，重写 `IMPLEMENTATION_PLAN.md` 为里程碑勾选格式。
