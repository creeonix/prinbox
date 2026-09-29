import Foundation
import Observation

/// View model of the popover: selection, folding, settings mode and key handling. The SwiftUI views
/// read it directly; it contains no AppKit.
@MainActor
@Observable
public final class PopoverState {
    public let store: InboxStore
    public let folds: FoldStore
    public private(set) var selection = Selection()
    public var showingSettings = false
    public var isRecordingShortcut = false
    /// Measured height of the list content, used to size the popover.
    public var contentHeight: CGFloat = 0

    @ObservationIgnored private var lastItems: [InboxItemID] = []

    public init(store: InboxStore, folds: FoldStore) {
        self.store = store
        self.folds = folds
        lastItems = items
        store.onInboxChange = { [weak self] in self?.reconcileSelection() }
    }

    public var items: [InboxItemID] {
        InboxLayout.visibleItems(store.inbox ?? .empty, folded: folds.folded)
    }

    public func isSelected(_ id: InboxItemID) -> Bool { selection.current == id }

    public func select(_ id: InboxItemID) { selection = Selection(current: id) }

    /// Follows the selected item through a change of the visible items.
    public func reconcileSelection() {
        let current = items
        selection = selection.reconciled(previous: lastItems, current: current)
        lastItems = current
    }

    public func toggleFold(_ kind: SectionKind) {
        folds.toggle(kind)
        reconcileSelection()
    }

    /// The store reconciles the selection through `onInboxChange`, including refreshes that start elsewhere.
    public func refresh() async {
        await store.refresh()
    }

    public func refreshIfStale() async {
        await store.refreshIfStale()
    }

    /// Resets transient state each time the popover opens and selects the first PR row.
    public func popoverWillShow() {
        showingSettings = false
        isRecordingShortcut = false
        reconcileSelection()
        if selection.current == nil { selection = Selection(current: firstRow ?? items.first) }
    }

    /// Activating a header folds it; a row or "more" row opens its URL.
    public func activate(_ id: InboxItemID) -> KeyAction {
        switch id {
        case .header(let kind):
            toggleFold(kind)
            return .handled
        case .row(let prID):
            return url(forRow: prID).map(KeyAction.open) ?? .handled
        case .more(let kind):
            return .open(kind.moreURL)
        }
    }

    /// Returns nil when the key is not for the popover, so the event continues to the view.
    public func handle(_ command: KeyCommand) -> KeyAction? {
        if showingSettings {
            guard command == .escape else { return nil }
            showingSettings = false
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
        store.inbox?.sections.lazy.flatMap(\.rows).first { $0.id == id }?.pullRequest.url
    }
}
