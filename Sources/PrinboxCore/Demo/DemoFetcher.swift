import Foundation

/// Sample inbox for screenshots and demos (`Prinbox --demo`). It never runs gh; every repository and
/// login is fictional (three orgs: acme, globex, initech), every mark state appears at least once, and
/// every time is relative to the moment the fetcher was created, so ages read naturally and refreshes
/// return identical PRs: nothing "changes", the demo snooze stays asleep and the new marks stay put.
/// Includes two replies to you (waiting 4h and 1h), one unanswered open thread on an approved PR, two pushes
/// since your review (#2210 after an approval, #733 after a force-push over requested changes), three reviewed
/// rows for the Reviewed section (#1250, #702, #140), and two stacks: bob's #1291 on #1290 inside Needs your
/// review, and your #1301 on #1298 across Your PRs and Waiting on others. 22 PRs in all.
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
            head: String? = nil, base: String? = nil,
            lastCommit: Double? = nil, verdict: String? = nil, verdictAt: Double? = nil, verdictOid: String? = nil,
            headOid: String? = nil, recent: [String]? = nil, commits: Int? = nil
        ) -> PullRequest {
            PullRequest(
                id: "DEMO_\(number)", number: number, title: title,
                url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, repository: repo, isArchived: false,
                authorLogin: author, avatarURL: nil, isDraft: isDraft, additions: additions, deletions: deletions,
                createdAt: ago(24 * 5), updatedAt: ago(updated), reviewDecision: decision, mergeable: mergeable,
                ci: ci,
                viewerReview: reviewed.map {
                    ViewerReview(state: verdict ?? "COMMENTED", submittedAt: ago($0), commitOid: verdictOid)
                },
                reviewRequestedAt: requested.map(ago), readyForReviewAt: nil, source: source,
                commentCount: comments, ownerAvatarURL: nil, ownerIsOrganization: true,
                headRef: head, baseRef: base, lastCommitAt: lastCommit.map(ago), threads: threads,
                headOid: headOid,
                viewerVerdict: verdict.map {
                    ViewerReview(state: $0, submittedAt: verdictAt.map(ago), commitOid: verdictOid)
                },
                recentCommitOids: recent, commitCount: commits)
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
            // Take another look: you approved two days ago and alice pushed twice since; the row opens the diff
            // since your review (spec 0.8 3.7).
            pr(
                2210, "Index the audit log by actor", repo: "acme/api", author: "alice",
                96, 14, updated: 6, source: .involved, comments: 3, reviewed: 48, lastCommit: 6,
                verdict: "APPROVED", verdictAt: 48, verdictOid: "3f9c2d1", headOid: "b7e41a0",
                recent: ["90ab12c", "3f9c2d1", "5d6e7f8", "b7e41a0"], commits: 4),
            // Take another look: you requested changes and frank force-pushed a rewrite; your commit is gone.
            pr(
                733, "Split the invoice job", repo: "globex/billing", author: "frank",
                230, 120, updated: 2, source: .involved, ci: .failure, comments: 2, reviewed: 26, lastCommit: 2,
                verdict: "CHANGES_REQUESTED", verdictAt: 26, verdictOid: "a1b2c3d", headOid: "e5f6a7b",
                recent: ["c0ffee1", "d00d1e2", "e5f6a7b"], commits: 3),
            // Reviewed (shown with --all or Show reviewed): approved and quiet, changes requested and quiet, and a
            // comment-only review.
            pr(
                1250, "Refund flow rework", repo: "acme/web", author: "bob",
                410, 95, updated: 12, source: .involved, decision: .approved, comments: 4, reviewed: 30,
                verdict: "APPROVED", verdictAt: 30, verdictOid: "7a7a7a7", headOid: "7a7a7a7",
                recent: ["1111111", "7a7a7a7"], commits: 2),
            pr(
                702, "Rotate the API keys", repo: "globex/billing", author: "heidi",
                58, 22, updated: 20, source: .involved, decision: .changesRequested, comments: 3, reviewed: 22,
                verdict: "CHANGES_REQUESTED", verdictAt: 22, verdictOid: "beefcaf", headOid: "beefcaf",
                recent: ["beefcaf"], commits: 1),
            pr(
                140, "Clarify the on-call guide", repo: "initech/docs", author: "erin",
                31, 8, updated: 28, source: .involved, ci: .none, comments: 2, reviewed: 28,
                headOid: "0c0c0c0", recent: ["0c0c0c0"], commits: 1),
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
