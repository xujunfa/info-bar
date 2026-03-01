# Info Bar Web Connector - Implementation Plan

## 0. 实施状态（2026-03-01）

本计划对应的 Phase 1 已完成并在本仓库落地，当前状态如下：

1. 已完成 **方式 A**（MAIN world 注入 + fetch/xhr hook + postMessage 链路）。
2. Factory usage 采集规则已生效：`/api/organization/subscription/usage`。
3. Service Worker 已完成标准化、去重、`chrome.storage.local` 落盘、日志输出。
4. 已接入 Supabase sink（写入 + 读回缓存），并提供 SQL migration。
5. 已有定时刷新基础能力（`chrome.alarms`，保守频率 + 节流）。
6. Mac App `factory` provider 已改为从 Supabase 读取（不再走原 Factory API 鉴权链路）。
7. 配置已切换为 `config.example.json` + `config.local.json` 模式，`config.local.json` 在 `.gitignore`。

本期明确未做：

1. 方式 B（`chrome.debugger + CDP`）。
2. 生产级服务端聚合/权限体系扩展（当前依赖 Supabase RLS）。

## 1. 背景与目标

`info-bar-web-connector` 的定位是一个通用浏览器桥接层：

1. 当某个 Provider 无稳定公开 API、或 API 鉴权成本过高时，改由 Chrome Extension 从页面/浏览器上下文抓取信息。
2. 将抓取结果标准化后写入本地存储或后端（后续默认 Supabase）。
3. 由 Mac App 读取桥接层产物，而不是直接依赖目标站点的复杂前端鉴权链路。

本计划首期只落地方式 A（主世界注入 + hook fetch/XHR），并先打通 Factory usage 场景。

---

## 2. 本期范围（Phase 1）

1. 创建 MV3 扩展骨架与最小可运行消息链路。
2. 在 `app.factory.ai` 页面注入 MAIN world 脚本，hook `window.fetch` 和 `XMLHttpRequest`。
3. 捕获 usage 接口响应后，发送到扩展 Service Worker。
4. Service Worker 做去重、标准化、持久化（先 `chrome.storage.local` + 日志）。
5. 预留后端 Sink 接口（Supabase），但本期默认关闭网络写入。
6. 实现页面定时刷新驱动（用于持续拉取最新 usage）。

---

## 3. 目录规划

已创建目录：

- `extensions/info-bar-web-connector/`
- `extensions/info-bar-web-connector/src/background/`
- `extensions/info-bar-web-connector/src/content/`
- `extensions/info-bar-web-connector/src/page/`
- `extensions/info-bar-web-connector/src/shared/`

后续建议文件：

1. `extensions/info-bar-web-connector/manifest.json`
2. `extensions/info-bar-web-connector/src/page/factory-hook.js`
3. `extensions/info-bar-web-connector/src/content/bridge.js`
4. `extensions/info-bar-web-connector/src/background/service-worker.js`
5. `extensions/info-bar-web-connector/src/shared/contracts.js`
6. `extensions/info-bar-web-connector/README.md`

---

## 4. 方案 A 技术设计

## 4.1 注入与 Hook

1. Content Script 在 `https://app.factory.ai/*` 运行。
2. Content Script 通过 `chrome.scripting.executeScript` 注入 `factory-hook.js` 到 `MAIN` world。
3. `factory-hook.js` 包装：
   - `window.fetch`
   - `XMLHttpRequest.prototype.open/send`
4. 对匹配 URL（`/api/organization/subscription/usage`）的响应执行 clone 读取，提取 JSON 负载。

## 4.2 消息链路

1. Page Script -> `window.postMessage`（带 `source = info-bar-web-connector`）。
2. Content Script -> 校验来源与 schema 后 `chrome.runtime.sendMessage`。
3. Service Worker -> 去重 + 持久化 +（可选）上报。

## 4.3 数据契约（统一 Envelope）

```json
{
  "connector": "info-bar-web-connector",
  "provider": "factory",
  "event": "usage_snapshot",
  "capturedAt": "2026-03-01T10:00:00.000Z",
  "pageUrl": "https://app.factory.ai/...",
  "request": {
    "url": "https://api.factory.ai/api/organization/subscription/usage",
    "method": "POST"
  },
  "payload": {},
  "meta": {
    "traceId": "...",
    "hook": "fetch|xhr",
    "version": 1
  }
}
```

