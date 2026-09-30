import Foundation
import Testing

@testable import PrinboxCore

/// Guards scripts/anonymize.jq: recorded fixtures are committed, so nothing private may survive it.
@Suite struct AnonymizerTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var allowed: [Regex<Substring>] {
        [
            /PR_\d+/, /PR title \d+/, /org-\d+\/repo-\d+/, /org-\d+/, /me|user-\d+/, /ref-\d+/, /redacted/,
            /https:\/\/github\.com\/org-\d+\/repo-\d+\/pull\/\d+/,
            /https:\/\/avatars\.githubusercontent\.com\/u\/\d+\?v=4/,
            /\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ/,
            /APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED|COMMENTED|DISMISSED|PENDING/,
            /MERGEABLE|CONFLICTING|UNKNOWN|SUCCESS|FAILURE|ERROR|EXPECTED|FORBIDDEN|NOT_FOUND|RATE_LIMITED/,
            /ReviewRequestedEvent|ReadyForReviewEvent|User|Team|Bot|Mannequin|Organization/,
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
        #expect(try Self.unexpectedStrings(in: Fixture.data("live-2026-09-30")) == [])
    }

    static func anonymize(_ raw: String) async throws -> Data {
        let jq = try #require(
            ["/usr/bin/jq", "/opt/homebrew/bin/jq"].first { FileManager.default.isExecutableFile(atPath: $0) })
        let script = root.appendingPathComponent("scripts/anonymize.jq").path
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(
            "anonymizer-\(UUID().uuidString).json")
        try Data(raw.utf8).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let output = try await ProcessCommandRunner().run(
            executable: URL(fileURLWithPath: jq), arguments: ["-f", script, input.path], environment: [:],
            timeout: .seconds(10))
        #expect(output.exitCode == 0, "\(output.stderr)")
        return output.stdout
    }

    /// A details node with every field the query asks for, plus fields it does not (bodies, names, paths),
    /// all carrying the word "secret".
    static func node(_ id: String, repo: String, owner: String, kind: String = "Organization") -> String {
        #"{"id":"\#(id)","number":5,"title":"Secret title","url":"https://github.com/\#(repo)/pull/5","#
            + #""isDraft":false,"additions":1,"deletions":2,"createdAt":"2026-08-01T09:00:00Z","updatedAt":"2026-08-01T09:00:00Z","#
            + #""headRefName":"secret-branch","baseRefName":"main","bodyText":"secret body","totalCommentsCount":3,"#
            + #""author":{"login":"secret-author","avatarUrl":"https://avatars.githubusercontent.com/u/42?s=64","name":"Secret Name"},"#
            + #""repository":{"nameWithOwner":"\#(repo)","isArchived":false,"description":"secret repo","#
            + #""owner":{"__typename":"\#(kind)","login":"\#(owner)","avatarUrl":"https://avatars.githubusercontent.com/u/7?s=64","name":"Secret Org"}},"#
            + #""reviewDecision":null,"mergeable":"MERGEABLE","viewerLatestReview":null,"#
            + #""latestOpinionatedReviews":{"nodes":[{"state":"APPROVED","author":{"login":"secret-reviewer"}},null]},"#
            + #""commits":{"nodes":[{"commit":{"committedDate":"2026-08-01T08:00:00Z","statusCheckRollup":{"state":"SUCCESS"},"message":"secret"}}]},"#
            + #""timelineItems":{"nodes":[{"__typename":"ReviewRequestedEvent","#
            + #""createdAt":"2026-08-01T09:00:00Z","requestedReviewer":{"__typename":"Team","slug":"secret-team"}}]},"#
            + #""reviewThreads":{"totalCount":1,"nodes":[{"isResolved":false,"path":"secret/file.swift","comments":{"totalCount":2,"nodes":["#
            + #"{"author":{"login":"secret-viewer"},"createdAt":"2026-08-01T10:00:00Z","body":"secret comment"},"#
            + #"{"author":{"login":"secret-reviewer"},"createdAt":"2026-08-01T11:00:00Z","body":"secret reply"}]}}]},"#
            + #""reviews":{"totalCount":1,"nodes":[{"author":{"login":"secret-reviewer"},"state":"APPROVED","submittedAt":"2026-08-01T12:00:00Z","bodyText":"lgtm"}]}}"#
    }

    /// A two-phase fixture: every node is a hit of the review search, all nodes in one batch.
    static func fixture(_ entries: [(id: String, node: String)]) -> String {
        let hits = entries.map { #"{"id":"\#($0.id)","updatedAt":"2026-08-01T09:00:00Z"}"# }.joined(separator: ",")
        return
            #"{"search":{"data":{"viewer":{"login":"secret-viewer"},"rateLimit":{"cost":1,"remaining":4999,"resetAt":"2026-08-01T13:00:00Z"},"#
            + #""review":{"issueCount":\#(entries.count),"nodes":[\#(hits)]},"mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}}},"#
            + #""details":[{"data":{"rateLimit":{"cost":5,"remaining":4994,"resetAt":"2026-08-01T13:00:00Z"},"nodes":[\#(entries.map(\.node).joined(separator: ","))]}}]}"#
    }

    @Test func unknownFieldsAreDroppedNotCopied() async throws {
        let output = try await Self.anonymize(
            Self.fixture([("PR_kwSECRET", Self.node("PR_kwSECRET", repo: "secret-org/app", owner: "secret-org"))]))
        #expect(try Self.unexpectedStrings(in: output) == [])
    }

    @Test func distinctOwnersStayDistinctAndOwnersMatchTheirRepositories() async throws {
        let output = try await Self.anonymize(
            Self.fixture([
                ("PR_1", Self.node("PR_1", repo: "zeta-org/app", owner: "zeta-org")),
                ("PR_2", Self.node("PR_2", repo: "alpha-org/lib", owner: "alpha-org", kind: "User")),
                ("PR_3", Self.node("PR_3", repo: "zeta-org/other", owner: "zeta-org")),
            ]))
        let result = try Fixture.twoPhase(data: output)
        let byID = Dictionary(uniqueKeysWithValues: result.pullRequests.map { ($0.id, $0) })
        #expect(byID["PR_1"]?.repository == "org-2/repo-2")
        #expect(byID["PR_2"]?.repository == "org-1/repo-1")
        #expect(byID["PR_3"]?.repository == "org-2/repo-3")
        #expect(byID["PR_2"]?.ownerIsOrganization == false)
        #expect(byID["PR_1"]?.ownerIsOrganization == true)
        #expect(byID["PR_1"]?.ownerAvatarURL == byID["PR_3"]?.ownerAvatarURL)
        #expect(byID["PR_1"]?.commentCount == 3)
        #expect(byID["PR_1"]?.reviewDecision == .approved)
        #expect(result.fingerprint.count == 3)
    }

    @Test func conversationAuthorsAndBranchesBecomePlaceholders() async throws {
        let output = try await Self.anonymize(
            Self.fixture([("PR_1", Self.node("PR_1", repo: "secret-org/app", owner: "secret-org"))]))
        let pr = try #require(try Fixture.twoPhase(data: output).pullRequests.first)
        #expect(pr.baseRef == "ref-1")
        #expect(pr.headRef == "ref-2")
        #expect(pr.authorLogin == "user-1")
        #expect(pr.threads?.first?.comments.map(\.authorLogin) == ["me", "user-2"])
        #expect(pr.threads?.first?.isResolved == false)
        #expect(
            pr.reviews == [Review(authorLogin: "user-2", state: "APPROVED", submittedAt: date("2026-08-01T12:00:00Z"))])
        #expect(pr.lastCommitAt == date("2026-08-01T08:00:00Z"))
    }
}
