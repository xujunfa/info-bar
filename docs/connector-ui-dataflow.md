# Connector to InfoBar UI Dataflow

Last updated: 2026-03-02

## Purpose

This document explains how usage data captured by the browser extension is transformed and rendered in the InfoBar Settings UI.

## End-to-end pipeline

1. Page capture (extension MAIN world hook)
- File: `extensions/info-bar-web-connector/src/page/factory-hook.js`
- Hook points: `fetch` and `XMLHttpRequest`
- Matches provider rules from `contracts.js` (`factory_usage_subscription`)
- Emits page message type `INFO_BAR_PAGE_CAPTURED`

2. Message bridge
- File: `extensions/info-bar-web-connector/src/content/bridge.js`
- Forwards validated page message to service worker as `INFO_BAR_CAPTURED`

3. Service worker normalization + dedupe
- File: `extensions/info-bar-web-connector/src/background/service-worker.js`
- Normalizes into connector snapshot:
  - `connector`, `provider`, `event`
  - request metadata (`request_url`, `request_method`, `request_status`, `request_rule_id`)
  - `payload`, `meta`, `capturedAt`
- Builds `dedupeKey = provider|event|request_url|bucket|payloadHash`
- Drops duplicate snapshots before sink writes

4. Supabase sink (`connector_events`)
- Service worker writes normalized snapshot as upsert row (`on_conflict=dedupe_key`)
- Required row dimensions consumed by app:
  - `connector`, `provider`, `event`
  - `payload` (usage payload)
  - `metadata` (trace/source context)

5. Desktop app read path
- File: `Sources/InfoBar/Modules/Quota/SupabaseConnectorEventClient.swift`
- Query filter:
  - `connector=info-bar-web-connector`
  - `provider=factory`
  - `event=usage_snapshot`
  - order by `captured_at.desc`, `limit=1`

6. Provider mapping to `QuotaSnapshot`
- File: `Sources/InfoBar/Modules/Quota/FactoryUsageClient.swift`
- Maps `connector_events.payload` to normalized monthly `QuotaWindow`
- Adds traceable metadata (`connector`, `event`, optional `dedupe_key`, `trace_id`)

7. Settings rendering
- Files:
  - `Sources/InfoBar/UI/Settings/SettingsProviderViewModel.swift`
  - `Sources/InfoBar/UI/Settings/SettingsWindowController.swift`
- Displays usage card, progress, derived reset text, optional token-in-millions metric

## Factory payload contract

`FactoryUsageClient` uses a broad alias strategy for payload compatibility.

| UI field | Primary source | Accepted fallback aliases |
| --- | --- | --- |
| used | `usage.standard.orgTotalTokensUsed` | `userTokens`, `orgOverageUsed`, `current_month_usage`, `month_usage`, `usage`, `used`, `used_tokens`, `consumed`, `total_usage` |
| limit | `usage.standard.totalAllowance` | `basicAllowance`, `monthly_limit`, `month_limit`, `token_limit`, `quota`, `total_quota`, `limit`, `total` |
| remaining | `usage.standard.remainingAllowance` | `orgRemainingTokens`, `monthly_remaining`, `month_remaining`, `remaining_tokens`, `remaining`, `left`, `left_tokens` |
| usedPercent | `usage.standard.usedRatio` | `used_percent`, `usage_percent`, `monthly_percent`, `usedPercent`, `usagePercent`, `usedRate`, `usageRate`, `ratio`, `percent` |
| resetAt | `usage.endDate` | `reset_at`, `next_reset_at`, `period_end`, `expires_at`, `endDate`, `end_date` |
| windowTitle | `window_title`/`windowTitle` | `title`, `plan_name`, `planName`, `subscription_name` |
| unit | `unit` | `token_unit`, `tokenUnit`, `usage_unit`, `usageUnit` |

Derived fallback behavior:

- if `limit` missing and `used+remaining` exist -> `limit = used + remaining`
- if `used` missing and `limit+remaining` exist -> `used = limit - remaining`
- if `remaining` missing and `limit+used` exist -> `remaining = limit - used`
- if `limit` still missing but `used` exists -> use default monthly limit `20,000,000`
- if `resetAt` missing -> end of current month

## Configuration coupling

The extension and desktop app must agree on Supabase configuration:

- table default: `connector_events`
- connector default: `info-bar-web-connector`
- key source precedence:
  - extension: `config.example.json` -> `config.local.json` -> `chrome.storage.local.supabase_config`
  - app: `INFOBAR_CONFIG_FILE` (if set) -> local/example config files -> environment variables

Placeholder values are treated as missing config by both sides, which intentionally disables remote sync.

## Adding a new provider (cross-team checklist)

1. Extension:
- add capture rules in `src/shared/contracts.js`
- ensure normalized payload contains at least usage core fields (`used/limit/remaining` or enough to derive percent)

2. Supabase:
- keep provider/event values stable for app query filters

3. App:
- add provider registration in `QuotaProviderRegistry`
- implement provider-specific `QuotaSnapshotFetching` mapper
- document aliases in `docs/provider-usage-mapping.md`

4. UI:
- verify window labels normalize to user-facing names
- ensure missing metrics are hidden rather than rendered as placeholder noise
