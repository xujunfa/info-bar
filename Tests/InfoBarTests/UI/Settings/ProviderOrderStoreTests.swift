import XCTest
@testable import InfoBar

final class ProviderOrderStoreTests: XCTestCase {
    private var sut: ProviderOrderStore!
    private let defaultIDs = ["codex", "zenmux", "minimax", "bigmodel"]

    override func setUp() {
        super.setUp()
        let suite = UUID().uuidString
        sut = ProviderOrderStore(defaults: UserDefaults(suiteName: suite)!)
    }

    // 首次使用（无存储）→ 返回 defaultIDs
    func testDefaultOrderReturnsDefaultIDs() {
        XCTAssertEqual(sut.orderedIDs(defaultIDs: defaultIDs), defaultIDs)
    }

    // setOrder 后持久化
    func testSetOrderPersists() {
        let newOrder = ["bigmodel", "minimax", "zenmux", "codex"]
        sut.setOrder(newOrder)
        XCTAssertEqual(sut.orderedIDs(defaultIDs: defaultIDs), newOrder)
    }

    // 存储的 ID 集合与 defaultIDs 不一致 → 回退 defaultIDs
    func testOrderWithDifferentIDSetFallsBackToDefault() {
        sut.setOrder(["codex", "unknown"])
        XCTAssertEqual(sut.orderedIDs(defaultIDs: defaultIDs), defaultIDs)
    }

    // 非法存储类型 → 回退 defaultIDs
    func testInvalidStoredTypeFallsBackToDefault() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(42, forKey: "InfoBar.providerOrder")
        let store = ProviderOrderStore(defaults: defaults)
        XCTAssertEqual(store.orderedIDs(defaultIDs: defaultIDs), defaultIDs)
    }

    // 空数组存储 → 回退 defaultIDs
    func testEmptyStoredOrderFallsBackToDefault() {
        sut.setOrder([])
        XCTAssertEqual(sut.orderedIDs(defaultIDs: defaultIDs), defaultIDs)
    }
}
