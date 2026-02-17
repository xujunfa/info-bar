import Foundation

struct ZenMuxBrowserCookieImporter: ZenMuxBrowserCookieImporting {
    private let collector: BrowserQuotaCookieCollecting

    init(collector: BrowserQuotaCookieCollecting = BrowserQuotaCookieCollector()) {
        self.collector = collector
    }

    func importCookieHeader() throws -> String? {
        try collector.collectHeader(config: BrowserQuotaCookieConfig(
            domains: ["zenmux.ai", ".zenmux.ai"],
            requiredCookieNames: Set(["sessionId", "sessionId.sig", "ctoken"]),
            preferredBrowsers: [.chrome, .safari, .firefox]
        ))
    }
}
