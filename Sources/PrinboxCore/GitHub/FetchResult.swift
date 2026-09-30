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
