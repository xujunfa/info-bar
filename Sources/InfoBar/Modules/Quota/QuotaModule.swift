import Foundation

public final class QuotaModule: Module {
    private let reader: QuotaReader
    private var widgets: [QuotaWidget] = []

    public init(reader: QuotaReader = QuotaReader()) {
        self.reader = reader
        super.init()
        self.reader.callback = { [weak self] snapshot in
            self?.loadCallback(snapshot)
        }
    }

    public func setWidgets(_ widgets: [QuotaWidget]) {
        self.widgets = widgets
    }

    private func loadCallback(_ snapshot: QuotaSnapshot?) {
        self.widgets.filter { $0.isActive }.forEach { $0.setSnapshot(snapshot) }
    }
}
