import Foundation
import PrinboxCore

/// The command's composition root: the one place that knows the platform.
enum Composition {
    static func context(for invocation: Invocation) -> RunContext {
        let logger = StderrLogging(verbose: invocation.verbose)
        #if os(Linux)
            let directories: Directories = XDGDirectories()
            let delivery: NotificationDelivering = NotifySendDelivery(logger: logger)
            let opener: URLOpening = ProcessURLOpener(
                executable: URL(fileURLWithPath: "/usr/bin/xdg-open"), logger: logger)
            let notifyNote: String? = nil
        #else
            let directories: Directories = MacDirectories()
            let delivery: NotificationDelivering = NoDelivery()
            let opener: URLOpening = ProcessURLOpener(executable: URL(fileURLWithPath: "/usr/bin/open"), logger: logger)
            let notifyNote: String? = "notifications on macOS are delivered by PRInbox.app"
        #endif
        let settingsURL =
            invocation.settingsPath.map { URL(fileURLWithPath: $0) }
            ?? directories.config.appendingPathComponent("settings.json")
        let settings = JSONKeyValueFile(url: settingsURL, logger: logger)
        let lock = FileLock(url: directories.state.appendingPathComponent("prinbox.lock"), logger: logger)
        let locator = GhLocator(overridePath: settings.object(forKey: GhLocator.overrideKey) as? String)
        return RunContext(
            fetcher: GhClient(locator: locator, logger: logger),
            cache: JSONCacheFile(
                url: directories.state.appendingPathComponent("cache.json"), lock: lock, logger: logger),
            persistence: JSONStateFile(url: JSONStateFile.url(in: directories)), lock: lock,
            followReviewThreads: settings.object(forKey: FetchSettings.key) as? Bool ?? true,
            scope: SearchScope.read(from: settings, logger: logger),
            ghOverride: locator.overridePath, delivery: delivery, opener: opener, notifyNote: notifyNote,
            clock: { Date() }, logger: logger, version: Version.string)
    }
}
