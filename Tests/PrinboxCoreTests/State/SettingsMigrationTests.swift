import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SettingsMigrationTests {
    func withFile(_ body: (JSONKeyValueFile) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(JSONKeyValueFile(url: directory.appendingPathComponent("settings.json")))
    }

    @Test func movesEveryKnownKeyOnceAndClearsTheSource() throws {
        try withFile { file in
            let source = MemoryDefaults()
            source.set(["mentions"], forKey: FoldStore.key)
            source.set(["acme": 2], forKey: OrgColorStore.key)
            source.set(true, forKey: DisplaySettings.compactKey)
            source.set(false, forKey: FetchSettings.key)
            source.set([35, 3], forKey: HotKeySettings.key)
            source.set("/x/gh", forKey: GhLocator.overrideKey)
            source.set("unrelated", forKey: "somethingElse")
            let moved = SettingsMigration.migrate(from: source, to: file)
            #expect(
                Set(moved) == [
                    FoldStore.key, OrgColorStore.key, DisplaySettings.compactKey, FetchSettings.key,
                    HotKeySettings.key, GhLocator.overrideKey,
                ])
            #expect(file.object(forKey: FoldStore.key) as? [String] == ["mentions"])
            #expect(file.object(forKey: GhLocator.overrideKey) as? String == "/x/gh")
            #expect(file.object(forKey: FetchSettings.key) as? Bool == false)
            for key in moved { #expect(source.object(forKey: key) == nil) }
            #expect(source.object(forKey: "somethingElse") as? String == "unrelated")
        }
    }

    @Test func doesNothingWhenTheFileExists() throws {
        try withFile { file in
            file.set(false, forKey: DisplaySettings.compactKey)
            let source = MemoryDefaults()
            source.set(true, forKey: DisplaySettings.compactKey)
            #expect(SettingsMigration.migrate(from: source, to: file) == [])
            #expect(file.object(forKey: DisplaySettings.compactKey) as? Bool == false)
            #expect(source.object(forKey: DisplaySettings.compactKey) as? Bool == true)
        }
    }

    @Test func anEmptySourceCreatesNoFile() throws {
        try withFile { file in
            #expect(SettingsMigration.migrate(from: MemoryDefaults(), to: file) == [])
            #expect(!file.fileExists)
        }
    }

    @Test func theKeyListNamesEveryStore() {
        #expect(SettingsMigration.keys.count == 9)
        #expect(SettingsMigration.keys.contains(NotificationSettings.key))
        #expect(SettingsMigration.keys.contains(DisplaySettings.groupKey))
        #expect(SettingsMigration.keys.contains(DisplaySettings.orgAvatarsKey))
    }
}
