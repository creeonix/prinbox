import Foundation
import Testing

@testable import PrinboxCore

@Suite struct PullRequestMapperTests {
    let result: FetchResult

    init() throws {
        result = try Fixture.twoPhase("review-mix")
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
        let response = try SearchResponse.decode(Data(#"{"message":"Not Found"}"#.utf8))
        #expect(throws: FetchError.badResponse) { try PullRequestMapper.merge(search: response, details: []) }
    }

    @Test func sumsTheCostAndFingerprintsTheSearch() {
        #expect(result.cost == 4)
        #expect(result.fingerprint.count == 6)
        #expect(result.fingerprint["PR_C"] == date("2026-08-05T10:00:00Z"))
    }

    @Test func truncatedPagesCountsReviewsToo() throws {
        let review: [String: Any] = ["author": ["login": "a"], "state": "APPROVED", "submittedAt": NSNull()]
        let node = TwoPhaseJSON.node(
            "PR_1",
            [
                "reviewThreads": ["totalCount": 0, "nodes": []],
                "reviews": ["totalCount": 60, "nodes": Array(repeating: review, count: 50)],
            ])
        let details = try DetailsResponse.decode(TwoPhaseJSON.details([node]))
        #expect(PullRequestMapper.truncatedPages([details]) == 1)
    }

    @Test func truncatedPagesCountsAReviewsPageOnANodeWithoutThreads() throws {
        // Conversation off still asks for nothing; a node may carry `reviews` and no `reviewThreads` when a
        // fixture or a partial response leaves the threads out. The reviews page alone counts.
        let review: [String: Any] = ["author": ["login": "a"], "state": "APPROVED", "submittedAt": NSNull()]
        let truncated = TwoPhaseJSON.node(
            "PR_1", ["reviews": ["totalCount": 60, "nodes": Array(repeating: review, count: 50)]])
        let plain = TwoPhaseJSON.node("PR_2")
        let details = try DetailsResponse.decode(TwoPhaseJSON.details([truncated, plain]))
        #expect(PullRequestMapper.truncatedPages([details]) == 1)
    }

    @Test func readsTheVerdictTheHeadAndTheRecentCommitsFromTheFixture() throws {
        let moved = try pr("PR_C")
        #expect(
            moved.viewerVerdict
                == ViewerReview(state: "APPROVED", submittedAt: date("2026-08-03T09:00:00Z"), commitOid: "c1c1c1c1"))
        #expect(moved.headOid == "c3c3c3c3")
        #expect(moved.recentCommitOids == ["c1c1c1c1", "c2c2c2c2", "c3c3c3c3"])
        #expect(moved.commitCount == 3)
        #expect(moved.movedSinceVerdict)
        #expect(moved.commitsSinceVerdict == 2)
        let still = try pr("PR_B")
        #expect(still.viewerVerdict?.state == "CHANGES_REQUESTED")
        #expect(still.movedSinceVerdict == false)
        #expect(still.commitsSinceVerdict == 0)
        let own = try pr("PR_E")
        #expect(own.headOid == "e2e2e2e2")
        #expect(own.viewerVerdict == nil)
        #expect(own.commitsSinceVerdict == nil)
        #expect(try pr("PR_A").headOid == nil)
        #expect(try pr("PR_A").recentCommitOids == nil)
    }
}
