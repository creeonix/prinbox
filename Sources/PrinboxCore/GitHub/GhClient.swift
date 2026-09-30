import Foundation
import os

/// What a refresh asks for.
public struct FetchRequest: Sendable, Equatable {
    /// `id -> updatedAt` of the previous fetch. When phase 1 returns the same set, the fetch answers
    /// `.unchanged` without running phase 2. Nil forces a full fetch.
    public let previous: [String: Date]?
    /// Threads and reviews, and the `involved` search behind Replies to you. Off is the lighter refresh.
    public let includeConversation: Bool

    public init(previous: [String: Date]? = nil, includeConversation: Bool = true) {
        self.previous = previous
        self.includeConversation = includeConversation
    }

    public static let full = FetchRequest()
}

public enum FetchOutcome: Sendable, Equatable {
    /// Nothing moved since `previous`; the inbox as built stands.
    case unchanged
    case result(FetchResult)
}

public protocol InboxFetching: Sendable {
    func fetch(_ request: FetchRequest) async throws -> FetchOutcome
}

extension InboxFetching {
    /// A full fetch, for `--print` and tests. Without `previous` a fetcher cannot answer `.unchanged`.
    public func fetch() async throws -> FetchResult {
        switch try await fetch(.full) {
        case .result(let result): return result
        case .unchanged: throw FetchError.badResponse
        }
    }
}

/// Fetches the inbox in two phases through `gh api graphql`: one ids-only request (`SearchQuery`), then rows
/// and conversation for every hit in concurrent batches of 10 (`DetailsQuery`). gh owns authentication;
/// prinbox never sees the token. Failures log gh's stderr (truncated) to the unified log. stdout is never logged.
public struct GhClient: InboxFetching {
    public static let defaultTimeout: Duration = .seconds(30)
    /// Ids per details request. GitHub terminates a request after 10 s; ten heavy PRs with threads measured 3.6 s.
    public static let batchSize = 10
    private static let log = Logger(subsystem: "io.github.creeonix.prinbox", category: "gh")

    private let locator: GhLocator
    private let runner: CommandRunning
    private let timeout: Duration

    public init(
        locator: GhLocator = GhLocator(), runner: CommandRunning = ProcessCommandRunner(),
        timeout: Duration = GhClient.defaultTimeout
    ) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func ghPath() -> String? { locator.locate()?.path }

    /// The `ghPath` override in effect, if any.
    public var ghOverride: String? { locator.overridePath }

