import Foundation

/// The one-time move of every setting out of UserDefaults into `settings.json` (0.5.0). Runs only when the
/// file does not exist yet; a launch that finds the file never looks at defaults again.
public enum SettingsMigration {
    public static let keys = [
        FoldStore.key, OrgColorStore.key, DisplaySettings.groupKey, DisplaySettings.orgAvatarsKey,
        DisplaySettings.compactKey, FetchSettings.key, NotificationSettings.key, HotKeySettings.key,
        GhLocator.overrideKey,
    ]

    /// The update check's two keys now live in update.json; they are cleared from defaults, not copied.
    public static let obsoleteKeys = [UpdateStore.checkedAtKey, UpdateStore.latestReleaseKey]

    /// Clears the obsolete keys from `source`, copies every known key it holds into `file`, then removes the
    /// copies from `source`. A write that failed leaves the file missing: no copied key is removed and the next
    /// launch retries. Returns the keys moved.
    public static func migrate(from source: KeyValueStoring, to file: JSONKeyValueFile) -> [String] {
        guard !file.fileExists else { return [] }
        for key in obsoleteKeys { source.set(nil, forKey: key) }
        var copied: [String] = []
        for key in keys {
            guard let value = source.object(forKey: key) else { continue }
            file.set(value, forKey: key)
            copied.append(key)
        }
        guard file.fileExists else { return [] }
        for key in copied { source.set(nil, forKey: key) }
        return copied
    }
}
