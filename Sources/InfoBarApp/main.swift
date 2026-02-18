import AppKit
import Foundation
import InfoBar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarsByID: [String: MenuBarController] = [:]
    private var quotaWidgets: [QuotaWidget] = []
    private var quotaModules: [QuotaModule] = []
    private let settingsWindowController = SettingsWindowController()
    private let visibilityStore = ProviderVisibilityStore()
    private let orderStore = ProviderOrderStore()
    private var snapshots: [String: QuotaSnapshot?] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let providers = QuotaProviderRegistry.defaultProviders()
        let defaultIDs = providers.map(\.id)

        for provider in providers {
            snapshots[provider.id] = nil
        }

        // Phase 1: create modules & widgets for every provider, but do NOT call start() yet.
        for provider in providers {
            let menuBar = MenuBarController(providerID: provider.id)
            let widget = QuotaWidget()
            let reader = QuotaReader(fetcher: provider.makeFetcher())
            let module = QuotaModule(reader: reader)

            widget.onSnapshot = { [weak self, weak menuBar] snapshot in
                Task { @MainActor [weak self] in
                    menuBar?.update(snapshot: snapshot)
                    self?.snapshots[provider.id] = snapshot
                    self?.pushSnapshotsToSettings(defaultIDs: defaultIDs)
                }
            }
            menuBar.onClicked = { [weak self] in
                self?.settingsWindowController.show()
            }
            module.setWidgets([widget])
            module.mount()

            menuBarsByID[provider.id] = menuBar
            quotaWidgets.append(widget)
            quotaModules.append(module)
        }

        // Phase 2: mount status items in stored order so the menu bar matches settings.
        mountMenuBars(orderedIDs: orderStore.orderedIDs(defaultIDs: defaultIDs))

        // Wire callbacks.
        settingsWindowController.onVisibilityChanged = { [weak self] providerID, isVisible in
            guard let self else { return }
            self.visibilityStore.setVisible(isVisible, providerID: providerID)
            self.menuBarsByID[providerID]?.setVisible(isVisible)
            self.pushSnapshotsToSettings(defaultIDs: defaultIDs)
        }

        settingsWindowController.onOrderChanged = { [weak self] newOrder in
            guard let self else { return }
            self.orderStore.setOrder(newOrder)
            self.mountMenuBars(orderedIDs: newOrder)
            self.pushSnapshotsToSettings(defaultIDs: defaultIDs)
        }

        pushSnapshotsToSettings(defaultIDs: defaultIDs)
    }

    func applicationWillTerminate(_ notification: Notification) {
        quotaModules.forEach { $0.unmount() }
    }

    // MARK: Private

    /// Stop all status items, then remount them in `orderedIDs` order.
    /// NSStatusBar places each new item to the LEFT of existing ones, so we
    /// create in REVERSE of the desired left-to-right display order.
    private func mountMenuBars(orderedIDs: [String]) {
        // Remove every current status item.
        for id in menuBarsByID.keys {
            menuBarsByID[id]?.stop()
        }
        // Remount in reverse so the first item in orderedIDs ends up leftmost.
        for id in orderedIDs.reversed() {
            guard let bar = menuBarsByID[id] else { continue }
            bar.start()
            bar.setVisible(visibilityStore.isVisible(providerID: id))
            if let snapshot = snapshots[id] {
                bar.update(snapshot: snapshot)
            }
        }
    }

    private func pushSnapshotsToSettings(defaultIDs: [String]) {
        let orderedIDs = orderStore.orderedIDs(defaultIDs: defaultIDs)
        let vms = orderedIDs.map { id in
            SettingsProviderViewModel(
                providerID: id,
                snapshot: snapshots[id] ?? nil,
                isVisible: visibilityStore.isVisible(providerID: id)
            )
        }
        settingsWindowController.update(viewModels: vms)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
