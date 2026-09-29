import AppKit
import PrinboxCore

/// Refreshes every five minutes and after the Mac wakes. Popover-open and manual refreshes live in
/// the coordinator. Networking is rarely back the instant the Mac wakes, so neither trigger fires then:
/// the timer runs on the suspending clock (it does not advance during sleep) and the wake refresh waits.
@MainActor
final class RefreshTriggers {
    static let interval: Duration = .seconds(300)
    static let wakeDelay: Duration = .seconds(15)

    private var timer: Task<Void, Never>?
    private var setupPoll: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// `retrySetup` runs every `InboxStore.setupRetryInterval`; it only fetches while gh needs setup.
    func start(
        _ refresh: @escaping @MainActor @Sendable () async -> Void,
        retrySetup: @escaping @MainActor @Sendable () async -> Void
    ) {
        setupPoll = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: InboxStore.setupRetryInterval)
                guard !Task.isCancelled else { return }
                await retrySetup()
            }
        }
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval, clock: .suspending)
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: RefreshTriggers.wakeDelay)
                await refresh()
            }
        }
    }
}
