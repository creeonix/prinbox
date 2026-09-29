import AppKit
import PrinboxCore

/// The menu-bar item: pull-request symbol plus count, dimmed at zero, red with "!" on error.
/// Left click runs `onLeftClick`; right click shows a small fallback menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onLeftClick: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void

    init(onLeftClick: @escaping @MainActor () -> Void, onRefresh: @escaping @MainActor () -> Void) {
        self.onLeftClick = onLeftClick
        self.onRefresh = onRefresh
        super.init()
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render(.loading)
    }

    var anchor: NSView? { item.button }

    func render(_ badge: StatusBadge) {
        guard let button = item.button else { return }
        switch badge {
        case .loading:
            show(button, title: "…", tint: nil, dimmed: true, tooltip: "PRInbox: loading")
        case .count(let count):
            show(button, title: "\(count)", tint: nil, dimmed: false, tooltip: "PRInbox: \(count) waiting on you")
        case .zero:
            show(button, title: "", tint: nil, dimmed: true, tooltip: "PRInbox: nothing waiting on you")
        case .error(let message):
            show(button, title: "!", tint: .systemRed, dimmed: false, tooltip: "PRInbox: \(message)")
        }
    }

    private func show(_ button: NSStatusBarButton, title: String, tint: NSColor?, dimmed: Bool, tooltip: String) {
        button.image = Self.symbol(tint: tint)
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        if let tint { attributes[.foregroundColor] = tint }
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " \(title)", attributes: attributes)
        button.appearsDisabled = dimmed
        button.toolTip = tooltip
    }

    private static func symbol(tint: NSColor?) -> NSImage? {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRInbox")
        guard let tint else {
            base?.isTemplate = true
            return base
        }
        let tinted = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        tinted?.isTemplate = false
        return tinted
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onLeftClick()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let refresh = menu.addItem(withTitle: "Refresh now", action: #selector(refreshChosen), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PRInbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func refreshChosen() { onRefresh() }
}
