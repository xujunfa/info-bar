import AppKit

// MARK: - Public Controller

@MainActor
public final class SettingsWindowController {
    public private(set) var window: NSPanel?
    public private(set) var viewModels: [SettingsProviderViewModel] = []
    public var onVisibilityChanged: ((String, Bool) -> Void)?
    public var onOrderChanged: (([String]) -> Void)?
    public var onRefreshRequested: ((String) -> Void)?

    private weak var listVC: ProviderListViewController?
    private weak var detailVC: ProviderDetailViewController?

    public init() {}

    public func show() {
        if window == nil {
            let (panel, leftVC, rightVC) = makePanel()
            window = panel
            listVC = leftVC
            detailVC = rightVC
        }
        syncCallbacks()
        listVC?.reload(viewModels: viewModels)
        window?.orderFront(nil)
    }

    public func update(viewModels: [SettingsProviderViewModel]) {
        self.viewModels = viewModels
        syncCallbacks()
        listVC?.reload(viewModels: viewModels)
    }

    // MARK: Private

    private func syncCallbacks() {
        listVC?.onOrderChanged = { [weak self] ids in
            self?.onOrderChanged?(ids)
        }
        listVC?.onSelectionChanged = { [weak self] vm in
            self?.detailVC?.configure(viewModel: vm)
        }
        detailVC?.onVisibilityChanged = { [weak self] id, visible in
            self?.onVisibilityChanged?(id, visible)
        }
        detailVC?.onRefreshRequested = { [weak self] id in
            self?.onRefreshRequested?(id)
        }
    }

    private func makePanel() -> (NSPanel, ProviderListViewController, ProviderDetailViewController) {
        let leftVC = ProviderListViewController()
        let rightVC = ProviderDetailViewController()

        let leftItem = NSSplitViewItem(viewController: leftVC)
        leftItem.minimumThickness = SettingsTheme.Layout.sidebarWidth
        leftItem.maximumThickness = SettingsTheme.Layout.sidebarWidth

        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.minimumThickness = SettingsTheme.Layout.detailMinimumWidth

        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin
        splitVC.addSplitViewItem(leftItem)
        splitVC.addSplitViewItem(rightItem)
        splitVC.preferredContentSize = SettingsTheme.Layout.panelSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: SettingsTheme.Layout.panelSize),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "InfoBar Settings"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = splitVC
        panel.center()

        return (panel, leftVC, rightVC)
    }
}

// MARK: - Toggle Switch Bridge

@MainActor
private final class ToggleSwitchBridge: NSObject {
    let providerID: String
    let handler: (String, Bool) -> Void

    init(providerID: String, handler: @escaping (String, Bool) -> Void) {
        self.providerID = providerID
        self.handler = handler
    }

    @objc func toggled(_ sender: NSSwitch) {
        handler(providerID, sender.state == .on)
    }
}

@MainActor
private final class RefreshButtonBridge: NSObject {
    let providerID: String
    let handler: (String) -> Void

    init(providerID: String, handler: @escaping (String) -> Void) {
        self.providerID = providerID
        self.handler = handler
    }

    @objc func refreshClicked(_ sender: NSButton) {
        handler(providerID)
    }
}

// MARK: - Provider List View Controller

