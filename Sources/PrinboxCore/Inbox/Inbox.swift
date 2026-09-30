import Foundation

public struct InboxRow: Sendable, Equatable, Identifiable {
    public let pullRequest: PullRequest
    public let classification: Classification
    public var id: String { pullRequest.id }
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

    public init(sections: [InboxSection], badgeCount: Int, warnings: [String], spansMultipleOrgs: Bool = false) {
        self.sections = sections
        self.badgeCount = badgeCount
        self.warnings = warnings
        self.spansMultipleOrgs = spansMultipleOrgs
    }

    public static let empty = Inbox(sections: [], badgeCount: 0, warnings: [])

    public var isEmpty: Bool { sections.isEmpty }

    public func section(_ kind: SectionKind) -> InboxSection? { sections.first { $0.kind == kind } }
}
