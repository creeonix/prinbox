import Foundation
import Testing

@testable import PrinboxCore

struct FakeRunner: CommandRunning {
    let handler: @Sendable (URL, [String], [String: String]) throws -> CommandOutput

    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
    {
        try handler(executable, arguments, environment)
    }
}

/// Collects the queries a client ran, in order.
final class QueryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func add(_ query: String) -> Int {
        lock.withLock {
            stored.append(query)
            return stored.count
        }
    }

    var queries: [String] { lock.withLock { stored } }
    var detailsQueries: [String] { queries.filter { !$0.hasPrefix("query InboxIDs") } }
}

@Suite struct GhClientTests {
    let gh = GhLocator(overridePath: "/fake/gh", environmentPath: nil, isExecutable: { $0 == "/fake/gh" })

    func client(_ handler: @escaping @Sendable (URL, [String], [String: String]) throws -> CommandOutput) -> GhClient {
        GhClient(locator: gh, runner: FakeRunner(handler: handler))
    }

    static func ok(_ data: Data, stderr: String = "", exitCode: Int32 = 0) -> CommandOutput {
        CommandOutput(exitCode: exitCode, stdout: data, stderr: stderr)
    }

    static func nodes(_ ids: [String]) -> CommandOutput { ok(TwoPhaseJSON.details(ids.map { TwoPhaseJSON.node($0) })) }

    /// Answers the search with `search` and each details query through `details(ids, callNumber)`.
    func twoPhase(
        search: Data, log: QueryLog = QueryLog(),
        details: @escaping @Sendable ([String], Int) throws -> CommandOutput = { ids, _ in nodes(ids) }
    ) -> GhClient {
        client { executable, arguments, environment in
            #expect(executable.path == "/fake/gh")
            #expect(arguments.prefix(3) == ["api", "graphql", "-f"])
            #expect(environment["GH_PROMPT_DISABLED"] == "1")
            let query = String((arguments.last ?? "").dropFirst("query=".count))
            let call = log.add(query)
            if query.hasPrefix("query InboxIDs") { return Self.ok(search) }
            return try details(TwoPhaseJSON.requestedIDs(in: query), call)
        }
    }

    let hits23 = TwoPhaseJSON.search(
        review: (1...3).map { TwoPhaseJSON.hit("r\($0)") }, mentions: (1...5).map { TwoPhaseJSON.hit("m\($0)") },
        mine: (1...15).map { TwoPhaseJSON.hit("o\($0)") })

    @Test func searchesThenFetchesBatchesOfTenInSearchOrder() async throws {
        let log = QueryLog()
        let result = try await twoPhase(search: hits23, log: log).fetch()
        #expect(log.queries.count == 4)
        #expect(log.queries[0].hasPrefix("query InboxIDs"))
        #expect(log.detailsQueries.map { TwoPhaseJSON.requestedIDs(in: $0).count }.sorted() == [3, 10, 10])
        let expected = (1...3).map { "r\($0)" } + (1...5).map { "m\($0)" } + (1...15).map { "o\($0)" }
        #expect(result.pullRequests.map(\.id) == expected)
        #expect(result.pullRequests.first?.source == .review)
        #expect(result.pullRequests.last?.source == .mine)
        #expect(result.totals == [.review: 3, .mentions: 5, .mine: 15])
        #expect(result.fetched == [.review: 3, .mentions: 5, .mine: 15])
        #expect(result.cost == 1 + 3 * 5)
        #expect(result.fingerprint.count == 23)
        #expect(result.fingerprint["r1"] == date(TwoPhaseJSON.updatedAt))
    }

    @Test func unchangedWhenThePreviousFingerprintMatches() async throws {
        let log = QueryLog()
        let client = twoPhase(search: hits23, log: log)
        guard case .result(let first) = try await client.fetch(.full) else {
            Issue.record("expected a result")
            return
        }
        let again = try await client.fetch(FetchRequest(previous: first.fingerprint))
        #expect(again == .unchanged)
        #expect(log.queries.count == 5)
        var moved = first.fingerprint
        moved["r1"] = date("2026-08-01T11:00:00Z")
        guard case .result = try await client.fetch(FetchRequest(previous: moved)) else {
            Issue.record("expected a result")
            return
        }
        #expect(log.queries.count == 9)
    }

