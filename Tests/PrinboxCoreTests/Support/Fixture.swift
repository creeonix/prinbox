import Foundation

enum Fixture {
    /// Loads Tests/PrinboxCoreTests/Fixtures/<name>.json from the source tree (no SwiftPM resources).
    static func data(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }
}
