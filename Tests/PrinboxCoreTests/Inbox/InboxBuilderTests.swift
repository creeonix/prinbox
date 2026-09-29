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
}
