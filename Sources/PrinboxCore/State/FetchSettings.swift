import Foundation
import Observation

/// What a refresh asks for, persisted through `KeyValueStoring` (settings.json in the app): Follow review
/// threads (Replies to you, open threads on your PRs, the thread-aware snooze wake; off is the lighter refresh)
/// and the three scope settings (spec 4.1). Each change writes its one key.
@MainActor
@Observable
public final class FetchSettings {
    public nonisolated static let key = "followReviewThreads"

    public private(set) var followReviewThreads: Bool
    public private(set) var scope: SearchScope
    /// The Repositories field's text while it is edited; `commitRepositories` turns it into the setting.
    public var repositoriesDraft: String
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        followReviewThreads = defaults.object(forKey: Self.key) as? Bool ?? true
        let scope = SearchScope.read(from: defaults)
        self.scope = scope
        repositoriesDraft = Self.text(scope.repositories)
    }

    public func setFollowReviewThreads(_ on: Bool) {
        followReviewThreads = on
        defaults.set(on, forKey: Self.key)
    }

    public func setDirectReviewRequestsOnly(_ on: Bool) {
        scope.directReviewRequestsOnly = on
        defaults.set(on, forKey: SearchScope.directKey)
    }

    public func setHideDrafts(_ on: Bool) {
        scope.hideDrafts = on
        defaults.set(on, forKey: SearchScope.hideDraftsKey)
    }

    /// Parses the draft on commas and whitespace, keeps the valid entries, shows them back normalized (a
    /// dropped entry is visible by its absence), and writes `repositories` once when they differ from the
    /// setting. Returns whether the scope changed.
    @discardableResult
    public func commitRepositories() -> Bool {
        let entries = repositoriesDraft.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        let kept = SearchScope.normalize(entries).kept
        repositoriesDraft = Self.text(kept)
        guard kept != scope.repositories else { return false }
        scope.repositories = kept
        defaults.set(kept, forKey: SearchScope.repositoriesKey)
        return true
    }

    private static func text(_ entries: [String]) -> String { entries.joined(separator: ", ") }
}
