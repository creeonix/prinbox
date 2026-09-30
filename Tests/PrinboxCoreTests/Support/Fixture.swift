import Foundation

@testable import PrinboxCore

/// A recorded two-phase fixture: `{"search": <phase 1 response>, "details": [<one response per batch>]}`.
struct TwoPhaseFixture: Decodable {
    let search: SearchResponse
    let details: [DetailsResponse]
}

enum Fixture {
    /// The fixture recorded from a real account by `scripts/record-fixture.sh` (anonymized).
    static let liveName = "live-2026-10-01"

    /// Loads Tests/PrinboxCoreTests/Fixtures/<name>.json from the source tree (no SwiftPM resources).
    static func data(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    /// Decodes a two-phase fixture and merges it as the client would.
    static func twoPhase(_ name: String) throws -> FetchResult { try twoPhase(data: data(name)) }

    static func twoPhase(data: Data) throws -> FetchResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(TwoPhaseFixture.self, from: data)
        return try PullRequestMapper.merge(search: fixture.search, details: fixture.details)
    }
}
