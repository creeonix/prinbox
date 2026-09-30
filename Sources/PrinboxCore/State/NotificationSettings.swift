import Foundation
import Observation

/// Whether new review requests raise a macOS notification, persisted in user defaults. The shell asks
/// macOS for permission when this turns on; the setting stays on even when macOS says no, so Settings
/// can explain what to fix.
@MainActor
@Observable
public final class NotificationSettings {
    public static let key = "notifyOnNewReviewRequests"

    public private(set) var isEnabled: Bool
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.key) as? Bool ?? false
    }

    public func setEnabled(_ on: Bool) {
        isEnabled = on
        defaults.set(on, forKey: Self.key)
    }
}

/// The notification permission as the shell reports it; `unavailable` means the process has no bundle.
public enum NotificationStatus: Sendable, Equatable {
    case unavailable
    case notDetermined
    case authorized
    case denied

    /// A hint under the Settings toggle, or nil when nothing needs fixing.
    public var note: String? {
        switch self {
        case .denied: "Notifications are off for PRInbox. Turn them on in System Settings › Notifications."
        case .unavailable: "Not available when run from the build directory."
        case .notDetermined, .authorized: nil
        }
    }
}
