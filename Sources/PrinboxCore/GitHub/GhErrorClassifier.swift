import Foundation

/// Maps a failed `gh` run to a `FetchError`. gh exits 4 when not logged in and 1 for everything else,
/// so the rest is read from stderr.
enum GhErrorClassifier {
    static let networkMarkers = [
        "dial tcp", "no such host", "connection refused", "network is unreachable",
        "i/o timeout", "tls handshake timeout", "error connecting to",
    ]

    static func classify(exitCode: Int32, stderr: String) -> FetchError {
        let text = stderr.lowercased()
        if exitCode == 4 || text.contains("http 401") || text.contains("bad credentials") {
            return .loggedOut
        }
        if text.contains("rate limit") { return .rateLimited(resetAt: nil) }
        if networkMarkers.contains(where: text.contains) { return .offline }
        return .other(firstLine(stderr) ?? "gh exited with code \(exitCode)")
    }

    /// First non-empty line without gh's "gh: " prefix, cut to 120 characters.
    static func firstLine(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let message = trimmed.hasPrefix("gh: ") ? String(trimmed.dropFirst(4)) : trimmed
        return message.isEmpty ? nil : String(message.prefix(120))
    }
}
