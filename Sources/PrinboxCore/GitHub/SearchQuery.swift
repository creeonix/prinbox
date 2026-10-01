import Foundation

/// Phase 1 of a refresh: one request, up to four ids-only searches. Measured at 1 point and about 2 s for
/// 120 hits; with the row fields nested here instead, 60 hits took 7.6 s and 90 hit GitHub's 10 s limit.
public enum SearchQuery {
    public static let pageSize = 30

    /// `includeInvolved` adds the search behind Replies to you (Follow review threads on). The four searches
    /// are disjoint: `involved` excludes the other three qualifiers.
    public static func text(includeInvolved: Bool) -> String {
        let searches = SearchSource.allCases.filter { includeInvolved || $0 != .involved }.map { source in
            "  \(source.rawValue): search(query: \"is:pr is:open archived:false \(qualifier(source)) sort:updated-desc\","
                + " type: ISSUE, first: \(pageSize)) { issueCount nodes { ... on PullRequest { id updatedAt } } }"
        }
        return
            (["query InboxIDs {", "  viewer { login }", "  rateLimit { cost remaining resetAt }"] + searches + ["}"])
            .joined(separator: "\n")
    }

    static func qualifier(_ source: SearchSource) -> String {
        switch source {
        case .review: "review-requested:@me"
        case .mentions: "mentions:@me -author:@me -review-requested:@me"
        case .mine: "author:@me"
        case .involved: "involves:@me -author:@me -review-requested:@me -mentions:@me"
        }
    }
}
