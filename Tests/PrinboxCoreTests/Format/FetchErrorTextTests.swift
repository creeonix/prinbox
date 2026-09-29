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
}
