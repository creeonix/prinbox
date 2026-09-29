import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    private let store: InboxStore
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?

    init() {
        store = InboxStore(fetcher: GhClient())
    }

    func start() {
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.refreshNow() },
            onRefresh: { [weak self] in self?.refreshNow() })
        observeBadge()
        triggers.start { [weak self] in await self?.store.refresh() }
        refreshNow()
    }

    private func refreshNow() {
        Task { await store.refresh() }
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
