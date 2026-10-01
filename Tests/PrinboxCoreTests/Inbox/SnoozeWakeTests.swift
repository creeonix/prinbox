import Foundation
import Testing

@testable import PrinboxCore

/// The v0.4 wake rule. `before` and `after` are relative to the snooze; the entry's `updatedAt` is `before`.
@Suite struct SnoozeWakeTests {
    let snoozedAt = date("2026-08-05T09:00:00Z")
    let before = date("2026-08-05T08:00:00Z")
    let after = date("2026-08-05T10:00:00Z")
    var entry: SnoozeEntry { SnoozeEntry(snoozedAt: snoozedAt, updatedAt: before) }

    func wakes(_ pr: PullRequest) -> Bool { Snooze.wakes(pr, entry: entry, viewer: "me") }

    @Test func withoutThreadDataAnyNewerUpdatedAtWakes() {
        #expect(wakes(makePR(updatedAt: after)))
        #expect(!wakes(makePR(updatedAt: before)))
    }

    @Test func withThreadDataUpdatedAtAloneDoesNotWake() {
        #expect(!wakes(makePR(updatedAt: after, threads: [])))
        #expect(!wakes(makePR(updatedAt: after, threads: [thread(comment("alice", before))])))
    }

    @Test func aReplyInMyThreadAfterTheSnoozeWakes() {
        #expect(wakes(makePR(threads: [thread(comment("me", before), comment("alice", after))])))
        #expect(
            wakes(makePR(threads: [thread(comment("alice", before), comment("me", before), comment("bob", after))])))
    }

    @Test func olderRepliesMyOwnCommentsAndResolvedThreadsDoNotWake() {
        #expect(!wakes(makePR(threads: [thread(comment("me", before), comment("alice", before))])))
        #expect(!wakes(makePR(threads: [thread(comment("alice", before), comment("me", after))])))
        #expect(!wakes(makePR(threads: [thread(comment("me", before), comment("alice", after), resolved: true)])))
        #expect(!wakes(makePR(threads: [thread(comment("me", before), comment("alice", snoozedAt))])))
    }

    @Test func aReplyInAThreadIAmNotInDoesNotWakeSomeoneElsesPullRequest() {
        #expect(
            !wakes(makePR(authorLogin: "alice", threads: [thread(comment("alice", before), comment("bob", after))])))
    }

    @Test func onMyOwnPullRequestAnyNewThreadCommentBySomeoneElseWakes() {
        #expect(wakes(makePR(authorLogin: "me", threads: [thread(comment("bob", after))])))
        #expect(wakes(makePR(authorLogin: "Me", threads: [thread(comment("bob", before), comment("carol", after))])))
    }

    @Test func myOwnCommentOnMyOwnPullRequestDoesNotWake() {
        #expect(!wakes(makePR(authorLogin: "me", threads: [thread(comment("bob", before), comment("me", after))])))
    }

    @Test func ghostRepliesWake() {
        #expect(wakes(makePR(threads: [thread(comment("me", before), comment("ghost", after))])))
    }

    @Test func aNewCommitWakes() {
        #expect(wakes(makePR(lastCommitAt: after, threads: [])))
        #expect(!wakes(makePR(lastCommitAt: before, threads: [])))
        #expect(!wakes(makePR(lastCommitAt: snoozedAt, threads: [])))
    }

    @Test func aReRequestAfterTheSnoozeWakes() {
        #expect(wakes(makePR(reviewRequestedAt: after, threads: [])))
        #expect(!wakes(makePR(reviewRequestedAt: before, threads: [])))
    }

    @Test func aNewReviewWakesOnlyMyOwnPullRequest() {
        let approval = [Review(authorLogin: "bob", state: "APPROVED", submittedAt: after)]
        #expect(wakes(makePR(authorLogin: "me", threads: [], reviews: approval)))
        #expect(!wakes(makePR(authorLogin: "alice", threads: [], reviews: approval)))
        #expect(
            !wakes(
                makePR(
                    authorLogin: "me", threads: [],
                    reviews: [Review(authorLogin: "bob", state: "APPROVED", submittedAt: before)])))
        #expect(
            !wakes(
                makePR(
                    authorLogin: "me", threads: [],
                    reviews: [Review(authorLogin: "me", state: "COMMENTED", submittedAt: after)])))
        #expect(
            !wakes(
                makePR(
                    authorLogin: "me", threads: [],
                    reviews: [Review(authorLogin: "bob", state: "APPROVED", submittedAt: nil)])))
    }

    @Test func reconcileAppliesTheRuleWithTheResultsViewer() {
        let entries = ["a": entry, "b": entry]
        let result = makeResult([
            makePR(id: "a", authorLogin: "me", threads: [thread(comment("bob", after))]),
            makePR(id: "b", updatedAt: after, threads: []),
        ])
        #expect(Snooze.reconcile(entries, with: result) == ["b": entry])
    }
}
