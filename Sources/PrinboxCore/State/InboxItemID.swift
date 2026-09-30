import Foundation

/// Everything the keyboard can select in the popover.
public enum InboxItemID: Hashable, Sendable {
    case header(SectionKind)
    case row(String)
    case more(SectionKind)
}

public enum InboxLayout {
    /// Focusable items in display order. Rows and "more" rows of folded sections are skipped. With
    /// `grouped`, rows follow the org groups, matching the grouped view.
    public static func visibleItems(_ inbox: Inbox, folded: Set<SectionKind>, grouped: Bool = false) -> [InboxItemID] {
        inbox.sections.flatMap { section -> [InboxItemID] in
            let header = InboxItemID.header(section.kind)
            guard !folded.contains(section.kind) else { return [header] }
            let rows = grouped ? section.groups.flatMap(\.rows) : section.rows
            let more: [InboxItemID] = section.moreCount > 0 ? [.more(section.kind)] : []
            return [header] + rows.map { .row($0.id) } + more
        }
    }
}
