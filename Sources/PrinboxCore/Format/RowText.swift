import Foundation

/// Every string shown for a row, a header or a placeholder, shared by the popover and `--print`.
public enum RowText {
    /// "#12 Title". Control characters (line breaks, tabs, terminal escapes) and bidi overrides become
    /// spaces and whitespace runs collapse, so a row never wraps, recolors a terminal or reverses its text.
    public static func title(_ pr: PullRequest) -> String {
        let scalars = pr.title.unicodeScalars.map { isUnsafe($0) ? " " : $0 }
        let flat = String(String.UnicodeScalarView(scalars)).split(whereSeparator: \.isWhitespace)
        return "#\(pr.number) \(flat.joined(separator: " "))"
    }

    /// C0/C1 controls plus bidi embeddings, overrides and isolates (U+202A-U+202E, U+2066-U+2069).
    static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control || (0x202A...0x202E).contains(scalar.value)
            || (0x2066...0x2069).contains(scalar.value)
    }

    /// "web · waiting 6h · +120 −4" for review sections, "web · updated 3h ago · +1 −0" for own PRs.
    /// `showOrg` writes "acme/web" instead of "web": on when the inbox spans several orgs and grouping is off.
    public static func meta(_ row: InboxRow, now: Date, showOrg: Bool = false) -> String {
        let pr = row.pullRequest
        let age =
            row.classification.waitingSince.map { "waiting \(RelativeAge.format(from: $0, to: now))" }
            ?? "updated \(RelativeAge.format(from: pr.updatedAt, to: now)) ago"
        return [repoLabel(pr, showOrg: showOrg), age, "+\(pr.additions) −\(pr.deletions)"].joined(separator: " · ")
            + stackSegment(row)
    }

    /// " · stack 2/3" for a chain member, nothing otherwise. A fact in the fact line, not a mark.
    static func stackSegment(_ row: InboxRow) -> String {
        row.stack.map { " · stack \($0.position)/\($0.size)" } ?? ""
    }

    /// The row tooltip: the full repository name, and the parent for a chain member.
    public static func help(_ row: InboxRow) -> String {
        guard let parent = row.stack?.parentNumber else { return row.pullRequest.repository }
        return "\(row.pullRequest.repository) · stacked on #\(parent)"
    }

    /// The fixed tail of a compact row, after the truncating title: "· web", "· web · Draft" or
    /// "· web · Snoozed" (a snoozed draft says Snoozed; the row is dimmed either way), then "· 8h" when the
    /// compact layout shows an age.
    public static func compactTrailer(_ row: InboxRow, showOrg: Bool = false, age: String? = nil) -> String {
        let repo = "· \(repoLabel(row.pullRequest, showOrg: showOrg))"
        let status = row.classification.reason == .snoozed ? " · Snoozed" : row.pullRequest.isDraft ? " · Draft" : ""
        return repo + stackSegment(row) + status + (age.map { " · \($0)" } ?? "")
    }

    /// The age for a compact row outside Waiting on others: "8h" waiting, or "1h ago" since the last update.
    public static func compactAge(_ row: InboxRow, now: Date) -> String {
        row.classification.waitingSince.map { RelativeAge.format(from: $0, to: now) }
            ?? "\(RelativeAge.format(from: row.pullRequest.updatedAt, to: now)) ago"
    }

    static func repoLabel(_ pr: PullRequest, showOrg: Bool) -> String {
        showOrg ? pr.repository : pr.repoShortName
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

    /// "3 waiting on you · updated 14:05", plus "· 2 new" when rows are new since the last look; "Setup
    /// needed" while gh is missing or signed out, or "Loading…" before the first successful refresh.
    public static func header(
        badgeCount: Int, lastSuccess: Date?, needsSetup: Bool = false, newCount: Int = 0,
        timeZone: TimeZone = .current
    ) -> String {
        if needsSetup { return "Setup needed" }
        guard let lastSuccess else { return "Loading…" }
        let base = "\(badgeCount) waiting on you · updated \(ClockText.hhmm(lastSuccess, timeZone: timeZone))"
        return newCount > 0 ? "\(base) · \(newCount) new" : base
    }
}
