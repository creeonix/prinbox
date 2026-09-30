import Foundation

/// What a refresh brought into the review sections, for the notification. The baseline is the previous
/// fetch (extended, not replaced, by an incomplete fetch), not the seen ledger: a PR the user has not looked
/// at must not notify again five minutes later.
public enum Arrivals {
    static let sections: Set<SectionKind> = [.needsReview, .takeAnotherLook]

    /// Non-draft rows of Needs your review and Take another look whose PR the baseline lacks, or has with
    /// an older `updatedAt`. Nil `previous` (the first fetch after launch) gives nothing.
    public static func compute(previous: [String: Date]?, current: Inbox) -> [InboxRow] {
        guard let previous else { return [] }
        return current.sections
            .filter { sections.contains($0.kind) }
            .flatMap(\.rows)
            .filter { row in
                !row.pullRequest.isDraft && (previous[row.id].map { row.pullRequest.updatedAt > $0 } ?? true)
            }
    }
}

/// One macOS notification for a refresh's arrivals.
public struct ArrivalNotice: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The PR to open on click, or nil when there are several: the app shows the popover instead.
    public let url: URL?

    public init(title: String, body: String, url: URL?) {
        self.title = title
        self.body = body
        self.url = url
    }

    public static func make(_ rows: [InboxRow]) -> ArrivalNotice? {
        guard let first = rows.first else { return nil }
        if rows.count == 1 {
            let pr = first.pullRequest
            return ArrivalNotice(
                title: RowText.title(pr), body: "\(pr.repository) · \(first.classification.section.title)",
                url: pr.url)
        }
        let titles = rows.prefix(3).map { RowText.title($0.pullRequest) }
        let rest = rows.count - titles.count
        let lines = titles + (rest > 0 ? ["and \(rest) more"] : [])
        return ArrivalNotice(title: "\(rows.count) new review requests", body: lines.joined(separator: "\n"), url: nil)
    }
}
