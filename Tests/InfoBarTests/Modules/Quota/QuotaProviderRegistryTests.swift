import XCTest
@testable import InfoBar

final class QuotaProviderRegistryTests: XCTestCase {
    func testDefaultProvidersContainCodex() {
        let providers = QuotaProviderRegistry.defaultProviders()
        XCTAssertTrue(providers.contains { $0.id == "codex" })
    }
}
