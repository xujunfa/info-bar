# Provider Usage Mapping Matrix

Last updated: 2026-03-02

## Canonical model used by InfoBar

All providers are normalized into `QuotaSnapshot` -> `QuotaWindow` with these key fields:

- identity: `providerID`, `window.id`, `window.label`
- usage metrics: `usedPercent`, `used`, `remaining`, `limit`, `unit`
- time: `resetAt`
- display context: `windowTitle`, `metadata`

`QuotaWindow` applies a final normalization layer for every provider:

- `usedPercent` is clamped to `0...100`
- `limit` keeps only finite positive values
- `used` keeps finite non-negative values, and is clamped by `limit` when present
- `remaining` keeps finite non-negative values, is clamped by `limit`, or inferred from `limit - used`
- `unit`, `windowTitle`, and metadata keys/values are trimmed; empty values are removed

## Provider mapping rules

### Codex (`Sources/InfoBar/Modules/Quota/CodexUsageClient.swift`)

Source:

- API: `chatgpt_base_url` from `~/.codex/config.toml` if configured; fallback `https://chatgpt.com/backend-api/wham/usage`

Window strategy:

- Primary window is required (`rate_limit.primary_window`) and mapped as 5-hour usage
- Secondary window is optional (`rate_limit.secondary_window`) and mapped as weekly usage

Field mapping matrix:

| Canonical field | Source priority | Fallback strategy |
| --- | --- | --- |
| `used` | `used`/`usage`/`used_count`/`current_usage` | infer from `limit - remaining` |
| `limit` | `limit`/`total`/`quota`/`total_quota` | infer from `used + remaining` |
| `remaining` | `remaining`/`remaining_quota`/`left` | stays nil if unavailable |
| `usedPercent` | `used_percent`/`usage_percent`/`percent` | derive from `used+limit`, then `remaining+limit`, then `used/(used+remaining)` |
| `resetAt` | `reset_at`/`next_reset_at`/`window_end` | use `limit_window_seconds`, then fixed fallback duration (5h or 7d) |
| `windowTitle` | `window_title`/`title`/`name` | default `5-hour usage` or `Weekly usage` |
| `unit` | `unit` | remains nil |
| `metadata` | `window_seconds`, `plan_type`, `period_type` | omitted when empty |

### ZenMux (`Sources/InfoBar/Modules/Quota/ZenMuxUsageClient.swift`)

Source:

- API: `https://zenmux.ai/api/subscription/get_current_usage`

Window strategy:

- First tries array-style windows (`windows`, `usage_windows`, `periods`, `items`, `list`, or top-level array)
- If no array window can be parsed, falls back to object-level monthly + weekly extraction
- Final windows are sorted by period priority: 5-hour, day, week, month, others

Field mapping matrix:

| Canonical field | Source priority | Fallback strategy |
| --- | --- | --- |
| `used` | `used`/`used_count`/`currentValue`/`consumed`/`usage` | for object fallback: monthly/weekly aliases |
| `limit` | `limit`/`total`/`quota`/`allowance` | for object fallback: monthly/weekly aliases |
| `remaining` | `remaining`/`left`/`remaining_quota` | for object fallback: monthly/weekly aliases |
| `usedPercent` | `used_percent`/`usage_percent` | derive from `usedRate`, then usage arithmetic |
| `resetAt` | `reset_at`/`period_end`/`next_reset_at`/`cycleEndTime` | infer from period type (5h/1d/1w/30d) |
| `windowTitle` | `window_title`/`title`/`name` | object fallback uses `Weekly usage` for weekly window |
| `unit` | `unit`/`quota_unit` | stays nil if unavailable |
| `metadata` | `period_type`, optional `cycle_start`, `cycle_end` | omitted when empty |

### MiniMax (`Sources/InfoBar/Modules/Quota/MiniMaxUsageClient.swift`)

Source:

- API: `https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains` with `groupId` query

Window strategy:

- Uses first model where `current_interval_total_count > 0`
- Produces one window; period identity depends on `period_type`

Field mapping matrix:

