import XCTest
@testable import InfoBar

final class BigModelUsageClientTests: XCTestCase {
    func testThrowsMissingCredentialsWhenCookieUnavailable() throws {
        let client = BigModelUsageClient(browserCookieImporter: StubBigModelBrowserImporter(result: .success(nil)))

        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            guard case BigModelUsageClientError.missingCredentials = error else {
                XCTFail("Expected missingCredentials, got \(error)")
                return
            }
        }
    }

    func testDecodesQuotaPayloadAndMapsSnapshot() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "success": true,
          "data": {
            "planName": "Free",
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "usage": 1000000,
                "currentValue": 250000,
                "remaining": 750000,
                "percentage": 25,
                "nextResetTime": 1768000000000
              },
              {
                "type": "TIME_LIMIT",
                "unit": 1,
                "number": 30,
                "usage": 1,
                "currentValue": 0,
                "remaining": 1,
                "percentage": 0,
                "nextResetTime": 1768600000000
              }
            ]
          }
        }
        """

        let response = try BigModelUsageClient.decodeResponse(data: Data(json.utf8))
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try BigModelUsageClient.mapToSnapshot(response: response, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.providerID, "bigmodel")
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].id, "tokens_limit")
        XCTAssertEqual(snapshot.windows[0].label, "H")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 25)
        XCTAssertEqual(snapshot.windows[0].used, 250_000)
        XCTAssertEqual(snapshot.windows[0].limit, 1_000_000)
        XCTAssertEqual(snapshot.windows[0].remaining, 750_000)
        XCTAssertEqual(snapshot.windows[0].unit, "tokens")
        XCTAssertEqual(snapshot.windows[0].windowTitle, "Token quota")
        XCTAssertEqual(snapshot.windows[0].metadata?["plan_name"], "Free")
        XCTAssertEqual(snapshot.windows[0].resetAt, Date(timeIntervalSince1970: 1_768_000_000))
        XCTAssertEqual(snapshot.windows[1].id, "time_limit")
        XCTAssertEqual(snapshot.windows[1].label, "W")
        XCTAssertEqual(snapshot.windows[1].usedPercent, 0)
        XCTAssertEqual(snapshot.windows[1].used, 0)
        XCTAssertEqual(snapshot.windows[1].limit, 1)
        XCTAssertEqual(snapshot.windows[1].remaining, 1)
        XCTAssertEqual(snapshot.windows[1].unit, "minutes")
        XCTAssertEqual(snapshot.windows[1].windowTitle, "Time quota")
        XCTAssertEqual(snapshot.windows[1].resetAt, Date(timeIntervalSince1970: 1_768_600_000))
    }

    func testMapsPercentageOnlyLimitWhenAbsoluteFieldsMissing() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "success": true,
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "percentage": 64,
                "nextResetTime": 1768000000
              }
            ]
          }
        }
        """

        let response = try BigModelUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try BigModelUsageClient.mapToSnapshot(
            response: response,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 64)
        XCTAssertEqual(snapshot.windows[0].resetAt, Date(timeIntervalSince1970: 1_768_000_000))
        XCTAssertNil(snapshot.windows[0].used)
        XCTAssertNil(snapshot.windows[0].limit)
        XCTAssertNil(snapshot.windows[0].remaining)
    }

    func testThrowsApiFailureWhenResponseIsNotSuccess() throws {
        let json = """
        {
          "code": 401,
          "msg": "invalid token",
          "success": false
        }
        """

        let response = try BigModelUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try BigModelUsageClient.mapToSnapshot(response: response, fetchedAt: Date())) { error in
            guard case let BigModelUsageClientError.apiFailure(message) = error else {
                XCTFail("Expected apiFailure, got \(error)")
                return
            }
            XCTAssertEqual(message, "invalid token")
        }
    }

    func testThrowsMissingUsageDataWhenLimitsEmpty() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "success": true,
          "data": {
            "limits": []
          }
        }
        """

        let response = try BigModelUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try BigModelUsageClient.mapToSnapshot(response: response, fetchedAt: Date())) { error in
            guard case BigModelUsageClientError.missingUsageData = error else {
                XCTFail("Expected missingUsageData, got \(error)")
                return
            }
        }
    }

    func testBigModelBrowserCookieImporterUsesReusableCollector() throws {
        let collector = StubQuotaCookieCollector(result: .success("bizCookie=abc"))
        let importer = BigModelBrowserCookieImporter(collector: collector)
        let header = try importer.importCookieHeader()

        XCTAssertEqual(header, "bizCookie=abc")
        XCTAssertEqual(
            collector.lastConfig?.domains,
            ["open.bigmodel.cn", ".bigmodel.cn", "bigmodel.cn", "z.ai", ".z.ai", "api.z.ai"]
        )
        XCTAssertEqual(collector.lastConfig?.requiredCookieNames, Set<String>())
        XCTAssertEqual(collector.lastConfig?.preferredBrowsers, [.chrome, .safari, .firefox])
    }

    func testExtractsAuthorizationTokenFromCookieHeader() {
        let token = BigModelUsageClient.authorizationToken(fromCookieHeader: "foo=bar; access_token=abc123; x=y")
        XCTAssertEqual(token, "abc123")
    }

    func testExtractsBigModelProductionTokenFromCookieHeader() {
        let token = BigModelUsageClient.authorizationToken(
            fromCookieHeader: "foo=bar; bigmodel_token_production=prod-token-xyz; x=y"
        )
        XCTAssertEqual(token, "prod-token-xyz")
    }
}

private struct StubBigModelBrowserImporter: BigModelBrowserCookieImporting {
    let result: Result<String?, Error>

    func importCookieHeader() throws -> String? {
        try result.get()
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
