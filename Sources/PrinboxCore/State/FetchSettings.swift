import Foundation
import Observation

/// What a refresh asks for, persisted through `KeyValueStoring` (settings.json in the app): Follow review
/// threads (Replies to you, open threads on your PRs, the thread-aware snooze wake; off is the lighter refresh)
/// and the two scope settings (spec 4.1). Each change writes its one key.
@MainActor
@Observable
public final class FetchSettings {
    public nonisolated static let key = "followReviewThreads"

    public private(set) var followReviewThreads: Bool
    public private(set) var scope: SearchScope
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        followReviewThreads = defaults.object(forKey: Self.key) as? Bool ?? true
        scope = SearchScope.read(from: defaults)
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
}
