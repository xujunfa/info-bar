import XCTest
import Foundation
@testable import InfoBar

final class CLIRunnerTests: XCTestCase {
    func testCLIRunnerReturnsStdout() throws {
        let runner = CLIRunner()
        let result = try runner.run(executable: "/bin/echo", arguments: ["ok"])
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
        XCTAssertEqual(result.exitCode, 0)
    }
}
