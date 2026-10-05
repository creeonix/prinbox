@testable import PrinboxCore

final class MemoryDefaults: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? { storage[defaultName] }

    func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }

    var isEmpty: Bool { storage.isEmpty }
}
