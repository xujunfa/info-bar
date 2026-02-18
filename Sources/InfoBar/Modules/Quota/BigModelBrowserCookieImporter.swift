import Foundation

protocol BigModelBrowserCookieImporting {
    func importCookieHeader() throws -> String?
}

struct BigModelBrowserCookieImporter: BigModelBrowserCookieImporting {
    private let collector: BrowserQuotaCookieCollecting

    init(collector: BrowserQuotaCookieCollecting = BrowserQuotaCookieCollector()) {
        self.collector = collector
    }

    func importCookieHeader() throws -> String? {
        try collector.collectHeader(config: BrowserQuotaCookieConfig(
            domains: ["open.bigmodel.cn", ".bigmodel.cn", "bigmodel.cn", "z.ai", ".z.ai", "api.z.ai"],
            requiredCookieNames: Set<String>(),
            preferredBrowsers: [.chrome, .safari, .firefox]
        ))
    }
}
