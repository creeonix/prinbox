import Foundation
import Observation

/// The persisted global shortcut. `spec == nil` means the user removed it.
@MainActor
@Observable
public final class HotKeySettings {
    public nonisolated static let key = "globalShortcut"

    public private(set) var spec: HotKeySpec?
    /// Set by the app when registration fails, typically because another app owns the shortcut.
    public var isUnavailable = false

    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.key) as? [Int] {
            spec = HotKeySpec(storedValue: stored)
        } else {
            spec = .default
        }
    }

    public func update(_ spec: HotKeySpec?) {
        self.spec = spec
        defaults.set(spec?.storedValue ?? [], forKey: Self.key)
    }
}
