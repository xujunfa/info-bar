import XCTest
@testable import InfoBar

final class FactoryUsageClientTests: XCTestCase {
    func testFetchSnapshotReadsLatestFactoryUsageFromSupabase() throws {
        let expectation = XCTestExpectation(description: "request captured")
        URLProtocolStub.requestHandler = { request in
            expectation.fulfill()

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "test-anon-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-anon-key")

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(queryItems["provider"], "eq.factory")
            XCTAssertEqual(queryItems["event"], "eq.usage_snapshot")
            XCTAssertEqual(queryItems["connector"], "eq.info-bar-web-connector")
            XCTAssertEqual(queryItems["limit"], "1")

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            [{
              "connector":"info-bar-web-connector",
              "provider":"factory",
              "event":"usage_snapshot",
              "captured_at":"2026-03-01T11:27:45.029Z",
              "payload":{
                "usage":{
                  "endDate":1775026800000,
                  "standard":{
                    "totalAllowance":20000000,
                    "orgTotalTokensUsed":4000000
                  }
                }
              },
              "metadata":{"traceId":"trace-1","hook":"fetch","version":1}
            }]
            """
            return (response, Data(body.utf8))
        }

        let session = makeStubSession()
        let missingConfigPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("infobar-missing-\(UUID().uuidString).json")
            .path
        let client = FactoryUsageClient(
            environment: [
                "INFOBAR_CONFIG_FILE": missingConfigPath,
                "INFOBAR_SUPABASE_URL": "https://unit-test.supabase.co",
                "INFOBAR_SUPABASE_ANON_KEY": "test-anon-key"
            ],
            session: session
        )

        let snapshot = try client.fetchSnapshot()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(snapshot.providerID, "factory")
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
        XCTAssertEqual(snapshot.windows.first?.resetAt, Date(timeIntervalSince1970: 1_775_026_800))
        XCTAssertEqual(snapshot.windows.first?.used, 4_000_000)
        XCTAssertEqual(snapshot.windows.first?.limit, 20_000_000)
        XCTAssertEqual(snapshot.windows.first?.remaining, 16_000_000)
        XCTAssertEqual(snapshot.windows.first?.unit, "tokens")
        XCTAssertEqual(snapshot.windows.first?.windowTitle, "Monthly tokens")
        XCTAssertEqual(snapshot.windows.first?.metadata?["connector"], "info-bar-web-connector")
    }

    func testFetchSnapshotThrowsUnauthorizedWhenSupabaseRejects() {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        let session = makeStubSession()
        let missingConfigPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("infobar-missing-\(UUID().uuidString).json")
            .path
        let client = FactoryUsageClient(
            environment: [
                "INFOBAR_CONFIG_FILE": missingConfigPath,
                "INFOBAR_SUPABASE_URL": "https://unit-test.supabase.co",
                "INFOBAR_SUPABASE_ANON_KEY": "test-anon-key"
            ],
            session: session
        )

        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            guard case SupabaseConnectorClientError.unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        }
    }

    func testFetchSnapshotThrowsNoRecordsFoundWhenSupabaseReturnsEmptyList() {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("[]".utf8))
        }

        let client = makeFactoryClient(session: makeStubSession())
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            guard case SupabaseConnectorClientError.noRecordsFound = error else {
                XCTFail("Expected noRecordsFound, got \(error)")
                return
            }
        }
    }

    func testFetchSnapshotThrowsMissingUsageDataWhenPayloadFieldsMissing() {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            [{
              "connector":"info-bar-web-connector",
              "provider":"factory",
              "event":"usage_snapshot",
              "captured_at":"2026-03-01T11:27:45.029Z",
              "payload":{"foo":"bar"}
            }]
            """
            return (response, Data(body.utf8))
        }

