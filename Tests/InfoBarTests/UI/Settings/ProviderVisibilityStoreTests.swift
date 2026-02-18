import XCTest
@testable import InfoBar

final class ProviderVisibilityStoreTests: XCTestCase {
    private func makeSUT() -> ProviderVisibilityStore {
        // Use an isolated suite so tests don't pollute standard UserDefaults.
        ProviderVisibilityStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testDefaultVisibilityIsTrue() {
        XCTAssertTrue(makeSUT().isVisible(providerID: "codex"))
    }

    func testSetFalsePersists() {
        let sut = makeSUT()
        sut.setVisible(false, providerID: "codex")
        XCTAssertFalse(sut.isVisible(providerID: "codex"))
    }

    func testSetTrueAfterFalsePersists() {
        let sut = makeSUT()
        sut.setVisible(false, providerID: "codex")
        sut.setVisible(true,  providerID: "codex")
        XCTAssertTrue(sut.isVisible(providerID: "codex"))
    }

    func testOtherProviderUnaffected() {
        let sut = makeSUT()
        sut.setVisible(false, providerID: "codex")
        XCTAssertTrue(sut.isVisible(providerID: "zenmux"))
    }

    func testInvalidStoredTypeFallsBackToVisible() {
        let ud = UserDefaults(suiteName: UUID().uuidString)!
        ud.set("not_a_dict", forKey: "InfoBar.providerVisibility")
        let sut = ProviderVisibilityStore(defaults: ud)
        XCTAssertTrue(sut.isVisible(providerID: "codex"))
    }
}
