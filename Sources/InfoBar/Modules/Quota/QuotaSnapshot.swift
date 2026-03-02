import Foundation

public struct QuotaWindow: Equatable, Codable {
    public let id: String
    public let label: String
    public let usedPercent: Int
    public let resetAt: Date
    public let used: Double?
    public let limit: Double?
    public let remaining: Double?
    public let unit: String?
    public let windowTitle: String?
    public let metadata: [String: String]?

    public init(
        id: String,
        label: String,
        usedPercent: Int,
        resetAt: Date,
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        unit: String? = nil,
        windowTitle: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetAt = resetAt

        let normalizedLimit = Self.normalizedLimit(limit)
        let normalizedUsed = Self.normalizedUsed(used, limit: normalizedLimit)
        self.limit = normalizedLimit
        self.used = normalizedUsed
        self.remaining = Self.normalizedRemaining(remaining, used: normalizedUsed, limit: normalizedLimit)
        self.unit = Self.normalizedText(unit)
        self.windowTitle = Self.normalizedText(windowTitle)
        self.metadata = Self.normalizedMetadata(metadata)
    }

    public var usedRatio: Double {
        Double(usedPercent) / 100
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private static func normalizedLimit(_ value: Double?) -> Double? {
        guard let value = normalizedNumber(value), value > 0 else {
            return nil
        }
        return value
    }

    private static func normalizedUsed(_ value: Double?, limit: Double?) -> Double? {
        guard let used = normalizedNumber(value) else { return nil }
        guard let limit else { return used }
        return min(used, limit)
    }

    private static func normalizedRemaining(_ value: Double?, used: Double?, limit: Double?) -> Double? {
        guard let limit else { return normalizedNumber(value) }

        if let value = normalizedNumber(value) {
            return min(value, limit)
        }

        guard let used else { return nil }
        return max(0, limit - used)
    }

    private static func normalizedMetadata(_ metadata: [String: String]?) -> [String: String]? {
        guard let metadata else { return nil }

        var cleaned: [String: String] = [:]
        for (key, value) in metadata {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            cleaned[normalizedKey] = normalizedValue
        }

        return cleaned.isEmpty ? nil : cleaned
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