    public func fetch(_ request: FetchRequest) async throws -> FetchOutcome {
        guard let gh = locator.locate() else { throw FetchError.ghNotFound }
        let started = ContinuousClock.now
        let search = try Self.interpretSearch(
            try await run(gh, query: SearchQuery.text(includeInvolved: request.includeConversation)))
        let fingerprint = PullRequestMapper.fingerprint(search)
        if let previous = request.previous, previous == fingerprint {
            Self.log.info("fetch unchanged: 1 request, \(search.data?.rateLimit?.cost ?? 0) points")
            return .unchanged
        }
        let ids = PullRequestMapper.orderedIDs(search).map(\.id)
        let batches = stride(from: 0, to: ids.count, by: Self.batchSize).map {
            Array(ids[$0..<min($0 + Self.batchSize, ids.count)])
        }
        let details = try await withThrowingTaskGroup(of: (Int, [DetailsResponse]).self) { group in
            for (index, batch) in batches.enumerated() {
                group.addTask {
                    (
                        index,
                        try await self.fetchDetails(
                            gh, ids: batch, includeConversation: request.includeConversation, maySplit: true)
                    )
                }
            }
            var collected: [(Int, [DetailsResponse])] = []
            for try await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        let result = try PullRequestMapper.merge(search: search, details: details)
        let elapsed = (ContinuousClock.now - started) / .milliseconds(1)
        Self.log.info(
            "fetch: \(1 + details.count) requests, \(result.cost) points, remaining \(search.data?.rateLimit?.remaining ?? -1), \(result.pullRequests.count) PRs, \(Int(elapsed)) ms"
        )
        let truncated = PullRequestMapper.truncatedPages(details)
        if truncated > 0 { Self.log.debug("fetch: \(truncated) thread pages truncated at the page size") }
        return .result(result)
    }

    /// One batch. A failure that may be GitHub's time limit is retried once as two halves (a lone id once as
    /// is); a second failure fails the fetch. Rate limit, auth and network errors fail at once.
    private func fetchDetails(_ gh: URL, ids: [String], includeConversation: Bool, maySplit: Bool) async throws
        -> [DetailsResponse]
    {
        do {
            let output = try await run(gh, query: DetailsQuery.text(ids: ids, includeConversation: includeConversation))
            return [try Self.interpretDetails(output)]
        } catch let error as FetchError where maySplit && Self.isRetryable(error) {
            Self.log.notice(
                "details batch of \(ids.count) failed: \(String(describing: error), privacy: .private); retrying split")
            if ids.count == 1 {
                return try await fetchDetails(gh, ids: ids, includeConversation: includeConversation, maySplit: false)
            }
            try Task.checkCancellation()
            let half = (ids.count + 1) / 2
            async let first = fetchDetails(
                gh, ids: Array(ids[..<half]), includeConversation: includeConversation, maySplit: false)
            async let second = fetchDetails(
                gh, ids: Array(ids[half...]), includeConversation: includeConversation, maySplit: false)
            return try await first + second
        }
    }

    /// Timeouts and 5xx are GitHub failing under load, which a smaller request may get past; `other` is a
    /// failure without a body, which the same bargain covers. Everything else would fail again unchanged.
    static func isRetryable(_ error: FetchError) -> Bool {
        switch error {
        case .timedOut, .githubUnavailable, .other: true
        case .ghNotFound, .loggedOut, .offline, .rateLimited, .badResponse: false
        }
    }

    private func run(_ gh: URL, query: String) async throws -> CommandOutput {
        let output: CommandOutput
        do {
            output = try await runner.run(
                executable: gh, arguments: ["api", "graphql", "-f", "query=\(query)"],
                environment: Self.environment(), timeout: timeout)
        } catch CommandRunnerError.timedOut {
            Self.log.error("gh timed out")
            throw FetchError.timedOut
        } catch CommandRunnerError.launchFailed(let reason) {
            Self.log.error("gh could not be launched: \(reason, privacy: .public)")
            throw FetchError.other("Could not run gh: \(reason)")
        } catch {
            Self.log.error("gh failed to run: \(String(describing: error), privacy: .public)")
            throw FetchError.other("Could not run gh: \(error.localizedDescription)")
        }
        if output.exitCode != 0 {
            Self.log.error("gh exited \(output.exitCode): \(String(output.stderr.prefix(500)), privacy: .private)")
        }
        return output
    }

    /// gh prints the response body even when it exits 1 because of GraphQL errors, so a decodable body is
    /// used first and stderr only explains failures without one.
    static func interpretSearch(_ output: CommandOutput) throws -> SearchResponse {
        if let response = try? SearchResponse.decode(output.stdout), response.data != nil || response.errors != nil {
            let errors = response.errors ?? []
            if GraphQLErrors.isRateLimited(errors) {
                throw FetchError.rateLimited(resetAt: response.data?.rateLimit?.resetAt)
            }
            guard response.data?.viewer?.login != nil else {
                throw errors.first.map { FetchError.other(String($0.message.prefix(120))) } ?? FetchError.badResponse
            }
            return response
        }
        throw failure(output)
    }

    static func interpretDetails(_ output: CommandOutput) throws -> DetailsResponse {
        if let response = try? DetailsResponse.decode(output.stdout), response.data != nil || response.errors != nil {
            let errors = response.errors ?? []
            if GraphQLErrors.isRateLimited(errors) {
                throw FetchError.rateLimited(resetAt: response.data?.rateLimit?.resetAt)
            }
            guard response.data?.nodes != nil else {
                throw errors.first.map { FetchError.other(String($0.message.prefix(120))) } ?? FetchError.badResponse
            }
            return response
        }
        throw failure(output)
    }

    private static func failure(_ output: CommandOutput) -> FetchError {
        output.exitCode == 0
            ? .badResponse : GhErrorClassifier.classify(exitCode: output.exitCode, stderr: output.stderr)
    }

    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        base.merging(["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"]) { _, new in new }
    }
}
