import XCTest
import AppKit
@testable import InfoBar

final class QuotaStatusViewDrawingTests: XCTestCase {
    func testQuotaStatusViewDrawingDoesNotCrash() {
        let view = QuotaStatusView(frame: NSRect(x: 0, y: 0, width: 100, height: 20), providerID: "minimax")
        
        let resetAt = Date().addingTimeInterval(3600)
        let window1 = QuotaWindow(id: "h", label: "H", usedPercent: 10, resetAt: resetAt)
        let snapshot = QuotaSnapshot(providerID: "minimax", windows: [window1], fetchedAt: Date())
        let model = QuotaDisplayModel(snapshot: snapshot)
        
        view.update(model: model)
        
        // This should not crash
        view.draw(view.bounds)
    }
}
