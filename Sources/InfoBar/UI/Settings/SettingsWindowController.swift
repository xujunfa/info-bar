import AppKit

// MARK: - Public Controller

@MainActor
public final class SettingsWindowController {
    public private(set) var window: NSPanel?
    public private(set) var viewModels: [SettingsProviderViewModel] = []
    public var onVisibilityChanged: ((String, Bool) -> Void)?
    public var onOrderChanged: (([String]) -> Void)?

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
    }

    private func makePanel() -> (NSPanel, ProviderListViewController, ProviderDetailViewController) {
        let leftVC = ProviderListViewController()
        let rightVC = ProviderDetailViewController()

        let leftItem = NSSplitViewItem(viewController: leftVC)
        leftItem.minimumThickness = 200
        leftItem.maximumThickness = 200

        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.minimumThickness = 300

        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin
        splitVC.addSplitViewItem(leftItem)
        splitVC.addSplitViewItem(rightItem)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "InfoBar Settings"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Set preferredContentSize before assigning contentViewController:
        // otherwise AppKit resizes the window to the VC's preferredContentSize,
        // which defaults to NSZeroSize and collapses the panel to a title bar.
        splitVC.preferredContentSize = NSSize(width: 640, height: 440)
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

// MARK: - Provider List View Controller

private final class ProviderListViewController: NSViewController,
                                                NSTableViewDataSource,
                                                NSTableViewDelegate {

    var onSelectionChanged: ((SettingsProviderViewModel?) -> Void)?
    var onOrderChanged: (([String]) -> Void)?

    private let tableView = NSTableView()
    private var currentViewModels: [SettingsProviderViewModel] = []
    private var selectedProviderID: String?

    private static let draggingType = NSPasteboard.PasteboardType("com.infobar.providerRow")

    // MARK: View lifecycle

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("provider"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.draggingType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        view = scrollView
    }

    func reload(viewModels: [SettingsProviderViewModel]) {
        let prevID = selectedProviderID
        currentViewModels = viewModels
        tableView.reloadData()

        // Restore or initialize selection
        if let prevID, let idx = currentViewModels.firstIndex(where: { $0.providerID == prevID }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            // tableViewSelectionDidChange fires → onSelectionChanged
        } else if !currentViewModels.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            // tableViewSelectionDidChange fires → onSelectionChanged
        } else {
            selectedProviderID = nil
            onSelectionChanged?(nil)
        }
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
        return cell
    }

    // MARK: NSTableViewDelegate

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0, row < currentViewModels.count {
            selectedProviderID = currentViewModels[row].providerID
            onSelectionChanged?(currentViewModels[row])
        } else {
            selectedProviderID = nil
            onSelectionChanged?(nil)
        }
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

        // Restore selection to the moved row
        if let selID = selectedProviderID,
           let newIdx = currentViewModels.firstIndex(where: { $0.providerID == selID }) {
            tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
        }
        return true
    }
}

// MARK: - Provider Row View

private final class ProviderRowView: NSTableCellView {
    private let dragHandle = NSImageView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setup() {
        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal",
                                   accessibilityDescription: nil)
        dragHandle.imageScaling = .scaleProportionallyDown
        dragHandle.contentTintColor = .tertiaryLabelColor
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dragHandle)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(statusDot)

        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
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

            statusDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    func configure(viewModel: SettingsProviderViewModel) {
        nameLabel.stringValue = viewModel.providerID

        if let url = Bundle.module.url(forResource: viewModel.providerID,
                                       withExtension: "svg",
                                       subdirectory: "Resources/Icons"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            iconView.image = image
        } else {
            iconView.image = NSImage(systemSymbolName: "circle.fill",
                                     accessibilityDescription: nil)
        }

        statusDot.layer?.backgroundColor = viewModel.isVisible
            ? NSColor.systemGreen.cgColor
            : NSColor.tertiaryLabelColor.cgColor
    }
}

// MARK: - Provider Detail View Controller

private final class ProviderDetailViewController: NSViewController {
    var onVisibilityChanged: ((String, Bool) -> Void)?
    private var toggleBridge: ToggleSwitchBridge?

    override func loadView() {
        view = NSView()
    }

    func configure(viewModel: SettingsProviderViewModel?) {
        // Remove all existing subviews
        view.subviews.forEach { $0.removeFromSuperview() }
        toggleBridge = nil

        guard let vm = viewModel else {
            let label = NSTextField(labelWithString: "Select a provider")
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
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
        // Padding lives in the anchor offsets below, NOT in edgeInsets.
        // That way container.widthAnchor == usable content width, and
        // all "row.widthAnchor == container.widthAnchor" constraints are exact.
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        // Header: icon + name + updated
        let headerView = makeHeader(vm: vm)
        container.addArrangedSubview(headerView)
        headerView.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(16, after: headerView)

        // Divider 1
        let divider1 = makeDivider()
        container.addArrangedSubview(divider1)
        divider1.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        container.setCustomSpacing(12, after: divider1)

        // Usage section
        if !vm.windows.isEmpty {
            let usageLabel = NSTextField(labelWithString: "USAGE")
            usageLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            usageLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(usageLabel)
            container.setCustomSpacing(8, after: usageLabel)

            for window in vm.windows {
                let row = makeWindowRow(window: window)
                container.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
                container.setCustomSpacing(6, after: row)
            }
            container.setCustomSpacing(12, after: container.arrangedSubviews.last ?? usageLabel)

            let divider2 = makeDivider()
            container.addArrangedSubview(divider2)
            divider2.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            container.setCustomSpacing(12, after: divider2)
        }

        // Toggle row
        let toggleRow = makeToggleRow(vm: vm)
        container.addArrangedSubview(toggleRow)
        toggleRow.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    private func makeHeader(vm: SettingsProviderViewModel) -> NSView {
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
        ])

        if let url = Bundle.module.url(forResource: vm.providerID,
                                       withExtension: "svg",
                                       subdirectory: "Resources/Icons"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            iconView.image = image
        } else {
            iconView.image = NSImage(systemSymbolName: "circle.fill",
                                     accessibilityDescription: nil)
        }

        let nameLabel = NSTextField(labelWithString: vm.providerID)
        nameLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let updatedText: String
        if let fetchedAt = vm.fetchedAt {
            updatedText = "Updated: \(formatAgo(from: fetchedAt))"
        } else {
            updatedText = "No data yet"
        }
        let updatedLabel = NSTextField(labelWithString: updatedText)
        updatedLabel.font = .systemFont(ofSize: 11)
        updatedLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [nameLabel, updatedLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let headerStack = NSStackView(views: [iconView, titleStack])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        return headerStack
    }

    private func makeWindowRow(window: SettingsProviderViewModel.WindowViewModel) -> NSView {
        let label = NSTextField(labelWithString: window.label)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
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
        percentLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)

        let timeLabel = NSTextField(labelWithString: "(\(window.timeLeft) left)")
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, progress, percentLabel, timeLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeToggleRow(vm: SettingsProviderViewModel) -> NSView {
        let toggleLabel = NSTextField(labelWithString: "Show in menu bar")
        toggleLabel.font = .systemFont(ofSize: 13)

        let toggle = NSSwitch()
        toggle.state = vm.isVisible ? .on : .off

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
        let box = NSBox()
        box.boxType = .separator
        return box
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