private final class ProviderListViewController: NSViewController,
                                                NSTableViewDataSource,
                                                NSTableViewDelegate {

    var onSelectionChanged: ((SettingsProviderViewModel?) -> Void)?
    var onOrderChanged: (([String]) -> Void)?

    private let tableView = NSTableView()
    private var currentViewModels: [SettingsProviderViewModel] = []
    private var selectedProviderID: String?
    private var hoveredRow: Int?

    private static let draggingType = NSPasteboard.PasteboardType("com.infobar.providerRow")

    // MARK: View lifecycle

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("provider"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = SettingsTheme.Layout.listRowHeight
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: SettingsTheme.Layout.listRowSpacing)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.draggingType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = SettingsTheme.Layout.listContentInset
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        view = effectView
    }

    func reload(viewModels: [SettingsProviderViewModel]) {
        let prevID = selectedProviderID
        currentViewModels = viewModels
        hoveredRow = nil
        tableView.reloadData()

        // Restore or initialize selection
        if let prevID, let idx = currentViewModels.firstIndex(where: { $0.providerID == prevID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            // tableViewSelectionDidChange fires -> onSelectionChanged
        } else if !currentViewModels.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            // tableViewSelectionDidChange fires -> onSelectionChanged
        } else {
            selectedProviderID = nil
            onSelectionChanged?(nil)
        }

        applyRowStates()
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        currentViewModels.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let vm = currentViewModels[row]
        let cell = ProviderRowView(frame: .zero)
        cell.configure(viewModel: vm)
        let isSelected = tableView.selectedRowIndexes.contains(row)
        let isHovered = hoveredRow == row
        cell.applyInteractionState(selected: isSelected, hovered: isHovered)
        return cell
    }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ProviderListRowView()
        rowView.onHoverChanged = { [weak self, weak tableView, weak rowView] isHovered in
            guard let self, let tableView, let rowView else { return }
            let row = tableView.row(for: rowView)
            guard row >= 0 else { return }
            if isHovered {
                hoveredRow = row
            } else if hoveredRow == row {
                hoveredRow = nil
            }
            applyRowStates()
        }
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < currentViewModels.count {
            selectedProviderID = currentViewModels[row].providerID
            onSelectionChanged?(currentViewModels[row])
        } else {
            selectedProviderID = nil
            onSelectionChanged?(nil)
        }

        // Keep hover state in sync after click-based selection changes.
        let mouseLocation = tableView.convert(tableView.window?.mouseLocationOutsideOfEventStream ?? .zero,
                                              from: nil)
        let rowUnderPointer = tableView.row(at: mouseLocation)
        hoveredRow = rowUnderPointer >= 0 ? rowUnderPointer : nil

        applyRowStates()
    }

    // MARK: Drag & Drop

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.draggingType)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: any NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: any NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let str = info.draggingPasteboard.string(forType: Self.draggingType),
              let fromRow = Int(str),
              fromRow != row,
              fromRow < currentViewModels.count else { return false }

        let adjustedRow = fromRow < row ? row - 1 : row

        var newModels = currentViewModels
        let moved = newModels.remove(at: fromRow)
        newModels.insert(moved, at: adjustedRow)
        currentViewModels = newModels

        tableView.beginUpdates()
        tableView.moveRow(at: fromRow, to: adjustedRow)
        tableView.endUpdates()

        onOrderChanged?(currentViewModels.map(\.providerID))

        // Restore selection to the moved row.
        if let selID = selectedProviderID,
           let newIdx = currentViewModels.firstIndex(where: { $0.providerID == selID }) {
            tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
        }

        applyRowStates()
        return true
    }

    // MARK: Private

    private func applyRowStates() {
        guard tableView.numberOfRows > 0 else { return }

        for row in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ProviderRowView else {
                continue
            }
            let isSelected = tableView.selectedRowIndexes.contains(row)
            let isHovered = hoveredRow == row
            cell.applyInteractionState(selected: isSelected, hovered: isHovered)
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? ProviderListRowView {
                rowView.isSelectedForHighlight = isSelected
                rowView.isHoveredForHighlight = isHovered
            }
        }
    }
}

private final class ProviderListRowView: NSTableRowView {
    var onHoverChanged: ((Bool) -> Void)?
    var isSelectedForHighlight = false {
        didSet {
            guard oldValue != isSelectedForHighlight else { return }
            needsDisplay = true
        }
    }
    var isHoveredForHighlight = false {
        didSet {
            guard oldValue != isHoveredForHighlight else { return }
            needsDisplay = true
        }
    }

    private var trackingAreaRef: NSTrackingArea?

    override func drawSelection(in dirtyRect: NSRect) {
        // Custom selection drawing in drawBackground.
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        let fillColor: NSColor
        if isSelectedForHighlight {
            fillColor = SettingsTheme.Color.rowSelectedBackground
        } else if isHoveredForHighlight {
            fillColor = SettingsTheme.Color.rowHoverBackground
        } else {
            return
        }

        let rect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: SettingsTheme.Radius.row,
            yRadius: SettingsTheme.Radius.row
        )
        fillColor.setFill()
        path.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }
}

