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

    func map(_ overrides: [String: Any], source: SearchSource = .review) throws -> PullRequest {
        let node = TwoPhaseJSON.node("PR_1", Self.base.merging(overrides) { _, new in new })
        let hit: [Any] = [TwoPhaseJSON.hit("PR_1")]
        let search = try SearchResponse.decode(
            TwoPhaseJSON.search(
                review: source == .review ? hit : [], mentions: source == .mentions ? hit : [],
                mine: source == .mine ? hit : [], involved: source == .involved ? hit : nil))
        let details = try DetailsResponse.decode(TwoPhaseJSON.details([node]))
        return try #require(try PullRequestMapper.merge(search: search, details: [details]).pullRequests.first)
    }

    @Test func missingNewFieldsDecodeToDefaults() throws {
        let pr = try map([:])
        #expect(pr.commentCount == 0)
        #expect(pr.ownerAvatarURL == nil)
        #expect(pr.ownerIsOrganization == false)
        #expect(pr.ownerLogin == "acme")
        #expect(pr.headOid == nil)
        #expect(pr.viewerVerdict == nil)
        #expect(pr.recentCommitOids == nil)
        #expect(pr.commitCount == nil)
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

    @Test func missingConversationFieldsAreNil() throws {
        let pr = try map([:])
        #expect(pr.headRef == nil)
        #expect(pr.lastCommitAt == nil)
        #expect(pr.threads == nil)
        #expect(pr.reviews == nil)
    }

    @Test func mapsThreadsReviewsRefsAndTheLastCommit() throws {
        let pr = try map([
            "headRefName": "feature/x", "baseRefName": "main",
            "commits": [
                "nodes": [["commit": ["committedDate": "2026-08-02T08:00:00Z", "statusCheckRollup": NSNull()]]]
            ],
            "reviewThreads": [
                "totalCount": 2,
                "nodes": [
                    [
                        "isResolved": false,
                        "comments": [
                            "totalCount": 2,
                            "nodes": [
                                ["author": ["login": "me"], "createdAt": "2026-08-02T09:00:00Z"],
                                ["author": NSNull(), "createdAt": "2026-08-02T10:00:00Z"],
                            ],
                        ],
                    ],
                    ["isResolved": true, "comments": ["totalCount": 0, "nodes": []]],
                    NSNull(),
                ],
            ],
            "reviews": [
                "totalCount": 3,
                "nodes": [
                    ["author": ["login": "bob"], "state": "APPROVED", "submittedAt": "2026-08-02T11:00:00Z"],
                    ["author": ["login": "carol"], "state": "PENDING", "submittedAt": NSNull()],
                    ["author": NSNull(), "state": "COMMENTED", "submittedAt": "2026-08-02T12:00:00Z"],
                ],
            ],
        ])
        #expect(pr.headRef == "feature/x")
        #expect(pr.baseRef == "main")
        #expect(pr.lastCommitAt == date("2026-08-02T08:00:00Z"))
        #expect(
            pr.threads == [
                ReviewThread(
                    isResolved: false,
                    comments: [
                        ThreadComment(authorLogin: "me", createdAt: date("2026-08-02T09:00:00Z")),
                        ThreadComment(authorLogin: "ghost", createdAt: date("2026-08-02T10:00:00Z")),
                    ]),
                ReviewThread(isResolved: true, comments: []),
            ])
        #expect(
            pr.reviews == [
                Review(authorLogin: "bob", state: "APPROVED", submittedAt: date("2026-08-02T11:00:00Z")),
                Review(authorLogin: "ghost", state: "COMMENTED", submittedAt: date("2026-08-02T12:00:00Z")),
            ])
    }

    @Test func involvedHitsKeepTheirSource() throws {
        #expect(try map([:], source: .involved).source == .involved)
        #expect(try map([:], source: .mine).source == .mine)
    }

    @Test func isCrossRepositoryReadsTrueAndDefaultsToFalse() throws {
        let fork = try DetailsResponse.decode(
            TwoPhaseJSON.details([TwoPhaseJSON.node("PR_1", ["isCrossRepository": true])]))
        let plain = try DetailsResponse.decode(TwoPhaseJSON.details([TwoPhaseJSON.node("PR_2")]))
        let forkPR = PullRequestMapper.makePullRequest(
            try #require(fork.data?.nodes?.first ?? nil), source: .review, viewer: "me")
        let plainPR = PullRequestMapper.makePullRequest(
            try #require(plain.data?.nodes?.first ?? nil), source: .review, viewer: "me")
        #expect(forkPR.isCrossRepository)
        #expect(!plainPR.isCrossRepository)
    }

    @Test func readsTheHeadOidTheVerdictAndTheRecentCommits() throws {
        let pr = try map([
            "headRefOid": "b7e41a0000000000000000000000000000000000",
            "latestOpinionatedReviews": [
                "nodes": [
                    [
                        "state": "APPROVED", "submittedAt": "2026-08-02T10:00:00Z", "author": ["login": "ME"],
                        "commit": ["oid": "3f9c2d1"],
                    ],
                    ["state": "CHANGES_REQUESTED", "author": ["login": "bob"], "commit": ["oid": "b7e41a0"]],
                ]
            ],
            "recent": [
                "totalCount": 4,
                "nodes": [
                    ["commit": ["oid": "90ab12c"]], ["commit": ["oid": "3f9c2d1"]], NSNull(),
                    ["commit": ["oid": "b7e41a0000000000000000000000000000000000"]],
                ],
            ],
        ])
        #expect(pr.headOid == "b7e41a0000000000000000000000000000000000")
        #expect(
            pr.viewerVerdict
                == ViewerReview(state: "APPROVED", submittedAt: date("2026-08-02T10:00:00Z"), commitOid: "3f9c2d1"))
        #expect(pr.recentCommitOids == ["90ab12c", "3f9c2d1", "b7e41a0000000000000000000000000000000000"])
        #expect(pr.commitCount == 4)
        #expect(pr.movedSinceVerdict)
        #expect(pr.commitsSinceVerdict == 1)
    }

    @Test func aCommentedDismissedOrPendingEntryIsNoVerdictAndAnotherUsersIsNotYours() throws {
        for state in ["COMMENTED", "DISMISSED", "PENDING"] {
            let pr = try map([
                "latestOpinionatedReviews": [
                    "nodes": [["state": state, "author": ["login": "me"], "commit": ["oid": "1"]]]
                ]
            ])
            #expect(pr.viewerVerdict == nil, "\(state)")
        }
        let other = try map([
            "latestOpinionatedReviews": ["nodes": [["state": "APPROVED", "author": ["login": "bob"]]]]
        ])
        #expect(other.viewerVerdict == nil)
        #expect(other.reviewDecision == .approved)
    }
}
