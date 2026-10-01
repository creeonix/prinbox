import Foundation
import Observation

/// Whether refreshes follow review threads (Replies to you, open threads on your PRs, the thread-aware snooze
/// wake), persisted in user defaults. Off is the lighter refresh: three searches and rows only, and a snooze
/// wakes on any change.
@MainActor
@Observable
public final class FetchSettings {
    public static let key = "followReviewThreads"

    public private(set) var followReviewThreads: Bool
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        followReviewThreads = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    public func setFollowReviewThreads(_ on: Bool) {
        followReviewThreads = on
        defaults.set(on, forKey: Self.key)
    }
}
