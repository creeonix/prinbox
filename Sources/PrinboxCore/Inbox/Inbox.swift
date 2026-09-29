import Foundation

public struct InboxRow: Sendable, Equatable, Identifiable {
    public let pullRequest: PullRequest
    public let classification: Classification
    public var id: String { pullRequest.id }
}

public struct InboxSection: Sendable, Equatable, Identifiable {
    public let kind: SectionKind
    /// Rows to display, sorted and capped.
    public let rows: [InboxRow]
    /// Everything GitHub has for this section: classified rows plus unfetched search results.
    public let count: Int
    /// Rows hidden by the cap plus unfetched results. Above zero, a "+N more on GitHub" row is shown.
    public let moreCount: Int
    public var id: SectionKind { kind }
}

public struct Inbox: Sendable, Equatable {
    public let sections: [InboxSection]
    public let badgeCount: Int
    public let warnings: [String]

    public static let empty = Inbox(sections: [], badgeCount: 0, warnings: [])

    public var isEmpty: Bool { sections.isEmpty }

    public func section(_ kind: SectionKind) -> InboxSection? { sections.first { $0.kind == kind } }
}
