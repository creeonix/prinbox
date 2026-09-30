@testable import PrinboxCore

/// Fetcher whose answer depends on the call number (1-based). The simple form answers full results; the
/// `outcomes` form sees the request and can answer `.unchanged`. Every request is recorded.
actor ScriptedFetcher: InboxFetching {
    private(set) var calls = 0
    private(set) var requests: [FetchRequest] = []
    private let script: @Sendable (Int, FetchRequest) async throws -> FetchOutcome

    init(_ script: @escaping @Sendable (Int) async throws -> FetchResult) {
        self.script = { call, _ in .result(try await script(call)) }
    }

    init(outcomes script: @escaping @Sendable (Int, FetchRequest) async throws -> FetchOutcome) {
        self.script = script
    }

    func fetch(_ request: FetchRequest) async throws -> FetchOutcome {
        calls += 1
        requests.append(request)
        return try await script(calls, request)
    }
}
