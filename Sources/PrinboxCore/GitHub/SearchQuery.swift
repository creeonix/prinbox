import Foundation

/// Phase 1 of a refresh: one request, up to four ids-only searches. Measured at 1 point and about 2 s for
/// 120 hits; with the row fields nested here instead, 60 hits took 7.6 s and 90 hit GitHub's 10 s limit.
public enum SearchQuery {
    public static let pageSize = 30
    /// GitHub rejects longer search strings.
    public static let queryLimit = 256

    /// The four searches, always: `involved` is the one that returns the PRs you reviewed (spec 0.8 3.3). They are
    /// disjoint: `involved` excludes the other three qualifiers. `scope` changes every qualifier (spec 0.7 4.2).
    public static func text(scope: SearchScope = .none) -> String {
        let searches = SearchSource.allCases.map { source in
            "  \(source.rawValue): search(query: \"\(query(source, scope: scope))\","
                + " type: ISSUE, first: \(pageSize)) { issueCount nodes { ... on PullRequest { id updatedAt } } }"
        }
        return
            (["query InboxIDs {", "  viewer { login }", "  rateLimit { cost remaining resetAt }"] + searches + ["}"])
            .joined(separator: "\n")
    }

    /// The whole search string for one source, as GitHub sees it.
    public static func query(_ source: SearchSource, scope: SearchScope = .none) -> String {
        "is:pr is:open archived:false \(qualifier(source, scope: scope)) sort:updated-desc"
    }

    /// How many characters the longest query exceeds `queryLimit` by; 0 when every one fits (spec 0.7 3.3).
    public static func overflow(scope: SearchScope) -> Int {
        let longest = SearchSource.allCases.map { query($0, scope: scope).count }.max() ?? 0
        return max(0, longest - queryLimit)
    }

    /// Direct-only swaps `review-requested` for `user-review-requested` in the inclusion and the exclusions
    /// alike, so the searches stay disjoint and a team-requested PR can reach Mentions or Replies to you on its
    /// own merits. Hidden drafts apply to other people's PRs only; the user's own search keeps them. The default
    /// repositories narrow every search (`user:owner` for `owner/*`, `repo:owner/name` otherwise, ORed).
    static func qualifier(_ source: SearchSource, scope: SearchScope = .none) -> String {
        let requested = scope.directReviewRequestsOnly ? "user-review-requested" : "review-requested"
        let draft = scope.hideDrafts ? " -is:draft" : ""
        let repos = scope.repositories.map(RepositoryEntries.qualifier(for:)).joined()
        switch source {
        case .review: return "\(requested):@me\(draft)\(repos)"
        case .mentions: return "mentions:@me -author:@me -\(requested):@me\(draft)\(repos)"
        case .mine: return "author:@me\(repos)"
        case .involved: return "involves:@me -author:@me -\(requested):@me -mentions:@me\(draft)\(repos)"
        }
    }
}
