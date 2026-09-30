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
        #expect(try await inbox().badgeCount == 5)
    }

    @Test func spansThreeFictionalOrganizations() async throws {
        let box = try await inbox()
        let owners = Set(box.sections.flatMap(\.rows).map(\.pullRequest.ownerLogin))
        #expect(owners == ["acme", "globex", "initech"])
        #expect(box.spansMultipleOrgs)
        #expect(box.sections.flatMap(\.rows).allSatisfy { $0.pullRequest.ownerIsOrganization })
    }

    @Test func coversEveryMarkState() async throws {
        let marks = try await inbox().sections.flatMap(\.rows).map { RowMarks.marks(for: $0.pullRequest) }
        #expect(Set(marks.compactMap(\.ci)) == [.passed, .failed, .running])
        #expect(marks.contains { $0.ci == nil })
        #expect(Set(marks.compactMap(\.review)) == [.approved, .changesRequested])
        #expect(Set(marks.compactMap(\.merge)) == [.ready, .conflicts])
        #expect(marks.contains { $0.comments == nil })
        #expect(marks.contains { ($0.comments ?? 0) >= 10 })
    }

    @Test func agesAreRelativeToNow() async throws {
        let review = try #require(try await inbox().section(.needsReview)?.rows.first)
        #expect(RowText.meta(review, now: now).contains("waiting 2d"))
    }
}
