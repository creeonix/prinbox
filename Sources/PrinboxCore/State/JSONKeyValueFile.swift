import Foundation

/// `settings.json` (and `update.json`): one JSON object of the values the stores keep through
/// `KeyValueStoring`, pretty-printed with sorted keys and written atomically. A write reloads the file first
/// and changes one key, so a hand edit made while the app runs survives the next toggle; the edit itself is
/// read at the next launch. A file that is not a JSON object is logged and treated as empty, and the next
/// write replaces it.
public final class JSONKeyValueFile: KeyValueStoring, @unchecked Sendable {
    public let url: URL
    private let logger: Logging
    private let lock = NSLock()
    private var values: [String: Any]

    public init(url: URL, logger: Logging = NullLogging()) {
        self.url = url
        self.logger = logger
        values = Self.read(url, logger: logger)
    }

    public var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            var next = Self.read(url, logger: logger)
            next[defaultName] = value
            values = next
            do {
                try Self.write(next, to: url)
            } catch {
                logger.error(.state, "\(url.lastPathComponent) not saved", private: String(describing: error))
            }
        }
    }

    private static func read(_ url: URL, logger: Logging) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.notice(.state, "\(url.lastPathComponent) unreadable, treating it as empty")
            return [:]
        }
        return object
    }

    private static func write(_ values: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(values) else { throw CocoaError(.propertyListWriteInvalid) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: values, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

/// An in-memory store for `--demo` and tests. The demo seeds it with every section unfolded.
public final class MemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    public init(initial: [String: Any] = [:]) { values = initial }

    public func object(forKey defaultName: String) -> Any? { lock.withLock { values[defaultName] } }

    public func set(_ value: Any?, forKey defaultName: String) { lock.withLock { values[defaultName] = value } }
}
