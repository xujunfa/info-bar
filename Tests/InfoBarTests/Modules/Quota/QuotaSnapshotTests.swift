import XCTest
@testable import InfoBar

final class QuotaSnapshotTests: XCTestCase {
    func testQuotaSnapshotComputedFields() {
        let snapshot = QuotaSnapshot(
            limit: 1000,
            used: 250,
            resetAt: Date(timeIntervalSince1970: 1_800_000_000),
            fetchedAt: Date()
        )

        XCTAssertEqual(snapshot.remaining, 750)
        XCTAssertEqual(snapshot.usedRatio, 0.25, accuracy: 0.0001)
        XCTAssertFalse(snapshot.isExhausted)
    }
}
