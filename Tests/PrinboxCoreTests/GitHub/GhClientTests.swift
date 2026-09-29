import Foundation
import Testing

@testable import PrinboxCore

struct FakeRunner: CommandRunning {
    let handler: @Sendable (URL, [String], [String: String]) throws -> CommandOutput

    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
    {
        try handler(executable, arguments, environment)
    }
}

@Suite struct GhClientTests {
    let gh = GhLocator(overridePath: "/fake/gh", environmentPath: nil, isExecutable: { $0 == "/fake/gh" })

    func client(_ handler: @escaping @Sendable (URL, [String], [String: String]) throws -> CommandOutput) -> GhClient {
        GhClient(locator: gh, runner: FakeRunner(handler: handler))
    }

    @Test func runsGhApiGraphqlWithTheInboxQuery() async throws {
        let fixture = try Fixture.data("review-mix")
        let result = try await client { executable, arguments, environment in
            #expect(executable.path == "/fake/gh")
            #expect(arguments == ["api", "graphql", "-f", "query=\(InboxQuery.text)"])
            #expect(environment["GH_PROMPT_DISABLED"] == "1")
            return CommandOutput(exitCode: 0, stdout: fixture, stderr: "")
        }.fetch()
        #expect(result.pullRequests.count == 6)
    }

    @Test func partialErrorsWithExitOneStillReturnData() async throws {
        let body =
            #"{"data":{"viewer":{"login":"me"},"review":{"issueCount":0,"nodes":[]},"#
            + #""mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}},"#
            + #""errors":[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement."}]}"#
        let result = try await client { _, _, _ in
            CommandOutput(
                exitCode: 1, stdout: Data(body.utf8), stderr: "gh: Resource protected by organization SAML enforcement."
            )
        }.fetch()
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
    }

    @Test func loggedOutGhIsLoggedOut() async {
        await #expect(throws: FetchError.loggedOut) {
            try await client { _, _, _ in CommandOutput(exitCode: 4, stdout: Data(), stderr: "gh auth login") }.fetch()
        }
    }

    @Test func networkFailureIsOffline() async {
        await #expect(throws: FetchError.offline) {
            try await client { _, _, _ in
                CommandOutput(exitCode: 1, stdout: Data(), stderr: "dial tcp: lookup api.github.com: no such host")
            }.fetch()
        }
    }

    @Test func runnerTimeoutIsTimedOut() async {
        await #expect(throws: FetchError.timedOut) {
            try await client { _, _, _ in throw CommandRunnerError.timedOut }.fetch()
        }
    }

    @Test func launchFailureOfAnExistingGhExplainsItself() async {
        await #expect(throws: FetchError.other("Could not run gh: bad CPU type in executable")) {
            try await client { _, _, _ in throw CommandRunnerError.launchFailed("bad CPU type in executable") }.fetch()
        }
    }

    @Test func missingGhIsGhNotFound() async {
        let missing = GhLocator(overridePath: nil, environmentPath: nil, isExecutable: { _ in false })
        await #expect(throws: FetchError.ghNotFound) {
            try await GhClient(
                locator: missing,
                runner: FakeRunner { _, _, _ in CommandOutput(exitCode: 0, stdout: Data(), stderr: "") }
            ).fetch()
        }
    }

    @Test func garbageOnSuccessIsBadResponse() {
        #expect(throws: FetchError.badResponse) {
            try GhClient.interpret(CommandOutput(exitCode: 0, stdout: Data("not json".utf8), stderr: ""))
        }
    }
}
