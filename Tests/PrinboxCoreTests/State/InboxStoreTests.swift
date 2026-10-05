import Foundation
import Testing

@testable import PrinboxCore

@MainActor
final class StoreHolder {
    var store: InboxStore?
}

@MainActor
final class ReceivedRows {
    var ids: [String] = []
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

    @Test func aToggleDuringAFetchDoesNotLetItsFingerprintSkipTheFollowUp() async {
        let holder = StoreHolder()
        let prs = [makePR(id: "a")]
        let fetcher = ScriptedFetcher(outcomes: { call, _ in
            if call == 1, let store = await holder.store {
                await store.setIncludeConversation(false)
                await store.refresh()
            }
            return .result(makeResult(prs))
        })
        let store = InboxStore(fetcher: fetcher)
        holder.store = store
        await store.refresh()
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(requests[1].previous == nil)
        #expect(requests[1].includeConversation == false)
        await store.refresh()
        #expect(await fetcher.requests.last?.previous != nil)
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

    @Test func snoozeMovesTheRowAndUnsnoozeRestoresIt() async {
        let store = InboxStore(fetcher: ScriptedFetcher { _ in makeResult([makePR(id: "a"), makePR(id: "b")]) })
        let changes = Counter()
        await store.refresh()
        store.onInboxChange = { changes.bump() }
        store.snooze("a")
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.inbox?.section(.waitingOnOthers)?.rows.map(\.id) == ["a"])
        #expect(store.state.isSnoozed("a"))
        #expect(changes.value == 1)
        store.snooze("a")
        store.snooze("unknown")
        #expect(changes.value == 1)
        store.unsnooze("a")
        #expect(store.inbox?.badgeCount == 2)
        #expect(store.inbox?.section(.waitingOnOthers) == nil)
        store.unsnooze("a")
        #expect(changes.value == 2)
    }

