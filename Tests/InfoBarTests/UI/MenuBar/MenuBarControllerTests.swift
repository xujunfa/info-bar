import XCTest
@testable import InfoBar

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testOnClickedCallbackCanBeSetAndInvoked() {
        let sut = MenuBarController(providerID: "test")
        var wasCalled = false
        sut.onClicked = { wasCalled = true }
        sut.onClicked?()
        XCTAssertTrue(wasCalled)
    }
}
