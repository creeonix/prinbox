import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.creeonix.prinbox"

    private let client: GhClient
    private let store: InboxStore
    private let state: PopoverState
    private let display: DisplaySettings
    private let colors: OrgColorStore
    private let hotKeys: HotKeySettings
    private let loginItem = LoginItem()
    private let avatars: AvatarImages
    private let info: AppInfo
    private let updates: UpdateStore
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?
    private var popover: PopoverController?
    private var hotKeyCenter: HotKeyCenter?
    private var closingForBrowser = false
    private let isDemo: Bool

    /// In demo mode the inbox comes from `DemoFetcher`, preferences live in a separate suite with every
    /// section open, and no global shortcut is registered, so a demo never touches the real setup.
    init(demo: Bool = false) {
        let defaults = demo ? Self.demoDefaults() : UserDefaults.standard
        let client = GhClient()
        let store = InboxStore(fetcher: demo ? DemoFetcher() : client)
        isDemo = demo
        self.client = client
        info = AppInfo(client: client)
        // Demo builds report "dev", so the store never checks there.
        updates = UpdateStore(
            currentVersion: demo ? "dev" : info.version, checker: GhReleaseChecker(locator: GhLocator()),
            defaults: defaults)
        self.store = store
        display = DisplaySettings(defaults: defaults)
        colors = OrgColorStore(defaults: defaults)
        state = PopoverState(store: store, folds: FoldStore(defaults: defaults), display: display, colors: colors)
        hotKeys = HotKeySettings(defaults: defaults)
        avatars = AvatarImages(cache: AvatarCache(directory: AvatarCache.defaultDirectory(bundleID: Self.bundleID)))
    }

    func start() {
        state.onRecordingEnded = { [weak self] in self?.applyHotKey() }
        state.onSettingsOpened = { [weak self] in
            self?.info.refresh()
            self?.loginItem.refresh()
        }
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.togglePopover() },
            onRefresh: { [weak self] in self?.refreshNow() },
            onOpenUpdate: { [weak self] in self?.openUpdate() })
        let root = InboxView(
            state: state, avatars: avatars, hotKeys: hotKeys, loginItem: loginItem,
            info: info, updates: updates, actions: makeActions())
        popover = PopoverController(
            rootView: root,
            keyHandler: { [weak self] event in self?.handleKey(event) ?? false },
            onShow: { [weak self] in self?.popoverWillShow() },
            onClose: { [weak self] in self?.popoverDidClose() })
        if !isDemo {
            hotKeyCenter = HotKeyCenter { [weak self] in self?.togglePopover() }
            applyHotKey()
        }
        observeBadge()
        triggers.start(
            { [weak self] in await self?.refreshAll() },
            retrySetup: { [weak self] in await self?.store.retryIfSetupNeeded() })
        refreshNow()
    }

    private static func demoDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "\(bundleID).demo") ?? .standard
        defaults.set([String](), forKey: FoldStore.key)
        return defaults
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            open: { [weak self] url in self?.open(url) },
            refresh: { [weak self] in self?.refreshNow() },
            quit: { NSApp.terminate(nil) },
            toggleShortcutRecording: { [weak self] in self?.toggleShortcutRecording() },
            setShortcut: { [weak self] spec in self?.setShortcut(spec) },
            setLaunchAtLogin: { [weak self] enabled in self?.loginItem.setEnabled(enabled) },
            copy: { [weak self] command in self?.copy(command) })
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        state.copiedCommand = command
    }

    private func togglePopover() {
        guard let anchor = statusItem?.anchor else { return }
        popover?.toggle(relativeTo: anchor)
    }

    private func popoverWillShow() {
        state.popoverWillShow()
        Task { await state.refreshIfStale() }
    }

    /// Closing mid-recording ends it; the hook re-registers the shortcut that recording suspended.
    /// Showing the popover activated prinbox; when it closes by Esc or the shortcut, hiding hands focus back
    /// to the previous app. A close for an opened PR leaves activation to the browser.
    private func popoverDidClose() {
        if state.isRecordingShortcut { state.stopRecording() }
        if !closingForBrowser && NSApp.isActive { NSApp.hide(nil) }
        closingForBrowser = false
    }

    private func refreshNow() {
        Task { await refreshAll() }
    }

    /// Every inbox refresh is also the moment to see whether a newer PRInbox exists (at most once a day).
    private func refreshAll() async {
        await state.refresh()
        await updates.checkIfDue()
    }

    private func openUpdate() {
        NSWorkspace.shared.open(
            updates.available?.url ?? URL(string: "https://github.com/creeonix/prinbox/releases/latest")!)
    }

    private func open(_ url: URL) {
        closingForBrowser = true
        NSWorkspace.shared.open(url)
        popover?.close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = HotKeyModifiers(event.modifierFlags)
        if state.isRecordingShortcut { return recordShortcut(keyCode: event.keyCode, modifiers: modifiers) }
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

    // MARK: Global shortcut

    /// While recording, the current shortcut is unregistered; otherwise Carbon would swallow it and it
    /// could never be re-recorded.
    private func toggleShortcutRecording() {
        if state.isRecordingShortcut {
            state.stopRecording()
        } else {
            hotKeyCenter?.unregister()
            state.startRecording()
        }
    }

    /// Esc cancels. Keys without ⌃, ⌥ or ⌘ are swallowed and recording continues.
    private func recordShortcut(keyCode: UInt16, modifiers: HotKeyModifiers) -> Bool {
        if keyCode == 53 {
            state.stopRecording()
            return true
        }
        guard let spec = HotKeySpec.recorded(keyCode: keyCode, modifiers: modifiers) else { return true }
        hotKeys.update(spec)
        state.stopRecording()
        return true
    }

    private func setShortcut(_ spec: HotKeySpec?) {
        hotKeys.update(spec)
        applyHotKey()
    }

    private func applyHotKey() {
        hotKeys.isUnavailable = !(hotKeyCenter?.register(hotKeys.spec) ?? false)
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge, update: updates.available)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