    @Test func snoozesSurviveARefreshUntilThePullRequestChanges() async {
        let old = date("2026-08-01T10:00:00Z")
        let fetcher = ScriptedFetcher { call in
            makeResult([makePR(id: "a", updatedAt: call < 3 ? old : old.addingTimeInterval(60))])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        store.snooze("a")
        await store.refresh()
        #expect(store.inbox?.badgeCount == 0)
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(!store.state.isSnoozed("a"))
    }

    @Test func arrivalsAreThePullRequestsThatEnterAnAttentionSection() async {
        let old = date("2026-08-01T10:00:00Z")
        let newer = date("2026-08-02T10:00:00Z")
        let fetcher = ScriptedFetcher { call in
            switch call {
            case 1:
                makeResult([
                    makePR(id: "a", number: 1, updatedAt: old),
                    makePR(id: "d", number: 3, isDraft: true, updatedAt: old),
                ])
            case 2:
                makeResult([
                    makePR(id: "a", number: 1, updatedAt: newer), makePR(id: "b", number: 2, updatedAt: old),
                    makePR(id: "d", number: 3, isDraft: true, updatedAt: newer),
                    makePR(id: "m", number: 4, source: .mentions),
                ])
            default:
                makeResult([makePR(id: "a", number: 1, updatedAt: newer), makePR(id: "b", number: 2, updatedAt: old)])
            }
        }
        let store = InboxStore(fetcher: fetcher)
        let seen = Counter()
        store.onArrivals = { rows in
            seen.bump()
            #expect(rows.map(\.id) == ["b"])
        }
        await store.refresh()
        #expect(store.arrivals.isEmpty)
        #expect(seen.value == 0)
        await store.refresh()
        #expect(store.arrivals.map(\.id) == ["b"])
        #expect(seen.value == 1)
        await store.refresh()
        #expect(store.arrivals.isEmpty)
        #expect(seen.value == 1)
    }

    @Test func aSnoozedReviewRequestThatWakesArrivesAgain() async {
        let old = date("2026-08-01T10:00:00Z")
        let newer = date("2026-08-02T10:00:00Z")
        let fetcher = ScriptedFetcher { call in
            makeResult([makePR(id: "a", updatedAt: call < 3 ? old : newer)])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        store.snooze("a")
        await store.refresh()
        #expect(store.arrivals.isEmpty)
        await store.refresh()
        #expect(!store.state.isSnoozed("a"))
        #expect(store.arrivals.map(\.id) == ["a"])
    }

    @Test func snoozeClearsTheArrivals() async {
        let fetcher = ScriptedFetcher { call in
            call == 1 ? makeResult([]) : makeResult([makePR(id: "a")])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(store.arrivals.map(\.id) == ["a"])
        store.snooze("a")
        #expect(store.arrivals.isEmpty)
    }

    @Test func anInjectedStateStoreIsUsedForSnoozes() async {
        let memory = MemoryStatePersistence(AppState(snoozed: ["a": SnoozeEntry(snoozedAt: start, updatedAt: start)]))
        let store = InboxStore(
            fetcher: ScriptedFetcher { _ in makeResult([makePR(id: "a", updatedAt: start)]) },
            state: StateStore(persistence: memory))
        await store.refresh()
        #expect(store.inbox?.badgeCount == 0)
        #expect(memory.saved?.seen == ["a": start])
    }

    @Test func pullRequestsMissingFromAnIncompleteFetchDoNotArriveWhenTheyReturn() async {
        let old = date("2026-08-01T10:00:00Z")
        let fetcher = ScriptedFetcher { call in
            switch call {
            case 2:
                makeResult(
                    [makePR(id: "b", number: 2, updatedAt: old)],
                    warnings: ["acme requires SSO re-authorization: results incomplete"])
            case 3:
                makeResult([
                    makePR(id: "a", number: 1, updatedAt: old), makePR(id: "b", number: 2, updatedAt: old),
                    makePR(id: "c", number: 3, updatedAt: old),
                ])
            default:
                makeResult([makePR(id: "a", number: 1, updatedAt: old), makePR(id: "b", number: 2, updatedAt: old)])
            }
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(store.arrivals.isEmpty)
        await store.refresh()
        #expect(store.arrivals.map(\.id) == ["c"])
    }

    @Test func unchangedKeepsTheInboxAndRefreshesTheClock() async {
        let clock = TestClock(start)
        let prs = [makePR(id: "a")]
        let fetcher = ScriptedFetcher(outcomes: { call, _ in call == 1 ? .result(makeResult(prs)) : .unchanged })
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        let changes = Counter()
        store.onInboxChange = { changes.bump() }
        await store.refresh()
        clock.advance(300)
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.lastSuccess == start.addingTimeInterval(300))
        #expect(store.error == nil)
        #expect(changes.value == 1)
        #expect(store.arrivals.isEmpty)
        #expect(store.isRefreshing == false)
    }

    @Test func thePreviousFingerprintRidesAlongWhileTheLastFullFetchIsFresh() async {
        let clock = TestClock(start)
        let prs = [makePR(id: "a")]
        let fetcher = ScriptedFetcher(outcomes: { _, _ in .result(makeResult(prs)) })
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        clock.advance(300)
        await store.refresh()
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(requests[0].previous == nil)
        #expect(requests[1].previous == ["a": prs[0].updatedAt])
        let allFollowing = requests.allSatisfy(\.includeConversation)
        #expect(allFollowing)
    }

    @Test func firstFetchAndToggleAndCeilingForceAFullFetch() async {
        let clock = TestClock(start)
        let prs = [makePR(id: "a")]
        let fetcher = ScriptedFetcher(outcomes: { _, _ in .result(makeResult(prs)) })
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        store.setIncludeConversation(false)
        clock.advance(60)
        await store.refresh()
        clock.advance(60)
        await store.refresh()
        clock.advance(15 * 60)
        await store.refresh()
        let requests = await fetcher.requests
        #expect(requests.map { $0.previous == nil } == [true, true, false, true])
        #expect(requests.map(\.includeConversation) == [true, false, false, false])
        #expect(store.includeConversation == false)
        store.setIncludeConversation(false)
        clock.advance(60)
        await store.refresh()
        #expect(await fetcher.requests.last?.previous != nil)
    }

    @Test func unchangedClearsAnEarlierErrorAndExposesTheStatusLink() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher(outcomes: { call, _ in
            switch call {
            case 1: return .result(makeResult([]))
            case 2: throw FetchError.githubUnavailable(status: 502)
            default: return .unchanged
            }
        })
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        await store.refresh()
        #expect(store.error == .githubUnavailable(status: 502))
        #expect(store.warningLink == FetchError.statusPage)
        #expect(store.warningLines.first?.hasPrefix("GitHub is having trouble (HTTP 502), showing data from") == true)
        await store.refresh()
        #expect(store.error == nil)
        #expect(store.warningLink == nil)
    }

    @Test func arrivalsReachTheHandlerEvenWhenTheInboxHookSnoozes() async {
        let holder = StoreHolder()
        let received = ReceivedRows()
        let old = date("2026-08-01T10:00:00Z")
        let fetcher = ScriptedFetcher { call in
            call == 1
                ? makeResult([makePR(id: "a", updatedAt: old)])
                : makeResult([makePR(id: "a", updatedAt: old), makePR(id: "b", number: 2)])
        }
        let store = InboxStore(fetcher: fetcher)
        holder.store = store
        store.onInboxChange = { holder.store?.snooze("b") }
        store.onArrivals = { rows in received.ids = rows.map(\.id) }
        await store.refresh()
        await store.refresh()
        #expect(received.ids == ["b"])
        #expect(store.state.isSnoozed("b"))
    }

    @Test func anUnchangedCheckPicksUpAnotherWritersSnooze() async throws {
        let persistence = MemoryStatePersistence()
        let pr = makePR(id: "PR_1")
        let fetcher = ScriptedFetcher(outcomes: { call, _ in call == 1 ? .result(makeResult([pr])) : .unchanged })
        let store = InboxStore(fetcher: fetcher, state: StateStore(persistence: persistence))
        await store.refresh()
        #expect(store.inbox?.section(.needsReview)?.rows.count == 1)
        let entry = SnoozeEntry(snoozedAt: date("2026-08-10T12:00:00Z"), updatedAt: pr.updatedAt)
        try persistence.save(AppState(snoozed: ["PR_1": entry]))
        await store.refresh()
        #expect(store.inbox?.section(.needsReview) == nil)
        #expect(store.inbox?.section(.waitingOnOthers)?.rows.first?.classification.reason == .snoozed)
    }

    @Test func reloadStateRebuildsOnlyWhenTheSnoozesChanged() async throws {
        let persistence = MemoryStatePersistence()
        let pr = makePR(id: "PR_1")
        let store = InboxStore(
            fetcher: ScriptedFetcher { _ in makeResult([pr]) }, state: StateStore(persistence: persistence))
        let counter = Counter()
        await store.refresh()
        store.onInboxChange = { counter.bump() }
        store.reloadState()
        #expect(counter.value == 0)
        try persistence.save(AppState(snoozed: ["PR_1": SnoozeEntry(snoozedAt: start, updatedAt: pr.updatedAt)]))
        store.reloadState()
        #expect(counter.value == 1)
        #expect(store.inbox?.section(.waitingOnOthers)?.rows.first?.id == "PR_1")
    }

    func cached(
        fetchedAt: Date, checkedAt: Date? = nil, attention: [String]? = [], prs: [PullRequest],
        includeConversation: Bool = true
    ) -> InboxCache {
        InboxCache(
            fetchedAt: fetchedAt, checkedAt: checkedAt ?? fetchedAt, includeConversation: includeConversation,
            viewer: testViewer,
            fingerprint: Dictionary(prs.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { _, new in new }),
            attention: attention, result: makeResult(prs))
    }

    @Test func adoptCacheShowsTheRowsBeforeAnyFetch() {
        let clock = TestClock(start)
        let counter = Counter()
        let store = InboxStore(
            fetcher: ScriptedFetcher { _ in makeResult([]) },
            cache: MemoryCache(cached(fetchedAt: start - 60, prs: [makePR(id: "PR_1")])), clock: { clock.now })
        store.onInboxChange = { counter.bump() }
        store.adoptCache()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.lastSuccess == start - 60)
        #expect(counter.value == 1)
    }

    @Test func aFreshCachedFingerprintRidesAlongAndAStaleOneDoesNot() async {
        for (age, expected) in [(60.0, true), (16 * 60.0, false)] {
            let clock = TestClock(start)
            let fetcher = ScriptedFetcher { _ in makeResult([]) }
            let store = InboxStore(
                fetcher: fetcher, cache: MemoryCache(cached(fetchedAt: start - age, prs: [makePR(id: "PR_1")])),
                clock: { clock.now })
            store.adoptCache()
            await store.refresh()
            let request = await fetcher.requests.first
            #expect((request?.previous != nil) == expected)
            #expect(request?.previousViewer == (expected ? testViewer : nil))
        }
    }

    @Test func aCacheFromTheOtherShapeGivesRowsButNoFingerprintOrBaseline() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { _ in makeResult([makePR(id: "PR_1"), makePR(id: "PR_2")]) }
        let received = ReceivedRows()
        let store = InboxStore(
            fetcher: fetcher,
            cache: MemoryCache(
                cached(
                    fetchedAt: start - 60, attention: ["PR_1"], prs: [makePR(id: "PR_1")], includeConversation: false)),
            clock: { clock.now })
        store.onArrivals = { received.ids = $0.map(\.id) }
        store.adoptCache()
        #expect(store.inbox?.badgeCount == 1)
        await store.refresh()
        #expect(await fetcher.requests.first?.previous == nil)
        #expect(received.ids == [])
    }

