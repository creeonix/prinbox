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
        let clock = now
        let result = try await DemoFetcher(now: { clock }).fetch()
        #expect(InboxBuilder.build(result).sections.map(\.kind) == SectionKind.allCases.filter { $0 != .reviewed })
        #expect(InboxBuilder.build(result, showReviewed: true).sections.map(\.kind) == SectionKind.allCases)
    }

    @Test func badgeCountsTheNonDraftReviewAndMentionRows() async throws {
        #expect(try await inbox().badgeCount == 11)
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
        #expect(box.sections.map(\.kind) == SectionKind.allCases.filter { $0 != .reviewed })
        #expect(box.badgeCount == 10)
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
        #expect(box.sections.flatMap(\.rows).count == 19)
    }

    @Test func twoChainsOneInsideASectionAndOneAcrossTwo() async throws {
        let box = try await inbox()
        let review = try #require(box.section(.needsReview))
        #expect(review.rows.prefix(2).map(\.id) == ["DEMO_1290", "DEMO_1291"])
        #expect(
            review.rows[0].stack
                == StackPosition(position: 1, size: 2, parentID: nil, parentNumber: nil, rootID: "DEMO_1290"))
        #expect(RowText.meta(review.rows[1], now: now).hasSuffix("· stack 2/2"))
        let base = try #require(box.section(.waitingOnOthers)?.rows.first { $0.id == "DEMO_1298" })
        let top = try #require(box.section(.yourPRs)?.rows.first { $0.id == "DEMO_1301" })
        #expect(base.stack?.position == 1)
        #expect(top.stack?.parentID == "DEMO_1298")
        #expect(RowText.compactTrailer(base, showOrg: true) == "· acme/web · stack 1/2")
        #expect(RowText.help(top) == "acme/web · stacked on #1298")
        #expect(box.sections.flatMap(\.rows).filter { $0.stack != nil }.count == 4)
    }

    @Test func defaultRepositoriesNarrowTheSampleInbox() async throws {
        let clock = now
        let request = FetchRequest(scope: SearchScope(repositories: ["acme/*", "globex/billing"]))
        guard case .result(let result) = try await DemoFetcher(now: { clock }).fetch(request) else {
            Issue.record("the demo answered unchanged")
            return
        }
        // 22 sample PRs; globex/sync (#917), initech/docs (#58, #140) and initech/tps (#612, #33) fall outside.
        let repositories = Set(result.pullRequests.map(\.repository))
        #expect(repositories == ["acme/web", "acme/api", "acme/shop", "globex/billing"])
        #expect(result.pullRequests.count == 17)
        #expect(result.totals == result.fetched)
        #expect(result.isComplete)
        let drafts = FetchRequest(scope: SearchScope(hideDrafts: true))
        guard case .result(let unfiltered) = try await DemoFetcher(now: { clock }).fetch(drafts) else { return }
        #expect(unfiltered.pullRequests.count == 22)
    }

    @Test func theSampleShowsBothPushesAndThreeReviewedRows() async throws {
        let box = try await inbox()
        let look = try #require(box.section(.takeAnotherLook))
        // Longest waiting first: #2210 pushed 6h ago, #917 requested 5h ago, #1284 requested 3h ago,
        // #733 pushed 2h ago.
        #expect(look.rows.map(\.id) == ["DEMO_2210", "DEMO_917", "DEMO_1284", "DEMO_733"])
        #expect(
            look.rows.map(\.classification.reason)
                == [.pushedSinceApproval, .reReviewRequested, .reReviewRequested, .pushedSinceChangesRequested])
        #expect(RowText.since(look.rows[0].pullRequest) == "2 commits since you approved")
        #expect(RowText.since(look.rows[1].pullRequest) == nil)
        #expect(RowText.since(look.rows[3].pullRequest) == "rewritten since you requested changes")
        #expect(look.rows[0].openURL == URL(string: "https://github.com/acme/api/pull/2210/files/3f9c2d1..b7e41a0"))
        #expect(
            look.rows[3].openURL == URL(string: "https://github.com/globex/billing/pull/733/files/a1b2c3d..e5f6a7b"))
        #expect(box.section(.reviewed) == nil)
        let clock = now
        let all = InboxBuilder.build(try await DemoFetcher(now: { clock }).fetch(), showReviewed: true)
        let reviewed = try #require(all.section(.reviewed))
        #expect(reviewed.rows.map(\.id) == ["DEMO_1250", "DEMO_702", "DEMO_140"])
        #expect(reviewed.rows.map(\.classification.reason) == [.youApproved, .youRequestedChanges, .youCommented])
        #expect(reviewed.rows.allSatisfy { $0.openURL == $0.pullRequest.url })
        #expect(all.badgeCount == 11)
        #expect(all.sections.flatMap(\.rows).count == 22)
    }
}
