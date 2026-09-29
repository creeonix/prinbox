import Foundation
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct PopoverStateTests {
    let a = makePR(id: "a", number: 1, reviewRequestedAt: date("2026-08-02T10:00:00Z"))
    let b = makePR(id: "b", number: 2, reviewRequestedAt: date("2026-08-03T10:00:00Z"))

    func makeState(
        folded: [SectionKind] = [], script: @escaping @Sendable (Int) async throws -> FetchResult
    ) async -> PopoverState {
        let defaults = MemoryDefaults()
        defaults.set(folded.map(\.rawValue), forKey: FoldStore.key)
        let state = PopoverState(
            store: InboxStore(fetcher: ScriptedFetcher(script)), folds: FoldStore(defaults: defaults))
        await state.refresh()
        return state
    }

    @Test func popoverOpensOnTheFirstRow() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.showingSettings = true
        state.popoverWillShow()
        #expect(state.selection.current == .row("a"))
        #expect(state.showingSettings == false)
    }

    @Test func arrowsMoveAndEnterOpensThePullRequest() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.popoverWillShow()
        #expect(state.handle(.down) == .handled)
        #expect(state.handle(.enter) == .open(b.url))
    }

    @Test func enterOnAHeaderTogglesTheFold() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.header(.needsReview))
        #expect(state.handle(.enter) == .handled)
        #expect(state.folds.isFolded(.needsReview))
        #expect(state.items == [.header(.needsReview)])
        #expect(state.selection.current == .header(.needsReview))
    }

    @Test func enterOnTheMoreRowOpensTheSearch() async {
        let prs = (1...9).map { makePR(id: "p\($0)", number: $0) }
        let state = await makeState { _ in makeResult(prs) }
        state.select(.more(.needsReview))
        #expect(state.handle(.enter) == .open(SectionKind.needsReview.moreURL))
    }

    @Test func foldingASectionMovesTheSelectionToItsHeader() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.row("b"))
        state.toggleFold(.needsReview)
        #expect(state.selection.current == .header(.needsReview))
    }

    @Test func refreshThatRemovesTheSelectedRowSelectsThePrecedingOne() async {
        let (first, second) = (a, b)
        let state = await makeState { call in makeResult(call == 1 ? [first, second] : [first]) }
        state.select(.row("b"))
        await state.refresh()
        #expect(state.selection.current == .row("a"))
    }

    @Test func refreshAndEscapeKeys() async {
        let state = await makeState { _ in makeResult([]) }
        #expect(state.handle(.refresh) == .refresh)
        #expect(state.handle(.escape) == .close)
    }

    @Test func escapeInSettingsReturnsToTheList() async {
        let state = await makeState { _ in makeResult([]) }
        state.showingSettings = true
        #expect(state.handle(.down) == nil)
        #expect(state.handle(.escape) == .handled)
        #expect(state.showingSettings == false)
    }
}

@MainActor
@Suite struct PopoverStateReconcileTests {
    let a = makePR(id: "a", number: 1, reviewRequestedAt: date("2026-08-02T10:00:00Z"))
    let b = makePR(id: "b", number: 2, reviewRequestedAt: date("2026-08-03T10:00:00Z"))

    @Test func refreshThroughTheStoreAlsoReconcilesTheSelection() async {
        let (first, second) = (a, b)
        let defaults = MemoryDefaults()
        defaults.set([String](), forKey: FoldStore.key)
        let store = InboxStore(fetcher: ScriptedFetcher { call in makeResult(call == 1 ? [first, second] : [first]) })
        let state = PopoverState(store: store, folds: FoldStore(defaults: defaults))
        await store.refresh()
        state.select(.row("b"))
        await store.refresh()
        #expect(state.selection.current == .row("a"))
    }
}
