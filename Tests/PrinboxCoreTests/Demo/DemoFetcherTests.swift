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
        #expect(try await inbox().badgeCount == 8)
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

    @Test func refreshesReturnIdenticalPullRequests() async throws {
        let clock = TestClock(now)
        let fetcher = DemoFetcher(now: { clock.now })
        let first = try await fetcher.fetch()
        clock.advance(3600)
        let second = try await fetcher.fetch()
        #expect(first == second)
    }

    @Test func initialStateParksOneReviewRequestAndLeavesFourRowsNew() async throws {
        let clock = now
        let fetcher = DemoFetcher(now: { clock })
        let state = fetcher.initialState
        let result = try await fetcher.fetch()
        let snoozed = try #require(result.pullRequests.first { $0.id == "DEMO_1284" })
        let entry = SnoozeEntry(snoozedAt: now.addingTimeInterval(-3600), updatedAt: snoozed.updatedAt)
        #expect(state.snoozed == ["DEMO_1284": entry])
        #expect(state.seen?.count == result.pullRequests.count - 4)
        let unseen = result.pullRequests.filter { state.seen?[$0.id] == nil }.map(\.id)
        #expect(Set(unseen) == ["DEMO_2104", "DEMO_482", "DEMO_58", "DEMO_145"])
        let box = InboxBuilder.build(result, snoozed: Set(state.snoozed.keys))
        #expect(box.sections.map(\.kind) == SectionKind.allCases)
        #expect(box.badgeCount == 7)
        #expect(box.section(.waitingOnOthers)?.rows.last?.classification.reason == .snoozed)
    }

    @Test func showsTwoRepliesAndOneOpenThread() async throws {
        let box = try await inbox()
        let replies = try #require(box.section(.repliesToYou))
        #expect(replies.rows.map(\.id) == ["DEMO_2077", "DEMO_145"])
        #expect(replies.rows.map(\.pendingReplies) == [2, 1])
        #expect(replies.rows.map(\.classification.reason) == [.awaitingReply, .awaitingReply])
        #expect(RowText.meta(replies.rows[0], now: now).contains("waiting 4h"))
        #expect(RowText.meta(replies.rows[1], now: now).contains("waiting 1h"))
        let own = try #require(box.section(.yourPRs)?.rows.first { $0.id == "DEMO_489" })
        #expect(own.classification.reason == .openThreads)
        #expect(own.pendingReplies == 1)
        #expect(RowMarks.isReady(own.pullRequest))
        #expect(box.sections.flatMap(\.rows).count == 16)
    }
}
