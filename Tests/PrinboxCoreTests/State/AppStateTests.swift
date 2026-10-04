import Foundation
import Testing

@testable import PrinboxCore

@Suite struct AppStateTests {
    let snoozedAt = date("2026-09-30T09:00:00Z")
    let updatedAt = date("2026-09-29T17:40:00Z")

    /// A state file in a fresh temporary directory, removed when `body` returns.
    func withStateFile(_ body: (JSONStateFile) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(JSONStateFile(url: directory.appendingPathComponent("state.json")))
    }

    func write(_ json: String, to file: JSONStateFile) throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file.url)
    }

    @Test func missingFileLoadsAsNil() throws {
        try withStateFile { file in
            let loaded = try file.load()
            #expect(loaded == nil)
            #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        }
    }

    @Test func saveCreatesTheDirectoryAndRoundTrips() throws {
        try withStateFile { file in
            let state = AppState(
                snoozed: ["PR_1": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: updatedAt)],
                seen: ["PR_2": updatedAt])
            try file.save(state)
            let loaded = try file.load()
            #expect(loaded == state)
            #expect(FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        }
    }

    @Test func fileIsReadableJSONWithWholeSecondUTCDates() throws {
        try withStateFile { file in
            try file.save(
                AppState(
                    snoozed: [
                        "PR_1": SnoozeEntry(snoozedAt: snoozedAt, updatedAt: updatedAt)
                    ]))
            let text = try String(contentsOf: file.url, encoding: .utf8)
            #expect(text.contains("\"snoozedAt\" : \"2026-09-30T09:00:00Z\""))
            #expect(text.contains("\"version\" : 1"))
            #expect(!text.contains("\"seen\""))
        }
    }

    @Test func unknownKeysAndNewerVersionsStillLoadAndKeepTheirVersion() throws {
        try withStateFile { file in
            try write(
                """
                {"version": 7, "snoozed": {}, "seen": {"PR_9": "2026-09-30T10:12:00Z"}, "future": {"x": 1}}
                """, to: file)
            let loaded = try #require(try file.load())
            #expect(loaded.version == 7)
            #expect(loaded.seen == ["PR_9": date("2026-09-30T10:12:00Z")])
            try file.save(loaded)
            let reloaded = try file.load()
            #expect(reloaded?.version == 7)
        }
    }

    @Test func missingSnoozedAndVersionDefault() throws {
        try withStateFile { file in
            try write(#"{"seen": {"PR_9": "2026-09-30T10:12:00Z"}}"#, to: file)
            let loaded = try #require(try file.load())
            #expect(loaded.version == AppState.currentVersion)
            #expect(loaded.snoozed.isEmpty)
            #expect(loaded.seen?.count == 1)
            try write("{}", to: file)
            let empty = try file.load()
            #expect(empty == AppState())
        }
    }

    @Test func theContractExampleDecodes() throws {
        try withStateFile { file in
            try write(
                """
                {
                  "seen" : { "PR_kwDOA1" : "2026-09-30T10:12:00Z" },
                  "snoozed" : { "PR_kwDOA2" : { "snoozedAt" : "2026-09-30T09:00:00Z", "updatedAt" : "2026-09-29T17:40:00Z" } },
                  "version" : 1
                }
                """, to: file)
            let loaded = try #require(try file.load())
            #expect(loaded.snoozed["PR_kwDOA2"]?.snoozedAt == date("2026-09-30T09:00:00Z"))
            #expect(loaded.seen?["PR_kwDOA1"] == date("2026-09-30T10:12:00Z"))
        }
    }

    @Test func corruptFileThrows() throws {
        try withStateFile { file in
            try write("{not json", to: file)
            #expect(throws: (any Error).self) { try file.load() }
            try write("[]", to: file)
            #expect(throws: (any Error).self) { try file.load() }
        }
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
