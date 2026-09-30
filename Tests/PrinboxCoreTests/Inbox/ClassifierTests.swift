// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Testing

@testable import PrinboxCore

@Suite struct ClassifierTests {
    /// Every PR in these tests is visible; a hidden verdict fails the test loudly.
    func classify(_ pr: PullRequest) -> Classification { Classifier.classify(pr, viewer: testViewer)! }

    @Test func requestedWithoutViewerReviewNeedsReview() {
        let result = classify(makePR(source: .review))
        #expect(result.section == .needsReview)
        #expect(result.reason == .reviewRequested)
    }

    @Test func requestedAfterViewerReviewIsTakeAnotherLook() {
        let reviewed = ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-02T10:00:00Z"))
        let result = classify(makePR(viewerReview: reviewed, source: .review))
        #expect(result.section == .takeAnotherLook)
        #expect(result.reason == .reReviewRequested)
    }

    @Test func mentionSearchIsMentions() {
        let result = classify(makePR(source: .mentions))
        #expect(result.section == .mentions)
        #expect(result.reason == .mentioned)
    }

    @Test func draftsInReviewSectionsAreNotHidden() {
        #expect(classify(makePR(isDraft: true, source: .review)).section == .needsReview)
    }

    @Test func ownChangesRequestedWinsOverEverything() {
        let pr = makePR(
            reviewDecision: .changesRequested, mergeable: .conflicting, ci: .failure, source: .mine)
        #expect(classify(pr).reason == .changesRequested)
        #expect(classify(pr).section == .yourPRs)
    }

    @Test func ownConflictWinsOverRedCI() {
        #expect(classify(makePR(mergeable: .conflicting, ci: .failure, source: .mine)).reason == .mergeConflicts)
    }

    @Test func ownRedCIWinsOverApproval() {
        #expect(classify(makePR(reviewDecision: .approved, ci: .failure, source: .mine)).reason == .ciRed)
    }

    @Test func ownApprovedIsReadyToMerge() {
        #expect(classify(makePR(reviewDecision: .approved, source: .mine)).reason == .readyToMerge)
    }

    @Test func ownApprovedDraftIsWaitingAsDraft() {
        let result = classify(makePR(isDraft: true, reviewDecision: .approved, source: .mine))
        #expect(result.section == .waitingOnOthers)
        #expect(result.reason == .draft)
    }

    @Test func ownDraftWithRedCIStillNeedsAction() {
        #expect(classify(makePR(isDraft: true, ci: .failure, source: .mine)).section == .yourPRs)
    }

    @Test func unknownMergeabilityIsNotAConflict() {
        let result = classify(makePR(mergeable: .unknown, source: .mine))
        #expect(result.section == .waitingOnOthers)
        #expect(result.reason == .waitingForReview)
    }

    @Test func approvedWithRunningCIIsNotReadyToMerge() {
        let result = classify(makePR(reviewDecision: .approved, ci: .pending, source: .mine))
        #expect(result.section == .waitingOnOthers)
        #expect(result.reason == .waitingForReview)
        #expect(classify(makePR(reviewDecision: .approved, ci: .none, source: .mine)).reason == .readyToMerge)
    }

    @Test func ownSectionsHaveNoWaitingSince() {
        #expect(classify(makePR(reviewDecision: .approved, source: .mine)).waitingSince == nil)
        #expect(classify(makePR(source: .mine)).waitingSince == nil)
    }

    @Test func reasonTones() {
        #expect(Reason.reviewRequested.tone == .attention)
        #expect(Reason.ciRed.tone == .failure)
        #expect(Reason.readyToMerge.tone == .success)
        #expect(Reason.waitingForReview.tone == .neutral)
    }

