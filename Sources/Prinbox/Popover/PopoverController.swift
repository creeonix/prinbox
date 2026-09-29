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
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        // One level above pop-up menus, so bars that also use that level (OmniWM's workspace bar with
        // windowLevel = "popup") cannot cover the popover.
        window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window?.makeKey()
        keyMonitor.install()
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        keyMonitor.remove()
        onClose()
    }
}
