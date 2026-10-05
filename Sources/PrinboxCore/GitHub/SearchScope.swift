import Foundation

/// The three scope settings as one value (spec 4.1): they ride in `FetchRequest`, change the four search
/// qualifiers, and are recorded in the cache as part of the request shape a fingerprint and a baseline are
/// trusted for. The Codable keys are the `settings.json` names.
public struct SearchScope: Codable, Equatable, Sendable {
    public static let directKey = "directReviewRequestsOnly"
    public static let repositoriesKey = "repositories"
    public static let hideDraftsKey = "hideDrafts"

    /// Requests that reach the user through a team are left out of Needs your review and Take another look.
    public var directReviewRequestsOnly: Bool
    /// `owner` or `owner/name` entries; empty means everything. `owner` is every repository of that user or
    /// organization (`user:` matches both; measured in the spec's decisions table).
    public var repositories: [String]
    /// Other people's draft pull requests are left out; the user's own stay.
    public var hideDrafts: Bool

    public init(directReviewRequestsOnly: Bool = false, repositories: [String] = [], hideDrafts: Bool = false) {
        self.directReviewRequestsOnly = directReviewRequestsOnly
        self.repositories = repositories
        self.hideDrafts = hideDrafts
    }

    public static let none = SearchScope()

    public var isEmpty: Bool { self == .none }

    /// The settings as a store holds them; a missing or wrongly typed key means its default.
    public static func read(from store: KeyValueStoring) -> SearchScope {
        SearchScope(
            directReviewRequestsOnly: store.object(forKey: directKey) as? Bool ?? false,
            repositories: store.object(forKey: repositoriesKey) as? [String] ?? [],
            hideDrafts: store.object(forKey: hideDraftsKey) as? Bool ?? false)
    }

    /// A GitHub login, optionally a slash and a repository name.
    public static func isValidEntry(_ entry: String) -> Bool {
        entry.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9-]*(\/[A-Za-z0-9._-]+)?/) != nil
    }

    /// Trimmed, valid, deduplicated without regard to case (GitHub names are), in the order given. `dropped`
    /// counts the invalid entries for the notice, which names a count and never an entry.
    public static func normalize(_ entries: [String]) -> (kept: [String], dropped: Int) {
        var seen = Set<String>()
        var kept: [String] = []
        var dropped = 0
        for raw in entries {
            let entry = raw.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }
            guard isValidEntry(entry) else {
                dropped += 1
                continue
            }
            if seen.insert(entry.lowercased()).inserted { kept.append(entry) }
        }
        return (kept, dropped)
    }

    /// ` user:owner` or ` repo:owner/name` per kept entry, each with its leading space; empty when none.
    var repositoryQualifiers: String {
        Self.normalize(repositories).kept.map { $0.contains("/") ? " repo:\($0)" : " user:\($0)" }.joined()
    }
}
