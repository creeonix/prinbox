import Foundation

public struct InboxRow: Sendable, Equatable, Identifiable {
    public let pullRequest: PullRequest
    public let classification: Classification
    /// Threads waiting for the viewer's answer (Awaiting your reply, Open threads); 0 otherwise.
    public let pendingReplies: Int
    /// The row's place in a chain of stacked pull requests, nil for a PR outside any chain.
    public let stack: StackPosition?
    public var id: String { pullRequest.id }

    public init(
        pullRequest: PullRequest, classification: Classification, pendingReplies: Int = 0,
        stack: StackPosition? = nil
    ) {
        self.pullRequest = pullRequest
        self.classification = classification
        self.pendingReplies = pendingReplies
        self.stack = stack
    }
}

/// Rows of one section that share a repository owner, for the "Group by organization" view.
public struct OrgGroup: Sendable, Equatable, Identifiable {
    public let org: String
    public let rows: [InboxRow]
    public var id: String { org }

    /// Groups in order of first appearance; rows keep their order inside a group, so the first group
    /// holds the section's most urgent row.
    public static func grouping(_ rows: [InboxRow]) -> [OrgGroup] {
        rows.reduce(into: [OrgGroup]()) { groups, row in
            let org = row.pullRequest.ownerLogin
            if let index = groups.firstIndex(where: { $0.org == org }) {
                groups[index] = OrgGroup(org: org, rows: groups[index].rows + [row])
            } else {
                groups.append(OrgGroup(org: org, rows: [row]))
            }
        }
    }
}

public struct InboxSection: Sendable, Equatable, Identifiable {
    public let kind: SectionKind
    /// Rows to display, sorted and capped.
    public let rows: [InboxRow]
    /// The same rows grouped by owner, for the grouped view.
    public let groups: [OrgGroup]
    /// Everything GitHub has for this section: classified rows plus unfetched search results.
    public let count: Int
    /// Rows hidden by the cap plus unfetched results. Above zero, a "+N more on GitHub" row is shown.
    public let moreCount: Int
    public var id: SectionKind { kind }

    public init(kind: SectionKind, rows: [InboxRow], count: Int, moreCount: Int) {
        self.kind = kind
        self.rows = rows
        self.groups = OrgGroup.grouping(rows)
        self.count = count
        self.moreCount = moreCount
    }
}

public struct Inbox: Sendable, Equatable {
    public let sections: [InboxSection]
    public let badgeCount: Int
    public let warnings: [String]
    /// True when the fetched PRs belong to more than one owner; rows then show `org/repo` and org badges.
    public let spansMultipleOrgs: Bool
    /// The scope the rows were fetched under; the "+N more" links carry it.
    public let scope: SearchScope

    public init(
        sections: [InboxSection], badgeCount: Int, warnings: [String], spansMultipleOrgs: Bool = false,
        scope: SearchScope = .none
    ) {
        self.sections = sections
        self.badgeCount = badgeCount
        self.warnings = warnings
        self.spansMultipleOrgs = spansMultipleOrgs
        self.scope = scope
    }

    public static let empty = Inbox(sections: [], badgeCount: 0, warnings: [])

    public var isEmpty: Bool { sections.isEmpty }

    public func section(_ kind: SectionKind) -> InboxSection? { sections.first { $0.kind == kind } }

    /// The section's GitHub page under this inbox's scope.
    public func moreURL(_ kind: SectionKind) -> URL { kind.moreURL(scope: scope) }
}
