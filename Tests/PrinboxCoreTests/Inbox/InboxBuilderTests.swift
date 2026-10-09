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

    @Test func repliesSectionSitsAfterNeedsReviewAndCountsTowardTheBadge() {
        let owed = thread(
            comment("alice", date("2026-08-03T10:00:00Z")), comment(testViewer, date("2026-08-04T10:00:00Z")),
            comment("alice", date("2026-08-05T10:00:00Z")))
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "r", number: 1, source: .review),
                makePR(id: "reply", number: 2, source: .involved, threads: [owed]),
                makePR(id: "again", number: 3, viewerReview: reviewed, source: .review),
                makePR(id: "draft", number: 4, isDraft: true, source: .involved, threads: [owed]),
            ]))
        #expect(inbox.sections.map(\.kind) == [.needsReview, .repliesToYou, .takeAnotherLook])
        #expect(inbox.section(.repliesToYou)?.rows.map(\.id) == ["reply", "draft"])
        #expect(inbox.section(.repliesToYou)?.rows.first?.pendingReplies == 1)
        #expect(inbox.badgeCount == 3)
    }

    @Test func hiddenPullRequestsLeaveNoTraceAndInvolvedHasNoMoreRow() {
        let inbox = InboxBuilder.build(
            makeResult(
                [
                    makePR(id: "r", repository: "acme/web", source: .review),
                    makePR(id: "quiet", repository: "globex/x", source: .involved),
                ],
                totals: [.review: 1, .mentions: 0, .mine: 0, .involved: 40]))
        #expect(inbox.sections.map(\.kind) == [.needsReview])
        #expect(!inbox.spansMultipleOrgs)
        #expect(inbox.section(.needsReview)?.moreCount == 0)
    }

    func ago(_ day: Int) -> Date { date("2026-08-0\(day)T10:00:00Z") }

    @Test func aChainStaysContiguousWhereItsMostUrgentMemberSorts() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "a", number: 1, reviewRequestedAt: ago(2), headRef: "f1", baseRef: "main"),
                makePR(id: "c", number: 3, reviewRequestedAt: ago(3)),
                makePR(id: "b", number: 2, reviewRequestedAt: ago(4), headRef: "f2", baseRef: "f1"),
            ]))
        let rows = inbox.section(.needsReview)?.rows
        #expect(rows?.map(\.id) == ["a", "b", "c"])
        #expect(rows?.map { $0.stack?.position } == [1, 2, nil])
    }

    @Test func aBlockSortsByItsMostUrgentMemberEvenWhenThatIsTheTop() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "a", number: 1, reviewRequestedAt: ago(4), headRef: "f1", baseRef: "main"),
                makePR(id: "c", number: 3, reviewRequestedAt: ago(3)),
                makePR(id: "b", number: 2, reviewRequestedAt: ago(2), headRef: "f2", baseRef: "f1"),
            ]))
        #expect(inbox.section(.needsReview)?.rows.map(\.id) == ["a", "b", "c"])
    }

    @Test func theCapKeepsABlockWholeWhenItStartsInsideIt() {
        let singles = (1...7).map {
            makePR(id: "s\($0)", number: $0, reviewRequestedAt: date("2026-08-01T0\($0):00:00Z"))
        }
        let x = makePR(id: "x", number: 8, reviewRequestedAt: ago(2), headRef: "f1", baseRef: "main")
        let y = makePR(id: "y", number: 9, reviewRequestedAt: ago(3), headRef: "f2", baseRef: "f1")
        let whole = InboxBuilder.build(makeResult(singles + [x, y]), cap: 8)
        #expect(whole.section(.needsReview)?.rows.map(\.id).suffix(2) == ["x", "y"])
        #expect(whole.section(.needsReview)?.moreCount == 0)
        let cut = InboxBuilder.build(makeResult(singles + [x, y]), cap: 7)
        #expect(cut.section(.needsReview)?.rows.count == 7)
        #expect(cut.section(.needsReview)?.moreCount == 2)
    }

    @Test func aSnoozedMemberStaysWithTheSnoozedRowsAndKeepsItsPosition() {
        let base = makePR(id: "base", number: 1, updatedAt: ago(5), source: .mine, headRef: "f1", baseRef: "main")
        let top = makePR(id: "top", number: 2, updatedAt: ago(4), source: .mine, headRef: "f2", baseRef: "f1")
        let inbox = InboxBuilder.build(makeResult([base, top]), snoozed: ["base"])
        let rows = inbox.section(.waitingOnOthers)?.rows
        #expect(rows?.map(\.id) == ["top", "base"])
        #expect(rows?.last?.classification.reason == .snoozed)
        #expect(rows?.last?.stack?.position == 1)
    }

    @Test func positionsCrossSections() {
        let base = makePR(id: "base", number: 1, reviewRequestedAt: ago(2), headRef: "f1", baseRef: "main")
        let top = makePR(id: "top", number: 2, ci: .failure, source: .mine, headRef: "f2", baseRef: "f1")
        let inbox = InboxBuilder.build(makeResult([base, top]))
        #expect(inbox.section(.needsReview)?.rows.first?.stack?.position == 1)
        #expect(
            inbox.section(.yourPRs)?.rows.first?.stack
                == StackPosition(position: 2, size: 2, parentID: "base", parentNumber: 1, rootID: "base"))
    }

    @Test func aForkHasNoPositionsAndNoReordering() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "a", number: 1, reviewRequestedAt: ago(1), headRef: "f", baseRef: "main"),
                makePR(id: "c", number: 3, reviewRequestedAt: ago(2)),
                makePR(id: "b", number: 2, reviewRequestedAt: ago(3), headRef: "l", baseRef: "f"),
                makePR(id: "d", number: 4, reviewRequestedAt: ago(4), headRef: "r", baseRef: "f"),
            ]))
        let rows = inbox.section(.needsReview)?.rows
        #expect(rows?.map(\.id) == ["a", "c", "b", "d"])
        #expect(rows?.allSatisfy { $0.stack == nil } == true)
    }

    @Test func theInboxCarriesTheScopeForItsMoreLinks() {
        let scope = SearchScope(hideDrafts: true)
        let inbox = InboxBuilder.build(makeResult([makePR()]), scope: scope)
        #expect(inbox.scope == scope)
        #expect(inbox.moreURL(.needsReview) == SectionKind.needsReview.moreURL(scope: scope))
        #expect(InboxBuilder.build(makeResult([makePR()])).scope == .none)
        #expect(Inbox.empty.moreURL(.mentions) == SectionKind.mentions.moreURL)
    }

    @Test func aBlockEndingExactlyAtTheCapIsNotStretched() {
        // s1..s6 wait since Aug 1 (01:00..06:00), the block x (Aug 2), y (Aug 3) follows, w (Aug 5) is last:
        // s1 s2 s3 s4 s5 s6 x y w. Cap 8 ends on y, the block's last member; nothing after it shares the root.
        let singles = (1...6).map {
            makePR(id: "s\($0)", number: $0, reviewRequestedAt: date("2026-08-01T0\($0):00:00Z"))
        }
        let x = makePR(id: "x", number: 7, reviewRequestedAt: ago(2), headRef: "f1", baseRef: "main")
        let y = makePR(id: "y", number: 8, reviewRequestedAt: ago(3), headRef: "f2", baseRef: "f1")
        let w = makePR(id: "w", number: 9, reviewRequestedAt: ago(5))
        let inbox = InboxBuilder.build(makeResult(singles + [x, y, w]), cap: 8)
        #expect(inbox.section(.needsReview)?.rows.map(\.id) == ["s1", "s2", "s3", "s4", "s5", "s6", "x", "y"])
        #expect(inbox.section(.needsReview)?.moreCount == 1)
    }

    @Test func theCapStretchesOverAWholeChainOfThree() {
        // s1..s6, then the block x (Aug 2), y (Aug 3), z (Aug 4), then w (Aug 5): ten rows. Cap 7 lands on x
        // and takes y and z with it; cap 8 lands on y and takes z. Both show nine rows and leave w.
        let singles = (1...6).map {
            makePR(id: "s\($0)", number: $0, reviewRequestedAt: date("2026-08-01T0\($0):00:00Z"))
        }
        let x = makePR(id: "x", number: 7, reviewRequestedAt: ago(2), headRef: "f1", baseRef: "main")
        let y = makePR(id: "y", number: 8, reviewRequestedAt: ago(3), headRef: "f2", baseRef: "f1")
        let z = makePR(id: "z", number: 9, reviewRequestedAt: ago(4), headRef: "f3", baseRef: "f2")
        let w = makePR(id: "w", number: 10, reviewRequestedAt: ago(5))
        for cap in [7, 8] {
            let inbox = InboxBuilder.build(makeResult(singles + [x, y, z, w]), cap: cap)
            #expect(inbox.section(.needsReview)?.rows.map(\.id).suffix(3) == ["x", "y", "z"], "cap \(cap)")
            #expect(inbox.section(.needsReview)?.rows.count == 9, "cap \(cap)")
            #expect(inbox.section(.needsReview)?.moreCount == 1, "cap \(cap)")
        }
    }

    @Test func reviewedRowsAreDroppedUnlessAsked() throws {
        let approved = ViewerReview(state: "APPROVED", submittedAt: date("2026-08-01T11:00:00Z"), commitOid: "aaa")
        let quiet = makePR(
            id: "q", updatedAt: date("2026-08-02T10:00:00Z"), viewerReview: approved, source: .involved, headOid: "aaa",
            viewerVerdict: approved)
        let newer = makePR(
            id: "n", updatedAt: date("2026-08-04T10:00:00Z"),
            viewerReview: ViewerReview(state: "COMMENTED", submittedAt: nil),
            source: .involved)
        let result = makeResult([quiet, newer], totals: [.review: 0, .mentions: 0, .mine: 0, .involved: 5])
        let hidden = InboxBuilder.build(result)
        #expect(hidden.sections.isEmpty)
        #expect(hidden.badgeCount == 0)
        let shown = InboxBuilder.build(result, showReviewed: true)
        let section = try #require(shown.section(.reviewed))
        #expect(section.rows.map(\.id) == ["n", "q"])
        // Two rows plus the involved search's three unfetched hits, attributed here only when the section shows.
        #expect(section.count == 5)
        #expect(section.moreCount == 3)
        #expect(shown.badgeCount == 0)
        #expect(shown.sections.map(\.kind) == [.reviewed])
    }

    @Test func aRowOpensTheDeltaWhenTheDiffMovedSinceYourVerdict() throws {
        let approved = ViewerReview(state: "APPROVED", submittedAt: nil, commitOid: "aaa")
        let moved = makePR(
            id: "m", number: 3, repository: "acme/api", viewerReview: approved, source: .involved, headOid: "ccc",
            viewerVerdict: approved)
        let row = try #require(
            InboxBuilder.build(makeResult([moved, makePR(id: "p")])).section(.takeAnotherLook)?.rows.first)
        #expect(row.openURL == URL(string: "https://github.com/acme/api/pull/3/files/aaa..ccc"))
        let plain = try #require(InboxBuilder.build(makeResult([makePR(id: "p")])).section(.needsReview)?.rows.first)
        #expect(plain.openURL == plain.pullRequest.url)
    }
}
