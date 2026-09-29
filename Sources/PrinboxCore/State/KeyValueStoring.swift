import Foundation

/// The part of `UserDefaults` prinbox uses. Tests substitute an in-memory store.
public protocol KeyValueStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}
