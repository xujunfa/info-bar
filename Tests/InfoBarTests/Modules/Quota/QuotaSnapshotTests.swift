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
}
