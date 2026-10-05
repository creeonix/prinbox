import Foundation

/// Turns a fetch into the displayed inbox: drop archived repositories and hidden PRs, classify, sort each section,
/// cap it (snoozed rows are never hidden), and count the badge.
public enum InboxBuilder {
    public static let rowCap = 8

    /// The unfetched remainder of each search is attributed to the last section that search feeds.
    static let remainderSection: [SearchSource: SectionKind] = [
        .review: .takeAnotherLook, .mentions: .mentions, .mine: .waitingOnOthers,
    ]

    /// `snoozed` holds the ids the user parked; they are classified as snoozed before anything else.
    public static func build(_ result: FetchResult, snoozed: Set<String> = [], cap: Int = rowCap) -> Inbox {
        let viewer = result.viewerLogin
        let stacks = Stacks.compute(result.pullRequests)
        let rows = result.pullRequests
            .filter { !$0.isArchived }
            .compactMap { pr -> InboxRow? in
                guard let classification = Classifier.classify(pr, viewer: viewer, snoozed: snoozed.contains(pr.id))
                else { return nil }
                return InboxRow(
                    pullRequest: pr, classification: classification,
                    pendingReplies: Classifier.pendingReplies(pr, viewer: viewer, reason: classification.reason),
                    stack: stacks[pr.id])
            }
        let remainders = unfetchedBySection(result)
        let sections = SectionKind.allCases.compactMap { kind -> InboxSection? in
            let members = sorted(rows.filter { $0.classification.section == kind }, kind: kind)
            // Snoozed rows follow the capped rows in full: hidden ones could never be woken from the popover.
            // The snooze also wins over contiguity: a parked chain member sits with the parked rows.
            let snoozed = members.filter { $0.classification.reason == .snoozed }
            let active = blocked(members.filter { $0.classification.reason != .snoozed })
            let shown = capped(active, cap: cap)
            let remainder = remainders[kind] ?? 0
            guard !members.isEmpty || remainder > 0 else { return nil }
            return InboxSection(
                kind: kind, rows: shown + snoozed, count: members.count + remainder,
                moreCount: active.count - shown.count + remainder)
        }
        let badge = rows.filter { $0.classification.section.countsTowardBadge && !$0.pullRequest.isDraft }.count
        let owners = Set(rows.map(\.pullRequest.ownerLogin))
        return Inbox(
            sections: sections, badgeCount: badge, warnings: result.warnings, spansMultipleOrgs: owners.count > 1)
    }

    /// Keeps a chain contiguous: when its first member in sort order is met, every member of that chain the
    /// section shows follows it, ordered by position. The block therefore sits where its most urgent member would.
    static func blocked(_ rows: [InboxRow]) -> [InboxRow] {
        var placed = Set<String>()
        var out: [InboxRow] = []
        for row in rows where !placed.contains(row.id) {
            guard let root = row.stack?.rootID else {
                out.append(row)
                placed.insert(row.id)
                continue
            }
            let members = rows.filter { $0.stack?.rootID == root }
                .sorted { ($0.stack?.position ?? 0) < ($1.stack?.position ?? 0) }
            out += members
            placed.formUnion(members.map(\.id))
        }
        return out
    }

    /// The cap never splits a block: a chain that starts within the cap is shown whole.
    static func capped(_ rows: [InboxRow], cap: Int) -> [InboxRow] {
        guard rows.count > cap, cap > 0, let root = rows[cap - 1].stack?.rootID else { return Array(rows.prefix(cap)) }
        var end = cap
        while end < rows.count, rows[end].stack?.rootID == root { end += 1 }
        return Array(rows.prefix(end))
    }

    static func unfetchedBySection(_ result: FetchResult) -> [SectionKind: Int] {
        Dictionary(
            uniqueKeysWithValues: remainderSection.map { source, kind in
                (kind, max(0, (result.totals[source] ?? 0) - (result.fetched[source] ?? 0)))
            })
    }

    /// Review sections: longest waiting first. Own sections: newest update first, snoozed rows after the
    /// rest. Ties: lower number first.
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
