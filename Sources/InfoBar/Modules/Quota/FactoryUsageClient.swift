import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FactoryUsageClientError: Error {
    case missingUsageData
}

struct FactoryUsageClient: QuotaSnapshotFetching {
    private static let defaultMonthlyLimitTokens: Double = 20_000_000
    private let supabaseClient: SupabaseConnectorEventClient

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) {
        self.supabaseClient = SupabaseConnectorEventClient(
            providerID: "factory",
            eventID: "usage_snapshot",
            environment: environment,
            session: session,
            snapshotMapper: Self.mapToSnapshot(record:fetchedAt:)
        )
    }

    func fetchSnapshot() throws -> QuotaSnapshot {
        try supabaseClient.fetchSnapshot()
    }

    static func mapToSnapshot(record: SupabaseConnectorEventRecord, fetchedAt: Date) throws -> QuotaSnapshot {
        let payload = record.payload

        var used = number(forPath: ["usage", "standard", "orgTotalTokensUsed"], in: payload)
            ?? number(forPath: ["usage", "standard", "userTokens"], in: payload)
            ?? number(forPath: ["usage", "standard", "orgOverageUsed"], in: payload)
            ?? number(for: [
                "current_month_usage",
                "currentMonthUsage",
                "month_usage",
                "monthUsage",
                "usage",
                "used",
                "used_tokens",
                "usedTokens",
                "consumed",
                "consumed_tokens",
                "total_usage",
                "totalUsage"
            ], in: payload)

        var limit = number(forPath: ["usage", "standard", "totalAllowance"], in: payload)
            ?? number(forPath: ["usage", "standard", "basicAllowance"], in: payload)
            ?? number(for: [
                "monthly_limit",
                "monthlyLimit",
                "month_limit",
                "monthLimit",
                "token_limit",
                "tokenLimit",
                "quota",
                "total_quota",
                "totalQuota",
                "limit",
                "total"
            ], in: payload)

        var remaining = number(forPath: ["usage", "standard", "remainingAllowance"], in: payload)
            ?? number(forPath: ["usage", "standard", "orgRemainingTokens"], in: payload)
            ?? number(for: [
                "monthly_remaining",
                "monthlyRemaining",
                "month_remaining",
                "monthRemaining",
                "remaining_tokens",
                "remainingTokens",
                "remaining",
                "left",
                "left_tokens",
                "leftTokens"
            ], in: payload)

        if limit == nil, let used, let remaining {
            limit = used + remaining
        }
        if used == nil, let limit, let remaining {
            used = max(0, limit - remaining)
        }
        if remaining == nil, let limit, let used {
            remaining = max(0, limit - used)
        }

        let usedPercent: Int
        if let ratio = number(forPath: ["usage", "standard", "usedRatio"], in: payload) {
            usedPercent = percentFromRatio(ratio)
        } else if let value = value(for: [
            "used_percent",
            "usage_percent",
            "monthly_percent",
            "usedPercent",
            "usagePercent",
            "monthlyPercent",
            "usedRate",
            "usageRate",
            "ratio",
            "percent"
        ], in: payload),
                  let parsed = parsePercent(value) {
            usedPercent = parsed
        } else if let used, let limit, limit > 0 {
            usedPercent = Int((max(0, min(used, limit)) / limit * 100).rounded())
        } else if let remaining, let limit, limit > 0 {
            usedPercent = Int((max(0, min(limit - remaining, limit)) / limit * 100).rounded())
        } else {
            throw FactoryUsageClientError.missingUsageData
        }

        if limit == nil, used != nil {
            limit = Self.defaultMonthlyLimitTokens
        }
        if let limit, limit > 0, used == nil {
            used = limit * Double(usedPercent) / 100
        }
        if let limit, limit > 0, remaining == nil, let used {
            remaining = max(0, limit - used)
        }

        let resetAt = date(forPath: ["usage", "endDate"], in: payload)
            ?? date(for: [
                "reset_at",
                "resetAt",
                "next_reset_at",
                "nextResetAt",
                "cycle_end_time",
                "cycleEndTime",
                "period_end",
                "periodEnd",
                "expires_at",
                "expiresAt",
                "endDate",
                "end_date"
            ], in: payload)
            ?? endOfMonth(from: fetchedAt)

        var metadata: [String: String] = [
            "connector": record.connector,
            "event": record.event
        ]
        if let dedupeKey = normalizedText(record.dedupeKey) {
            metadata["dedupe_key"] = dedupeKey
        }
        if let traceID = string(from: record.metadata, keys: ["traceId", "trace_id"]) {
            metadata["trace_id"] = traceID
        }

        let windowTitle = string(
            for: ["window_title", "windowTitle", "title", "plan_name", "planName", "subscription_name", "subscriptionName"],
            in: payload
        ) ?? "Monthly tokens"
        let unit = string(
            for: ["unit", "token_unit", "tokenUnit", "usage_unit", "usageUnit"],
            in: payload
        ) ?? "tokens"

        let window = QuotaWindow(
            id: "monthly",
            label: "M",
            usedPercent: usedPercent,
            resetAt: resetAt,
            used: used,
            limit: limit,
            remaining: remaining,
            unit: unit,
            windowTitle: windowTitle,
            metadata: metadata
        )
        return QuotaSnapshot(providerID: "factory", windows: [window], fetchedAt: fetchedAt)
    }

    private static func value(for keys: [String], in root: ConnectorJSONValue) -> ConnectorJSONValue? {
        let normalized = Set(keys.map { $0.lowercased() })
        return findValue(in: root, keys: normalized)
    }

    private static func findValue(in value: ConnectorJSONValue, keys: Set<String>) -> ConnectorJSONValue? {
        switch value {
        case let .object(object):
            for (key, candidate) in object where keys.contains(key.lowercased()) {
                return candidate
            }
            for (_, child) in object {
                if let nested = findValue(in: child, keys: keys) {
                    return nested
                }
            }
        case let .array(items):
            for item in items {
                if let nested = findValue(in: item, keys: keys) {
                    return nested
                }
            }
        default:
            break
        }
        return nil
    }

    private static func nestedValue(in root: ConnectorJSONValue, path: [String]) -> ConnectorJSONValue? {
        var current = root
        for key in path {
            guard case let .object(object) = current else {
                return nil
            }
            guard let next = object[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func number(forPath path: [String], in root: ConnectorJSONValue) -> Double? {
        guard let value = nestedValue(in: root, path: path) else {
            return nil
        }
        return number(from: value)
    }

    private static func number(for keys: [String], in root: ConnectorJSONValue) -> Double? {
        guard let value = value(for: keys, in: root) else {
            return nil
        }
        return number(from: value)
    }

    private static func number(from value: ConnectorJSONValue) -> Double? {
        switch value {
        case let .number(v):
            return v
        case let .string(v):
            let cleaned = v
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        case let .bool(v):
            return v ? 1 : 0
        default:
            return nil
        }
    }

    private static func parsePercent(_ value: ConnectorJSONValue) -> Int? {
        let raw: Double?
        switch value {
        case let .number(v):
            raw = v
        case let .string(v):
            let cleaned = v
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            raw = Double(cleaned)
        default:
            raw = nil
        }

        guard let raw else {
            return nil
        }
        let percent = (raw >= 0 && raw <= 1) ? raw * 100 : raw
        return Int(max(0, min(100, percent.rounded())))
    }

    private static func string(for keys: [String], in root: ConnectorJSONValue) -> String? {
        guard let value = value(for: keys, in: root) else {
            return nil
        }
        return string(from: value)
    }

    private static func string(from value: ConnectorJSONValue?, keys: [String]) -> String? {
        guard let value else { return nil }
        return string(for: keys, in: value)
    }

    private static func string(from value: ConnectorJSONValue) -> String? {
        switch value {
        case let .string(v):
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let .number(v):
            return String(v)
        case let .bool(v):
            return String(v)
        default:
            return nil
        }
    }

    private static func percentFromRatio(_ ratio: Double) -> Int {
        let normalized: Double
        if ratio <= 1 {
            normalized = ratio * 100
        } else {
            normalized = ratio
        }
        return Int(max(0, min(100, normalized.rounded())))
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func date(forPath path: [String], in root: ConnectorJSONValue) -> Date? {
        guard let value = nestedValue(in: root, path: path) else {
            return nil
        }
        return date(from: value)
    }

    private static func date(for keys: [String], in root: ConnectorJSONValue) -> Date? {
        guard let value = value(for: keys, in: root) else {
            return nil
        }
        return date(from: value)
    }

    private static func date(from value: ConnectorJSONValue) -> Date? {
        switch value {
        case let .number(v):
            return date(fromEpochLike: v)
        case let .string(v):
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if let numeric = Double(trimmed) {
                return date(fromEpochLike: numeric)
            }
            return parseISODate(trimmed)
        default:
            return nil
        }
    }

    private static func date(fromEpochLike raw: Double) -> Date {
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func endOfMonth(from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let start = calendar.date(from: components),
              let next = calendar.date(byAdding: .month, value: 1, to: start) else {
            return date
        }
        return next
    }
}
