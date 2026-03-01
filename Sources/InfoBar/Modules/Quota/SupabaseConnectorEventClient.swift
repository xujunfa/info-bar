import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ConnectorJSONValue: Decodable {
    case object([String: ConnectorJSONValue])
    case array([ConnectorJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let object = try? container.decode([String: ConnectorJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([ConnectorJSONValue].self) {
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
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported connector JSON value")
        }
    }
}

struct SupabaseConnectorEventRecord: Decodable {
    let connector: String
    let provider: String
    let event: String
    let dedupeKey: String?
    let capturedAt: Date?
    let receivedAt: Date?
    let pageURL: String?
    let requestURL: String?
    let requestMethod: String?
    let requestStatus: Int?
    let requestRuleID: String?
    let payload: ConnectorJSONValue
    let metadata: ConnectorJSONValue?

    enum CodingKeys: String, CodingKey {
        case connector
        case provider
        case event
        case dedupeKey = "dedupe_key"
        case capturedAt = "captured_at"
        case receivedAt = "received_at"
        case pageURL = "page_url"
        case requestURL = "request_url"
        case requestMethod = "request_method"
        case requestStatus = "request_status"
        case requestRuleID = "request_rule_id"
        case payload
        case metadata
    }
}

enum SupabaseConnectorClientError: Error {
    case missingConfiguration(String)
    case invalidRequestURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String?)
    case noRecordsFound
}

struct SupabaseConnectorConfig: Equatable {
    let projectURL: URL
    let apiKey: String
    let table: String
    let connectorID: String
}

struct SupabaseConnectorEventClient: QuotaSnapshotFetching {
    typealias SnapshotMapper = (SupabaseConnectorEventRecord, Date) throws -> QuotaSnapshot

    private let environment: [String: String]
    private let session: URLSession
    private let providerID: String
    private let eventID: String
    private let snapshotMapper: SnapshotMapper

    private static let defaultTableName = "connector_events"
    private static let defaultConnectorID = "info-bar-web-connector"

    private struct AppConfigFile: Decodable {
        let supabase: SupabaseSection?
    }

    private struct SupabaseSection: Decodable {
        let projectURL: String?
        let url: String?
        let anonKey: String?
        let apiKey: String?
        let table: String?
        let connectorID: String?

        enum CodingKeys: String, CodingKey {
            case projectURL
            case url
            case anonKey
            case apiKey
            case table
            case connectorID
        }
    }

    init(
        providerID: String,
        eventID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        snapshotMapper: @escaping SnapshotMapper
    ) {
        self.providerID = providerID
        self.eventID = eventID
        self.environment = environment
        self.session = session
        self.snapshotMapper = snapshotMapper
    }

    func fetchSnapshot() throws -> QuotaSnapshot {
        let config = try resolveConfig(environment: environment)
        var components = URLComponents(
            url: config.projectURL.appendingPathComponent("rest/v1/\(config.table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "select",
                value: [
                    "connector",
                    "provider",
                    "event",
                    "dedupe_key",
                    "captured_at",
                    "received_at",
                    "page_url",
                    "request_url",
                    "request_method",
                    "request_status",
                    "request_rule_id",
                    "payload",
                    "metadata"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "connector", value: "eq.\(config.connectorID)"),
            URLQueryItem(name: "provider", value: "eq.\(providerID)"),
            URLQueryItem(name: "event", value: "eq.\(eventID)"),
            URLQueryItem(name: "order", value: "captured_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw SupabaseConnectorClientError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("InfoBar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try perform(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseConnectorClientError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([SupabaseConnectorEventRecord].self, from: data)
            guard let latest = records.first else {
                throw SupabaseConnectorClientError.noRecordsFound
            }
            return try snapshotMapper(latest, Date())
        case 401, 403:
            throw SupabaseConnectorClientError.unauthorized
        default:
            throw SupabaseConnectorClientError.serverError(http.statusCode, Self.preview(data: data))
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
                box.set(.failure(SupabaseConnectorClientError.invalidResponse))
                return
            }
            box.set(.success((data, response)))
        }.resume()

        semaphore.wait()
        guard let result = box.get() else {
            throw SupabaseConnectorClientError.invalidResponse
        }
        return try result.get()
    }

    private func resolveConfig(environment: [String: String]) throws -> SupabaseConnectorConfig {
        let fileSections = try loadSupabaseSections(environment: environment)
        let envProjectURL = firstNonEmpty(environment: environment, keys: [
            "INFOBAR_SUPABASE_URL",
            "SUPABASE_URL",
            "NEXT_PUBLIC_SUPABASE_URL"
        ])
        let envApiKey = firstNonEmpty(environment: environment, keys: [
            "INFOBAR_SUPABASE_ANON_KEY",
            "INFOBAR_SUPABASE_PUBLISHABLE_KEY",
            "SUPABASE_ANON_KEY",
            "NEXT_PUBLIC_SUPABASE_ANON_KEY",
            "SUPABASE_PUBLISHABLE_KEY",
            "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"
        ])
        let envTable = firstNonEmpty(environment: environment, keys: [
            "INFOBAR_SUPABASE_TABLE"
        ])
        let envConnectorID = firstNonEmpty(environment: environment, keys: [
            "INFOBAR_CONNECTOR_ID"
        ])

        let rawProjectURL = firstValidSupabaseURL(values: [
            fileSections.explicit?.projectURL,
            fileSections.explicit?.url,
            fileSections.local?.projectURL,
            fileSections.local?.url,
            envProjectURL,
            fileSections.example?.projectURL,
            fileSections.example?.url
        ])

        guard let rawProjectURL, let projectURL = URL(string: rawProjectURL) else {
            throw SupabaseConnectorClientError.missingConfiguration(
                "Missing Supabase URL. Configure INFOBAR_SUPABASE_URL or config.local.json supabase.projectURL."
            )
        }

        let rawApiKey = firstValidSupabaseAPIKey(values: [
            fileSections.explicit?.anonKey,
            fileSections.explicit?.apiKey,
            fileSections.local?.anonKey,
            fileSections.local?.apiKey,
            envApiKey,
            fileSections.example?.anonKey,
            fileSections.example?.apiKey
        ])

        guard let rawApiKey, !rawApiKey.isEmpty else {
            throw SupabaseConnectorClientError.missingConfiguration(
                "Missing Supabase API key. Configure INFOBAR_SUPABASE_ANON_KEY or config.local.json supabase.anonKey."
            )
        }

        let table = firstNonEmpty(values: [
            fileSections.explicit?.table,
            fileSections.local?.table,
            envTable,
            fileSections.example?.table,
            Self.defaultTableName
        ]) ?? Self.defaultTableName

        let connectorID = firstNonEmpty(values: [
            fileSections.explicit?.connectorID,
            fileSections.local?.connectorID,
            envConnectorID,
            fileSections.example?.connectorID,
            Self.defaultConnectorID
        ]) ?? Self.defaultConnectorID

        return SupabaseConnectorConfig(
            projectURL: projectURL,
            apiKey: rawApiKey,
            table: table,
            connectorID: connectorID
        )
    }

    private struct SupabaseSectionSources {
        let explicit: SupabaseSection?
        let local: SupabaseSection?
        let example: SupabaseSection?
    }

    private func loadSupabaseSections(environment: [String: String]) throws -> SupabaseSectionSources {
        if let explicit = firstNonEmpty(environment: environment, keys: ["INFOBAR_CONFIG_FILE"]) {
            return SupabaseSectionSources(
                explicit: try loadSupabaseSection(atPath: normalizePath(explicit)),
                local: nil,
                example: nil
            )
        }

        let cwd = FileManager.default.currentDirectoryPath
        let localPath = normalizePath("\(cwd)/config.local.json")
        let examplePath = normalizePath("\(cwd)/config.example.json")
        return SupabaseSectionSources(
            explicit: nil,
            local: try loadSupabaseSection(atPath: localPath),
            example: try loadSupabaseSection(atPath: examplePath)
        )
    }

    private func loadSupabaseSection(atPath path: String) throws -> SupabaseSection? {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppConfigFile.self, from: data)
            return decoded.supabase
        } catch {
            throw SupabaseConnectorClientError.missingConfiguration(
                "Failed to parse config file at \(path): \(error)"
            )
        }
    }

    private func normalizePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(trimmed)
            .path
    }

    private func firstNonEmpty(environment: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            return raw
        }
        return nil
    }

    private func firstNonEmpty(values: [String?]) -> String? {
        for value in values {
            guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            return raw
        }
        return nil
    }

    private func firstValidSupabaseURL(values: [String?]) -> String? {
        for value in values {
            guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            if isPlaceholderSupabaseURL(raw) {
                continue
            }
            return raw
        }
        return nil
    }

    private func firstValidSupabaseAPIKey(values: [String?]) -> String? {
        for value in values {
            guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            if isPlaceholderSupabaseAPIKey(raw) {
                continue
            }
            return raw
        }
        return nil
    }

    private func isPlaceholderSupabaseURL(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard let components = URLComponents(string: lowercased), let host = components.host else {
            return false
        }
        if host == "your-project-ref.supabase.co" {
            return true
        }
        return host.contains("your-project-ref")
    }

    private func isPlaceholderSupabaseAPIKey(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return true
        }
        if normalized == "sb_publishable_replace_me" || normalized == "sb_anon_replace_me" {
            return true
        }
        if normalized.contains("replace_me") || normalized.contains("replace-me") {
            return true
        }
        return false
    }

    private static func preview(data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(240))
    }
}
