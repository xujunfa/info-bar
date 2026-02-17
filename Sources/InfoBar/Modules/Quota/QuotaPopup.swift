import Foundation

public final class QuotaPopup: Popup {
    public private(set) var snapshot: QuotaSnapshot?

    public func render(_ snapshot: QuotaSnapshot?) {
        self.snapshot = snapshot
    }
}
