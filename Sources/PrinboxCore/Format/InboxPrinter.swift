import Foundation

/// Plain-text rendering for `Prinbox --print`, the live end-to-end check. Full repository names are
/// printed so exclusions (archived repositories) can be verified.
public enum InboxPrinter {
    public static func render(_ inbox: Inbox, now: Date) -> String {
        let header = "waiting on you: \(inbox.badgeCount)"
        let body =
            inbox.isEmpty
            ? ["", "Inbox zero. Nothing waiting on you."]
            : inbox.sections.flatMap { section in
                ["", "\(section.kind.title) (\(section.count))"]
                    + section.rows.flatMap { lines(for: $0, compact: section.kind.usesCompactRows, now: now) }
                    + (section.moreCount > 0 ? ["  \(RowText.more(section.moreCount))"] : [])
            }
        let warnings = inbox.warnings.isEmpty ? [] : [""] + inbox.warnings.map { "warning: \($0)" }
        return ([header] + body + warnings).joined(separator: "\n")
    }

    static func lines(for row: InboxRow, compact: Bool, now: Date) -> [String] {
        let repo = "[\(row.pullRequest.repository)]"
        if compact { return ["  \(RowText.compact(row))  \(repo)"] }
        return ["  \(RowText.title(row.pullRequest))  \(repo)", "      \(RowText.detail(row, now: now))"]
    }
}
