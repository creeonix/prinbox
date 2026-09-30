import Foundation
import Testing

@testable import PrinboxCore

@Suite struct ReleaseCheckerTests {
    let gh = GhLocator(overridePath: "/fake/gh", environmentPath: nil, isExecutable: { $0 == "/fake/gh" })

    @Test func asksGhForTheLatestReleaseAndDecodesIt() async throws {
        let body =
            #"{"tag_name":"v0.3.0","name":"PRInbox 0.3.0","html_url":"https://github.com/creeonix/prinbox/releases/tag/v0.3.0"}"#
        let checker = GhReleaseChecker(
            locator: gh,
            runner: FakeRunner { executable, arguments, environment in
                #expect(executable.path == "/fake/gh")
                #expect(arguments == ["api", "repos/creeonix/prinbox/releases/latest"])
                #expect(environment["GH_PROMPT_DISABLED"] == "1")
                return CommandOutput(exitCode: 0, stdout: Data(body.utf8), stderr: "")
            })
        let release = try await checker.latestRelease()
        let url = URL(string: "https://github.com/creeonix/prinbox/releases/tag/v0.3.0")!
        #expect(release == Release(tag: "v0.3.0", url: url))
        #expect(release.version == AppVersion("0.3.0"))
    }

    @Test func nonZeroExitAndBadBodiesThrow() async {
        let failing = GhReleaseChecker(
            locator: gh,
            runner: FakeRunner { _, _, _ in CommandOutput(exitCode: 1, stdout: Data(), stderr: "HTTP 404") })
        await #expect(throws: (any Error).self) { try await failing.latestRelease() }
        let garbled = GhReleaseChecker(
            locator: gh,
            runner: FakeRunner { _, _, _ in CommandOutput(exitCode: 0, stdout: Data("{}".utf8), stderr: "") })
        await #expect(throws: (any Error).self) { try await garbled.latestRelease() }
    }

    @Test func missingGhThrows() async {
        let none = GhLocator(overridePath: "/fake/gh", environmentPath: nil, isExecutable: { _ in false })
        let checker = GhReleaseChecker(
            locator: none, runner: FakeRunner { _, _, _ in CommandOutput(exitCode: 0, stdout: Data(), stderr: "") })
        await #expect(throws: FetchError.ghNotFound) { try await checker.latestRelease() }
    }

    @Test func displayVersionDropsTheTagPrefixAndKeepsOddTags() {
        let page = GhReleaseChecker.releasesPage
        #expect(Release(tag: "v0.3.0", url: page).displayVersion == "0.3.0")
        #expect(Release(tag: "nightly", url: page).displayVersion == "nightly")
    }
}
