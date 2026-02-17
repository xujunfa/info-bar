import Foundation

public final class QuotaReader: Reader<QuotaSnapshot> {
    private let fetcher: QuotaSnapshotFetching

    public init(
        fetcher: QuotaSnapshotFetching = CodexUsageClient(),
        callback: @escaping Callback = { _ in }
    ) {
        self.fetcher = fetcher
        super.init(interval: 300, popup: false, callback: callback)
    }

    public override func read() {
        do {
            let snapshot = try fetcher.fetchSnapshot()
            callback(snapshot)
        } catch {
            callback(nil)
        }
    }
}
