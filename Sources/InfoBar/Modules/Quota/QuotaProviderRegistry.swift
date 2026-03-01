import Foundation

public struct QuotaProviderRegistration {
    public let id: String
    public let makeFetcher: () -> any QuotaSnapshotFetching

    public init(id: String, makeFetcher: @escaping () -> any QuotaSnapshotFetching) {
        self.id = id
        self.makeFetcher = makeFetcher
    }
}

public enum QuotaProviderRegistry {
    public static func defaultProviders() -> [QuotaProviderRegistration] {
        [
            QuotaProviderRegistration(id: "codex") {
                CodexUsageClient()
            },
            QuotaProviderRegistration(id: "zenmux") {
                ZenMuxUsageClient()
            },
            QuotaProviderRegistration(id: "minimax") {
                MiniMaxUsageClient()
            },
            QuotaProviderRegistration(id: "bigmodel") {
                BigModelUsageClient()
            },
            QuotaProviderRegistration(id: "factory") {
                FactoryUsageClient()
            }
        ]
    }
}
