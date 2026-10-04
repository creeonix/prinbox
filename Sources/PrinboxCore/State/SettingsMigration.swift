import Foundation

/// The one-time move of every setting out of UserDefaults into `settings.json` (0.5.0). Runs only when the
/// file does not exist yet; a launch that finds the file never looks at defaults again.
public enum SettingsMigration {
    public static let keys = [
        FoldStore.key, OrgColorStore.key, DisplaySettings.groupKey, DisplaySettings.orgAvatarsKey,
        DisplaySettings.compactKey, FetchSettings.key, NotificationSettings.key, HotKeySettings.key,
        GhLocator.overrideKey,
    ]

    /// Copies every known key `source` holds into `file` and removes it from `source`. Returns the keys moved.
    public static func migrate(from source: KeyValueStoring, to file: JSONKeyValueFile) -> [String] {
        guard !file.fileExists else { return [] }
        var moved: [String] = []
        for key in keys {
            guard let value = source.object(forKey: key) else { continue }
            file.set(value, forKey: key)
            source.set(nil, forKey: key)
            moved.append(key)
        }
        return moved
    }
}
