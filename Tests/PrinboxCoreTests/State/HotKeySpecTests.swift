import Testing

@testable import PrinboxCore

@Suite struct HotKeySpecTests {
    @Test func defaultIsControlOptionP() {
        #expect(HotKeySpec.default.displayString == "⌃⌥P")
        #expect(HotKeySpec.default.carbonModifiers == 4096 | 2048)
    }

    @Test func modifiersDisplayInMenuOrder() {
        let spec = HotKeySpec(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(spec.displayString == "⌃⌥⇧⌘A")
        #expect(spec.carbonModifiers == 256 | 512 | 2048 | 4096)
    }

    @Test func unknownKeysGetANumberedName() {
        #expect(HotKeySpec(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }

    @Test func recordingRequiresControlOptionOrCommand() {
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: [.shift]) == nil)
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: []) == nil)
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: [.option]) == HotKeySpec(keyCode: 35, modifiers: [.option]))
    }

    @Test func storedValueRoundTrips() {
        let spec = HotKeySpec(keyCode: 15, modifiers: [.command, .shift])
        #expect(HotKeySpec(storedValue: spec.storedValue) == spec)
        #expect(HotKeySpec(storedValue: []) == nil)
        #expect(HotKeySpec(storedValue: [1]) == nil)
    }

    @Test func storedShortcutWithoutControlOptionOrCommandIsRejected() {
        #expect(HotKeySpec(storedValue: [35, 0]) == nil)
        #expect(HotKeySpec(storedValue: [35, HotKeyModifiers.shift.rawValue]) == nil)
    }
}
