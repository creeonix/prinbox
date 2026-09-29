import Foundation
import os

public protocol InboxFetching: Sendable {
    func fetch() async throws -> FetchResult
}

/// Fetches the inbox by running `gh api graphql`. gh owns authentication; prinbox never sees the token.
/// Failures log gh's stderr (truncated) to the unified log. stdout is never logged.
public struct GhClient: InboxFetching {
    public static let defaultTimeout: Duration = .seconds(30)
    private static let log = Logger(subsystem: "io.github.creeonix.prinbox", category: "gh")

    private let locator: GhLocator
    private let runner: CommandRunning
    private let timeout: Duration

    public init(
        locator: GhLocator = GhLocator(), runner: CommandRunning = ProcessCommandRunner(),
        timeout: Duration = GhClient.defaultTimeout
    ) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func ghPath() -> String? { locator.locate()?.path }

    /// The `ghPath` override in effect, if any.
    public var ghOverride: String? { locator.overridePath }

    public func fetch() async throws -> FetchResult {
        guard let gh = locator.locate() else { throw FetchError.ghNotFound }
        let output: CommandOutput
        do {
            output = try await runner.run(
                executable: gh, arguments: ["api", "graphql", "-f", "query=\(InboxQuery.text)"],
                environment: Self.environment(), timeout: timeout)
        } catch CommandRunnerError.timedOut {
            Self.log.error("gh timed out")
            throw FetchError.timedOut
        } catch CommandRunnerError.launchFailed(let reason) {
            Self.log.error("gh could not be launched: \(reason, privacy: .public)")
            throw FetchError.other("Could not run gh: \(reason)")
        } catch {
            Self.log.error("gh failed to run: \(String(describing: error), privacy: .public)")
            throw FetchError.other("Could not run gh: \(error.localizedDescription)")
        }
        if output.exitCode != 0 {
            Self.log.error("gh exited \(output.exitCode): \(String(output.stderr.prefix(500)), privacy: .public)")
        }
        return try Self.interpret(output)
    }

    /// gh prints the response body even when it exits 1 because of GraphQL errors, so a decodable body
    /// is used first and stderr only explains failures without one.
    static func interpret(_ output: CommandOutput) throws -> FetchResult {
        if let response = try? InboxResponse.decode(output.stdout), response.data != nil || response.errors != nil {
            return try PullRequestMapper.map(response)
        }
        guard output.exitCode == 0 else {
            throw GhErrorClassifier.classify(exitCode: output.exitCode, stderr: output.stderr)
        }
        throw FetchError.badResponse
    }

    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        base.merging(["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"]) { _, new in new }
    }
}
