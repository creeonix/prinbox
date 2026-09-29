import Testing

@testable import PrinboxCore

@Suite struct SelectionTests {
    let items: [InboxItemID] = [.header(.needsReview), .row("a"), .row("b"), .more(.needsReview)]

    @Test func downFromNothingSelectsTheFirstItem() {
        #expect(Selection().movingDown(in: items).current == .header(.needsReview))
    }

    @Test func upFromNothingSelectsTheLastItem() {
        #expect(Selection().movingUp(in: items).current == .more(.needsReview))
    }

    @Test func movementWrapsAtBothEnds() {
        #expect(Selection(current: .more(.needsReview)).movingDown(in: items).current == .header(.needsReview))
        #expect(Selection(current: .header(.needsReview)).movingUp(in: items).current == .more(.needsReview))
    }

    @Test func movingInAnEmptyListClearsTheSelection() {
        #expect(Selection(current: .row("a")).movingDown(in: []).current == nil)
    }

    @Test func reconcileKeepsASurvivingItem() {
        let after: [InboxItemID] = [.header(.needsReview), .row("b")]
        #expect(Selection(current: .row("b")).reconciled(previous: items, current: after).current == .row("b"))
    }

    @Test func foldingMovesTheSelectionToTheHeader() {
        let after: [InboxItemID] = [.header(.needsReview)]
        #expect(
            Selection(current: .row("b")).reconciled(previous: items, current: after).current == .header(.needsReview))
    }

    @Test func removedRowSelectsThePrecedingRow() {
        let after: [InboxItemID] = [.header(.needsReview), .row("a"), .more(.needsReview)]
        #expect(Selection(current: .row("b")).reconciled(previous: items, current: after).current == .row("a"))
    }

    @Test func reconcileWithEmptyInboxClearsSelection() {
        #expect(Selection(current: .row("a")).reconciled(previous: items, current: []).current == nil)
    }

    @Test func unknownItemFallsBackToTheFirst() {
        #expect(
            Selection(current: .row("zzz")).reconciled(previous: [], current: items).current == .header(.needsReview))
    }
}
