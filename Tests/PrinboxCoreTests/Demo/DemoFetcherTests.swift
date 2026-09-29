import Foundation
import Testing

@testable import PrinboxCore

@Suite struct DemoFetcherTests {
    let now = date("2026-08-10T12:00:00Z")

    func inbox() async throws -> Inbox {
        let clock = now
        return InboxBuilder.build(try await DemoFetcher(now: { clock }).fetch())
    }

    @Test func fillsEverySection() async throws {
        #expect(try await inbox().sections.map(\.kind) == SectionKind.allCases)
    }

    @Test func badgeCountsTheNonDraftReviewAndMentionRows() async throws {
        #expect(try await inbox().badgeCount == 4)
    }

    @Test func usesOnlyFictionalRepositories() async throws {
        let rows = try await inbox().sections.flatMap(\.rows)
        #expect(rows.allSatisfy { $0.pullRequest.repository.hasPrefix("acme/") })
    }

    @Test func agesAreRelativeToNow() async throws {
        let review = try #require(try await inbox().section(.needsReview)?.rows.first)
        #expect(RowText.meta(review, now: now).contains("waiting 2d"))
    }
}
