import AppKit
import PrinboxCore

/// The menu-bar item: pull-request symbol plus count, dimmed at zero, red with "!" on error.
/// Left click runs `onLeftClick`; right click shows a small fallback menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onLeftClick: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void
    private let onOpenUpdate: @MainActor () -> Void
    private var update: Release?

    init(
        onLeftClick: @escaping @MainActor () -> Void, onRefresh: @escaping @MainActor () -> Void,
        onOpenUpdate: @escaping @MainActor () -> Void
    ) {
        self.onLeftClick = onLeftClick
        self.onRefresh = onRefresh
        self.onOpenUpdate = onOpenUpdate
        super.init()
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render(.loading)
    }

    var anchor: NSView? { item.button }

    func render(_ badge: StatusBadge, update: Release? = nil) {
        guard let button = item.button else { return }
        self.update = update
        let suffix = update.map { " · PRInbox \($0.displayVersion) is available" } ?? ""
        switch badge {
        case .loading:
            show(button, title: "…", tint: nil, dimmed: true, tooltip: "PRInbox: loading" + suffix)
        case .count(let count):
            show(
                button, title: "\(count)", tint: nil, dimmed: false,
                tooltip: "PRInbox: \(count) waiting on you" + suffix)
        case .zero:
            show(button, title: "", tint: nil, dimmed: true, tooltip: "PRInbox: nothing waiting on you" + suffix)
        case .error(let message):
            show(button, title: "!", tint: .systemRed, dimmed: false, tooltip: "PRInbox: \(message)" + suffix)
        }
    }

    private func show(_ button: NSStatusBarButton, title: String, tint: NSColor?, dimmed: Bool, tooltip: String) {
        button.image = Self.symbol(tint: tint, badged: update != nil)
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        if let tint { attributes[.foregroundColor] = tint }
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " \(title)", attributes: attributes)
        button.appearsDisabled = dimmed
        button.toolTip = tooltip
    }

    /// The template symbol, with a small up-arrow badge while an update is pending. The red error
    /// state keeps its "!" and no badge: it is the more urgent of the two.
    private static func symbol(tint: NSColor?, badged: Bool) -> NSImage? {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRInbox")
        guard let tint else {
            let image = badged ? base.map(badge) : base
            image?.isTemplate = true
            return image
        }
        let tinted = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        tinted?.isTemplate = false
        return tinted
    }

    /// Composites `arrow.up.circle.fill` at 40% of the height onto the symbol's bottom-trailing corner.
    /// The canvas grows by half the badge so the badge hangs off the glyph instead of covering it, and a
    /// 1 pt ring is knocked out first so it stands off. Both are template shapes, so the result is a
    /// template image too.
    private static func badge(_ base: NSImage) -> NSImage {
        let side = (base.size.height * 0.4).rounded()
        let size = NSSize(width: base.size.width + side / 2, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            let frame = NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: frame.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil)?.draw(in: frame)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PRInbox, update available"
        return image
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
        if let update {
            let download = menu.addItem(
                withTitle: "Download PRInbox \(update.displayVersion)…",
                action: #selector(downloadChosen), keyEquivalent: "")
            download.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PRInbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func refreshChosen() { onRefresh() }

    @objc private func downloadChosen() { onOpenUpdate() }
}
