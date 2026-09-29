import Foundation
import Observation

/// Owns the inbox and serializes refreshes: one fetch at a time, a refresh requested meanwhile runs
/// exactly once afterwards, rate limiting pauses refreshes until GitHub's reset time, and a failure keeps
/// the last good inbox.
@MainActor
@Observable
public final class InboxStore {
    public static let staleAfter: TimeInterval = 60
    public static let rateLimitFallbackPause: TimeInterval = 15 * 60

    public private(set) var inbox: Inbox?
    public private(set) var error: FetchError?
    public private(set) var lastSuccess: Date?
    public private(set) var isRefreshing = false

    @ObservationIgnored private var followUpRequested = false
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private let fetcher: InboxFetching
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(fetcher: InboxFetching, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.clock = clock
    }

    public var badge: StatusBadge {
        StatusBadge.derive(inbox: inbox, error: error, lastSuccess: lastSuccess)
    }

    /// The current error (if any) followed by partial-data warnings.
    public var warningLines: [String] {
        (error.map { [$0.message(lastSuccess: lastSuccess)] } ?? []) + (inbox?.warnings ?? [])
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

    /// Refreshes only when the last success is older than `staleAfter`. Used when the popover opens.
    public func refreshIfStale() async {
        if let lastSuccess, clock().timeIntervalSince(lastSuccess) < Self.staleAfter { return }
        await refresh()
    }

    private var isPaused: Bool {
        pausedUntil.map { clock() < $0 } ?? false
    }

    private func fetchOnce() async {
        do {
            let result = try await fetcher.fetch()
            inbox = InboxBuilder.build(result)
            error = nil
            lastSuccess = clock()
            pausedUntil = nil
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
