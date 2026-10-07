import Foundation

/// The three scope settings as one value (spec 0.6 4.1, spec 3.4): they ride in `FetchRequest`, change the four
/// search qualifiers, and are recorded in the cache as part of the request shape a fingerprint and a baseline are
/// trusted for. The Codable keys are the `settings.json` names.
public struct SearchScope: Codable, Equatable, Sendable {
    public static let directKey = "directReviewRequestsOnly"
    public static let repositoriesKey = "defaultRepositories"
    public static let hideDraftsKey = "hideDrafts"

    /// Requests that reach the user through a team are left out of Needs your review and Take another look.
    public var directReviewRequestsOnly: Bool
    /// `owner/*` or `owner/name` entries, always normalized (`RepositoryEntries.normalize`); empty means every
    /// repository.
    public var repositories: [String] {
        didSet { repositories = RepositoryEntries.normalize(repositories).entries }
    }
    /// Other people's draft pull requests are left out; the user's own stay.
    public var hideDrafts: Bool

    public init(directReviewRequestsOnly: Bool = false, repositories: [String] = [], hideDrafts: Bool = false) {
        self.directReviewRequestsOnly = directReviewRequestsOnly
        self.repositories = RepositoryEntries.normalize(repositories).entries
        self.hideDrafts = hideDrafts
    }

    public static let none = SearchScope()

    public var isEmpty: Bool { self == .none }

    enum CodingKeys: String, CodingKey {
        case directReviewRequestsOnly
        case repositories = "defaultRepositories"
        case hideDrafts
    }

    /// A 0.6.0 cache's scope has no `defaultRepositories`: the empty list, the meaning it had.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            directReviewRequestsOnly: try container.decode(Bool.self, forKey: .directReviewRequestsOnly),
            repositories: try container.decodeIfPresent([String].self, forKey: .repositories) ?? [],
            hideDrafts: try container.decode(Bool.self, forKey: .hideDrafts))
    }

    /// The settings as a store holds them; a missing or wrongly typed key means its default. Invalid entries are
    /// dropped with one notice naming how many (never which: it may be a typo of a real name).
    public static func read(from store: KeyValueStoring, logger: Logging = NullLogging()) -> SearchScope {
        let raw = store.object(forKey: repositoriesKey) as? [String] ?? []
        let (entries, dropped) = RepositoryEntries.normalize(raw)
        if dropped > 0 {
            let noun = dropped == 1 ? "entry" : "entries"
            logger.notice(.state, "default repositories: ignored \(dropped) invalid \(noun)")
        }
        return SearchScope(
            directReviewRequestsOnly: store.object(forKey: directKey) as? Bool ?? false,
            repositories: entries,
            hideDrafts: store.object(forKey: hideDraftsKey) as? Bool ?? false)
    }
}
