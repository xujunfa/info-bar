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
        XCTAssertEqual(tableView.rowHeight, 46, accuracy: 0.1)
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
        XCTAssertTrue(allTexts(in: detailView).contains("ID: codex"))
        XCTAssertFalse(allTexts(in: detailView).contains("Visible"))
    }

    func testDetailHeaderShowsAccountInfoBesideIDWhenAvailable() throws {
        let sut = SettingsWindowController()
        sut.show()
        let now = Date()
        let window = QuotaWindow(
            id: "w",
            label: "W",
            usedPercent: 10,
            resetAt: now.addingTimeInterval(600),
            metadata: ["email": "dev@example.com"]
        )
        let vm = SettingsProviderViewModel(
            providerID: "codex",
            snapshot: QuotaSnapshot(providerID: "codex", windows: [window], fetchedAt: now),
            now: now
        )
        sut.update(viewModels: [vm])

        let detailView = try XCTUnwrap(detailView(from: sut.window))
        let texts = allTexts(in: detailView)
        XCTAssertTrue(texts.contains(where: { $0.contains("ID: codex") && $0.contains("Account: dev@example.com") }))
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
        let refreshButton = try XCTUnwrap(refreshButton(in: detailView))
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
        XCTAssertFalse(allTexts(in: detailView).contains("Show in menu bar"))
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

    func testSidebarRowShowsUsageSummaryAndStatusText() throws {
        let sut = SettingsWindowController()
        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(
            providerID: "codex",
            snapshot: makeSnapshot(providerID: "codex", usedPercent: 42),
            isVisible: true
        )])

        let tableView = try XCTUnwrap(providerTableView(from: sut.window))
        let rowView = try XCTUnwrap(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let texts = allTexts(in: rowView)
        XCTAssertTrue(texts.contains("Codex"))
        XCTAssertTrue(texts.contains(where: { $0.hasPrefix("Updated: ") }))
        XCTAssertFalse(texts.contains("Visible"))
        XCTAssertNotNil(firstSubview(in: rowView, matchingToolTip: "Visible in menu bar"))
    }

    func testUsageCardShowsMetricsAndMetadata() throws {
        let sut = SettingsWindowController()
        sut.show()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = QuotaWindow(
            id: "weekly",
            label: "W",
            usedPercent: 60,
            resetAt: now.addingTimeInterval(3700),
            used: 6_000,
            limit: 10_000,
            unit: "tokens",
            windowTitle: "Weekly Window",
            metadata: [
                "model_name": "MiniMax-M2",
                "period_type": "weekly",
                "hook": "fetch",
            ]
        )
        let vm = SettingsProviderViewModel(
            providerID: "minimax",
            snapshot: QuotaSnapshot(providerID: "minimax", windows: [window], fetchedAt: now),
            now: now
        )
        sut.update(viewModels: [vm])

        let detail = try XCTUnwrap(detailView(from: sut.window))
        let texts = allTexts(in: detail)
        XCTAssertTrue(texts.contains("USAGE WINDOWS"))
        XCTAssertTrue(texts.contains("USED"))
        XCTAssertTrue(texts.contains("REMAINING"))
        XCTAssertTrue(texts.contains("LIMIT"))
        XCTAssertTrue(texts.contains("TOKENS (M)"))
        XCTAssertTrue(texts.contains("6K tokens"))
        XCTAssertTrue(texts.contains("4K tokens"))
        XCTAssertTrue(texts.contains("10K tokens"))
        XCTAssertTrue(texts.contains("0.006M"))
        XCTAssertTrue(texts.contains(where: { $0.hasPrefix("resets at ") }))
        XCTAssertFalse(texts.contains(where: { $0.contains("Model:") || $0.contains("Source:") || $0.contains("Trace:") }))
    }

    func testUsageCardOmitsUnavailableMetricsInsteadOfDashPlaceholders() throws {
        let sut = SettingsWindowController()
        sut.show()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = QuotaWindow(
            id: "session",
            label: "S",
            usedPercent: 15,
            resetAt: now.addingTimeInterval(1200),
            used: 150,
            unit: "requests"
        )
        let vm = SettingsProviderViewModel(
            providerID: "codex",
            snapshot: QuotaSnapshot(providerID: "codex", windows: [window], fetchedAt: now),
            now: now
        )
        sut.update(viewModels: [vm])

        let detail = try XCTUnwrap(detailView(from: sut.window))
        let texts = allTexts(in: detail)
        XCTAssertFalse(texts.contains("REMAINING"))
        XCTAssertFalse(texts.contains("LIMIT"))
        XCTAssertFalse(texts.contains("—"))
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

    func testRefreshButtonCallbackChainUsesSelectedProviderID() throws {
        let sut = SettingsWindowController()
        var receivedProviderID: String?
        sut.onRefreshRequested = { id in receivedProviderID = id }

        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil)])

        let detail = try XCTUnwrap(detailView(from: sut.window))
        let refresh = try XCTUnwrap(refreshButton(in: detail))
        let loadingIndicator = try XCTUnwrap(refreshLoadingIndicator(in: detail))
        refresh.performClick(nil)

        XCTAssertEqual(receivedProviderID, "codex")
        XCTAssertTrue(refresh.isHidden)
        XCTAssertFalse(loadingIndicator.isHidden)
    }

    func testVisibilityToggleCallbackChainSendsUpdatedState() throws {
        let sut = SettingsWindowController()
        var received: (String, Bool)?
        sut.onVisibilityChanged = { id, visible in received = (id, visible) }

        sut.show()
        sut.update(viewModels: [SettingsProviderViewModel(providerID: "codex", snapshot: nil, isVisible: true)])

        let detail = try XCTUnwrap(detailView(from: sut.window))
        let toggle = try XCTUnwrap(firstSubview(in: detail, matching: NSSwitch.self))
        toggle.performClick(nil)

        XCTAssertEqual(received?.0, "codex")
        XCTAssertEqual(received?.1, false)
    }

    func testSelectionRemainsWhenClearingSelectionOnNonEmptyList() throws {
        let sut = SettingsWindowController()
        sut.show()
        let first = SettingsProviderViewModel(providerID: "codex", snapshot: makeSnapshot(providerID: "codex", usedPercent: 20))
        let second = SettingsProviderViewModel(providerID: "bigmodel", snapshot: makeSnapshot(providerID: "bigmodel", usedPercent: 50))
        sut.update(viewModels: [first, second])

        let tableView = try XCTUnwrap(providerTableView(from: sut.window))
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)

        XCTAssertEqual(tableView.selectedRow, 1)
        let detail = try XCTUnwrap(detailView(from: sut.window))
        XCTAssertTrue(allTexts(in: detail).contains("Bigmodel"))
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

    private func firstSubview(in view: NSView, matchingToolTip toolTip: String) -> NSView? {
        if view.toolTip == toolTip {
            return view
        }
        for subview in view.subviews {
            if let matched = firstSubview(in: subview, matchingToolTip: toolTip) {
                return matched
            }
        }
        return nil
    }

    private func refreshButton(in view: NSView) -> NSButton? {
        allButtons(in: view).first { button in
            button.toolTip == "Refresh usage"
        }
    }

    private func refreshLoadingIndicator(in view: NSView) -> NSProgressIndicator? {
        allIndicators(in: view).first { indicator in
            indicator.style == .spinning
        }
    }

    private func allButtons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton {
            buttons.append(button)
        }
        for subview in view.subviews {
            buttons.append(contentsOf: allButtons(in: subview))
        }
        return buttons
    }

    private func allIndicators(in view: NSView) -> [NSProgressIndicator] {
        var indicators: [NSProgressIndicator] = []
        if let indicator = view as? NSProgressIndicator {
            indicators.append(indicator)
        }
        for subview in view.subviews {
            indicators.append(contentsOf: allIndicators(in: subview))
        }
        return indicators
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
