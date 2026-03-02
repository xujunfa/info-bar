import XCTest
@testable import InfoBar

final class ZenMuxUsageClientTests: XCTestCase {
    func testDecodesUsageEnvelopeAndMapsSnapshot() throws {
        let json = """
        {
          "success": true,
          "message": "ok",
          "data": {
            "usage_percent": 41,
            "reset_at": 1768000000,
            "weekly_usage_percent": 9,
            "weekly_reset_at": 1768600000
          }
        }
        """

        let response = try ZenMuxUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try ZenMuxUsageClient.mapToSnapshot(response: response, fetchedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.providerID, "zenmux")
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].label, "M")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 41)
        XCTAssertEqual(snapshot.windows[0].resetAt, Date(timeIntervalSince1970: 1768000000))
        XCTAssertEqual(snapshot.windows[0].metadata?["period_type"], "monthly")
        XCTAssertEqual(snapshot.windows[1].label, "W")
        XCTAssertEqual(snapshot.windows[1].usedPercent, 9)
        XCTAssertEqual(snapshot.windows[1].resetAt, Date(timeIntervalSince1970: 1768600000))
        XCTAssertEqual(snapshot.windows[1].windowTitle, "Weekly usage")
        XCTAssertEqual(snapshot.windows[1].metadata?["period_type"], "weekly")
    }

    func testThrowsWhenUsageFieldsMissing() throws {
        let json = """
        {
          "success": true,
          "message": "ok",
          "data": {
            "foo": "bar"
          }
        }
        """

        let response = try ZenMuxUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try ZenMuxUsageClient.mapToSnapshot(response: response, fetchedAt: Date())) { error in
            guard case let ZenMuxUsageClientError.missingUsageData(raw) = error else {
                XCTFail("Expected missingUsageData, got \(error)")
                return
            }
            XCTAssertNotNil(raw)
            XCTAssertTrue(raw?.contains("\"foo\"") == true)
        }
    }

    func testMapsRealZenMuxArrayPayload() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "periodType": "week",
              "usedRate": 0.11818452165515873,
              "cycleEndTime": "2026-02-21T02:00:08.000Z"
            },
            {
              "periodType": "hour_5",
              "usedRate": 0.010664101871666666,
              "cycleEndTime": "2026-02-17T16:05:06.000Z"
            }
          ]
        }
        """

        let response = try ZenMuxUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try ZenMuxUsageClient.mapToSnapshot(response: response, fetchedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.providerID, "zenmux")
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].id, "hour_5")
        XCTAssertEqual(snapshot.windows[0].label, "H")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 1)
        XCTAssertEqual(snapshot.windows[0].resetAt, Date(timeIntervalSince1970: 1_771_344_306))
        XCTAssertEqual(snapshot.windows[1].id, "week")
        XCTAssertEqual(snapshot.windows[1].label, "W")
        XCTAssertEqual(snapshot.windows[1].usedPercent, 12)
        XCTAssertEqual(snapshot.windows[1].resetAt, Date(timeIntervalSince1970: 1_771_639_208))
    }

    func testParsesObjectPayloadArrayAndSupplementaryUsageFields() throws {
        let json = """
        {
          "success": true,
          "data": {
            "usageWindows": [
              {
                "periodType": "month",
                "used": 2400,
                "limit": 12000,
                "remaining": 9600,
                "next_reset_at": 1769600000,
                "unit": "tokens",
                "title": "Monthly tokens"
              },
              {
                "periodType": "week",
                "usedRate": 0.2,
                "cycleEndTime": 1769000000
              }
            ]
          }
        }
        """

        let response = try ZenMuxUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try ZenMuxUsageClient.mapToSnapshot(
            response: response,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].id, "week")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 20)
        XCTAssertEqual(snapshot.windows[1].id, "month")
        XCTAssertEqual(snapshot.windows[1].usedPercent, 20)
        XCTAssertEqual(snapshot.windows[1].used, 2_400)
        XCTAssertEqual(snapshot.windows[1].limit, 12_000)
        XCTAssertEqual(snapshot.windows[1].remaining, 9_600)
        XCTAssertEqual(snapshot.windows[1].unit, "tokens")
        XCTAssertEqual(snapshot.windows[1].windowTitle, "Monthly tokens")
        XCTAssertEqual(snapshot.windows[1].resetAt, Date(timeIntervalSince1970: 1_769_600_000))
    }

    func testCookieHeaderUsesEnvironmentOverride() {
        let env = [
            "ZENMUX_COOKIE_HEADER": "sessionId=sid; sessionId.sig=sig; ctoken=abc"
        ]
        XCTAssertEqual(
            ZenMuxCookieStore.cookieHeaderFromEnvironment(env),
            "sessionId=sid; sessionId.sig=sig; ctoken=abc"
        )
    }

    func testCookieHeaderBuildsFromSessionComponents() {
        let env = [
            "ZENMUX_SESSION_ID": "sid",
            "ZENMUX_SESSION_SIG": "sig",
            "ZENMUX_CTOKEN": "abc"
        ]
        XCTAssertEqual(
            ZenMuxCookieStore.cookieHeaderFromEnvironment(env),
            "sessionId=sid; sessionId.sig=sig; ctoken=abc"
        )
    }

    func testCookieHeaderFallsBackToBrowserImporter() {
        let store = ZenMuxCookieStore(browserImporter: StubBrowserImporter(header: "sessionId=sid; ctoken=abc"))
        let header = store.cookieHeader(for: URL(string: "https://zenmux.ai")!, environment: [:])
        XCTAssertEqual(header, "sessionId=sid; ctoken=abc")
    }

    func testCookieHeaderPrefersBrowserImporterOverRuntimeCookieStorage() {
        let runtimeCookies = [
            makeCookie(name: "sessionId", value: "runtime-session"),
            makeCookie(name: "ctoken", value: "runtime-token")
        ]
        let store = ZenMuxCookieStore(
            browserImporter: StubBrowserImporter(header: "sessionId=browser-session; sessionId.sig=browser-sig; ctoken=browser-token"),
            runtimeCookieSource: StubRuntimeCookieSource(cookies: runtimeCookies)
        )

        let header = store.cookieHeader(for: URL(string: "https://zenmux.ai")!, environment: [:])
        XCTAssertEqual(header, "sessionId=browser-session; sessionId.sig=browser-sig; ctoken=browser-token")
    }

    func testZenMuxBrowserCookieImporterUsesReusableCollector() throws {
        let collector = StubQuotaCookieCollector(result: .success("sessionId=sid; sessionId.sig=sig; ctoken=abc"))
        let importer = ZenMuxBrowserCookieImporter(collector: collector)
        let header = try importer.importCookieHeader()

        XCTAssertEqual(header, "sessionId=sid; sessionId.sig=sig; ctoken=abc")
        XCTAssertEqual(collector.lastConfig?.domains, ["zenmux.ai", ".zenmux.ai"])
        XCTAssertEqual(collector.lastConfig?.requiredCookieNames, Set(["sessionId", "sessionId.sig", "ctoken"]))
        XCTAssertEqual(collector.lastConfig?.preferredBrowsers, [.chrome, .safari, .firefox])
    }

    func testLiveProbeFetchesSnapshotWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["ZENMUX_LIVE_PROBE"] == "1" else {
            throw XCTSkip("Set ZENMUX_LIVE_PROBE=1 to run live probe")
        }

        let snapshot = try ZenMuxUsageClient().fetchSnapshot()
        XCTAssertEqual(snapshot.providerID, "zenmux")
        XCTAssertFalse(snapshot.windows.isEmpty)
    }

}

private struct StubBrowserImporter: ZenMuxBrowserCookieImporting {
    let header: String?

    func importCookieHeader() throws -> String? {
        header
    }
}

private struct StubRuntimeCookieSource: ZenMuxRuntimeCookieSourcing {
    let cookies: [HTTPCookie]

    func cookies(for url: URL) -> [HTTPCookie]? {
        cookies
    }
}

private func makeCookie(name: String, value: String) -> HTTPCookie {
    HTTPCookie(properties: [
        .name: name,
        .value: value,
        .domain: ".zenmux.ai",
        .path: "/",
        .secure: true
    ])!
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
