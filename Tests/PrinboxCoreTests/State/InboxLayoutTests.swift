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
}
