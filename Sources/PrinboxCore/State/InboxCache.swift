import Foundation

/// `cache.json`: the last fetch and its bookkeeping, so a process that starts from nothing (the command, the
/// app at launch) gets the one-point unchanged check, correct arrivals and rows at once. Not a contract: the
/// shape may change with any release, and a `version` a reader does not know means "no cache". Other
/// programs read the inbox through `prinbox inbox --format json`.
public struct InboxCache: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    /// Versions this build reads: 1 (0.5.0 to 0.7.0) for its rows, fingerprint and known repositories, 2 for
    /// everything (spec 0.8 6.2).
    public static let readableVersions: Set<Int> = [1, 2]
    /// CI results and merge conflicts do not move `updatedAt`, so a fingerprint older than this never skips
    /// the batches. The same ceiling as the app's `fullFetchInterval`.
    public static let fingerprintCeiling: TimeInterval = 15 * 60

    public var version: Int
    /// When `result` was fetched.
    public var fetchedAt: Date
    /// The last time GitHub confirmed it, including an unchanged check.
    public var checkedAt: Date
    /// The request shape `fingerprint` and `result` came from: the conversation flag and the scope. A 0.5
    /// file has no `scope`, which decodes as the empty scope, the meaning it had.
    public var includeConversation: Bool
    public var scope: SearchScope
    public var viewer: String
    /// `id -> updatedAt` over every search node.
    public var fingerprint: [String: Date]
    /// The arrivals baseline, sorted; absent until a notifier writes one.
    public var attention: [String]?
    public var result: FetchResult
    /// The repositories of the last fetch made with no default repositories, for the picker (spec 3.4); absent in
    /// a 0.6.0 file.
    public var knownRepositories: [String]?

    enum CodingKeys: String, CodingKey {
        case version, fetchedAt, checkedAt, includeConversation, scope, viewer, fingerprint, attention, result
        case knownRepositories
    }

    public init(
        fetchedAt: Date, checkedAt: Date, includeConversation: Bool, scope: SearchScope = .none, viewer: String,
        fingerprint: [String: Date], attention: [String]?, result: FetchResult, knownRepositories: [String]? = nil
    ) {
        version = InboxCache.currentVersion
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.includeConversation = includeConversation
        self.scope = scope
        self.viewer = viewer
        self.fingerprint = fingerprint
        self.attention = attention
        self.result = result
        self.knownRepositories = knownRepositories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        includeConversation = try container.decode(Bool.self, forKey: .includeConversation)
        scope = try container.decodeIfPresent(SearchScope.self, forKey: .scope) ?? .none
        viewer = try container.decode(String.self, forKey: .viewer)
        fingerprint = try container.decode([String: Date].self, forKey: .fingerprint)
        // A version-1 file predates the rules of 0.8: its rows and fingerprint hold, its arrivals baseline does not
        // (spec 0.8 6.2, ruling 12.5).
        attention = version >= 2 ? try container.decodeIfPresent([String].self, forKey: .attention) : nil
        result = try container.decode(FetchResult.self, forKey: .result)
        knownRepositories = try container.decodeIfPresent([String].self, forKey: .knownRepositories)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(checkedAt, forKey: .checkedAt)
        try container.encode(includeConversation, forKey: .includeConversation)
        try container.encode(scope, forKey: .scope)
        try container.encode(viewer, forKey: .viewer)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(attention, forKey: .attention)
        try container.encode(result, forKey: .result)
        try container.encodeIfPresent(knownRepositories, forKey: .knownRepositories)
    }

    public var shape: FetchShape { FetchShape(includeConversation: includeConversation, scope: scope) }

    /// The fingerprint a fetch may send as `previous`: same request shape, younger than the ceiling.
    public func trustedFingerprint(now: Date, shape: FetchShape) -> [String: Date]? {
        guard self.shape == shape else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age < Self.fingerprintCeiling else { return nil }
        return fingerprint
    }

    /// The baseline arrivals are computed against: same request shape, and one was recorded.
    public func trustedAttention(shape: FetchShape) -> Set<String>? {
        guard self.shape == shape, let attention else { return nil }
        return Set(attention)
    }

    /// What a `.result` writer records as `knownRepositories`: the result's repositories when the fetch had no
    /// default repositories, else what the file holds (`existing`), so a filtered fetch never narrows the picker.
    public static func knownRepositories(after result: FetchResult, scope: SearchScope, carrying existing: [String]?)
        -> [String]?
    {
        scope.repositories.isEmpty ? result.repositoryNames : existing
    }
}
