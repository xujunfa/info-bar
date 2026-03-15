# Next Session Prompt

## Quick start

1. Read `.claude/CLAUDE.md` (project rules)
2. Read `.context/HANDOFF.md` (current state)
3. Read `.context/ACTIVE_CONTEXT.md` (milestone status, if resuming planned work)

## Current status

All 5 planned milestones are complete. The project is in a stable, shippable state.

Last verified: `swift build` clean, `swift test` 117 passed / 1 skipped / 0 failed.

## Known backlog (not yet started)

See `.context/HANDOFF.md` §5 "Known Issues" for items that may be worth addressing:
- Thread safety (`QuotaWidget.lastSnapshot`, persistence stores)
- Dead code cleanup (`state(for:)` ratio fallback, Kit layer unused paths)
- Security hardening (`FactoryBrowserRefreshTokenImporter` token escaping)
- Logic deduplication (H/W window identification)

## Constraints

- TDD: RED -> GREEN -> REFACTOR
- Run `swift build` and `swift test` before committing
- Conventional Commits
- Do not push unless explicitly asked