    @Test func conversationOffDropsTheInvolvedSearchAndTheThreadFields() async throws {
        let log = QueryLog()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("a")])
        _ = try await twoPhase(search: search, log: log).fetch(FetchRequest(includeConversation: false))
        #expect(!log.queries[0].contains("involved"))
        #expect(!log.queries[1].contains("reviewThreads"))
        _ = try await twoPhase(search: search, log: log).fetch(.full)
        #expect(log.queries[2].contains("involved: search"))
        #expect(log.queries[3].contains("reviewThreads(last: 30)"))
    }

    @Test func aFailingBatchIsRetriedAsTwoHalves() async throws {
        let log = QueryLog()
        let search = TwoPhaseJSON.search(mine: (1...10).map { TwoPhaseJSON.hit("o\($0)") })
        let result = try await twoPhase(search: search, log: log) { ids, call in
            if call == 2 { return Self.ok(Data(), stderr: "gh: HTTP 502", exitCode: 1) }
            return Self.nodes(ids)
        }.fetch()
        #expect(log.detailsQueries.map { TwoPhaseJSON.requestedIDs(in: $0).count }.sorted() == [5, 5, 10])
        #expect(result.pullRequests.count == 10)
        #expect(result.pullRequests.map(\.id) == (1...10).map { "o\($0)" })
    }

    @Test func aLoneIDIsRetriedOnceAsIs() async throws {
        let log = QueryLog()
        let result = try await twoPhase(search: TwoPhaseJSON.search(mine: [TwoPhaseJSON.hit("o1")]), log: log) {
            ids, call in
            if call == 2 { throw CommandRunnerError.timedOut }
            return Self.nodes(ids)
        }.fetch()
        #expect(log.detailsQueries.map { TwoPhaseJSON.requestedIDs(in: $0) } == [["o1"], ["o1"]])
        #expect(result.pullRequests.count == 1)
    }

    @Test func aBatchThatFailsTwiceFailsTheFetch() async {
        let log = QueryLog()
        let search = TwoPhaseJSON.search(mine: (1...4).map { TwoPhaseJSON.hit("o\($0)") })
        await #expect(throws: FetchError.githubUnavailable(status: 502)) {
            try await twoPhase(search: search, log: log) { _, _ in Self.ok(Data(), stderr: "gh: HTTP 502", exitCode: 1)
            }.fetch()
        }
        #expect(log.queries.count == 4)
    }

    @Test func rateLimitLoggedOutAndOfflineAreNotRetried() async {
        for (stderr, exitCode, expected) in [
            ("gh: API rate limit exceeded (HTTP 403)", Int32(1), FetchError.rateLimited(resetAt: nil)),
            ("gh auth login", Int32(4), FetchError.loggedOut),
            ("dial tcp: lookup api.github.com: no such host", Int32(1), FetchError.offline),
        ] {
            let log = QueryLog()
            await #expect(throws: expected) {
                try await twoPhase(search: TwoPhaseJSON.search(mine: [TwoPhaseJSON.hit("o1")]), log: log) { _, _ in
                    Self.ok(Data(), stderr: stderr, exitCode: exitCode)
                }.fetch()
            }
            #expect(log.queries.count == 2, "\(stderr)")
        }
    }

    @Test func rateLimitInABatchBodyPausesWithTheResetTime() async {
        let body = TwoPhaseJSON.details([], errors: [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]])
        await #expect(throws: FetchError.rateLimited(resetAt: date("2026-08-01T13:00:00Z"))) {
            try await twoPhase(search: TwoPhaseJSON.search(mine: [TwoPhaseJSON.hit("o1")])) { _, _ in Self.ok(body) }
                .fetch()
        }
    }

    @Test func mergeSkipsNodesTheBatchesDidNotReturn() async throws {
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("a"), TwoPhaseJSON.hit("b")])
        let body = TwoPhaseJSON.details(
            [TwoPhaseJSON.node("a"), NSNull()],
            errors: [["type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement."]])
        let result = try await twoPhase(search: search) { _, _ in Self.ok(body, stderr: "gh: SAML", exitCode: 1) }
            .fetch()
        #expect(result.pullRequests.map(\.id) == ["a"])
        #expect(result.fetched[.review] == 2)
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
        #expect(!result.isComplete)
    }

    @Test func aDecodableBodyWinsOverA5xxInStderr() async throws {
        let client = client { _, arguments, _ in
            let query = arguments.last ?? ""
            if query.contains("InboxIDs") {
                return Self.ok(TwoPhaseJSON.search(mine: [TwoPhaseJSON.hit("o1")]), stderr: "gh: HTTP 502", exitCode: 1)
            }
            return Self.nodes(["o1"])
        }
        #expect(try await client.fetch().pullRequests.count == 1)
    }

    @Test func partialErrorsOnTheSearchStillReturnData() async throws {
        let search = TwoPhaseJSON.search(
            errors: [["type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement."]])
        let result = try await twoPhase(search: search).fetch()
        #expect(result.pullRequests.isEmpty)
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
    }

    @Test func searchFailuresAreClassified() async {
        await #expect(throws: FetchError.loggedOut) {
            try await client { _, _, _ in Self.ok(Data(), stderr: "gh auth login", exitCode: 4) }.fetch()
        }
        await #expect(throws: FetchError.offline) {
            try await client { _, _, _ in
                Self.ok(Data(), stderr: "dial tcp: lookup api.github.com: no such host", exitCode: 1)
            }.fetch()
        }
        await #expect(throws: FetchError.timedOut) {
            try await client { _, _, _ in throw CommandRunnerError.timedOut }.fetch()
        }
        await #expect(throws: FetchError.other("Could not run gh: bad CPU type in executable")) {
            try await client { _, _, _ in throw CommandRunnerError.launchFailed("bad CPU type in executable") }.fetch()
        }
        await #expect(throws: FetchError.githubUnavailable(status: 503)) {
            try await client { _, _, _ in Self.ok(Data(), stderr: "gh: HTTP 503", exitCode: 1) }.fetch()
        }
    }

    @Test func missingGhIsGhNotFound() async {
        let missing = GhLocator(overridePath: nil, environmentPath: nil, isExecutable: { _ in false })
        await #expect(throws: FetchError.ghNotFound) {
            try await GhClient(locator: missing, runner: FakeRunner { _, _, _ in Self.ok(Data()) }).fetch()
        }
    }

    @Test func garbageOnSuccessIsBadResponse() {
        #expect(throws: FetchError.badResponse) {
            try GhClient.interpretSearch(CommandOutput(exitCode: 0, stdout: Data("not json".utf8), stderr: ""))
        }
        #expect(throws: FetchError.badResponse) {
            try GhClient.interpretDetails(CommandOutput(exitCode: 0, stdout: Data("{}".utf8), stderr: ""))
        }
        #expect(GhClient.isRetryable(.timedOut))
        #expect(GhClient.isRetryable(.githubUnavailable(status: 502)))
        #expect(GhClient.isRetryable(.other("x")))
        #expect(!GhClient.isRetryable(.rateLimited(resetAt: nil)))
        #expect(!GhClient.isRetryable(.offline))
    }

    @Test func fetchWithoutARequestIsAFullFetch() async throws {
        let log = QueryLog()
        let result = try await twoPhase(search: TwoPhaseJSON.search(mine: [TwoPhaseJSON.hit("o1")]), log: log).fetch()
        #expect(result.pullRequests.count == 1)
        #expect(log.queries[0].contains("involved: search"))
    }
}
