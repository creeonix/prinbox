import Foundation

@testable import PrinboxCore

let testViewer = "me"

func date(_ iso: String) -> Date {
    guard let value = ISO8601DateFormatter().date(from: iso) else {
        fatalError("bad test date \(iso)")
    }
    return value
}

func makePR(
    id: String = "PR_1",
    number: Int = 1,
    title: String = "Add feature",
    repository: String = "acme/web",
    isArchived: Bool = false,
    authorLogin: String = "alice",
    isDraft: Bool = false,
    additions: Int = 10,
    deletions: Int = 2,
    createdAt: Date = date("2026-08-01T10:00:00Z"),
    updatedAt: Date = date("2026-08-01T10:00:00Z"),
    reviewDecision: ReviewDecision = .reviewRequired,
    mergeable: Mergeable = .mergeable,
    ci: CIState = .success,
    viewerReview: ViewerReview? = nil,
    reviewRequestedAt: Date? = nil,
    readyForReviewAt: Date? = nil,
    source: SearchSource = .review,
    commentCount: Int = 0,
    headRef: String? = nil,
    baseRef: String? = nil,
    lastCommitAt: Date? = nil,
    threads: [ReviewThread]? = nil,
    reviews: [Review]? = nil
) -> PullRequest {
    PullRequest(
        id: id,
        number: number,
        title: title,
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        repository: repository,
        isArchived: isArchived,
        authorLogin: authorLogin,
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
        isDraft: isDraft,
        additions: additions,
        deletions: deletions,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reviewDecision: reviewDecision,
        mergeable: mergeable,
        ci: ci,
        viewerReview: viewerReview,
        reviewRequestedAt: reviewRequestedAt,
        readyForReviewAt: readyForReviewAt,
        source: source,
        commentCount: commentCount,
        headRef: headRef,
        baseRef: baseRef,
        lastCommitAt: lastCommitAt,
        threads: threads,
        reviews: reviews
    )
}

func makeResult(_ prs: [PullRequest], totals: [SearchSource: Int]? = nil, warnings: [String] = []) -> FetchResult {
    let counts = Dictionary(grouping: prs, by: \.source).mapValues(\.count)
    let fetched = Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, counts[$0] ?? 0) })
    return FetchResult(
        viewerLogin: testViewer, pullRequests: prs, totals: totals ?? fetched, fetched: fetched, warnings: warnings)
}

func comment(_ login: String, _ at: Date) -> ThreadComment {
    ThreadComment(authorLogin: login, createdAt: at)
}

func thread(_ comments: ThreadComment..., resolved: Bool = false) -> ReviewThread {
    ReviewThread(isResolved: resolved, comments: comments)
}
