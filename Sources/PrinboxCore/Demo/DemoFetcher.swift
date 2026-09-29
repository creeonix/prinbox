import Foundation

/// Sample inbox for screenshots and demos (`Prinbox --demo`). It never runs gh; every repository and
/// login is fictional, and every time is relative to `now` so ages always read naturally.
public struct DemoFetcher: InboxFetching {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func fetch() async throws -> FetchResult {
        let prs = DemoData.pullRequests(now: now())
        let counts = Dictionary(grouping: prs, by: \.source).mapValues(\.count)
        let fetched = Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, counts[$0] ?? 0) })
        return FetchResult(viewerLogin: "me", pullRequests: prs, totals: fetched, fetched: fetched, warnings: [])
    }
}

enum DemoData {
    static func pullRequests(now: Date) -> [PullRequest] {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func pr(
            _ number: Int, _ title: String, repo: String, author: String, _ additions: Int, _ deletions: Int,
            updated: Double, source: SearchSource, isDraft: Bool = false, decision: ReviewDecision = .reviewRequired,
            ci: CIState = .success, reviewed: Double? = nil, requested: Double? = nil
        ) -> PullRequest {
            PullRequest(
                id: "DEMO_\(number)", number: number, title: title,
                url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, repository: repo, isArchived: false,
                authorLogin: author, avatarURL: nil, isDraft: isDraft, additions: additions, deletions: deletions,
                createdAt: ago(24 * 5), updatedAt: ago(updated), reviewDecision: decision, mergeable: .mergeable,
                ci: ci, viewerReview: reviewed.map { ViewerReview(state: "COMMENTED", submittedAt: ago($0)) },
                reviewRequestedAt: requested.map(ago), readyForReviewAt: nil, source: source)
        }
        return [
            pr(
                1290, "Migrate the settings page to the new design system", repo: "acme/web", author: "bob",
                620, 410, updated: 3, source: .review, requested: 50),
            pr(
                482, "Add rate limiting to the public API", repo: "acme/api", author: "alice",
                214, 37, updated: 1, source: .review, requested: 5),
            pr(
                77, "Fix the flaky checkout integration test", repo: "acme/shop", author: "carol",
                18, 9, updated: 2, source: .review, isDraft: true, requested: 2),
            pr(
                1284, "Cache avatar images on disk", repo: "acme/web", author: "dave",
                96, 12, updated: 3, source: .review, reviewed: 50, requested: 3),
            pr(
                58, "Document the release process", repo: "acme/docs", author: "erin",
                140, 6, updated: 0.5, source: .mentions),
            pr(
                1301, "Speed up search indexing", repo: "acme/web", author: "me",
                388, 120, updated: 1, source: .mine, ci: .failure),
            pr(
                489, "Retry webhook deliveries with backoff", repo: "acme/api", author: "me",
                75, 20, updated: 6, source: .mine, decision: .approved),
            pr(
                1298, "Bump the Swift toolchain to 6.4", repo: "acme/web", author: "me",
                4, 4, updated: 20, source: .mine),
            pr(
                91, "Explore an offline mode", repo: "acme/shop", author: "me",
                512, 30, updated: 72, source: .mine, isDraft: true),
        ]
    }
}