| Canonical field | Source priority | Fallback strategy |
| --- | --- | --- |
| `limit` | `current_interval_total_count` | fail when missing/non-positive |
| `remaining` | `current_interval_remaining_count` | else from `limit - used`, else legacy `current_interval_usage_count` (treated as remaining) |
| `used` | `current_interval_used_count` | derive from `limit - remaining` |
| `usedPercent` | derived from `used / limit` | fail when cannot derive |
| `resetAt` | `reset_at`/`next_reset_at` | else `remains_time` milliseconds, else `fetchedAt` |
| `windowTitle` | inferred from `period_type` (`5-hour`, `Daily`, `Weekly`, `Monthly`) | default `Current interval` |
| `unit` | `quota_unit` | default `requests` |
| `metadata` | `model_name`, `period_type`, `remains_time_ms` | omitted when empty |

### BigModel (`Sources/InfoBar/Modules/Quota/BigModelUsageClient.swift`)

Source:

- API: `https://open.bigmodel.cn/api/monitor/usage/quota/limit` (or env override)

Window strategy:

- Selects token window from first limit item whose `type` contains `TOKEN`
- Selects time window from first limit item whose `type` contains `TIME`
- Either window can be omitted if mapping fails; both omitted means failure

Field mapping matrix:

| Canonical field | Source priority | Fallback strategy |
| --- | --- | --- |
| `limit` | `usage` | else `currentValue + remaining` |
| `used` | `currentValue` | else `limit - remaining` |
| `remaining` | `remaining` | else `limit - used` |
| `usedPercent` | `percentage` | derive from `used+limit`, then `remaining+limit`, then `used/(used+remaining)` |
| `resetAt` | `nextResetTime` | default `fetchedAt` |
| `windowTitle` | `title` | else `periodName`, then static fallback (`Token quota`/`Time quota`) |
| `unit` | `unit` code mapping (`3=tokens`, `1=minutes`) | infer from `type`, then static fallback |
| `metadata` | `limit_type`, `unit_code`, `cycle_count`, `plan_name` | omitted when empty |

### Factory (`Sources/InfoBar/Modules/Quota/FactoryUsageClient.swift`)

Source:

- Reads latest `connector_events` row from Supabase through `SupabaseConnectorEventClient`
- Filter: `connector=info-bar-web-connector`, `provider=factory`, `event=usage_snapshot`

Window strategy:

- Produces one monthly window from connector payload

Field mapping matrix:

| Canonical field | Source priority | Fallback strategy |
| --- | --- | --- |
| `used` | nested `usage.standard.orgTotalTokensUsed` -> `userTokens` -> `orgOverageUsed` -> broad alias scan (`current_month_usage`, `used_tokens`, `consumed`, etc.) | derive from `limit - remaining`; if `limit` exists and still nil, derive from `usedPercent` |
| `limit` | nested `usage.standard.totalAllowance` -> `basicAllowance` -> broad alias scan (`monthly_limit`, `quota`, `total`, etc.) | derive from `used + remaining`; if still nil and `used` exists, use default `20,000,000` |
| `remaining` | nested `usage.standard.remainingAllowance` -> `orgRemainingTokens` -> broad alias scan (`monthly_remaining`, `left_tokens`, etc.) | derive from `limit - used` |
| `usedPercent` | nested `usage.standard.usedRatio` | parse percentage aliases (`used_percent`, `usageRate`, `ratio`, etc.), then derive from usage arithmetic |
| `resetAt` | nested `usage.endDate` | parse common reset aliases (`reset_at`, `period_end`, `endDate`, etc.), then month-end of `fetchedAt` |
| `windowTitle` | `window_title`/`title`/`plan_name`/`subscription_name` | default `Monthly tokens` |
| `unit` | `unit`/`token_unit`/`usage_unit` | default `tokens` |
| `metadata` | always include `connector` + `event`; optional `dedupe_key`, `trace_id` | omitted optional keys when empty |

## UI-side label normalization

The Settings UI applies an additional label standardization layer in `SettingsProviderViewModel`:

- weekly aliases (`W`, `weekly`, `period_type=week`) -> `Weekly usage`
- 5-hour aliases (`H`, `hour_5`, `current interval`, `period_type=hour`) -> `5-hour usage`

This keeps cross-provider display text stable even when upstream payload labels vary.
