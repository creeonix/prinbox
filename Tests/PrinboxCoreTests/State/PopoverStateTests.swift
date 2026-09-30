import Foundation
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct PopoverStateTests {
    let a = makePR(id: "a", number: 1, reviewRequestedAt: date("2026-08-02T10:00:00Z"))
    let b = makePR(id: "b", number: 2, reviewRequestedAt: date("2026-08-03T10:00:00Z"))

    func makeState(
        folded: [SectionKind] = [], grouped: Bool = false, script: @escaping @Sendable (Int) async throws -> FetchResult
    ) async -> PopoverState {
        let defaults = MemoryDefaults()
        defaults.set(folded.map(\.rawValue), forKey: FoldStore.key)
        defaults.set(grouped, forKey: DisplaySettings.groupKey)
        let state = PopoverState(
            store: InboxStore(fetcher: ScriptedFetcher(script)), folds: FoldStore(defaults: defaults),
            display: DisplaySettings(defaults: defaults), colors: OrgColorStore(defaults: defaults))
        await state.refresh()
        return state
    }

    @Test func popoverOpensOnTheFirstRow() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.openSettings()
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

    @Test func popoverOpeningClearsTheCopiedMarker() async {
        let state = await makeState { _ in makeResult([]) }
        state.copiedCommand = "gh auth login"
        state.popoverWillShow()
        #expect(state.copiedCommand == nil)
    }

    @Test func escapeInSettingsReturnsToTheList() async {
        let state = await makeState { _ in makeResult([]) }
        state.openSettings()
        #expect(state.handle(.down) == nil)
        #expect(state.handle(.escape) == .handled)
        #expect(state.showingSettings == false)
    }

    @Test func openingSettingsFiresItsHook() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        let opened = Counter()
        state.onSettingsOpened = { opened.bump() }
        state.openSettings()
        #expect(state.showingSettings)
        #expect(opened.value == 1)
    }

    @Test func leavingSettingsCancelsARecordingInProgress() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        let ended = Counter()
        state.onRecordingEnded = { ended.bump() }
        state.openSettings()
        state.startRecording()
        #expect(state.isRecordingShortcut)
        state.leaveSettings()
        #expect(state.showingSettings == false)
        #expect(state.isRecordingShortcut == false)
        #expect(ended.value == 1)
        state.leaveSettings()
        #expect(ended.value == 1)
    }

    @Test func escapeLeavesSettingsAndShowingThePopoverEndsARecording() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        let ended = Counter()
        state.onRecordingEnded = { ended.bump() }
        state.openSettings()
        #expect(state.handle(.escape) == .handled)
        #expect(state.showingSettings == false)
        state.startRecording()
        state.popoverWillShow()
        #expect(state.isRecordingShortcut == false)
        #expect(ended.value == 1)
    }

    @Test func groupingChangesTheKeyboardOrderAndKeepsTheSelection() async {
        let prs = [
            makePR(id: "a", number: 1, repository: "acme/web", reviewRequestedAt: date("2026-08-01T10:00:00Z")),
            makePR(id: "g", number: 2, repository: "globex/billing", reviewRequestedAt: date("2026-08-02T10:00:00Z")),
            makePR(id: "b", number: 3, repository: "acme/api", reviewRequestedAt: date("2026-08-03T10:00:00Z")),
        ]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.row("g"))
        #expect(state.showsOrgNames)
        #expect(state.showsOrgBadges)
        #expect(state.showsSeparators == false)
        state.setGroupByOrganization(true)
        #expect(state.items == [.header(.needsReview), .row("a"), .row("b"), .row("g")])
        #expect(state.selection.current == .row("g"))
        #expect(state.showsOrgNames == false)
        #expect(state.showsSeparators)
        #expect(state.handle(.up) == .handled)
        #expect(state.selection.current == .row("b"))
    }

    @Test func singleOrgInboxShowsNoOrgCues() async {
        let prs = [a, b]
        let state = await makeState(grouped: true) { _ in makeResult(prs) }
        #expect(state.showsOrgNames == false)
        #expect(state.showsOrgBadges == false)
        #expect(state.showsSeparators == false)
    }

    @Test func refreshAssignsOrgColors() async {
        let prs = [
            makePR(id: "a", repository: "acme/web"),
            makePR(id: "g", repository: "globex/billing", source: .mine),
        ]
        let state = await makeState { _ in makeResult(prs) }
        #expect(state.colors.index(for: "acme") == 0)
        #expect(state.colors.index(for: "globex") == 1)
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
        let state = PopoverState(
            store: store, folds: FoldStore(defaults: defaults),
            display: DisplaySettings(defaults: defaults), colors: OrgColorStore(defaults: defaults))
        await store.refresh()
        state.select(.row("b"))
        await store.refresh()
        #expect(state.selection.current == .row("a"))
    }
}
