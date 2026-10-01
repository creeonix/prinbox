import Foundation
import Testing

@testable import PrinboxCore

@Suite struct FetchErrorTextTests {
    let utc = TimeZone(identifier: "UTC")!
    let at = date("2026-08-10T14:05:00Z")

    func text(_ error: FetchError, lastSuccess: Date? = nil) -> String {
        error.message(lastSuccess: lastSuccess, timeZone: utc)
    }

    @Test func messages() {
        #expect(text(.ghNotFound) == "gh not installed, click for setup")
        #expect(text(.loggedOut) == "gh not signed in, click for setup")
        #expect(text(.offline) == "Offline")
        #expect(text(.offline, lastSuccess: at) == "Offline, showing data from 14:05")
        #expect(text(.timedOut) == "GitHub did not answer in time")
        #expect(text(.rateLimited(resetAt: at)) == "Rate limited until 14:05")
        #expect(text(.rateLimited(resetAt: nil)) == "Rate limited by GitHub")
        #expect(text(.badResponse) == "Unexpected response from gh")
        #expect(text(.other("boom")) == "boom")
    }

    @Test func githubUnavailableNamesTheStatusAndTheLastData() {
        let at = date("2026-08-10T17:13:00Z")
        #expect(
            FetchError.githubUnavailable(status: 502).message(lastSuccess: at, timeZone: utc)
                == "GitHub is having trouble (HTTP 502), showing data from 17:13")
        #expect(
            FetchError.githubUnavailable(status: 503).message(lastSuccess: nil, timeZone: utc)
                == "GitHub is having trouble (HTTP 503)")
    }

    @Test func onlyGithubUnavailableHasAHelpLink() {
        #expect(FetchError.githubUnavailable(status: 502).helpURL == URL(string: "https://www.githubstatus.com"))
        #expect(FetchError.offline.helpURL == nil)
        #expect(FetchError.timedOut.helpURL == nil)
        #expect(FetchError.githubUnavailable(status: 502).needsSetup == false)
    }
}
