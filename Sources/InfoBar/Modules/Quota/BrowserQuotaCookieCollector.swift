import Foundation

enum BrowserQuotaBrowser: Equatable {
    case chrome
    case safari
    case firefox
}

struct BrowserQuotaCookieConfig: Equatable {
    let domains: [String]
    let requiredCookieNames: Set<String>
    let preferredBrowsers: [BrowserQuotaBrowser]
}

protocol BrowserQuotaCookieCollecting {
    func collectHeader(config: BrowserQuotaCookieConfig) throws -> String?
}

#if os(macOS)
import SweetCookieKit

struct BrowserQuotaCookieCollector: BrowserQuotaCookieCollecting {
    private static let client = BrowserCookieClient()

    func collectHeader(config: BrowserQuotaCookieConfig) throws -> String? {
        guard !config.domains.isEmpty else { return nil }
        let query = BrowserCookieQuery(domains: config.domains)

        for browser in config.preferredBrowsers {
            guard let mapped = map(browser) else { continue }
            let sources = try? Self.client.records(matching: query, in: mapped)
            guard let sources else { continue }

            for source in sources where !source.records.isEmpty {
                let cookies = BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin)
                if let header = buildHeader(cookies: cookies, requiredNames: config.requiredCookieNames) {
                    return header
                }
            }
        }
        return nil
    }

    private func map(_ browser: BrowserQuotaBrowser) -> Browser? {
        switch browser {
        case .chrome: .chrome
        case .safari: .safari
        case .firefox: .firefox
        }
    }

    private func buildHeader(cookies: [HTTPCookie], requiredNames: Set<String>) -> String? {
        guard !cookies.isEmpty else { return nil }

        let entries = cookies
            .filter { requiredNames.isEmpty || requiredNames.contains($0.name) }
            .map { "\($0.name)=\($0.value)" }

        guard !entries.isEmpty else { return nil }
        return entries.joined(separator: "; ")
    }
}
#else
struct BrowserQuotaCookieCollector: BrowserQuotaCookieCollecting {
    func collectHeader(config: BrowserQuotaCookieConfig) throws -> String? {
        nil
    }
}
#endif
