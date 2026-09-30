import Foundation

/// Which avatars this session has loaded, is loading, or failed to load. A failed login is tried again
/// once `retryAfter` has passed, so a flaky download does not leave initials for the whole session.
public struct AvatarAttempts: Sendable, Equatable {
    public static let defaultRetryAfter: TimeInterval = 5 * 60

    private let retryAfter: TimeInterval
    private let loaded: Set<String>
    private let pending: Set<String>
    private let failures: [String: Date]

    public init(retryAfter: TimeInterval = AvatarAttempts.defaultRetryAfter) {
        self.init(retryAfter: retryAfter, loaded: [], pending: [], failures: [:])
    }

    private init(retryAfter: TimeInterval, loaded: Set<String>, pending: Set<String>, failures: [String: Date]) {
        self.retryAfter = retryAfter
        self.loaded = loaded
        self.pending = pending
        self.failures = failures
    }

    public func shouldAttempt(_ login: String, now: Date) -> Bool {
        if loaded.contains(login) || pending.contains(login) { return false }
        guard let failed = failures[login] else { return true }
        return now.timeIntervalSince(failed) >= retryAfter
    }

    public func recordingAttempt(_ login: String) -> AvatarAttempts {
        AvatarAttempts(retryAfter: retryAfter, loaded: loaded, pending: pending.union([login]), failures: failures)
    }

    public func recordingSuccess(_ login: String) -> AvatarAttempts {
        AvatarAttempts(
            retryAfter: retryAfter, loaded: loaded.union([login]), pending: pending.subtracting([login]),
            failures: failures.filter { $0.key != login })
    }

    public func recordingFailure(_ login: String, at now: Date) -> AvatarAttempts {
        AvatarAttempts(
            retryAfter: retryAfter, loaded: loaded, pending: pending.subtracting([login]),
            failures: failures.merging([login: now]) { _, new in new })
    }
}
