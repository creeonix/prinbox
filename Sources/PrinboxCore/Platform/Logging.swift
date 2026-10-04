import Foundation

public enum LogLevel: Int, Sendable, Comparable {
    case debug
    case info
    case notice
    case error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The os.Logger categories of the app, reused by every other logger.
public enum LogCategory: String, Sendable {
    case gh
    case state
    case cli
}

/// Where Core writes its log lines. A line is a public message plus an optional private detail (gh's stderr,
/// an error's text) that an adapter may redact: the unified log marks it private, stderr prints it only when
/// asked. The app supplies `os.Logger`, the command stderr, tests a recorder.
public protocol Logging: Sendable {
    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, private detail: String?)
}

extension Logging {
    public func debug(_ category: LogCategory, _ message: String, private detail: String? = nil) {
        log(.debug, category, message, private: detail)
    }

    public func info(_ category: LogCategory, _ message: String, private detail: String? = nil) {
        log(.info, category, message, private: detail)
    }

    public func notice(_ category: LogCategory, _ message: String, private detail: String? = nil) {
        log(.notice, category, message, private: detail)
    }

    public func error(_ category: LogCategory, _ message: String, private detail: String? = nil) {
        log(.error, category, message, private: detail)
    }
}

/// The default where nothing asked for a log: tests, and Core objects built without one.
public struct NullLogging: Logging {
    public init() {}
    public func log(_ level: LogLevel, _ category: LogCategory, _ message: String, private detail: String?) {}
}
