import Foundation

public struct CommandOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String

    public init(exitCode: Int32, stdout: Data, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CommandRunnerError: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Runs an external command. The real implementation is `ProcessCommandRunner`; tests replay recorded output.
public protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
}
