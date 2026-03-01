# 实施计划

## 概览

- 项目：Info Bar（Web Connector + Supabase 集成子项目）
- 里程碑总数：5
- 创建日期：2026-03-01
- 最近更新：2026-03-02
- 当前执行阶段：里程碑 3
- 参考文档：`.context/DESIGN.md`（总体设计）、`.context/archive/IMPLEMENTATION_PLAN-2026-03-02-pre-workflow-migration.md`（迁移前详版）

---

## 里程碑 1：Extension 采集链路（方式 A）

**目标**：在 Factory 页面稳定捕获 usage 接口并传入 service worker。

### 任务

- [x] 1.1 创建 MV3 扩展骨架与最小权限 manifest
  - 文件：`extensions/info-bar-web-connector/manifest.json`
- [x] 1.2 在 MAIN world 注入 page script，hook `fetch` + `XMLHttpRequest`
  - 文件：`extensions/info-bar-web-connector/src/page/factory-hook.js`
- [x] 1.3 打通消息链路（page -> content -> background）
  - 文件：`extensions/info-bar-web-connector/src/content/bridge.js`、`extensions/info-bar-web-connector/src/background/service-worker.js`
- [x] 1.4 落地 Factory usage 抓取规则
  - 文件：`extensions/info-bar-web-connector/src/shared/contracts.js`
- [x] 1.5 完成扩展侧调试与本地加载说明
  - 文件：`extensions/info-bar-web-connector/README.md`

### 验收标准

- 能在 `https://app.factory.ai/*` 捕获 usage 响应。
- Service worker 可以稳定收到结构化消息并输出调试日志。
- 非白名单域不注入脚本。

---

## 里程碑 2：标准化、持久化与 Supabase 集成

**目标**：采集结果可去重落盘并同步到 Supabase，Mac App 可从 Supabase 读取 factory 快照。

### 任务

- [x] 2.1 定义通用 Envelope 契约与 provider/rule 注册
  - 文件：`extensions/info-bar-web-connector/src/shared/contracts.js`
- [x] 2.2 实现 service worker 去重、local 持久化与兼容旧 key
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`
- [x] 2.3 创建 `connector_events` migration + RLS policy
  - 文件：`extensions/info-bar-web-connector/supabase/migrations/20260301_create_connector_events.sql`
- [x] 2.4 接入 Supabase sink 写入与 read-back 缓存
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`
- [x] 2.5 将 Mac App `factory` provider 切换为 Supabase 读取
  - 文件：`Sources/InfoBar/Modules/Quota/SupabaseConnectorEventClient.swift`、`Sources/InfoBar/Modules/Quota/FactoryUsageClient.swift`
- [x] 2.6 配置模式切换为 `config.example.json` + `config.local.json`
  - 文件：`config.example.json`、`config.local.json`、`extensions/info-bar-web-connector/config.example.json`

### 验收标准

- 本地可看到 `connector_snapshots` 与 `connector_remote_snapshots`。
- Supabase 表 `public.connector_events` 可查询到最新 factory usage 事件。
- Mac App 工厂配额读取链路不再依赖原 Factory API 鉴权。

---

## 里程碑 3：Mac App Connector Event Client 抽象（当前）

**目标**：将现有 Factory 专用映射抽象为可复用结构，降低接入新 provider 的重复代码。

### 任务

- [ ] 3.1 设计通用的 Connector Event -> `QuotaSnapshot` 映射接口
  - 文件：`Sources/InfoBar/Modules/Quota/SupabaseConnectorEventClient.swift`（必要时新增 `Sources/InfoBar/Modules/Quota/ConnectorEventSnapshotMapper.swift`）
- [ ] 3.2 重构 `FactoryUsageClient` 使用通用抽象，保留兼容行为
  - 文件：`Sources/InfoBar/Modules/Quota/FactoryUsageClient.swift`
- [ ] 3.3 为通用抽象补齐单元测试（成功路径、空数据、鉴权失败、占位配置）
  - 文件：`Tests/InfoBarTests/Modules/Quota/FactoryUsageClientTests.swift`（必要时新增测试文件）
- [ ] 3.4 更新 Provider 注册/依赖注入以支持后续多 provider
  - 文件：`Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`、`Sources/InfoBarApp/main.swift`
- [ ] 3.5 更新开发文档中的抽象约束与扩展步骤
  - 文件：`extensions/info-bar-web-connector/README.md`、`docs/`（如需新增）

### 验收标准

- 新增 provider 时无需复制整套 Supabase 请求与解析流程。
- 现有 factory 行为与测试结果保持一致或更稳健。
- 抽象层具备明确的输入输出与错误语义。

---

## 里程碑 4：第二个 Provider 的 Extension 采集复用验证

**目标**：在不破坏 Factory 的前提下，为第二 provider 落地捕获规则并打通端到端链路。

### 任务

- [ ] 4.1 在扩展契约中新增第二 provider 配置（host/rule/refresh）
  - 文件：`extensions/info-bar-web-connector/src/shared/contracts.js`
- [ ] 4.2 更新 manifest 白名单与注入范围（最小权限）
  - 文件：`extensions/info-bar-web-connector/manifest.json`
- [ ] 4.3 实现并验证新 provider 的 page/content/background 捕获链路
  - 文件：`extensions/info-bar-web-connector/src/page/*.js`、`extensions/info-bar-web-connector/src/content/bridge.js`、`extensions/info-bar-web-connector/src/background/service-worker.js`
- [ ] 4.4 在 Mac App 侧接入对应 `UsageClient`（复用里程碑 3 抽象）
  - 文件：`Sources/InfoBar/Modules/Quota/*UsageClient.swift`、`Sources/InfoBar/Modules/Quota/QuotaProviderRegistry.swift`
- [ ] 4.5 增加最小回归测试与手工验证脚本
  - 文件：`Tests/InfoBarTests/Modules/Quota/*`、`extensions/info-bar-web-connector/README.md`

### 验收标准

- 两个 provider 都能稳定产出快照并落地到 `connector_events`。
- 扩展权限仍限定在白名单域。
- Factory 现有能力无回归。

---

## 里程碑 5：可观测性与稳定性加固

**目标**：为采集与同步链路提供可观测指标、错误分类和运维可读性。

### 任务

- [ ] 5.1 为 service worker 增加 sink 成功率/去重率/失败原因统计
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`
- [ ] 5.2 设计并落地 metrics 存储结构（`chrome.storage.local`）
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`
- [ ] 5.3 统一日志脱敏策略并补齐敏感字段回归检查
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`、`extensions/info-bar-web-connector/src/shared/contracts.js`
- [ ] 5.4 校验 `chrome.alarms` 刷新稳定性（节流/退避）
  - 文件：`extensions/info-bar-web-connector/src/background/service-worker.js`
- [ ] 5.5 更新运行手册与故障排查指南
  - 文件：`extensions/info-bar-web-connector/README.md`、`docs/`

### 验收标准

- 可以追踪最近周期的采集量、去重效果、失败分布。
- 故障定位不依赖临时打印，基于结构化指标即可快速判断问题。
- 日志与存储中不出现敏感 token/cookie/secret 明文。
