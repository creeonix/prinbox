import Foundation

/// Which search in `InboxQuery` returned a pull request. Declaration order is the dedupe priority.
public enum SearchSource: String, Sendable, CaseIterable {
    case review
    case mentions
    case mine
}

public enum ReviewDecision: Sendable, Equatable {
    case approved
    case changesRequested
    case reviewRequired
    case none
}

public enum Mergeable: Sendable, Equatable {
    case mergeable
    case conflicting
    case unknown
}

public enum CIState: Sendable, Equatable {
    case success
    case failure
    case pending
    case none
}

/// The viewer's latest submitted review. Pending (unsubmitted) reviews are never represented.
public struct ViewerReview: Sendable, Equatable {
    public let state: String
    public let submittedAt: Date?

    public init(state: String, submittedAt: Date?) {
        self.state = state
        self.submittedAt = submittedAt
    }
}

public struct PullRequest: Sendable, Equatable, Identifiable {
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

    public init(
        id: String, number: Int, title: String, url: URL, repository: String, isArchived: Bool,
        authorLogin: String, avatarURL: URL?, isDraft: Bool, additions: Int, deletions: Int,
        createdAt: Date, updatedAt: Date, reviewDecision: ReviewDecision, mergeable: Mergeable,
        ci: CIState, viewerReview: ViewerReview?, reviewRequestedAt: Date?, readyForReviewAt: Date?,
        source: SearchSource, commentCount: Int = 0, ownerAvatarURL: URL? = nil, ownerIsOrganization: Bool = false
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
