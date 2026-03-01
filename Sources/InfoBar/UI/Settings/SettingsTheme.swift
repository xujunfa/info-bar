import AppKit

@MainActor
enum SettingsTheme {
    enum Layout {
        static let panelSize = NSSize(width: 640, height: 440)
        static let sidebarWidth: CGFloat = 204
        static let detailMinimumWidth: CGFloat = 320
        static let contentInset: CGFloat = 20
        static let listContentInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        static let listRowHeight: CGFloat = 38
        static let listRowSpacing: CGFloat = 1
        static let listCellHorizontalInset: CGFloat = 10
        static let placeholderMaxWidth: CGFloat = 360
        static let usagePlaceholderHeight: CGFloat = 70
    }

    enum Radius {
        static let panel: CGFloat = 12
        static let row: CGFloat = 8
        static let icon: CGFloat = 8
        static let statusDot: CGFloat = 5
        static let placeholder: CGFloat = 12
    }

    enum Typography {
        static var providerName: NSFont { NSFont.systemFont(ofSize: 13, weight: .medium) }
        static var providerTitle: NSFont { NSFont.systemFont(ofSize: 18, weight: .semibold) }
        static var body: NSFont { NSFont.systemFont(ofSize: 13, weight: .regular) }
        static var caption: NSFont { NSFont.systemFont(ofSize: 11, weight: .regular) }
        static var section: NSFont { NSFont.systemFont(ofSize: 11, weight: .semibold) }
        static var usageLabel: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }
        static var placeholderTitle: NSFont { NSFont.systemFont(ofSize: 15, weight: .semibold) }
    }

    enum Shadow {
        static func subtle(y: CGFloat = -1) -> NSShadow {
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: y)
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
            return shadow
        }
    }

    enum Color {
        static var sidebarBackground: NSColor {
            NSColor.windowBackgroundColor.blended(withFraction: 0.08, of: .controlBackgroundColor)
            ?? NSColor.windowBackgroundColor
        }

        static var detailBackground: NSColor {
            NSColor.windowBackgroundColor
        }

        static var splitDivider: NSColor {
            NSColor.separatorColor.withAlphaComponent(0.45)
        }

        static var rowHoverBackground: NSColor {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12)
        }

        static var rowSelectedBackground: NSColor {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.30)
        }

        static var rowBorder: NSColor {
            NSColor.separatorColor.withAlphaComponent(0.2)
        }

        static var statusVisible: NSColor { .systemGreen }
        static var statusHidden: NSColor { .systemGray }
        static var statusWarning: NSColor { .systemOrange }

        static var primaryText: NSColor { .labelColor }
        static var secondaryText: NSColor { .secondaryLabelColor }
        static var tertiaryText: NSColor { .tertiaryLabelColor }

        static var placeholderBackground: NSColor {
            NSColor.controlBackgroundColor.withAlphaComponent(0.52)
        }

        static var placeholderBorder: NSColor {
            NSColor.separatorColor.withAlphaComponent(0.65)
        }
    }
}
