import AppKit

/// Refreshes every five minutes and after the Mac wakes. Popover-open and manual refreshes live in
/// the coordinator.
@MainActor
final class RefreshTriggers {
    static let interval: Duration = .seconds(300)

    private var timer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    func start(_ refresh: @escaping @MainActor @Sendable () async -> Void) {
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await refresh() }
        }
    }
}