    @Test func badgeSections() {
        #expect(
            SectionKind.allCases.filter(\.countsTowardBadge) == [
                .needsReview, .repliesToYou, .takeAnotherLook, .mentions,
            ])
    }

    @Test func snoozedLandsInWaitingOnOthersWhateverTheSource() {
        for source in SearchSource.allCases where source != .involved {
            let pr = makePR(reviewDecision: .changesRequested, source: source)
            let result = Classifier.classify(pr, viewer: testViewer, snoozed: true)!
            #expect(result.section == .waitingOnOthers)
            #expect(result.reason == .snoozed)
            #expect(result.waitingSince == nil)
        }
        #expect(Reason.snoozed.tone == .neutral)
        #expect(Reason.snoozed.rawValue == "Snoozed")
    }

    let t1 = date("2026-08-03T10:00:00Z")
    let t2 = date("2026-08-04T10:00:00Z")
    let t3 = date("2026-08-05T10:00:00Z")

    /// A thread the viewer took part in where alice spoke last, at t3.
    var owed: ReviewThread { thread(comment("alice", t1), comment(testViewer, t2), comment("alice", t3)) }

    @Test func repliesBeatTakeAnotherLookAndMentions() {
        let reviewed = ViewerReview(state: "COMMENTED", submittedAt: t2)
        let again = classify(makePR(viewerReview: reviewed, reviewRequestedAt: t3, source: .review, threads: [owed]))
        #expect(again.section == .repliesToYou)
        #expect(again.reason == .awaitingReply)
        #expect(again.waitingSince == t3)
        let mention = classify(makePR(source: .mentions, threads: [owed]))
        #expect(mention.section == .repliesToYou)
        #expect(Reason.awaitingReply.tone == .attention)
    }

    @Test func aRequestNotYetAnsweredBeatsReplies() {
        let pr = makePR(source: .review, threads: [owed])
        #expect(classify(pr).section == .needsReview)
    }

    @Test func involvedIsRepliesToYouOrHidden() {
        #expect(classify(makePR(source: .involved, threads: [owed])).section == .repliesToYou)
        #expect(Classifier.classify(makePR(source: .involved, threads: []), viewer: testViewer) == nil)
        #expect(Classifier.classify(makePR(source: .involved), viewer: testViewer) == nil)
        let answered = thread(comment("alice", t1), comment(testViewer, t2))
        #expect(Classifier.classify(makePR(source: .involved, threads: [answered]), viewer: testViewer) == nil)
    }

    @Test func hiddenBeatsSnoozed() {
        #expect(Classifier.classify(makePR(source: .involved), viewer: testViewer, snoozed: true) == nil)
        let parked = Classifier.classify(makePR(source: .involved, threads: [owed]), viewer: testViewer, snoozed: true)
        #expect(parked?.reason == .snoozed)
    }

    @Test func repliesWaitingSinceIsTheOldestPendingReplyFlooredAtVisibleSince() {
        let newer = thread(comment("bob", t1), comment(testViewer, t2), comment("bob", date("2026-08-06T10:00:00Z")))
        let pr = makePR(source: .involved, threads: [newer, owed])
        #expect(classify(pr).waitingSince == t3)
        let draftUntil = date("2026-08-05T12:00:00Z")
        let floored = makePR(readyForReviewAt: draftUntil, source: .involved, threads: [owed])
        #expect(classify(floored).waitingSince == draftUntil)
    }

    @Test func ownOpenThreadsSitBetweenConflictsAndRedCI() {
        let unanswered = thread(comment("bob", t1))
        let open = makePR(ci: .failure, source: .mine, threads: [unanswered])
        #expect(classify(open).section == .yourPRs)
        #expect(classify(open).reason == .openThreads)
        #expect(Reason.openThreads.tone == .attention)
        let conflicting = makePR(mergeable: .conflicting, source: .mine, threads: [unanswered])
        #expect(classify(conflicting).reason == .mergeConflicts)
        let answeredByMe = makePR(
            reviewDecision: .approved, source: .mine, threads: [thread(comment("bob", t1), comment(testViewer, t2))])
        #expect(classify(answeredByMe).reason == .readyToMerge)
        let botThread = makePR(source: .mine, threads: [thread(comment("dependabot[bot]", t1))])
        #expect(classify(botThread).reason == .openThreads)
    }

    @Test func pendingRepliesCountsTheThreadsWaitingForMe() {
        let pr = makePR(source: .involved, threads: [owed, owed, thread(comment("bob", t1))])
        #expect(Classifier.pendingReplies(pr, viewer: testViewer, reason: .awaitingReply) == 2)
        let mine = makePR(
            source: .mine,
            threads: [owed, thread(comment("bob", t1)), thread(comment("bob", t1), comment(testViewer, t2))])
        #expect(Classifier.pendingReplies(mine, viewer: testViewer, reason: .openThreads) == 2)
        #expect(Classifier.pendingReplies(mine, viewer: testViewer, reason: .ciRed) == 0)
    }

    @Test func repliesSectionFacts() {
        #expect(SectionKind.allCases[1] == .repliesToYou)
        #expect(SectionKind.repliesToYou.title == "Replies to you")
        #expect(SectionKind.repliesToYou.countsTowardBadge)
        #expect(!SectionKind.repliesToYou.sortsByRecency)
        #expect(!SectionKind.repliesToYou.usesCompactRows)
        #expect(
            SectionKind.repliesToYou.moreURL.absoluteString
                == "https://github.com/pulls?q=is%3Aopen+is%3Apr+involves%3A%40me+-author%3A%40me")
        #expect(!SearchSource.involved.boundsCompleteness)
        #expect(SearchSource.review.boundsCompleteness)
    }
}
