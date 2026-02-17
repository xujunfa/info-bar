import Foundation

public struct QuotaWindow: Equatable, Codable {
    public let id: String
    public let label: String
    public let usedPercent: Int
    public let resetAt: Date

    public init(id: String, label: String, usedPercent: Int, resetAt: Date) {
        self.id = id
        self.label = label
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetAt = resetAt
    }

    public var usedRatio: Double {
        Double(usedPercent) / 100
    }
}

public struct QuotaSnapshot: Equatable, Codable {
    public let providerID: String
    public let windows: [QuotaWindow]
    public let fetchedAt: Date

    public init(providerID: String, windows: [QuotaWindow], fetchedAt: Date) {
        self.providerID = providerID
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var primaryWindow: QuotaWindow? {
        windows.first
    }

    public var primaryUsedRatio: Double {
        primaryWindow?.usedRatio ?? 0
    }
}
