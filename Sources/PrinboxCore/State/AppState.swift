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
}
