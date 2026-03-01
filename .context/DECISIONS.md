# 决策日志

## [DEC-001] 首期采用方式 A（MAIN world 注入 + fetch/xhr hook）

- **日期**：2026-03-01
- **里程碑**：1 — Extension 采集链路（方式 A）
- **背景**：需要在 provider API 不稳定或鉴权复杂时，快速建立可运行的数据采集链路。
- **备选方案**：
  1. 方式 A：MAIN world 注入 + fetch/xhr hook — 实现快、侵入低、可快速验证；但受页面实现细节变化影响。
  2. 方式 B：`chrome.debugger + CDP` — 捕获能力更底层；但权限敏感、复杂度高、首期成本大。
- **决策**：首期落地方式 A，方式 B 作为后续备选。
- **理由**：当前目标是尽快打通端到端链路并验证业务可行性，方式 A 更符合交付速度与风险平衡。

## [DEC-002] 采用统一 Envelope + 去重 + 双存储（local + Supabase）

- **日期**：2026-03-01
- **里程碑**：2 — 标准化、持久化与 Supabase 集成
- **背景**：采集数据需要兼顾本地调试可见性、跨端消费一致性以及重复事件控制。
- **备选方案**：
  1. 只写本地 `chrome.storage.local` — 调试方便，但跨端读取困难、无法作为长期数据源。
  2. 只写远端 Supabase — 结构统一，但离线调试与故障定位能力不足。
  3. 本地+远端双通道，统一契约并去重 — 实现稍复杂，但可同时满足调试与生产链路。
- **决策**：采用统一 Envelope，先本地去重落盘，再写 Supabase，并保留 read-back 缓存。
- **理由**：最大化可观测性与稳定性，且为 Mac App 消费提供统一来源。

## [DEC-003] Mac App 的 factory provider 改为读取 Supabase connector_events

- **日期**：2026-03-01
- **里程碑**：2 — 标准化、持久化与 Supabase 集成
- **背景**：Factory 原始 API 的鉴权链路复杂且易受前端变化影响，维护成本高。
- **备选方案**：
  1. 继续直接调用 Factory API — 依赖 provider 鉴权细节，波动风险大。
  2. 读取扩展产出的 Supabase 标准化事件 — 链路更统一，但需要维护映射逻辑。
- **决策**：Factory 在 Mac App 侧使用 `SupabaseConnectorEventClient` 读取标准化事件。
- **理由**：降低 provider-specific 鉴权依赖，统一多 provider 接入路径。

## [DEC-004] 配置管理采用 `config.example.json` + `config.local.json`

- **日期**：2026-03-01
- **里程碑**：2 — 标准化、持久化与 Supabase 集成
- **背景**：需要在仓库可共享默认配置与本地私密配置之间取得平衡。
- **备选方案**：
  1. 全部配置入库 — 协作方便，但存在敏感信息泄露风险。
  2. 全部依赖环境变量 — 安全性高，但开发体验较差，跨模块一致性弱。
  3. 示例配置入库 + 本地配置忽略 — 兼顾安全与可用性。
- **决策**：仓库保留 `config.example.json`，真实配置写入 `config.local.json` 并 gitignore。
- **理由**：降低泄露风险并提升多端（Mac App + Extension）配置一致性。
