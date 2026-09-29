import Foundation

/// Finds the gh binary. Apps launched from Finder or at login do not inherit the shell PATH, so the
/// Homebrew locations are checked explicitly before PATH.
public struct GhLocator: Sendable {
    public static let fixedCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private let overridePath: String?
    private let environmentPath: String?
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        overridePath: String? = UserDefaults.standard.string(forKey: "ghPath"),
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.overridePath = overridePath
        self.environmentPath = environmentPath
        self.isExecutable = isExecutable
    }

    public func locate() -> URL? {
        let fromPath = (environmentPath ?? "").split(separator: ":").map { "\($0)/gh" }
        let candidates = [overridePath].compactMap { $0 } + Self.fixedCandidates + fromPath
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }
}
