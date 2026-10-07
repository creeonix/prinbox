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

    @Test func theScopeStartsFromTheStoreAndWritesOneKeyPerChange() {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: SearchScope.directKey)
        let settings = FetchSettings(defaults: defaults)
        #expect(settings.scope == SearchScope(directReviewRequestsOnly: true))
        settings.setDirectReviewRequestsOnly(false)
        #expect(defaults.object(forKey: SearchScope.directKey) as? Bool == false)
        settings.setDirectReviewRequestsOnly(true)
        settings.setHideDrafts(true)
        #expect(settings.scope.directReviewRequestsOnly)
        #expect(settings.scope.hideDrafts)
        #expect(defaults.object(forKey: SearchScope.directKey) as? Bool == true)
        #expect(defaults.object(forKey: SearchScope.hideDraftsKey) as? Bool == true)
        #expect(
            FetchSettings(defaults: defaults).scope == SearchScope(directReviewRequestsOnly: true, hideDrafts: true))
    }

    @Test func setRepositoriesNormalizesAndWritesTheKey() {
        let defaults = MemoryDefaults()
        defaults.set(["acme", "org:bad"], forKey: SearchScope.repositoriesKey)
        let logger = MemoryLogging()
        let settings = FetchSettings(defaults: defaults, logger: logger)
        #expect(settings.scope == SearchScope(repositories: ["acme/*"]))
        #expect(logger.messages(.notice) == ["default repositories: ignored 1 invalid entry"])
        settings.setRepositories(["globex/billing", "acme/*", "acme/web"])
        #expect(settings.scope.repositories == ["acme/*", "globex/billing"])
        #expect(defaults.object(forKey: SearchScope.repositoriesKey) as? [String] == ["acme/*", "globex/billing"])
        settings.setRepositories([])
        #expect(settings.scope.isEmpty)
        #expect(defaults.object(forKey: SearchScope.repositoriesKey) as? [String] == [])
        #expect(FetchSettings(defaults: defaults).scope == .none)
    }
}
