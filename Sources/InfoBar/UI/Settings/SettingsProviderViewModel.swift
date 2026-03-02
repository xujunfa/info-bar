import Foundation

public struct SettingsProviderViewModel: Equatable {

    // MARK: - Nested types

    public struct WindowViewModel: Equatable {
        public struct MetadataItem: Equatable {
            public let title: String
            public let value: String

            public init(title: String, value: String) {
                self.title = title
                self.value = value
            }

            public var text: String {
                "\(title): \(value)"
            }
        }

        public let label: String
        public let usedPercent: Int
        /// Human-readable absolute usage, e.g. "1.2K/10K tokens" or "—" when unavailable.
        public let absoluteUsageText: String
        /// Human-readable time until reset, e.g. "2d", "3h", "45m", or "—" if past/unknown.
        public let timeLeft: String
        /// Human-readable reset message, e.g. "resets at 03-02 14:30 (in 2h)".
        public let resetText: String
        /// Human-readable used amount, e.g. "1.2K tokens" or "—" when unavailable.
        public let usedText: String
        /// Human-readable remaining amount, e.g. "8.8K tokens" or "—" when unavailable.
        public let remainingText: String
        /// Human-readable limit amount, e.g. "10K tokens" or "—" when unavailable.
        public let limitText: String
        /// Unit string after normalization, e.g. "tokens".
        public let unitText: String?
        /// Human-readable token consumption using M unit, e.g. "0.004M".
        public let tokenUsageInMillionsText: String?
        /// Supplemental metadata rendered in card footer.
        public let metadataItems: [MetadataItem]

        public var metadataText: String? {
            guard !metadataItems.isEmpty else { return nil }
            return metadataItems.map(\.text).joined(separator: "  ·  ")
        }
    }

    public enum ProviderStatus: Equatable {
        case visible
        case hidden
        case warning

        public var title: String {
            switch self {
            case .visible:
                return "Visible"
            case .hidden:
                return "Hidden"
            case .warning:
                return "High usage"
            }
        }
    }

    // MARK: - Properties

    public let providerID: String
    /// Compact one-line summary kept for backward compatibility.
    public let summary: String
    /// Richer subtitle used by provider list rows.
    public let listSummary: String
    public let isVisible: Bool
    public let status: ProviderStatus
    public let statusText: String
    public let accountText: String?
    public let windows: [WindowViewModel]
    public let fetchedAt: Date?

    // MARK: - Init

    public init(providerID: String, snapshot: QuotaSnapshot?, isVisible: Bool = true, now: Date = Date()) {
        self.providerID = providerID
        self.isVisible = isVisible
        let fetchedAt = snapshot?.fetchedAt
        self.fetchedAt = fetchedAt

        guard let snapshot, !snapshot.windows.isEmpty else {
            self.summary = "—"
            self.listSummary = Self.listUpdatedSummary(fetchedAt: fetchedAt, now: now)
            self.accountText = nil
            self.windows = []
            self.status = Self.providerStatus(isVisible: isVisible, windows: [])
            self.statusText = self.status.title
            return
        }

        self.summary = snapshot.windows
            .map { "\($0.label): \($0.usedPercent)%" }
            .joined(separator: "  ")

        self.windows = snapshot.windows.map { w in
            let timeLeft = Self.formatTimeLeft(from: w.resetAt, now: now)
            let label = Self.standardizedWindowLabel(for: w)
            let normalizedUnit = Self.normalizedText(w.unit)
            return WindowViewModel(
                label: label,
                usedPercent: w.usedPercent,
                absoluteUsageText: UsageFormatting.absoluteUsageText(
                    used: w.used,
                    limit: w.limit,
                    unit: normalizedUnit
                ),
                timeLeft: timeLeft,
                resetText: Self.formatResetText(resetAt: w.resetAt, timeLeft: timeLeft),
                usedText: Self.metricText(value: w.used, unit: normalizedUnit),
                remainingText: Self.metricText(value: w.remaining, unit: normalizedUnit),
                limitText: Self.metricText(value: w.limit, unit: normalizedUnit),
                unitText: normalizedUnit,
                tokenUsageInMillionsText: Self.tokenUsageInMillionsText(value: w.used, unit: normalizedUnit),
                metadataItems: Self.metadataItems(from: w.metadata)
            )
        }

        self.listSummary = Self.listUpdatedSummary(fetchedAt: fetchedAt, now: now)
        self.accountText = Self.accountText(from: snapshot.windows)
        self.status = Self.providerStatus(isVisible: isVisible, windows: self.windows)
        self.statusText = self.status.title
    }

    // MARK: - Private helpers

    static func formatTimeLeft(from date: Date, now: Date = Date()) -> String {
        let diff = date.timeIntervalSince(now)
        guard diff > 0 else { return "—" }
        let seconds = Int(diff)
        let days = seconds / 86400
        if days > 0 { return "\(days)d" }
        let hours = seconds / 3600
        if hours > 0 { return "\(hours)h" }
        let minutes = max(1, seconds / 60)
        return "\(minutes)m"
    }

