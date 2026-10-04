import Foundation

/// The command's logger. By default only notice and error lines appear and the private detail is replaced,
/// since Waybar and systemd keep stderr in the journal; `--verbose` prints every level and the detail, on
/// the grounds that a person at a terminal asked.
public struct StderrLogging: Logging {
    public let verbose: Bool
    private let write: @Sendable (String) -> Void

    public init(
        verbose: Bool, write: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }
    ) {
        self.verbose = verbose
        self.write = write
    }

    public func log(_ level: LogLevel, _ category: LogCategory, _ message: String, private detail: String?) {
        guard verbose || level >= .notice else { return }
        let suffix = detail.map { verbose ? ": \($0)" : " <private>" } ?? ""
        write("prinbox: \(message)\(suffix)\n")
    }
}
