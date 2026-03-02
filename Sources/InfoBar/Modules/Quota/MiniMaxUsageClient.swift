import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MiniMaxUsageResponse: Decodable {
    let baseResp: BaseResponse?
    let modelRemains: [ModelRemain]?

    enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case modelRemains = "model_remains"
    }

    struct BaseResponse: Decodable {
        let statusCode: Int?
        let statusMessage: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMessage = "status_msg"
        }
    }

    struct ModelRemain: Decodable {
        let modelName: String?
        let currentIntervalTotalCount: Double?
        let currentIntervalUsageCount: Double?
        let currentIntervalUsedCount: Double?
        let currentIntervalRemainingCount: Double?
        let remainsTimeMS: Double?
        let resetAt: Double?
        let periodType: String?
        let quotaUnit: String?

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
            self.modelName = Self.decodeString(in: container, keys: ["model_name", "modelName", "name"])
            self.currentIntervalTotalCount = Self.decodeNumber(
                in: container,
                keys: ["current_interval_total_count", "currentIntervalTotalCount", "interval_total_count"]
            )
            self.currentIntervalUsageCount = Self.decodeNumber(
                in: container,
                keys: ["current_interval_usage_count", "currentIntervalUsageCount", "interval_usage_count"]
            )
            self.currentIntervalUsedCount = Self.decodeNumber(
                in: container,
                keys: ["current_interval_used_count", "currentIntervalUsedCount", "used_count", "usedCount"]
            )
            self.currentIntervalRemainingCount = Self.decodeNumber(
                in: container,
                keys: ["current_interval_remaining_count", "currentIntervalRemainingCount", "remaining_count", "remainingCount"]
            )
            self.remainsTimeMS = Self.decodeNumber(
                in: container,
                keys: ["remains_time", "remainsTime", "remain_ms", "remaining_time_ms"]
            )
            self.resetAt = Self.decodeNumber(
                in: container,
                keys: ["reset_at", "resetAt", "next_reset_at", "nextResetAt", "window_end", "windowEnd"]
            )
            self.periodType = Self.decodeString(
                in: container,
                keys: ["period_type", "periodType", "interval", "window"]
            )
            self.quotaUnit = Self.decodeString(
                in: container,
                keys: ["quota_unit", "quotaUnit", "unit"]
            )
        }

        private static func decodeNumber(
            in container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]
        ) -> Double? {
            for key in keys {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                if let value = try? container.decode(Double.self, forKey: codingKey), value.isFinite {
                    return value
                }
                if let value = try? container.decode(Int.self, forKey: codingKey) {
                    return Double(value)
                }
                if let value = try? container.decode(String.self, forKey: codingKey) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

public enum MiniMaxUsageClientError: Error {
    case invalidResponse
    case unauthorized
    case serverError(Int, String?)
    case apiFailure(String)
    case missingUsageData
}

struct MiniMaxUsageClient: QuotaSnapshotFetching {
    private let environment: [String: String]
    private let session: URLSession
    private let browserCookieImporter: MiniMaxBrowserCookieImporting

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        browserCookieImporter: MiniMaxBrowserCookieImporting = MiniMaxBrowserCookieImporter()
    ) {
        self.environment = environment
        self.session = session
        self.browserCookieImporter = browserCookieImporter
    }

    func fetchSnapshot() throws -> QuotaSnapshot {
        let groupID = resolveGroupID(environment: environment)
        var components = URLComponents(string: resolveUsageURL(environment: environment))!
        components.queryItems = [URLQueryItem(name: "groupId", value: groupID)]

        guard let url = components.url else {
            throw MiniMaxUsageClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("InfoBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookieHeader = try browserCookieImporter.importCookieHeader(), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try perform(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw MiniMaxUsageClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let payload = try Self.decodeResponse(data: data)
            return try Self.mapToSnapshot(response: payload, fetchedAt: Date())
        case 401, 403:
            throw MiniMaxUsageClientError.unauthorized
        default:
            throw MiniMaxUsageClientError.serverError(http.statusCode, Self.preview(data: data))
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
                box.set(.failure(MiniMaxUsageClientError.invalidResponse))
                return
            }
            box.set(.success((data, response)))
        }.resume()

        semaphore.wait()
        guard let result = box.get() else {
            throw MiniMaxUsageClientError.invalidResponse
        }
        return try result.get()
    }

    static func decodeResponse(data: Data) throws -> MiniMaxUsageResponse {
        try JSONDecoder().decode(MiniMaxUsageResponse.self, from: data)
    }

    static func mapToSnapshot(response: MiniMaxUsageResponse, fetchedAt: Date) throws -> QuotaSnapshot {
        if let status = response.baseResp?.statusCode, status != 0 {
            throw MiniMaxUsageClientError.apiFailure(response.baseResp?.statusMessage ?? "request failed")
        }

        guard let model = response.modelRemains?.first(where: {
            if let total = positiveNumber($0.currentIntervalTotalCount), total > 0 {
                return true
            }
            return false
        }) else {
            throw MiniMaxUsageClientError.missingUsageData
        }

        guard let limit = positiveNumber(model.currentIntervalTotalCount), limit > 0 else {
            throw MiniMaxUsageClientError.missingUsageData
        }

        let explicitUsed = clamped(model.currentIntervalUsedCount, limit: limit)
        let explicitRemaining = clamped(model.currentIntervalRemainingCount, limit: limit)
        let legacyRemaining = clamped(model.currentIntervalUsageCount, limit: limit)

        let used: Double
        let remaining: Double
        if let explicitRemaining {
            remaining = explicitRemaining
            used = max(0, limit - explicitRemaining)
        } else if let explicitUsed {
            used = explicitUsed
            remaining = max(0, limit - explicitUsed)
        } else if let legacyRemaining {
            // Legacy payloads expose `current_interval_usage_count` as remaining count.
            remaining = legacyRemaining
            used = max(0, limit - legacyRemaining)
        } else {
            throw MiniMaxUsageClientError.missingUsageData
        }

        let usedPercent = Int((used / limit * 100).rounded())
        let resetAt = resolveResetAt(model: model, fetchedAt: fetchedAt)
        let (windowID, label) = windowIdentity(periodType: model.periodType)

        var metadata: [String: String] = [:]
        if let modelName = normalizedText(model.modelName) {
            metadata["model_name"] = modelName
        }
        if let periodType = normalizedText(model.periodType) {
            metadata["period_type"] = periodType
        }
        if let remainsTimeMS = positiveNumber(model.remainsTimeMS) {
            metadata["remains_time_ms"] = String(Int(remainsTimeMS.rounded()))
        }

        let windowTitle = title(for: model.periodType) ?? "Current interval"

        let window = QuotaWindow(
            id: windowID,
            label: label,
            usedPercent: usedPercent,
            resetAt: resetAt,
            used: used,
            limit: limit,
            remaining: remaining,
            unit: normalizedText(model.quotaUnit) ?? "requests",
            windowTitle: windowTitle,
            metadata: metadata.isEmpty ? nil : metadata
        )
        return QuotaSnapshot(providerID: "minimax", windows: [window], fetchedAt: fetchedAt)
    }

    private static func positiveNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private static func clamped(_ value: Double?, limit: Double) -> Double? {
        guard let value = positiveNumber(value) else { return nil }
        return min(value, limit)
    }

    private static func resolveResetAt(model: MiniMaxUsageResponse.ModelRemain, fetchedAt: Date) -> Date {
        if let raw = positiveNumber(model.resetAt), raw > 0 {
            return normalizeDate(raw)
        }
        if let remainsMS = positiveNumber(model.remainsTimeMS), remainsMS > 0 {
            return fetchedAt.addingTimeInterval(remainsMS / 1000)
        }
        return fetchedAt
    }

    private static func normalizeDate(_ raw: Double) -> Date {
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    private static func windowIdentity(periodType: String?) -> (String, String) {
        let normalized = periodType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "hour_5", "five_hour", "5h", "hour":
            return ("hour_5", "H")
        case "day", "daily":
            return ("day", "D")
        case "week", "weekly":
            return ("week", "W")
        case "month", "monthly":
            return ("month", "M")
        case "":
            return ("hour_5", "H")
        default:
            return (normalized, String(normalized.prefix(1)).uppercased())
        }
    }

    private static func title(for periodType: String?) -> String? {
        let normalized = periodType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalized {
        case "hour_5", "five_hour", "5h", "hour":
            return "5-hour usage"
        case "day", "daily":
            return "Daily usage"
        case "week", "weekly":
            return "Weekly usage"
        case "month", "monthly":
            return "Monthly usage"
        default:
            return nil
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func resolveUsageURL(environment: [String: String]) -> String {
        if let raw = environment["MINIMAX_USAGE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return "https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains"
    }

    private func resolveGroupID(environment: [String: String]) -> String {
        if let raw = environment["MINIMAX_GROUP_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return "2015339786063057444"
    }

    private static func preview(data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(240))
    }
}
