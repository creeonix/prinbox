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

    @Test func compactRowsIsOffByDefaultAndPersists() {
        let defaults = MemoryDefaults()
        let settings = DisplaySettings(defaults: defaults)
        #expect(settings.compactRows == false)
        settings.setCompactRows(true)
        #expect(defaults.object(forKey: DisplaySettings.compactKey) as? Bool == true)
        #expect(DisplaySettings(defaults: defaults).compactRows == true)
    }

    @Test func theReviewSettingsDefaultToBackgroundColorTheSentenceAndNoReviewedSection() {
        let settings = DisplaySettings(defaults: MemoryDefaults())
        #expect(settings.rowColor == .background)
        #expect(settings.sinceReviewLine == true)
        #expect(settings.showReviewed == false)
        #expect(RowColor.allCases == [.plain, .background, .title])
        #expect(RowColor.plain.rawValue == "none")
    }

    @Test func theReviewSettingsPersistAndAnUnknownColorReadsAsTheDefault() {
        let defaults = MemoryDefaults()
        let settings = DisplaySettings(defaults: defaults)
        settings.setRowColor(.title)
        settings.setSinceReviewLine(false)
        settings.setShowReviewed(true)
        #expect(defaults.object(forKey: DisplaySettings.rowColorKey) as? String == "title")
        #expect(defaults.object(forKey: DisplaySettings.sinceReviewKey) as? Bool == false)
        #expect(defaults.object(forKey: DisplaySettings.showReviewedKey) as? Bool == true)
        let reloaded = DisplaySettings(defaults: defaults)
        #expect(reloaded.rowColor == .title && reloaded.sinceReviewLine == false && reloaded.showReviewed)
        defaults.set("neon", forKey: DisplaySettings.rowColorKey)
        #expect(DisplaySettings(defaults: defaults).rowColor == .background)
    }
}
