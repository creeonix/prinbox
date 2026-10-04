import PrinboxCore
import os

/// The app's logger: one `os.Logger` per category under the bundle's subsystem. The message is public, so
/// `log stream` shows it; the detail is private, as gh's stderr has been since 0.2.
struct OSLogging: Logging {
    static let subsystem = "io.github.creeonix.prinbox"
    private static let gh = Logger(subsystem: subsystem, category: "gh")
    private static let state = Logger(subsystem: subsystem, category: "state")
    private static let cli = Logger(subsystem: subsystem, category: "cli")

    func log(_ level: LogLevel, _ category: LogCategory, _ message: String, private detail: String?) {
        let logger =
            switch category {
            case .gh: Self.gh
            case .state: Self.state
            case .cli: Self.cli
            }
        let type: OSLogType =
            switch level {
            case .debug: .debug
            case .info: .info
            case .notice: .default
            case .error: .error
            }
        if let detail {
            logger.log(level: type, "\(message, privacy: .public): \(detail, privacy: .private)")
        } else {
            logger.log(level: type, "\(message, privacy: .public)")
        }
    }
}
