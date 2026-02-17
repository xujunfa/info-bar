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
        let statusCode: Int
        let statusMessage: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMessage = "status_msg"
        }
    }

    struct ModelRemain: Decodable {
        let modelName: String?
        let currentIntervalTotalCount: Int
        let currentIntervalUsageCount: Int
        let remainsTimeMS: Int

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case remainsTimeMS = "remains_time"
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
        components.queryItems = [URLQueryItem(name: "GroupId", value: groupID)]

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

        guard let model = response.modelRemains?.first(where: { $0.currentIntervalTotalCount > 0 }) else {
            throw MiniMaxUsageClientError.missingUsageData
        }

        let remainsCount = max(0, min(model.currentIntervalUsageCount, model.currentIntervalTotalCount))
        let usedCount = model.currentIntervalTotalCount - remainsCount
        let usedPercent = Int((Double(usedCount) / Double(model.currentIntervalTotalCount) * 100).rounded())
        let resetAt = fetchedAt.addingTimeInterval(Double(model.remainsTimeMS) / 1000)

        let window = QuotaWindow(
            id: "hour_5",
            label: "H",
            usedPercent: usedPercent,
            resetAt: resetAt
        )
        return QuotaSnapshot(providerID: "minimax", windows: [window], fetchedAt: fetchedAt)
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
