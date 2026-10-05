import Foundation

/// Where `AppState` lives between launches.
public protocol StatePersisting: Sendable {
    /// Nil when nothing was saved yet. Throws when something is there but cannot be decoded.
    func load() throws -> AppState?
    func save(_ state: AppState) throws
}

/// `state.json` is larger than `JSONStateFile.sizeLimit` and is treated as unreadable (spec 5.2).
public struct StateFileTooLarge: Error, Equatable {
    public let bytes: Int
}

/// `state.json`: pretty-printed with sorted keys and ISO 8601 dates so it diffs well, written atomically so
/// a reader (the app, `--print`, the MCP server) never sees a partial file.
public struct JSONStateFile: StatePersisting {
    /// The real file is kilobytes; anything above this is not ours and would stall the reload.
    public static let sizeLimit = 8 * 1024 * 1024

    public let url: URL
    public let sizeLimit: Int

    public init(url: URL, sizeLimit: Int = JSONStateFile.sizeLimit) {
        self.url = url
        self.sizeLimit = sizeLimit
    }

    /// `<state directory>/state.json`.
    public static func url(in directories: Directories) -> URL {
        directories.state.appendingPathComponent("state.json")
    }

    /// Nil for a missing file; the read itself decides, so a file created between a check and the read is
    /// still loaded. A file over `sizeLimit` throws before it is read.
    public func load() throws -> AppState? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
        if let bytes = (size as? NSNumber)?.intValue ?? size as? Int, bytes > sizeLimit {
            throw StateFileTooLarge(bytes: bytes)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppState.self, from: data)
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

    /// The file is gone: `load()` answers nil from now on. For the reload tests.
    public func clear() { lock.withLock { stored = nil } }

    public func save(_ state: AppState) throws {
        lock.withLock {
            stored = state
            saves += 1
        }
    }
}
