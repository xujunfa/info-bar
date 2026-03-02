import XCTest
@testable import InfoBar

final class CodexUsageClientTests: XCTestCase {
    func testDecodesPrimaryWindowAndMapsSnapshot() throws {
        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 22,
              "reset_at": 1766948068,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 43,
              "reset_at": 1767407914,
              "limit_window_seconds": 604800
            }
          }
        }
        """

        let response = try CodexUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try CodexUsageClient.mapToSnapshot(response: response, fetchedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.providerID, "codex")
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].label, "H")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 22)
        XCTAssertEqual(snapshot.windows[0].resetAt, Date(timeIntervalSince1970: 1766948068))
        XCTAssertEqual(snapshot.windows[0].windowTitle, "5-hour usage")
        XCTAssertEqual(snapshot.windows[0].metadata?["window_seconds"], "18000")
        XCTAssertEqual(snapshot.windows[0].metadata?["plan_type"], "pro")
        XCTAssertEqual(snapshot.windows[1].label, "W")
        XCTAssertEqual(snapshot.windows[1].usedPercent, 43)
        XCTAssertEqual(snapshot.windows[1].resetAt, Date(timeIntervalSince1970: 1767407914))
        XCTAssertEqual(snapshot.windows[1].windowTitle, "Weekly usage")
        XCTAssertEqual(snapshot.windows[1].metadata?["window_seconds"], "604800")
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 100))
    }

    func testInfersFieldsWhenPercentOrResetAreMissing() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {
              "used": 45,
              "limit": 120,
              "remaining": 75,
              "limit_window_seconds": 18000,
              "unit": " requests "
            }
          }
        }
        """

        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let response = try CodexUsageClient.decodeResponse(data: Data(json.utf8))
        let snapshot = try CodexUsageClient.mapToSnapshot(response: response, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercent, 38)
        XCTAssertEqual(snapshot.windows[0].used, 45)
        XCTAssertEqual(snapshot.windows[0].limit, 120)
        XCTAssertEqual(snapshot.windows[0].remaining, 75)
        XCTAssertEqual(snapshot.windows[0].unit, "requests")
        XCTAssertEqual(snapshot.windows[0].resetAt, fetchedAt.addingTimeInterval(18_000))
    }

    func testThrowsWhenPrimaryWindowMissing() throws {
        let json = """
        {
          "rate_limit": {}
        }
        """

        let response = try CodexUsageClient.decodeResponse(data: Data(json.utf8))
        XCTAssertThrowsError(try CodexUsageClient.mapToSnapshot(response: response, fetchedAt: Date()))
    }
}
