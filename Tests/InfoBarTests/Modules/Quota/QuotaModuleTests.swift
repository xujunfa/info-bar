import XCTest
@testable import InfoBar

final class QuotaModuleTests: XCTestCase {
    func testRefreshPushesLatestSnapshotToWidget() {
        let expected = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(id: "five_hour", label: "H", usedPercent: 40, resetAt: Date(timeIntervalSince1970: 200))
            ],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let reader = QuotaReader(fetcher: StubFetcher(result: .success(expected)))
        let module = QuotaModule(reader: reader)
        let widget = QuotaWidget()
        let exp = expectation(description: "snapshot pushed to widget")

        widget.onSnapshot = { snapshot in
            if snapshot == expected {
                exp.fulfill()
            }
        }
        module.setWidgets([widget])

        module.refresh()
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(widget.lastSnapshot, expected)
    }
}

private struct StubFetcher: QuotaSnapshotFetching {
    let result: Result<QuotaSnapshot, Error>

    func fetchSnapshot() throws -> QuotaSnapshot {
        try result.get()
    }
}
