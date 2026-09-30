import Foundation

public struct Release: Sendable, Equatable {
    public let tag: String
    public let url: URL

    public init(tag: String, url: URL) {
        self.tag = tag
        self.url = url
    }

    public var version: AppVersion? { AppVersion(tag) }

    /// "0.3.0" for `v0.3.0`; the raw tag when it does not parse.
    public var displayVersion: String { version?.description ?? tag }
}

public protocol ReleaseChecking: Sendable {
    func latestRelease() async throws -> Release
}

/// Asks gh for the latest release of the PRInbox repository. Any failure is thrown and the caller
/// drops it: an update check is best effort and never becomes an error the user sees.
public struct GhReleaseChecker: ReleaseChecking {
    public static let repository = "creeonix/prinbox"
    /// The fallback page when no release is known.
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases/latest")!
    public static let defaultTimeout: Duration = .seconds(15)

    private let locator: GhLocator
    private let runner: CommandRunning
    private let timeout: Duration

    public init(
        locator: GhLocator = GhLocator(), runner: CommandRunning = ProcessCommandRunner(),
        timeout: Duration = GhReleaseChecker.defaultTimeout
    ) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func latestRelease() async throws -> Release {
        guard let gh = locator.locate() else { throw FetchError.ghNotFound }
        let output = try await runner.run(
            executable: gh, arguments: ["api", "repos/\(Self.repository)/releases/latest"],
            environment: GhClient.environment(), timeout: timeout)
        guard output.exitCode == 0 else { throw FetchError.other("gh exited \(output.exitCode)") }
        return try Self.decode(output.stdout)
    }

    static func decode(_ data: Data) throws -> Release {
        struct Body: Decodable {
            let tagName: String
            let htmlUrl: URL

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlUrl = "html_url"
            }
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        return Release(tag: body.tagName, url: body.htmlUrl)
    }
}