    private static func metricText(value: Double?, unit: String?) -> String {
        guard let abbreviated = UsageFormatting.abbreviated(value) else {
            return UsageFormatting.unavailableText
        }
        guard let unit else { return abbreviated }
        return "\(abbreviated) \(unit)"
    }

    private static func listUpdatedSummary(fetchedAt: Date?, now: Date) -> String {
        guard let fetchedAt else {
            return "Updated: waiting for first snapshot"
        }
        return "Updated: \(formatAgo(from: fetchedAt, now: now))"
    }

    private static func standardizedWindowLabel(for window: QuotaWindow) -> String {
        let sourceLabel = normalizedText(window.windowTitle) ?? normalizedText(window.label) ?? window.label
        let normalizedLabel = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPeriodType = normalizedText(window.metadata?["period_type"])?.lowercased() ?? ""

        if normalizedLabel == "w"
            || normalizedLabel == "weekly"
            || normalizedLabel == "weekly usage"
            || normalizedID == "week"
            || normalizedPeriodType == "week"
            || normalizedPeriodType == "weekly" {
            return "Weekly usage"
        }

        if normalizedLabel == "h"
            || normalizedLabel == "current interval"
            || normalizedLabel.contains("5-hour")
            || normalizedLabel.contains("5 hour")
            || normalizedLabel == "5h"
            || normalizedLabel == "hourly"
            || normalizedID == "hour_5"
            || normalizedPeriodType == "hour_5"
            || normalizedPeriodType == "five_hour"
            || normalizedPeriodType == "5h"
            || normalizedPeriodType == "hour" {
            return "5-hour usage"
        }

        return sourceLabel
    }

    private static func formatResetText(resetAt: Date, timeLeft: String) -> String {
        guard timeLeft != "—" else { return UsageFormatting.unknownResetText }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        let resetAtText = formatter.string(from: resetAt)
        return "resets at \(resetAtText) (in \(timeLeft))"
    }

    private static func providerStatus(isVisible: Bool, windows: [WindowViewModel]) -> ProviderStatus {
        if !isVisible {
            return .hidden
        }
        if windows.contains(where: { $0.usedPercent >= 90 }) {
            return .warning
        }
        return .visible
    }

    private static func metadataItems(from metadata: [String: String]?) -> [WindowViewModel.MetadataItem] {
        guard let metadata else { return [] }

        let prioritized: [(key: String, title: String)] = [
            ("model_name", "Model"),
            ("plan_name", "Plan"),
            ("plan_type", "Plan"),
            ("period_type", "Window"),
            ("limit_type", "Window"),
            ("connector", "Source"),
            ("source", "Source"),
            ("hook", "Source"),
            ("trace_id", "Trace"),
        ]

        var items: [WindowViewModel.MetadataItem] = []
        var consumedKeys = Set<String>()
        var consumedTitles = Set<String>()

        for candidate in prioritized {
            guard let value = normalizedText(metadata[candidate.key]) else { continue }
            guard !consumedTitles.contains(candidate.title) else { continue }
            items.append(WindowViewModel.MetadataItem(title: candidate.title, value: value))
            consumedKeys.insert(candidate.key)
            consumedTitles.insert(candidate.title)
            if items.count >= 3 {
                return items
            }
        }

        for key in metadata.keys.sorted() {
            guard !consumedKeys.contains(key) else { continue }
            guard let value = normalizedText(metadata[key]) else { continue }
            items.append(WindowViewModel.MetadataItem(title: metadataTitle(from: key), value: value))
            if items.count >= 3 {
                break
            }
        }

        return items
    }

    private static func tokenUsageInMillionsText(value: Double?, unit: String?) -> String? {
        guard let value, value > 0 else { return nil }
        guard let unit = unit?.lowercased(), unit.contains("token") else { return nil }

        let millions = value / 1_000_000
        let decimals: Int
        if millions >= 100 {
            decimals = 0
        } else if millions >= 10 {
            decimals = 1
        } else if millions >= 1 {
            decimals = 2
        } else {
            decimals = 3
        }
        let formatted = String(format: "%.\(decimals)f", millions)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return "\(formatted)M"
    }

    private static func accountText(from windows: [QuotaWindow]) -> String? {
        let candidates = [
            "account_email",
            "email",
            "user_email",
            "account_phone",
            "phone",
            "mobile",
            "user_phone",
            "account",
            "account_name",
            "user_name",
            "user",
        ]

        for key in candidates {
            for window in windows {
                guard let metadata = window.metadata else { continue }
                if let value = normalizedText(metadata[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func metadataTitle(from rawKey: String) -> String {
        let normalized = rawKey
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Metadata" }
        return normalized
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func formatAgo(from date: Date, now: Date) -> String {
        let diff = Int(now.timeIntervalSince(date))
        if diff < 60 { return "just now" }
        let minutes = diff / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
