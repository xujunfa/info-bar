import XCTest
@testable import InfoBar

final class QuotaLayoutMetricsTests: XCTestCase {
    func testTextStartsAfterIconArea() {
        let iconMaxX = QuotaLayoutMetrics.iconX + QuotaLayoutMetrics.iconSize
        XCTAssertGreaterThan(QuotaLayoutMetrics.textX, iconMaxX)
        XCTAssertGreaterThan(QuotaLayoutMetrics.statusWidth, QuotaLayoutMetrics.textX)
    }

    func testTextAreaHasEnoughWidthForDurationSuffix() {
        let textAreaWidth = QuotaLayoutMetrics.statusWidth - QuotaLayoutMetrics.textX - 2
        XCTAssertGreaterThanOrEqual(textAreaWidth, 80)
    }
}
