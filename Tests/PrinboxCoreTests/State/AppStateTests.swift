import Foundation
import Testing

@testable import PrinboxCore

@Suite struct AppStateTests {
    let snoozedAt = date("2026-09-30T09:00:00Z")
    let updatedAt = date("2026-09-29T17:40:00Z")

    func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    @Test func missingFileLoadsAsNil() throws {
        #expect(try JSONStateFile(url: temporaryFile()).load() == nil)
    }

    @Test func saveCreatesTheDirectoryAndRoundTrips() throws {
        let file = JSONStateFile(url: temporaryFile())
        let state = AppState(
            snoozed: ["PR_1": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: updatedAt)],
            seen: ["PR_2": updatedAt])
        try file.save(state)
        #expect(try file.load() == state)
        #expect(FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
    }

    @Test func fileIsReadableJSONWithISODates() throws {
        let file = JSONStateFile(url: temporaryFile())
        try file.save(AppState(snoozed: ["PR_1": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: updatedAt)]))
        let text = try String(contentsOf: file.url, encoding: .utf8)
        #expect(text.contains("\"snoozedAt\" : \"2026-09-30T09:00:00Z\""))
        #expect(text.contains("\"version\" : 1"))
        #expect(!text.contains("\"seen\""))
    }

    @Test func unknownKeysAndNewerVersionsStillLoad() throws {
        let file = JSONStateFile(url: temporaryFile())
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
            {"version": 7, "snoozed": {}, "seen": {"PR_9": "2026-09-30T10:12:00Z"}, "future": {"x": 1}}
            """
        try Data(json.utf8).write(to: file.url)
        let loaded = try file.load()
        #expect(loaded?.version == 7)
        #expect(loaded?.seen == ["PR_9": date("2026-09-30T10:12:00Z")])
    }

    @Test func corruptFileThrows() throws {
        let file = JSONStateFile(url: temporaryFile())
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file.url)
        #expect(throws: (any Error).self) { try file.load() }
    }

    @Test func defaultURLIsUnderApplicationSupport() {
        let url = JSONStateFile.defaultURL()
        #expect(url.lastPathComponent == "state.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "prinbox")
        #expect(url.path.contains("/Library/Application Support/"))
    }

    @Test func memoryPersistenceRemembersTheLastSave() throws {
        let memory = MemoryStatePersistence()
        #expect(try memory.load() == nil)
        try memory.save(AppState(seen: [:]))
        try memory.save(AppState(seen: ["PR_1": updatedAt]))
        #expect(try memory.load() == AppState(seen: ["PR_1": updatedAt]))
        #expect(memory.saveCount == 2)
        #expect(try MemoryStatePersistence(AppState(version: 3)).load()?.version == 3)
    }
}
