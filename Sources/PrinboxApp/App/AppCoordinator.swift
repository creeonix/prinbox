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
    private let hotKeys: HotKeySettings
    private let notifications: NotificationSettings
    private let fetchSettings: FetchSettings
    private let notifier = Notifier()
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

    /// In demo mode the inbox comes from `DemoFetcher`, settings live in memory with every section open, the
    /// state (one snooze, four new rows) stays in memory, and no global shortcut is registered, so a demo never
    /// touches the real setup. `settingsPath` names an explicit settings file (the screenshot harness).
    init(demo: Bool = false, settingsPath: String? = nil) {
        let logger = OSLogging()
        let directories = MacDirectories()
        let settings: KeyValueStoring
        if let settingsPath {
            settings = JSONKeyValueFile(url: URL(fileURLWithPath: settingsPath), logger: logger)
        } else if demo {
            settings = MemoryKeyValueStore(initial: [FoldStore.key: [String]()])
        } else {
            let file = JSONKeyValueFile(url: directories.config.appendingPathComponent("settings.json"), logger: logger)
            let moved = SettingsMigration.migrate(from: UserDefaults.standard, to: file)
            if !moved.isEmpty { logger.notice(.state, "moved \(moved.count) settings from defaults to settings.json") }
            settings = file
        }
        let updateState: KeyValueStoring =
            demo
            ? MemoryKeyValueStore()
            : JSONKeyValueFile(url: directories.state.appendingPathComponent("update.json"), logger: logger)
        let locator = GhLocator(overridePath: settings.object(forKey: GhLocator.overrideKey) as? String)
        let client = GhClient(locator: locator, logger: logger)
        let fetcher: InboxFetching
        let persistence: StatePersisting
        if demo {
            let demoFetcher = DemoFetcher()
            fetcher = demoFetcher
            persistence = MemoryStatePersistence(demoFetcher.initialState)
        } else {
            fetcher = client
            persistence = JSONStateFile(url: JSONStateFile.url(in: directories))
        }
        let lock = demo ? nil : FileLock(url: directories.state.appendingPathComponent("prinbox.lock"), logger: logger)
        let store = InboxStore(
            fetcher: fetcher, state: StateStore(persistence: persistence, lock: lock, logger: logger),
            cache: demo
                ? MemoryCache()
                : JSONCacheFile(url: directories.state.appendingPathComponent("cache.json"), lock: lock, logger: logger)
        )
        isDemo = demo
        self.client = client
        info = AppInfo(client: client)
        // Demo builds report "dev", so the store never checks there.
        updates = UpdateStore(
            currentVersion: demo ? "dev" : info.version, checker: GhReleaseChecker(locator: locator),
            defaults: updateState)
        self.store = store
        let display = DisplaySettings(defaults: settings)
        let colors = OrgColorStore(defaults: settings)
        state = PopoverState(
            store: store, folds: FoldStore(defaults: settings), display: display, colors: colors,
            opener: WorkspaceURLOpener())
        hotKeys = HotKeySettings(defaults: settings)
        notifications = NotificationSettings(defaults: settings)
        fetchSettings = FetchSettings(defaults: settings)
        store.setIncludeConversation(fetchSettings.followReviewThreads)
        avatars = AvatarImages(cache: AvatarCache(directory: AvatarCache.directory(in: directories)))
    }

    func start() {
        state.onRecordingEnded = { [weak self] in self?.applyHotKey() }
        state.onSettingsOpened = { [weak self] in
            self?.info.refresh()
            self?.loginItem.refresh()
            Task { await self?.notifier.refresh() }
        }
        state.onDidOpenURL = { [weak self] in
            guard let self, self.popover?.isShown == true else { return }
            self.closingForBrowser = true
            self.popover?.close()
        }
        notifier.onOpen = { [weak self] url in
            if let url { self?.state.open(url) } else { self?.showPopover() }
        }
        notifier.start()
        store.onArrivals = { [weak self] rows in self?.notify(rows) }
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.togglePopover() },
            onRefresh: { [weak self] in self?.refreshNow() },
            onOpenUpdate: { [weak self] in self?.openUpdate() })
        let root = InboxView(
            state: state, avatars: avatars, hotKeys: hotKeys, loginItem: loginItem,
            info: info, updates: updates, notifications: notifications, fetchSettings: fetchSettings,
            notifier: notifier, actions: makeActions())
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
        store.adoptCache()
        refreshNow()
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            open: { [weak self] url in self?.open(url) },
            refresh: { [weak self] in self?.refreshNow() },
            quit: { [weak self] in
                self?.state.popoverDidClose()
                NSApp.terminate(nil)
            },
            toggleShortcutRecording: { [weak self] in self?.toggleShortcutRecording() },
            setShortcut: { [weak self] spec in self?.setShortcut(spec) },
            setLaunchAtLogin: { [weak self] enabled in self?.loginItem.setEnabled(enabled) },
            copy: { [weak self] command in self?.copy(command) },
            snooze: { [weak self] id in self?.state.snooze(id) },
            unsnooze: { [weak self] id in self?.state.unsnooze(id) },
            copyLink: { [weak self] url in self?.copyToPasteboard(url.absoluteString) },
            setNotifications: { [weak self] enabled in self?.setNotifications(enabled) },
            setFollowReviewThreads: { [weak self] on in self?.setFollowReviewThreads(on) })
    }

    private func copy(_ command: String) {
        copyToPasteboard(command)
        state.copiedCommand = command
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func togglePopover() {
        guard let anchor = statusItem?.anchor else { return }
        popover?.toggle(relativeTo: anchor)
    }

    private func popoverWillShow() {
        state.popoverWillShow()
        Task {
            await state.refreshIfStale()
            await updates.checkIfDue()
        }
    }

    /// Closing marks the rows shown as seen and ends a recording in progress (the hook re-registers the
    /// shortcut that recording suspended). Showing the popover activated prinbox; when it closes by Esc or
    /// the shortcut, hiding hands focus back to the previous app. A close for an opened PR leaves activation
    /// to the browser.
    private func popoverDidClose() {
        state.popoverDidClose()
        if !closingForBrowser && NSApp.isActive { NSApp.hide(nil) }
        closingForBrowser = false
    }

    /// One banner per refresh, only while the popover is closed: an open popover already shows the marks.
    /// The permission is re-read each time, so one granted later in System Settings takes effect at once.
    private func notify(_ rows: [InboxRow]) {
        guard notifications.isEnabled, !(popover?.isShown ?? false), let notice = ArrivalNotice.make(rows) else {
            return
        }
        Task {
            await notifier.refresh()
            // The popover may have opened during the round-trip.
            guard notifier.status == .authorized, !(self.popover?.isShown ?? false) else { return }
            await notifier.deliver(notice)
        }
    }

    private func showPopover() {
        guard let anchor = statusItem?.anchor, let popover, !popover.isShown else { return }
        popover.show(relativeTo: anchor)
    }

    /// Turning the setting on asks macOS; a refusal keeps the setting on and Settings shows what to fix.
    private func setNotifications(_ enabled: Bool) {
        notifications.setEnabled(enabled)
        // A refusal is not an error here: refresh() surfaces the status as the Settings note.
        if enabled { Task { await notifier.requestAuthorization() } }
    }

    /// The switch changes what a refresh asks for, so the next refresh is a full one, at once.
    private func setFollowReviewThreads(_ on: Bool) {
        fetchSettings.setFollowReviewThreads(on)
        store.setIncludeConversation(on)
        refreshNow()
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
        state.open(updates.available?.url ?? GhReleaseChecker.releasesPage)
    }

    private func open(_ url: URL) {
        state.open(url)
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
