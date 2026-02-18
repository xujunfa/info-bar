import Foundation

public struct SettingsProviderViewModel: Equatable {

    // MARK: - Nested types

    public struct WindowViewModel: Equatable {
        public let label: String
        public let usedPercent: Int
        /// Human-readable time until reset, e.g. "2d", "3h", "45m", or "—" if past/unknown.
        public let timeLeft: String
    }

    // MARK: - Properties

    public let providerID: String
    /// Compact one-line summary kept for backward compatibility.
    public let summary: String
    public let isVisible: Bool
    public let windows: [WindowViewModel]
    public let fetchedAt: Date?

    // MARK: - Init

    public init(providerID: String, snapshot: QuotaSnapshot?, isVisible: Bool = true) {
        self.providerID = providerID
        self.isVisible = isVisible
        self.fetchedAt = snapshot?.fetchedAt

        guard let snapshot, !snapshot.windows.isEmpty else {
            self.summary = "—"
            self.windows = []
            return
        }

        self.summary = snapshot.windows
            .map { "\($0.label): \($0.usedPercent)%" }
            .joined(separator: "  ")

        let now = Date()
        self.windows = snapshot.windows.map { w in
            WindowViewModel(
                label: w.label,
                usedPercent: w.usedPercent,
                timeLeft: Self.formatTimeLeft(from: w.resetAt, now: now)
            )
        }
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
}
