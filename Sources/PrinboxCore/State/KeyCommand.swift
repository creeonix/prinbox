import Foundation

/// Keys the popover understands.
public enum KeyCommand: Equatable, Sendable {
    case up
    case down
    case enter
    case refresh
    case escape

    /// Returns nil for keys the popover leaves alone. R counts only without ⌘, ⌃ or ⌥.
    public init?(keyCode: UInt16, characters: String?, modifiers: HotKeyModifiers) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .enter
        case 53: self = .escape
        default:
            guard modifiers.isDisjoint(with: [.command, .control, .option]), characters?.lowercased() == "r" else {
                return nil
            }
            self = .refresh
        }
    }
}

/// What the app should do after the popover handled a key or an activation.
public enum KeyAction: Equatable, Sendable {
    case handled
    case open(URL)
    case refresh
    case close
}
