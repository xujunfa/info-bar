import XCTest
@testable import InfoBar

final class CodexAuthStoreTests: XCTestCase {
    func testParsesTokensFromAuthJSON() throws {
        let json = """
        {
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "acct-123"
          }
        }
        """

        let credentials = try CodexAuthStore.parse(data: Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "access-token")
        XCTAssertEqual(credentials.accountId, "acct-123")
    }

    func testParsesAPIKeyFromAuthJSON() throws {
        let json = """
        {
          "OPENAI_API_KEY": "sk-test"
        }
        """

        let credentials = try CodexAuthStore.parse(data: Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "sk-test")
        XCTAssertNil(credentials.accountId)
    }

    func testThrowsWhenMissingCredentials() {
        let json = "{}"

        XCTAssertThrowsError(try CodexAuthStore.parse(data: Data(json.utf8)))
    }
}
