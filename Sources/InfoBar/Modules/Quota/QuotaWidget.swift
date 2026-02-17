import Foundation

public final class QuotaWidget: Widget {
    public private(set) var lastSnapshot: QuotaSnapshot?

    public func setSnapshot(_ snapshot: QuotaSnapshot?) {
        self.lastSnapshot = snapshot
        setValue(snapshot)
    }
}
