import XCTest
@testable import InfoBar

final class AppBootstrapTests: XCTestCase {
    func testBootstrapProvidesStatusTitle() {
        XCTAssertEqual(AppBootstrap.statusTitle, "InfoBar")
    }
}
