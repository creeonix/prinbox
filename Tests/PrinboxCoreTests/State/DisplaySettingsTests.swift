import Testing

@testable import PrinboxCore

@MainActor
@Suite struct DisplaySettingsTests {
    @Test func defaultsAreGroupingOffAndBadgesOn() {
        let settings = DisplaySettings(defaults: MemoryDefaults())
        #expect(settings.groupByOrganization == false)
        #expect(settings.showOrganizationAvatars == true)
    }

    @Test func changesPersistAndReload() {
        let defaults = MemoryDefaults()
        let settings = DisplaySettings(defaults: defaults)
        settings.setGroupByOrganization(true)
        settings.setShowOrganizationAvatars(false)
        #expect(defaults.object(forKey: DisplaySettings.groupKey) as? Bool == true)
        let reloaded = DisplaySettings(defaults: defaults)
        #expect(reloaded.groupByOrganization == true)
        #expect(reloaded.showOrganizationAvatars == false)
    }
}
