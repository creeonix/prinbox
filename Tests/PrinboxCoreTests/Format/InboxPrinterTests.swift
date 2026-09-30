import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxPrinterTests {
    let now = date("2026-08-10T12:00:00Z")

    @Test func rendersSectionsRowsAndWarnings() {
        let inbox = InboxBuilder.build(
            makeResult(
                [
                    makePR(
                        id: "a", number: 101, title: "Review me", repository: "acme/web",
                        reviewRequestedAt: date("2026-08-10T06:00:00Z")),
                    makePR(id: "b", number: 9, title: "Mine", repository: "acme/api", source: .mine),
                ], warnings: ["w1"]))
        let expected = """
            waiting on you: 1

            Needs your review (1)
              #101 Review me  [acme/web]
                  web · waiting 6h · +10 −2 · Review requested

            Waiting on others (1)
              #9 Mine · Waiting for review  [acme/api]

            warning: w1
            """
        #expect(InboxPrinter.render(inbox, now: now) == expected)
    }

    @Test func rendersInboxZero() {
        #expect(InboxPrinter.render(.empty, now: now) == "waiting on you: 0\n\nInbox zero. Nothing waiting on you.")
    }

    @Test func rendersSnoozedRowsInWaitingOnOthers() {
        let inbox = InboxBuilder.build(
            makeResult([makePR(id: "a", number: 101, title: "Parked", repository: "acme/web")]), snoozed: ["a"])
        let expected = """
            waiting on you: 0

            Waiting on others (1)
              #101 Parked · Snoozed  [acme/web]
            """
        #expect(InboxPrinter.render(inbox, now: now) == expected)
    }
}
