import Foundation
import Testing

@testable import PrinboxCore

@Suite struct RelativeAgeTests {
    let now = date("2026-08-10T12:00:00Z")

    func age(_ seconds: TimeInterval) -> String {
        RelativeAge.format(from: now.addingTimeInterval(-seconds), to: now)
    }

    @Test func boundaries() {
        #expect(age(0) == "<1m")
        #expect(age(59) == "<1m")
        #expect(age(60) == "1m")
        #expect(age(59 * 60) == "59m")
        #expect(age(60 * 60) == "1h")
        #expect(age(47 * 3600 + 59 * 60) == "47h")
        #expect(age(48 * 3600) == "2d")
    }

    @Test func futureTimestampsReadAsJustNow() {
        #expect(age(-300) == "<1m")
    }

    @Test func clockTextUsesTheGivenTimeZone() throws {
        let instant = date("2026-08-10T12:05:00Z")
        #expect(ClockText.hhmm(instant, timeZone: try #require(TimeZone(identifier: "UTC"))) == "12:05")
        #expect(ClockText.hhmm(instant, timeZone: try #require(TimeZone(identifier: "Europe/Warsaw"))) == "14:05")
    }
}
