import Foundation

/// Keys the popover understands.
public enum KeyCommand: Equatable, Sendable {
    case up
    case down
    case enter
    case refresh
    case snooze
    case unsnooze
    case repositories
    case escape

    /// Returns nil for keys the popover leaves alone. R, S, U and F count only without ⌘, ⌃ or ⌥.
    public init?(keyCode: UInt16, characters: String?, modifiers: HotKeyModifiers) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .enter
        case 53: self = .escape
        default:
            guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
            switch characters?.lowercased() {
            case "r": self = .refresh
            case "s": self = .snooze
            case "u": self = .unsnooze
            case "f": self = .repositories
            default: return nil
            }
        }
    }
}

/// What the app should do after the popover handled a key or an activation.
public enum KeyAction: Equatable, Sendable {
    case handled
    case open(URL)
    case refresh
    case close
    /// open the default-repositories menu (spec 4.4)
    case pickRepositories
}
