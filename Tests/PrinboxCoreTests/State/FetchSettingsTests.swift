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
        defaults.set(["acme", "globex/billing"], forKey: SearchScope.repositoriesKey)
        let settings = FetchSettings(defaults: defaults)
        #expect(settings.scope == SearchScope(repositories: ["acme", "globex/billing"]))
        #expect(settings.repositoriesDraft == "acme, globex/billing")
        settings.setDirectReviewRequestsOnly(true)
        settings.setHideDrafts(true)
        #expect(settings.scope.directReviewRequestsOnly)
        #expect(settings.scope.hideDrafts)
        #expect(defaults.object(forKey: SearchScope.directKey) as? Bool == true)
        #expect(defaults.object(forKey: SearchScope.hideDraftsKey) as? Bool == true)
        #expect(
            FetchSettings(defaults: defaults).scope
                == SearchScope(
                    directReviewRequestsOnly: true, repositories: ["acme", "globex/billing"], hideDrafts: true))
    }

    @Test func commitNormalizesTheDraftAndWritesOnlyOnAChange() {
        let defaults = MemoryDefaults()
        let settings = FetchSettings(defaults: defaults)
        settings.repositoriesDraft = " acme,globex/billing  org:bad acme "
        #expect(settings.commitRepositories())
        #expect(settings.scope.repositories == ["acme", "globex/billing"])
        #expect(settings.repositoriesDraft == "acme, globex/billing")
        #expect(defaults.object(forKey: SearchScope.repositoriesKey) as? [String] == ["acme", "globex/billing"])
        settings.repositoriesDraft = "acme, globex/billing"
        #expect(settings.commitRepositories() == false)
        settings.repositoriesDraft = ""
        #expect(settings.commitRepositories())
        #expect(settings.scope.repositories == [])
        #expect(defaults.object(forKey: SearchScope.repositoriesKey) as? [String] == [])
    }
}