// MARK: - Provider Row View

private final class ProviderRowView: NSTableCellView {
    private let dragHandle = NSImageView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()

    private var statusColor = SettingsTheme.Color.statusHidden

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setup() {
        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal",
                                   accessibilityDescription: "Drag to reorder")
        dragHandle.imageScaling = .scaleProportionallyDown
        dragHandle.contentTintColor = SettingsTheme.Color.tertiaryText
        dragHandle.alphaValue = 0.2
        dragHandle.toolTip = "Drag to reorder providers"
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = SettingsTheme.Color.secondaryText
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = SettingsTheme.Radius.icon
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = SettingsTheme.Typography.providerName
        nameLabel.textColor = SettingsTheme.Color.primaryText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = SettingsTheme.Radius.statusDot
        statusDot.layer?.borderColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        statusDot.layer?.borderWidth = 1
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dragHandle)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(statusDot)

        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsTheme.Layout.listCellHorizontalInset),
            dragHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 16),
            dragHandle.heightAnchor.constraint(equalToConstant: 16),

            iconView.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusDot.leadingAnchor,
                                                constant: -8),

            statusDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            statusDot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 9),
            statusDot.heightAnchor.constraint(equalToConstant: 9),
        ])
    }

    func configure(viewModel: SettingsProviderViewModel) {
        nameLabel.stringValue = providerDisplayName(for: viewModel.providerID)
        iconView.image = providerIconImage(for: viewModel.providerID)

        let hasCriticalUsage = viewModel.windows.contains { $0.usedPercent >= 90 }
        if !viewModel.isVisible {
            statusColor = SettingsTheme.Color.statusHidden
            statusDot.toolTip = "Hidden from menu bar"
        } else if hasCriticalUsage {
            statusColor = SettingsTheme.Color.statusWarning
            statusDot.toolTip = "High quota usage"
        } else {
            statusColor = SettingsTheme.Color.statusVisible
            statusDot.toolTip = "Visible in menu bar"
        }

        statusDot.layer?.backgroundColor = statusColor.cgColor
    }

    func applyInteractionState(selected: Bool, hovered: Bool) {
        let emphasized = selected || hovered
        dragHandle.alphaValue = emphasized ? 0.85 : 0.2
        dragHandle.contentTintColor = emphasized ? SettingsTheme.Color.primaryText : SettingsTheme.Color.tertiaryText

        iconView.contentTintColor = emphasized ? SettingsTheme.Color.primaryText : SettingsTheme.Color.secondaryText
        nameLabel.textColor = emphasized ? SettingsTheme.Color.primaryText : SettingsTheme.Color.secondaryText

        statusDot.layer?.backgroundColor = statusColor.cgColor
        statusDot.layer?.borderWidth = emphasized ? 1.2 : 1
    }
}

// MARK: - Provider Detail View Controller

