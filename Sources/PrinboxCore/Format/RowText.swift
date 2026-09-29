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
