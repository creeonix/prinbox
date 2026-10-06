import Foundation

/// Phase 1 of a refresh: one request, up to four ids-only searches. Measured at 1 point and about 2 s for
/// 120 hits; with the row fields nested here instead, 60 hits took 7.6 s and 90 hit GitHub's 10 s limit.
public enum SearchQuery {
    public static let pageSize = 30

    /// `includeInvolved` adds the search behind Replies to you (Follow review threads on). The four searches
    /// are disjoint: `involved` excludes the other three qualifiers. `scope` changes every qualifier (spec 4.2).
    public static func text(includeInvolved: Bool, scope: SearchScope = .none) -> String {
        let searches = SearchSource.allCases.filter { includeInvolved || $0 != .involved }.map { source in
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

    /// Direct-only swaps `review-requested` for `user-review-requested` in the inclusion and the exclusions
    /// alike, so the searches stay disjoint and a team-requested PR can reach Mentions or Replies to you on its
    /// own merits. Hidden drafts apply to other people's PRs only; the user's own search keeps them.
    static func qualifier(_ source: SearchSource, scope: SearchScope = .none) -> String {
        let requested = scope.directReviewRequestsOnly ? "user-review-requested" : "review-requested"
        let draft = scope.hideDrafts ? " -is:draft" : ""
        switch source {
        case .review: return "\(requested):@me\(draft)"
        case .mentions: return "mentions:@me -author:@me -\(requested):@me\(draft)"
        case .mine: return "author:@me"
        case .involved: return "involves:@me -author:@me -\(requested):@me -mentions:@me\(draft)"
        }
    }
}
