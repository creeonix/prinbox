import Testing

@testable import PrinboxCore

@Suite struct RowMarksTests {
    @Test func commentsAreShownOnlyAboveZero() {
        #expect(RowMarks.marks(for: makePR()).comments == nil)
        #expect(RowMarks.marks(for: makePR(commentCount: 4)).comments == 4)
        #expect(RowMarks.commentsHelp(1) == "1 comment")
        #expect(RowMarks.commentsHelp(4) == "4 comments")
    }

    @Test func ciMapsToPassedFailedRunning() {
        #expect(RowMarks.marks(for: makePR(ci: .success)).ci == .passed)
        #expect(RowMarks.marks(for: makePR(ci: .failure)).ci == .failed)
        #expect(RowMarks.marks(for: makePR(ci: .pending)).ci == .running)
        #expect(RowMarks.marks(for: makePR(ci: .none)).ci == nil)
    }

    @Test func reviewShowsOnlyApprovedAndChangesRequested() {
        #expect(RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .pending)).review == .approved)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .changesRequested)).review == .changesRequested)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .reviewRequired)).review == nil)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .none)).review == nil)
    }

    @Test func readyCollapsesCIAndReviewIntoTheMergeMark() {
        let marks = RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .success, commentCount: 2))
        #expect(marks == RowMarks(comments: 2, ci: nil, review: nil, merge: .ready))
        #expect(RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .none)).merge == .ready)
    }

    @Test func notReadyWhileDraftOrCIRunningOrFailed() {
        #expect(RowMarks.isReady(makePR(isDraft: true, reviewDecision: .approved)) == false)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .pending)).merge == nil)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .failure)).merge == nil)
        #expect(RowMarks.marks(for: makePR(reviewDecision: .approved, ci: .failure)).ci == .failed)
    }

    @Test func conflictsWinOverReady() {
        let marks = RowMarks.marks(for: makePR(reviewDecision: .approved, mergeable: .conflicting, ci: .success))
        #expect(marks.merge == .conflicts)
        #expect(marks.review == .approved)
        #expect(marks.ci == .passed)
        #expect(RowMarks.marks(for: makePR(mergeable: .unknown)).merge == nil)
    }

    @Test func helpTexts() {
        #expect(CIMark.passed.help == "CI passed")
        #expect(CIMark.failed.help == "CI failed")
        #expect(CIMark.running.help == "CI running")
        #expect(ReviewMark.approved.help == "Approved")
        #expect(ReviewMark.changesRequested.help == "Changes requested")
        #expect(MergeMark.ready.help == "Ready to merge")
        #expect(MergeMark.conflicts.help == "Merge conflicts")
    }

    @Test func commentsHelpNamesTheThreadsWaitingForMe() {
        #expect(RowMarks.commentsHelp(9, pending: 2) == "9 comments, 2 waiting for your reply")
        #expect(RowMarks.commentsHelp(1, pending: 1) == "1 comment, 1 waiting for your reply")
        #expect(RowMarks.commentsHelp(4, pending: 0) == "4 comments")
    }

    @Test func onlyTheReplyReasonsHighlightComments() {
        #expect(Reason.awaitingReply.highlightsComments)
        #expect(Reason.openThreads.highlightsComments)
        #expect(!Reason.reviewRequested.highlightsComments)
        #expect(!Reason.changesRequested.highlightsComments)
        #expect(!Reason.snoozed.highlightsComments)
    }

    @Test func theVerdictCueIsYoursAndNeverOnYourOwnRows() {
        func row(_ pr: PullRequest) -> InboxRow {
            InboxRow(pullRequest: pr, classification: Classifier.classify(pr, viewer: testViewer)!)
        }
        let approved = ViewerReview(state: "APPROVED", submittedAt: nil, commitOid: "aaa")
        let blocked = ViewerReview(state: "CHANGES_REQUESTED", submittedAt: nil, commitOid: "aaa")
        #expect(
            VerdictCue.of(
                row(makePR(viewerReview: approved, source: .involved, headOid: "ccc", viewerVerdict: approved)))
                == .approved)
        #expect(
            VerdictCue.of(row(makePR(viewerReview: blocked, source: .review, viewerVerdict: blocked)))
                == .changesRequested)
        #expect(
            VerdictCue.of(
                row(makePR(viewerReview: approved, source: .involved, headOid: "aaa", viewerVerdict: approved)))
                == .approved)
        #expect(VerdictCue.of(row(makePR(source: .review))) == nil)
        #expect(
            VerdictCue.of(
                row(makePR(viewerReview: ViewerReview(state: "COMMENTED", submittedAt: nil), source: .review))) == nil)
        #expect(VerdictCue.of(row(makePR(authorLogin: testViewer, source: .mine, viewerVerdict: approved))) == nil)
    }
}
