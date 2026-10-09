import Foundation

/// Hand-built gh responses for the two-phase fetch, as the bytes gh would print.
enum TwoPhaseJSON {
    static let updatedAt = "2026-08-01T10:00:00Z"
    static var rateLimit: [String: Any] { ["cost": 1, "remaining": 4900, "resetAt": "2026-08-01T13:00:00Z"] }

    /// One search hit.
    static func hit(_ id: String, updatedAt: String = updatedAt) -> [String: Any] {
        ["id": id, "updatedAt": updatedAt]
    }

    /// A phase 1 response. `involved` nil leaves the search out of the fake response; the client decodes it as absent.
    static func search(
        review: [Any] = [], mentions: [Any] = [], mine: [Any] = [], involved: [Any]? = nil,
        viewer: String = "me", cost: Int = 1, errors: [[String: Any]]? = nil
    ) -> Data {
        var data: [String: Any] = [
            "viewer": ["login": viewer], "rateLimit": rateLimit.merging(["cost": cost]) { _, new in new },
            "review": ["issueCount": review.count, "nodes": review],
            "mentions": ["issueCount": mentions.count, "nodes": mentions],
            "mine": ["issueCount": mine.count, "nodes": mine],
        ]
        if let involved { data["involved"] = ["issueCount": involved.count, "nodes": involved] }
        var body: [String: Any] = ["data": data]
        if let errors { body["errors"] = errors }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    /// A minimal details node; `overrides` replace or add fields.
    static func node(_ id: String, _ overrides: [String: Any] = [:]) -> [String: Any] {
        let base: [String: Any] = [
            "id": id, "number": 1, "title": "T \(id)", "url": "https://github.com/acme/web/pull/1",
            "isDraft": false, "additions": 1, "deletions": 0,
            "createdAt": "2026-08-01T09:00:00Z", "updatedAt": updatedAt,
            "author": ["login": "alice", "avatarUrl": "https://avatars.githubusercontent.com/u/1"],
            "repository": ["nameWithOwner": "acme/web", "isArchived": false],
            "reviewDecision": NSNull(), "mergeable": "MERGEABLE", "viewerLatestReview": NSNull(),
            "commits": ["nodes": []], "timelineItems": ["nodes": []],
        ]
        return base.merging(overrides) { _, new in new }
    }

    /// A phase 2 response for one batch. `nodes` may hold `NSNull()` for ids GitHub could not resolve.
    static func details(_ nodes: [Any], cost: Int = 5, errors: [[String: Any]]? = nil) -> Data {
        var body: [String: Any] = [
            "data": ["rateLimit": rateLimit.merging(["cost": cost]) { _, new in new }, "nodes": nodes]
        ]
        if let errors { body["errors"] = errors }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    /// The ids a details query names, in order (the only quoted strings in that query).
    static func requestedIDs(in query: String) -> [String] {
        query.matches(of: /"([A-Za-z0-9_=-]+)"/).map { String($0.1) }
    }
}
