import Foundation

/// `--format json`: pretty-printed, sorted keys, ISO 8601 dates.
public enum InboxJSON {
    public static func render(_ document: InboxDocument) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(document) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// `--format lines`: one tab-separated row per line, flat, in display order, for fzf, walker and rofi.
/// Fields: id, kind, number, title, repository, reasonText, age, flags, url. A capped section adds a
/// `more:<kind>` line with the section's page.
public enum InboxLines {
    public static func render(_ document: InboxDocument) -> String {
        var lines: [String] = []
        for section in document.sections {
            for row in section.rows {
                lines.append(
                    [
                        row.id, section.kind, String(row.number), RowText.flattened(row.title), row.repository,
                        row.reasonText, row.age,
                        flags(row), row.url.absoluteString,
                    ].joined(separator: "\t"))
            }
            if section.moreCount > 0 {
                lines.append(
                    [
                        "more:\(section.kind)", section.kind, "", RowText.more(section.moreCount), "", "", "", "",
                        section.moreUrl?.absoluteString ?? "",
                    ].joined(separator: "\t"))
            }
        }
        return lines.map { $0 + "\n" }.joined()
    }

    static func flags(_ row: InboxDocument.Row) -> String {
        var flags: [String] = []
        if row.isNew { flags.append("new") }
        if row.isDraft { flags.append("draft") }
        if row.snoozed { flags.append("snoozed") }
        if let stack = row.stack { flags.append("stack \(stack.position)/\(stack.size)") }
        return flags.joined(separator: ",")
    }
}

/// `--format waybar`: Waybar's custom-module object, one line. `text` is the count (`!` when gh needs
/// attention and nothing is known), `alt` one state for format-icons, `class` the states for CSS, `tooltip`
/// the inbox. Waybar parses the tooltip as Pango markup unless told not to, so it is escaped.
public enum InboxWaybar {
    public static func render(_ document: InboxDocument) -> String {
        let setup = document.error.map { $0.code == "ghNotFound" || $0.code == "loggedOut" } ?? false
        let failed = document.error != nil && !setup
        let hasRows = document.sections.contains { !$0.rows.isEmpty }
        let count = document.badge > 0 ? String(document.badge) : ""
        let text = (setup || failed) && !hasRows ? "!" : count
        let alt = setup ? "setup" : failed ? "error" : document.badge > 0 ? "waiting" : "idle"
        var classes = [document.badge > 0 ? "waiting" : "idle"]
        if document.newCount > 0 { classes.append("new") }
        if setup { classes.append("setup") } else if failed { classes.append("error") }
        let object: [String: Any] = ["text": text, "alt": alt, "class": classes, "tooltip": tooltip(document)]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func tooltip(_ document: InboxDocument) -> String {
        var lines: [String] = []
        if let error = document.error { lines.append(error.message) }
        for section in document.sections where !section.rows.isEmpty {
            lines.append("\(section.title) (\(section.count))")
            for row in section.rows {
                lines.append("#\(row.number) \(RowText.flattened(row.title)) · \(row.repository) · \(row.age)")
            }
        }
        return escape(lines.joined(separator: "\n"))
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// `--format tmux`: the count when something waits, nothing when idle, `!` when gh needs attention, `!N`
/// when the fetch failed but N cached rows are known. The label and colors stay in the tmux config.
public enum InboxTmux {
    public static func render(_ document: InboxDocument) -> String {
        let count = document.badge > 0 ? String(document.badge) : ""
        return document.error == nil ? count : "!" + count
    }
}
