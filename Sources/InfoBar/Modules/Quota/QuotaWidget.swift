import Foundation

public final class QuotaWidget: Widget {
    public private(set) var lastSnapshot: QuotaSnapshot?
    public var onSnapshot: ((QuotaSnapshot?) -> Void)?

    public func setSnapshot(_ snapshot: QuotaSnapshot?) {
        self.lastSnapshot = snapshot
        setValue(snapshot)
        onSnapshot?(snapshot)
    }
}
