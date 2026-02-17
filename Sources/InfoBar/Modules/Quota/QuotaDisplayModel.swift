import Foundation

public struct QuotaDisplayModel: Equatable {
    public enum State: Equatable {
        case normal
        case warning
        case critical
        case unknown
    }

    public let text: String
    public let topLine: String
    public let bottomLine: String
    public let ratio: Double
    public let state: State

    public init(snapshot: QuotaSnapshot?) {
        guard let snapshot else {
            self.text = "H: -- -- | W: -- --"
            self.topLine = "H: -- --"
            self.bottomLine = "W: -- --"
            self.ratio = 0
            self.state = .unknown
            return
        }

        self.topLine = Self.lineText(window: snapshot.windows.first, fallbackLabel: "H", fetchedAt: snapshot.fetchedAt)
        self.bottomLine = Self.lineText(
            window: snapshot.windows.count > 1 ? snapshot.windows[1] : nil,
            fallbackLabel: "W",
            fetchedAt: snapshot.fetchedAt
        )
        self.text = "\(self.topLine) | \(self.bottomLine)"
        self.ratio = max(0, min(snapshot.primaryUsedRatio, 1))

        switch self.ratio {
        case ..<0.7: self.state = .normal
        case ..<0.9: self.state = .warning
        default: self.state = .critical
        }
    }

    private static func lineText(window: QuotaWindow?, fallbackLabel: String, fetchedAt: Date) -> String {
        guard let window else {
            return "\(fallbackLabel): -- --"
        }
        return "\(window.label): \(window.usedPercent)% \(durationText(from: fetchedAt, to: window.resetAt))"
    }

    private static func durationText(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let days = seconds / 86_400
        if days >= 1 {
            return daysText(days)
        }

        let hours = seconds / 3_600
        if hours < 1 {
            return minutesText(seconds: seconds)
        }
        return hoursText(hours)
    }

    private static func daysText(_ days: Double) -> String {
        let rounded = (days * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return "\(Int(rounded.rounded()))d"
        }
        return "\(rounded)d"
    }

    private static func minutesText(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes)min"
    }

    private static func hoursText(_ hours: Double) -> String {
        let rounded = (hours * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return "\(Int(rounded.rounded()))h"
        }
        return "\(rounded)h"
    }
}
