import Foundation

protocol MiniMaxBrowserCookieImporting {
    func importCookieHeader() throws -> String?
}

struct MiniMaxBrowserCookieImporter: MiniMaxBrowserCookieImporting {
    private let collector: BrowserQuotaCookieCollecting

    init(collector: BrowserQuotaCookieCollecting = BrowserQuotaCookieCollector()) {
        self.collector = collector
    }

    func importCookieHeader() throws -> String? {
        try collector.collectHeader(config: BrowserQuotaCookieConfig(
            domains: ["www.minimaxi.com", ".minimaxi.com", "minimaxi.com"],
            requiredCookieNames: Set<String>(),
            preferredBrowsers: [.chrome, .safari, .firefox]
        ))
    }
}
