import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SnoozeTests {
    let snoozedAt = date("2026-08-05T09:00:00Z")
    let seen = date("2026-08-01T10:00:00Z")

    var entries: [String: SnoozeEntry] { ["a": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: seen)] }

    @Test func unchangedPullRequestStaysSnoozed() {
        let kept = Snooze.reconcile(entries, with: makeResult([makePR(id: "a", updatedAt: seen)]))
        #expect(kept == entries)
    }

    @Test func newerUpdatedAtWakesThePullRequest() {
        let later = seen.addingTimeInterval(60)
        let kept = Snooze.reconcile(entries, with: makeResult([makePR(id: "a", updatedAt: later)]))
        #expect(kept.isEmpty)
    }

    @Test func absentFromACompleteFetchIsDropped() {
        let kept = Snooze.reconcile(entries, with: makeResult([makePR(id: "b")]))
        #expect(kept.isEmpty)
    }

    @Test func absentFromAnIncompleteFetchIsKept() {
        let warned = makeResult([makePR(id: "b")], warnings: ["acme requires SSO re-authorization: results incomplete"])
        #expect(Snooze.reconcile(entries, with: warned) == entries)
        let truncated = makeResult([makePR(id: "b")], totals: [.review: 40, .mentions: 0, .mine: 0])
        #expect(Snooze.reconcile(entries, with: truncated) == entries)
    }

    @Test func aScopedFetchKeepsEntriesForAbsentPullRequests() {
        let gone = ["PR_gone": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: seen)]
        let result = makeResult([makePR(id: "PR_1", updatedAt: seen)])
        #expect(Snooze.reconcile(gone, with: result).isEmpty)
        #expect(Snooze.reconcile(gone, with: result, scoped: true) == gone)
        let changed = makeResult([makePR(id: "a", updatedAt: seen.addingTimeInterval(60))])
        #expect(Snooze.reconcile(entries, with: changed, scoped: true).isEmpty)
    }

    @Test func fetchIsCompleteOnlyWithoutWarningsOrTruncation() {
        #expect(makeResult([makePR()]).isComplete)
        #expect(!makeResult([makePR()], warnings: ["w"]).isComplete)
        #expect(!makeResult([makePR()], totals: [.review: 2, .mentions: 0, .mine: 0]).isComplete)
        #expect(makeResult([], totals: [:]).isComplete)
    }

    @Test func involvedTruncationDoesNotMakeAFetchIncomplete() {
        #expect(
            makeResult([makePR(source: .involved)], totals: [.review: 0, .mentions: 0, .mine: 0, .involved: 40])
                .isComplete)
        #expect(
            !makeResult([makePR(source: .review)], totals: [.review: 40, .mentions: 0, .mine: 0, .involved: 0])
                .isComplete)
    }
}
