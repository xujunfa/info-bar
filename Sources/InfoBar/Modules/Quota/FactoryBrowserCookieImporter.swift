import Foundation

protocol FactoryBrowserCookieImporting {
    func importCookieHeader() throws -> String?
}

struct FactoryBrowserCookieImporter: FactoryBrowserCookieImporting {
    private let collector: BrowserQuotaCookieCollecting

    init(collector: BrowserQuotaCookieCollecting = BrowserQuotaCookieCollector()) {
        self.collector = collector
    }

    func importCookieHeader() throws -> String? {
        try collector.collectHeader(config: BrowserQuotaCookieConfig(
            domains: ["api.factory.ai", "factory.ai", ".factory.ai"],
            requiredCookieNames: Set<String>(),
            preferredBrowsers: [.chrome, .safari, .firefox]
        ))
    }
}
