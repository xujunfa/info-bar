import AppKit
import Foundation

@MainActor
public final class MenuBarController {
    private var item: NSStatusItem?
    private let statusView: QuotaStatusView

    public init(providerID: String = "codex") {
        self.statusView = QuotaStatusView(
            frame: NSRect(x: 0, y: 0, width: QuotaLayoutMetrics.statusWidth, height: QuotaLayoutMetrics.statusHeight),
            providerID: providerID
        )
    }

    public func start() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: QuotaLayoutMetrics.statusWidth)
        self.item = item

        if let button = item.button {
            button.addSubview(statusView)
            statusView.frame = button.bounds
            statusView.autoresizingMask = [.width, .height]
        }
    }

    public func update(snapshot: QuotaSnapshot?) {
        statusView.update(model: QuotaDisplayModel(snapshot: snapshot))
    }
}
