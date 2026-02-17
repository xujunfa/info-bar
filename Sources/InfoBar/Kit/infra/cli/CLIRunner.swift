import Foundation

public struct CLIRunResult: Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum CLIRunnerError: Error {
    case timeout
}

public final class CLIRunner {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 10
    ) throws -> CLIRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let timeoutResult = finished.wait(timeout: .now() + timeout)
        if timeoutResult == .timedOut, process.isRunning {
            process.terminate()
            throw CLIRunnerError.timeout
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return CLIRunResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
