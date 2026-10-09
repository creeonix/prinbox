import Foundation

/// What a refresh brought into the attention sections, for the notification. A row arrives when its PR was
/// not in those sections at the previous fetch; a PR that changes while it already sits there is not an
/// arrival, or an active PR would notify every five minutes. The baseline is the previous inbox's attention
/// ids (extended, not replaced, by an incomplete fetch), not the seen ledger: a PR the user has not looked at
/// must not notify again five minutes later.
public enum Arrivals {
    static let sections: [SectionKind] = [.needsReview, .repliesToYou, .takeAnotherLook]

    /// Non-draft row ids of the attention sections. A draft is left out, so it arrives when it becomes ready.
    public static func attentionIDs(_ inbox: Inbox) -> Set<String> {
        Set(attentionRows(inbox).map(\.id))
    }

    /// Non-draft rows of the attention sections whose PR was not there at the previous fetch. Nil `previous`
    /// (the first fetch after launch) gives nothing.
    public static func compute(previous: Set<String>?, current: Inbox) -> [InboxRow] {
        guard let previous else { return [] }
        return attentionRows(current).filter { !previous.contains($0.id) }
    }

    /// The next baseline: the attention ids now, or, after an incomplete fetch, the previous baseline plus
    /// them, so PRs a partial response left out do not come back as arrivals.
    public static func baseline(after inbox: Inbox, complete: Bool, extending previous: Set<String>?) -> Set<String> {
        let current = attentionIDs(inbox)
        return complete ? current : (previous ?? []).union(current)
    }

    private static func attentionRows(_ inbox: Inbox) -> [InboxRow] {
        inbox.sections.filter { sections.contains($0.kind) }.flatMap(\.rows).filter { !$0.pullRequest.isDraft }
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
            let reason = first.classification.reason
            let what = reason.isPushedSinceVerdict ? reason.rawValue : first.classification.section.title
            return ArrivalNotice(title: RowText.title(pr), body: "\(pr.repository) · \(what)", url: pr.url)
        }
        let replies = rows.filter { $0.classification.section == .repliesToYou }.count
        let updates = rows.filter { $0.classification.reason.isPushedSinceVerdict }.count
        let requests = rows.count - replies - updates
        let kinds = [
            (requests, "review request", "review requests"), (replies, "reply", "replies"),
            (updates, "update", "updates"),
        ]
        .filter { $0.0 > 0 }
        let title =
            kinds.count == 1
            ? "\(rows.count) new \(kinds[0].2)"
            : "\(rows.count) new: " + kinds.map { counted($0.0, $0.1, plural: $0.2) }.joined(separator: ", ")
        let titles = rows.prefix(3).map { RowText.title($0.pullRequest) }
        let rest = rows.count - titles.count
        let lines = titles + (rest > 0 ? ["and \(rest) more"] : [])
        return ArrivalNotice(title: title, body: lines.joined(separator: "\n"), url: nil)
    }

    static func counted(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
