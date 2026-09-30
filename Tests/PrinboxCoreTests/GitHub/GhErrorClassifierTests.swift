import Testing

@testable import PrinboxCore

@Suite struct GhErrorClassifierTests {
    @Test func exitCodeFourIsLoggedOut() {
        let stderr =
            "To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.\n"
        #expect(GhErrorClassifier.classify(exitCode: 4, stderr: stderr) == .loggedOut)
    }

    @Test func badCredentialsIsLoggedOut() {
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Bad credentials (HTTP 401)\n") == .loggedOut)
    }

    @Test func connectionFailureIsOffline() {
        let stderr =
            #"Post "https://api.github.com/graphql": proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused"#
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .offline)
    }

    @Test func unknownHostIsOffline() {
        let stderr = #"Post "https://api.github.com/graphql": dial tcp: lookup api.github.com: no such host"#
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .offline)
    }

    @Test func rateLimitMessageIsRateLimited() {
        let stderr = "gh: API rate limit exceeded for user ID 1. (HTTP 403)\n"
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .rateLimited(resetAt: nil))
    }

    @Test func otherFailuresKeepTheFirstLineWithoutPrefix() {
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Something odd\nmore detail\n")
                == .other("Something odd"))
    }

    @Test func emptyStderrNamesTheExitCode() {
        #expect(GhErrorClassifier.classify(exitCode: 2, stderr: "") == .other("gh exited with code 2"))
    }

    @Test func longMessagesAreCutTo120Characters() {
        let long = String(repeating: "x", count: 300)
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: long) == .other(String(repeating: "x", count: 120)))
    }

    @Test func serverErrorsAreGitHubUnavailable() {
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: "gh: HTTP 502\n") == .githubUnavailable(status: 502))
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Service Unavailable (HTTP 503)\n")
                == .githubUnavailable(status: 503))
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "gh: HTTP 504: gateway timeout")
                == .githubUnavailable(status: 504))
        #expect(GhErrorClassifier.serverErrorStatus("gh: http 404") == nil)
    }

    @Test func serverErrorPrecedence() {
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Bad credentials (HTTP 401) then HTTP 502")
                == .loggedOut)
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "gh: API rate limit exceeded (HTTP 503)")
                == .rateLimited(resetAt: nil))
        #expect(
            GhErrorClassifier.classify(exitCode: 1, stderr: "dial tcp: i/o timeout (HTTP 502)") == .offline)
    }
}
