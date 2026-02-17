import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexUsageResponse: Decodable {
    let rateLimit: RateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimitDetails: Decodable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable {
        let usedPercent: Int
        let resetAt: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }
}

public enum CodexUsageClientError: Error {
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case missingPrimaryWindow
}

public protocol QuotaSnapshotFetching {
    func fetchSnapshot() throws -> QuotaSnapshot
}

public struct CodexUsageClient: QuotaSnapshotFetching {
    private let environment: [String: String]
    private let session: URLSession

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) {
        self.environment = environment
        self.session = session
    }

    public func fetchSnapshot() throws -> QuotaSnapshot {
        let credentials = try CodexAuthStore.load(environment: environment)
        var request = URLRequest(url: Self.resolveUsageURL(environment: environment))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("InfoBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try perform(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexUsageClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let payload = try Self.decodeResponse(data: data)
            return try Self.mapToSnapshot(response: payload, fetchedAt: Date())
        case 401, 403:
            throw CodexUsageClientError.unauthorized
        default:
            throw CodexUsageClientError.serverError(http.statusCode)
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
                box.set(.failure(CodexUsageClientError.invalidResponse))
                return
            }
            box.set(.success((data, response)))
        }.resume()

        semaphore.wait()
        guard let result = box.get() else { throw CodexUsageClientError.invalidResponse }
        return try result.get()
    }

    static func decodeResponse(data: Data) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }

    static func mapToSnapshot(response: CodexUsageResponse, fetchedAt: Date) throws -> QuotaSnapshot {
        guard let window = response.rateLimit?.primaryWindow else {
            throw CodexUsageClientError.missingPrimaryWindow
        }

        var windows: [QuotaWindow] = [
            QuotaWindow(
                id: "five_hour",
                label: "H",
                usedPercent: window.usedPercent,
                resetAt: Date(timeIntervalSince1970: TimeInterval(window.resetAt))
            )
        ]

        if let weeklyWindow = response.rateLimit?.secondaryWindow {
            windows.append(QuotaWindow(
                id: "weekly",
                label: "W",
                usedPercent: weeklyWindow.usedPercent,
                resetAt: Date(timeIntervalSince1970: TimeInterval(weeklyWindow.resetAt))
            ))
        }

        return QuotaSnapshot(providerID: "codex", windows: windows, fetchedAt: fetchedAt)
    }

    private static func resolveUsageURL(environment: [String: String]) -> URL {
        let defaultURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (codexHome?.isEmpty == false) ? URL(fileURLWithPath: codexHome!) : home
            .appendingPathComponent(".codex")
        let configURL = root.appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
              let parsed = parseChatGPTBaseURL(from: contents) else {
            return defaultURL
        }

        let normalized = normalize(baseURL: parsed)
        let suffix = normalized.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"
        return URL(string: normalized + suffix) ?? defaultURL
    }

    private static func parseChatGPTBaseURL(from config: String) -> String? {
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "chatgpt_base_url" else { continue }

            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func normalize(baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "https://chatgpt.com/backend-api"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if (trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com")) &&
            !trimmed.contains("/backend-api") {
            trimmed += "/backend-api"
        }
        return trimmed
    }
}
