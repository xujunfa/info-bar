# InfoBar — Technical Design

> Last updated: 2026-03-11

## 1. Project Overview

A macOS menu bar application that displays real-time Quota/Usage information for multiple Coding Agent providers (Codex, ZenMux, MiniMax, BigModel, Factory) simultaneously in the system menu bar.

Each provider gets its own `NSStatusItem` showing a two-line text widget (Stats-style: left icon + right two-line text). Clicking any item opens a shared Settings panel.

## 2. Technical Stack

| Layer | Technology | Notes |
|---|---|---|
| Package manager | Swift Package Manager | `swift-tools-version: 6.2` |
| Platform | macOS 14+ | Pure AppKit, no SwiftUI |
| App entry | `main.swift` + `NSApplication.shared.run()` | Manual AppKit lifecycle |
| Dependencies | [SweetCookieKit](https://github.com/steipete/SweetCookieKit) | Browser cookie extraction |
| Timer / Scheduling | `DispatchSourceTimer` (via `Repeater`) | GCD-based periodic fetching |
| Network | `URLSession` + semaphore-based synchronous wrapper | Blocking on background queues |
| Persistence | `UserDefaults` | Provider order, visibility |
| External data | Supabase REST API | For Factory provider (via Chrome Extension) |
| Config | `config.example.json` + `config.local.json` | Supabase credentials, gitignored |

## 3. Project Structure

```
InfoBar/
├── Package.swift
├── config.example.json                  # Supabase config template
├── Sources/
│   ├── InfoBar/                         # Library target
│   │   ├── InfoBar.swift                # Module exports
│   │   ├── AppBootstrap.swift           # App constants
│   │   │
│   │   ├── Kit/                         # ── Base framework layer ──
│   │   │   ├── module/
│   │   │   │   ├── module.swift         # Module base (mount/unmount)
│   │   │   │   ├── reader.swift         # Reader<Value> (Repeater + fetch + callback)
│   │   │   │   ├── widget.swift         # WidgetProtocol (setValue interface)
│   │   │   │   └── popup.swift          # Popup base (unused in Quota)
│   │   │   ├── plugins/
│   │   │   │   ├── Repeater.swift       # DispatchSourceTimer wrapper
│   │   │   │   └── Store.swift          # Value store helper
│   │   │   └── infra/cli/
│   │   │       └── CLIRunner.swift      # Shell command runner
│   │   │
│   │   ├── Modules/                     # ── Domain modules ──
│   │   │   └── Quota/
│   │   │       ├── QuotaSnapshot.swift          # Domain model (QuotaSnapshot + QuotaWindow)
│   │   │       ├── QuotaDisplayModel.swift      # Menu bar view model + Pace algorithm
│   │   │       ├── QuotaModule.swift            # Module subclass
│   │   │       ├── QuotaReader.swift            # Reader<QuotaSnapshot>
│   │   │       ├── QuotaWidget.swift            # Widget subclass
│   │   │       ├── QuotaPopup.swift             # Popup subclass (unused)
│   │   │       ├── QuotaProviderRegistry.swift  # Provider factory
│   │   │       ├── CodexUsageClient.swift       # Direct API
│   │   │       ├── ZenMuxUsageClient.swift      # Direct API
│   │   │       ├── MiniMaxUsageClient.swift     # Direct API
│   │   │       ├── BigModelUsageClient.swift    # Direct API
│   │   │       ├── FactoryUsageClient.swift     # Via Supabase
│   │   │       ├── SupabaseConnectorEventClient.swift  # Supabase REST generic client
│   │   │       ├── CodexAuthStore.swift                # ~/.codex/auth.json
│   │   │       ├── BrowserQuotaCookieCollector.swift   # SweetCookieKit wrapper
│   │   │       ├── *BrowserCookieImporter.swift        # Per-provider cookie config
│   │   │       ├── FactoryBrowserRefreshTokenImporter.swift
│   │   │       └── config.plist                        # Bundled config resource
│   │   │
│   │   ├── UI/                          # ── Presentation layer ──
│   │   │   ├── MenuBar/
│   │   │   │   ├── MenuBarController.swift      # Per-provider NSStatusItem
│   │   │   │   ├── QuotaStatusView.swift        # draw()-based two-line widget
│   │   │   │   └── QuotaLayoutMetrics.swift     # Layout constants
│   │   │   └── Settings/
│   │   │       ├── SettingsWindowController.swift # NSPanel + NSSplitViewController
│   │   │       ├── SettingsProviderViewModel.swift
│   │   │       ├── SettingsTheme.swift           # Visual tokens
│   │   │       ├── UsageFormatting.swift          # Number/unit formatting
│   │   │       ├── ProviderOrderStore.swift       # UserDefaults persistence
│   │   │       └── ProviderVisibilityStore.swift
│   │   │
│   │   └── Resources/Icons/             # Provider SVG icons (isTemplate)
│   │
│   └── InfoBarApp/
│       └── main.swift                   # App entry point + wiring
│
├── Tests/InfoBarTests/                  # XCTest suite (~117 tests)
├── extensions/
│   └── info-bar-web-connector/          # Chrome Extension (MV3)
└── docs/
    ├── provider-usage-mapping.md
    ├── settings-ui-spec.md
    ├── connector-ui-dataflow.md
    └── settings-qa-checklist.md
```

## 4. Architecture

### Core Pipeline: Module -> Reader -> Widget

```
┌──────────────┐  start()/mount()  ┌──────────────────────────────┐
│ QuotaModule  │──────────────────>│ QuotaReader                  │
│              │                   │ (Repeater DispatchSourceTimer │
│              │                   │  + QuotaSnapshotFetching)     │
└──────────────┘                   └──────────────┬───────────────┘
       │                                          │
       │ setWidgets([])                           │ callback(QuotaSnapshot)
       ▼                                          ▼
┌──────────────┐                   ┌──────────────────────────────┐
│ QuotaWidget  │<──────────────────│ setSnapshot()                │
│ (onSnapshot  │                   │ -> onSnapshot callback       │
│  callback)   │                   └──────────────────────────────┘
└──────────────┘
       │ onSnapshot
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ AppDelegate (main.swift)                                         │
│  ├─ menuBar.update(snapshot) -> QuotaDisplayModel -> draw()      │
│  └─ settingsWindowController.update(viewModels)                  │
└──────────────────────────────────────────────────────────────────┘
```

Each provider is independently instantiated:
- 1 `QuotaModule` per provider
- 1 `QuotaReader` per module (with provider-specific `QuotaSnapshotFetching`)
- 1 `QuotaWidget` per module
- 1 `MenuBarController` per provider (its own `NSStatusItem`)

### App Wiring (main.swift)

`AppDelegate.applicationDidFinishLaunching`:

1. Set activation policy to `.accessory` (no Dock icon)
2. Load all providers from `QuotaProviderRegistry.defaultProviders()`
3. For each provider: create Module + Reader + Widget + MenuBarController
4. Wire `widget.onSnapshot` -> `menuBar.update()` + `settings.push()`
5. Mount menu bar items in persisted order (reversed for NSStatusBar semantics)
6. Wire Settings callbacks: `onVisibilityChanged`, `onOrderChanged`, `onRefreshRequested`

## 5. Domain Model

### QuotaWindow

```swift
QuotaWindow(
    id: String,                    // e.g. "hour_5", "week", "monthly"
    label: String,                 // e.g. "H", "W", "M"
    usedPercent: Int,              // 0-100, clamped at init
    resetAt: Date,
    // Optional extended fields (added in milestone 2):
    used: Double?,                 // Absolute usage value
    limit: Double?,                // Total quota
    remaining: Double?,            // Remaining quota
    unit: String?,                 // e.g. "tokens", "requests", "minutes"
    windowTitle: String?,          // e.g. "5-hour usage", "Monthly tokens"
    metadata: [String: String]?    // Provider-specific context
)
```

Normalization applied at init: `usedPercent` clamped 0-100, `used`/`remaining` non-negative, `limit` positive-only, `used` capped by `limit`, `remaining` inferred from `limit - used` if missing.

### QuotaSnapshot

```swift
QuotaSnapshot(
    providerID: String,
    windows: [QuotaWindow],
    fetchedAt: Date
)
```

### QuotaDisplayModel

Transforms `QuotaSnapshot` into menu bar display state:

- **H/W pinned layout**: top = W (Weekly), bottom = H (Hourly)
- **Missing H**: display `H: -- --`
- **Missing W**: display `W: -- --`
- **Color state**: Pace-driven (normal / warning / critical / unknown)

## 6. Pace Color Algorithm

```
elapsed      = clamp(1 - remain / duration)
expected     = 0.8 × elapsed^1.1
paceGap      = max(0, expected - usedRatio)
baseUrgency  = clamp(paceGap / 0.8)          ← clamped to [0, 1]
timePressure = elapsed^1.6
urgency      = baseUrgency × (0.35 + 0.65 × timePressure)
```

Thresholds: `warning >= 0.30`, `critical >= 0.60`

Duration mapping:
- Hourly window (`H`, `hour_5`, `5h`, `tokens_limit`) → 5 hours
- Daily window (`D`, `day`, `daily`) → 24 hours
- Weekly window (`W`, `week`, `weekly`, `time_limit`) → 7 days
- Monthly window (`M`, `month`, `monthly`) → 30 days
- Unrecognized → urgency = 0 (no pace data)

Special rule: **if W missing and H present, pace is computed from H alone**.

The urgency of all windows in scope is computed and the maximum is used for the final state.

## 7. Provider System

5 providers registered in `QuotaProviderRegistry.defaultProviders()`:

| Provider | Auth method | Data source | Windows |
|---|---|---|---|
| codex | `~/.codex/auth.json` (API key or OAuth) | Direct API | H (5-hour) + W (weekly) |
| zenmux | Browser cookies (`sessionId`, `sessionId.sig`, `ctoken`) | Direct API | Variable (sorted by period) |
| minimax | Browser cookies (all for `minimaxi.com`) | Direct API | Single window |
| bigmodel | Browser cookies → Bearer token extraction | Direct API | H (token) + W (time) |
| factory | Supabase anon key | Supabase `connector_events` | M (monthly) |

All implement:

```swift
public protocol QuotaSnapshotFetching: Sendable {
    func fetchSnapshot() throws -> QuotaSnapshot
}
```

### Adding a new provider

1. Create `<Provider>UsageClient` implementing `QuotaSnapshotFetching`
2. Map provider response to `QuotaSnapshot` + `[QuotaWindow]`
3. Register in `QuotaProviderRegistry.defaultProviders()`
4. Add provider icon SVG to `Resources/Icons/` (must set `image.isTemplate = true`)
5. Add tests: decoding, mapping, edge cases, regression

**If the provider uses Supabase connector events** (like Factory):
- Add capture rules to the Chrome Extension (`src/shared/contracts.js`)
- Create a client via `SupabaseConnectorEventClient` with a custom `snapshotMapper`
- See `docs/connector-ui-dataflow.md` for the full pipeline

## 8. Menu Bar Rendering

Each provider occupies its own `NSStatusItem` via `MenuBarController`:

- Left: 20×20 provider icon (SVG loaded as NSImage, template mode)
- Right: Two-line text drawn via `QuotaStatusView.draw(_:)`
  - Format: `<label>: <used%> <timeLeft>`
  - Top line = Weekly (W) or first window
  - Bottom line = Hourly (H) or second window

Layout constants (`QuotaLayoutMetrics`):
- `statusWidth = 100`, `statusHeight = 22`
- `iconSize = 20`, `iconX = 2`, `textX = 22`
- `topFont = .systemFont(ofSize: 9)`, `bottomFont = .systemFont(ofSize: 9)`

### Mount order

NSStatusBar places each new item LEFT of existing ones. To achieve desired left-to-right order:

1. `stop()` all current items
2. `start()` in **reverse** of desired order
3. Apply visibility per `ProviderVisibilityStore`

Trigger points: app launch, drag reorder (`onOrderChanged`), visibility toggle (`onVisibilityChanged` — must full remount, not just `setVisible`, to prevent order drift).

## 9. Settings UI

```
SettingsWindowController (NSPanel 640×440)
  ├── NSSplitViewController
  │     ├── ProviderListViewController  [left ~204px fixed]
  │     │     └── NSTableView + ProviderRowView (NSTableCellView)
  │     │           icon | name | "Updated: Xm ago" | status dot
  │     └── ProviderDetailViewController  [right flexible]
  │           header: 40×40 icon | name (ID) | account | Refresh button
  │           USAGE cards per window:
  │             [windowTitle | NSProgressIndicator bar | metrics | reset time]
  │           Show in menu bar: [label | spacer | NSSwitch]
  └── Data flow:
        onOrderChanged -> ProviderOrderStore.setOrder() -> mountMenuBars()
        onVisibilityChanged -> ProviderVisibilityStore -> mountMenuBars()
        onRefreshRequested -> QuotaModule.refresh() -> QuotaReader.read()
```

Visual tokens centralized in `SettingsTheme.swift`. ViewModel logic in `SettingsProviderViewModel.swift`.

See `docs/settings-ui-spec.md` for detailed spec.

## 10. Chrome Extension

`extensions/info-bar-web-connector/` — MV3 extension for capturing provider API responses when direct API access is impractical.

Pipeline:

1. **`factory-hook.js`** (MAIN world): Hooks `fetch` + `XMLHttpRequest`, captures matched API responses
2. **`bridge.js`** (content script): Relays page messages to service worker via `chrome.runtime.sendMessage`
3. **`service-worker.js`**: Normalizes payload, dedupes (10-min bucket + FNV-1a hash), writes to `chrome.storage.local` + Supabase `connector_events` table

Provider/rule registry: `src/shared/contracts.js`

Current capture rule: `api.factory.ai/api/organization/subscription/usage`

See `extensions/info-bar-web-connector/README.md` for setup, config, and validation.

## 11. Configuration

### Mac App

Supabase config resolution order (for Factory provider via `SupabaseConnectorEventClient`):

1. `INFOBAR_CONFIG_FILE` env var → explicit file path
2. `config.local.json` adjacent to executable
3. `SUPABASE_PROJECT_URL` + `SUPABASE_ANON_KEY` env vars
4. `config.example.json` (placeholder values detected and skipped)

### Chrome Extension

Config merge order:

1. Built-in defaults (`DEFAULT_SUPABASE_CONFIG`)
2. `config.example.json`
3. `config.local.json` (gitignored)
4. `chrome.storage.local.supabase_config` (runtime override)

Placeholder values (e.g., `your-project-ref.supabase.co`) are detected and treated as missing config.
