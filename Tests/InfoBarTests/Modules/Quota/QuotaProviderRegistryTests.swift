import XCTest
@testable import InfoBar

final class QuotaProviderRegistryTests: XCTestCase {
    func testDefaultProvidersContainCodexZenMuxAndMiniMax() {
        let providers = QuotaProviderRegistry.defaultProviders()
        XCTAssertTrue(providers.contains { $0.id == "codex" })
        XCTAssertTrue(providers.contains { $0.id == "zenmux" })
        XCTAssertTrue(providers.contains { $0.id == "minimax" })
    }
}
