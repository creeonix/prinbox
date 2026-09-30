// Ported from Pullover (https://github.com/omgovich/pullover), src/core/map-pr.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// Turns a decoded `InboxResponse` into domain values.
enum PullRequestMapper {
    static func map(_ response: InboxResponse) throws -> FetchResult {
        let errors = response.errors ?? []
        if GraphQLErrors.isRateLimited(errors) {
            throw FetchError.rateLimited(resetAt: response.data?.rateLimit?.resetAt)
        }
        guard let data = response.data, let viewer = data.viewer?.login else {
            throw errors.first.map { FetchError.other(String($0.message.prefix(120))) } ?? FetchError.badResponse
        }
        let candidates = SearchSource.allCases.flatMap { source in
            (data.search(for: source)?.nodes ?? [])
                .compactMap { $0?.pullRequest }
                .map { makePullRequest($0, source: source, viewer: viewer) }
        }
        let unique = candidates.reduce(into: [PullRequest]()) { kept, pr in
            if !kept.contains(where: { $0.id == pr.id }) { kept.append(pr) }
        }
        return FetchResult(
            viewerLogin: viewer,
            pullRequests: unique,
            totals: perSearch(data) { $0.issueCount },
            fetched: perSearch(data) { $0.nodes.count },
            warnings: GraphQLErrors.warnings(errors)
        )
    }

    private static func perSearch(
        _ data: InboxResponse.Payload, _ value: (InboxResponse.Search) -> Int
    ) -> [SearchSource: Int] {
        Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, data.search(for: $0).map(value) ?? 0) })
    }

    static func makePullRequest(_ node: InboxResponse.PRNode, source: SearchSource, viewer: String) -> PullRequest {
        let events = (node.timelineItems?.nodes ?? []).compactMap { $0 }
        let rollup = node.commits?.nodes.compactMap { $0 }.last?.commit.statusCheckRollup?.state
        return PullRequest(
            id: node.id,
            number: node.number,
            title: node.title,
            url: node.url,
            repository: node.repository.nameWithOwner,
            isArchived: node.repository.isArchived,
            authorLogin: node.author?.login ?? "ghost",
            avatarURL: node.author?.avatarUrl,
            isDraft: node.isDraft,
            additions: node.additions,
            deletions: node.deletions,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            reviewDecision: reviewDecision(
                node.reviewDecision,
                latestReviews: (node.latestOpinionatedReviews?.nodes ?? []).compactMap { $0?.state }),
            mergeable: mergeable(node.mergeable),
            ci: ciState(rollup),
            viewerReview: viewerReview(node.viewerLatestReview),
            reviewRequestedAt: reviewRequestedAt(events, viewer: viewer),
            readyForReviewAt: events.filter { $0.typename == "ReadyForReviewEvent" }.compactMap(\.createdAt).max(),
            source: source,
            commentCount: node.totalCommentsCount ?? 0,
            ownerAvatarURL: node.repository.owner?.avatarUrl,
            ownerIsOrganization: node.repository.owner?.typename == "Organization"
        )
    }

    /// The latest request naming the viewer; otherwise the latest request for a team (or an unknown
    /// reviewer), which is how team review requests reach the viewer.
    static func reviewRequestedAt(_ events: [InboxResponse.TimelineNode], viewer: String) -> Date? {
        let requests = events.filter { $0.typename == "ReviewRequestedEvent" }
        let direct = requests.filter {
            $0.requestedReviewer?.typename == "User"
                && $0.requestedReviewer?.login?.lowercased() == viewer.lowercased()
        }
        let indirect = requests.filter { $0.requestedReviewer?.typename != "User" }
        return direct.compactMap(\.createdAt).max() ?? indirect.compactMap(\.createdAt).max()
    }

    /// GitHub reports no decision for repositories that require no reviews; the latest opinionated
    /// reviews stand in then: any request for changes blocks, otherwise any approval approves.
    static func reviewDecision(_ raw: String?, latestReviews: [String]) -> ReviewDecision {
        switch raw {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        case nil where latestReviews.contains("CHANGES_REQUESTED"): .changesRequested
        case nil where latestReviews.contains("APPROVED"): .approved
        default: .none
        }
    }

    /// GitHub computes mergeability lazily; anything but MERGEABLE/CONFLICTING is unknown, never a conflict.
    static func mergeable(_ raw: String?) -> Mergeable {
        switch raw {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }
    }

    static func ciState(_ raw: String?) -> CIState {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    /// Pending reviews are unsubmitted and dismissed ones no longer count, so neither is a review.
    static func viewerReview(_ review: InboxResponse.Review?) -> ViewerReview? {
        guard let review, review.state != "PENDING", review.state != "DISMISSED" else { return nil }
        return ViewerReview(state: review.state, submittedAt: review.submittedAt)
    }
}
