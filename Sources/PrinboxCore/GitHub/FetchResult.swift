import Foundation

/// One successful refresh, before classification.
public struct FetchResult: Sendable, Equatable {
    public let viewerLogin: String
    /// Deduplicated by id; the first search in `SearchSource` order wins.
    public let pullRequests: [PullRequest]
    /// `issueCount` per search: everything GitHub has.
    public let totals: [SearchSource: Int]
    /// Nodes returned per search, including null entries.
    public let fetched: [SearchSource: Int]
    /// Partial-data warnings from GraphQL `errors` that came with usable `data`.
    public let warnings: [String]
    /// Points GitHub charged for the requests of this fetch (phase 1 plus every batch), for the log.
    public let cost: Int
    /// `id -> updatedAt` of every search hit. The next refresh sends it back; an identical set skips phase 2.
    public let fingerprint: [String: Date]

    public init(
        viewerLogin: String, pullRequests: [PullRequest], totals: [SearchSource: Int],
        fetched: [SearchSource: Int], warnings: [String], cost: Int = 0, fingerprint: [String: Date] = [:]
    ) {
        self.viewerLogin = viewerLogin
        self.pullRequests = pullRequests
        self.totals = totals
        self.fetched = fetched
        self.warnings = warnings
        self.cost = cost
        self.fingerprint = fingerprint
    }

    /// True when nothing was left out: no partial-result warning, and every search returned as many nodes as
    /// GitHub counted for it. Only a complete fetch may say that a PR is gone.
    public var isComplete: Bool {
        warnings.isEmpty
            && SearchSource.allCases.filter(\.boundsCompleteness).allSatisfy { (fetched[$0] ?? 0) >= (totals[$0] ?? 0) }
    }
}

/// Why a refresh failed. Partial data is not an error; it arrives as `FetchResult.warnings`.
public enum FetchError: Error, Sendable, Equatable {
    case ghNotFound
    case loggedOut
    case offline
    case timedOut
    case rateLimited(resetAt: Date?)
    case badResponse
    case githubUnavailable(status: Int)
    case other(String)
}

/// Stored in the cache without `cost` (a per-fetch figure) and `fingerprint` (a sibling key there).
extension FetchResult: Codable {
    enum CodingKeys: String, CodingKey {
        case viewerLogin
        case pullRequests
        case totals
        case fetched
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            viewerLogin: try container.decode(String.self, forKey: .viewerLogin),
            pullRequests: try container.decode([PullRequest].self, forKey: .pullRequests),
            totals: try container.decode([SearchSource: Int].self, forKey: .totals),
            fetched: try container.decode([SearchSource: Int].self, forKey: .fetched),
            warnings: try container.decode([String].self, forKey: .warnings))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(viewerLogin, forKey: .viewerLogin)
        try container.encode(pullRequests, forKey: .pullRequests)
        try container.encode(totals, forKey: .totals)
        try container.encode(fetched, forKey: .fetched)
        try container.encode(warnings, forKey: .warnings)
    }
}
