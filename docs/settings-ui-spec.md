# Settings UI Spec

Last updated: 2026-03-02

## Scope

This document defines the current behavior and information hierarchy of the Settings window (`InfoBar Settings`) for provider quota display.

## Sidebar (Provider List)

- Row height: `46` points.
- Each row shows:
  - Provider icon
  - Provider display name
  - Relative update time (`Updated: ...`)
  - Visibility status dot
- Visibility status dot:
  - Green: visible in menu bar
  - Gray: hidden from menu bar
- Selection behavior:
  - Non-empty list must always keep one selected item.
  - Clicking blank space must not clear selection.
  - If a selection clear is requested while list is non-empty, previous selection is restored; fallback to first row.

## Detail Header

- Header content:
  - Provider name
  - `ID: <providerID>`
  - Optional account identity if present:
    - `ID: <providerID>  ·  Account: <email/phone/...>`
  - Updated text (`Updated: ...`)
- Top-right controls:
  - Toggle switch (show/hide in menu bar), no label text
  - Refresh button (compact style)
  - Spinner loading indicator (hidden by default)

## Refresh Interaction

- On refresh click:
  - Refresh button hides and disables.
  - Spinner is shown and animated.
  - Tooltip changes to `Refreshing usage...`.
- After short feedback interval:
  - Spinner hides and stops.
  - Refresh button shows again and re-enables.
  - Tooltip returns to `Refresh usage`.

## Usage Window Card

- Window name normalization for presentation:
  - `Current interval` / `H` / `hour_5` variants -> `5-hour usage`
  - `W` / weekly variants -> `Weekly usage`
- Card content:
  - Window title
  - Percent value
  - Progress bar
  - Metric blocks (equal-width layout, fixed spacing)
  - Reset line
- Metrics shown only when value exists:
  - `USED`
  - `REMAINING`
  - `LIMIT`
  - `TOKENS (M)` (only for token unit and valid used value)
- Placeholder `-` values are not rendered in UI metric blocks.

## Reset Time Text

- Reset text format:
  - `resets at MM-dd HH:mm (in X)`
- If reset cannot be determined:
  - `reset time unknown`
