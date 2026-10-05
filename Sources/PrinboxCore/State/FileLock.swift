import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#else
    import Darwin
#endif

/// An advisory lock (`flock`) on a sidecar file, held around a reload-apply-replace of state.json or
/// cache.json so the app and the command never lose each other's writes. The lock is tried without blocking
/// for up to `patience`; past that the writer logs a notice and writes anyway, so a stuck process can never
/// freeze the menu bar app. The kernel releases the lock when the holder dies.
public struct FileLock: Sendable {
    public static let defaultPatience: TimeInterval = 2

    public let url: URL
    public let patience: TimeInterval
    private let logger: Logging

    public init(url: URL, patience: TimeInterval = FileLock.defaultPatience, logger: Logging = NullLogging()) {
        self.url = url
        self.patience = patience
        self.logger = logger
    }

    /// Runs `body` holding the lock when it could be taken.
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        let descriptor = acquire()
        defer { release(descriptor) }
        return try body()
    }

    private func acquire() -> Int32? {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            logger.notice(.state, "lock file not opened, writing without it")
            return nil
        }
        let deadline = Date().addingTimeInterval(patience)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK || Date() >= deadline {
                logger.notice(.state, "lock not acquired within \(Int(patience * 1000)) ms, writing without it")
                close(descriptor)
                return nil
            }
            usleep(20_000)
        }
        return descriptor
    }

    private func release(_ descriptor: Int32?) {
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
