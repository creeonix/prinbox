import Foundation
import Testing

@testable import PrinboxCore

/// Mapper rules for the fields added in v0.2, driven by one hand-written review-search node.
@Suite struct MapperFieldTests {
    static var base: [String: Any] {
        [
            "id": "PR_1", "number": 1, "title": "T", "url": "https://github.com/acme/web/pull/1",
            "isDraft": false, "additions": 1, "deletions": 0,
            "createdAt": "2026-08-01T10:00:00Z", "updatedAt": "2026-08-01T10:00:00Z",
            "author": ["login": "alice", "avatarUrl": "https://avatars.githubusercontent.com/u/1"],
            "repository": ["nameWithOwner": "acme/web", "isArchived": false],
            "reviewDecision": NSNull(), "mergeable": "MERGEABLE", "viewerLatestReview": NSNull(),
            "commits": ["nodes": []], "timelineItems": ["nodes": []],
        ]
    }

    func map(_ overrides: [String: Any]) throws -> PullRequest {
        let node = Self.base.merging(overrides) { _, new in new }
        let body: [String: Any] = [
            "data": [
                "viewer": ["login": "me"],
                "review": ["issueCount": 1, "nodes": [node]],
                "mentions": ["issueCount": 0, "nodes": []],
                "mine": ["issueCount": 0, "nodes": []],
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try #require(try PullRequestMapper.map(InboxResponse.decode(data)).pullRequests.first)
    }

    @Test func missingNewFieldsDecodeToDefaults() throws {
        let pr = try map([:])
        #expect(pr.commentCount == 0)
        #expect(pr.ownerAvatarURL == nil)
        #expect(pr.ownerIsOrganization == false)
        #expect(pr.ownerLogin == "acme")
    }

    @Test func readsCommentCountAndOrganizationOwner() throws {
        let pr = try map([
            "totalCommentsCount": 7,
            "repository": [
                "nameWithOwner": "acme/web", "isArchived": false,
                "owner": [
                    "__typename": "Organization", "login": "acme",
                    "avatarUrl": "https://avatars.githubusercontent.com/u/9",
                ],
            ],
        ])
        #expect(pr.commentCount == 7)
        #expect(pr.ownerAvatarURL == URL(string: "https://avatars.githubusercontent.com/u/9"))
        #expect(pr.ownerIsOrganization)
    }

    @Test func aUserOwnerIsNotAnOrganization() throws {
        let pr = try map([
            "repository": [
                "nameWithOwner": "bob/dotfiles", "isArchived": false,
                "owner": [
                    "__typename": "User", "login": "bob", "avatarUrl": "https://avatars.githubusercontent.com/u/2",
                ],
            ]
        ])
        #expect(pr.ownerIsOrganization == false)
        #expect(pr.ownerLogin == "bob")
    }

    @Test func nullDecisionFallsBackToLatestReviews() throws {
        let approved = try map(["latestOpinionatedReviews": ["nodes": [["state": "APPROVED"], ["state": "COMMENTED"]]]])
        #expect(approved.reviewDecision == .approved)
        let blocked = try map([
            "latestOpinionatedReviews": ["nodes": [["state": "APPROVED"], NSNull(), ["state": "CHANGES_REQUESTED"]]]
        ])
        #expect(blocked.reviewDecision == .changesRequested)
        let silent = try map(["latestOpinionatedReviews": ["nodes": [["state": "COMMENTED"]]]])
        #expect(silent.reviewDecision == ReviewDecision.none)
        #expect(try map([:]).reviewDecision == ReviewDecision.none)
    }

    @Test func explicitDecisionWinsOverLatestReviews() throws {
        let pr = try map([
            "reviewDecision": "REVIEW_REQUIRED",
            "latestOpinionatedReviews": ["nodes": [["state": "APPROVED"]]],
        ])
        #expect(pr.reviewDecision == .reviewRequired)
    }

    @Test func dismissedViewerReviewCountsAsNoReview() throws {
        let pr = try map(["viewerLatestReview": ["state": "DISMISSED", "submittedAt": "2026-08-02T10:00:00Z"]])
        #expect(pr.viewerReview == nil)
        #expect(Classifier.classify(pr, viewer: "me")?.section == .needsReview)
    }
}
