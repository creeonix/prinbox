import Foundation
import Testing

@testable import PrinboxCore

@MainActor
final class StoreHolder {
    var store: InboxStore?
}

@MainActor
@Suite struct InboxStoreTests {
    let start = date("2026-08-10T12:00:00Z")

    @Test func successfulRefreshBuildsTheInbox() async {
        let clock = TestClock(start)
        let store = InboxStore(fetcher: ScriptedFetcher { _ in makeResult([makePR()]) }, clock: { clock.now })
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.error == nil)
        #expect(store.lastSuccess == start)
        #expect(store.badge == .count(1))
        #expect(store.isRefreshing == false)
    }

    @Test func failedRefreshKeepsTheLastInbox() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { return makeResult([makePR()]) }
            throw FetchError.offline
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.error == .offline)
        #expect(store.badge == .error(FetchError.offline.message(lastSuccess: store.lastSuccess)))
    }

    @Test func successAfterFailureClearsTheError() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.loggedOut }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        #expect(store.error == .loggedOut)
        await store.refresh()
        #expect(store.error == nil)
        #expect(store.badge == .zero)
    }

    @Test func refreshRequestedDuringAFetchRunsExactlyOnceMore() async {
        let holder = StoreHolder()
        let fetcher = ScriptedFetcher { call in
            if call == 1, let store = await holder.store {
                await store.refresh()
                await store.refresh()
            }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher)
        holder.store = store
        await store.refresh()
        #expect(await fetcher.calls == 2)
        #expect(store.isRefreshing == false)
    }

    @Test func rateLimitPausesRefreshesUntilReset() async {
        let clock = TestClock(start)
        let reset = start.addingTimeInterval(600)
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.rateLimited(resetAt: reset) }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        clock.advance(300)
        await store.refresh()
        #expect(await fetcher.calls == 1)
        #expect(store.error == .rateLimited(resetAt: reset))
        clock.advance(301)
        await store.refresh()
        #expect(await fetcher.calls == 2)
        #expect(store.error == nil)
    }

    @Test func rateLimitWithoutResetPausesFifteenMinutes() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.rateLimited(resetAt: nil) }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        clock.advance(14 * 60)
        await store.refresh()
        #expect(await fetcher.calls == 1)
        clock.advance(61)
        await store.refresh()
        #expect(await fetcher.calls == 2)
    }

    @Test func refreshIfStaleOnlyFetchesOldData() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { _ in makeResult([]) }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refreshIfStale()
        #expect(await fetcher.calls == 1)
        clock.advance(30)
        await store.refreshIfStale()
        #expect(await fetcher.calls == 1)
        clock.advance(31)
        await store.refreshIfStale()
        #expect(await fetcher.calls == 2)
    }

    @Test func unexpectedErrorsBecomeOther() async {
        let store = InboxStore(fetcher: ScriptedFetcher { _ in throw CancellationError() })
        await store.refresh()
        guard case .other = store.error else {
            Issue.record("expected .other, got \(String(describing: store.error))")
            return
        }
    }

    @Test func setupErrorsAreNotRepeatedInTheWarningLines() async {
        let store = InboxStore(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut })
        await store.refresh()
        #expect(store.needsSetup)
        #expect(store.warningLines == [])
    }

    @Test func retryIfSetupNeededOnlyFetchesWhileSetupIsNeeded() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.ghNotFound }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.retryIfSetupNeeded()
        #expect(await fetcher.calls == 0)
        await store.refresh()
        await store.retryIfSetupNeeded()
        #expect(await fetcher.calls == 2)
        #expect(store.needsSetup == false)
        await store.retryIfSetupNeeded()
        #expect(await fetcher.calls == 2)
    }

    @Test func warningLinesPutTheErrorFirst() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 {
                return makeResult([], warnings: ["acme restricts gh (OAuth app access): results incomplete"])
            }
            throw FetchError.offline
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(
            store.warningLines == [
                FetchError.offline.message(lastSuccess: store.lastSuccess),
                "acme restricts gh (OAuth app access): results incomplete",
            ])
    }
}
