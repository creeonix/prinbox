import Testing

@testable import PrinboxCore

@MainActor
@Suite struct FetchSettingsTests {
    @Test func followsReviewThreadsByDefault() {
        #expect(FetchSettings(defaults: MemoryDefaults()).followReviewThreads)
        #expect(FetchSettings.key == "followReviewThreads")
    }

    @Test func persistsTheChoice() {
        let defaults = MemoryDefaults()
        let settings = FetchSettings(defaults: defaults)
        settings.setFollowReviewThreads(false)
        #expect(settings.followReviewThreads == false)
        #expect(defaults.object(forKey: FetchSettings.key) as? Bool == false)
        #expect(FetchSettings(defaults: defaults).followReviewThreads == false)
    }

    @Test func aCorruptedValueMeansOn() {
        let defaults = MemoryDefaults()
        defaults.set("no", forKey: FetchSettings.key)
        #expect(FetchSettings(defaults: defaults).followReviewThreads)
    }
}
