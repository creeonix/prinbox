import Foundation

/// Turns a fetch into the displayed inbox: drop archived repositories, classify, sort each section,
/// cap it, and count the badge.
public enum InboxBuilder {
    public static let rowCap = 8

    /// The unfetched remainder of each search is attributed to the last section that search feeds.
    static let remainderSection: [SearchSource: SectionKind] = [
        .review: .takeAnotherLook, .mentions: .mentions, .mine: .waitingOnOthers,
    ]

    /// `snoozed` holds the ids the user parked; they are classified as snoozed before anything else.
    public static func build(_ result: FetchResult, snoozed: Set<String> = [], cap: Int = rowCap) -> Inbox {
        let rows = result.pullRequests
            .filter { !$0.isArchived }
            .map {
                InboxRow(pullRequest: $0, classification: Classifier.classify($0, snoozed: snoozed.contains($0.id)))
            }
        let remainders = unfetchedBySection(result)
        let sections = SectionKind.allCases.compactMap { kind -> InboxSection? in
            let members = sorted(rows.filter { $0.classification.section == kind }, kind: kind)
            let remainder = remainders[kind] ?? 0
            guard !members.isEmpty || remainder > 0 else { return nil }
            return InboxSection(
                kind: kind, rows: Array(members.prefix(cap)), count: members.count + remainder,
                moreCount: max(0, members.count - cap) + remainder)
        }
        let badge = rows.filter { $0.classification.section.countsTowardBadge && !$0.pullRequest.isDraft }.count
        let owners = Set(rows.map(\.pullRequest.ownerLogin))
        return Inbox(
            sections: sections, badgeCount: badge, warnings: result.warnings, spansMultipleOrgs: owners.count > 1)
    }

    static func unfetchedBySection(_ result: FetchResult) -> [SectionKind: Int] {
        Dictionary(
            uniqueKeysWithValues: remainderSection.map { source, kind in
                (kind, max(0, (result.totals[source] ?? 0) - (result.fetched[source] ?? 0)))
            })
    }

    /// Review sections: longest waiting first. Own sections: newest update first, snoozed rows after the rest. Ties: lower number first.
    static func sorted(_ rows: [InboxRow], kind: SectionKind) -> [InboxRow] {
        rows.sorted { lhs, rhs in
            let leftSnoozed = lhs.classification.reason == .snoozed
            let rightSnoozed = rhs.classification.reason == .snoozed
            if leftSnoozed != rightSnoozed { return rightSnoozed }
            if kind.sortsByRecency, lhs.pullRequest.updatedAt != rhs.pullRequest.updatedAt {
                return lhs.pullRequest.updatedAt > rhs.pullRequest.updatedAt
            }
            if !kind.sortsByRecency {
                let left = lhs.classification.waitingSince ?? .distantFuture
                let right = rhs.classification.waitingSince ?? .distantFuture
                if left != right { return left < right }
            }
            return lhs.pullRequest.number < rhs.pullRequest.number
        }
    }
}
