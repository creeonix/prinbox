import AppKit
import Observation
import PrinboxCore
import UserNotifications
import os

/// macOS notifications for arrivals. `UNUserNotificationCenter` aborts in a process without a bundle, so
/// everything here is a no-op when the app runs from the build directory (`swift run`, `--print`, tests).
@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let isAvailable = Bundle.main.bundleURL.pathExtension == "app"
    /// One identifier for every arrivals banner, so a new one replaces any earlier arrivals banner still in
    /// Notification Center instead of stacking.
    static let arrivalsIdentifier = "io.github.creeonix.prinbox.arrivals"
    nonisolated private static let logger = Logger(subsystem: OSLogging.subsystem, category: "notifications")

    private(set) var status: NotificationStatus = Notifier.isAvailable ? .notDetermined : .unavailable
    /// A click: the PR to open, or nil to show the popover.
    @ObservationIgnored var onOpen: (@MainActor (URL?) -> Void)?

    private var center: UNUserNotificationCenter? { Self.isAvailable ? .current() : nil }

    /// Installs the delegate at launch, so a click on a banner reaches the app even when it was delivered
    /// before the popover was ever opened.
    func start() {
        center?.delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        guard let center else { return }
        status = Self.status(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async {
        guard let center else { return }
        _ = try? await center.requestAuthorization(options: [.alert])
        await refresh()
    }

    func deliver(_ notice: ArrivalNotice) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        if let url = notice.url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: Self.arrivalsIdentifier, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Self.logger.error("notification not delivered: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private static func status(_ status: UNAuthorizationStatus) -> NotificationStatus {
        switch status {
        case .authorized, .provisional: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:))
        await MainActor.run { onOpen?(url) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        .banner
    }
}

extension Notifier: NotificationDelivering {}
