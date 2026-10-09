import Foundation

/// Which search in `SearchQuery` returned a pull request. Declaration order is the dedupe priority.
public enum SearchSource: String, Sendable, CaseIterable, Codable, CodingKeyRepresentable {
    case review
    case mentions
    case mine
    case involved

    /// The `involved` search is best effort: most of its PRs are hidden, so its truncation must not stop the
    /// completeness checks that prune snoozes and the seen ledger.
    public var boundsCompleteness: Bool { self != .involved }
}

public enum ReviewDecision: String, Sendable, Equatable, Codable {
    case approved
    case changesRequested
    case reviewRequired
    case none
}

public enum Mergeable: String, Sendable, Equatable, Codable {
    case mergeable
    case conflicting
    case unknown
}

public enum CIState: String, Sendable, Equatable, Codable {
    case success
    case failure
    case pending
    case none
}

/// The viewer's latest submitted review. Pending (unsubmitted) reviews are never represented.
public struct ViewerReview: Sendable, Equatable, Codable {
    public let state: String
    public let submittedAt: Date?
    /// The commit the review points at. GitHub re-points it across a rebase that leaves the diff unchanged, so
    /// comparing it with the head is GitHub's own "changes since your last review" (spec 0.8 3.1). Nil in a cache
    /// written before 0.8.0.
    public let commitOid: String?

    public init(state: String, submittedAt: Date?, commitOid: String? = nil) {
        self.state = state
        self.submittedAt = submittedAt
        self.commitOid = commitOid
    }
}

public struct PullRequest: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    /// "owner/name".
    public let repository: String
    public let isArchived: Bool
    public let authorLogin: String
    public let avatarURL: URL?
    public let isDraft: Bool
    public let additions: Int
    public let deletions: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let reviewDecision: ReviewDecision
    public let mergeable: Mergeable
    public let ci: CIState
    public let viewerReview: ViewerReview?
    public let reviewRequestedAt: Date?
    public let readyForReviewAt: Date?
    public let source: SearchSource
    /// `totalCommentsCount`: issue comments plus review comments.
    public let commentCount: Int
    public let ownerAvatarURL: URL?
    /// The repository owner is an organization (false for a user's personal repository).
    public let ownerIsOrganization: Bool
    /// Branch names, for stacked PRs later; nil when phase 2 did not run for this PR.
    public let headRef: String?
    public let baseRef: String?
    /// `committedDate` of the last commit; the snooze rule's commit date.
    public let lastCommitAt: Date?
    /// Review threads and reviews; nil when the conversation was not fetched (setting off, demo without them).
    public let threads: [ReviewThread]?
    public let reviews: [Review]?
    /// The head branch lives in another repository (a fork). Such a PR is never another PR's parent.
    public let isCrossRepository: Bool
    /// `headRefOid`; nil in a cache written before 0.8.0.
    public let headOid: String?
    /// The viewer's latest approval or request for changes (spec 0.8 3.1); nil without one or in an older cache.
    public let viewerVerdict: ViewerReview?
    /// The oids of the last `recentCommitWindow` commits, oldest first, and the PR's commit count (spec 0.8 3.2);
    /// nil in an older cache.
    public let recentCommitOids: [String]?
    public let commitCount: Int?

    public init(
        id: String, number: Int, title: String, url: URL, repository: String, isArchived: Bool,
        authorLogin: String, avatarURL: URL?, isDraft: Bool, additions: Int, deletions: Int,
        createdAt: Date, updatedAt: Date, reviewDecision: ReviewDecision, mergeable: Mergeable,
        ci: CIState, viewerReview: ViewerReview?, reviewRequestedAt: Date?, readyForReviewAt: Date?,
        source: SearchSource, commentCount: Int = 0, ownerAvatarURL: URL? = nil, ownerIsOrganization: Bool = false,
        headRef: String? = nil, baseRef: String? = nil, lastCommitAt: Date? = nil, threads: [ReviewThread]? = nil,
        reviews: [Review]? = nil, isCrossRepository: Bool = false,
        headOid: String? = nil, viewerVerdict: ViewerReview? = nil, recentCommitOids: [String]? = nil,
        commitCount: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.isArchived = isArchived
        self.authorLogin = authorLogin
        self.avatarURL = avatarURL
        self.isDraft = isDraft
        self.additions = additions
        self.deletions = deletions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.ci = ci
        self.viewerReview = viewerReview
        self.reviewRequestedAt = reviewRequestedAt
        self.readyForReviewAt = readyForReviewAt
        self.source = source
        self.commentCount = commentCount
        self.ownerAvatarURL = ownerAvatarURL
        self.ownerIsOrganization = ownerIsOrganization
        self.headRef = headRef
        self.baseRef = baseRef
        self.lastCommitAt = lastCommitAt
        self.threads = threads
        self.reviews = reviews
        self.isCrossRepository = isCrossRepository
        self.headOid = headOid
        self.viewerVerdict = viewerVerdict
        self.recentCommitOids = recentCommitOids
        self.commitCount = commitCount
    }

    /// Repository owner: "acme" for "acme/web". Shown as the org name.
    public var ownerLogin: String {
        repository.split(separator: "/").first.map(String.init) ?? repository
    }

    /// Repository name without the owner: "web" for "acme/web".
    public var repoShortName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

extension PullRequest {
    /// How many commit ids a fetch brings for the count since your verdict.
    public static let recentCommitWindow = 30

    /// The diff moved since your verdict: both oids known and different (spec 0.8 3.2). A rebase that leaves the
    /// diff unchanged does not count, because GitHub re-points the review to the new head.
    public var movedSinceVerdict: Bool {
        guard let head = headOid, let verdict = viewerVerdict?.commitOid else { return false }
        return head != verdict
    }

    /// Commits after the verdict's in the recent list: 0 when nothing moved, nil without a verdict or when the
    /// verdict's commit is no longer on the branch (a rewrite, or more commits than the window).
    public var commitsSinceVerdict: Int? {
        guard let verdict = viewerVerdict?.commitOid else { return nil }
        guard movedSinceVerdict else { return 0 }
        guard let oids = recentCommitOids, let index = oids.firstIndex(of: verdict) else { return nil }
        return oids.count - index - 1
    }

    /// Moved, the verdict's commit gone from the branch, and at most a window of commits: a force-pushed rewrite.
    /// A missing count reads as rewritten.
    public var rewrittenSinceVerdict: Bool {
        movedSinceVerdict && commitsSinceVerdict == nil && (commitCount ?? 0) <= Self.recentCommitWindow
    }

    /// GitHub's diff between the verdict's commit and the head, when the diff moved (spec 0.8 3.7).
    public var sinceReviewURL: URL? {
        guard movedSinceVerdict, let head = headOid, let verdict = viewerVerdict?.commitOid else { return nil }
        return URL(string: "\(url.absoluteString)/files/\(verdict)..\(head)")
    }
}
