import Foundation

public struct CodexCredentials: Equatable {
    public let accessToken: String
    public let accountId: String?

    public init(accessToken: String, accountId: String?) {
        self.accessToken = accessToken
        self.accountId = accountId
    }
}

public enum CodexAuthStoreError: Error {
    case notFound
    case invalidJSON
    case missingCredentials
}

public enum CodexAuthStore {
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexCredentials {
        let url = authFileURL(environment: environment)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexAuthStoreError.notFound
        }
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> CodexCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthStoreError.invalidJSON
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return CodexCredentials(accessToken: trimmed, accountId: nil)
            }
        }

        guard let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String else {
            throw CodexAuthStoreError.missingCredentials
        }

        let trimmedAccess = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccess.isEmpty else {
            throw CodexAuthStoreError.missingCredentials
        }

        let accountId = (tokens["account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCredentials(accessToken: trimmedAccess, accountId: accountId?.isEmpty == false ? accountId : nil)
    }

    private static func authFileURL(environment: [String: String]) -> URL {
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }
}
