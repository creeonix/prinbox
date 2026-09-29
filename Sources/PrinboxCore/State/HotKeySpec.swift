import Foundation

public struct HotKeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)
}

/// A global shortcut: a virtual key code plus modifiers.
public struct HotKeySpec: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers

    /// ⌃⌥P, the same default as Pullover.
    public static let `default` = HotKeySpec(keyCode: 35, modifiers: [.control, .option])

    public init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A recorded shortcut must include ⌃, ⌥ or ⌘ so that ordinary typing can never trigger it.
    public static func recorded(keyCode: UInt16, modifiers: HotKeyModifiers) -> HotKeySpec? {
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        return HotKeySpec(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    /// "⌃⌥P": modifiers in macOS menu order, then the key name.
    public var displayString: String {
        let symbols: [(HotKeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + KeyNames.name(for: keyCode)
    }

    /// Carbon mask for RegisterEventHotKey: cmdKey 1<<8, shiftKey 1<<9, optionKey 1<<11, controlKey 1<<12.
    public var carbonModifiers: UInt32 {
        let masks: [(HotKeyModifiers, UInt32)] = [
            (.command, 1 << 8), (.shift, 1 << 9), (.option, 1 << 11), (.control, 1 << 12),
        ]
        return masks.filter { modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }
    }

    /// The user-defaults form: `[keyCode, modifiers]`.
    public var storedValue: [Int] { [Int(keyCode), modifiers.rawValue] }

    public init?(storedValue: [Int]) {
        guard storedValue.count == 2, let code = UInt32(exactly: storedValue[0]) else { return nil }
        self.init(keyCode: code, modifiers: HotKeyModifiers(rawValue: storedValue[1]))
    }
}

/// Names for ANSI virtual key codes (Carbon kVK_*).
enum KeyNames {
    static func name(for keyCode: UInt32) -> String { names[keyCode] ?? "Key \(keyCode)" }

    static let names: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
    ]
}
