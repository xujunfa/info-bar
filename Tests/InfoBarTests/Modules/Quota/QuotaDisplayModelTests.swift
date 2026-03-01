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

        XCTAssertEqual(model.text, "W: 20% 2.1d | H: 13% 2h")
        XCTAssertEqual(model.topLine, "W: 20% 2.1d")
        XCTAssertEqual(model.bottomLine, "H: 13% 2h")
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

        XCTAssertEqual(model.topLine, "W: -- --")
        XCTAssertEqual(model.bottomLine, "H: 85% 2.5h")
        XCTAssertEqual(model.state, .normal)
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

        XCTAssertEqual(model.topLine, "W: 10% 1h")
        XCTAssertEqual(model.bottomLine, "H: 1% 45min")
    }

    func testDisplayModelPinsHWLinesWhenInputOrderIsUnexpected() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "zenmux",
            windows: [
                QuotaWindow(id: "week", label: "W", usedPercent: 20, resetAt: fetchedAt.addingTimeInterval(3600)),
                QuotaWindow(id: "hour_5", label: "H", usedPercent: 5, resetAt: fetchedAt.addingTimeInterval(30 * 60))
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "W: 20% 1h")
        XCTAssertEqual(model.bottomLine, "H: 5% 30min")
    }

    func testDisplayModelShowsWeeklyOnTopLineWhenHourlyMissing() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "zenmux",
            windows: [
                QuotaWindow(id: "week", label: "W", usedPercent: 42, resetAt: fetchedAt.addingTimeInterval(2 * 3600))
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "W: 42% 2h")
        XCTAssertEqual(model.bottomLine, "H: -- --")
    }

    func testDisplayModelTurnsCriticalWhenPaceFarBehindNearReset() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 0,
                    resetAt: fetchedAt.addingTimeInterval(20 * 60)
                )
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.state, .critical)
    }

    func testDisplayModelTurnsWarningWhenPaceBehind() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 20,
                    resetAt: fetchedAt.addingTimeInterval(45 * 60)
                )
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.state, .warning)
    }

    func testDisplayModelTurnsWarningForWeeklyWhenLowNearReset() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "weekly",
                    label: "W",
                    usedPercent: 36,
                    resetAt: fetchedAt.addingTimeInterval(1.1 * 24 * 3600)
                )
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.state, .warning)
    }

    func testDisplayModelUsesHourlyAloneWhenWeeklyMissing() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(
                    id: "five_hour",
                    label: "H",
                    usedPercent: 80,
                    resetAt: fetchedAt.addingTimeInterval(4 * 3600)
                ),
                QuotaWindow(
                    id: "monthly",
                    label: "M",
                    usedPercent: 0,
                    resetAt: fetchedAt.addingTimeInterval(1 * 24 * 3600)
                )
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.state, .normal)
    }

    func testDisplayModelSupportsFactoryMonthlyFormat() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = QuotaSnapshot(
            providerID: "factory",
            windows: [
                QuotaWindow(
                    id: "monthly",
                    label: "M",
                    usedPercent: 40,
                    resetAt: fetchedAt.addingTimeInterval(1.2 * 24 * 3600)
                )
            ],
            fetchedAt: fetchedAt
        )

        let model = QuotaDisplayModel(snapshot: snapshot)

        XCTAssertEqual(model.topLine, "M: 40% 1.2d")
    }
}
