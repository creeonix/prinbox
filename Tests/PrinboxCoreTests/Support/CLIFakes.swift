import Foundation

@testable import PrinboxCore

/// Records every notice delivered.
final class FakeDelivery: NotificationDelivering, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ArrivalNotice] = []

    func deliver(_ notice: ArrivalNotice) async { lock.withLock { stored.append(notice) } }

    var notices: [ArrivalNotice] { lock.withLock { stored } }
}

/// A run context over fakes. Every piece can be handed in, so a test can inspect it afterwards.
func makeContext(
    fetcher: InboxFetching, cache: CacheStoring = MemoryCache(),
    persistence: StatePersisting = MemoryStatePersistence(),
    lock: FileLock? = nil, followReviewThreads: Bool = true, ghOverride: String? = nil,
    delivery: NotificationDelivering = FakeDelivery(), opener: URLOpening = FakeOpener(), notifyNote: String? = nil,
    clock: @escaping @Sendable () -> Date = { date("2026-08-10T12:00:00Z") }, logger: Logging = NullLogging(),
    version: String = "0.5.0-test"
) -> RunContext {
    RunContext(
        fetcher: fetcher, cache: cache, persistence: persistence, lock: lock, followReviewThreads: followReviewThreads,
        ghOverride: ghOverride, delivery: delivery, opener: opener, notifyNote: notifyNote, clock: clock,
        logger: logger,
        version: version)
}
