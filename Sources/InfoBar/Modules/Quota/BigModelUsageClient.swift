import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct BigModelUsageResponse: Decodable {
    let code: Int
    let msg: String?
    let success: Bool
    let data: DataEnvelope?

    struct DataEnvelope: Decodable {
        let limits: [Limit]
    }

    struct Limit: Decodable {
        let type: String
        let usage: Int?
        let currentValue: Int?
        let remaining: Int?
        let percentage: Double?
        let nextResetTime: Int?
    }
}

public enum BigModelUsageClientError: Error {
    case invalidResponse
    case missingCredentials
    case unauthorized
    case serverError(Int, String?)
    case apiFailure(String)
    case missingUsageData
}

struct BigModelUsageClient: QuotaSnapshotFetching {
    private let environment: [String: String]
    private let session: URLSession
    private let browserCookieImporter: BigModelBrowserCookieImporting

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        browserCookieImporter: BigModelBrowserCookieImporting = BigModelBrowserCookieImporter()
    ) {
        self.environment = environment
        self.session = session
        self.browserCookieImporter = browserCookieImporter
    }

    func fetchSnapshot() throws -> QuotaSnapshot {
        guard let cookieHeader = try browserCookieImporter.importCookieHeader(), !cookieHeader.isEmpty else {
            throw BigModelUsageClientError.missingCredentials
        }

        var request = URLRequest(url: resolveQuotaURL(environment: environment))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let token = Self.authorizationToken(fromCookieHeader: cookieHeader), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("InfoBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try perform(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw BigModelUsageClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let payload = try Self.decodeResponse(data: data)
            return try Self.mapToSnapshot(response: payload, fetchedAt: Date())
        case 401, 403:
            throw BigModelUsageClientError.unauthorized
        default:
            throw BigModelUsageClientError.serverError(http.statusCode, Self.preview(data: data))
        }
    }

    private func perform(request: URLRequest) throws -> (Data, URLResponse) {
        final class ResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Result<(Data, URLResponse), Error>?

            func set(_ newValue: Result<(Data, URLResponse), Error>) {
                lock.lock()
                value = newValue
                lock.unlock()
            }

            func get() -> Result<(Data, URLResponse), Error>? {
                lock.lock()
                let current = value
                lock.unlock()
                return current
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.set(.failure(error))
                return
            }
            guard let data, let response else {
                box.set(.failure(BigModelUsageClientError.invalidResponse))
                return
            }
            box.set(.success((data, response)))
        }.resume()

        semaphore.wait()
        guard let result = box.get() else {
            throw BigModelUsageClientError.invalidResponse
        }
        return try result.get()
    }

    static func decodeResponse(data: Data) throws -> BigModelUsageResponse {
        try JSONDecoder().decode(BigModelUsageResponse.self, from: data)
    }

    static func mapToSnapshot(response: BigModelUsageResponse, fetchedAt: Date) throws -> QuotaSnapshot {
        guard response.success, response.code == 200 else {
            throw BigModelUsageClientError.apiFailure(response.msg ?? "request failed")
        }

        let limits = response.data?.limits ?? []
        guard !limits.isEmpty else {
            throw BigModelUsageClientError.missingUsageData
        }

        var windows: [QuotaWindow] = []
        if let tokenLimit = limits.first(where: { $0.type == "TOKENS_LIMIT" }) {
            windows.append(QuotaWindow(
                id: "tokens_limit",
                label: "T",
                usedPercent: usedPercent(limit: tokenLimit),
                resetAt: resetAt(limit: tokenLimit, fetchedAt: fetchedAt)
            ))
        }
        if let timeLimit = limits.first(where: { $0.type == "TIME_LIMIT" }) {
            windows.append(QuotaWindow(
                id: "time_limit",
                label: "M",
                usedPercent: usedPercent(limit: timeLimit),
                resetAt: resetAt(limit: timeLimit, fetchedAt: fetchedAt)
            ))
        }

        guard !windows.isEmpty else {
            throw BigModelUsageClientError.missingUsageData
        }
        return QuotaSnapshot(providerID: "bigmodel", windows: windows, fetchedAt: fetchedAt)
    }

    private static func usedPercent(limit: BigModelUsageResponse.Limit) -> Int {
        if let usage = limit.usage, usage > 0 {
            if let remaining = limit.remaining {
                let used = max(0, min(usage, usage - remaining))
                return Int((Double(used) / Double(usage) * 100).rounded())
            }
            if let current = limit.currentValue {
                let used = max(0, min(usage, current))
                return Int((Double(used) / Double(usage) * 100).rounded())
            }
        }
        if let percentage = limit.percentage {
            return Int(percentage.rounded())
        }
        return 0
    }

    private static func resetAt(limit: BigModelUsageResponse.Limit, fetchedAt: Date) -> Date {
        guard let millis = limit.nextResetTime else { return fetchedAt }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    private func resolveQuotaURL(environment: [String: String]) -> URL {
        if let quotaURL = Self.cleaned(environment["Z_AI_QUOTA_URL"]),
           let resolved = Self.url(from: quotaURL, appendDefaultPath: false) {
            return resolved
        }
        if let host = Self.cleaned(environment["Z_AI_API_HOST"]),
           let resolved = Self.url(from: host, appendDefaultPath: true) {
            return resolved
        }
        return URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
    }

    private static func url(from raw: String, appendDefaultPath: Bool) -> URL? {
        if let direct = URL(string: raw), direct.scheme != nil {
            if appendDefaultPath, (direct.path.isEmpty || direct.path == "/") {
                return direct.appendingPathComponent("api/monitor/usage/quota/limit")
            }
            return direct
        }
        guard let https = URL(string: "https://\(raw)") else { return nil }
        if appendDefaultPath, (https.path.isEmpty || https.path == "/") {
            return https.appendingPathComponent("api/monitor/usage/quota/limit")
        }
        return https
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func preview(data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(240))
    }

    static func authorizationToken(fromCookieHeader header: String) -> String? {
        let candidates: Set<String> = [
            "authorization",
            "access_token",
            "access-token",
            "accesstoken",
            "token",
            "api_key",
            "apikey",
            "x_api_key",
            "x-api-key"
        ]

        for part in header.split(separator: ";") {
            let tokenPair = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tokenPair.isEmpty else { continue }
            let pieces = tokenPair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }

            let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matched = candidates.contains(key) || key.hasPrefix("bigmodel_token")
            guard matched else { continue }

            var value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.replacingOccurrences(of: "+", with: " ")
            let decoded = value.removingPercentEncoding ?? value
            let stripped = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "authorization" {
                if stripped.lowercased().hasPrefix("bearer ") {
                    let idx = stripped.index(stripped.startIndex, offsetBy: 7)
                    let bearer = stripped[idx...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return bearer.isEmpty ? nil : bearer
                }
            }
            return stripped.isEmpty ? nil : stripped
        }
        return nil
    }
}
