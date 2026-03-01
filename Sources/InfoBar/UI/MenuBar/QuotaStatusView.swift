import AppKit
import Foundation

// QuotaStatusView: Custom menu bar view for displaying quota information
final class QuotaStatusView: NSView {
    private var model = QuotaDisplayModel(snapshot: nil)
    private let fallbackSymbolName = "chevron.left.forwardslash.chevron.right"
    private let providerID: String
    private lazy var providerImage: NSImage? = Self.loadProviderImage(providerID: providerID)

    init(frame frameRect: NSRect, providerID: String) {
        self.providerID = providerID
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.providerID = "codex"
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: QuotaLayoutMetrics.statusWidth, height: QuotaLayoutMetrics.statusHeight)
    }

    // Let all mouse events pass through to the underlying NSStatusBarButton.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(model: QuotaDisplayModel) {
        guard self.model != model else { return }
        self.model = model
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        super.draw(dirtyRect)

        drawIcon()

        let textColor = color(for: model.state)
        let topFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        let bottomFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let safeTextColor = textColor
        
        let pStyle = NSMutableParagraphStyle()
        pStyle.lineBreakMode = .byTruncatingTail
        pStyle.alignment = .left

        let contentWidth = bounds.width - QuotaLayoutMetrics.textX - 2
        
        if !model.topLine.isEmpty, contentWidth > 0 {
            let topAttr = NSMutableAttributedString(string: model.topLine)
            let fullRange = NSRect(x: QuotaLayoutMetrics.textX, y: 11, width: contentWidth, height: 10)
            let range = NSRange(location: 0, length: topAttr.length)
            topAttr.addAttribute(.foregroundColor, value: safeTextColor, range: range)
            topAttr.addAttribute(.paragraphStyle, value: pStyle, range: range)
            if let f = topFont as NSFont? { topAttr.addAttribute(.font, value: f, range: range) }
            topAttr.draw(in: fullRange)
        }
        
        if !model.bottomLine.isEmpty, contentWidth > 0 {
            let botAttr = NSMutableAttributedString(string: model.bottomLine)
            let fullRange = NSRect(x: QuotaLayoutMetrics.textX, y: 1, width: contentWidth, height: 10)
            let range = NSRange(location: 0, length: botAttr.length)
            botAttr.addAttribute(.foregroundColor, value: safeTextColor, range: range)
            botAttr.addAttribute(.paragraphStyle, value: pStyle, range: range)
            if let f = bottomFont as NSFont? { botAttr.addAttribute(.font, value: f, range: range) }
            botAttr.draw(in: fullRange)
        }
    }

    private func drawIcon() {
        var image = providerImage
        if image == nil, #available(macOS 11.0, *) {
            image = NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: providerID.capitalized)
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

    private static func loadProviderImage(providerID: String) -> NSImage? {
        let candidates = [providerID.lowercased(), "codex"]
        for name in candidates {
            if let url = Bundle.module.url(
                forResource: name,
                withExtension: "svg",
                subdirectory: "Resources/Icons"
            ), let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private func color(for state: QuotaDisplayModel.State) -> NSColor {
        switch state {
        case .normal: return NSColor.labelColor
        case .warning: return NSColor.systemOrange
        case .critical: return NSColor.systemRed
        case .unknown: return NSColor.systemGray
        }
    }
}