## 4.4 定时刷新机制

1. `chrome.alarms` 每 N 分钟触发。
2. Service Worker 查找已打开的 `app.factory.ai` tab：
   - 找到则触发 content script 执行刷新动作。
   - 找不到则按配置创建后台 tab，等待加载后采集，再决定保留或关闭。
3. 加入节流和指数退避，避免高频刷新触发风控。

---

## 5. 与 Mac App 的集成边界

本期只定义边界，不在本期强实现完整传输链：

1. Extension 侧先保证 `chrome.storage.local` 有最新标准化快照。
2. 为后续集成预留两条通道：
   - 通道 A：写入 Supabase（推荐长期方案）。
   - 通道 B：本地桥接（localhost helper）供 Mac App 读取。

本期本地验证目标：日志可见 + `chrome.storage.local` 可读。

---

## 6. 实施里程碑

## Milestone 1: Bootstrap

1. 完成 `manifest.json`（MV3，最小权限）。
2. 注册 content script 与 service worker。
3. 在目标页面输出基础日志，验证扩展加载。

验收：打开 `app.factory.ai` 可看到 content/background 都启动。

## Milestone 2: Hook Pipeline

1. 完成 MAIN world fetch/xhr hook。
2. 仅采集 usage 目标接口。
3. 完成 page -> content -> background 消息打通。

验收：能在 background log 中看到 usage 响应 JSON。

## Milestone 3: Normalize + Persist

1. 实现统一 Envelope 映射。
2. 实现去重键（如 `provider + request.url + capturedAt bucket + hash(payload)`）。
3. 写入 `chrome.storage.local` 最近 N 条快照。

验收：刷新页面后可持续看到最新快照，且无明显重复写爆。

## Milestone 4: Refresh Driver

1. 引入 `chrome.alarms` 定时触发。
2. 触发 tab 刷新或数据请求动作。
3. 加入失败重试与退避。

验收：无人手动操作时，快照仍可定时更新。

## Milestone 5: Sink Adapter (Local First)

1. 抽象 Sink 接口：`console` / `localStorage` / `supabase`。
2. 本地默认 `console + chrome.storage.local`。
3. 预留 Supabase 配置（URL、anon key、table）。

验收：切换 sink 不影响采集主流程。

---

## 7. 权限与安全策略

1. 仅申请必要权限：`scripting`, `storage`, `alarms`, `tabs`（按需）+ 对应 host permissions。
2. 仅允许白名单域：`https://app.factory.ai/*`, `https://api.factory.ai/*`。
3. 消息校验必须包含：`source`, `schemaVersion`, `provider`。
4. 默认不记录敏感头和 token。
5. 上报前做字段脱敏与最小化采集。

---

## 8. 风险与缓解

1. 页面改造导致 hook 点失效。
   - 缓解：fetch/xhr 双通道 + 版本化检测 + 失效告警。
2. 扩展注入时序问题（过晚导致漏采集）。
   - 缓解：`document_start` 注入 + 初始化重放策略。
3. 高频刷新触发风控。
   - 缓解：最低刷新间隔、指数退避、夜间降频。
4. 数据重复和噪音。
   - 缓解：去重 + TTL + 仅保留最近 N 条。

---

## 9. 测试与验收清单

1. 功能测试：
   - 打开页面后首次采集成功。
   - 手动刷新后可捕获新快照。
   - 定时刷新能自动产出快照。
2. 稳定性测试：
   - 浏览器重启后仍可恢复采集。
   - tab 切换/页面重定向不丢链路。
3. 安全测试：
   - 日志不泄露 token。
   - 非白名单域无注入。

Release Gate（本期完成标准）：

1. 方式 A 在 Factory usage 场景稳定跑通。
2. 采集结果能稳定写入 `chrome.storage.local`。
3. 代码具备通用 Provider 扩展点（不只绑定 Factory）。

---

## 10. 非目标（本期不做）

1. 方式 B（`chrome.debugger + CDP`）实现。
2. 上架 Chrome Web Store 的合规包。
3. Mac App 端最终生产链路接入（仅定义接口边界）。

---

## 11. 下一会话执行顺序建议

1. 先落 `manifest + content + background` 的最小运行闭环。
2. 再落 MAIN world hook 与 usage 精准匹配。
3. 再做持久化与 refresh driver。
4. 最后接入可开关的 Supabase sink。