private final class ProviderDetailViewController: NSViewController {
    var onVisibilityChanged: ((String, Bool) -> Void)?
    var onRefreshRequested: ((String) -> Void)?
    private var toggleBridge: ToggleSwitchBridge?
    private var refreshBridge: RefreshButtonBridge?

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .contentBackground
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        view = effectView
    }

    func configure(viewModel: SettingsProviderViewModel?) {
        view.subviews.forEach { $0.removeFromSuperview() }
        toggleBridge = nil
        refreshBridge = nil

        guard let vm = viewModel else {
            let placeholder = makeSelectionPlaceholderView()
            view.addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor,
                                                     constant: SettingsTheme.Layout.contentInset),
                placeholder.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                      constant: -SettingsTheme.Layout.contentInset),
                placeholder.widthAnchor.constraint(lessThanOrEqualToConstant: SettingsTheme.Layout.placeholderMaxWidth),
            ])
            return
        }

        buildDetail(vm: vm)
    }

    // MARK: Private

    private func buildDetail(vm: SettingsProviderViewModel) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: SettingsTheme.Layout.contentInset),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsTheme.Layout.contentInset),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsTheme.Layout.contentInset),
            container.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor,
                                              constant: -SettingsTheme.Layout.contentInset),
        ])

        let headerView = makeHeader(vm: vm)
        container.addArrangedSubview(headerView)
        headerView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(16, after: headerView)

        let divider1 = makeDivider()
        container.addArrangedSubview(divider1)
        divider1.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(12, after: divider1)

        let usageLabel = NSTextField(labelWithString: "USAGE")
        usageLabel.font = SettingsTheme.Typography.section
        usageLabel.textColor = SettingsTheme.Color.secondaryText
        container.addArrangedSubview(usageLabel)
        container.setCustomSpacing(8, after: usageLabel)

        if vm.windows.isEmpty {
            let placeholder = makeUsagePlaceholderView(fetchedAt: vm.fetchedAt)
            container.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            container.setCustomSpacing(12, after: placeholder)
        } else {
            for window in vm.windows {
                let row = makeWindowRow(window: window)
                container.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
                container.setCustomSpacing(6, after: row)
            }
            container.setCustomSpacing(12, after: container.arrangedSubviews.last ?? usageLabel)
        }

        let divider2 = makeDivider()
        container.addArrangedSubview(divider2)
        divider2.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(12, after: divider2)

        let toggleRow = makeToggleRow(vm: vm)
        container.addArrangedSubview(toggleRow)
        toggleRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    private func makeSelectionPlaceholderView() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        icon.contentTintColor = SettingsTheme.Color.tertiaryText

        let titleLabel = NSTextField(labelWithString: "Select a provider")
        titleLabel.font = SettingsTheme.Typography.placeholderTitle
        titleLabel.textColor = SettingsTheme.Color.primaryText

        let subtitleLabel = NSTextField(wrappingLabelWithString: "Choose a provider in the left list to inspect usage windows, refresh data, and toggle menu visibility.")
        subtitleLabel.font = SettingsTheme.Typography.body
        subtitleLabel.textColor = SettingsTheme.Color.secondaryText
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [icon, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8

        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = SettingsTheme.Radius.placeholder
        card.layer?.backgroundColor = SettingsTheme.Color.placeholderBackground.cgColor
        card.layer?.borderColor = SettingsTheme.Color.placeholderBorder.cgColor
        card.layer?.borderWidth = 1
        card.shadow = SettingsTheme.Shadow.subtle()
        card.translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        return card
    }

    private func makeUsagePlaceholderView(fetchedAt: Date?) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        icon.contentTintColor = SettingsTheme.Color.tertiaryText

        let titleLabel = NSTextField(labelWithString: "No usage data yet")
        titleLabel.font = SettingsTheme.Typography.providerName
        titleLabel.textColor = SettingsTheme.Color.primaryText

        let subtitle: String
        if fetchedAt == nil {
            subtitle = "Run Refresh to load the first quota snapshot for this provider."
        } else {
            subtitle = "Latest snapshot did not include window metrics."
        }
        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = SettingsTheme.Typography.caption
        subtitleLabel.textColor = SettingsTheme.Color.secondaryText
        subtitleLabel.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let rowStack = NSStackView(views: [icon, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10

        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = SettingsTheme.Radius.placeholder
        card.layer?.backgroundColor = SettingsTheme.Color.placeholderBackground.cgColor
        card.layer?.borderColor = SettingsTheme.Color.placeholderBorder.cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false

        rowStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            rowStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            rowStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsTheme.Layout.usagePlaceholderHeight),
        ])

        return card
    }

    private func makeHeader(vm: SettingsProviderViewModel) -> NSView {
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = SettingsTheme.Radius.icon
        iconView.layer?.masksToBounds = true
        iconView.image = providerIconImage(for: vm.providerID)
        iconView.contentTintColor = SettingsTheme.Color.primaryText
        iconView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
        ])

        let nameLabel = NSTextField(labelWithString: providerDisplayName(for: vm.providerID))
        nameLabel.font = SettingsTheme.Typography.providerTitle
        nameLabel.textColor = SettingsTheme.Color.primaryText

        let updatedText: String
        if let fetchedAt = vm.fetchedAt {
            updatedText = "Updated: \(formatAgo(from: fetchedAt))"
        } else {
            updatedText = "Updated: waiting for first snapshot"
        }
        let updatedLabel = NSTextField(labelWithString: updatedText)
        updatedLabel.font = SettingsTheme.Typography.caption
        updatedLabel.textColor = SettingsTheme.Color.secondaryText

        let titleStack = NSStackView(views: [nameLabel, updatedLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        let refreshImage = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Refresh usage"
        ) ?? NSImage()
        refreshImage.isTemplate = true

        let refreshButton = NSButton(image: refreshImage, target: nil, action: nil)
        refreshButton.title = ""
        refreshButton.imagePosition = .imageOnly
        refreshButton.bezelStyle = .texturedRounded
        refreshButton.controlSize = .small
        refreshButton.toolTip = "Refresh usage"

        let bridge = RefreshButtonBridge(providerID: vm.providerID) { [weak self] id in
            self?.onRefreshRequested?(id)
        }
        refreshButton.target = bridge
        refreshButton.action = #selector(RefreshButtonBridge.refreshClicked(_:))
        refreshBridge = bridge

        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [iconView, titleStack, spacer, refreshButton])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        return headerStack
    }

    private func makeWindowRow(window: SettingsProviderViewModel.WindowViewModel) -> NSView {
        let label = NSTextField(labelWithString: window.label)
        label.font = SettingsTheme.Typography.usageLabel
        label.textColor = SettingsTheme.Color.primaryText
        label.setContentHuggingPriority(.required, for: .horizontal)

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.controlSize = .small
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = Double(window.usedPercent)
        progress.isIndeterminate = false
        progress.translatesAutoresizingMaskIntoConstraints = false

        let percentLabel = NSTextField(labelWithString: "\(window.usedPercent)%")
        percentLabel.font = SettingsTheme.Typography.usageLabel
        percentLabel.textColor = SettingsTheme.Color.primaryText
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)

        let timeLabel = NSTextField(labelWithString: "(\(window.timeLeft) left)")
        timeLabel.font = SettingsTheme.Typography.caption
        timeLabel.textColor = SettingsTheme.Color.secondaryText
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, progress, percentLabel, timeLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        NSLayoutConstraint.activate([
            progress.heightAnchor.constraint(equalToConstant: 8),
        ])

        return row
    }

    private func makeToggleRow(vm: SettingsProviderViewModel) -> NSView {
        let toggleLabel = NSTextField(labelWithString: "Show in menu bar")
        toggleLabel.font = SettingsTheme.Typography.body
        toggleLabel.textColor = SettingsTheme.Color.primaryText

        let toggle = NSSwitch()
        toggle.state = vm.isVisible ? .on : .off
        toggle.controlSize = .small

        let bridge = ToggleSwitchBridge(providerID: vm.providerID) { [weak self] id, visible in
            self?.onVisibilityChanged?(id, visible)
        }
        toggle.target = bridge
        toggle.action = #selector(ToggleSwitchBridge.toggled(_:))
        toggleBridge = bridge

        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [toggleLabel, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
    }

    private func formatAgo(from date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "just now" }
        let minutes = diff / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

private func providerIconImage(for providerID: String,
                               fallbackSystemSymbol: String = "circle.fill") -> NSImage {
    if let url = Bundle.module.url(forResource: providerID,
                                   withExtension: "svg",
                                   subdirectory: "Resources/Icons"),
       let image = NSImage(contentsOf: url) {
        image.isTemplate = true
        return image
    }

    return NSImage(systemSymbolName: fallbackSystemSymbol, accessibilityDescription: nil) ?? NSImage()
}

private func providerDisplayName(for providerID: String) -> String {
    guard let first = providerID.first else { return providerID }
    return first.uppercased() + providerID.dropFirst()
}
