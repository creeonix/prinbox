import Foundation

/// Sample inbox for screenshots and demos (`Prinbox --demo`). It never runs gh; every repository and
/// login is fictional (three orgs: acme, globex, initech), every mark state appears at least once, and
/// every time is relative to the moment the fetcher was created, so ages read naturally and refreshes
/// return identical PRs: nothing "changes", the demo snooze stays asleep and the new marks stay put.
/// Includes two replies to you (waiting 4h and 1h), one unanswered open thread on an approved PR, and two
/// stacks: bob's #1291 on #1290 inside Needs your review, and your #1301 on #1298 across Your PRs and Waiting
/// on others.
public struct DemoFetcher: InboxFetching {
    private let base: Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        base = now()
    }

    /// The demo never answers `.unchanged`: its data is frozen anyway, and the inbox is built once. Default
    /// repositories narrow the sample (spec 3.4) so the filtered popover can be shown; the other switches are ignored.
    public func fetch(_ request: FetchRequest) async throws -> FetchOutcome {
        let entries = request.scope.repositories
        let prs = DemoData.pullRequests(now: base).filter { pr in
            entries.isEmpty || entries.contains { RepositoryEntries.covers($0, repository: pr.repository) }
        }
        let counts = Dictionary(grouping: prs, by: \.source).mapValues(\.count)
        let fetched = Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, counts[$0] ?? 0) })
        return .result(
            FetchResult(viewerLogin: "me", pullRequests: prs, totals: fetched, fetched: fetched, warnings: []))
    }

    /// One snoozed review request and four rows that are new since the last look, for screenshots.
    public var initialState: AppState { DemoData.initialState(now: base) }
}

enum DemoData {
    /// The re-requested review is parked; a second Take-another-look PR keeps that section populated.
    static let snoozedID = "DEMO_1284"
    /// Two review requests, the mention and a reply are new since the last look.
    static let newIDs: Set<String> = ["DEMO_2104", "DEMO_482", "DEMO_58", "DEMO_145"]

    static func initialState(now: Date) -> AppState {
        let prs = pullRequests(now: now)
        let snoozed = prs.filter { $0.id == snoozedID }.map {
            ($0.id, SnoozeEntry(snoozedAt: now.addingTimeInterval(-3600), updatedAt: $0.updatedAt))
        }
        let seen = prs.filter { !newIDs.contains($0.id) }.map { ($0.id, $0.updatedAt) }
        return AppState(
            snoozed: Dictionary(uniqueKeysWithValues: snoozed), seen: Dictionary(uniqueKeysWithValues: seen))
    }

    static func pullRequests(now: Date) -> [PullRequest] {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func comment(_ login: String, _ hoursAgo: Double) -> ThreadComment {
            ThreadComment(authorLogin: login, createdAt: ago(hoursAgo))
        }
        func thread(_ comments: ThreadComment..., resolved: Bool = false) -> ReviewThread {
            ReviewThread(isResolved: resolved, comments: comments)
        }
        func pr(
            _ number: Int, _ title: String, repo: String, author: String, _ additions: Int, _ deletions: Int,
            updated: Double, source: SearchSource, isDraft: Bool = false, decision: ReviewDecision = .reviewRequired,
            ci: CIState = .success, mergeable: Mergeable = .mergeable, comments: Int = 0,
            reviewed: Double? = nil, requested: Double? = nil, threads: [ReviewThread]? = nil,
            head: String? = nil, base: String? = nil
        ) -> PullRequest {
            PullRequest(
                id: "DEMO_\(number)", number: number, title: title,
                url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, repository: repo, isArchived: false,
                authorLogin: author, avatarURL: nil, isDraft: isDraft, additions: additions, deletions: deletions,
                createdAt: ago(24 * 5), updatedAt: ago(updated), reviewDecision: decision, mergeable: mergeable,
                ci: ci, viewerReview: reviewed.map { ViewerReview(state: "COMMENTED", submittedAt: ago($0)) },
                reviewRequestedAt: requested.map(ago), readyForReviewAt: nil, source: source,
                commentCount: comments, ownerAvatarURL: nil, ownerIsOrganization: true,
                headRef: head, baseRef: base, threads: threads)
        }
        return [
            pr(
                1290, "Migrate the settings page to the new design system", repo: "acme/web", author: "bob",
                620, 410, updated: 3, source: .review, comments: 3, requested: 50,
                head: "settings-redesign", base: "main"),
            pr(
                1291, "Settings page: migrate the notifications tab", repo: "acme/web", author: "bob",
                140, 65, updated: 2, source: .review, ci: .pending, comments: 1, requested: 49,
                head: "settings-notifications", base: "settings-redesign"),
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
                917, "Add a retry budget to the sync worker", repo: "globex/sync", author: "grace",
                210, 44, updated: 5, source: .review, comments: 6, reviewed: 30, requested: 5),
            // Replies to you: alice answered two of your threads; you are no longer a requested reviewer, so the
            // involved search is what finds this PR.
            pr(
                2077, "Stream large uploads instead of buffering them", repo: "acme/api", author: "alice",
                188, 41, updated: 3, source: .involved, comments: 9, reviewed: 26,
                threads: [
                    thread(comment("alice", 30), comment("me", 26), comment("alice", 4)),
                    thread(comment("alice", 28), comment("me", 26), comment("alice", 3)),
                    thread(comment("me", 27), comment("alice", 25), resolved: true),
                ]),
            // Re-requested and answered by another reviewer: the answer owed wins over Take another look.
            pr(
                145, "Rotate the signing keys quarterly", repo: "globex/billing", author: "frank",
                64, 12, updated: 1, source: .review, comments: 5, reviewed: 20, requested: 1,
                threads: [thread(comment("frank", 22), comment("me", 20), comment("heidi", 1))]),
            pr(
                58, "Document the release process", repo: "initech/docs", author: "erin",
                140, 6, updated: 0.5, source: .mentions, ci: .none, comments: 4),
            pr(
                1301, "Speed up search indexing", repo: "acme/web", author: "me",
                388, 120, updated: 1, source: .mine, ci: .failure, comments: 2,
                head: "search-indexing", base: "swift-6-4"),
            pr(
                489, "Retry webhook deliveries with backoff", repo: "acme/api", author: "me",
                75, 20, updated: 6, source: .mine, decision: .approved, comments: 5,
                threads: [thread(comment("bob", 5))]),
            pr(
                310, "Reconcile invoices nightly", repo: "globex/billing", author: "me",
                142, 61, updated: 4, source: .mine, decision: .approved, mergeable: .conflicting),
            pr(
                612, "Rewrite the TPS report generator", repo: "initech/tps", author: "me",
                540, 233, updated: 9, source: .mine, decision: .changesRequested, comments: 9),
            pr(
                1298, "Bump the Swift toolchain to 6.4", repo: "acme/web", author: "me",
                4, 4, updated: 20, source: .mine, ci: .pending, head: "swift-6-4", base: "main"),
            pr(
                33, "Add a cover sheet to every report", repo: "initech/tps", author: "me",
                27, 3, updated: 30, source: .mine, comments: 1),
            pr(
                91, "Explore an offline mode", repo: "acme/shop", author: "me",
                512, 30, updated: 72, source: .mine, isDraft: true, ci: .none),
        ]
    }
}
