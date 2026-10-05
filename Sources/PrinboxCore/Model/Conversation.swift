import Foundation

/// One comment of a review thread: who and when. Bodies are never fetched.
public struct ThreadComment: Sendable, Equatable, Codable {
    public let authorLogin: String
    public let createdAt: Date

    public init(authorLogin: String, createdAt: Date) {
        self.authorLogin = authorLogin
        self.createdAt = createdAt
    }
}

/// A review thread, comments oldest first (GitHub returns the last page in chronological order).
public struct ReviewThread: Sendable, Equatable, Codable {
    public let isResolved: Bool
    public let comments: [ThreadComment]

    public init(isResolved: Bool, comments: [ThreadComment]) {
        self.isResolved = isResolved
        self.comments = comments
    }
}

/// A submitted review: author, GitHub state (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED), date.
public struct Review: Sendable, Equatable, Codable {
    public let authorLogin: String
    public let state: String
    public let submittedAt: Date?

    public init(authorLogin: String, state: String, submittedAt: Date?) {
        self.authorLogin = authorLogin
        self.state = state
        self.submittedAt = submittedAt
    }
}
