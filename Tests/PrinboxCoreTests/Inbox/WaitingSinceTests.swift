// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct WaitingSinceTests {
    func since(_ pr: PullRequest) -> Date? { Classifier.classify(pr).waitingSince }

    @Test func needsReviewUsesTheRequestTime() {
        let pr = makePR(reviewRequestedAt: date("2026-08-03T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-03T10:00:00Z"))
    }

    @Test func needsReviewFallsBackToCreation() {
        #expect(since(makePR(createdAt: date("2026-08-02T10:00:00Z"), source: .review)) == date("2026-08-02T10:00:00Z"))
    }

    @Test func draftFloorWinsOverAnEarlierRequest() {
        let pr = makePR(
            reviewRequestedAt: date("2026-08-02T10:00:00Z"), readyForReviewAt: date("2026-08-04T10:00:00Z"),
            source: .review)
        #expect(since(pr) == date("2026-08-04T10:00:00Z"))
    }

    @Test func reReviewUsesARequestAfterTheReview() {
        let pr = makePR(
            viewerReview: ViewerReview(state: "APPROVED", submittedAt: date("2026-08-02T10:00:00Z")),
            reviewRequestedAt: date("2026-08-03T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-03T10:00:00Z"))
    }

    @Test func reReviewIgnoresARequestPredatingTheReview() {
        let pr = makePR(
            updatedAt: date("2026-08-05T10:00:00Z"),
            viewerReview: ViewerReview(state: "APPROVED", submittedAt: date("2026-08-03T10:00:00Z")),
            reviewRequestedAt: date("2026-08-02T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-05T10:00:00Z"))
    }

    @Test func mentionsUseTheLastUpdate() {
        #expect(
            since(makePR(updatedAt: date("2026-08-06T10:00:00Z"), source: .mentions)) == date("2026-08-06T10:00:00Z"))
    }
}
