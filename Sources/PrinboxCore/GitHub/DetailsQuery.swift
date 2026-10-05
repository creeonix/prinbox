import Foundation

/// Phase 2: rows and conversation for a batch of ids through `nodes(ids:)`. Ten ids per request keep each one
/// far under GitHub's 10 s limit (3.6 s measured for the heaviest public PRs with every batch concurrent).
public enum DetailsQuery {
    public static let placeholder = "__IDS__"

    static let rowFields = [
        "id number title url isDraft additions deletions createdAt updatedAt totalCommentsCount",
        "headRefName baseRefName isCrossRepository",
        "author { login avatarUrl(size: 64) }",
        "repository { nameWithOwner isArchived owner { __typename login avatarUrl(size: 64) } }",
        "reviewDecision mergeable",
        "viewerLatestReview { state submittedAt }",
        "latestOpinionatedReviews(first: 10) { nodes { state } }",
        "commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }",
        "timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) { nodes { __typename"
            + " ... on ReviewRequestedEvent { createdAt requestedReviewer { __typename ... on User { login } } }"
            + " ... on ReadyForReviewEvent { createdAt } } }",
    ]

    /// Thread and review pages. 30 threads of 20 comments cost half of 50 by 50; a truncated page is logged.
    /// No body text anywhere: no rule reads it, and fixtures and logs stay free of it.
    static let conversationFields = [
        "reviewThreads(last: 30) { totalCount nodes { isResolved comments(last: 20) { totalCount nodes { author { login } createdAt } } } }",
        "reviews(last: 50) { totalCount nodes { author { login } state submittedAt } }",
    ]

    /// The query with `__IDS__` where the id list goes; `scripts/record-fixture.sh` fills it in.
    public static func template(includeConversation: Bool) -> String {
        let fields = rowFields + (includeConversation ? conversationFields : [])
        let head = [
            "query PullRequests {", "  rateLimit { cost remaining resetAt }", "  nodes(ids: [\(placeholder)]) {",
            "    ... on PullRequest {",
        ]
        return (head + fields.map { "      " + $0 } + ["    }", "  }", "}"]).joined(separator: "\n")
    }

    /// Ids inlined as a quoted list. Anything that is not a GitHub node id is dropped, so nothing that came
    /// back in a response can change the shape of the next query. The caller logs what was dropped.
    public static func text(ids: [String], includeConversation: Bool) -> String {
        let list = validIDs(ids).map { "\"\($0)\"" }.joined(separator: ", ")
        return template(includeConversation: includeConversation).replacingOccurrences(of: placeholder, with: list)
    }

    /// The ids `text` would keep, in order.
    public static func validIDs(_ ids: [String]) -> [String] { ids.filter(isValidID) }

    /// Node ids are base64url-like: ASCII letters and digits, `_`, `-` and `=`.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "=") }
    }
}
