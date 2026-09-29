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

    public init(
        viewerLogin: String, pullRequests: [PullRequest], totals: [SearchSource: Int],
        fetched: [SearchSource: Int], warnings: [String]
    ) {
        self.viewerLogin = viewerLogin
        self.pullRequests = pullRequests
        self.totals = totals
        self.fetched = fetched
        self.warnings = warnings
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
    case other(String)
}
