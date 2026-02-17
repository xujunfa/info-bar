import Foundation

public struct QuotaSnapshot: Equatable, Codable {
    public let limit: Int
    public let used: Int
    public let resetAt: Date
    public let fetchedAt: Date

    public init(limit: Int, used: Int, resetAt: Date, fetchedAt: Date) {
        self.limit = max(limit, 0)
        self.used = max(used, 0)
        self.resetAt = resetAt
        self.fetchedAt = fetchedAt
    }

    public var remaining: Int {
        max(limit - used, 0)
    }

    public var usedRatio: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }

    public var isExhausted: Bool {
        used >= limit && limit > 0
    }
}
