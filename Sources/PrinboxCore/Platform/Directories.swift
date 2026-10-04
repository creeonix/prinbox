import Foundation

/// Where the three kinds of files live. Both adapters are plain Foundation and compile everywhere; the
/// composition roots choose: the app and the command on macOS take `MacDirectories`, the command on Linux
/// `XDGDirectories`.
public protocol Directories: Sendable {
    /// `settings.json`.
    var config: URL { get }
    /// `state.json`, `cache.json`, `update.json`, `prinbox.lock`.
    var state: URL { get }
    /// Avatars.
    var cache: URL { get }
}

/// macOS: config under `~/.config` (or `$XDG_CONFIG_HOME`), state in Application Support, caches in Caches.
public struct MacDirectories: Directories {
    public let config: URL
    public let state: URL
    public let cache: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleID: String = "io.github.creeonix.prinbox"
    ) {
        config = XDGDirectories.base(environment["XDG_CONFIG_HOME"], default: home.appendingPathComponent(".config"))
            .appendingPathComponent("prinbox", isDirectory: true)
        state = home.appendingPathComponent("Library/Application Support/prinbox", isDirectory: true)
        cache = home.appendingPathComponent("Library/Caches/\(bundleID)", isDirectory: true)
    }
}

/// Linux: the XDG base directories with their standard defaults.
public struct XDGDirectories: Directories {
    public let config: URL
    public let state: URL
    public let cache: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        config = Self.base(environment["XDG_CONFIG_HOME"], default: home.appendingPathComponent(".config"))
            .appendingPathComponent("prinbox", isDirectory: true)
        state = Self.base(environment["XDG_STATE_HOME"], default: home.appendingPathComponent(".local/state"))
            .appendingPathComponent("prinbox", isDirectory: true)
        cache = Self.base(environment["XDG_CACHE_HOME"], default: home.appendingPathComponent(".cache"))
            .appendingPathComponent("prinbox", isDirectory: true)
    }

    /// The specification: an unset, empty or relative value is ignored.
    static func base(_ value: String?, default fallback: URL) -> URL {
        guard let value, value.hasPrefix("/") else { return fallback }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
