// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Testing

@testable import PrinboxCore

@Suite struct ClassifierTests {
    func classify(_ pr: PullRequest) -> Classification { Classifier.classify(pr) }

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
        #expect(SectionKind.allCases.filter(\.countsTowardBadge) == [.needsReview, .takeAnotherLook, .mentions])
    }

    @Test func snoozedLandsInWaitingOnOthersWhateverTheSource() {
        for source in SearchSource.allCases {
            let pr = makePR(reviewDecision: .changesRequested, source: source)
            let result = Classifier.classify(pr, snoozed: true)
            #expect(result.section == .waitingOnOthers)
            #expect(result.reason == .snoozed)
            #expect(result.waitingSince == nil)
        }
        #expect(Reason.snoozed.tone == .neutral)
        #expect(Reason.snoozed.rawValue == "Snoozed")
    }
}
