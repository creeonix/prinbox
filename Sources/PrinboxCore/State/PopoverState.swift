import Foundation
import Observation

/// View model of the popover: selection, folding, settings mode and key handling. The SwiftUI views
/// read it directly; it contains no AppKit. Hooks let the app shell react (re-register the shortcut,
/// re-read the gh path) without the model knowing about AppKit.
@MainActor
@Observable
public final class PopoverState {
    public let store: InboxStore
    public let folds: FoldStore
    public let display: DisplaySettings
    public let colors: OrgColorStore
    public let opener: URLOpening
    public private(set) var selection = Selection()
    public private(set) var showingSettings = false
    public private(set) var isRecordingShortcut = false
    /// The setup command last copied, so its button can say "Copied".
    public var copiedCommand: String?
    /// Measured height of the list content, used to size the popover.
    public var contentHeight: CGFloat = 0

    /// Called when Settings opens, so the shell can re-read the gh path and the login-item status.
    @ObservationIgnored public var onSettingsOpened: (@MainActor () -> Void)?
    /// Called when a shortcut recording ends for any reason, so the shell re-registers the shortcut.
    @ObservationIgnored public var onRecordingEnded: (@MainActor () -> Void)?
    /// Called after a URL was handed to the opener, so the shell can close the popover.
    @ObservationIgnored public var onDidOpenURL: (@MainActor () -> Void)?
    @ObservationIgnored private var lastItems: [InboxItemID] = []

    public init(
        store: InboxStore, folds: FoldStore, display: DisplaySettings, colors: OrgColorStore,
        opener: URLOpening = NullURLOpener()
    ) {
        self.store = store
        self.folds = folds
        self.display = display
        self.colors = colors
        self.opener = opener
        lastItems = items
        store.onInboxChange = { [weak self] in self?.inboxDidChange() }
    }

    public var items: [InboxItemID] {
        InboxLayout.visibleItems(store.inbox ?? .empty, folded: folds.folded, grouped: display.groupByOrganization)
    }

    // MARK: Org cues

    private var spansMultipleOrgs: Bool { store.inbox?.spansMultipleOrgs ?? false }

    /// `org/repo` in row text: several orgs, and no separators saying which is which.
    public var showsOrgNames: Bool { spansMultipleOrgs && !display.groupByOrganization }

    public var showsOrgBadges: Bool { spansMultipleOrgs && display.showOrganizationAvatars }

    public var showsSeparators: Bool { spansMultipleOrgs && display.groupByOrganization }

    /// Compact rows outside Waiting on others carry the age, since the compact layout drops the meta line.
    public func showsCompactAge(_ kind: SectionKind) -> Bool { display.compactRows && !kind.usesCompactRows }

    public func setGroupByOrganization(_ on: Bool) {
        display.setGroupByOrganization(on)
        reconcileSelection()
    }

    public func setShowReviewed(_ on: Bool) {
        display.setShowReviewed(on)
        store.setShowReviewed(on)
        reconcileSelection()
    }

    // MARK: Opening

    /// Opens a PR, a section page or a help link through the adapter, then tells the shell.
    public func open(_ url: URL) {
        let opener = self.opener
        Task { await opener.open(url) }
        onDidOpenURL?()
    }

    // MARK: Selection

    public func isSelected(_ id: InboxItemID) -> Bool { selection.current == id }

    public func select(_ id: InboxItemID) { selection = Selection(current: id) }

    /// Follows the selected item through a change of the visible items.
    public func reconcileSelection() {
        let current = items
        selection = selection.reconciled(previous: lastItems, current: current)
        lastItems = current
    }

    private func inboxDidChange() {
        colors.assign((store.inbox?.sections ?? []).flatMap(\.rows).map(\.pullRequest.ownerLogin))
        reconcileSelection()
    }

    public func toggleFold(_ kind: SectionKind) {
        folds.toggle(kind)
        reconcileSelection()
    }

    // MARK: Snooze and new rows

    /// Snoozes through the store and keeps the selection at its position, so the next row is selected (the
    /// snoozed row moves to Waiting on others, which is folded by default), as when archiving mail.
    public func snooze(_ id: String) {
        keepingPosition { store.snooze(id) }
    }

    public func unsnooze(_ id: String) {
        keepingPosition { store.unsnooze(id) }
    }

