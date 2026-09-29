import Testing

@testable import PrinboxCore

/// Invariants of a response recorded from a real account (anonymized by scripts/anonymize.jq).
@Suite struct RecordedFixtureTests {
    let result: FetchResult

    init() throws {
        result = try PullRequestMapper.map(InboxResponse.decode(Fixture.data("live-2026-09-29")))
    }

    @Test func containsOnlyAnonymizedValues() {
        #expect(result.viewerLogin == "me")
        #expect(!result.pullRequests.isEmpty)
        for pr in result.pullRequests {
            #expect(pr.repository.hasPrefix("acme/repo-"))
            #expect(pr.title.hasPrefix("PR title "))
            #expect(pr.url.absoluteString.hasPrefix("https://github.com/acme/repo-"))
        }
    }

    @Test func ownPullRequestsLandInOwnSections() {
        let own: Set<SectionKind> = [.yourPRs, .waitingOnOthers]
        let rows = InboxBuilder.build(result).sections.flatMap(\.rows)
        for row in rows where row.pullRequest.source == .mine {
            #expect(own.contains(row.classification.section))
        }
    }

    @Test func archivedRepositoriesAreExcludedByTheQuery() {
        #expect(result.pullRequests.allSatisfy { !$0.isArchived })
    }
}
