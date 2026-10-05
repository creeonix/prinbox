import Foundation

/// Finds the gh binary. Apps launched from Finder or at login do not inherit the shell PATH, so the
/// Homebrew locations are checked explicitly before PATH. A `ghPath` setting is exclusive: when set,
/// only that path is used, so a wrong override is reported instead of silently bypassed.
public struct GhLocator: Sendable {
    public static let fixedCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    public static let overrideKey = "ghPath"

    /// The non-empty `ghPath` override, if any.
    public let overridePath: String?
    private let environmentPath: String?
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        overridePath: String? = nil,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.overridePath = overridePath.flatMap { $0.isEmpty ? nil : $0 }
        self.environmentPath = environmentPath
        self.isExecutable = isExecutable
    }

    public func locate() -> URL? {
        let fromPath = (environmentPath ?? "").split(separator: ":").map { "\($0)/gh" }
        let candidates = overridePath.map { [$0] } ?? Self.fixedCandidates + fromPath
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }
}
