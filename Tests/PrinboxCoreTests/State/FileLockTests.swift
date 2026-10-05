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
        try? await Task.sleep(for: .milliseconds(50))
        FileLock(url: url).withLock { order.add("second in") }
        await holder.value
        #expect(order.entries == ["first in", "first out", "second in"])
    }

    @Test func aStuckLockIsGivenUpWithANotice() async {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let logger = MemoryLogging()
        let holder = Task.detached { FileLock(url: url).withLock { Thread.sleep(forTimeInterval: 0.6) } }
        try? await Task.sleep(for: .milliseconds(50))
        var ran = false
        FileLock(url: url, patience: 0.1, logger: logger).withLock { ran = true }
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

    @Test func theBodyValueAndErrorsPassThrough() throws {
        let url = lockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let lock = FileLock(url: url)
        #expect(lock.withLock { 42 } == 42)
        #expect(throws: FetchError.offline) { try lock.withLock { throw FetchError.offline } }
        #expect(lock.withLock { 1 } == 1)
    }
}
