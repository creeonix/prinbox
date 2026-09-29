import Foundation
import Testing

@testable import PrinboxCore

/// Guards scripts/anonymize.jq: recorded fixtures are committed, so nothing private may survive it.
@Suite struct AnonymizerTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var allowed: [Regex<Substring>] {
        [
            /PR_\d+/, /PR title \d+/, /acme\/repo-\d+/, /me|user-\d+/, /redacted/,
            /https:\/\/github\.com\/acme\/repo-\d+\/pull\/\d+/,
            /https:\/\/avatars\.githubusercontent\.com\/u\/\d+\?v=4/,
            /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/,
            /APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED|COMMENTED|DISMISSED|PENDING/,
            /MERGEABLE|CONFLICTING|UNKNOWN|SUCCESS|FAILURE|ERROR|EXPECTED|FORBIDDEN|NOT_FOUND|RATE_LIMITED/,
            /ReviewRequestedEvent|ReadyForReviewEvent|User|Team|Bot|Mannequin/,
        ]
    }

    static func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap(strings(in:))
        case let object as [String: Any]: object.values.flatMap(strings(in:))
        default: []
        }
    }

    static func unexpectedStrings(in data: Data) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data)
        return strings(in: json).filter { string in !allowed.contains { string.wholeMatch(of: $0) != nil } }
    }

    @Test func committedFixtureHoldsOnlyPlaceholders() throws {
        #expect(try Self.unexpectedStrings(in: Fixture.data("live-2026-09-29")) == [])
    }

    @Test func unknownFieldsAreDroppedNotCopied() async throws {
        let raw =
            #"{"data":{"viewer":{"login":"secret-viewer"},"review":{"issueCount":1,"nodes":[{"#
            + #""id":"PR_kwSECRET","number":5,"title":"Secret title","url":"https://github.com/secret-org/app/pull/5","#
            + #""isDraft":false,"additions":1,"deletions":2,"createdAt":"2026-08-01T09:00:00Z","updatedAt":"2026-08-01T09:00:00Z","#
            + #""headRefName":"secret-branch","bodyText":"secret body","#
            + #""author":{"login":"secret-author","avatarUrl":"https://avatars.githubusercontent.com/u/42?s=64","name":"Secret Name"},"#
            + #""repository":{"nameWithOwner":"secret-org/app","isArchived":false,"description":"secret repo"},"#
            + #""reviewDecision":null,"mergeable":"MERGEABLE","viewerLatestReview":null,"#
            + #""commits":{"nodes":[]},"timelineItems":{"nodes":[{"__typename":"ReviewRequestedEvent","#
            + #""createdAt":"2026-08-01T09:00:00Z","requestedReviewer":{"__typename":"Team","slug":"secret-team"}}]}}]},"#
            + #""mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}}}"#
        let jq = try #require(
            ["/usr/bin/jq", "/opt/homebrew/bin/jq"].first { FileManager.default.isExecutableFile(atPath: $0) })
        let script = Self.root.appendingPathComponent("scripts/anonymize.jq").path
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(
            "anonymizer-\(UUID().uuidString).json")
        try Data(raw.utf8).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let output = try await ProcessCommandRunner().run(
            executable: URL(fileURLWithPath: jq), arguments: ["-f", script, input.path], environment: [:],
            timeout: .seconds(10))
        #expect(output.exitCode == 0, "\(output.stderr)")
        #expect(try Self.unexpectedStrings(in: output.stdout) == [])
    }
}
