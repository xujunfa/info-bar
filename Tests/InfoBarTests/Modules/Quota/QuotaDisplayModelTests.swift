import XCTest
@testable import InfoBar

final class QuotaDisplayModelTests: XCTestCase {
    func testDisplayModelFromSnapshotUsesHWLines() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 13,
                    resetAt: fetchedAt.addingTimeInterval(2 * 3600)
                ),
                QuotaWindow(
                    id: "weekly",
                    label: "W",
                    usedPercent: 20,
                    resetAt: fetchedAt.addingTimeInterval((2 * 24 + 3.5) * 3600)
                )
            ],
            fetchedAt: fetchedAt
        )
        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.text, "H: 13% 2h | W: 20% 2.1d")
        XCTAssertEqual(model.topLine, "H: 13% 2h")
        XCTAssertEqual(model.bottomLine, "W: 20% 2.1d")
        XCTAssertEqual(model.ratio, 0.13, accuracy: 0.0001)
        XCTAssertEqual(model.state, .normal)
    }

    func testDisplayModelFallbackWhenWeeklyWindowMissing() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 85,
                    resetAt: fetchedAt.addingTimeInterval(2.5 * 3600)
                )
            ],
            fetchedAt: fetchedAt
        )
        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "H: 85% 2.5h")
        XCTAssertEqual(model.bottomLine, "W: -- --")
        XCTAssertEqual(model.state, .warning)
    }

    func testDisplayModelSupportsGenericLabelsForOtherAgents() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "agent-x",
            windows: [
                QuotaWindow(id: "daily", label: "D", usedPercent: 55, resetAt: fetchedAt.addingTimeInterval(3600)),
                QuotaWindow(id: "monthly", label: "M", usedPercent: 12, resetAt: fetchedAt.addingTimeInterval(26 * 3600))
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "D: 55% 1h")
        XCTAssertEqual(model.bottomLine, "M: 12% 1.1d")
    }

    func testDisplayModelUsesMinutesWhenLessThanOneHour() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "zenmux",
            windows: [
                QuotaWindow(id: "hour_5", label: "H", usedPercent: 1, resetAt: fetchedAt.addingTimeInterval(45 * 60)),
                QuotaWindow(id: "week", label: "W", usedPercent: 10, resetAt: fetchedAt.addingTimeInterval(3_600))
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "H: 1% 45min")
    }
}
