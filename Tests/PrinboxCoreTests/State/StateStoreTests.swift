import Foundation
import Testing

@testable import PrinboxCore

/// Persistence whose load or save fails, for the error paths.
struct FailingPersistence: StatePersisting {
    struct Failure: Error {}
    let loadFails: Bool
    let saveFails: Bool

    func load() throws -> AppState? {
        if loadFails { throw Failure() }
        return nil
    }

    func save(_ state: AppState) throws {
        if saveFails { throw Failure() }
    }
}

@MainActor
@Suite struct StateStoreTests {
    let start = date("2026-08-10T12:00:00Z")
    let old = date("2026-08-01T10:00:00Z")
    let newer = date("2026-08-02T10:00:00Z")
    let entry = SnoozeEntry(snoozedAt: date("2026-08-10T11:00:00Z"), updatedAt: date("2026-08-01T10:00:00Z"))

    func makeStore(_ memory: MemoryStatePersistence = MemoryStatePersistence()) -> (StateStore, MemoryStatePersistence)
    {
        let clock = TestClock(start)
        return (StateStore(persistence: memory, clock: { clock.now }), memory)
    }

    @Test func persistenceFailuresLogAFixedMessageWithTheErrorAsThePrivateDetail() {
        let logger = MemoryLogging()
        let store = StateStore(persistence: FailingPersistence(loadFails: true, saveFails: true), logger: logger)
        let first = logger.lines
        #expect(first.count == 1)
        #expect(first.first?.level == .error)
        #expect(first.first?.category == .state)
        #expect(first.first?.message == "state.json unreadable, starting empty")
        #expect(first.first?.detail != nil)
        store.snooze(makePR())
        let lines = logger.lines
        #expect(lines.count == 3)
        #expect(lines[1].message == "state.json unreadable, keeping the in-memory state")
        #expect(lines.last?.level == .error)
        #expect(lines.last?.category == .state)
        #expect(lines.last?.message == "state.json not saved")
        #expect(lines.last?.detail != nil)
    }

    @Test func snoozeRecordsTheClockAndTheUpdatedAtAndSaves() {
        let (store, memory) = makeStore()
        let pr = makePR(id: "a", updatedAt: old)
        store.snooze(pr)
        #expect(store.isSnoozed("a"))
        #expect(store.snoozedIDs == ["a"])
        #expect(store.state.snoozed["a"] == SnoozeEntry(snoozedAt: start, updatedAt: old))
        #expect(memory.saved?.snoozed["a"]?.updatedAt == old)
        store.unsnooze("a")
        #expect(!store.isSnoozed("a"))
        #expect(memory.saved?.snoozed.isEmpty == true)
        #expect(memory.saveCount == 2)
    }

    @Test func unchangedStateIsNotSavedAgain() {
        let (store, memory) = makeStore()
        store.unsnooze("missing")
        #expect(memory.saveCount == 0)
    }

    @Test func storedStateIsLoadedAtInit() {
        let memory = MemoryStatePersistence(
            AppState(snoozed: ["a": SnoozeEntry(snoozedAt: start, updatedAt: old)], seen: ["b": old]))
        let (store, _) = makeStore(memory)
        #expect(store.isSnoozed("a"))
        #expect(store.isNew(makePR(id: "b", updatedAt: newer)))
    }

    @Test func didFetchWakesAndPrunesSnoozes() {
        let (store, _) = makeStore()
        store.snooze(makePR(id: "a", updatedAt: old))
        store.snooze(makePR(id: "gone", updatedAt: old))
        store.didFetch(makeResult([makePR(id: "a", updatedAt: newer)]))
        #expect(store.snoozedIDs.isEmpty)
    }

    @Test func didFetchKeepsSnoozesAbsentFromAnIncompleteFetch() {
        let (store, _) = makeStore()
        store.snooze(makePR(id: "gone", updatedAt: old))
        store.didFetch(makeResult([makePR(id: "a")], warnings: ["partial"]))
        #expect(store.isSnoozed("gone"))
    }

    @Test func firstFetchSeedsTheLedgerSoNothingIsNew() {
        let (store, memory) = makeStore()
        let pr = makePR(id: "a", updatedAt: old)
        #expect(!store.isNew(pr))
        store.didFetch(makeResult([pr]))
        #expect(store.state.seen == ["a": old])
        #expect(!store.isNew(pr))
        #expect(memory.saved?.seen == ["a": old])
    }

