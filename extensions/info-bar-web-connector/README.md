# Info Bar Web Connector (Method A)

Chrome Extension (MV3) for capture-driven integration when provider APIs are unavailable or hard to authenticate.

Current default provider is `factory`, and the runtime pipeline is provider-config driven:

- Provider/rule registry in `src/shared/contracts.js`
- MAIN world hook captures matched requests
- Message chain: page script `postMessage` -> content script -> service worker
- Service worker normalizes + dedupes + writes local + writes Supabase + reads back recent rows
- Alarm refresh is scheduled per provider

## Scope in this phase

- Method A only
- Inject page script into MAIN world
- Hook `window.fetch` and `XMLHttpRequest`
- Factory capture rule: `api.factory.ai/api/organization/subscription/usage`
- Supabase sink enabled with RLS-safe upsert target

## File layout

- `manifest.json`
- `config.example.json`
- `src/shared/contracts.js`
- `src/page/factory-hook.js`
- `src/content/bridge.js`
- `src/background/service-worker.js`
- `supabase/migrations/20260301_create_connector_events.sql`

## Supabase schema

Table: `public.connector_events`

Core columns:

- identity: `id`, `dedupe_key`
- dimensions: `connector`, `provider`, `event`, `request_rule_id`
- timestamps: `captured_at`, `received_at`, `created_at`, `updated_at`
- request fields: `request_url`, `request_method`, `request_status`, `page_url`
- payload fields: `payload` (jsonb), `metadata` (jsonb), `source`

Indexes:

- unique `dedupe_key`
- `(provider, event, captured_at desc)`
- `(connector, created_at desc)`
- `(received_at desc)`

RLS policies:

- `connector_events_insert_anon`: allow `anon/authenticated` insert for connector `info-bar-web-connector`
- `connector_events_select_anon`: allow `anon/authenticated` select for connector `info-bar-web-connector`

## Local load

1. Open `chrome://extensions`
2. Enable `Developer mode`
3. Click `Load unpacked`
4. Select:
   `/Users/xujunfa/.codex/worktrees/69be/info-bar/extensions/info-bar-web-connector`

## Runtime config (config.example/config.local)

1. Copy `config.example.json` to `config.local.json`.
2. Fill real Supabase values in `config.local.json`.
3. `config.local.json` is gitignored.

`config.local.json` schema:

```json
{
  "supabase": {
    "enabled": true,
    "projectUrl": "https://your-project-ref.supabase.co",
    "apiKey": "sb_publishable_xxx",
    "table": "connector_events",
    "readBackLimit": 20
  }
}
```

Service worker merges config in this order:

1. `config.example.json`
2. `config.local.json`
3. `chrome.storage.local.supabase_config` (runtime override)

Placeholder values (for example `your-project-ref.supabase.co` or `sb_publishable_replace_me`) are treated as missing config and Supabase sync is skipped.

## Runtime config (storage)

Service worker seeds `chrome.storage.local.supabase_config` automatically on first run:

```js
{
  enabled: true,
  projectUrl: "https://your-project-ref.supabase.co",
  table: "connector_events",
  apiKey: "<publishable/anon key>",
  readBackLimit: 20
}
```

You can override it manually in service worker console:

```js
chrome.storage.local.set({
  supabase_config: {
    enabled: true,
    projectUrl: "https://your-project-ref.supabase.co",
    table: "connector_events",
    apiKey: "<your key>",
    readBackLimit: 20
  }
});
```

## Validation

1. Open `https://app.factory.ai` and trigger usage request.
2. Service worker console should print:
   - `[info-bar] normalized snapshot: ...`
   - no sink errors for Supabase.
3. Check local storage:

```js
chrome.storage.local.get([
  "connector_snapshots",
  "connector_dedupe_index",
  "factory_usage_snapshots",
  "factory_usage_dedupe_index",
  "connector_remote_snapshots",
  "supabase_config"
], console.log);
```

Expected:

- local snapshots still written (`connector_snapshots` + legacy `factory_usage_snapshots`)
- remote read cache exists in `connector_remote_snapshots`
- Supabase config exists in `supabase_config`

## Alarm verification

```js
chrome.alarms.get("provider_refresh_factory", console.log);
chrome.alarms.create("provider_refresh_factory", { when: Date.now() + 1000 });
```

Expected logs:

- `[info-bar] refresh alarm fired: factory`
- `[info-bar] refresh alarm dispatched: factory tabs=...`
- `[info-bar] supabase read sync: factory rows=...` (if remote reachable)

## Security notes

- Minimal permissions: `storage`, `alarms`, `tabs`
- Host whitelist:
  - `https://app.factory.ai/*`
  - `https://xtgnhgfeqedmlkyvnjvy.supabase.co/*`
- If you change `projectUrl` domain, update `manifest.json` `host_permissions` accordingly.
- Logs redact token-like fields (`token`, `authorization`, `cookie`, `secret`, `password`, `apiKey`)
- URL logs are sanitized to `origin + pathname`

## Add a new provider

1. Add provider config in `src/shared/contracts.js`:
   - `pageHosts`
   - `tabUrlPatterns`
   - `refresh`
   - `captureRules`
2. Add domain whitelist in `manifest.json`:
   - `host_permissions`
   - `content_scripts.matches`
   - `web_accessible_resources.matches`
3. Reload extension.

No pipeline code changes are required if target responses are JSON.

## InfoBar app integration contract

For the current `factory` provider, the desktop app reads from `connector_events` with:

- `connector=info-bar-web-connector`
- `provider=factory`
- `event=usage_snapshot`
- latest row by `captured_at desc`

To keep Settings UI rendering stable, payload should expose at least enough data to derive:

- `used` / `limit` / `remaining` (preferred), or
- `usedPercent` + one absolute quantity so app-side fallback can infer the rest

Recommended payload keys (first-priority path):

- `usage.standard.orgTotalTokensUsed` -> used
- `usage.standard.totalAllowance` -> limit
- `usage.standard.remainingAllowance` -> remaining
- `usage.standard.usedRatio` -> usedPercent
- `usage.endDate` -> resetAt

The app accepts multiple alias fields and applies fallback inference. See:

- [`docs/provider-usage-mapping.md`](../../docs/provider-usage-mapping.md)
- [`docs/connector-ui-dataflow.md`](../../docs/connector-ui-dataflow.md)
