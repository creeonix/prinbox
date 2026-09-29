import Foundation

/// Every string shown for a row, a header or a placeholder, shared by the popover and `--print`.
public enum RowText {
    /// "#12 Title". Line breaks and tabs become single spaces so a row never wraps.
    public static func title(_ pr: PullRequest) -> String {
        let flat = pr.title.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
        return "#\(pr.number) \(flat)"
    }

    /// "web · waiting 6h · +120 −4" for review sections, "web · updated 3h ago · +1 −0" for own PRs.
    public static func meta(_ row: InboxRow, now: Date) -> String {
        let pr = row.pullRequest
        let age =
            row.classification.waitingSince.map { "waiting \(RelativeAge.format(from: $0, to: now))" }
            ?? "updated \(RelativeAge.format(from: pr.updatedAt, to: now)) ago"
        return [pr.repoShortName, age, "+\(pr.additions) −\(pr.deletions)"].joined(separator: " · ")
    }

    public static func detail(_ row: InboxRow, now: Date) -> String {
        "\(meta(row, now: now)) · \(row.classification.reason.rawValue)"
    }

    /// One-line row for Waiting on others: "#9 Title · Waiting for review".
    public static func compact(_ row: InboxRow) -> String {
        "\(title(row.pullRequest)) · \(row.classification.reason.rawValue)"
    }

    public static func more(_ count: Int) -> String { "+\(count) more on GitHub" }

    /// Up to two uppercase characters for the avatar placeholder.
    public static func initials(_ login: String) -> String { String(login.prefix(2)).uppercased() }

    /// "3 waiting on you · updated 14:05", or "Loading…" before the first successful refresh.
    public static func header(badgeCount: Int, lastSuccess: Date?, timeZone: TimeZone = .current) -> String {
        guard let lastSuccess else { return "Loading…" }
        return "\(badgeCount) waiting on you · updated \(ClockText.hhmm(lastSuccess, timeZone: timeZone))"
    }
}
