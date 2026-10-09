import Foundation
import Testing

@testable import PrinboxCore

final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ entry: String) { lock.withLock { stored.append(entry) } }
    var entries: [String] { lock.withLock { stored } }
}

@Suite struct FileLockTests {
    func lockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-lock-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("prinbox.lock")
    }

    /// Polls until the holder is inside its lock, failing the test after two seconds.
    func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            if Date() >= deadline {
                Issue.record("the holder did not take the lock within two seconds")
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func twoLocksOnOnePathSerializeTheirBodies() async {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let order = OrderLog()
        let holder = Task.detached {
            FileLock(url: url).withLock {
                order.add("first in")
                Thread.sleep(forTimeInterval: 0.3)
                order.add("first out")
            }
        }
        await waitUntil { order.entries.contains("first in") }
        FileLock(url: url).withLock { order.add("second in") }
        await holder.value
        #expect(order.entries == ["first in", "first out", "second in"])
    }

    /// The holder keeps the lock until the test says "done", never for a fixed time: on a loaded CI runner the
    /// 0.6 s it used to sleep could pass before the second lock was even tried, and the notice never came.
    @Test func aStuckLockIsGivenUpWithANotice() async {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let logger = MemoryLogging()
        let order = OrderLog()
        let holder = Task.detached {
            FileLock(url: url).withLock {
                order.add("held")
                let deadline = Date().addingTimeInterval(5)
                while !order.entries.contains("done") && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
        }
        await waitUntil { order.entries.contains("held") }
        var ran = false
        FileLock(url: url, patience: 0.1, logger: logger).withLock { ran = true }
        order.add("done")
        #expect(ran)
        #expect(logger.messages(.notice) == ["lock not acquired within 100 ms, writing without it"])
        await holder.value
    }

    @Test func anUnopenableLockPathStillRunsTheBody() {
        let logger = MemoryLogging()
        var ran = false
        let lock = FileLock(url: URL(fileURLWithPath: "/dev/null/impossible/prinbox.lock"), logger: logger)
        lock.withLock { ran = true }
        #expect(ran)
        #expect(logger.messages(.notice) == ["lock file not opened, writing without it"])
    }

    /// A leaked descriptor would keep the lock, so the next `withLock` on the same path would wait out its
    /// patience and log a notice: no notice means every descriptor was released.
    @Test func theBodyValueAndErrorsPassThroughWithoutLeakingTheLock() throws {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let logger = MemoryLogging()
        let lock = FileLock(url: url, patience: 0.2, logger: logger)
        #expect(lock.withLock { 42 } == 42)
        #expect(throws: FetchError.offline) { try lock.withLock { throw FetchError.offline } }
        #expect(lock.withLock { 1 } == 1)
        #expect(FileLock(url: url, patience: 0.2, logger: logger).withLock { 2 } == 2)
        #expect(logger.lines.isEmpty)
    }
}
