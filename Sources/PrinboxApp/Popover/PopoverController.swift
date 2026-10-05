import AppKit
import SwiftUI

/// Hosts the SwiftUI inbox in a transient NSPopover under the status item. Popovers have the
/// AXPopover role, so tiling window managers (OmniWM, AeroSpace, yabai) never manage them.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let keyMonitor: KeyMonitor
    private let onShow: @MainActor () -> Void
    private let onClose: @MainActor () -> Void
    private var resignObserver: NSObjectProtocol?

    init<Content: View>(
        rootView: Content, keyHandler: @escaping @MainActor (NSEvent) -> Bool,
        onShow: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void
    ) {
        keyMonitor = KeyMonitor(handler: keyHandler)
        self.onShow = onShow
        self.onClose = onClose
        super.init()
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo anchor: NSView) {
        if popover.isShown { close() } else { show(relativeTo: anchor) }
    }

    /// A dock-less app gets keystrokes only once it is active and the popover window is key.
    func show(relativeTo anchor: NSView) {
        onShow()
        // `activate()` only asks; the system granted it here no earlier than the user's first click inside the
        // popover, and that activation tore down the context menu the click had opened (the first right-click
        // lost its menu). The user clicked the status item, so activating regardless is what they asked for.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        // One level above pop-up menus, so bars that also use that level (OmniWM's workspace bar with
        // windowLevel = "popup") cannot cover the popover.
        window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window?.makeKey()
        keyMonitor.install()
        // `show` while shown would otherwise leak the earlier observer (no caller does this today).
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        // A click in another app while a row menu is tracking is consumed by the menu, so the transient popover
        // never sees a click outside; the app still resigns active, and that is the moment to close.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfShown() }
        }
    }

    func close() { popover.performClose(nil) }

    private func closeIfShown() {
        if popover.isShown { popover.performClose(nil) }
    }

    func popoverDidClose(_ notification: Notification) {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        keyMonitor.remove()
        onClose()
    }
}
