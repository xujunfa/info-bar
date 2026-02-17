import AppKit
import Foundation
import InfoBar

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBars: [MenuBarController] = []
    private var quotaWidgets: [QuotaWidget] = []
    private var quotaModules: [QuotaModule] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        for provider in QuotaProviderRegistry.defaultProviders() {
            let menuBar = MenuBarController()
            let widget = QuotaWidget()
            let reader = QuotaReader(fetcher: provider.makeFetcher())
            let module = QuotaModule(reader: reader)

            widget.onSnapshot = { [weak menuBar] snapshot in
                Task { @MainActor in
                    menuBar?.update(snapshot: snapshot)
                }
            }
            module.setWidgets([widget])
            menuBar.start()
            module.mount()

            menuBars.append(menuBar)
            quotaWidgets.append(widget)
            quotaModules.append(module)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        quotaModules.forEach { $0.unmount() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
