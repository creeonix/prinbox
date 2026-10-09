import Foundation

/// Raw shapes of the two `gh api graphql` responses. Only the mapper reads them.
private func iso8601Decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// Phase 1: `SearchQuery`.
struct SearchResponse: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?

    static func decode(_ bytes: Data) throws -> SearchResponse {
        try iso8601Decoder().decode(SearchResponse.self, from: bytes)
    }

    struct Payload: Decodable {
        let viewer: Viewer?
        let rateLimit: RateLimit?
        let review: Search?
        let mentions: Search?
        let mine: Search?
        let involved: Search?

        func search(for source: SearchSource) -> Search? {
            switch source {
            case .review: review
            case .mentions: mentions
            case .mine: mine
            case .involved: involved
            }
        }
    }

    struct Search: Decodable {
        let issueCount: Int
        let nodes: [SearchNode?]
    }

    /// A hit. Hits that are not pull requests come back as `{}` and decode with a nil id.
    struct SearchNode: Decodable {
        let id: String?
        let updatedAt: Date?
    }
}

/// Phase 2: `DetailsQuery`, one response per batch.
struct DetailsResponse: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?

    static func decode(_ bytes: Data) throws -> DetailsResponse {
        try iso8601Decoder().decode(DetailsResponse.self, from: bytes)
    }

    struct Payload: Decodable {
        let rateLimit: RateLimit?
        /// One entry per requested id; null when GitHub could not resolve it (an error explains why).
        let nodes: [PRNode?]?
    }
}

struct Viewer: Decodable { let login: String }

struct RateLimit: Decodable {
    let cost: Int?
    let remaining: Int?
    let resetAt: Date?
}

/// One pull request as `DetailsQuery` returns it.
struct PRNode: Decodable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let additions: Int
    let deletions: Int
    let createdAt: Date
    let updatedAt: Date
    let author: Author?
    let repository: Repository
    let reviewDecision: String?
    let mergeable: String?
    let viewerLatestReview: ViewerReviewNode?
    let commits: Connection<CommitNode>?
    let timelineItems: Connection<TimelineNode>?
    let totalCommentsCount: Int?
    let latestOpinionatedReviews: Connection<ReviewStateNode>?
    let headRefName: String?
    let baseRefName: String?
    let isCrossRepository: Bool?
    let headRefOid: String?
    let reviewThreads: Connection<ThreadNode>?
    let reviews: Connection<ReviewNode>?
    let recent: Connection<OidCommitNode>?

    struct Author: Decodable {
        let login: String
        let avatarUrl: URL?
    }

    struct Repository: Decodable {
        let nameWithOwner: String
        let isArchived: Bool
        let owner: Owner?
    }

    struct Owner: Decodable {
        let typename: String
        let login: String
        let avatarUrl: URL?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case login
            case avatarUrl
        }
    }

    /// An entry of `latestOpinionatedReviews`: the state alone before 0.8.0, the author and commit since.
    struct ReviewStateNode: Decodable {
        let state: String
        let submittedAt: Date?
        let author: Author?
        let commit: CommitRef?
    }

    struct CommitRef: Decodable { let oid: String }

    struct OidCommitNode: Decodable { let commit: CommitRef }

    struct ViewerReviewNode: Decodable {
        let state: String
        let submittedAt: Date?
    }

    /// `totalCount` is present only where the query asks for it (the conversation pages).
    struct Connection<Node: Decodable & Sendable>: Decodable, Sendable {
        let totalCount: Int?
        let nodes: [Node?]
    }

    struct CommitNode: Decodable { let commit: Commit }

    struct Commit: Decodable {
        let committedDate: Date?
        let statusCheckRollup: Rollup?
    }

    struct Rollup: Decodable { let state: String }

    struct TimelineNode: Decodable {
        let typename: String
        let createdAt: Date?
        let requestedReviewer: Reviewer?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case createdAt
            case requestedReviewer
        }
    }

    struct Reviewer: Decodable {
        let typename: String
        let login: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case login
        }
    }

    struct ThreadNode: Decodable {
        let isResolved: Bool
        let comments: Connection<CommentNode>?
    }

    struct CommentNode: Decodable {
        let author: Author?
        let createdAt: Date
    }

    struct ReviewNode: Decodable {
        let author: Author?
        let state: String
        let submittedAt: Date?
    }
}

public struct GraphQLError: Decodable, Sendable, Equatable {
    public let type: String?
    public let message: String
}
