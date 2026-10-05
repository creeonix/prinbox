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

    @Test func rendersRepliesAndOpenThreads() {
        let owed = thread(
            comment("alice", date("2026-08-10T05:00:00Z")), comment(testViewer, date("2026-08-10T05:30:00Z")),
            comment("alice", date("2026-08-10T06:00:00Z")))
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(
                    id: "a", number: 12, title: "Answer me", repository: "acme/api", source: .involved, threads: [owed]),
                makePR(
                    id: "b", number: 9, title: "Mine", repository: "acme/api", updatedAt: date("2026-08-10T11:00:00Z"),
                    source: .mine, threads: [thread(comment("bob", date("2026-08-10T10:00:00Z")))]),
            ]))
        let expected = """
            waiting on you: 1

            Replies to you (1)
              #12 Answer me  [acme/api]
                  api · waiting 6h · +10 −2 · Awaiting your reply

            Your PRs (1)
              #9 Mine  [acme/api]
                  api · updated 1h ago · +10 −2 · Open threads
            """
        #expect(InboxPrinter.render(inbox, now: now) == expected)
    }

    @Test func aChainPrintsItsPositionOnEachDetailLine() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(
                    id: "a", number: 1, title: "Base", repository: "acme/web",
                    reviewRequestedAt: date("2026-08-10T06:00:00Z"), headRef: "f1", baseRef: "main"),
                makePR(
                    id: "b", number: 2, title: "Top", repository: "acme/web",
                    reviewRequestedAt: date("2026-08-10T07:00:00Z"), headRef: "f2", baseRef: "f1"),
            ]))
        let lines = InboxPrinter.render(inbox, now: now).split(separator: "\n").map(String.init)
        let details = lines.filter { $0.contains("waiting") && $0.contains("+") }
        #expect(details.count == 2)
        #expect(details[0].contains(" · stack 1/2 · "))
        #expect(details[1].contains(" · stack 2/2 · "))
    }
}