    @Test func theFirstFetchNotifiesAgainstTheAdoptedBaseline() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { _ in makeResult([makePR(id: "PR_1"), makePR(id: "PR_2")]) }
        let received = ReceivedRows()
        let store = InboxStore(
            fetcher: fetcher,
            cache: MemoryCache(cached(fetchedAt: start - 60, attention: ["PR_1"], prs: [makePR(id: "PR_1")])),
            clock: { clock.now })
        store.onArrivals = { received.ids = $0.map(\.id) }
        store.adoptCache()
        await store.refresh()
        #expect(received.ids == ["PR_2"])
    }

    @Test func aFullFetchWritesTheCacheAndAnUnchangedCheckBumpsCheckedAt() async throws {
        let clock = TestClock(start)
        let memory = MemoryCache()
        let pr = makePR(id: "PR_1")
        let fetcher = ScriptedFetcher(outcomes: { call, _ in call == 1 ? .result(makeResult([pr])) : .unchanged })
        let store = InboxStore(fetcher: fetcher, cache: memory, clock: { clock.now })
        await store.refresh()
        let written = try #require(memory.saved)
        #expect(written.fetchedAt == start)
        #expect(written.checkedAt == start)
        #expect(written.includeConversation == true)
        #expect(written.viewer == testViewer)
        #expect(written.fingerprint == ["PR_1": pr.updatedAt])
        #expect(written.attention == ["PR_1"])
        #expect(written.result.pullRequests == [pr])
        clock.advance(300)
        await store.refresh()
        #expect(memory.saved?.checkedAt == start + 300)
        #expect(memory.saved?.fetchedAt == start)
        #expect(memory.writeCount == 2)
    }

    @Test func adoptCacheAnnouncesWhatAPollerFetchedWhileTheAppWasOff() async {
        let clock = TestClock(start)
        let memory = MemoryCache(
            cached(fetchedAt: start - 60, attention: ["PR_1"], prs: [makePR(id: "PR_1"), makePR(id: "PR_2")]))
        let fetcher = ScriptedFetcher(outcomes: { _, _ in .unchanged })
        let received = ReceivedRows()
        let store = InboxStore(fetcher: fetcher, cache: memory, clock: { clock.now })
        store.onArrivals = { received.ids += $0.map(\.id) }
        store.adoptCache()
        #expect(received.ids == ["PR_2"])
        #expect(memory.saved?.attention == ["PR_1", "PR_2"])
        await store.refresh()
        #expect(await fetcher.requests.first?.previous != nil)
        #expect(received.ids == ["PR_2"])
    }

    @Test func nothingIsAdoptedWithoutACache() {
        let store = InboxStore(fetcher: ScriptedFetcher { _ in makeResult([]) })
        store.adoptCache()
        #expect(store.inbox == nil)
        #expect(store.lastSuccess == nil)
    }

    @Test func setScopeClearsTheFingerprintAndTheBaselineAndRidesInTheRequest() async {
        let clock = TestClock(start)
        let scope = SearchScope(directReviewRequestsOnly: true, repositories: ["acme"])
        let pr1 = makePR(id: "PR_1")
        let pr2 = makePR(id: "PR_2")
        let fetcher = ScriptedFetcher(outcomes: { call, _ in .result(makeResult(call == 1 ? [pr1] : [pr1, pr2])) })
        let received = ReceivedRows()
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        store.onArrivals = { received.ids = $0.map(\.id) }
        await store.refresh()
        #expect(received.ids == [])
        store.setScope(scope)
        #expect(store.shape == FetchShape(includeConversation: true, scope: scope))
        #expect(store.includeConversation)
        store.setScope(scope)
        clock.advance(60)
        await store.refresh()
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(requests[1].previous == nil)
        #expect(requests[1].scope == scope)
        // The first fetch under a new shape is a quiet start: PR_2 is new to the view, not an arrival.
        #expect(received.ids == [])
        #expect(store.inbox?.badgeCount == 2)
    }

    @Test func anUnchangedBumpLeavesACacheOfAnotherShapeOrFingerprintAlone() async throws {
        let clock = TestClock(start)
        let memory = MemoryCache()
        let pr = makePR(id: "PR_1")
        let other = makePR(id: "PR_2")
        let fetcher = ScriptedFetcher(outcomes: { call, _ in call == 1 ? .result(makeResult([pr])) : .unchanged })
        let store = InboxStore(fetcher: fetcher, cache: memory, clock: { clock.now })
        await store.refresh()
        #expect(memory.writeCount == 1)
        // A server fetching under another scope replaced the cache meanwhile.
        memory.update { _ in
            InboxCache(
                fetchedAt: self.start + 10, checkedAt: self.start + 10, includeConversation: true,
                scope: SearchScope(hideDrafts: true), viewer: testViewer, fingerprint: ["PR_2": other.updatedAt],
                attention: nil, result: makeResult([other]))
        }
        clock.advance(300)
        await store.refresh()
        #expect(memory.saved?.checkedAt == start + 10)
        #expect(memory.writeCount == 2)
        // The same shape but a newer fingerprint is left alone too.
        memory.update { _ in
            InboxCache(
                fetchedAt: self.start + 300, checkedAt: self.start + 300, includeConversation: true, viewer: testViewer,
                fingerprint: ["PR_2": other.updatedAt], attention: nil, result: makeResult([other]))
        }
        clock.advance(60)
        await store.refresh()
        #expect(memory.saved?.checkedAt == start + 300)
        #expect(memory.writeCount == 3)
        #expect(store.lastSuccess == start + 360)
    }
}
