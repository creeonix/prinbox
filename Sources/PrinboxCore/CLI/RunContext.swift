import Foundation

/// Everything a command call needs, composed by the executable: the adapters, the two settings the command
/// reads, and the version it reports.
public struct RunContext: Sendable {
    public let fetcher: InboxFetching
    public let cache: CacheStoring
    public let persistence: StatePersisting
    public let lock: FileLock?
    public let followReviewThreads: Bool
    public let ghOverride: String?
    public let delivery: NotificationDelivering
    public let opener: URLOpening
    /// Printed once when `--notify` is given and this platform's delivery is a no-op (macOS).
    public let notifyNote: String?
    public let clock: @Sendable () -> Date
    public let logger: Logging
    public let version: String

    public init(
        fetcher: InboxFetching, cache: CacheStoring, persistence: StatePersisting, lock: FileLock?,
        followReviewThreads: Bool, ghOverride: String?, delivery: NotificationDelivering, opener: URLOpening,
        notifyNote: String?, clock: @escaping @Sendable () -> Date, logger: Logging, version: String
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.persistence = persistence
        self.lock = lock
        self.followReviewThreads = followReviewThreads
        self.ghOverride = ghOverride
        self.delivery = delivery
        self.opener = opener
        self.notifyNote = notifyNote
        self.clock = clock
        self.logger = logger
        self.version = version
    }
}

/// What one `inbox` call produced: the document, the exit code, and what goes to stderr (already prefixed,
/// or the setup guide's text).
public struct RunOutcome: Sendable, Equatable {
    public let document: InboxDocument
    public let exitCode: Int32
    public let stderr: [String]
    /// The setup guide's plain text when gh is missing or signed out; the server puts it in the content.
    public let setupGuide: String?

    public init(document: InboxDocument, exitCode: Int32, stderr: [String], setupGuide: String? = nil) {
        self.document = document
        self.exitCode = exitCode
        self.stderr = stderr
        self.setupGuide = setupGuide
    }
}

public struct CommandOutcome: Sendable, Equatable {
    public let exitCode: Int32
    public let stderr: [String]
    /// The pull request the command acted on, when it found one (snooze, open: the one fetched or cached;
    /// unsnooze: the cached row, if any). The server reports it; the command prints nothing on success.
    public let pullRequest: PullRequest?

    public init(exitCode: Int32, stderr: [String], pullRequest: PullRequest? = nil) {
        self.exitCode = exitCode
        self.stderr = stderr
        self.pullRequest = pullRequest
    }
}
