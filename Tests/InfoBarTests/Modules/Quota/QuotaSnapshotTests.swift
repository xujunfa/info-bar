import XCTest
@testable import InfoBar

final class QuotaSnapshotTests: XCTestCase {
    func testQuotaSnapshotComputedFields() {
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 120,
                    resetAt: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                QuotaWindow(
                    id: "weekly",
                    label: "W",
                    usedPercent: -10,
                    resetAt: Date(timeIntervalSince1970: 1_900_000_000)
                )
            ],
            fetchedAt: Date()
        )

        XCTAssertEqual(snapshot.primaryWindow?.usedPercent, 100)
        XCTAssertEqual(snapshot.windows[1].usedPercent, 0)
        XCTAssertEqual(snapshot.primaryUsedRatio, 1.0)
    }

    func testQuotaWindowSanitizesOptionalUsageFields() {
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 42,
            resetAt: Date(timeIntervalSince1970: 1_900_000_000),
            used: 1_500,
            limit: 1_000,
            remaining: -10,
            unit: " tokens ",
            windowTitle: " Monthly budget ",
            metadata: [
                " source ": " api ",
                "": "invalid",
                "note": ""
            ]
        )

        XCTAssertEqual(window.used, 1_000)
        XCTAssertEqual(window.limit, 1_000)
        XCTAssertEqual(window.remaining, 0)
        XCTAssertEqual(window.unit, "tokens")
        XCTAssertEqual(window.windowTitle, "Monthly budget")
        XCTAssertEqual(window.metadata, ["source": "api"])
    }

    func testQuotaWindowInfersRemainingFromUsedAndLimitWhenMissing() {
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 25,
            resetAt: Date(),
            used: 250,
            limit: 1_000,
            remaining: nil,
            unit: "tokens"
        )

        XCTAssertEqual(window.used, 250)
        XCTAssertEqual(window.limit, 1_000)
        XCTAssertEqual(window.remaining, 750)
    }

    func testQuotaWindowDropsInvalidLimitAndKeepsUsed() {
        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: 25,
            resetAt: Date(),
            used: 250,
            limit: 0,
            unit: "tokens"
        )

        XCTAssertEqual(window.used, 250)
        XCTAssertNil(window.limit)
        XCTAssertNil(window.remaining)
    }
}
