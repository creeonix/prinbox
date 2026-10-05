import Foundation
import Observation

/// Owns the inbox and serializes refreshes: one fetch at a time, a refresh requested meanwhile runs
/// exactly once afterwards, rate limiting pauses refreshes until GitHub's reset time, and a failure keeps
/// the last good inbox. It also owns the `StateStore`: snoozes shape the inbox it builds, and consecutive
/// fetches are diffed for arrivals, and a refresh whose ids and updatedAt did not change skips the batches.
@MainActor
@Observable
public final class InboxStore {
    public static let staleAfter: TimeInterval = 60
    public static let rateLimitFallbackPause: TimeInterval = 15 * 60
    /// A refresh that finds nothing changed skips phase 2, but CI results and merge conflicts do not move a PR's
    /// `updatedAt`, so a full fetch runs at least this often.
    public static let fullFetchInterval: TimeInterval = InboxCache.fingerprintCeiling

    public private(set) var inbox: Inbox?
    public private(set) var error: FetchError?
    public private(set) var lastSuccess: Date?
    public private(set) var isRefreshing = false
    /// Rows that arrived in the review sections with the last successful fetch (see `Arrivals`). Cleared by
    /// `snooze` and `unsnooze`, which rebuild without fetching.
    public private(set) var arrivals: [InboxRow] = []
    /// Snoozes and the seen ledger; the popover reads and writes it through this store.
    public let state: StateStore
    /// Follow review threads: threads, reviews and the `involved` search. Off is the lighter refresh.
    public private(set) var includeConversation = true

    /// Called after every inbox change, whoever triggered the refresh (timer, wake, popover, R key).
    @ObservationIgnored public var onInboxChange: (@MainActor () -> Void)?
    /// Called after `onInboxChange` when a fetch brought arrivals.
    @ObservationIgnored public var onArrivals: (@MainActor ([InboxRow]) -> Void)?
    @ObservationIgnored private var followUpRequested = false
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private var lastResult: FetchResult?
    /// The arrivals baseline: the attention ids of the last inbox. A complete fetch replaces it; an incomplete
    /// one only adds to it, so PRs a partial response left out do not come back as arrivals.
    @ObservationIgnored private var known: Set<String>?
    /// `id -> updatedAt` of the last full fetch; sent back so an unchanged inbox costs one request.
    @ObservationIgnored private var fingerprint: [String: Date]?
    @ObservationIgnored private var lastFullFetch: Date?
    @ObservationIgnored private let fetcher: InboxFetching
    @ObservationIgnored private let cache: CacheStoring
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(
        fetcher: InboxFetching, state: StateStore = StateStore(persistence: MemoryStatePersistence()),
        cache: CacheStoring = MemoryCache(), clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.state = state
        self.cache = cache
        self.clock = clock
    }

    /// Adopts the cache at launch: rows at once, the last confirmation time, and, when the trust rules hold,
    /// the fingerprint (so the first refresh may be an unchanged check) and the arrivals baseline (so PRs that
    /// entered an attention section while the app was not running notify). Rows already in the cached result
    /// that the baseline lacks (a poller fetched them) are announced here. Called once, before the first
    /// refresh.
    public func adoptCache() {
        guard let cached = cache.load() else { return }
        lastResult = cached.result
        lastSuccess = cached.checkedAt
        if let fingerprint = cached.trustedFingerprint(
            now: clock(), shape: FetchShape(includeConversation: includeConversation))
        {
            self.fingerprint = fingerprint
            lastFullFetch = cached.fetchedAt
        }
        known = cached.trustedAttention(shape: FetchShape(includeConversation: includeConversation))
        let built = InboxBuilder.build(cached.result, snoozed: state.snoozedIDs)
        inbox = built
        // A poller may have refreshed the fingerprint past the baseline, so the first refresh can be an unchanged
        // check: announce what it fetched now, and advance the baseline in the cache too.
        let arrived = Arrivals.compute(previous: known, current: built)
        if !arrived.isEmpty {
            let baseline = Arrivals.baseline(after: built, complete: cached.result.isComplete, extending: known)
            known = baseline
            arrivals = arrived
            cache.update { existing in
                guard var next = existing else { return nil }
                next.attention = baseline.sorted()
                return next
            }
        }
        onInboxChange?()
        if !arrived.isEmpty { onArrivals?(arrived) }
    }

    public var badge: StatusBadge {
        StatusBadge.derive(inbox: inbox, error: error, lastSuccess: lastSuccess)
    }

    /// The current error (if any) followed by partial-data warnings. Setup errors are left out: the setup
    /// panel explains them.
    public var warningLines: [String] {
        let errorLine = error.flatMap { $0.needsSetup ? nil : $0.message(lastSuccess: lastSuccess) }
        return (errorLine.map { [$0] } ?? []) + (inbox?.warnings ?? [])
    }

