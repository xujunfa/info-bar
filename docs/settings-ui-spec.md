# Settings UI Spec

Last updated: 2026-03-02

## Scope

This document defines the current behavior of the Settings window (`InfoBar Settings`) for provider quota visualization and control.

## Layout and structure

- Panel size: `640 x 440`
- Split layout:
  - Sidebar fixed width: `204`
  - Detail minimum width: `320`
- Content inset: `20`

## Sidebar (provider list)

Row composition:

- Drag handle (`line.3.horizontal`)
- Provider icon
- Provider display name
- Relative update subtitle (`Updated: ...`)
- Visibility status dot

Row rules:

- Row height: `46`
- Row spacing: `1`
- Empty selection is not allowed when list is non-empty
- Clicking list blank area must not clear the current selection
- If selection clear is requested while list has items, restore previous selection or fallback to first item

Status dot color:

- Green: visible in menu bar
- Gray: hidden from menu bar

List subtitle copy:

- With snapshot: `Updated: just now | Xm ago | Xh ago | Xd ago`
- Without snapshot: `Updated: waiting for first snapshot`

## Detail header

Header fields:

- Provider name (capitalized provider ID)
- Provider ID: `ID: <providerID>`
- Optional account suffix:
  - `ID: <providerID>  ·  Account: <value>`
  - account value is extracted from metadata keys by priority:
    `account_email`, `email`, `user_email`, `account_phone`, `phone`, `mobile`, `user_phone`, `account`, `account_name`, `user_name`, `user`
- Relative update time text (same formatter as sidebar)

Header controls (right side):

- Visibility toggle (`NSSwitch`, no text label)
- Compact refresh icon button (`arrow.clockwise`)
- Spinner (`NSProgressIndicator`) for refresh feedback

## Refresh interaction

On refresh click:

- Hide refresh button
- Disable refresh button
- Show spinner and start animation
- Refresh tooltip: `Refreshing usage...`

Feedback reset:

- Delay: about `0.45s`
- Hide spinner and stop animation
- Show and re-enable refresh button
- Tooltip back to `Refresh usage`

## Usage card structure

Each usage window card contains:

- Top row: normalized window title + percentage text
- Progress bar (`0...100`)
- Optional metric block row
- Reset text row

Metric block rendering:

- Blocks are equal-width and only rendered when corresponding value is available
- Supported blocks:
  - `USED`
  - `REMAINING`
  - `LIMIT`
  - `TOKENS (M)` (only when unit contains `token` and used value > 0)
- No placeholder dash blocks are rendered

Value formatting:

- Numeric abbreviation: `K`, `M`, `B`
- Absolute usage:
  - both used+limit: `<used>/<limit> <unit>`
  - only used: `<used> <unit>`
  - only limit: `0/<limit> <unit>`
- Missing values display `—` only in view-model text; UI hides unavailable metric blocks

## Copy and label rules

Window label normalization:

- Weekly aliases (`W`, `weekly`, `period_type=week`) -> `Weekly usage`
- 5-hour aliases (`H`, `current interval`, `hour_5`, `period_type=hour`) -> `5-hour usage`

Reset text:

- Standard: `resets at MM-dd HH:mm (in X)`
- Unknown/past reset: `reset time unknown`

Metadata display policy:

- Usage card does not show raw metadata text blocks
- Metadata is still used internally for account extraction and label normalization

## Empty states

No provider selected:

- Center placeholder card:
  - title: `Select a provider`
  - description: `Choose a provider in the left list to inspect usage windows, refresh data, and toggle menu visibility.`

Provider selected but no window data:

- Usage placeholder card:
  - title: `No usage data yet`
  - with no snapshot: `Run Refresh to load the first quota snapshot for this provider.`
  - with snapshot but no windows: `Latest snapshot did not include window metrics.`

## Interaction invariants

- Drag-and-drop ordering remains enabled in sidebar
- `Command + W` closes settings panel
- `show(selectingProviderID:)` pre-selects provider when available
- Selection persists across `update(viewModels:)` refresh cycles when possible
