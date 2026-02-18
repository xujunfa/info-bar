import AppKit
import Foundation

// Private bridge: forwards NSButton target/action to a Swift closure.
// @MainActor is safe because AppKit always invokes target/action on the main thread.
@MainActor
private final class ButtonActionBridge: NSObject {
    var action: (() -> Void)?

    @objc func buttonClicked(_ sender: Any?) {
        print("[MenuBarController] buttonClicked fired")
        action?()
    }
}

@MainActor
public final class MenuBarController {
    private var item: NSStatusItem?
    private let statusView: QuotaStatusView
    private var actionBridge: ButtonActionBridge?
    public var onClicked: (() -> Void)?

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

            let bridge = ButtonActionBridge()
            bridge.action = { [weak self] in
                print("[MenuBarController] onClicked invoked")
                self?.onClicked?()
            }
            button.target = bridge
            button.action = #selector(ButtonActionBridge.buttonClicked(_:))
            actionBridge = bridge
        }
    }

    /// Remove the NSStatusItem from the menu bar without destroying state.
    /// Call start() afterwards to remount it (e.g. to change display order).
    public func stop() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            self.actionBridge = nil
        }
    }

    public func update(snapshot: QuotaSnapshot?) {
        statusView.update(model: QuotaDisplayModel(snapshot: snapshot))
    }

    public func setVisible(_ visible: Bool) {
        item?.isVisible = visible
    }
}
