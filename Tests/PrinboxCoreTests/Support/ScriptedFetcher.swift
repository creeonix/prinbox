@testable import PrinboxCore

/// Fetcher whose answer depends on the call number (1-based).
actor ScriptedFetcher: InboxFetching {
    private(set) var calls = 0
    private let script: @Sendable (Int) async throws -> FetchResult

    init(_ script: @escaping @Sendable (Int) async throws -> FetchResult) { self.script = script }

    func fetch() async throws -> FetchResult {
        calls += 1
        return try await script(calls)
    }
}
