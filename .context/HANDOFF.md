# Info Bar Handoff

> Last updated: 2026-03-11
> Previous version archived: `.context/archive/HANDOFF-2026-03-02-pre-doc-cleanup.md`

## 1. Current Status

- All 5 milestones completed (Settings UI upgrade + Usage model extension + Provider mapping + Settings info presentation + Regression & docs)
- `swift test`: 117 passed, 1 skipped, 0 failed (last verified 2026-03-02)
- `swift build`: clean, 0 warnings

## 2. Provider Status

| Provider | Auth | Data source | Status |
|---|---|---|---|
| codex | `~/.codex/auth.json` | Direct API | Stable |
| zenmux | Browser cookies | Direct API | Stable |
| minimax | Browser cookies | Direct API | Stable |
| bigmodel | Browser cookies → Bearer token | Direct API | Stable |
| factory | Supabase anon key | Chrome Extension → Supabase | Stable |

## 3. Architecture Summary

- **App entry**: `Sources/InfoBarApp/main.swift` — pure AppKit, `NSApplication.shared.run()`
- **Core pipeline**: `QuotaModule` -> `QuotaReader` (Repeater timer) -> `QuotaWidget` -> `MenuBarController`
- **Settings**: `NSPanel` + `NSSplitViewController` (left list + right detail)
- **Menu bar**: One `NSStatusItem` per provider, two-line `draw()`-based widget
- **Chrome Extension**: `extensions/info-bar-web-connector/` (MV3, Factory capture only)

## 4. Key File Index

| Area | Key files |
|---|---|
| Entry & wiring | `Sources/InfoBarApp/main.swift` |
| Domain model | `Modules/Quota/QuotaSnapshot.swift`, `QuotaDisplayModel.swift` |
| Module lifecycle | `Modules/Quota/QuotaModule.swift`, `QuotaReader.swift`, `QuotaWidget.swift` |
| Provider clients | `CodexUsageClient.swift`, `ZenMuxUsageClient.swift`, `MiniMaxUsageClient.swift`, `BigModelUsageClient.swift`, `FactoryUsageClient.swift` |
| Supabase | `SupabaseConnectorEventClient.swift` |
| Menu bar | `UI/MenuBar/MenuBarController.swift`, `QuotaStatusView.swift`, `QuotaLayoutMetrics.swift` |
| Settings | `UI/Settings/SettingsWindowController.swift`, `SettingsProviderViewModel.swift`, `SettingsTheme.swift` |
| Persistence | `ProviderOrderStore.swift`, `ProviderVisibilityStore.swift` |

All paths relative to `Sources/InfoBar/`.

## 5. Known Issues (not yet addressed)

1. **Thread safety**: `QuotaWidget.lastSnapshot` mutated on background queue, read from main thread — data race risk
2. **Thread safety**: `ProviderOrderStore` / `ProviderVisibilityStore` lack `@MainActor` isolation
3. **Dead code**: `state(for:)` ratio-based fallback (0.7/0.9 thresholds) never executes — `paceState` always returns non-nil
4. **Duplicated logic**: H/W window identification in both `QuotaDisplayModel` and `SettingsProviderViewModel`
5. **Security**: `FactoryBrowserRefreshTokenImporter` token value not escaped before JS injection

## 6. Documentation Map

| Document | Purpose |
|---|---|
| `.claude/CLAUDE.md` | Project rules, constraints, conventions |
| `.context/DESIGN.md` | Technical architecture |
| `.context/HANDOFF.md` | Current state for session continuity (this file) |
| `.context/ACTIVE_CONTEXT.md` | Milestone tracking |
| `.context/IMPLEMENTATION_PLAN.md` | Detailed task plan (all complete) |
| `.context/DECISIONS.md` | Decision log |
| `docs/provider-usage-mapping.md` | Provider field mapping matrix |
| `docs/settings-ui-spec.md` | Settings page visual spec |
| `docs/connector-ui-dataflow.md` | Extension → Supabase → App data flow |
| `docs/settings-qa-checklist.md` | Manual QA checklist |
