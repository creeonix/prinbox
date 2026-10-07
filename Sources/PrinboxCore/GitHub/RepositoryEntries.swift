import Foundation

/// The entries of `defaultRepositories` (spec 3.2): `owner/*` for every repository of a user or organization,
/// `owner/name` for one repository. Pure functions over strings; `SearchScope` holds the normalized form.
public enum RepositoryEntries {
    /// A GitHub login, alone or followed by `/*` or `/name`.
    public static func isValid(_ entry: String) -> Bool {
        entry.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9-]*(\/(\*|[A-Za-z0-9._-]+))?/) != nil
    }

    /// Trimmed, valid, respelled (`owner` to `owner/*`), deduplicated without regard to case (GitHub names are),
    /// freed of repositories a pinned owner covers, and sorted without regard to case. `dropped` counts the
    /// invalid entries for the notice, which names a count and never an entry.
    public static func normalize(_ raw: [String]) -> (entries: [String], dropped: Int) {
        var dropped = 0
        var seen = Set<String>()
        var kept: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard isValid(trimmed) else {
                dropped += 1
                continue
            }
            let entry = trimmed.contains("/") ? trimmed : trimmed + "/*"
            if seen.insert(entry.lowercased()).inserted { kept.append(entry) }
        }
        let pinnedOwners = Set(kept.filter(isWildcard).map { owner(of: $0).lowercased() })
        let uncovered = kept.filter { isWildcard($0) || !pinnedOwners.contains(owner(of: $0).lowercased()) }
        return (uncovered.sorted { $0.lowercased() < $1.lowercased() }, dropped)
    }

    /// `owner/*`.
    public static func isWildcard(_ entry: String) -> Bool { entry.hasSuffix("/*") }

    /// `acme` for `acme/web` and for `acme/*`.
    public static func owner(of entry: String) -> String {
        entry.split(separator: "/", maxSplits: 1).first.map(String.init) ?? entry
    }

    /// ` user:owner` or ` repo:owner/name`, with the leading space the qualifier string needs.
    public static func qualifier(for entry: String) -> String {
        isWildcard(entry) ? " user:\(owner(of: entry))" : " repo:\(entry)"
    }

    /// Whether `entry` covers the repository `owner/name`: `owner/*` covers every repository of that owner, an
    /// `owner/name` entry that one, both without regard to case.
    public static func covers(_ entry: String, repository: String) -> Bool {
        if isWildcard(entry) { return owner(of: entry).lowercased() == owner(of: repository).lowercased() }
        return entry.lowercased() == repository.lowercased()
    }
}
