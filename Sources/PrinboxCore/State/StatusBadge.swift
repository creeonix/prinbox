import Foundation

/// What the menu-bar item shows.
public enum StatusBadge: Equatable, Sendable {
    case loading
    case count(Int)
    case zero
    case error(String)

    public static func derive(
        inbox: Inbox?, error: FetchError?, lastSuccess: Date?, timeZone: TimeZone = .current
    ) -> StatusBadge {
        if let error { return .error(error.message(lastSuccess: lastSuccess, timeZone: timeZone)) }
        guard let inbox else { return .loading }
        return inbox.badgeCount > 0 ? .count(inbox.badgeCount) : .zero
    }
}
