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

    private static let paceTargetUsage: Double = 0.8
    private static let paceCurveAlpha: Double = 1.1
    private static let pacePressureAlpha: Double = 1.6
    private static let warningThreshold: Double = 0.30
    private static let criticalThreshold: Double = 0.60

    public init(snapshot: QuotaSnapshot?) {
        guard let snapshot else {
            self.text = "W: -- -- | H: -- --"
            self.topLine = "W: -- --"
            self.bottomLine = "H: -- --"
            self.ratio = 0
            self.state = .unknown
            return
        }

        guard !snapshot.windows.isEmpty else {
            self.text = "W: -- -- | H: -- --"
            self.topLine = "W: -- --"
            self.bottomLine = "H: -- --"
            self.ratio = 0
            self.state = .unknown
            return
        }

        let useHWPinnedLayout = Self.requiresHWPinnedLayout(windows: snapshot.windows)
        let hourlyWindow = snapshot.windows.first(where: Self.isHourlyWindow)
        let weeklyWindow = snapshot.windows.first(where: Self.isWeeklyWindow)
        let topWindow: QuotaWindow?
        let bottomWindow: QuotaWindow?

        if useHWPinnedLayout {
            topWindow = weeklyWindow
            bottomWindow = hourlyWindow
        } else {
            topWindow = snapshot.windows.first
            bottomWindow = snapshot.windows.count > 1 ? snapshot.windows[1] : nil
        }

        self.topLine = Self.lineText(window: topWindow, fallbackLabel: "W", fetchedAt: snapshot.fetchedAt)
        self.bottomLine = Self.lineText(window: bottomWindow, fallbackLabel: "H", fetchedAt: snapshot.fetchedAt)
        self.text = "\(self.topLine) | \(self.bottomLine)"

        if useHWPinnedLayout, let hourlyWindow {
            self.ratio = max(0, min(hourlyWindow.usedRatio, 1))
        } else {
            self.ratio = max(0, min(snapshot.primaryUsedRatio, 1))
        }

        if let paceState = Self.paceState(windows: snapshot.windows, fetchedAt: snapshot.fetchedAt) {
            self.state = paceState
        } else {
            self.state = Self.state(for: self.ratio)
        }
    }

    private static func lineText(window: QuotaWindow?, fallbackLabel: String, fetchedAt: Date) -> String {
        guard let window else {
            return "\(fallbackLabel): -- --"
        }
        let normalizedLabel = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = normalizedLabel.isEmpty ? fallbackLabel : normalizedLabel
        return "\(label): \(window.usedPercent)% \(durationText(from: fetchedAt, to: window.resetAt))"
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

    private static func state(for ratio: Double) -> State {
        switch ratio {
        case ..<0.7:
            return .normal
        case ..<0.9:
            return .warning
        default:
            return .critical
        }
    }

    private static func requiresHWPinnedLayout(windows: [QuotaWindow]) -> Bool {
        windows.contains(where: isHourlyWindow) || windows.contains(where: isWeeklyWindow)
    }

    private static func isHourlyWindow(_ window: QuotaWindow) -> Bool {
        let normalizedID = window.id.lowercased()
        let normalizedLabel = window.label.uppercased()
        return normalizedLabel == "H" || [
            "hour_5",
            "five_hour",
            "5h",
            "hour",
            "tokens_limit"
        ].contains(normalizedID)
    }

    private static func isWeeklyWindow(_ window: QuotaWindow) -> Bool {
        let normalizedID = window.id.lowercased()
        let normalizedLabel = window.label.uppercased()
        return normalizedLabel == "W" || [
            "week",
            "weekly",
            "time_limit"
        ].contains(normalizedID)
    }

    private static func paceState(windows: [QuotaWindow], fetchedAt: Date) -> State? {
        let hourlyWindows = windows.filter(isHourlyWindow)
        let weeklyWindows = windows.filter(isWeeklyWindow)
        let windowsForPace: [QuotaWindow]

        // For Codex-like H/W providers, if W is missing, use H alone.
        if weeklyWindows.isEmpty, !hourlyWindows.isEmpty {
            windowsForPace = hourlyWindows
        } else {
            windowsForPace = windows
        }

        let urgency = windowsForPace
            .map { paceUrgency(for: $0, fetchedAt: fetchedAt) }
            .max() ?? 0

        if urgency >= criticalThreshold {
            return .critical
        }
        if urgency >= warningThreshold {
            return .warning
        }
        return .normal
    }

    private static func paceUrgency(for window: QuotaWindow, fetchedAt: Date) -> Double {
        guard let duration = duration(for: window), duration > 0 else { return 0 }

        let remain = max(0, window.resetAt.timeIntervalSince(fetchedAt))
        let elapsedRatio = clamp(1 - (remain / duration))
        let expectedUsed = paceTargetUsage * pow(elapsedRatio, paceCurveAlpha)
        let used = clamp(window.usedRatio)
        let paceGap = max(0, expectedUsed - used)
        let baseUrgency = clamp(paceGap / paceTargetUsage)
        let timePressure = pow(elapsedRatio, pacePressureAlpha)
        return baseUrgency * (0.35 + 0.65 * timePressure)
    }

    private static func duration(for window: QuotaWindow) -> TimeInterval? {
        let normalizedID = window.id.lowercased()
        let normalizedLabel = window.label.uppercased()

        if isHourlyWindow(window) {
            return 5 * 3_600
        }
        if normalizedLabel == "D" || ["day", "daily"].contains(normalizedID) {
            return 24 * 3_600
        }
        if isWeeklyWindow(window) {
            return 7 * 24 * 3_600
        }
        if normalizedLabel == "M" || ["month", "monthly"].contains(normalizedID) {
            return 30 * 24 * 3_600
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        max(0, min(value, 1))
    }
}
