import Foundation

/// Where `AppState` lives between launches.
public protocol StatePersisting: Sendable {
    /// Nil when nothing was saved yet. Throws when something is there but cannot be decoded.
    func load() throws -> AppState?
    func save(_ state: AppState) throws
}

/// `state.json`: pretty-printed with sorted keys and ISO 8601 dates so it diffs well, written atomically so
/// a reader (the app, `--print`, a future MCP server) never sees a partial file.
public struct JSONStateFile: StatePersisting {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/prinbox/state.json`.
    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("prinbox", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public func load() throws -> AppState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: AppState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

/// In-memory persistence for tests and `--demo`.
public final class MemoryStatePersistence: StatePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppState?
    private var saves = 0

    public init(_ initial: AppState? = nil) { stored = initial }

    public var saved: AppState? { lock.withLock { stored } }

    public var saveCount: Int { lock.withLock { saves } }

    public func load() throws -> AppState? { lock.withLock { stored } }

    public func save(_ state: AppState) throws {
        lock.withLock {
            stored = state
            saves += 1
        }
    }
}
