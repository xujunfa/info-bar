import Foundation

enum UsageFormatting {
    static let unavailableText = "—"
    static let unknownResetText = "reset time unknown"

    static func abbreviated(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        let normalized = max(0, value)

        if normalized >= 1_000_000_000 {
            return shortText(normalized / 1_000_000_000, suffix: "B")
        }
        if normalized >= 1_000_000 {
            return shortText(normalized / 1_000_000, suffix: "M")
        }
        if normalized >= 1_000 {
            return shortText(normalized / 1_000, suffix: "K")
        }

        if abs(normalized.rounded() - normalized) < 0.0001 {
            return "\(Int(normalized.rounded()))"
        }
        return String(format: "%.1f", normalized)
    }

    static func absoluteUsageText(used: Double?, limit: Double?, unit: String?) -> String {
        let usedText = abbreviated(used)
        let limitText = abbreviated(limit)
        let unitText = normalizedUnit(unit)

        let valueText: String
        if let usedText, let limitText {
            valueText = "\(usedText)/\(limitText)"
        } else if let usedText {
            valueText = usedText
        } else if let limitText {
            valueText = "0/\(limitText)"
        } else {
            return unavailableText
        }

        guard let unitText else { return valueText }
        return "\(valueText) \(unitText)"
    }

    static func resetText(timeLeft: String) -> String {
        let trimmed = timeLeft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "—", !trimmed.isEmpty else {
            return unknownResetText
        }
        return "resets in \(trimmed)"
    }

    private static func shortText(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return "\(Int(rounded.rounded()))\(suffix)"
        }
        return "\(rounded)\(suffix)"
    }

    private static func normalizedUnit(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