    /// The current error's help link (GitHub's status page for a 5xx), nil otherwise.
    public var warningLink: URL? { error?.helpURL }

    public func refresh() async {
        guard !isPaused else { return }
        guard !isRefreshing else {
            followUpRequested = true
            return
        }
        isRefreshing = true
        repeat {
            followUpRequested = false
            await fetchOnce()
        } while followUpRequested && !isPaused
        isRefreshing = false
    }

    /// Poll interval while gh is missing or signed out, so fixing it shows up within seconds.
    public static let setupRetryInterval: Duration = .seconds(10)

    public var needsSetup: Bool { error?.needsSetup ?? false }

    /// Called every `setupRetryInterval`; fetches only while setup is needed. A missing or signed-out gh
    /// fails locally without a network request, so polling costs nothing.
    public func retryIfSetupNeeded() async {
        guard needsSetup else { return }
        await refresh()
    }

    /// Refreshes only when the last success is older than `staleAfter`. Used when the popover opens.
    public func refreshIfStale() async {
        if let lastSuccess, clock().timeIntervalSince(lastSuccess) < Self.staleAfter { return }
        await refresh()
    }

    // MARK: Conversation

    /// Changing what a fetch asks for invalidates the fingerprint, so the next refresh is a full one. The caller
    /// triggers that refresh.
    public func setIncludeConversation(_ on: Bool) {
        guard on != includeConversation else { return }
        includeConversation = on
        fingerprint = nil
    }

    // MARK: Snooze

    /// Parks a PR of the last fetch and rebuilds; unknown or already snoozed ids do nothing.
    public func snooze(_ id: String) {
        guard let pr = lastResult?.pullRequests.first(where: { $0.id == id }), !state.isSnoozed(id) else { return }
        state.snooze(pr)
        rebuild()
    }

    /// Wakes a snoozed PR and rebuilds; ids that are not snoozed do nothing.
    public func unsnooze(_ id: String) {
        guard state.isSnoozed(id) else { return }
        state.unsnooze(id)
        rebuild()
    }

    private func rebuild() {
        guard let lastResult else { return }
        arrivals = []
        inbox = InboxBuilder.build(lastResult, snoozed: state.snoozedIDs)
        onInboxChange?()
    }

    /// Picks up a snooze or wake another writer (the command) made in state.json; rebuilds when the set changed.
    public func reloadState() {
        let before = state.snoozedIDs
        state.reload()
        if state.snoozedIDs != before { rebuild() }
    }

    private var isPaused: Bool {
        pausedUntil.map { clock() < $0 } ?? false
    }

    private func fetchOnce() async {
        do {
            let request = nextRequest()
            switch try await fetcher.fetch(request) {
            case .unchanged:
                reloadState()
                let now = clock()
                error = nil
                lastSuccess = now
                pausedUntil = nil
                cache.update { existing in
                    guard var next = existing else { return nil }
                    next.checkedAt = now
                    return next
                }
            case .result(let result):
                state.didFetch(result)
                let built = InboxBuilder.build(result, snoozed: state.snoozedIDs)
                let arrived = Arrivals.compute(previous: known, current: built)
                let baseline = Arrivals.baseline(after: built, complete: result.isComplete, extending: known)
                arrivals = arrived
                known = baseline
                lastResult = result
                // A toggle during the fetch already cleared the fingerprint; this result answers the old question.
                fingerprint = request.includeConversation == includeConversation ? result.fingerprint : nil
                let now = clock()
                lastFullFetch = now
                inbox = built
                error = nil
                lastSuccess = now
                pausedUntil = nil
                cache.update { _ in
                    InboxCache(
                        fetchedAt: now, checkedAt: now, includeConversation: request.includeConversation,
                        viewer: result.viewerLogin, fingerprint: result.fingerprint, attention: baseline.sorted(),
                        result: result)
                }
                onInboxChange?()
                // `arrived`, not `arrivals`: a hook that snoozes synchronously rebuilds and clears the latter.
                if !arrived.isEmpty { onArrivals?(arrived) }
            }
        } catch let failure as FetchError {
            error = failure
            if case .rateLimited(let resetAt) = failure {
                pausedUntil = resetAt ?? clock().addingTimeInterval(Self.rateLimitFallbackPause)
            }
        } catch {
            self.error = .other(String(String(describing: error).prefix(120)))
        }
    }

    /// The previous fingerprint rides along while the last full fetch is younger than `fullFetchInterval`.
    private func nextRequest() -> FetchRequest {
        let fresh = lastFullFetch.map { clock().timeIntervalSince($0) < Self.fullFetchInterval } ?? false
        let previous = fresh ? fingerprint : nil
        return FetchRequest(
            previous: previous, includeConversation: includeConversation,
            previousViewer: previous == nil ? nil : lastResult?.viewerLogin)
    }
}
