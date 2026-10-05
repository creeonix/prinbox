import Foundation

@testable import PrinboxCore

/// Records every line, so tests can assert on what a component logs and what it keeps private.
final class MemoryLogging: Logging, @unchecked Sendable {
    struct Line: Equatable {
        let level: LogLevel
        let category: LogCategory
        let message: String
        let detail: String?
    }

    private let lock = NSLock()
    private var stored: [Line] = []

    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, private detail: String?) {
        lock.withLock { stored.append(Line(level: level, category: category, message: message, detail: detail)) }
    }

    var lines: [Line] { lock.withLock { stored } }

    /// Messages at one level, or all of them.
    func messages(_ level: LogLevel? = nil) -> [String] {
        lines.filter { level == nil || $0.level == level }.map(\.message)
    }
}
