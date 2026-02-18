import XCTest
@testable import InfoBar

final class SettingsProviderViewModelTests: XCTestCase {
    func testNilSnapshotShowsDash() {
        let vm = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        XCTAssertEqual(vm.providerID, "codex")
        XCTAssertEqual(vm.summary, "—")
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
}
