import Testing

@testable import PrinboxCore

@Suite struct KeyCommandTests {
    func command(_ code: UInt16, _ chars: String? = nil, _ mods: HotKeyModifiers = []) -> KeyCommand? {
        KeyCommand(keyCode: code, characters: chars, modifiers: mods)
    }

    @Test func navigationKeys() {
        #expect(command(126) == .up)
        #expect(command(125) == .down)
        #expect(command(36) == .enter)
        #expect(command(76) == .enter)
        #expect(command(53) == .escape)
    }

    @Test func plainRRefreshes() {
        #expect(command(15, "r") == .refresh)
        #expect(command(15, "R", [.shift]) == .refresh)
    }

    @Test func modifiedROrOtherKeysAreIgnored() {
        #expect(command(15, "r", [.command]) == nil)
        #expect(command(0, "a") == nil)
    }
}
