import Foundation

/// A snoozed PR: hidden until its `updatedAt` moves past the value recorded here.
public struct SnoozeEntry: Codable, Equatable, Sendable {
    public let snoozedAt: Date
    public let updatedAt: Date

    public init(snoozedAt: Date, updatedAt: Date) {
        self.snoozedAt = snoozedAt
        self.updatedAt = updatedAt
    }
}

/// Everything PRInbox remembers about individual PRs, persisted as `state.json`. Keys are PR node ids.
public struct AppState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var snoozed: [String: SnoozeEntry]
    /// `updatedAt` per PR at the last look. Nil until the first fetch seeds it, so a fresh install does not
    /// mark everything new. An empty ledger is different: it means the inbox was empty when last looked at.
    public var seen: [String: Date]?

    public init(version: Int = currentVersion, snoozed: [String: SnoozeEntry] = [:], seen: [String: Date]? = nil) {
        self.version = version
        self.snoozed = snoozed
        self.seen = seen
    }

    enum CodingKeys: String, CodingKey {
        case version
        case snoozed
        case seen
    }

    /// Missing `version` and `snoozed` take their defaults, so a file written by another writer with only the
    /// keys it knows still loads. Encoding stays synthesized and always writes all three (seen when present).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        snoozed = try container.decodeIfPresent([String: SnoozeEntry].self, forKey: .snoozed) ?? [:]
        seen = try container.decodeIfPresent([String: Date].self, forKey: .seen)
    }

    /// False until the ledger exists; then true for a PR the ledger lacks or knows with an older `updatedAt`.
    public func isNew(_ pr: PullRequest) -> Bool {
        guard let seen else { return false }
        guard let last = seen[pr.id] else { return true }
        return pr.updatedAt > last
    }
}
