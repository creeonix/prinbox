import Foundation

/// Sample inbox for screenshots and demos (`Prinbox --demo`). It never runs gh; every repository and login is fictional (three orgs: acme, globex,
/// initech), and every mark state appears at least once.
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
            ci: CIState = .success, mergeable: Mergeable = .mergeable, comments: Int = 0,
            reviewed: Double? = nil, requested: Double? = nil
        ) -> PullRequest {
            PullRequest(
                id: "DEMO_\(number)", number: number, title: title,
                url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, repository: repo, isArchived: false,
                authorLogin: author, avatarURL: nil, isDraft: isDraft, additions: additions, deletions: deletions,
                createdAt: ago(24 * 5), updatedAt: ago(updated), reviewDecision: decision, mergeable: mergeable,
                ci: ci, viewerReview: reviewed.map { ViewerReview(state: "COMMENTED", submittedAt: ago($0)) },
                reviewRequestedAt: requested.map(ago), readyForReviewAt: nil, source: source,
                commentCount: comments, ownerAvatarURL: nil, ownerIsOrganization: true)
        }
        return [
            pr(
                1290, "Migrate the settings page to the new design system", repo: "acme/web", author: "bob",
                620, 410, updated: 3, source: .review, comments: 3, requested: 50),
            pr(
                2104, "Charge sales tax per region", repo: "globex/billing", author: "frank",
                301, 88, updated: 2, source: .review, decision: .changesRequested, ci: .failure, comments: 7,
                requested: 8),
            pr(
                482, "Add rate limiting to the public API", repo: "acme/api", author: "alice",
                214, 37, updated: 1, source: .review, ci: .pending, requested: 5),
            pr(
                77, "Fix the flaky checkout integration test", repo: "acme/shop", author: "carol",
                18, 9, updated: 2, source: .review, isDraft: true, ci: .none, comments: 1, requested: 2),
            pr(
                1284, "Cache avatar images on disk", repo: "acme/web", author: "dave",
                96, 12, updated: 3, source: .review, decision: .approved, comments: 12, reviewed: 50, requested: 3),
            pr(
                58, "Document the release process", repo: "initech/docs", author: "erin",
                140, 6, updated: 0.5, source: .mentions, ci: .none, comments: 4),
            pr(
                1301, "Speed up search indexing", repo: "acme/web", author: "me",
                388, 120, updated: 1, source: .mine, ci: .failure, comments: 2),
            pr(
                489, "Retry webhook deliveries with backoff", repo: "acme/api", author: "me",
                75, 20, updated: 6, source: .mine, decision: .approved, comments: 5),
            pr(
                310, "Reconcile invoices nightly", repo: "globex/billing", author: "me",
                142, 61, updated: 4, source: .mine, decision: .approved, mergeable: .conflicting),
            pr(
                612, "Rewrite the TPS report generator", repo: "initech/tps", author: "me",
                540, 233, updated: 9, source: .mine, decision: .changesRequested, comments: 9),
            pr(
                1298, "Bump the Swift toolchain to 6.4", repo: "acme/web", author: "me",
                4, 4, updated: 20, source: .mine, ci: .pending),
            pr(
                33, "Add a cover sheet to every report", repo: "initech/tps", author: "me",
                27, 3, updated: 30, source: .mine, comments: 1),
            pr(
                91, "Explore an offline mode", repo: "acme/shop", author: "me",
                512, 30, updated: 72, source: .mine, isDraft: true, ci: .none),
        ]
    }
}
