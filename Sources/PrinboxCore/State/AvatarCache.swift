import Foundation

/// Disk cache for author avatars, one file per login, refreshed after `maxAge`. The cache is best-effort:
/// a failed download or write falls back to the stale copy (or nil, and the view shows initials).
/// Concurrent requests for the same login share one download.
public actor AvatarCache {
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 3600

    private let directory: URL
    private let loader: DataLoading
    private let maxAge: TimeInterval
    private let clock: @Sendable () -> Date
    private var downloads: [String: Task<Data?, Never>] = [:]

    public init(
        directory: URL, loader: DataLoading = URLSessionDataLoader(),
        maxAge: TimeInterval = AvatarCache.defaultMaxAge, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.loader = loader
        self.maxAge = maxAge
        self.clock = clock
    }

    /// ~/Library/Caches/<bundleID>/avatars
    public static func defaultDirectory(bundleID: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID)
            .appendingPathComponent("avatars")
    }

    public func data(login: String, url: URL?) async -> Data? {
        let file = directory.appendingPathComponent(Self.fileName(for: login))
        let cached = try? Data(contentsOf: file)
        if let cached, isFresh(file) { return cached }
        guard let url else { return cached }
        if let running = downloads[login] { return await running.value ?? cached }
        let loader = self.loader
        let task = Task { try? await loader.load(url) }
        downloads[login] = task
        let downloaded = await task.value
        downloads[login] = nil
        guard let downloaded else { return cached }
        write(downloaded, to: file)
        return downloaded
    }

    /// Anything outside [A-Za-z0-9_-] becomes "_", so a login can never name a path outside the directory.
    static func fileName(for login: String) -> String {
        let safe = login.map { char -> Character in
            char.isASCII && (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "_"
        }
        return String(safe) + ".png"
    }

    private func isFresh(_ file: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attributes?[.modificationDate] as? Date
        return modified.map { clock().timeIntervalSince($0) < maxAge } ?? false
    }

    private func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