    @Test func afterSeedingAbsentAndNewerPullRequestsAreNew() {
        let (store, _) = makeStore()
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old)]))
        #expect(store.isNew(makePR(id: "b", updatedAt: old)))
        #expect(store.isNew(makePR(id: "a", updatedAt: newer)))
        #expect(!store.isNew(makePR(id: "a", updatedAt: old)))
    }

    @Test func markSeenUpsertsWithoutForgetting() {
        let (store, _) = makeStore()
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old), makePR(id: "b", updatedAt: old)]))
        store.markSeen([makePR(id: "a", updatedAt: newer), makePR(id: "c", updatedAt: old)])
        #expect(store.state.seen == ["a": newer, "b": old, "c": old])
        #expect(!store.isNew(makePR(id: "a", updatedAt: newer)))
    }

    @Test func markSeenBeforeAnyFetchDoesNotCreateAnEmptyLedger() {
        let (store, memory) = makeStore()
        store.markSeen([])
        #expect(store.state.seen == nil)
        #expect(memory.saveCount == 0)
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old)]))
        #expect(!store.isNew(makePR(id: "a", updatedAt: old)))
    }

    @Test func completeFetchPrunesTheLedgerIncompleteKeepsIt() {
        let (store, _) = makeStore()
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old), makePR(id: "b", updatedAt: old)]))
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old)], warnings: ["partial"]))
        #expect(store.state.seen?.keys.sorted() == ["a", "b"])
        store.didFetch(makeResult([makePR(id: "a", updatedAt: old)]))
        #expect(store.state.seen == ["a": old])
    }

    @Test func emptyInboxSeedsAnEmptyLedgerSoLaterArrivalsAreNew() {
        let (store, _) = makeStore()
        store.didFetch(makeResult([]))
        #expect(store.state.seen == [:])
        #expect(store.isNew(makePR(id: "a")))
    }

    @Test func corruptFileStartsEmptyAndSaveFailureKeepsMemory() {
        let store = StateStore(persistence: FailingPersistence(loadFails: true, saveFails: true))
        #expect(store.state == AppState())
        store.snooze(makePR(id: "a"))
        #expect(store.isSnoozed("a"))
    }

    @Test func aChangeIsAppliedOnTopOfTheFileNotTheMemoryCopy() throws {
        let persistence = MemoryStatePersistence()
        let store = StateStore(persistence: persistence, clock: { date("2026-08-10T12:00:00Z") })
        // Another writer, the command, parks PR_2 while this store knows nothing about it.
        try persistence.save(AppState(snoozed: ["PR_2": entry]))
        store.snooze(makePR(id: "PR_1"))
        #expect(store.snoozedIDs == ["PR_1", "PR_2"])
        #expect(Set((persistence.saved?.snoozed ?? [:]).keys) == ["PR_1", "PR_2"])
    }

    @Test func reloadPublishesAnotherWritersChange() throws {
        let persistence = MemoryStatePersistence()
        let store = StateStore(persistence: persistence)
        try persistence.save(AppState(snoozed: ["PR_2": entry]))
        #expect(!store.isSnoozed("PR_2"))
        store.reload()
        #expect(store.isSnoozed("PR_2"))
    }

    @Test func reloadTreatsADeletedFileAsEmpty() {
        let persistence = MemoryStatePersistence(AppState(snoozed: ["PR_1": entry]))
        let store = StateStore(persistence: persistence)
        #expect(store.isSnoozed("PR_1"))
        persistence.clear()
        store.reload()
        #expect(store.state == AppState())
        #expect(persistence.saveCount == 0)
    }

    @Test func anUnreadableFileKeepsTheMemoryCopyOnWriteAndReload() {
        let logger = MemoryLogging()
        let store = StateStore(persistence: FailingPersistence(loadFails: true, saveFails: true), logger: logger)
        store.snooze(makePR(id: "PR_1"))
        store.reload()
        #expect(store.isSnoozed("PR_1"))
        #expect(logger.messages(.notice) == ["state.json unreadable, keeping the in-memory state"])
    }

    @Test func aLockedStoreStillWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-state-lock-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = JSONStateFile(url: directory.appendingPathComponent("state.json"))
        let store = StateStore(persistence: file, lock: FileLock(url: directory.appendingPathComponent("prinbox.lock")))
        store.snooze(makePR(id: "PR_1"))
        #expect(try file.load()?.snoozed.keys.contains("PR_1") == true)
    }
}
