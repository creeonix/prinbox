import Foundation

/// Where the cache lives. `update` is reload-apply-replace: `change` sees what is on disk now (nil when
/// nothing) and returns what to write, or nil to leave the file alone.
public protocol CacheStoring: Sendable {
    /// Nil when absent, unreadable, or written by another version.
    func load() -> InboxCache?
    func update(_ change: (InboxCache?) -> InboxCache?)
}

/// `cache.json`, pretty-printed with sorted keys and ISO 8601 dates, written atomically under the lock.
public struct JSONCacheFile: CacheStoring {
    public let url: URL
    private let lock: FileLock?
    private let logger: Logging

    public init(url: URL, lock: FileLock? = nil, logger: Logging = NullLogging()) {
        self.url = url
        self.lock = lock
        self.logger = logger
    }

    public func load() -> InboxCache? { read() }

    public func update(_ change: (InboxCache?) -> InboxCache?) {
        if let lock { lock.withLock { apply(change) } } else { apply(change) }
    }

    private func apply(_ change: (InboxCache?) -> InboxCache?) {
        guard let next = change(read()) else { return }
        do {
            try write(next)
        } catch {
            logger.error(.state, "cache.json not saved: \(String(describing: error))")
        }
    }

    private struct VersionOnly: Decodable {
        let version: Int?
    }

    private func read() -> InboxCache? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let version = try decoder.decode(VersionOnly.self, from: data).version ?? 0
            guard version == InboxCache.currentVersion else {
                logger.debug(.state, "cache.json version \(version) ignored")
                return nil
            }
            return try decoder.decode(InboxCache.self, from: data)
        } catch {
            logger.notice(.state, "cache.json unreadable, ignoring it", private: String(describing: error))
            return nil
        }
    }

    private func write(_ cache: InboxCache) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(cache).write(to: url, options: .atomic)
    }
}

/// In-memory cache for tests and `--demo`.
public final class MemoryCache: CacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: InboxCache?
    private var writes = 0

    public init(_ initial: InboxCache? = nil) { stored = initial }

    public var saved: InboxCache? { lock.withLock { stored } }

    public var writeCount: Int { lock.withLock { writes } }

    public func load() -> InboxCache? { lock.withLock { stored } }

    public func update(_ change: (InboxCache?) -> InboxCache?) {
        lock.withLock {
            guard let next = change(stored) else { return }
            stored = next
            writes += 1
        }
    }
}
