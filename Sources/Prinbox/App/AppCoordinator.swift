import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.creeonix.prinbox"

    private let store: InboxStore
    private let state: PopoverState
    private let avatars: AvatarImages
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?
    private var popover: PopoverController?

    init() {
        let store = InboxStore(fetcher: GhClient())
        self.store = store
        state = PopoverState(store: store, folds: FoldStore(defaults: UserDefaults.standard))
        avatars = AvatarImages(cache: AvatarCache(directory: AvatarCache.defaultDirectory(bundleID: Self.bundleID)))
    }

    func start() {
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.togglePopover() },
            onRefresh: { [weak self] in self?.refreshNow() })
        popover = PopoverController(
            rootView: InboxView(state: state, avatars: avatars, actions: makeActions()),
            keyHandler: { [weak self] event in self?.handleKey(event) ?? false },
            onShow: { [weak self] in self?.popoverWillShow() },
            onClose: {})
        observeBadge()
        triggers.start { [weak self] in await self?.state.refresh() }
        refreshNow()
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            open: { [weak self] url in self?.open(url) },
            refresh: { [weak self] in self?.refreshNow() },
            quit: { NSApp.terminate(nil) })
    }

    private func togglePopover() {
        guard let anchor = statusItem?.anchor else { return }
        popover?.toggle(relativeTo: anchor)
    }

    private func popoverWillShow() {
        state.popoverWillShow()
        Task { await state.refreshIfStale() }
    }

    private func refreshNow() {
        Task { await state.refresh() }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        popover?.close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = HotKeyModifiers(event.modifierFlags)
        guard
            let command = KeyCommand(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: modifiers),
            let action = state.handle(command)
        else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .handled: break
        case .open(let url): open(url)
        case .refresh: refreshNow()
        case .close: popover?.close()
        }
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
