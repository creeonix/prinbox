import Foundation
import Observation

/// Owns the inbox and serializes refreshes: one fetch at a time, a refresh requested meanwhile runs
/// exactly once afterwards, rate limiting pauses refreshes until GitHub's reset time, and a failure keeps
/// the last good inbox. It also owns the `StateStore`: snoozes shape the inbox it builds, and consecutive
/// fetches are diffed for arrivals.
@MainActor
@Observable
public final class InboxStore {
    public static let staleAfter: TimeInterval = 60
    public static let rateLimitFallbackPause: TimeInterval = 15 * 60

    public private(set) var inbox: Inbox?
    public private(set) var error: FetchError?
    public private(set) var lastSuccess: Date?
    public private(set) var isRefreshing = false
    /// Rows that arrived in the review sections with the last successful fetch (see `Arrivals`). Cleared by
    /// `snooze` and `unsnooze`, which rebuild without fetching.
    public private(set) var arrivals: [InboxRow] = []
    /// Snoozes and the seen ledger; the popover reads and writes it through this store.
    public let state: StateStore

    /// Called after every inbox change, whoever triggered the refresh (timer, wake, popover, R key).
    @ObservationIgnored public var onInboxChange: (@MainActor () -> Void)?
    /// Called after `onInboxChange` when a fetch brought arrivals.
    @ObservationIgnored public var onArrivals: (@MainActor ([InboxRow]) -> Void)?
    @ObservationIgnored private var followUpRequested = false
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private var lastResult: FetchResult?
    @ObservationIgnored private let fetcher: InboxFetching
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(
        fetcher: InboxFetching, state: StateStore = StateStore(persistence: MemoryStatePersistence()),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.state = state
        self.clock = clock
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

    // MARK: Snooze

    /// Parks a PR of the last fetch and rebuilds; unknown or already snoozed ids do nothing.
    public func snooze(_ id: String) {
        guard let pr = lastResult?.pullRequests.first(where: { $0.id == id }), !state.isSnoozed(id) else { return }
        state.snooze(pr)
        rebuild()
    }

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

    private var isPaused: Bool {
        pausedUntil.map { clock() < $0 } ?? false
    }

    private func fetchOnce() async {
        do {
            let result = try await fetcher.fetch()
            state.didFetch(result)
            let built = InboxBuilder.build(result, snoozed: state.snoozedIDs)
            arrivals = Arrivals.compute(previous: lastResult?.pullRequests, current: built)
            lastResult = result
            inbox = built
            error = nil
            lastSuccess = clock()
            pausedUntil = nil
            onInboxChange?()
            if !arrivals.isEmpty { onArrivals?(arrivals) }
        } catch let failure as FetchError {
            error = failure
            if case .rateLimited(let resetAt) = failure {
                pausedUntil = resetAt ?? clock().addingTimeInterval(Self.rateLimitFallbackPause)
            }
        } catch {
            self.error = .other(String(String(describing: error).prefix(120)))
        }
    }
}
