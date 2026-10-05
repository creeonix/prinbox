import Foundation

/// `cache.json`: the last fetch and its bookkeeping, so a process that starts from nothing (the command, the
/// app at launch) gets the one-point unchanged check, correct arrivals and rows at once. Not a contract: the
/// shape may change with any release, and a `version` a reader does not know means "no cache". Other
/// programs read the inbox through `prinbox inbox --format json`.
public struct InboxCache: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// CI results and merge conflicts do not move `updatedAt`, so a fingerprint older than this never skips
    /// the batches. The same ceiling as the app's `fullFetchInterval`.
    public static let fingerprintCeiling: TimeInterval = 15 * 60

    public var version: Int
    /// When `result` was fetched.
    public var fetchedAt: Date
    /// The last time GitHub confirmed it, including an unchanged check.
    public var checkedAt: Date
    /// The request shape `fingerprint` and `result` came from.
    public var includeConversation: Bool
    public var viewer: String
    /// `id -> updatedAt` over every search node.
    public var fingerprint: [String: Date]
    /// The arrivals baseline, sorted; absent until a notifier writes one.
    public var attention: [String]?
    public var result: FetchResult

    public init(
        fetchedAt: Date, checkedAt: Date, includeConversation: Bool, viewer: String, fingerprint: [String: Date],
        attention: [String]?, result: FetchResult
    ) {
        version = InboxCache.currentVersion
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.includeConversation = includeConversation
        self.viewer = viewer
        self.fingerprint = fingerprint
        self.attention = attention
        self.result = result
    }

    /// The fingerprint a fetch may send as `previous`: same request shape, younger than the ceiling.
    public func trustedFingerprint(now: Date, includeConversation: Bool) -> [String: Date]? {
        guard self.includeConversation == includeConversation else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age < Self.fingerprintCeiling else { return nil }
        return fingerprint
    }

    /// The baseline arrivals are computed against: same request shape, and one was recorded.
    public func trustedAttention(includeConversation: Bool) -> Set<String>? {
        guard self.includeConversation == includeConversation, let attention else { return nil }
        return Set(attention)
    }
}
