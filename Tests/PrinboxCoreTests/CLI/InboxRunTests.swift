import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxRunTests {
    let start = date("2026-08-10T12:00:00Z")
    let pr1 = makePR(id: "PR_1", number: 1, reviewRequestedAt: date("2026-08-10T08:00:00Z"))
    let pr2 = makePR(id: "PR_2", number: 2, reviewRequestedAt: date("2026-08-10T09:00:00Z"))

    func cached(
        _ prs: [PullRequest], fetchedAt: Date? = nil, checkedAt: Date? = nil, attention: [String]? = nil,
        includeConversation: Bool = true
    ) -> InboxCache {
        let fetched = fetchedAt ?? start - 60
        return InboxCache(
            fetchedAt: fetched, checkedAt: checkedAt ?? fetched, includeConversation: includeConversation,
            viewer: testViewer,
            fingerprint: Dictionary(prs.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { _, new in new }),
            attention: attention, result: makeResult(prs))
    }

    @Test func aFetchWritesTheCacheWithoutABaseline() async {
        let cache = MemoryCache()
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let outcome = await InboxRun(context: makeContext(fetcher: fetcher, cache: cache)).inbox(InboxOptions())
        #expect(outcome.exitCode == 0)
        #expect(outcome.stderr == [])
        #expect(outcome.document.source == "fetch")
        #expect(outcome.document.fetchedAt == start)
        #expect(outcome.document.badge == 1)
        #expect(cache.saved?.attention == nil)
        #expect(cache.saved?.fingerprint == ["PR_1": pr1.updatedAt])
        #expect(cache.saved?.includeConversation == true)
        #expect(await fetcher.requests.first?.previous == nil)
    }

    @Test func notifyOnAFreshCacheDeliversNothingAndWritesTheBaseline() async {
        let cache = MemoryCache()
        let delivery = FakeDelivery()
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1]) }, cache: cache, delivery: delivery)
        _ = await InboxRun(context: context).inbox(InboxOptions(notify: true))
        #expect(delivery.notices.isEmpty)
        #expect(cache.saved?.attention == ["PR_1"])
    }

    @Test func notifyAfterAnEntryDeliversOneNoticeAndAdvances() async {
        let cache = MemoryCache(cached([pr1], attention: ["PR_1"]))
        let delivery = FakeDelivery()
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1, self.pr2]) }, cache: cache, delivery: delivery)
        _ = await InboxRun(context: context).inbox(InboxOptions(notify: true))
        #expect(delivery.notices.map(\.title) == ["#2 Add feature"])
        #expect(cache.saved?.attention == ["PR_1", "PR_2"])
    }

    @Test func aNonNotifierDropsTheBaselineWhenTheRequestShapeChanges() async {
        let cache = MemoryCache(cached([pr1], attention: ["PR_1"], includeConversation: false))
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let context = makeContext(fetcher: fetcher, cache: cache, followReviewThreads: true)
        _ = await InboxRun(context: context).inbox(InboxOptions())
        #expect(cache.saved?.includeConversation == true)
        #expect(cache.saved?.attention == nil)
    }

    /// Answers `.unchanged` only when the request's fingerprint matches `current`, as GitHub would.
    func github(_ current: FetchResult) -> ScriptedFetcher {
        ScriptedFetcher(outcomes: { _, request in
            request.previous == current.fingerprint ? .unchanged : .result(current)
        })
    }

    @Test func aPollerBetweenTwoNotifyRunsDoesNotEatTheArrival() async {
        let cache = MemoryCache(cached([pr1], attention: ["PR_1"]))
        let delivery = FakeDelivery()
        let context = makeContext(fetcher: github(makeResult([pr1, pr2])), cache: cache, delivery: delivery)
        _ = await InboxRun(context: context).inbox(InboxOptions(format: .tmux))
        #expect(cache.saved?.attention == ["PR_1"])
        #expect(cache.saved?.result.pullRequests.count == 2)
        let notified = await InboxRun(context: context).inbox(InboxOptions(notify: true))
        #expect(notified.document.source == "unchanged")
        #expect(delivery.notices.count == 1)
        #expect(cache.saved?.attention == ["PR_1", "PR_2"])
    }

    @Test func aNotifyRunThatGetsUnchangedStillAnnouncesWhatAPollerFetched() async {
        let cache = MemoryCache(cached([pr1, pr2], attention: ["PR_1"]))
        let delivery = FakeDelivery()
        let fetcher = github(makeResult([pr1, pr2]))
        let context = makeContext(fetcher: fetcher, cache: cache, delivery: delivery)
        let first = await InboxRun(context: context).inbox(InboxOptions(notify: true))
        #expect(first.document.source == "unchanged")
        #expect(delivery.notices.map(\.title) == ["#2 Add feature"])
        #expect(cache.saved?.attention == ["PR_1", "PR_2"])
        _ = await InboxRun(context: context).inbox(InboxOptions(notify: true))
        #expect(delivery.notices.count == 1)
        #expect(await fetcher.calls == 2)
    }

    @Test func aPollerWritesTheReloadedAttentionNotTheOneItRead() async {
        let cache = MemoryCache(cached([pr1], attention: ["PR_1"]))
        let fetcher = ScriptedFetcher { [pr1, pr2] _ in
            cache.update { existing in
                guard var next = existing else { return nil }
                next.attention = ["PR_1", "PR_9"]
                return next
            }
            return makeResult([pr1, pr2])
        }
        _ = await InboxRun(context: makeContext(fetcher: fetcher, cache: cache)).inbox(InboxOptions(format: .tmux))
        #expect(cache.saved?.result.pullRequests.count == 2)
        #expect(cache.saved?.attention == ["PR_1", "PR_9"])
    }

    @Test func anUnchangedCheckServesTheCachedResultAndBumpsCheckedAt() async {
        let cache = MemoryCache(cached([pr1], fetchedAt: start - 120, checkedAt: start - 60))
        let fetcher = ScriptedFetcher(outcomes: { _, _ in .unchanged })
        let outcome = await InboxRun(context: makeContext(fetcher: fetcher, cache: cache)).inbox(InboxOptions())
        let request = await fetcher.requests.first
        #expect(request?.previous == ["PR_1": pr1.updatedAt])
        #expect(request?.previousViewer == testViewer)
        #expect(outcome.exitCode == 0)
        #expect(outcome.document.source == "unchanged")
        #expect(outcome.document.sections[0].rows.map(\.id) == ["PR_1"])
        #expect(outcome.document.fetchedAt == start - 120)
        #expect(outcome.document.checkedAt == start)
        #expect(cache.saved?.checkedAt == start)
        #expect(cache.saved?.fetchedAt == start - 120)
    }

    @Test func aStaleOrForeignFingerprintIsNotSent() async {
        for stale in [cached([pr1], fetchedAt: start - 16 * 60), cached([pr1], includeConversation: false)] {
            let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
            _ = await InboxRun(context: makeContext(fetcher: fetcher, cache: MemoryCache(stale))).inbox(InboxOptions())
            #expect(await fetcher.requests.first?.previous == nil)
        }
    }

    @Test func cachedServesWithoutFetchingAndFailsWithoutACache() async {
        let fetcher = ScriptedFetcher { _ in makeResult([]) }
        let served = await InboxRun(
            context: makeContext(fetcher: fetcher, cache: MemoryCache(cached([pr1], fetchedAt: start - 7200)))
        )
        .inbox(InboxOptions(cacheMode: .cached))
        #expect(await fetcher.calls == 0)
        #expect(served.exitCode == 0)
        #expect(served.document.source == "cache")
        #expect(served.document.badge == 1)
        let missing = await InboxRun(context: makeContext(fetcher: fetcher)).inbox(InboxOptions(cacheMode: .cached))
        #expect(missing.exitCode == 1)
        #expect(missing.stderr == ["prinbox: no cache yet, run prinbox inbox"])
        #expect(missing.document.source == nil)
        #expect(missing.document.sections.allSatisfy { $0.rows.isEmpty })
        #expect(await fetcher.calls == 0)
    }

    @Test func maxAgeServesAFreshCacheAndFetchesAStaleOne() async {
        for (checkedAt, served) in [(start - 30, true), (start - 90, false), (start + 30, true)] {
            let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
            let context = makeContext(fetcher: fetcher, cache: MemoryCache(cached([pr1], checkedAt: checkedAt)))
            let outcome = await InboxRun(context: context).inbox(InboxOptions(cacheMode: .maxAge(60)))
            #expect(await fetcher.calls == (served ? 0 : 1))
            #expect(outcome.document.source == (served ? "cache" : "fetch"))
        }
    }

    @Test func aFailedFetchWithACachePrintsTheRowsAndExits1() async {
        let cache = MemoryCache(cached([pr1]))
        let fetcher = ScriptedFetcher { _ in throw FetchError.offline }
        let outcome = await InboxRun(context: makeContext(fetcher: fetcher, cache: cache)).inbox(InboxOptions())
        #expect(outcome.exitCode == 1)
        #expect(outcome.document.source == "cache")
        #expect(outcome.document.sections[0].rows.map(\.id) == ["PR_1"])
        #expect(outcome.document.error?.code == "offline")
        #expect(outcome.document.error?.message.hasPrefix("Offline, showing data from") == true)
        #expect(outcome.stderr.first?.hasPrefix("prinbox: Offline, showing data from") == true)
        #expect(cache.writeCount == 0)
        let unavailable = ScriptedFetcher { _ in throw FetchError.githubUnavailable(status: 502) }
        let fiveHundred = await InboxRun(context: makeContext(fetcher: unavailable, cache: cache)).inbox(InboxOptions())
        #expect(fiveHundred.document.error?.help == FetchError.statusPage)
        #expect(fiveHundred.stderr.first?.hasSuffix("(https://www.githubstatus.com)") == true)
    }

    @Test func aFailedFetchWithoutACacheGivesAnEmptyDocument() async {
        let outcome = await InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.timedOut }))
            .inbox(InboxOptions())
        #expect(outcome.exitCode == 1)
        #expect(
            outcome.document.error
                == InboxDocument.ErrorInfo(code: "timedOut", message: "GitHub did not answer in time", help: nil))
        #expect(outcome.document.source == nil)
        #expect(outcome.document.fetchedAt == nil)
        #expect(outcome.document.sections.count == 6)
        #expect(outcome.stderr == ["prinbox: GitHub did not answer in time"])
    }

    @Test func setupNeededExits3WithTheGuideOnStderr() async {
        let signedOut = await InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut })
        ).inbox(InboxOptions())
        #expect(signedOut.exitCode == 3)
        #expect(signedOut.stderr == [SetupGuide.signedOut.plainText])
        #expect(
            signedOut.document.error
                == InboxDocument.ErrorInfo(code: "loggedOut", message: "Sign in to the GitHub CLI", help: nil))
        let missing = await InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.ghNotFound }, ghOverride: "/x/gh")
        ).inbox(InboxOptions())
        #expect(missing.exitCode == 3)
        #expect(missing.document.error?.message == "gh not found")
        let plain = await InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.ghNotFound }))
            .inbox(InboxOptions())
        #expect(plain.document.error?.help == URL(string: "https://cli.github.com"))
    }

    @Test func reconciliationWakesAndPrunesAndLeavesSeenAlone() async throws {
        let persistence = MemoryStatePersistence()
        let woken = SnoozeEntry(snoozedAt: start - 3600, updatedAt: pr1.updatedAt - 3600)
        let gone = SnoozeEntry(snoozedAt: start - 3600, updatedAt: start)
        let parked = SnoozeEntry(snoozedAt: start - 60, updatedAt: pr2.updatedAt)
        try persistence.save(AppState(snoozed: ["PR_1": woken, "PR_gone": gone, "PR_2": parked]))
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1, self.pr2]) }, persistence: persistence)
        let outcome = await InboxRun(context: context).inbox(InboxOptions())
        #expect(persistence.saved.map { Set($0.snoozed.keys) } == ["PR_2"])
        #expect(persistence.saved?.seen == nil)
        #expect(outcome.document.sections[0].rows.map(\.id) == ["PR_1"])
        #expect(outcome.document.sections[5].rows.map(\.id) == ["PR_2"])
    }

    @Test func theDocumentCarriesNewAndSnoozedFromState() async throws {
        let persistence = MemoryStatePersistence()
        try persistence.save(
            AppState(
                snoozed: ["PR_2": SnoozeEntry(snoozedAt: start, updatedAt: pr2.updatedAt)],
                seen: ["PR_1": pr1.updatedAt - 60, "PR_2": pr2.updatedAt]))
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1, self.pr2]) }, persistence: persistence)
        let outcome = await InboxRun(context: context).inbox(InboxOptions())
        #expect(outcome.document.sections[0].rows.first?.isNew == true)
        #expect(outcome.document.sections[5].rows.first?.snoozed == true)
        #expect(outcome.document.newCount == 1)
    }

    @Test func anUnreadableStateFileIsAWarningAndNothingIsWritten() async {
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1]) },
            persistence: FailingPersistence(loadFails: true, saveFails: true))
        let outcome = await InboxRun(context: context).inbox(InboxOptions())
        #expect(outcome.exitCode == 0)
        #expect(outcome.stderr == ["prinbox: warning: state.json unreadable, ignoring snoozes"])
        #expect(outcome.document.sections[0].rows.count == 1)
    }

    @Test func snoozeUsesTheCachedResultAndIsIdempotent() async {
        let persistence = MemoryStatePersistence()
        let fetcher = ScriptedFetcher { _ in makeResult([]) }
        let run = InboxRun(
            context: makeContext(fetcher: fetcher, cache: MemoryCache(cached([pr1])), persistence: persistence))
        let first = await run.snooze(id: "PR_1")
        #expect(first == CommandOutcome(exitCode: 0, stderr: [], pullRequest: pr1))
        #expect(persistence.saved?.snoozed["PR_1"] == SnoozeEntry(snoozedAt: start, updatedAt: pr1.updatedAt))
        #expect(await fetcher.calls == 0)
        let again = await run.snooze(id: "PR_1")
        #expect(again.exitCode == 0)
        #expect(persistence.saveCount == 1)
    }

    @Test func snoozeFetchesWhenTheIdIsNotCachedAndFailsWhenStillAbsent() async {
        let cache = MemoryCache()
        let persistence = MemoryStatePersistence()
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([self.pr2]) }, cache: cache, persistence: persistence))
        #expect(await run.snooze(id: "PR_2").exitCode == 0)
        #expect(cache.saved?.result.pullRequests.map(\.id) == ["PR_2"])
        #expect(persistence.saved?.snoozed.keys.contains("PR_2") == true)
        let absent = await run.snooze(id: "PR_9")
        #expect(absent == CommandOutcome(exitCode: 1, stderr: ["prinbox: PR_9 is not in your inbox"]))
        let offline = InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.offline }))
        #expect(await offline.snooze(id: "PR_9") == CommandOutcome(exitCode: 1, stderr: ["prinbox: Offline"]))
    }

    @Test func unsnoozeRemovesTheEntryAndIsSilentOtherwise() async throws {
        let persistence = MemoryStatePersistence()
        try persistence.save(AppState(snoozed: ["PR_1": SnoozeEntry(snoozedAt: start, updatedAt: start)]))
        let run = InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) }, persistence: persistence))
        #expect(run.unsnooze(id: "PR_1") == CommandOutcome(exitCode: 0, stderr: []))
        #expect(persistence.saved?.snoozed.isEmpty == true)
        #expect(run.unsnooze(id: "PR_1").exitCode == 0)
        #expect(persistence.saveCount == 2)
    }

    @Test func openOpensTheCachedURL() async {
        let opener = FakeOpener()
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([]) }, cache: MemoryCache(cached([pr1])), opener: opener))
        #expect(await run.open(id: "PR_1").exitCode == 0)
        #expect(opener.opened == [pr1.url])
        #expect(
            await run.open(id: "PR_9") == CommandOutcome(exitCode: 1, stderr: ["prinbox: PR_9 is not in your inbox"]))
    }

    @Test func printFetchesInFullAndTouchesNothing() async throws {
        let cache = MemoryCache()
        let persistence = MemoryStatePersistence()
        try persistence.save(AppState(snoozed: ["PR_2": SnoozeEntry(snoozedAt: start, updatedAt: pr2.updatedAt)]))
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1, self.pr2]) }
        let run = InboxRun(context: makeContext(fetcher: fetcher, cache: cache, persistence: persistence))
        let printed = await run.printInbox()
        #expect(printed.exitCode == 0)
        #expect(printed.stdout.hasPrefix("waiting on you: 1\n\nNeeds your review (1)\n  #1 Add feature  [acme/web]\n"))
        #expect(printed.stdout.contains("#2 Add feature · Snoozed  [acme/web]"))
        #expect(printed.stderr == [])
        #expect(await fetcher.requests.first == FetchRequest.full)
        #expect(cache.writeCount == 0)
        #expect(persistence.saveCount == 1)
        let failing = await InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }))
            .printInbox()
        #expect(failing.exitCode == 3)
        #expect(failing.stdout == "")
        #expect(failing.stderr == [SetupGuide.signedOut.plainText])
    }

    @Test func fetchErrorCodesAreTheCaseNames() {
        let errors: [FetchError] = [
            .ghNotFound, .loggedOut, .offline, .timedOut, .rateLimited(resetAt: nil), .badResponse,
            .githubUnavailable(status: 502), .other("x"),
        ]
        #expect(
            errors.map(\.code) == [
                "ghNotFound", "loggedOut", "offline", "timedOut", "rateLimited", "badResponse", "githubUnavailable",
                "other",
            ])
    }

    @Test func theScopeRidesInTheRequestAndGatesTheCache() async {
        let scope = SearchScope(directReviewRequestsOnly: true)
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let cache = MemoryCache(cached([pr1], attention: ["PR_1"]))
        let context = makeContext(fetcher: fetcher, cache: cache, scope: scope)
        _ = await InboxRun(context: context).inbox(InboxOptions())
        let request = await fetcher.requests.first
        #expect(request?.scope == scope)
        #expect(request?.previous == nil)
        #expect(cache.saved?.scope == scope)
        #expect(cache.saved?.attention == nil)
        _ = await InboxRun(context: context).inbox(InboxOptions())
        #expect(await fetcher.requests.last?.previous == ["PR_1": pr1.updatedAt])
        #expect(await fetcher.requests.count == 2)
    }

    @Test func anUnchangedBumpIsDroppedWhenTheCacheMovedUnderneath() async {
        let cache = MemoryCache(cached([pr1]))
        let fetcher = ScriptedFetcher(outcomes: { _, _ in
            cache.update { _ in self.cached([self.pr2], fetchedAt: self.start - 10, checkedAt: self.start - 10) }
            return .unchanged
        })
        let outcome = await InboxRun(context: makeContext(fetcher: fetcher, cache: cache)).inbox(InboxOptions())
        #expect(outcome.document.source == "unchanged")
        #expect(cache.saved?.checkedAt == start - 10)
        #expect(cache.saved?.result.pullRequests.map(\.id) == ["PR_2"])
    }

    @Test func printFetchesWithTheScope() async throws {
        let scope = SearchScope(repositories: ["acme"])
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let printed = await InboxRun(context: makeContext(fetcher: fetcher, scope: scope)).printInbox()
        #expect(printed.exitCode == 0)
        #expect(await fetcher.requests.first == FetchRequest(scope: scope))
    }

    @Test func writeStateFailurePathsReportOnStderr() async {
        let cache = MemoryCache(cached([pr1]))
        let unreadable = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([]) }, cache: cache,
                persistence: FailingPersistence(loadFails: true, saveFails: true)))
        #expect(
            await unreadable.snooze(id: "PR_1")
                == CommandOutcome(
                    exitCode: 1, stderr: ["prinbox: state.json is unreadable, nothing written"], pullRequest: pr1))
        let unsaveable = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([]) }, cache: cache,
                persistence: FailingPersistence(loadFails: false, saveFails: true)))
        let outcome = await unsaveable.snooze(id: "PR_1")
        #expect(outcome.exitCode == 1)
        #expect(outcome.stderr.first?.hasPrefix("prinbox: state.json not saved: ") == true)
    }

    @Test func snoozeAndOpenExit3WhenSetupIsNeeded() async {
        let run = InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }))
        let snoozed = await run.snooze(id: "PR_1")
        #expect(snoozed.exitCode == 3)
        #expect(snoozed.stderr == [SetupGuide.signedOut.plainText])
        let opened = await run.open(id: "PR_1")
        #expect(opened.exitCode == 3)
        #expect(opened.stderr == [SetupGuide.signedOut.plainText])
    }
}
