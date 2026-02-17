import AppKit
import Foundation

final class QuotaStatusView: NSView {
    private var model = QuotaDisplayModel(snapshot: nil)
    private let codexSymbolName = "chevron.left.forwardslash.chevron.right"
    private lazy var codexImage: NSImage? = Self.loadCodexImage()

    override var intrinsicContentSize: NSSize {
        NSSize(width: QuotaLayoutMetrics.statusWidth, height: QuotaLayoutMetrics.statusHeight)
    }

    func update(model: QuotaDisplayModel) {
        guard self.model != model else { return }
        self.model = model
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawIcon()

        let topAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let bottomAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: color(for: model.state)
        ]

        model.topLine.draw(
            in: NSRect(x: QuotaLayoutMetrics.textX, y: 11, width: bounds.width - QuotaLayoutMetrics.textX - 2, height: 10),
            withAttributes: topAttributes
        )
        model.bottomLine.draw(
            in: NSRect(x: QuotaLayoutMetrics.textX, y: 1, width: bounds.width - QuotaLayoutMetrics.textX - 2, height: 10),
            withAttributes: bottomAttributes
        )
    }

    private func drawIcon() {
        var image = codexImage
        if image == nil, #available(macOS 11.0, *) {
            image = NSImage(systemSymbolName: codexSymbolName, accessibilityDescription: "Codex")
        }
        guard let image else { return }

        let configured = image.withSymbolConfiguration(.init(pointSize: 9, weight: .medium)) ?? image
        configured.isTemplate = true

        NSColor.secondaryLabelColor.set()
        let y = floor((bounds.height - QuotaLayoutMetrics.iconSize) / 2)
        let rect = NSRect(
            x: QuotaLayoutMetrics.iconX,
            y: y,
            width: QuotaLayoutMetrics.iconSize,
            height: QuotaLayoutMetrics.iconSize
        )
        configured.draw(in: rect)
    }

    private static func loadCodexImage() -> NSImage? {
        if let url = Bundle.module.url(
            forResource: "codex",
            withExtension: "svg",
            subdirectory: "Resources/Icons"
        ), let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    private func color(for state: QuotaDisplayModel.State) -> NSColor {
        switch state {
        case .normal: return NSColor.systemGreen
        case .warning: return NSColor.systemOrange
        case .critical: return NSColor.systemRed
        case .unknown: return NSColor.systemGray
        }
    }
}
