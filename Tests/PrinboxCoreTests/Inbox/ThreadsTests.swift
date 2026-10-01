// Ported from Pullover (https://github.com/omgovich/pullover), src/core/threads.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct ThreadsTests {
    let me = testViewer
    let t1 = date("2026-08-01T10:00:00Z")
    let t2 = date("2026-08-01T11:00:00Z")
    let t3 = date("2026-08-01T12:00:00Z")
    let t4 = date("2026-08-02T09:00:00Z")

    @Test func nothingWithoutThreadData() {
        let pr = makePR()
        #expect(pr.threads == nil)
        #expect(Threads.unresolved(pr).isEmpty)
        #expect(Threads.awaitingReply(pr, viewer: me).isEmpty)
        #expect(Threads.unanswered(pr, viewer: me).isEmpty)
        #expect(Threads.oldestPendingReplyAt([], viewer: me) == nil)
    }

    @Test func awaitingReplyNeedsMyCommentAndSomeoneElseLast() {
        let owed = thread(comment("alice", t1), comment(me, t2), comment("alice", t3))
        let answered = thread(comment("alice", t1), comment(me, t2))
        let notMine = thread(comment("alice", t1), comment("bob", t2))
        let resolved = thread(comment("alice", t1), comment(me, t2), comment("alice", t3), resolved: true)
        let empty = thread()
        let pr = makePR(threads: [owed, answered, notMine, resolved, empty])
        #expect(Threads.unresolved(pr) == [owed, answered, notMine, empty])
        #expect(Threads.awaitingReply(pr, viewer: me) == [owed])
        #expect(Threads.unanswered(pr, viewer: me) == [owed, notMine])
    }

    @Test func loginsCompareCaseInsensitively() {
        let pr = makePR(threads: [thread(comment("Alice", t1), comment("ME", t2), comment("alice", t3))])
        #expect(Threads.awaitingReply(pr, viewer: "me").count == 1)
        #expect(Threads.sameLogin("Alice", "alice"))
        #expect(!Threads.sameLogin("alice", "alice2"))
    }

    @Test func botsAndDeletedAccountsCountAsSomeoneElse() {
        let pr = makePR(threads: [
            thread(comment(me, t1), comment("coderabbitai[bot]", t2)),
            thread(comment(me, t1), comment("ghost", t2)),
        ])
        #expect(Threads.awaitingReply(pr, viewer: me).count == 2)
    }

    @Test func pendingSinceIsTheCommentAfterMyLastOne() {
        let owed = thread(comment("alice", t1), comment(me, t2), comment("alice", t3), comment("bob", t4))
        #expect(Threads.pendingSince(owed, viewer: me) == t3)
        let neverSpoke = thread(comment("alice", t1), comment("bob", t2))
        #expect(Threads.pendingSince(neverSpoke, viewer: me) == t1)
        let spokeLast = thread(comment("alice", t1), comment(me, t2))
        #expect(Threads.pendingSince(spokeLast, viewer: me) == nil)
        #expect(Threads.pendingSince(thread(), viewer: me) == nil)
    }

    @Test func oldestPendingReplyIsTheOldestAcrossThreads() {
        let older = thread(comment("alice", t1), comment(me, t2), comment("alice", t3))
        let newer = thread(comment("bob", t4))
        #expect(Threads.oldestPendingReplyAt([newer, older], viewer: me) == t3)
        #expect(Threads.oldestPendingReplyAt([thread(comment(me, t1))], viewer: me) == nil)
    }

    @Test func isOwnComparesTheAuthorToTheViewer() {
        #expect(Threads.isOwn(makePR(authorLogin: "Me"), viewer: "me"))
        #expect(!Threads.isOwn(makePR(authorLogin: "alice"), viewer: "me"))
    }

    @Test func pullRequestCarriesTheConversationFields() {
        let review = Review(authorLogin: "bob", state: "APPROVED", submittedAt: t2)
        let pr = makePR(headRef: "feature/x", baseRef: "main", lastCommitAt: t1, threads: [], reviews: [review])
        #expect(pr.headRef == "feature/x")
        #expect(pr.baseRef == "main")
        #expect(pr.lastCommitAt == t1)
        #expect(pr.threads == [])
        #expect(pr.reviews == [review])
        #expect(makePR().reviews == nil)
    }
}
