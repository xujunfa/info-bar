import Foundation

private struct RawQuotaSnapshot: Decodable {
    let limit: Int
    let used: Int
    let resetAt: Date
}

public final class QuotaReader: Reader<QuotaSnapshot> {
    private let runner: CLIRunner
    private let executable: String
    private let arguments: [String]

    public init(
        runner: CLIRunner = CLIRunner(),
        executable: String = "/usr/bin/env",
        arguments: [String] = ["codex", "quota", "--json"],
        callback: @escaping Callback = { _ in }
    ) {
        self.runner = runner
        self.executable = executable
        self.arguments = arguments
        super.init(interval: 300, popup: false, callback: callback)
    }

    public override func read() {
        do {
            let result = try runner.run(executable: executable, arguments: arguments)
            guard result.exitCode == 0,
                  let data = result.stdout.data(using: .utf8) else {
                callback(nil)
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let parsed = try? decoder.decode(RawQuotaSnapshot.self, from: data) {
                callback(QuotaSnapshot(
                    limit: parsed.limit,
                    used: parsed.used,
                    resetAt: parsed.resetAt,
                    fetchedAt: Date()
                ))
            } else {
                callback(nil)
            }
        } catch {
            callback(nil)
        }
    }
}
