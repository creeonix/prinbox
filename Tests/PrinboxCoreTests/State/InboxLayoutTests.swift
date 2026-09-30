import Testing

@testable import PrinboxCore

@Suite struct InboxLayoutTests {
    let inbox = InboxBuilder.build(
        makeResult((1...9).map { makePR(id: "r\($0)", number: $0) } + [makePR(id: "w", source: .mine)]))

    @Test func expandedSectionsListRowsThenTheMoreRow() {
        let items = InboxLayout.visibleItems(inbox, folded: [])
        #expect(items.first == .header(.needsReview))
        #expect(items.contains(.row("r8")))
        #expect(!items.contains(.row("r9")))
        #expect(items.contains(.more(.needsReview)))
        #expect(items.suffix(2) == [.header(.waitingOnOthers), .row("w")])
    }

    @Test func foldedSectionsShowOnlyTheirHeader() {
        let items = InboxLayout.visibleItems(inbox, folded: [.needsReview, .waitingOnOthers])
        #expect(items == [.header(.needsReview), .header(.waitingOnOthers)])
    }

    @Test func groupedOrderWalksRowsGroupByGroup() {
        let prs = [
            makePR(id: "a", number: 1, repository: "acme/web", reviewRequestedAt: date("2026-08-01T10:00:00Z")),
            makePR(id: "g", number: 2, repository: "globex/billing", reviewRequestedAt: date("2026-08-02T10:00:00Z")),
            makePR(id: "b", number: 3, repository: "acme/api", reviewRequestedAt: date("2026-08-03T10:00:00Z")),
        ]
        let inbox = InboxBuilder.build(makeResult(prs))
        let grouped = InboxLayout.visibleItems(inbox, folded: [], grouped: true)
        #expect(grouped == [.header(.needsReview), .row("a"), .row("b"), .row("g")])
        let flat = InboxLayout.visibleItems(inbox, folded: [], grouped: false)
        #expect(flat == [.header(.needsReview), .row("a"), .row("g"), .row("b")])
        #expect(InboxLayout.visibleItems(inbox, folded: [.needsReview], grouped: true) == [.header(.needsReview)])
    }

    @Test func groupedOrderKeepsTheMoreRowLast() {
        let items = InboxLayout.visibleItems(inbox, folded: [], grouped: true)
        #expect(items.contains(.more(.needsReview)))
        #expect(items.firstIndex(of: .more(.needsReview))! > items.firstIndex(of: .row("r8"))!)
    }
}