    private func keepingPosition(_ change: () -> Void) {
        let index = selection.current.flatMap { items.firstIndex(of: $0) }
        change()
        let current = items
        guard let index, !current.isEmpty else { return }
        selection = Selection(current: current[min(index, current.count - 1)])
        lastItems = current
    }

    public func isNew(_ row: InboxRow) -> Bool { store.state.isNew(row.pullRequest) }

    /// Rows marked new in every section, folded or not; the header shows it.
    public var newCount: Int { allRows.filter(isNew).count }

    /// The popover closed: the rows it showed are now seen, and a recording in progress ends.
    public func popoverDidClose() {
        if isRecordingShortcut { stopRecording() }
        store.state.markSeen(allRows.map(\.pullRequest))
    }

    private var allRows: [InboxRow] { (store.inbox?.sections ?? []).flatMap(\.rows) }

    /// The store reconciles the selection through `onInboxChange`, including refreshes that start elsewhere.
    public func refresh() async {
        await store.refresh()
    }

    public func refreshIfStale() async {
        await store.refreshIfStale()
    }

    /// Resets transient state each time the popover opens and selects the first PR row.
    public func popoverWillShow() {
        store.reloadState()
        showingSettings = false
        if isRecordingShortcut { stopRecording() }
        copiedCommand = nil
        reconcileSelection()
        if selection.current == nil { selection = Selection(current: firstRow ?? items.first) }
    }

    // MARK: Settings and shortcut recording

    public func openSettings() {
        showingSettings = true
        onSettingsOpened?()
    }

    /// Leaving Settings by the back button or Esc also cancels a recording in progress.
    public func leaveSettings() {
        showingSettings = false
        if isRecordingShortcut { stopRecording() }
    }

    /// The shell unregisters the shortcut before calling this, or Carbon would swallow the new keys.
    public func startRecording() {
        isRecordingShortcut = true
    }

    public func stopRecording() {
        isRecordingShortcut = false
        onRecordingEnded?()
    }

    // MARK: Keys

    /// Activating a header folds it; a row or "more" row opens its URL.
    public func activate(_ id: InboxItemID) -> KeyAction {
        switch id {
        case .header(let kind):
            toggleFold(kind)
            return .handled
        case .row(let prID):
            return url(forRow: prID).map(KeyAction.open) ?? .handled
        case .more(let kind):
            return .open(moreURL(kind))
        }
    }

    /// The "+N more on GitHub" page of a section under the inbox's scope.
    public func moreURL(_ kind: SectionKind) -> URL { (store.inbox ?? .empty).moreURL(kind) }

    // MARK: Default repositories

    /// The menu over what the store knows and what is pinned (spec 4.2).
    public var repositoryPicker: RepositoryPicker {
        RepositoryPicker(known: store.knownRepositories, shape: store.shape)
    }

    public var defaultRepositories: [String] { store.shape.scope.repositories }

    public var hasDefaultRepositories: Bool { !defaultRepositories.isEmpty }

    /// The strip's label.
    public var defaultRepositoriesText: String { defaultRepositories.joined(separator: ", ") }

    /// Returns nil when the key is not for the popover, so the event continues to the view.
    public func handle(_ command: KeyCommand) -> KeyAction? {
        if showingSettings {
            guard command == .escape else { return nil }
            leaveSettings()
            return .handled
        }
        switch command {
        case .up:
            selection = selection.movingUp(in: items)
            return .handled
        case .down:
            selection = selection.movingDown(in: items)
            return .handled
        case .enter:
            return selection.current.map(activate) ?? .handled
        case .refresh:
            return .refresh
        case .snooze:
            // A Reviewed row has nothing to wait for, so it is never snoozed from here (ruling 12.10).
            if case .row(let id) = selection.current, !store.state.isSnoozed(id), section(forRow: id) != .reviewed {
                snooze(id)
            }
            return .handled
        case .unsnooze:
            if case .row(let id) = selection.current, store.state.isSnoozed(id) { unsnooze(id) }
            return .handled
        case .repositories:
            return .pickRepositories
        case .escape:
            return .close
        }
    }

    private var firstRow: InboxItemID? {
        items.first { item in
            if case .row = item { return true }
            return false
        }
    }

    private func url(forRow id: String) -> URL? {
        row(id)?.openURL
    }

    private func section(forRow id: String) -> SectionKind? {
        row(id)?.classification.section
    }

    private func row(_ id: String) -> InboxRow? {
        store.inbox?.sections.lazy.flatMap(\.rows).first { $0.id == id }
    }
}
