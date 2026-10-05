// Ported from Pullover (https://github.com/omgovich/pullover), src/core/map-pr.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// Turns the two decoded responses into domain values.
enum PullRequestMapper {
    /// Phase 1 and the batches of phase 2 into one `FetchResult`. Ids come from the searches, first source wins;
    /// a hit whose node no batch returned (deleted meanwhile, or null beside an error) is skipped, while its
    /// search still counts it as fetched and the error becomes a warning, so nothing is pruned on its account.
    static func merge(search: SearchResponse, details: [DetailsResponse]) throws -> FetchResult {
        let errors = (search.errors ?? []) + details.flatMap { $0.errors ?? [] }
        if GraphQLErrors.isRateLimited(errors) {
            throw FetchError.rateLimited(resetAt: search.data?.rateLimit?.resetAt)
        }
        guard let data = search.data, let viewer = data.viewer?.login else {
            throw errors.first.map { FetchError.other(String($0.message.prefix(120))) } ?? FetchError.badResponse
        }
        let nodes = Dictionary(
            details.flatMap { $0.data?.nodes ?? [] }.compactMap { $0 }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        let pullRequests = orderedIDs(search).compactMap { entry in
            nodes[entry.id].map { makePullRequest($0, source: entry.source, viewer: viewer) }
        }
        let cost = (data.rateLimit?.cost ?? 0) + details.reduce(0) { $0 + ($1.data?.rateLimit?.cost ?? 0) }
        return FetchResult(
            viewerLogin: viewer,
            pullRequests: pullRequests,
            totals: perSearch(data) { $0.issueCount },
            fetched: perSearch(data) { $0.nodes.count },
            warnings: GraphQLErrors.warnings(errors),
            cost: cost,
            fingerprint: fingerprint(search)
        )
    }

    /// Every hit in source order, deduplicated (the first search wins), with the search it came from.
    static func orderedIDs(_ search: SearchResponse) -> [(id: String, source: SearchSource)] {
        var seen = Set<String>()
        var ordered: [(id: String, source: SearchSource)] = []
        for source in SearchSource.allCases {
            for node in search.data?.search(for: source)?.nodes ?? [] {
                guard let id = node?.id, !seen.contains(id) else { continue }
                seen.insert(id)
                ordered.append((id, source))
            }
        }
        return ordered
    }

    /// `id -> updatedAt` over every hit. Two equal fingerprints mean nothing that moves `updatedAt` happened.
    static func fingerprint(_ search: SearchResponse) -> [String: Date] {
        var map: [String: Date] = [:]
        for source in SearchSource.allCases {
            for node in search.data?.search(for: source)?.nodes ?? [] {
                if let id = node?.id, let updatedAt = node?.updatedAt { map[id] = updatedAt }
            }
        }
        return map
    }

    /// Thread, comment or review pages that GitHub cut at the requested size, for the log.
    static func truncatedPages(_ details: [DetailsResponse]) -> Int {
        details.flatMap { $0.data?.nodes ?? [] }.compactMap { $0 }.reduce(0) { count, node in
            let reviews = node.reviews.map { ($0.totalCount ?? 0) > $0.nodes.count ? 1 : 0 } ?? 0
            guard let threads = node.reviewThreads else { return count + reviews }
            let cut = (threads.totalCount ?? 0) > threads.nodes.count ? 1 : 0
            let comments = threads.nodes.compactMap { $0?.comments }.filter { ($0.totalCount ?? 0) > $0.nodes.count }
                .count
            return count + cut + comments + reviews
        }
    }

    /// Only searches the query asked for get an entry (`involved` is absent with the setting off).
    private static func perSearch(
        _ data: SearchResponse.Payload, _ value: (SearchResponse.Search) -> Int
    ) -> [SearchSource: Int] {
        Dictionary(
            uniqueKeysWithValues: SearchSource.allCases.compactMap { source in
                data.search(for: source).map { (source, value($0)) }
            })
    }

    static func makePullRequest(_ node: PRNode, source: SearchSource, viewer: String) -> PullRequest {
        let events = (node.timelineItems?.nodes ?? []).compactMap { $0 }
        let lastCommit = node.commits?.nodes.compactMap { $0 }.last?.commit
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
            ci: ciState(lastCommit?.statusCheckRollup?.state),
            viewerReview: viewerReview(node.viewerLatestReview),
            reviewRequestedAt: reviewRequestedAt(events, viewer: viewer),
            readyForReviewAt: events.filter { $0.typename == "ReadyForReviewEvent" }.compactMap(\.createdAt).max(),
            source: source,
            commentCount: node.totalCommentsCount ?? 0,
            ownerAvatarURL: node.repository.owner?.avatarUrl,
            ownerIsOrganization: node.repository.owner?.typename == "Organization",
            headRef: node.headRefName,
            baseRef: node.baseRefName,
            lastCommitAt: lastCommit?.committedDate,
            threads: node.reviewThreads.map(threads),
            reviews: node.reviews.map(reviews),
            isCrossRepository: node.isCrossRepository ?? false
        )
    }

    /// Comments keep GitHub's order (oldest first); a deleted author is "ghost", like a deleted PR author.
    static func threads(_ connection: PRNode.Connection<PRNode.ThreadNode>) -> [ReviewThread] {
        connection.nodes.compactMap { $0 }.map { thread in
            ReviewThread(
                isResolved: thread.isResolved,
                comments: (thread.comments?.nodes ?? []).compactMap { $0 }.map {
                    ThreadComment(authorLogin: $0.author?.login ?? "ghost", createdAt: $0.createdAt)
                })
        }
    }

    /// Pending reviews are unsubmitted drafts of the viewer and never count.
    static func reviews(_ connection: PRNode.Connection<PRNode.ReviewNode>) -> [Review] {
        connection.nodes.compactMap { $0 }.filter { $0.state != "PENDING" }.map {
            Review(authorLogin: $0.author?.login ?? "ghost", state: $0.state, submittedAt: $0.submittedAt)
        }
    }

    /// The latest request naming the viewer; otherwise the latest request for a team (or an unknown
    /// reviewer), which is how team review requests reach the viewer.
    static func reviewRequestedAt(_ events: [PRNode.TimelineNode], viewer: String) -> Date? {
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
    static func viewerReview(_ review: PRNode.ViewerReviewNode?) -> ViewerReview? {
        guard let review, review.state != "PENDING", review.state != "DISMISSED" else { return nil }
        return ViewerReview(state: review.state, submittedAt: review.submittedAt)
    }
}
