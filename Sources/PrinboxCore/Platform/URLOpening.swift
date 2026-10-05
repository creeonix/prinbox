import Foundation

/// How a URL is opened: `NSWorkspace` in the app, `xdg-open` or `open` from the command.
public protocol URLOpening: Sendable {
    func open(_ url: URL) async
}

public struct NullURLOpener: URLOpening {
    public init() {}
    public func open(_ url: URL) async {}
}

/// Runs an opener command with the URL as its only argument.
public struct ProcessURLOpener: URLOpening {
    public static let timeout: Duration = .seconds(10)

    private let executable: URL
    private let runner: CommandRunning
    private let logger: Logging

    public init(executable: URL, runner: CommandRunning = ProcessCommandRunner(), logger: Logging = NullLogging()) {
        self.executable = executable
        self.runner = runner
        self.logger = logger
    }

    public func open(_ url: URL) async {
        let name = executable.lastPathComponent
        do {
            let output = try await runner.run(
                executable: executable, arguments: [url.absoluteString],
                environment: ProcessInfo.processInfo.environment, timeout: Self.timeout)
            if output.exitCode != 0 {
                logger.notice(.cli, "\(name) exited \(output.exitCode)", private: String(output.stderr.prefix(500)))
            }
        } catch {
            logger.notice(.cli, "\(name) did not run", private: String(describing: error))
        }
    }
}
