import Testing

@testable import PrinboxCore

@MainActor
@Suite struct OrgColorStoreTests {
    @Test func firstSeenOrgsGetTheLowestFreeIndices() {
        let store = OrgColorStore(defaults: MemoryDefaults())
        store.assign(["acme", "globex"])
        store.assign(["initech", "acme"])
        #expect(store.index(for: "acme") == 0)
        #expect(store.index(for: "globex") == 1)
        #expect(store.index(for: "initech") == 2)
        #expect(store.index(for: "unknown") == 0)
    }

    @Test func pastThePaletteTheLeastUsedIndexIsReused() {
        let store = OrgColorStore(defaults: MemoryDefaults())
        store.assign((1...8).map { "org-\($0)" })
        store.assign(["org-9", "org-10"])
        #expect(store.index(for: "org-8") == 7)
        #expect(store.index(for: "org-9") == 0)
        #expect(store.index(for: "org-10") == 1)
    }

    @Test func assignmentsPersistAndReload() {
        let defaults = MemoryDefaults()
        OrgColorStore(defaults: defaults).assign(["globex", "acme"])
        let reloaded = OrgColorStore(defaults: defaults)
        #expect(reloaded.index(for: "globex") == 0)
        #expect(reloaded.index(for: "acme") == 1)
        reloaded.assign(["initech"])
        #expect(reloaded.index(for: "initech") == 2)
        #expect(defaults.object(forKey: OrgColorStore.key) as? [String: Int] == ["globex": 0, "acme": 1, "initech": 2])
    }

    @Test func assigningNothingNewDoesNotWrite() {
        let defaults = MemoryDefaults()
        let store = OrgColorStore(defaults: defaults)
        store.assign(["acme"])
        defaults.set(nil, forKey: OrgColorStore.key)
        store.assign(["acme"])
        #expect(defaults.object(forKey: OrgColorStore.key) == nil)
    }

    @Test func negativeSavedIndicesAreDropped() {
        let defaults = MemoryDefaults()
        defaults.set(["acme": -3, "globex": 1], forKey: OrgColorStore.key)
        let store = OrgColorStore(defaults: defaults)
        #expect(store.index(for: "acme") == 0)
        store.assign(["acme"])
        #expect(store.index(for: "acme") == 0)
        #expect(store.index(for: "globex") == 1)
    }
}
