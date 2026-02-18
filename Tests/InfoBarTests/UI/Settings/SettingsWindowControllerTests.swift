import XCTest
import AppKit
@testable import InfoBar

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowCreatesWindow() {
        let sut = SettingsWindowController()
        XCTAssertNil(sut.window)
        sut.show()
        XCTAssertNotNil(sut.window)
    }

    func testWindowHasCorrectTitle() {
        let sut = SettingsWindowController()
        sut.show()
        XCTAssertEqual(sut.window?.title, "InfoBar Settings")
    }

    func testCallingShowTwiceReusesSameWindow() {
        let sut = SettingsWindowController()
        sut.show()
        let firstWindow = sut.window
        sut.show()
        XCTAssertTrue(sut.window === firstWindow)
    }

    func testUpdateStoresViewModels() {
        let sut = SettingsWindowController()
        let vms = [SettingsProviderViewModel(providerID: "codex", snapshot: nil)]
        sut.update(viewModels: vms)
        XCTAssertEqual(sut.viewModels.map(\.providerID), ["codex"])
    }

    func testOnVisibilityChangedCallbackIsFired() {
        let sut = SettingsWindowController()
        var received: (String, Bool)?
        sut.onVisibilityChanged = { id, visible in received = (id, visible) }
        sut.onVisibilityChanged?("codex", false)
        XCTAssertEqual(received?.0, "codex")
        XCTAssertEqual(received?.1, false)
    }

    func testOnOrderChangedCallbackIsFired() {
        let sut = SettingsWindowController()
        var receivedOrder: [String]?
        sut.onOrderChanged = { ids in receivedOrder = ids }
        sut.onOrderChanged?(["bigmodel", "codex"])
        XCTAssertEqual(receivedOrder, ["bigmodel", "codex"])
    }
}
