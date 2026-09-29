import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SetupGuideTests {
    @Test func missingGhExplainsInstallAndSignIn() throws {
        let guide = try #require(SetupGuide.for(.ghNotFound, ghOverride: nil))
        #expect(guide.title == "Install the GitHub CLI")
        #expect(guide.summary.hasPrefix("PRInbox reads your pull requests"))
        #expect(guide.footnote?.text == "Installed gh somewhere else? Point PRInbox at it")
        #expect(guide.steps.map(\.command) == ["brew install gh", "gh auth login"])
        #expect(guide.link?.url == URL(string: "https://cli.github.com"))
        #expect(guide.footnote?.command == "defaults write io.github.creeonix.prinbox ghPath /path/to/gh")
    }

    @Test func missingGhAtAnOverrideNamesThePath() throws {
        let guide = try #require(SetupGuide.for(.ghNotFound, ghOverride: "/opt/tools/gh"))
        #expect(guide.title == "gh not found")
        #expect(guide.summary.contains("/opt/tools/gh"))
        #expect(guide.steps.map(\.command) == ["defaults delete io.github.creeonix.prinbox ghPath", "brew install gh"])
    }

    @Test func loggedOutExplainsSignIn() throws {
        let guide = try #require(SetupGuide.for(.loggedOut, ghOverride: nil))
        #expect(guide.title == "Sign in to the GitHub CLI")
        #expect(guide.steps.map(\.command) == ["gh auth login"])
    }

    @Test func otherErrorsNeedNoSetup() {
        for error in [FetchError.offline, .timedOut, .rateLimited(resetAt: nil), .badResponse, .other("x")] {
            #expect(SetupGuide.for(error, ghOverride: nil) == nil)
            #expect(!error.needsSetup)
        }
        #expect(FetchError.ghNotFound.needsSetup)
        #expect(FetchError.loggedOut.needsSetup)
    }

    @Test func plainTextForTheTerminal() throws {
        let guide = try #require(SetupGuide.for(.loggedOut, ghOverride: nil))
        let expected = """
            Sign in to the GitHub CLI
            gh is installed but not signed in to GitHub, or its sign-in has expired.

            1. Run this in a terminal, choose GitHub.com, then "Login with a web browser":
                 gh auth login

            If your organization uses single sign-on, authorize gh for it when the browser asks.
            """
        #expect(guide.plainText == expected)
    }
}
