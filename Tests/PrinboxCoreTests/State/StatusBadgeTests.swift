import Foundation
import Testing

@testable import PrinboxCore

@Suite struct StatusBadgeTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func loadingBeforeAnyData() {
        #expect(StatusBadge.derive(inbox: nil, error: nil, lastSuccess: nil, timeZone: utc) == .loading)
    }

    @Test func countWhenSomethingWaits() {
        let inbox = InboxBuilder.build(makeResult([makePR()]))
        #expect(StatusBadge.derive(inbox: inbox, error: nil, lastSuccess: nil, timeZone: utc) == .count(1))
    }

    @Test func zeroWhenNothingWaits() {
        #expect(StatusBadge.derive(inbox: .empty, error: nil, lastSuccess: nil, timeZone: utc) == .zero)
    }

    @Test func errorWinsOverData() {
        let badge = StatusBadge.derive(inbox: .empty, error: .loggedOut, lastSuccess: nil, timeZone: utc)
        #expect(badge == .error("gh not signed in, click for setup"))
    }
}
