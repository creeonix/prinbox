import Foundation
import Testing

@testable import PrinboxCore

@Suite struct JSONKeyValueFileTests {
    /// A settings file in a fresh temporary directory, removed when `body` returns.
    func withFile(logger: Logging = NullLogging(), _ body: (JSONKeyValueFile, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-kv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try body(JSONKeyValueFile(url: url, logger: logger), url)
    }

    @Test func aMissingFileReadsAsEmpty() throws {
        try withFile { file, _ in
            #expect(file.object(forKey: "compactRows") == nil)
            #expect(!file.fileExists)
        }
    }

    @Test func setWritesPrettyJSONWithSortedKeysAndCreatesTheDirectory() throws {
        try withFile { file, url in
            file.set("/x/gh", forKey: "ghPath")
            file.set(true, forKey: "compactRows")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text == "{\n  \"compactRows\" : true,\n  \"ghPath\" : \"/x/gh\"\n}")
            #expect(file.fileExists)
        }
    }

    @Test func everyValueShapeTheStoresUseRoundTrips() throws {
        try withFile { file, url in
            file.set(true, forKey: "b")
            file.set(["mentions", "yourPRs"], forKey: "strings")
            file.set([35, 3], forKey: "ints")
            file.set(["acme": 0, "globex": 1], forKey: "colors")
            file.set(["tag": "v1", "url": "https://example.com"], forKey: "release")
            file.set("/x/gh", forKey: "s")
            let again = JSONKeyValueFile(url: url)
            #expect(again.object(forKey: "b") as? Bool == true)
            #expect(again.object(forKey: "strings") as? [String] == ["mentions", "yourPRs"])
            #expect(again.object(forKey: "ints") as? [Int] == [35, 3])
            #expect(again.object(forKey: "colors") as? [String: Int] == ["acme": 0, "globex": 1])
            #expect(
                again.object(forKey: "release") as? [String: String] == ["tag": "v1", "url": "https://example.com"])
            #expect(again.object(forKey: "s") as? String == "/x/gh")
        }
    }

    @Test func aWriteReloadsSoAHandEditSurvives() throws {
        try withFile { file, url in
            file.set(1, forKey: "a")
            try Data("{\"a\" : 1, \"hand\" : \"edit\"}".utf8).write(to: url)
            file.set(2, forKey: "b")
            let again = JSONKeyValueFile(url: url)
            #expect(again.object(forKey: "hand") as? String == "edit")
            #expect(again.object(forKey: "b") as? Int == 2)
        }
    }

    @Test func settingNilRemovesTheKey() throws {
        try withFile { file, url in
            file.set(1, forKey: "a")
            file.set(nil, forKey: "a")
            #expect(file.object(forKey: "a") == nil)
            #expect(JSONKeyValueFile(url: url).object(forKey: "a") == nil)
        }
    }

    @Test func anUnreadableFileReadsAsEmptyWithANoticeAndIsReplacedOnWrite() throws {
        let logger = MemoryLogging()
        try withFile(logger: logger) { file, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{not json".utf8).write(to: url)
            let broken = JSONKeyValueFile(url: url, logger: logger)
            #expect(broken.object(forKey: "a") == nil)
            #expect(logger.messages(.notice) == ["settings.json unreadable, treating it as empty"])
            broken.set(true, forKey: "a")
            #expect(JSONKeyValueFile(url: url).object(forKey: "a") as? Bool == true)
        }
    }

    @MainActor
    @Test func wrongTypesFallBackToTheDefault() throws {
        try withFile { file, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"compactRows\" : \"yes\", \"foldedSections\" : 3}".utf8).write(to: url)
            let store = JSONKeyValueFile(url: url)
            let display = DisplaySettings(defaults: store)
            #expect(display.compactRows == false)
            #expect(FoldStore(defaults: store).folded == FoldStore.defaultFolded)
            display.setCompactRows(true)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"compactRows\" : true"))
            #expect(text.contains("\"foldedSections\" : 3"))
        }
    }

    @Test func aValueJSONCannotHoldIsLoggedNotSavedAndNeverCrashes() throws {
        let logger = MemoryLogging()
        try withFile(logger: logger) { file, _ in
            file.set(Date(), forKey: "bad")
            #expect(logger.messages(.error) == ["settings.json not saved"])
            #expect(!file.fileExists)
        }
    }

    @Test func memoryStoreHoldsWhatItIsGiven() {
        let store = MemoryKeyValueStore(initial: ["foldedSections": [String]()])
        #expect(store.object(forKey: "foldedSections") as? [String] == [])
        store.set(true, forKey: "x")
        #expect(store.object(forKey: "x") as? Bool == true)
        store.set(nil, forKey: "x")
        #expect(store.object(forKey: "x") == nil)
    }
}
