import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxBuilderTests {
    let reviewed = ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-01T11:00:00Z"))

    @Test func dropsArchivedRepositories() {
        let inbox = InboxBuilder.build(makeResult([makePR(id: "old", isArchived: true, source: .mine)]))
        #expect(inbox.sections.isEmpty)
    }

    @Test func emitsNonEmptySectionsInDisplayOrder() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "w", source: .mine),
                makePR(id: "m", source: .mentions),
                makePR(id: "r", source: .review),
            ]))
        #expect(inbox.sections.map(\.kind) == [.needsReview, .mentions, .waitingOnOthers])
    }

    @Test func reviewSectionsPutTheLongestWaitingFirst() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "new", number: 3, reviewRequestedAt: date("2026-08-05T10:00:00Z")),
                makePR(id: "old", number: 2, reviewRequestedAt: date("2026-08-02T10:00:00Z")),
                makePR(id: "tie", number: 1, reviewRequestedAt: date("2026-08-05T10:00:00Z")),
            ]))
        #expect(inbox.section(.needsReview)?.rows.map(\.id) == ["old", "tie", "new"])
    }

    @Test func ownSectionsPutTheNewestFirst() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "a", updatedAt: date("2026-08-02T10:00:00Z"), source: .mine),
                makePR(id: "b", updatedAt: date("2026-08-05T10:00:00Z"), source: .mine),
            ]))
        #expect(inbox.section(.waitingOnOthers)?.rows.map(\.id) == ["b", "a"])
    }

    @Test func badgeCountsReviewAndMentionSectionsWithoutDrafts() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "r1"), makePR(id: "r2"), makePR(id: "draft", isDraft: true),
                makePR(id: "again", viewerReview: reviewed),
                makePR(id: "m", source: .mentions),
                makePR(id: "mine", reviewDecision: .approved, source: .mine),
            ]))
        #expect(inbox.badgeCount == 4)
    }

    @Test func capsRowsAndCountsTheOverflow() {
        let prs = (1...10).map { makePR(id: "p\($0)", number: $0) }
        let section = InboxBuilder.build(makeResult(prs)).section(.needsReview)
        #expect(section?.rows.count == 8)
        #expect(section?.count == 10)
        #expect(section?.moreCount == 2)
    }

    @Test func unfetchedResultsGoToTheLastSectionOfTheirSearch() {
        let result = makeResult([makePR(id: "r")], totals: [.review: 12, .mentions: 0, .mine: 0])
        let inbox = InboxBuilder.build(result)
        #expect(inbox.section(.needsReview)?.moreCount == 0)
        #expect(inbox.section(.takeAnotherLook)?.rows.isEmpty == true)
        #expect(inbox.section(.takeAnotherLook)?.moreCount == 11)
    }

    @Test func passesWarningsThrough() {
        #expect(InboxBuilder.build(makeResult([], warnings: ["w"])).warnings == ["w"])
    }

    @Test func emptyResultIsAnEmptyInbox() {
        let inbox = InboxBuilder.build(makeResult([]))
        #expect(inbox.isEmpty)
        #expect(inbox.badgeCount == 0)
    }

    @Test func groupsRowsByOwnerInOrderOfFirstAppearance() throws {
        let prs = [
            makePR(id: "a", number: 1, repository: "acme/web", reviewRequestedAt: date("2026-08-01T10:00:00Z")),
            makePR(id: "g", number: 2, repository: "globex/billing", reviewRequestedAt: date("2026-08-02T10:00:00Z")),
            makePR(id: "b", number: 3, repository: "acme/api", reviewRequestedAt: date("2026-08-03T10:00:00Z")),
        ]
        let section = try #require(InboxBuilder.build(makeResult(prs)).section(.needsReview))
        #expect(section.groups.map(\.org) == ["acme", "globex"])
        #expect(section.groups[0].rows.map(\.id) == ["a", "b"])
        #expect(section.groups[1].rows.map(\.id) == ["g"])
        #expect(section.rows.map(\.id) == ["a", "g", "b"])
    }

    @Test func spansMultipleOrgsLooksAtEveryRow() {
        let one = InboxBuilder.build(
            makeResult([makePR(id: "a", repository: "acme/web"), makePR(id: "b", repository: "acme/api")]))
        #expect(one.spansMultipleOrgs == false)
        #expect(one.sections[0].groups.count == 1)
        let two = InboxBuilder.build(
            makeResult([
                makePR(id: "a", repository: "acme/web"),
                makePR(id: "b", repository: "globex/api", source: .mine),
            ]))
        #expect(two.spansMultipleOrgs)
        #expect(Inbox.empty.spansMultipleOrgs == false)
    }

    @Test func spansMultipleOrgsCountsRowsBeyondTheCap() {
        let acme = (1...9).map { makePR(id: "a\($0)", number: $0, repository: "acme/web") }
        let globex = [makePR(id: "g", number: 10, repository: "globex/api")]
        let inbox = InboxBuilder.build(makeResult(acme + globex))
        #expect(inbox.spansMultipleOrgs)
        #expect(inbox.section(.needsReview)?.rows.count == 8)
    }

    @Test func snoozedRowsLeaveTheBadgeAndSortAfterOwnRows() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "r", number: 1, updatedAt: date("2026-08-09T10:00:00Z"), source: .review),
                makePR(id: "m", number: 2, updatedAt: date("2026-08-08T10:00:00Z"), source: .mentions),
                makePR(id: "own", number: 3, updatedAt: date("2026-08-01T10:00:00Z"), source: .mine),
            ]), snoozed: ["r", "m"])
        #expect(inbox.badgeCount == 0)
        #expect(inbox.sections.map(\.kind) == [.waitingOnOthers])
        #expect(inbox.section(.waitingOnOthers)?.rows.map(\.id) == ["own", "r", "m"])
        #expect(
            inbox.section(.waitingOnOthers)?.rows.map(\.classification.reason) == [
                .waitingForReview, .snoozed, .snoozed,
            ])
    }

    @Test func snoozedRowsAreNeverHiddenByTheCap() {
        let own = (1...9).map { makePR(id: "o\($0)", number: $0, source: .mine) }
        let parked = (1...3).map { makePR(id: "s\($0)", number: 100 + $0, repository: "globex/x") }
        let inbox = InboxBuilder.build(makeResult(own + parked), snoozed: Set(parked.map(\.id)))
        let section = inbox.section(.waitingOnOthers)
        #expect(section?.rows.count == 8 + 3)
        #expect(section?.rows.suffix(3).map(\.id) == ["s1", "s2", "s3"])
        #expect(section?.count == 12)
        #expect(section?.moreCount == 1)
        #expect(inbox.spansMultipleOrgs)
    }
}
