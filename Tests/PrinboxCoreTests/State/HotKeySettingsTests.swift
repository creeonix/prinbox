import Testing

@testable import PrinboxCore

@MainActor
@Suite struct HotKeySettingsTests {
    @Test func firstRunUsesTheDefault() {
        #expect(HotKeySettings(defaults: MemoryDefaults()).spec == .default)
    }

    @Test func clearingPersistsAsNoShortcut() {
        let defaults = MemoryDefaults()
        HotKeySettings(defaults: defaults).update(nil)
        #expect(HotKeySettings(defaults: defaults).spec == nil)
    }

    @Test func updatePersists() {
        let defaults = MemoryDefaults()
        let spec = HotKeySpec(keyCode: 15, modifiers: [.command, .option])
        HotKeySettings(defaults: defaults).update(spec)
        #expect(HotKeySettings(defaults: defaults).spec == spec)
    }

    @Test func malformedStoredValueMeansNoShortcut() {
        let defaults = MemoryDefaults()
        defaults.set([7], forKey: HotKeySettings.key)
        #expect(HotKeySettings(defaults: defaults).spec == nil)
    }
}
