import Foundation
import Testing

@testable import PrinboxCore

/// Answers with one release, or throws when given none, and counts the calls.
actor ScriptedChecker: ReleaseChecking {
    private(set) var calls = 0
    private let release: Release?

    init(_ release: Release?) { self.release = release }

    func latestRelease() async throws -> Release {
        calls += 1
        guard let release else { throw FetchError.badResponse }
        return release
    }
}

@MainActor
@Suite struct UpdateStoreTests {
    let start = date("2026-08-10T12:00:00Z")
    let page = URL(string: "https://github.com/creeonix/prinbox/releases/tag/v0.3.0")!

    func makeStore(
        version: String = "0.2.0", release: Release?, defaults: MemoryDefaults = MemoryDefaults(),
        clock: TestClock? = nil
    ) -> (UpdateStore, ScriptedChecker) {
        let checker = ScriptedChecker(release)
        let clock = clock ?? TestClock(start)
        let store = UpdateStore(currentVersion: version, checker: checker, defaults: defaults, clock: { clock.now })
        return (store, checker)
    }

    @Test func devBuildsNeverCheck() async {
        let (store, checker) = makeStore(version: "dev", release: Release(tag: "v9.0.0", url: page))
        await store.checkIfDue()
        #expect(await checker.calls == 0)
        #expect(store.available == nil)
    }

    @Test func newerReleaseIsAvailableAndPersisted() async {
        let defaults = MemoryDefaults()
        let (store, _) = makeStore(release: Release(tag: "v0.3.0", url: page), defaults: defaults)
        await store.checkIfDue()
        #expect(store.available?.tag == "v0.3.0")
        let stored = defaults.object(forKey: UpdateStore.latestReleaseKey) as? [String: String]
        #expect(stored == ["tag": "v0.3.0", "url": page.absoluteString])
        #expect(defaults.object(forKey: UpdateStore.checkedAtKey) as? Date == start)
    }

    @Test func sameOrOlderReleaseIsNotAvailable() async {
        let (same, _) = makeStore(release: Release(tag: "v0.2.0", url: page))
        await same.checkIfDue()
        #expect(same.available == nil)
        let (older, _) = makeStore(release: Release(tag: "v0.1.0", url: page))
        await older.checkIfDue()
        #expect(older.available == nil)
        let (unparsable, _) = makeStore(release: Release(tag: "v0.3.0-beta", url: page))
        await unparsable.checkIfDue()
        #expect(unparsable.available == nil)
    }

    @Test func checksAtMostOncePerDay() async {
        let clock = TestClock(start)
        let (store, checker) = makeStore(release: Release(tag: "v0.3.0", url: page), clock: clock)
        await store.checkIfDue()
        await store.checkIfDue()
        #expect(await checker.calls == 1)
        clock.advance(UpdateStore.interval - 1)
        await store.checkIfDue()
        #expect(await checker.calls == 1)
        clock.advance(1)
        await store.checkIfDue()
        #expect(await checker.calls == 2)
    }

    @Test func aFailedCheckCountsAsAnAttempt() async {
        let (store, checker) = makeStore(release: nil)
        await store.checkIfDue()
        await store.checkIfDue()
        #expect(await checker.calls == 1)
        #expect(store.available == nil)
    }

    @Test func storedReleaseSurvivesRelaunch() async {
        let defaults = MemoryDefaults()
        defaults.set(["tag": "v0.3.0", "url": page.absoluteString], forKey: UpdateStore.latestReleaseKey)
        defaults.set(start, forKey: UpdateStore.checkedAtKey)
        let (store, checker) = makeStore(release: Release(tag: "v9.9.9", url: page), defaults: defaults)
        #expect(store.available?.tag == "v0.3.0")
        await store.checkIfDue()
        #expect(await checker.calls == 0)
        let (upToDate, _) = makeStore(version: "0.3.0", release: nil, defaults: defaults)
        #expect(upToDate.available == nil)
    }
}