        let client = makeFactoryClient(session: makeStubSession())
        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            guard case FactoryUsageClientError.missingUsageData = error else {
                XCTFail("Expected missingUsageData, got \(error)")
                return
            }
        }
    }

    func testFetchSnapshotSupportsStringFormattedUsageFields() throws {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            [{
              "connector":"info-bar-web-connector",
              "provider":"factory",
              "event":"usage_snapshot",
              "captured_at":"2026-03-01T11:27:45.029Z",
              "payload":{
                "usage":{
                  "endDate":"1775026800000",
                  "standard":{
                    "totalAllowance":"20,000,000",
                    "orgTotalTokensUsed":"4,500,000"
                  }
                },
                "window_title":" Factory Monthly Quota ",
                "token_unit":" tokens "
              }
            }]
            """
            return (response, Data(body.utf8))
        }

        let snapshot = try makeFactoryClient(session: makeStubSession()).fetchSnapshot()
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 23)
        XCTAssertEqual(snapshot.windows.first?.used, 4_500_000)
        XCTAssertEqual(snapshot.windows.first?.limit, 20_000_000)
        XCTAssertEqual(snapshot.windows.first?.remaining, 15_500_000)
        XCTAssertEqual(snapshot.windows.first?.windowTitle, "Factory Monthly Quota")
        XCTAssertEqual(snapshot.windows.first?.unit, "tokens")
    }

    func testFetchSnapshotReadsSupabaseConfigFromConfigFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("infobar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.local.json")
        let configJSON = """
        {
          "supabase": {
            "projectURL": "https://from-file.supabase.co",
            "anonKey": "from-file-anon-key",
            "table": "connector_events",
            "connectorID": "info-bar-web-connector"
          }
        }
        """
        try Data(configJSON.utf8).write(to: configURL)

        let expectation = XCTestExpectation(description: "request captured")
        URLProtocolStub.requestHandler = { request in
            expectation.fulfill()
            XCTAssertTrue(request.url?.absoluteString.contains("from-file.supabase.co") == true)
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "from-file-anon-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer from-file-anon-key")

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            [{
              "connector":"info-bar-web-connector",
              "provider":"factory",
              "event":"usage_snapshot",
              "captured_at":"2026-03-01T11:27:45.029Z",
              "payload":{"usage":{"standard":{"usedRatio":0.2},"endDate":1775026800000}}
            }]
            """
            return (response, Data(body.utf8))
        }

        let session = makeStubSession()
        let client = FactoryUsageClient(
            environment: [
                "INFOBAR_CONFIG_FILE": configURL.path
            ],
            session: session
        )

        let snapshot = try client.fetchSnapshot()
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
    }

    func testFetchSnapshotRejectsPlaceholderConfigValues() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("infobar-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.local.json")
        let configJSON = """
        {
          "supabase": {
            "projectURL": "https://your-project-ref.supabase.co",
            "anonKey": "sb_publishable_replace_me"
          }
        }
        """
        try Data(configJSON.utf8).write(to: configURL)

        let client = FactoryUsageClient(
            environment: [
                "INFOBAR_CONFIG_FILE": configURL.path
            ],
            session: makeStubSession()
        )

        XCTAssertThrowsError(try client.fetchSnapshot()) { error in
            guard case let SupabaseConnectorClientError.missingConfiguration(message) = error else {
                XCTFail("Expected missingConfiguration, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Missing Supabase URL"))
        }
    }

    func testMapToSnapshotUsesUsedRatioWhenAvailable() throws {
        let record = try decodeRecord(
            """
            {
              "connector":"info-bar-web-connector",
              "provider":"factory",
              "event":"usage_snapshot",
              "captured_at":"2026-03-01T11:27:45.029Z",
              "payload":{
                "usage":{
                  "endDate":1775026800000,
                  "standard":{"usedRatio":0.375}
                }
              }
            }
            """
        )

        let snapshot = try FactoryUsageClient.mapToSnapshot(
            record: record,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.providerID, "factory")
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 38)
        XCTAssertEqual(snapshot.windows.first?.resetAt, Date(timeIntervalSince1970: 1_775_026_800))
        XCTAssertEqual(snapshot.windows.first?.windowTitle, "Monthly tokens")
    }

    func testFactoryBrowserCookieImporterUsesReusableCollector() throws {
        let collector = StubQuotaCookieCollector(result: .success("session=abc"))
        let importer = FactoryBrowserCookieImporter(collector: collector)
        let header = try importer.importCookieHeader()

        XCTAssertEqual(header, "session=abc")
        XCTAssertEqual(
            collector.lastConfig?.domains,
            ["api.factory.ai", "factory.ai", ".factory.ai"]
        )
        XCTAssertEqual(collector.lastConfig?.requiredCookieNames, Set<String>())
        XCTAssertEqual(collector.lastConfig?.preferredBrowsers, [.chrome, .safari, .firefox])
    }

    private func decodeRecord(_ json: String) throws -> SupabaseConnectorEventRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabaseConnectorEventRecord.self, from: Data(json.utf8))
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeFactoryClient(session: URLSession) -> FactoryUsageClient {
        let missingConfigPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("infobar-missing-\(UUID().uuidString).json")
            .path
        return FactoryUsageClient(
            environment: [
                "INFOBAR_CONFIG_FILE": missingConfigPath,
                "INFOBAR_SUPABASE_URL": "https://unit-test.supabase.co",
                "INFOBAR_SUPABASE_ANON_KEY": "test-anon-key"
            ],
            session: session
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
