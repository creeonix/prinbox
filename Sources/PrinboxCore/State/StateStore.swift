import Foundation
import Observation

/// Snoozes and the "seen" ledger, loaded from and saved to `state.json` through `StatePersisting`. Every
/// change that alters the state is saved at once; the views observe `state`.
@MainActor
@Observable
public final class StateStore {
    public private(set) var state: AppState
    @ObservationIgnored private let persistence: StatePersisting
    @ObservationIgnored private let lock: FileLock?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let logger: Logging

    /// A file that cannot be read is logged and replaced by an empty state at the next save.
    public init(
        persistence: StatePersisting, lock: FileLock? = nil, clock: @escaping @Sendable () -> Date = { Date() },
        logger: Logging = NullLogging()
    ) {
        self.persistence = persistence
        self.lock = lock
        self.clock = clock
        self.logger = logger
        do {
            state = try persistence.load() ?? AppState()
        } catch {
            logger.error(.state, "state.json unreadable, starting empty", private: String(describing: error))
            state = AppState()
        }
    }

    // MARK: Snooze

    public var snoozedIDs: Set<String> { Set(state.snoozed.keys) }

    public func isSnoozed(_ id: String) -> Bool { state.snoozed[id] != nil }

    public func snooze(_ pr: PullRequest) {
        update { $0.snoozed[pr.id] = SnoozeEntry(snoozedAt: clock(), updatedAt: pr.updatedAt) }
    }

    public func unsnooze(_ id: String) {
        update { $0.snoozed[id] = nil }
    }

    /// Wakes snoozes whose PR changed, seeds the ledger on the first fetch ever (so nothing is new after an
    /// install), and on a complete fetch forgets PRs GitHub no longer returns.
    public func didFetch(_ result: FetchResult) {
        update { state in
            state.snoozed = Snooze.reconcile(state.snoozed, with: result)
            if state.seen == nil {
                state.seen = Self.snapshot(result.pullRequests)
            } else if result.isComplete {
                let present = Set(result.pullRequests.map(\.id))
                state.seen = state.seen?.filter { present.contains($0.key) }
            }
        }
    }

    // MARK: New since last look

    /// False until the ledger exists; then true for a PR the ledger lacks or knows with an older `updatedAt`.
    public func isNew(_ pr: PullRequest) -> Bool {
        guard let seen = state.seen else { return false }
        guard let last = seen[pr.id] else { return true }
        return pr.updatedAt > last
    }

    /// The popover closed over these rows. Entries are upserted, never removed here; `didFetch` prunes.
    /// Nothing to mark leaves the ledger alone, so a close before the first fetch cannot create an empty one.
    public func markSeen(_ prs: [PullRequest]) {
        guard !prs.isEmpty else { return }
        update { $0.seen = ($0.seen ?? [:]).merging(Self.snapshot(prs)) { _, new in new } }
    }

    private static func snapshot(_ prs: [PullRequest]) -> [String: Date] {
        Dictionary(prs.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { _, new in new })
    }

    /// Picks up what another writer, the command, put in the file; nothing happens when it is unchanged or
    /// unreadable.
    public func reload() {
        guard let loaded = try? persistence.load(), loaded != state else { return }
        state = loaded
    }

    /// Applies a change on top of what the file holds now, under the lock, and saves when the result differs
    /// from the file. The published state is the result either way. A failed save is logged; the in-memory
    /// state keeps the change.
    private func update(_ change: (inout AppState) -> Void) {
        locked {
            let base = loadForWrite()
            var next = base
            change(&next)
            state = next
            guard next != base else { return }
            do {
                try persistence.save(next)
            } catch {
                logger.error(.state, "state.json not saved", private: String(describing: error))
            }
        }
    }

    /// The file's content right now: a missing file is an empty state, an unreadable one keeps the memory copy.
    private func loadForWrite() -> AppState {
        do {
            return try persistence.load() ?? AppState()
        } catch {
            logger.notice(.state, "state.json unreadable, keeping the in-memory state")
            return state
        }
    }

    private func locked(_ body: () -> Void) {
        if let lock { lock.withLock(body) } else { body() }
    }
}
