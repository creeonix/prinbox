import AppKit
import PrinboxCore
import SwiftUI

/// A borderless AppKit button that pops the default-repositories menu up below itself. SwiftUI's `Menu` cannot be
/// opened by a key, and AppKit's checks, dims and section headers are what the picker needs (spec 4.2). With a
/// `symbol` it is the header's icon; with a `title` it is the strip's pull-down.
struct RepositoryMenuButton: NSViewRepresentable {
    let state: PopoverState
    let actions: PopoverActions
    var symbol: String? = nil
    var title: String? = nil
    let help: String
    var tint: NSColor? = nil
    /// Set by the header only: the anchor the `F` key clicks.
    var anchor: MenuAnchor? = nil

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.popUp(_:)))
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        anchor?.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
            button.symbolConfiguration = NSImage.SymbolConfiguration(scale: .medium)
            button.contentTintColor = tint
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.title = title ?? ""
            button.font = NSFont.systemFont(ofSize: 11)
            button.lineBreakMode = .byTruncatingMiddle
            button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            button.imagePosition = .imageTrailing
            button.contentTintColor = tint
        }
        button.toolTip = help
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RepositoryMenuButton
        private lazy var menu = RepositoryMenu { [weak self] entry in self?.parent.actions.toggleRepository(entry) }

        init(parent: RepositoryMenuButton) { self.parent = parent }

        /// Pops the menu below the button, whichever way the view's coordinates run.
        @objc func popUp(_ sender: NSButton) {
            let built = menu.menu(for: parent.state.repositoryPicker)
            let below = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 2 : sender.bounds.minY - 2)
            built.popUp(positioning: nil, at: below, in: sender)
        }
    }
}
