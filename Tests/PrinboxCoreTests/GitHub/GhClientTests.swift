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

    func client(
        logger: Logging = NullLogging(),
        _ handler: @escaping @Sendable (URL, [String], [String: String]) throws -> CommandOutput
    ) -> GhClient {
        GhClient(locator: gh, runner: FakeRunner(handler: handler), logger: logger)
    }

    static func ok(_ data: Data, stderr: String = "", exitCode: Int32 = 0) -> CommandOutput {
        CommandOutput(exitCode: exitCode, stdout: data, stderr: stderr)
    }

    static func nodes(_ ids: [String]) -> CommandOutput { ok(TwoPhaseJSON.details(ids.map { TwoPhaseJSON.node($0) })) }

    /// Answers the search with `search` and each details query through `details(ids, callNumber)`.
    func twoPhase(
        search: Data, log: QueryLog = QueryLog(), logger: Logging = NullLogging(),
        details: @escaping @Sendable ([String], Int) throws -> CommandOutput = { ids, _ in nodes(ids) }
    ) -> GhClient {
        client(logger: logger) { executable, arguments, environment in
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

    @Test func unchangedRequiresTheSameViewer() async throws {
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1")])
        let previous = ["PR_1": date(TwoPhaseJSON.updatedAt)]
        let same = try await twoPhase(search: search).fetch(FetchRequest(previous: previous, previousViewer: "me"))
        #expect(same == .unchanged)
        let other = try await twoPhase(search: search).fetch(
            FetchRequest(previous: previous, previousViewer: "someone"))
        guard case .result = other else { return #expect(Bool(false), "a different viewer must fetch in full") }
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

    @Test func theScopeReachesTheSearch() async throws {
        let log = QueryLog()
        let client = twoPhase(search: TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1")]), log: log)
        let scope = SearchScope(
            directReviewRequestsOnly: true, repositories: ["acme", "globex/billing"], hideDrafts: true)
        _ = try await client.fetch(FetchRequest(scope: scope))
        let search = try #require(log.queries.first)
        #expect(search.contains("user-review-requested:@me -is:draft user:acme repo:globex/billing"))
        #expect(FetchRequest(scope: scope).shape == FetchShape(includeConversation: true, scope: scope))
    }

    @Test func aFilterPastTheSearchLimitFailsBeforeAnyRequest() async {
        let log = QueryLog()
        let client = twoPhase(search: TwoPhaseJSON.search(), log: log)
        let scope = SearchScope(
            directReviewRequestsOnly: true, repositories: [String(repeating: "a", count: 129)], hideDrafts: true)
        await #expect(
            throws: FetchError.other("default repositories too long for GitHub search: 1 over the 256-character limit")
        ) {
            try await client.fetch(FetchRequest(scope: scope))
        }
        #expect(log.queries.isEmpty)
    }

    @Test func conversationOffDropsTheThreadFieldsButKeepsTheInvolvedSearch() async throws {
        let log = QueryLog()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("a")])
        _ = try await twoPhase(search: search, log: log).fetch(FetchRequest(includeConversation: false))
        #expect(log.queries[0].contains("involved: search"))
        #expect(!log.queries[1].contains("reviewThreads"))
        _ = try await twoPhase(search: search, log: log).fetch(.full)
        #expect(log.queries[2].contains("involved: search"))
        #expect(log.queries[3].contains("reviewThreads(last: 30)"))
    }

    @Test func aFailingBatchIsRetriedAsTwoHalves() async throws {
        let log = QueryLog()
        let logger = MemoryLogging()
        let search = TwoPhaseJSON.search(mine: (1...10).map { TwoPhaseJSON.hit("o\($0)") })
        let result = try await twoPhase(search: search, log: log, logger: logger) { ids, call in
            if call == 2 { return Self.ok(Data(), stderr: "gh: HTTP 502", exitCode: 1) }
            return Self.nodes(ids)
        }.fetch()
        #expect(log.detailsQueries.map { TwoPhaseJSON.requestedIDs(in: $0).count }.sorted() == [5, 5, 10])
        #expect(result.pullRequests.count == 10)
        #expect(result.pullRequests.map(\.id) == (1...10).map { "o\($0)" })
        let notice = logger.lines.first { $0.level == .notice }
        #expect(notice?.message == "details batch of 10 failed; retrying split")
        #expect(notice?.detail != nil)
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

    @Test func aFetchLogsOneInfoLineAndAnUnchangedCheckAnother() async throws {
        let logger = MemoryLogging()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1")])
        let client = twoPhase(search: search, logger: logger)
        _ = try await client.fetch(.full)
        let fetchLines = logger.messages(.info).filter { $0.hasPrefix("fetch: 2 requests") }
        #expect(fetchLines.count == 1)
        let previous = ["PR_1": date(TwoPhaseJSON.updatedAt)]
        _ = try await client.fetch(FetchRequest(previous: previous))
        #expect(logger.messages(.info).contains { $0.hasPrefix("fetch unchanged: 1 request") })
        #expect(logger.lines.allSatisfy { $0.category == .gh })
    }

    @Test func aNonZeroExitLogsStderrAsThePrivateDetail() async {
        let logger = MemoryLogging()
        let client = client(logger: logger) { _, _, _ in
            CommandOutput(exitCode: 1, stdout: Data(), stderr: "gh: Bad credentials (HTTP 401)\n")
        }
        await #expect(throws: FetchError.loggedOut) { try await client.fetch(.full) }
        let line = logger.lines.first { $0.level == .error }
        #expect(line?.message == "gh exited 1")
        #expect(line?.detail == "gh: Bad credentials (HTTP 401)\n")
    }

    @Test func idsThatAreNotNodeIDsAreDroppedWithANoticeBeforePhaseTwo() async throws {
        let logger = MemoryLogging()
        let log = QueryLog()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1"), TwoPhaseJSON.hit("bad id\"")])
        _ = try await twoPhase(search: search, log: log, logger: logger).fetch(.full)
        #expect(log.detailsQueries.count == 1)
        #expect(TwoPhaseJSON.requestedIDs(in: log.detailsQueries[0]) == ["PR_1"])
        #expect(logger.messages(.notice) == ["dropped 1 ids that are not node ids"])
    }

    @Test func theFetchLineCarriesTheLowestRemainingAcrossEveryResponse() async throws {
        let logger = MemoryLogging()
        let hits = (1...12).map { TwoPhaseJSON.hit("PR_\($0)") }
        let search = TwoPhaseJSON.search(review: hits)
        let client = twoPhase(search: search, logger: logger) { ids, call in
            // The search says 4900; the batches say 4890 and 4895. The lowest is the truth after the fetch.
            var body =
                try JSONSerialization.jsonObject(
                    with: TwoPhaseJSON.details(ids.map { TwoPhaseJSON.node($0) })) as! [String: Any]
            var data = body["data"] as! [String: Any]
            data["rateLimit"] = ["cost": 5, "remaining": call == 2 ? 4890 : 4895, "resetAt": "2026-08-01T13:00:00Z"]
            body["data"] = data
            return Self.ok(try JSONSerialization.data(withJSONObject: body))
        }
        _ = try await client.fetch(.full)
        let line = try #require(logger.messages(.info).first { $0.hasPrefix("fetch: ") })
        #expect(line.contains("remaining 4890"))
    }

    @Test func theUnchangedLineCarriesRemainingAndElapsed() async throws {
        let logger = MemoryLogging()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1")])
        let client = twoPhase(search: search, logger: logger)
        _ = try await client.fetch(FetchRequest(previous: ["PR_1": date(TwoPhaseJSON.updatedAt)]))
        let line = try #require(logger.messages(.info).first { $0.hasPrefix("fetch unchanged: ") })
        #expect(line.contains("remaining 4900"))
        #expect(line.hasSuffix(" ms"))
    }

    @Test func cancellationIsHonoredBeforeTheRetryNotice() async throws {
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var task: Task<FetchOutcome, Error>?
            func set(_ t: Task<FetchOutcome, Error>) { lock.withLock { task = t } }
            func cancel() { lock.withLock { task?.cancel() } }
        }
        let box = Box()
        let logger = MemoryLogging()
        let log = QueryLog()
        let search = TwoPhaseJSON.search(review: [TwoPhaseJSON.hit("PR_1")])
        let client = twoPhase(search: search, log: log, logger: logger) { _, _ in
            box.cancel()
            throw FetchError.timedOut
        }
        let task = Task { try await client.fetch(.full) }
        box.set(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.detailsQueries.count == 1)
        #expect(logger.messages(.notice).isEmpty)
    }

    @Test func remainingTextPrintsAQuestionMarkWhenUnknown() {
        #expect(GhClient.remainingText(nil) == "?")
        #expect(GhClient.remainingText(4890) == "4890")
    }
}
