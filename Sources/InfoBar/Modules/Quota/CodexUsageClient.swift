import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexUsageResponse: Decodable {
    let rateLimit: RateLimitDetails?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case planType = "plan_type"
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
        let usedPercent: Double?
        let resetAt: Double?
        let limitWindowSeconds: Double?
        let used: Double?
        let limit: Double?
        let remaining: Double?
        let unit: String?
        let windowTitle: String?
        let periodType: String?

        private struct DynamicCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }

            init?(intValue: Int) {
                self.stringValue = "\(intValue)"
                self.intValue = intValue
            }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            self.usedPercent = Self.decodeNumber(
                in: container,
                keys: ["used_percent", "usedPercent", "usage_percent", "percent"]
            )
            self.resetAt = Self.decodeNumber(
                in: container,
                keys: ["reset_at", "resetAt", "next_reset_at", "nextResetAt", "window_end", "windowEnd"]
            )
            self.limitWindowSeconds = Self.decodeNumber(
                in: container,
                keys: ["limit_window_seconds", "window_seconds", "windowSeconds", "window_duration_seconds"]
            )
            self.used = Self.decodeNumber(
                in: container,
                keys: ["used", "usage", "used_count", "usedCount", "current_usage", "currentUsage"]
            )
            self.limit = Self.decodeNumber(
                in: container,
                keys: ["limit", "total", "quota", "total_quota", "totalQuota"]
            )
            self.remaining = Self.decodeNumber(
                in: container,
                keys: ["remaining", "remaining_quota", "remainingQuota", "left", "left_count", "leftCount"]
            )
            self.unit = Self.decodeString(in: container, keys: ["unit"])
            self.windowTitle = Self.decodeString(
                in: container,
                keys: ["window_title", "windowTitle", "title", "name"]
            )
            self.periodType = Self.decodeString(
                in: container,
                keys: ["period_type", "periodType", "id", "type"]
            )
        }

        private static func decodeNumber(
            in container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]
        ) -> Double? {
            for key in keys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                if let number = try? container.decode(Double.self, forKey: codingKey), number.isFinite {
                    return number
                }
                if let intValue = try? container.decode(Int.self, forKey: codingKey) {
                    return Double(intValue)
                }
                if let stringValue = try? container.decode(String.self, forKey: codingKey) {
                    let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let parsed = Double(trimmed), parsed.isFinite {
                        return parsed
                    }
                }
            }
            return nil
        }

        private static func decodeString(
            in container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]
        ) -> String? {
            for key in keys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                guard let value = try? container.decode(String.self, forKey: codingKey) else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return nil
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
        guard let primary = response.rateLimit?.primaryWindow,
              let primaryWindow = mapWindow(
                primary,
                id: "five_hour",
                label: "H",
                defaultTitle: "5-hour usage",
                fallbackDurationSeconds: 5 * 3_600,
                planType: response.planType,
                fetchedAt: fetchedAt
              ) else {
            throw CodexUsageClientError.missingPrimaryWindow
        }

        var windows: [QuotaWindow] = [primaryWindow]

        if let weeklyWindow = response.rateLimit?.secondaryWindow {
            if let mappedWeekly = mapWindow(
                weeklyWindow,
                id: "weekly",
                label: "W",
                defaultTitle: "Weekly usage",
                fallbackDurationSeconds: 7 * 24 * 3_600,
                planType: response.planType,
                fetchedAt: fetchedAt
            ) {
                windows.append(mappedWeekly)
            }
        }

        return QuotaSnapshot(providerID: "codex", windows: windows, fetchedAt: fetchedAt)
    }

    private static func mapWindow(
        _ source: CodexUsageResponse.WindowSnapshot,
        id: String,
        label: String,
        defaultTitle: String,
        fallbackDurationSeconds: Double,
        planType: String?,
        fetchedAt: Date
    ) -> QuotaWindow? {
        let normalizedLimit = positiveNumber(source.limit) ?? combinedLimit(used: source.used, remaining: source.remaining)
        let normalizedUsed = positiveNumber(source.used) ?? inferredUsed(limit: normalizedLimit, remaining: source.remaining)
        let normalizedRemaining = positiveNumber(source.remaining)
        let usedPercent = usedPercent(
            explicitPercent: source.usedPercent,
            used: normalizedUsed,
            limit: normalizedLimit,
            remaining: normalizedRemaining
        )

        guard let usedPercent else {
            return nil
        }

        var metadata: [String: String] = [:]
        if let seconds = positiveNumber(source.limitWindowSeconds) {
            metadata["window_seconds"] = String(Int(seconds.rounded()))
        }
        if let planType = normalizedText(planType) {
            metadata["plan_type"] = planType
        }
        if let periodType = normalizedText(source.periodType) {
            metadata["period_type"] = periodType
        }

        return QuotaWindow(
            id: id,
            label: label,
            usedPercent: usedPercent,
            resetAt: resolveResetAt(
                explicitResetAt: source.resetAt,
                fallbackDurationSeconds: source.limitWindowSeconds ?? fallbackDurationSeconds,
                fetchedAt: fetchedAt
            ),
            used: normalizedUsed,
            limit: normalizedLimit,
            remaining: normalizedRemaining,
            unit: normalizedText(source.unit),
            windowTitle: source.windowTitle ?? defaultTitle,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    private static func positiveNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private static func combinedLimit(used: Double?, remaining: Double?) -> Double? {
        guard let used = positiveNumber(used), let remaining = positiveNumber(remaining) else { return nil }
        return used + remaining
    }

    private static func inferredUsed(limit: Double?, remaining: Double?) -> Double? {
        guard let limit = positiveNumber(limit), let remaining = positiveNumber(remaining) else { return nil }
        return max(0, limit - remaining)
    }

    private static func usedPercent(
        explicitPercent: Double?,
        used: Double?,
        limit: Double?,
        remaining: Double?
    ) -> Int? {
        if let explicit = positiveNumber(explicitPercent) {
            return Int(explicit.rounded())
        }
        if let limit = positiveNumber(limit), limit > 0 {
            if let used = positiveNumber(used) {
                return Int((min(used, limit) / limit * 100).rounded())
            }
            if let remaining = positiveNumber(remaining) {
                return Int(((max(0, limit - remaining)) / limit * 100).rounded())
            }
        }
        if let used = positiveNumber(used), let remaining = positiveNumber(remaining) {
            let total = used + remaining
            guard total > 0 else { return nil }
            return Int((used / total * 100).rounded())
        }
        return nil
    }

    private static func resolveResetAt(
        explicitResetAt: Double?,
        fallbackDurationSeconds: Double?,
        fetchedAt: Date
    ) -> Date {
        if let explicitResetAt = positiveNumber(explicitResetAt), explicitResetAt > 0 {
            let seconds = explicitResetAt > 1_000_000_000_000 ? explicitResetAt / 1000 : explicitResetAt
            return Date(timeIntervalSince1970: seconds)
        }
        if let fallbackDurationSeconds = positiveNumber(fallbackDurationSeconds), fallbackDurationSeconds > 0 {
            return fetchedAt.addingTimeInterval(fallbackDurationSeconds)
        }
        return fetchedAt
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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
