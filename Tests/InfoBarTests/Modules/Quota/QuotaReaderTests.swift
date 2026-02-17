import XCTest
@testable import InfoBar

final class QuotaReaderTests: XCTestCase {
    func testReadPublishesSnapshotFromFetcher() {
        let expected = QuotaSnapshot(
            providerID: "codex",
            windows: [
                QuotaWindow(id: "five_hour", label: "H", usedPercent: 35, resetAt: Date(timeIntervalSince1970: 200)),
                QuotaWindow(id: "weekly", label: "W", usedPercent: 20, resetAt: Date(timeIntervalSince1970: 300))
            ],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let reader = QuotaReader(fetcher: StubFetcher(result: .success(expected)))

        let exp = expectation(description: "callback")
        var received: QuotaSnapshot?
        reader.callback = { (snapshot: QuotaSnapshot?) in
            received = snapshot
            exp.fulfill()
        }

        reader.read()
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(received, expected)
    }

    func testReadPublishesNilWhenFetcherFails() {
        let reader = QuotaReader(fetcher: StubFetcher(result: .failure(StubError.boom)))

        let exp = expectation(description: "callback")
        var received: QuotaSnapshot?
        reader.callback = { (snapshot: QuotaSnapshot?) in
            received = snapshot
            exp.fulfill()
        }

        reader.read()
        wait(for: [exp], timeout: 1.0)

        XCTAssertNil(received)
    }
}

private enum StubError: Error {
    case boom
}

private struct StubFetcher: QuotaSnapshotFetching {
    let result: Result<QuotaSnapshot, Error>

    func fetchSnapshot() throws -> QuotaSnapshot {
        try result.get()
    }
}
