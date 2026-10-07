import AppKit
import PrinboxCore

/// Builds the default-repositories menu from a `RepositoryPicker` (spec 4.2): a section header per owner, one item
/// per entry, checked when pinned or covered, disabled when covered or too long for GitHub's search. A click
/// toggles one entry through `toggle`; AppKit closes the menu.
@MainActor
final class RepositoryMenu: NSObject {
    private let toggle: @MainActor (String) -> Void

    init(toggle: @escaping @MainActor (String) -> Void) {
        self.toggle = toggle
    }

    func menu(for picker: RepositoryPicker) -> NSMenu {
        let menu = NSMenu(title: "Default repositories")
        menu.autoenablesItems = false
        for group in picker.groups {
            menu.addItem(NSMenuItem.sectionHeader(title: group.owner))
            for item in group.items {
                let menuItem = NSMenuItem(title: item.entry, action: #selector(didSelect(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.entry
                menuItem.state = item.isPinned || item.isCovered ? .on : .off
                menuItem.isEnabled = item.isEnabled
                if item.overflow > 0 { menuItem.toolTip = "Too long for GitHub search (\(item.overflow) over)" }
                menu.addItem(menuItem)
            }
        }
        if picker.groups.isEmpty {
            let empty = NSMenuItem(title: "No repositories known yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }

    @objc private func didSelect(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? String else { return }
        toggle(entry)
    }
}

/// The header button the `F` key clicks, so a key opens the same menu a click does (spec 4.4).
@MainActor
final class MenuAnchor {
    weak var button: NSButton?

    func popUp() { button?.performClick(nil) }
}
