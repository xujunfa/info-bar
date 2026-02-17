import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ZenMuxJSONValue: Decodable {
    case object([String: ZenMuxJSONValue])
    case array([ZenMuxJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let object = try? container.decode([String: ZenMuxJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([ZenMuxJSONValue].self) {
            self = .array(array)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported value")
        }
    }
}

struct ZenMuxUsageResponse: Decodable {
    let success: Bool
    let message: String?
    let data: ZenMuxJSONValue?
}

public enum ZenMuxUsageClientError: Error {
    case invalidResponse
    case unauthorized
    case serverError(Int, String?)
    case apiFailure(String)
    case missingUsageData(String?)
}

protocol ZenMuxCookieProviding {
    func cookieHeader(for url: URL, environment: [String: String]) -> String?
}

protocol ZenMuxBrowserCookieImporting {
    func importCookieHeader() throws -> String?
}

protocol ZenMuxRuntimeCookieSourcing {
    func cookies(for url: URL) -> [HTTPCookie]?
}

struct ZenMuxRuntimeCookieSource: ZenMuxRuntimeCookieSourcing {
    func cookies(for url: URL) -> [HTTPCookie]? {
        HTTPCookieStorage.shared.cookies(for: url)
    }
}

struct ZenMuxCookieStore: ZenMuxCookieProviding {
    private let browserImporter: ZenMuxBrowserCookieImporting
    private let runtimeCookieSource: ZenMuxRuntimeCookieSourcing

    init(
        browserImporter: ZenMuxBrowserCookieImporting = ZenMuxBrowserCookieImporter(),
        runtimeCookieSource: ZenMuxRuntimeCookieSourcing = ZenMuxRuntimeCookieSource()
    ) {
        self.browserImporter = browserImporter
        self.runtimeCookieSource = runtimeCookieSource
    }

    func cookieHeader(for url: URL, environment: [String: String]) -> String? {
        if let fromEnvironment = Self.cookieHeaderFromEnvironment(environment) {
            return fromEnvironment
        }

        if let fromBrowser = try? browserImporter.importCookieHeader(), !fromBrowser.isEmpty {
            return fromBrowser
        }

        if let cookies = runtimeCookieSource.cookies(for: url), !cookies.isEmpty {
            let value = cookies
                .filter { $0.domain.contains("zenmux.ai") }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            if !value.isEmpty {
                return value
            }
        }
        
        return nil
    }

    static func cookieHeaderFromEnvironment(_ environment: [String: String]) -> String? {
        if let raw = environment["ZENMUX_COOKIE_HEADER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        let sessionID = environment["ZENMUX_SESSION_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionSig = environment["ZENMUX_SESSION_SIG"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ctoken = environment["ZENMUX_CTOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sessionID, !sessionID.isEmpty else {
            return nil
        }

        var parts = ["sessionId=\(sessionID)"]
        if let sessionSig, !sessionSig.isEmpty {
            parts.append("sessionId.sig=\(sessionSig)")
        }
        if let ctoken, !ctoken.isEmpty {
            parts.append("ctoken=\(ctoken)")
        }
        return parts.joined(separator: "; ")
    }

}

struct ZenMuxUsageClient: QuotaSnapshotFetching {
    private let environment: [String: String]
    private let session: URLSession
    private let cookieStore: ZenMuxCookieProviding

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        cookieStore: ZenMuxCookieProviding = ZenMuxCookieStore()
    ) {
        self.environment = environment
        self.session = session
        self.cookieStore = cookieStore
    }

    func fetchSnapshot() throws -> QuotaSnapshot {
        var components = URLComponents(string: "https://zenmux.ai/api/subscription/get_current_usage")!
        let ctoken = environment["ZENMUX_CTOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: "ctoken", value: (ctoken?.isEmpty == false) ? ctoken : "nUjM0oIo9ETlz4qh7IZipt0U")
        ]
        guard let url = components.url else { throw ZenMuxUsageClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("InfoBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookieHeader = cookieStore.cookieHeader(for: url, environment: environment), !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try perform(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZenMuxUsageClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            do {
                let payload = try Self.decodeResponse(data: data)
                return try Self.mapToSnapshot(response: payload, fetchedAt: Date())
            } catch {
                Self.log("map/decode failed: \(error). body=\(Self.preview(data: data))")
                throw error
            }
        case 401, 403:
            Self.log("unauthorized status=\(http.statusCode). body=\(Self.preview(data: data))")
            throw ZenMuxUsageClientError.unauthorized
        default:
            let preview = Self.preview(data: data)
            Self.log("server error status=\(http.statusCode). body=\(preview)")
            throw ZenMuxUsageClientError.serverError(http.statusCode, preview)
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
                box.set(.failure(ZenMuxUsageClientError.invalidResponse))
                return
            }
            box.set(.success((data, response)))
        }.resume()

        semaphore.wait()
        guard let result = box.get() else { throw ZenMuxUsageClientError.invalidResponse }
        return try result.get()
    }

    static func decodeResponse(data: Data) throws -> ZenMuxUsageResponse {
        try JSONDecoder().decode(ZenMuxUsageResponse.self, from: data)
    }

    static func mapToSnapshot(response: ZenMuxUsageResponse, fetchedAt: Date) throws -> QuotaSnapshot {
        guard response.success else {
            throw ZenMuxUsageClientError.apiFailure(response.message ?? "request failed")
        }
        guard let data = response.data else {
            throw ZenMuxUsageClientError.missingUsageData(nil)
        }

        var windows = parseWindows(from: data)
        if windows.isEmpty, let object = object(from: data), let window = parsePrimaryWindow(from: object) {
            windows = [window]
            if let weekly = parseWeeklyWindow(from: object) {
                windows.append(weekly)
            }
        }
        guard !windows.isEmpty else {
            throw ZenMuxUsageClientError.missingUsageData(rawJSONString(from: data))
        }

        return QuotaSnapshot(providerID: "zenmux", windows: windows, fetchedAt: fetchedAt)
    }

    private static func parseWindows(from value: ZenMuxJSONValue) -> [QuotaWindow] {
        if let topLevelArray = array(from: value) {
            let windows = topLevelArray.compactMap(parseWindowEntry)
            return sortWindows(windows)
        }

        guard let root = object(from: value),
              let array = array(from: root["windows"]) else {
            return []
        }

        let windows = array.compactMap(parseWindowEntry)
        return sortWindows(windows)
    }

    private static func parseWindowEntry(from value: ZenMuxJSONValue) -> QuotaWindow? {
        guard let windowObject = object(from: value) else { return nil }
        let periodType = string(from: windowObject, keys: ["periodType", "period_type", "id", "type"]) ?? "window"
        let usedPercent = int(from: windowObject, keys: ["used_percent", "usedPercent", "usage_percent", "usageRate", "usage_rate"])
            ?? intPercentFromRate(from: windowObject, keys: ["usedRate", "used_rate", "usageRate", "usage_rate"])
        guard let usedPercent,
              let resetAt = date(
                from: windowObject,
                keys: ["reset_at", "resetAt", "period_end", "periodEnd", "next_reset_at", "cycleEndTime", "cycle_end_time"]
              ) else {
            return nil
        }

        let label = string(from: windowObject, keys: ["label"]) ?? label(for: periodType)
        return QuotaWindow(id: periodType, label: label, usedPercent: usedPercent, resetAt: resetAt)
    }

    private static func sortWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        windows.sorted { lhs, rhs in
            priority(for: lhs.id) < priority(for: rhs.id)
        }
    }

    private static func priority(for periodType: String) -> Int {
        switch periodType.lowercased() {
        case "hour_5", "five_hour", "5h", "hour":
            return 0
        case "day", "daily":
            return 1
        case "week", "weekly":
            return 2
        case "month", "monthly":
            return 3
        default:
            return 9
        }
    }

    private static func label(for periodType: String) -> String {
        switch periodType.lowercased() {
        case "hour_5", "five_hour", "5h", "hour":
            return "H"
        case "day", "daily":
            return "D"
        case "week", "weekly":
            return "W"
        case "month", "monthly":
            return "M"
        default:
            return String(periodType.prefix(1)).uppercased()
        }
    }

    private static func parsePrimaryWindow(from object: [String: ZenMuxJSONValue]) -> QuotaWindow? {
        guard let used = int(from: object, keys: ["usage_percent", "used_percent", "usageRate", "usage_rate", "usedRate"]),
              let resetAt = date(from: object, keys: ["reset_at", "resetAt", "period_end", "periodEnd", "next_reset_at"]) else {
            return nil
        }
        return QuotaWindow(id: "monthly", label: "M", usedPercent: used, resetAt: resetAt)
    }

    private static func parseWeeklyWindow(from object: [String: ZenMuxJSONValue]) -> QuotaWindow? {
        guard let used = int(from: object, keys: ["weekly_usage_percent", "weekly_used_percent", "weeklyUsagePercent"]),
              let resetAt = date(from: object, keys: ["weekly_reset_at", "weeklyResetAt"]) else {
            return nil
        }
        return QuotaWindow(id: "weekly", label: "W", usedPercent: used, resetAt: resetAt)
    }

    private static func object(from value: ZenMuxJSONValue?) -> [String: ZenMuxJSONValue]? {
        guard case let .object(object)? = value else { return nil }
        return object
    }

    private static func array(from value: ZenMuxJSONValue?) -> [ZenMuxJSONValue]? {
        guard case let .array(array)? = value else { return nil }
        return array
    }

    private static func string(from object: [String: ZenMuxJSONValue], keys: [String]) -> String? {
        for key in keys {
            if case let .string(value)? = object[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func int(from object: [String: ZenMuxJSONValue], keys: [String]) -> Int? {
        for key in keys {
            if case let .number(value)? = object[key] {
                return Int(value.rounded())
            }
            if case let .string(value)? = object[key], let number = Double(value) {
                return Int(number.rounded())
            }
        }
        return nil
    }

    private static func intPercentFromRate(from object: [String: ZenMuxJSONValue], keys: [String]) -> Int? {
        for key in keys {
            if case let .number(value)? = object[key] {
                return Int((value * 100).rounded())
            }
            if case let .string(value)? = object[key], let number = Double(value) {
                return Int((number * 100).rounded())
            }
        }
        return nil
    }

    private static func date(from object: [String: ZenMuxJSONValue], keys: [String]) -> Date? {
        for key in keys {
            if case let .number(value)? = object[key] {
                return normalizeDate(from: value)
            }
            if case let .string(value)? = object[key] {
                if let number = Double(value) {
                    return normalizeDate(from: number)
                }
                if let date = parseISO8601Date(value) {
                    return date
                }
            }
        }
        return nil
    }

    private static func normalizeDate(from number: Double) -> Date {
        let seconds = number > 10_000_000_000 ? number / 1000 : number
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f1.date(from: value) {
            return date
        }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: value)
    }

    private static func rawJSONString(from value: ZenMuxJSONValue) -> String? {
        guard let object = encodeJSONObject(value) else { return nil }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(text.prefix(400))
    }

    private static func encodeJSONObject(_ value: ZenMuxJSONValue) -> Any? {
        switch value {
        case let .object(dict):
            return dict.mapValues { encodeJSONObject($0) as Any }
        case let .array(array):
            return array.map { encodeJSONObject($0) as Any }
        case let .string(text):
            return text
        case let .number(number):
            return number
        case let .bool(flag):
            return flag
        case .null:
            return NSNull()
        }
    }

    private static func preview(data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        return String(text.prefix(400))
    }

    private static func log(_ message: String) {
        fputs("[ZenMuxUsageClient] \(message)\n", stderr)
    }
}
