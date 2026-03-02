# Settings QA Checklist

Last updated: 2026-03-02

## Execution record

## Automated regression checks

| Check | Command | Result | Notes |
| --- | --- | --- | --- |
| Full project tests | `swift test` | PASS | 117 passed, 1 skipped, 0 failed |
| Settings-focused tests | `swift test --filter 'SettingsProviderViewModelTests|SettingsWindowControllerTests'` | PASS | Previously run in milestone flow; latest assertions cover row selection, refresh feedback, metric visibility, and label normalization |

## Manual acceptance checklist

| Area | Scenario | Expected | Result | Evidence |
| --- | --- | --- | --- | --- |
| Sidebar selection | Click blank area in sidebar | Current row remains selected | PASS | Covered by `testSelectionRemainsWhenClearingSelectionOnNonEmptyList` |
| Sidebar identity | Verify row structure in Settings UI | Icon + name + `Updated:` text + status dot | PASS | Covered by `testSidebarRowShowsUsageSummaryAndStatusText` and implementation inspection |
| Header account display | Provider metadata contains account key | Header shows `ID: ...  ·  Account: ...` | PASS | Covered by `testDetailHeaderShowsAccountInfoBesideIDWhenAvailable` |
| Refresh interaction | Click refresh button once | Button swaps to spinner, then restores in ~0.45s | PASS | Covered by `testRefreshButtonUsesIconOnlyPresentation` + `testRefreshButtonCallbackChainUsesSelectedProviderID` and code path `applyRefreshFeedback` |
| Usage card noise control | Window misses used/remaining/limit | Missing blocks are hidden (no dash placeholders) | PASS | Covered by `testUsageCardOmitsUnavailableMetricsInsteadOfDashPlaceholders` |
| Window title normalization | Source label is `H`, `W`, `Current interval`, etc. | Shown as `5-hour usage` / `Weekly usage` | PASS | Covered by `testWindowLabelsAreStandardizedForFiveHourAndWeeklyWindows` |
| Token metric | Token unit + valid used value | Extra `TOKENS (M)` block is shown | PASS | Covered by `testWindowViewModelIncludesTokenUsageInMillions` |
| Placeholder state | Empty provider list / no windows | Selection placeholder and usage placeholder copy are correct | PASS | Covered by `testEmptyProviderListShowsSelectionPlaceholder` and `testProviderWithoutWindowsShowsUsagePlaceholder` |

## Sign-off summary

- Milestone 5 acceptance baseline is satisfied by full `swift test` pass and updated documentation set.
- No automated regressions were detected in Quota or Settings modules.
