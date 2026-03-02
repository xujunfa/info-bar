import XCTest
@testable import InfoBar

final class SettingsProviderViewModelTests: XCTestCase {
    func testNilSnapshotShowsDash() {
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        XCTAssertEqual(vm.providerID, "codex")
        XCTAssertEqual(vm.summary, "—")
        XCTAssertEqual(vm.listSummary, "Updated: waiting for first snapshot")
        XCTAssertEqual(vm.status, .visible)
        XCTAssertEqual(vm.statusText, "Visible")
    }

    func testSnapshotWithSingleWindowShowsFormatted() {
        let w = QuotaWindow(id: "w", label: "T", usedPercent: 45, resetAt: Date())
        let snap = QuotaSnapshot(providerID: "codex", windows: [w], fetchedAt: Date())
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap)
        XCTAssertEqual(vm.summary, "T: 45%")
    }

    func testSnapshotWithMultipleWindowsJoinsWithSpaces() {
        let windows = [
            QuotaWindow(id: "w1", label: "T", usedPercent: 45, resetAt: Date()),
            QuotaWindow(id: "w2", label: "M", usedPercent: 30, resetAt: Date()),
        ]
        let snap = QuotaSnapshot(providerID: "codex", windows: windows, fetchedAt: Date())
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap)
        XCTAssertEqual(vm.summary, "T: 45%  M: 30%")
    }

    func testEmptyWindowsShowsDash() {
        let snap = QuotaSnapshot(providerID: "codex", windows: [], fetchedAt: Date())
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap)
        XCTAssertEqual(vm.summary, "—")
    }

    func testIsVisibleDefaultsToTrue() {
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        XCTAssertTrue(vm.isVisible)
    }

    func testIsVisibleCanBeSetFalse() {
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: nil, isVisible: false)
        XCTAssertFalse(vm.isVisible)
        XCTAssertEqual(vm.status, .hidden)
        XCTAssertEqual(vm.statusText, "Hidden")
    }

    func testWindowsArePopulatedFromSnapshot() {
        let resetAt = Date().addingTimeInterval(86400 * 2 + 3600)  // 2+ days from now
        let w = QuotaWindow(id: "w", label: "Session", usedPercent: 78, resetAt: resetAt)
        let snap = QuotaSnapshot(providerID: "codex", windows: [w], fetchedAt: Date())
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap)
        XCTAssertEqual(vm.windows.count, 1)
        XCTAssertEqual(vm.windows[0].label, "Session")
        XCTAssertEqual(vm.windows[0].usedPercent, 78)
        XCTAssertEqual(vm.windows[0].timeLeft, "2d")
    }

    func testFetchedAtIsSet() {
        let fetchedAt = Date()
        let snap = QuotaSnapshot(providerID: "codex", windows: [], fetchedAt: fetchedAt)
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap)
        XCTAssertEqual(vm.fetchedAt, fetchedAt)

        let vmNil = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        XCTAssertNil(vmNil.fetchedAt)
    }

    func testWindowViewModelIncludesAbsoluteUsageAndResetText() {
        let now = Date()
        let resetAt = now.addingTimeInterval(3600)
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 26,
            resetAt: resetAt,
            used: 1_250,
            limit: 10_000,
            unit: "tokens",
            windowTitle: "Monthly"
        )

        let vm = SettingsProviderViewModel(
            providerID: "factory",
            snapshot: QuotaSnapshot(providerID: "factory", windows: [window], fetchedAt: now),
            now: now
        )

        XCTAssertEqual(vm.windows.count, 1)
        XCTAssertEqual(vm.windows[0].label, "Monthly")
        XCTAssertEqual(vm.windows[0].absoluteUsageText, "1.3K/10K tokens")
        XCTAssertEqual(vm.windows[0].usedText, "1.3K tokens")
        XCTAssertEqual(vm.windows[0].remainingText, "8.8K tokens")
        XCTAssertEqual(vm.windows[0].limitText, "10K tokens")
        XCTAssertEqual(vm.windows[0].unitText, "tokens")
        XCTAssertTrue(vm.windows[0].resetText.hasPrefix("resets at "))
        XCTAssertTrue(vm.windows[0].resetText.contains("(in 1h)"))
        XCTAssertEqual(vm.listSummary, "Updated: just now")
    }

    func testWindowViewModelFallsBackWhenAbsoluteUsageMissing() {
        let now = Date()
        let resetAt = now.addingTimeInterval(-1)
        let window = QuotaWindow(id: "monthly", label: "M", usedPercent: 26, resetAt: resetAt)

        let vm = SettingsProviderViewModel(
            providerID: "factory",
            snapshot: QuotaSnapshot(providerID: "factory", windows: [window], fetchedAt: now),
            now: now
        )

        XCTAssertEqual(vm.windows[0].absoluteUsageText, "—")
        XCTAssertEqual(vm.windows[0].resetText, "reset time unknown")
        XCTAssertEqual(vm.windows[0].usedText, "—")
        XCTAssertEqual(vm.windows[0].remainingText, "—")
        XCTAssertEqual(vm.windows[0].limitText, "—")
    }

    func testWindowViewModelFormatsUsedOnlyAbsoluteValue() {
        let now = Date()
        let resetAt = now.addingTimeInterval(120)
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 26,
            resetAt: resetAt,
            used: 987,
            unit: "requests"
        )

        let vm = SettingsProviderViewModel(
            providerID: "factory",
            snapshot: QuotaSnapshot(providerID: "factory", windows: [window], fetchedAt: now),
            now: now
        )

        XCTAssertEqual(vm.windows[0].absoluteUsageText, "987 requests")
        XCTAssertTrue(vm.windows[0].resetText.hasPrefix("resets at "))
        XCTAssertTrue(vm.windows[0].resetText.contains("(in 2m)"))
        XCTAssertEqual(vm.windows[0].usedText, "987 requests")
        XCTAssertEqual(vm.windows[0].remainingText, "—")
        XCTAssertEqual(vm.windows[0].limitText, "—")
    }

    func testWindowViewModelIncludesTokenUsageInMillions() {
        let now = Date()
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 26,
            resetAt: now.addingTimeInterval(120),
            used: 4_100,
            unit: "tokens"
        )

        let vm = SettingsProviderViewModel(
            providerID: "factory",
            snapshot: QuotaSnapshot(providerID: "factory", windows: [window], fetchedAt: now),
            now: now
        )

        XCTAssertEqual(vm.windows[0].tokenUsageInMillionsText, "0.004M")
    }

    func testProviderStatusUsesWarningWhenVisibleAndNearLimit() {
        let resetAt = Date().addingTimeInterval(3600)
        let window = QuotaWindow(id: "w", label: "hourly", usedPercent: 95, resetAt: resetAt)
        let snap = QuotaSnapshot(providerID: "codex", windows: [window], fetchedAt: Date())

        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snap, isVisible: true)
        XCTAssertEqual(vm.status, .warning)
        XCTAssertEqual(vm.statusText, "High usage")
    }

    func testWindowViewModelBuildsMetadataSummaryFromPrioritizedFields() {
        let now = Date()
        let window = QuotaWindow(
            id: "w",
            label: "monthly",
            usedPercent: 40,
            resetAt: now.addingTimeInterval(7200),
            used: 1_200,
            limit: 3_000,
            unit: "tokens",
            metadata: [
                "hook": "fetch",
                "period_type": "weekly",
                "model_name": "MiniMax-M2",
                "trace_id": "trace-1",
                "extra_key": "extra-value",
            ]
        )
        let snap = QuotaSnapshot(providerID: "minimax", windows: [window], fetchedAt: now)

        let vm = SettingsProviderViewModel(providerID: "minimax", snapshot: snap, now: now)
        XCTAssertEqual(vm.windows[0].metadataItems.count, 3)
        XCTAssertEqual(vm.windows[0].metadataItems.map(\.text), [
            "Model: MiniMax-M2",
            "Window: weekly",
            "Source: fetch",
        ])
        XCTAssertEqual(vm.windows[0].metadataText, "Model: MiniMax-M2  ·  Window: weekly  ·  Source: fetch")
    }

    func testListSummaryUsesRelativeUpdatedTime() {
        let now = Date(timeIntervalSince1970: 2_000)
        let fetchedAt = now.addingTimeInterval(-7200)
        let window = QuotaWindow(id: "w", label: "W", usedPercent: 20, resetAt: now.addingTimeInterval(600))
        let snapshot = QuotaSnapshot(providerID: "codex", windows: [window], fetchedAt: fetchedAt)

        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: snapshot, now: now)
        XCTAssertEqual(vm.listSummary, "Updated: 2h ago")
    }

    func testAccountInfoIsExtractedFromWindowMetadata() {
        let now = Date()
        let window = QuotaWindow(
            id: "w",
            label: "W",
            usedPercent: 30,
            resetAt: now.addingTimeInterval(600),
            metadata: [
                "email": "dev@example.com",
                "phone": "+86 13800000000",
            ]
        )

        let vm = SettingsProviderViewModel(
            providerID: "codex",
            snapshot: QuotaSnapshot(providerID: "codex", windows: [window], fetchedAt: now),
            now: now
        )
        XCTAssertEqual(vm.accountText, "dev@example.com")
    }

    func testWindowLabelsAreStandardizedForFiveHourAndWeeklyWindows() {
        let now = Date()
        let windows = [
            QuotaWindow(
                id: "hour_5",
                label: "H",
                usedPercent: 33,
                resetAt: now.addingTimeInterval(600),
                windowTitle: "Current interval"
            ),
            QuotaWindow(
                id: "week",
                label: "W",
                usedPercent: 12,
                resetAt: now.addingTimeInterval(3600)
            ),
        ]
        let vm = SettingsProviderViewModel(
            providerID: "minimax",
            snapshot: QuotaSnapshot(providerID: "minimax", windows: windows, fetchedAt: now),
            now: now
        )

        XCTAssertEqual(vm.windows.map(\.label), ["5-hour usage", "Weekly usage"])
    }
}
