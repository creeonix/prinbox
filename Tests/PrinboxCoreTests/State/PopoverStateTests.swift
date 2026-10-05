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

    @Test func sSnoozesTheSelectedRowAndKeepsThePosition() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.popoverWillShow()
        #expect(state.selection.current == .row("a"))
        #expect(state.handle(.snooze) == .handled)
        #expect(state.store.state.isSnoozed("a"))
        #expect(state.items == [.header(.needsReview), .row("b"), .header(.waitingOnOthers), .row("a")])
        #expect(state.selection.current == .row("b"))
    }

    @Test func uWakesTheSelectedSnoozedRowAndKeepsThePosition() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.popoverWillShow()
        _ = state.handle(.snooze)
        state.select(.row("a"))
        #expect(state.handle(.unsnooze) == .handled)
        #expect(!state.store.state.isSnoozed("a"))
        #expect(state.items == [.header(.needsReview), .row("a"), .row("b")])
        #expect(state.selection.current == .row("b"))
    }

    @Test func sOnASnoozedRowAndUOnAPlainRowDoNothing() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.popoverWillShow()
        #expect(state.handle(.unsnooze) == .handled)
        #expect(!state.store.state.isSnoozed("a"))
        #expect(state.selection.current == .row("a"))
        state.snooze("a")
        state.select(.row("a"))
        let before = state.items
        #expect(state.handle(.snooze) == .handled)
        #expect(state.items == before)
        #expect(state.selection.current == .row("a"))
    }

    @Test func sWithNoRowSelectedDoesNothingAndAFoldedTargetIsFine() async {
        let prs = [a]
        let state = await makeState(folded: [.waitingOnOthers]) { _ in makeResult(prs) }
        #expect(state.selection.current == nil)
        #expect(state.handle(.snooze) == .handled)
        #expect(!state.store.state.isSnoozed("a"))
        state.select(.header(.needsReview))
        #expect(state.handle(.snooze) == .handled)
        #expect(!state.store.state.isSnoozed("a"))
        #expect(state.selection.current == .header(.needsReview))
        state.select(.row("a"))
        #expect(state.handle(.snooze) == .handled)
        #expect(state.items == [.header(.waitingOnOthers)])
        #expect(state.selection.current == .header(.waitingOnOthers))
    }

    @Test func snoozeKeysAreIgnoredInSettings() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.row("a"))
        state.openSettings()
        #expect(state.handle(.snooze) == nil)
        #expect(state.handle(.unsnooze) == nil)
        #expect(!state.store.state.isSnoozed("a"))
    }

    @Test func newRowsAreCountedUntilThePopoverCloses() async {
        let old = date("2026-08-01T10:00:00Z")
        let newer = date("2026-08-02T10:00:00Z")
        let state = await makeState { call in
            call == 1
                ? makeResult([makePR(id: "a", number: 1, updatedAt: old)])
                : makeResult([
                    makePR(id: "a", number: 1, updatedAt: newer),
                    makePR(id: "b", number: 2, updatedAt: old, source: .mine),
                ])
        }
        #expect(state.newCount == 0)
        await state.refresh()
        let rows = state.store.inbox?.sections.flatMap(\.rows) ?? []
        #expect(rows.map { state.isNew($0) } == [true, true])
        #expect(state.newCount == 2)
        state.popoverWillShow()
        #expect(state.newCount == 2)
        state.popoverDidClose()
        #expect(state.newCount == 0)
        #expect(rows.allSatisfy { !state.isNew($0) })
    }

    @Test func closingThePopoverEndsARecording() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        let ended = Counter()
        state.onRecordingEnded = { ended.bump() }
        state.startRecording()
        state.popoverDidClose()
        #expect(!state.isRecordingShortcut)
        #expect(ended.value == 1)
    }

    @Test func compactAgeShowsOutsideWaitingOnOthersWhenCompactRowsIsOn() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        #expect(!state.showsCompactAge(.needsReview))
        state.display.setCompactRows(true)
        #expect(state.showsCompactAge(.needsReview))
        #expect(state.showsCompactAge(.yourPRs))
        #expect(!state.showsCompactAge(.waitingOnOthers))
    }

    @Test func snoozeKeepsThePositionWithGroupingOn() async {
        let prs = [
            makePR(id: "a1", number: 1, repository: "acme/web", reviewRequestedAt: date("2026-08-02T10:00:00Z")),
            makePR(id: "g", number: 2, repository: "globex/x", reviewRequestedAt: date("2026-08-03T10:00:00Z")),
            makePR(id: "a2", number: 3, repository: "acme/web", reviewRequestedAt: date("2026-08-04T10:00:00Z")),
        ]
        let state = await makeState(grouped: true) { _ in makeResult(prs) }
        #expect(state.items == [.header(.needsReview), .row("a1"), .row("a2"), .row("g")])
        state.select(.row("a2"))
        #expect(state.handle(.snooze) == .handled)
        #expect(state.items == [.header(.needsReview), .row("a1"), .row("g"), .header(.waitingOnOthers), .row("a2")])
        #expect(state.selection.current == .row("g"))
    }

    @Test func snoozeKeysIgnoreAMoreRow() async {
        let prs = (1...9).map { makePR(id: "p\($0)", number: $0) }
        let state = await makeState { _ in makeResult(prs) }
        state.select(.more(.needsReview))
        #expect(state.handle(.snooze) == .handled)
        #expect(state.handle(.unsnooze) == .handled)
        #expect(state.store.state.snoozedIDs.isEmpty)
        #expect(state.selection.current == .more(.needsReview))
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

    @Test func popoverWillShowPicksUpAnotherWritersSnooze() async throws {
        let persistence = MemoryStatePersistence()
        let prs = [a, b]
        let defaults = MemoryDefaults()
        let state = PopoverState(
            store: InboxStore(
                fetcher: ScriptedFetcher { _ in makeResult(prs) }, state: StateStore(persistence: persistence)),
            folds: FoldStore(defaults: defaults), display: DisplaySettings(defaults: defaults),
            colors: OrgColorStore(defaults: defaults))
        await state.refresh()
        try persistence.save(
            AppState(snoozed: ["a": SnoozeEntry(snoozedAt: date("2026-08-10T12:00:00Z"), updatedAt: a.updatedAt)]))
        state.popoverWillShow()
        #expect(state.store.inbox?.section(.waitingOnOthers)?.rows.first?.id == "a")
        #expect(state.store.inbox?.section(.needsReview)?.rows.map(\.id) == ["b"])
    }

    @Test func openGoesThroughTheAdapterAndCallsTheHook() async {
        let prs = [a]
        let opener = FakeOpener()
        let defaults = MemoryDefaults()
        let state = PopoverState(
            store: InboxStore(fetcher: ScriptedFetcher { _ in makeResult(prs) }), folds: FoldStore(defaults: defaults),
            display: DisplaySettings(defaults: defaults), colors: OrgColorStore(defaults: defaults), opener: opener)
        let counter = Counter()
        state.onDidOpenURL = { counter.bump() }
        state.open(a.url)
        #expect(counter.value == 1)
        var iterator = opener.stream.makeAsyncIterator()
        let opened = await iterator.next()
        #expect(opened == a.url)
    }
}
