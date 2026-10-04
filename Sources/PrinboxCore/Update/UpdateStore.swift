import Foundation
import Observation

/// Once-a-day check for a newer PRInbox release. The last result is kept in defaults so the notice
/// survives a relaunch, and the attempt time is recorded before the call, so an offline Mac asks again
/// tomorrow rather than at every refresh.
@MainActor
@Observable
public final class UpdateStore {
    public static let interval: TimeInterval = 24 * 3600
    public static let checkedAtKey = "updateCheckedAt"
    public static let latestReleaseKey = "latestRelease"

    /// Nil for dev builds, which never check.
    public let current: AppVersion?
    public private(set) var latest: Release?
    @ObservationIgnored private let checker: ReleaseChecking
    @ObservationIgnored private let defaults: KeyValueStoring
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var checking = false

    public init(
        currentVersion: String, checker: ReleaseChecking, defaults: KeyValueStoring,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        current = AppVersion(currentVersion)
        self.checker = checker
        self.defaults = defaults
        self.clock = clock
        if let stored = defaults.object(forKey: Self.latestReleaseKey) as? [String: String],
            let tag = stored["tag"], let url = stored["url"].flatMap(URL.init(string:))
        {
            latest = Release(tag: tag, url: url)
        }
    }

    /// The release to offer: the stored one when it is newer than the running version.
    public var available: Release? {
        guard let current, let latest, let version = latest.version, version > current else { return nil }
        return latest
    }

    public func checkIfDue() async {
        guard current != nil, !checking else { return }
        if let last = (defaults.object(forKey: Self.checkedAtKey) as? String).flatMap(
            ISO8601DateFormatter().date(from:))
        {
            let elapsed = clock().timeIntervalSince(last)
            if elapsed >= 0 && elapsed < Self.interval { return }
        }
        checking = true
        defer { checking = false }
        defaults.set(ISO8601DateFormatter().string(from: clock()), forKey: Self.checkedAtKey)
        guard let release = try? await checker.latestRelease() else { return }
        latest = release
        defaults.set(["tag": release.tag, "url": release.url.absoluteString], forKey: Self.latestReleaseKey)
    }
}
