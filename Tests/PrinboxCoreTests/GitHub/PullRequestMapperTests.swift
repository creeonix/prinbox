import Foundation
import Testing

@testable import PrinboxCore

@Suite struct PullRequestMapperTests {
    let result: FetchResult

    init() throws {
        result = try PullRequestMapper.map(InboxResponse.decode(Fixture.data("review-mix")))
    }

    func pr(_ id: String) throws -> PullRequest {
        try #require(result.pullRequests.first { $0.id == id })
    }

    @Test func readsViewerAndCounts() {
        #expect(result.viewerLogin == "me")
        #expect(result.totals == [.review: 5, .mentions: 2, .mine: 40])
        #expect(result.fetched == [.review: 5, .mentions: 2, .mine: 2])
        #expect(result.warnings.isEmpty)
    }

    @Test func skipsNullAndNonPullRequestNodesAndDedupesById() {
        #expect(result.pullRequests.map(\.id) == ["PR_A", "PR_B", "PR_C", "PR_D", "PR_E", "PR_F"])
    }

    @Test func firstSearchWinsForDuplicates() throws {
        let first = try pr("PR_A")
        #expect(first.source == .review)
        #expect(first.title == "Direct review request")
    }

    @Test func directRequestWinsOverTeamAndIgnoresOtherUsers() throws {
        #expect(try pr("PR_A").reviewRequestedAt == date("2026-08-02T10:00:00Z"))
    }

    @Test func teamRequestIsTheFallback() throws {
        #expect(try pr("PR_B").reviewRequestedAt == date("2026-08-03T08:00:00Z"))
    }

    @Test func pendingViewerReviewCountsAsNoReview() throws {
        #expect(try pr("PR_B").viewerReview == nil)
    }

    @Test func readsReadyForReviewTime() throws {
        #expect(try pr("PR_B").readyForReviewAt == date("2026-08-03T07:00:00Z"))
        #expect(try pr("PR_A").readyForReviewAt == nil)
    }

    @Test func keepsSubmittedViewerReview() throws {
        #expect(
            try pr("PR_C").viewerReview == ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-04T09:00:00Z")))
    }

    @Test func mapsCheckRollupStates() throws {
        #expect(try pr("PR_A").ci == .success)
        #expect(try pr("PR_B").ci == .pending)
        #expect(try pr("PR_C").ci == CIState.none)
        #expect(try pr("PR_D").ci == CIState.none)
        #expect(try pr("PR_E").ci == .failure)
        #expect(try pr("PR_F").ci == .pending)
    }

    @Test func mapsReviewDecisionAndMergeable() throws {
        #expect(try pr("PR_C").reviewDecision == .changesRequested)
        #expect(try pr("PR_D").reviewDecision == ReviewDecision.none)
        #expect(try pr("PR_E").reviewDecision == .approved)
        #expect(try pr("PR_D").mergeable == .conflicting)
        #expect(try pr("PR_F").mergeable == .unknown)
    }

    @Test func deletedAuthorBecomesGhost() throws {
        let ghost = try pr("PR_D")
        #expect(ghost.authorLogin == "ghost")
        #expect(ghost.avatarURL == nil)
    }

    @Test func keepsArchivedFlagForTheBuilder() throws {
        #expect(try pr("PR_F").isArchived)
        #expect(try pr("PR_F").isDraft)
    }

    @Test func responseWithoutDataIsBadResponse() throws {
        let response = try InboxResponse.decode(Data(#"{"message":"Not Found"}"#.utf8))
        #expect(throws: FetchError.badResponse) { try PullRequestMapper.map(response) }
    }
}
