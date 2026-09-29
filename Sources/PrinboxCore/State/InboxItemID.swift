import Foundation

/// Everything the keyboard can select in the popover.
public enum InboxItemID: Hashable, Sendable {
    case header(SectionKind)
    case row(String)
    case more(SectionKind)
}

public enum InboxLayout {
    /// Focusable items in display order. Rows and "more" rows of folded sections are skipped.
    public static func visibleItems(_ inbox: Inbox, folded: Set<SectionKind>) -> [InboxItemID] {
        inbox.sections.flatMap { section -> [InboxItemID] in
            let header = InboxItemID.header(section.kind)
            guard !folded.contains(section.kind) else { return [header] }
            let more: [InboxItemID] = section.moreCount > 0 ? [.more(section.kind)] : []
            return [header] + section.rows.map { .row($0.id) } + more
        }
    }
}
