import XCTest
@testable import InfoBar

final class MiniMaxUsageClientTests: XCTestCase {
    func testDecodesRemainsPayloadAndMapsSnapshot() throws {
        let json = """
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          },
          "model_remains": [
            {
              "model_name": "MiniMax-M2",
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 1350,
              "remains_time": 5400000
            }
          ]
        }
        """

        let response = try MiniMaxUsageClient.decodeResponse(data: Data(json.utf8))
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try MiniMaxUsageClient.mapToSnapshot(response: response, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.providerID, "minimax")
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].id, "hour_5")
        XCTAssertEqual(snapshot.windows[0].label, "H")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 10)
        XCTAssertEqual(snapshot.windows[0].resetAt, fetchedAt.addingTimeInterval(5_400))
    }

    func testMapsZeroUsedPercentWhenRemainsEqualsTotal() throws {
        let json = """
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          },
          "model_remains": [
            {
              "model_name": "MiniMax-M2",
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 1500,
              "remains_time": 300000
            }
          ]
        }
        """

        let response = try MiniMaxUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try MiniMaxUsageClient.mapToSnapshot(
            response: response,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(snapshot.windows[0].usedPercent, 0)
    }

    func testThrowsApiFailureWhenStatusCodeNonZero() throws {
        let json = """
        {
          "base_resp": {
            "status_code": 1004,
            "status_msg": "cookie is missing, log in again"
          }
        }
        """

        let response = try MiniMaxUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try MiniMaxUsageClient.mapToSnapshot(response: response, fetchedAt: Date())) { error in
            guard case let MiniMaxUsageClientError.apiFailure(message) = error else {
                XCTFail("Expected apiFailure, got \(error)")
                return
            }
            XCTAssertEqual(message, "cookie is missing, log in again")
        }
    }

    func testThrowsMissingUsageDataWhenModelRemainsUnavailable() throws {
        let json = """
        {
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          },
          "model_remains": []
        }
        """

        let response = try MiniMaxUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try MiniMaxUsageClient.mapToSnapshot(response: response, fetchedAt: Date())) { error in
            guard case MiniMaxUsageClientError.missingUsageData = error else {
                XCTFail("Expected missingUsageData, got \(error)")
                return
            }
        }
    }

    func testMiniMaxBrowserCookieImporterUsesReusableCollector() throws {
        let collector = StubQuotaCookieCollector(result: .success("foo=bar; baz=qux"))
        let importer = MiniMaxBrowserCookieImporter(collector: collector)
        let header = try importer.importCookieHeader()

        XCTAssertEqual(header, "foo=bar; baz=qux")
        XCTAssertEqual(
            collector.lastConfig?.domains,
            ["www.minimaxi.com", ".minimaxi.com", "minimaxi.com"]
        )
        XCTAssertEqual(collector.lastConfig?.requiredCookieNames, Set<String>())
        XCTAssertEqual(collector.lastConfig?.preferredBrowsers, [.chrome, .safari, .firefox])
    }
}

private final class StubQuotaCookieCollector: BrowserQuotaCookieCollecting {
    let result: Result<String?, Error>
    private(set) var lastConfig: BrowserQuotaCookieConfig?

    init(result: Result<String?, Error>) {
        self.result = result
    }

    func collectHeader(config: BrowserQuotaCookieConfig) throws -> String? {
        self.lastConfig = config
        return try result.get()
    }
}
