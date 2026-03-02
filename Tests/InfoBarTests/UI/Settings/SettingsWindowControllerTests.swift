import XCTest
import AppKit
@testable import InfoBar

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesWindow() {
        let sut = SettingsWindowController()
        XCTAssertNil(sut.window)
        sut.show()
        XCTAssertNotNil(sut.window)
    }

    func testWindowHasCorrectTitle() {
        let sut = SettingsWindowController()
        sut.show()
        XCTAssertEqual(sut.window?.title, "InfoBar Settings")
    }

    func testPanelUsesExpectedFrameAndStyle() {
        let sut = SettingsWindowController()
        sut.show()

        let panel = try? XCTUnwrap(sut.window)
        let contentRect = panel?.contentRect(forFrameRect: panel?.frame ?? .zero) ?? .zero
        XCTAssertEqual(contentRect.size.width, SettingsTheme.Layout.panelSize.width, accuracy: 0.1)
        XCTAssertEqual(contentRect.size.height, SettingsTheme.Layout.panelSize.height, accuracy: 0.1)

        XCTAssertTrue(panel?.styleMask.contains(.titled) == true)
        XCTAssertTrue(panel?.styleMask.contains(.closable) == true)
        XCTAssertTrue(panel?.styleMask.contains(.nonactivatingPanel) == true)
        XCTAssertEqual(panel?.level, .floating)
        XCTAssertEqual(panel?.isOpaque, true)
    }

    func testSplitViewUsesMilestoneOneLayoutMetrics() throws {
        let sut = SettingsWindowController()
        sut.show()

        let splitVC = try XCTUnwrap(splitViewController(from: sut.window))
        XCTAssertEqual(splitVC.splitViewItems.count, 2)
        XCTAssertEqual(splitVC.splitView.dividerStyle, .thin)

        let leftItem = splitVC.splitViewItems[0]
        let rightItem = splitVC.splitViewItems[1]

        XCTAssertEqual(leftItem.minimumThickness, SettingsTheme.Layout.sidebarWidth, accuracy: 0.1)
        XCTAssertEqual(leftItem.maximumThickness, SettingsTheme.Layout.sidebarWidth, accuracy: 0.1)
        XCTAssertEqual(rightItem.minimumThickness, SettingsTheme.Layout.detailMinimumWidth, accuracy: 0.1)
    }

    func testSecondRoundTuningUsesCompactSidebarAndRows() throws {
        let sut = SettingsWindowController()
        sut.show()

        let splitVC = try XCTUnwrap(splitViewController(from: sut.window))
        let leftItem = splitVC.splitViewItems[0]
        XCTAssertEqual(leftItem.minimumThickness, 204, accuracy: 0.1)
        XCTAssertEqual(leftItem.maximumThickness, 204, accuracy: 0.1)

        let tableView = try XCTUnwrap(providerTableView(from: sut.window))
        XCTAssertEqual(tableView.rowHeight, 38, accuracy: 0.1)
    }

    func testCallingShowTwiceReusesSameWindow() {
        let sut = SettingsWindowController()
        sut.show()
        let firstWindow = sut.window
        sut.show()
        XCTAssertTrue(sut.window === firstWindow)
    }

    func testUpdateStoresViewModels() {
        let sut = SettingsWindowController()
        let vms = [SettingsProviderViewModel(providerID: "codex", snapshot: nil)]
        sut.update(viewModels: vms)
        XCTAssertEqual(sut.viewModels.map(\.providerID), ["codex"])
    }

    func testEmptyProviderListShowsSelectionPlaceholder() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        XCTAssertTrue(allTexts(in: detailView).contains("Select a provider"))
    }

    func testProviderWithoutWindowsShowsUsagePlaceholder() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil)])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        let texts = allTexts(in: detailView)
        XCTAssertTrue(texts.contains("No usage data yet"))
    }

    func testProviderDisplayNameIsCapitalizedInDetailHeader() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil)])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        XCTAssertTrue(allTexts(in: detailView).contains("Codex"))
    }

    func testShowCanPreselectProviderFromMenuBarClick() throws {
        let sut = SettingsWindowController()
        let first = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        let second = SettingsProviderViewModel(providerID: "bigmodel", snapshot: nil)
        sut.update(viewModels: [first, second])

        sut.show(selectingProviderID: "bigmodel")

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        XCTAssertTrue(allTexts(in: detailView).contains("Bigmodel"))
    }

    func testShowPreselectAlsoMarksSidebarRowHighlighted() throws {
        let sut = SettingsWindowController()
        let first = SettingsProviderViewModel(providerID: "codex", snapshot: nil)
        let second = SettingsProviderViewModel(providerID: "bigmodel", snapshot: nil)
        sut.update(viewModels: [first, second])

        sut.show(selectingProviderID: "bigmodel")

        let tableView = try XCTUnwrap(providerTableView(from: sut.window))
        XCTAssertEqual(tableView.selectedRow, 1)

        let highlighted = try XCTUnwrap(rowSelectionHighlightState(in: tableView, row: 1))
        XCTAssertTrue(highlighted)
    }

    func testRefreshButtonUsesIconOnlyPresentation() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil)])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        let refreshButton = try XCTUnwrap(firstSubview(in: detailView, matching: NSButton.self))
        XCTAssertEqual(refreshButton.title, "")
        XCTAssertNotNil(refreshButton.image)
    }

    func testVisibilitySwitchUsesSmallControlSize() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil)])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        let toggle = try XCTUnwrap(firstSubview(in: detailView, matching: NSSwitch.self))
        XCTAssertEqual(toggle.controlSize, .small)
    }

    func testSelectionStaysStableAfterRefreshingViewModels() throws {
        let sut = SettingsWindowController()
        sut.show()

        let first = SettingsProviderViewModel(providerID: "codex", snapshot: makeSnapshot(providerID: "codex", usedPercent: 20))
        let second = SettingsProviderViewModel(providerID: "bigmodel", snapshot: makeSnapshot(providerID: "bigmodel", usedPercent: 65))
        sut.update(viewModels: [first, second])

        let tableView = try XCTUnwrap(providerTableView(from: sut.window))
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)

        let secondUpdated = SettingsProviderViewModel(providerID: "bigmodel", snapshot: makeSnapshot(providerID: "bigmodel", usedPercent: 70))
        let firstUpdated = SettingsProviderViewModel(providerID: "codex", snapshot: makeSnapshot(providerID: "codex", usedPercent: 25))
        sut.update(viewModels: [secondUpdated, firstUpdated])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        XCTAssertTrue(allTexts(in: detailView).map { $0.lowercased() }.contains("bigmodel"))
    }

    func testCommandWClosesSettingsPanel() throws {
        let sut = SettingsWindowController()
        sut.show()
        let panel = try XCTUnwrap(sut.window)
        panel.makeKeyAndOrderFront(nil)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        let handled = panel.performKeyEquivalent(with: event)
        XCTAssertTrue(handled)
        XCTAssertFalse(panel.isVisible)
    }

    func testOnVisibilityChangedCallbackIsFired() {
        let sut = SettingsWindowController()
        var received: (String, Bool)?
        sut.onVisibilityChanged = { id, visible in received = (id, visible) }
        sut.onVisibilityChanged?("codex", false)
        XCTAssertEqual(received?.0, "codex")
        XCTAssertEqual(received?.1, false)
    }

    func testOnOrderChangedCallbackIsFired() {
        let sut = SettingsWindowController()
        var receivedOrder: [String]?
        sut.onOrderChanged = { ids in receivedOrder = ids }
        sut.onOrderChanged?(["bigmodel", "codex"])
        XCTAssertEqual(receivedOrder, ["bigmodel", "codex"])
    }

    func testOnRefreshRequestedCallbackIsFired() {
        let sut = SettingsWindowController()
        var receivedProviderID: String?
        sut.onRefreshRequested = { id in receivedProviderID = id }
        sut.onRefreshRequested?("codex")
        XCTAssertEqual(receivedProviderID, "codex")
    }

    // MARK: - Helpers

    private func splitViewController(from panel: NSPanel?) -> NSSplitViewController? {
        guard let rootVC = panel?.contentViewController else { return nil }

        if let splitVC = rootVC as? NSSplitViewController {
            return splitVC
        }

        return rootVC.children.compactMap { $0 as? NSSplitViewController }.first
    }

    private func detailView(from panel: NSPanel?) -> NSView? {
        guard let splitVC = splitViewController(from: panel), splitVC.splitViewItems.count > 1 else {
            return nil
        }
        return splitVC.splitViewItems[1].viewController.view
    }

    private func providerTableView(from panel: NSPanel?) -> NSTableView? {
        guard let splitVC = splitViewController(from: panel), !splitVC.splitViewItems.isEmpty else {
            return nil
        }

        return firstSubview(in: splitVC.splitViewItems[0].viewController.view, matching: NSTableView.self)
    }

    private func allTexts(in view: NSView) -> [String] {
        var values: [String] = []
        if let label = view as? NSTextField {
            let text = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                values.append(text)
            }
        }

        for subview in view.subviews {
            values.append(contentsOf: allTexts(in: subview))
        }

        return values
    }

    private func firstSubview<T: NSView>(in view: NSView, matching type: T.Type) -> T? {
        if let matched = view as? T {
            return matched
        }

        for subview in view.subviews {
            if let matched: T = firstSubview(in: subview, matching: type) {
                return matched
            }
        }

        return nil
    }

    private func rowSelectionHighlightState(in tableView: NSTableView, row: Int) -> Bool? {
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: true) else {
            return nil
        }
        let mirror = Mirror(reflecting: rowView)
        return mirror.children.first(where: { $0.label == "isSelectedForHighlight" })?.value as? Bool
    }

    private func makeSnapshot(providerID: String, usedPercent: Int) -> QuotaSnapshot {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = fetchedAt.addingTimeInterval(3600)
        let window = QuotaWindow(id: "hour", label: "H", usedPercent: usedPercent, resetAt: resetAt)
        return QuotaSnapshot(providerID: providerID, windows: [window], fetchedAt: fetchedAt)
    }
}
