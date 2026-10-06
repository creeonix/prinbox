import Foundation

/// The two scope settings as one value (spec 4.1): they ride in `FetchRequest`, change the four search
/// qualifiers, and are recorded in the cache as part of the request shape a fingerprint and a baseline are
/// trusted for. The Codable keys are the `settings.json` names.
public struct SearchScope: Codable, Equatable, Sendable {
    public static let directKey = "directReviewRequestsOnly"
    public static let hideDraftsKey = "hideDrafts"

    /// Requests that reach the user through a team are left out of Needs your review and Take another look.
    public var directReviewRequestsOnly: Bool
    /// Other people's draft pull requests are left out; the user's own stay.
    public var hideDrafts: Bool

    public init(directReviewRequestsOnly: Bool = false, hideDrafts: Bool = false) {
        self.directReviewRequestsOnly = directReviewRequestsOnly
        self.hideDrafts = hideDrafts
    }

    public static let none = SearchScope()

    public var isEmpty: Bool { self == .none }

    /// The settings as a store holds them; a missing or wrongly typed key means its default.
    public static func read(from store: KeyValueStoring) -> SearchScope {
        SearchScope(
            directReviewRequestsOnly: store.object(forKey: directKey) as? Bool ?? false,
            hideDrafts: store.object(forKey: hideDraftsKey) as? Bool ?? false)
    }
}
