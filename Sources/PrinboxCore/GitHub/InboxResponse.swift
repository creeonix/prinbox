import Foundation

/// Raw shape of the `gh api graphql` response for `InboxQuery`. Only the mapper reads it.
struct InboxResponse: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?

    static func decode(_ bytes: Data) throws -> InboxResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InboxResponse.self, from: bytes)
    }

    struct Payload: Decodable {
        let viewer: Viewer?
        let rateLimit: RateLimit?
        let review: Search?
        let mentions: Search?
        let mine: Search?

        func search(for source: SearchSource) -> Search? {
            switch source {
            case .review: review
            case .mentions: mentions
            case .mine: mine
            case .involved: nil
            }
        }
    }

    struct Viewer: Decodable { let login: String }
    struct RateLimit: Decodable { let resetAt: Date? }

    struct Search: Decodable {
        let issueCount: Int
        let nodes: [SearchNode?]
    }

    /// A search hit. Hits that are not pull requests come back as `{}` and decode to `pullRequest == nil`.
    struct SearchNode: Decodable {
        let pullRequest: PRNode?

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys
            pullRequest = keys.isEmpty ? nil : try PRNode(from: decoder)
        }
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

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
        let viewerLatestReview: Review?
        let commits: Connection<CommitNode>?
        let timelineItems: Connection<TimelineNode>?
        let totalCommentsCount: Int?
        let latestOpinionatedReviews: Connection<ReviewState>?
    }

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

    struct ReviewState: Decodable { let state: String }

    struct Review: Decodable {
        let state: String
        let submittedAt: Date?
    }

    struct Connection<Node: Decodable>: Decodable {
        let nodes: [Node?]
    }

    struct CommitNode: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
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
}

public struct GraphQLError: Decodable, Sendable, Equatable {
    public let type: String?
    public let message: String
}
