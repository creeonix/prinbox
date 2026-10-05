import Foundation

/// The stateless orchestration every command call goes through (spec section 7): load the cache and the
/// state, serve or fetch, reconcile snoozes under the lock, compute arrivals for a notifier, write the
/// cache, shape the document. The executable only parses, composes and prints.
public struct InboxRun: Sendable {
    public let context: RunContext

    public init(context: RunContext) { self.context = context }

    static let stateWarning = "prinbox: warning: state.json unreadable, ignoring snoozes"

    /// Rows and their provenance, as a fetch or a served cache gives them.
    private struct Served {
        let result: FetchResult
        let source: String
        let fetchedAt: Date
        let checkedAt: Date
        let error: FetchError?
    }

    // MARK: inbox

    public func inbox(_ options: InboxOptions) async -> RunOutcome {
        let cached = context.cache.load()
        let now = context.clock()
        switch options.cacheMode {
        case .cached:
            guard let cached else {
                return RunOutcome(
                    document: emptyDocument(error: nil), exitCode: 1,
                    stderr: ["prinbox: no cache yet, run prinbox inbox"])
            }
            return outcome(served(cached), exitCode: 0, extra: [])
        case .maxAge(let seconds):
            if let cached, now.timeIntervalSince(cached.checkedAt) <= seconds {
                return outcome(served(cached), exitCode: 0, extra: [])
            }
        case .fetch:
            break
        }
        switch await fetch(cached: cached, notify: options.notify) {
        case .success(let fetched):
            return outcome(fetched, exitCode: 0, extra: [])
        case .failure(let error):
            let exitCode: Int32 = error.needsSetup ? 3 : 1
            let guide = SetupGuide.for(error, ghOverride: context.ghOverride)?.plainText
            guard let cached else {
                return RunOutcome(
                    document: emptyDocument(error: errorInfo(error, lastSuccess: nil)), exitCode: exitCode,
                    stderr: [stderrLine(error, lastSuccess: nil)], setupGuide: guide)
            }
            let fallback = Served(
                result: cached.result, source: "cache", fetchedAt: cached.fetchedAt, checkedAt: cached.checkedAt,
                error: error)
            return outcome(
                fallback, exitCode: exitCode, extra: [stderrLine(error, lastSuccess: cached.checkedAt)],
                setupGuide: guide)
        }
    }

    private func served(_ cached: InboxCache) -> Served {
        Served(
            result: cached.result, source: "cache", fetchedAt: cached.fetchedAt, checkedAt: cached.checkedAt, error: nil
        )
    }

    /// The request shape this run fetches under; the cache is trusted for it alone.
    private var shape: FetchShape { FetchShape(includeConversation: context.followReviewThreads, scope: context.scope) }

    /// Phase 1 with the cached fingerprint when trusted. `.unchanged` serves the cached result and bumps
    /// `checkedAt`; a result reconciles the state and replaces the cache. With `--notify` both branches announce
    /// arrivals against the cached baseline and advance it, so what a poller fetched (refreshing the fingerprint,
    /// so the notifier gets `.unchanged`) is still announced. A run without `--notify` keeps the `attention` it
    /// finds in the cache at write time, so a poller never eats an arrival nor undoes a notifier's advance.
    private func fetch(cached: InboxCache?, notify: Bool) async -> Result<Served, FetchError> {
        let now = context.clock()
        let shape = self.shape
        let previous = cached?.trustedFingerprint(now: now, shape: shape)
        let request = FetchRequest(
            previous: previous, includeConversation: shape.includeConversation,
            previousViewer: previous == nil ? nil : cached?.viewer, scope: shape.scope)
        do {
            switch try await context.fetcher.fetch(request) {
            case .unchanged:
                guard let cached else { return .failure(.badResponse) }
                var attention: [String]?
                if notify {
                    let (state, _) = loadStateForReading()
                    let snoozed = Set(Snooze.reconcile(state.snoozed, with: cached.result).keys)
                    attention = await announce(
                        InboxBuilder.build(cached.result, snoozed: snoozed), complete: cached.result.isComplete,
                        baseline: cached.trustedAttention(shape: shape))
                }
                context.cache.update { existing in
                    // Spec 7.3: stamp only the cache this check confirmed; a notifier's baseline advance is
                    // dropped with it, and announced again next time (two notifiers are unsupported anyway).
                    guard var next = existing, next.shape == shape, next.fingerprint == previous else { return nil }
                    next.checkedAt = now
                    if let attention { next.attention = attention }
                    return next
                }
                return .success(
                    Served(
                        result: cached.result, source: "unchanged", fetchedAt: cached.fetchedAt, checkedAt: now,
                        error: nil))
            case .result(let result):
                let inbox = InboxBuilder.build(result, snoozed: reconcile(result))
                var attention: [String]?
                if notify {
                    attention = await announce(
                        inbox, complete: result.isComplete, baseline: cached?.trustedAttention(shape: shape))
                }
                context.cache.update { existing in
                    InboxCache(
                        fetchedAt: now, checkedAt: now, includeConversation: shape.includeConversation,
                        scope: shape.scope,
                        viewer: result.viewerLogin, fingerprint: result.fingerprint,
                        attention: notify ? attention : (existing?.shape == shape ? existing?.attention : nil),
                        result: result)
                }
                return .success(Served(result: result, source: "fetch", fetchedAt: now, checkedAt: now, error: nil))
            }
        } catch let error as FetchError {
            return .failure(error)
        } catch {
            return .failure(.other(String(String(describing: error).prefix(120))))
        }
    }

    /// Delivers the rows that entered an attention section since `baseline`, and returns the advanced baseline.
    private func announce(_ inbox: Inbox, complete: Bool, baseline: Set<String>?) async -> [String] {
        let arrived = Arrivals.compute(previous: baseline, current: inbox)
        if let notice = ArrivalNotice.make(arrived) { await context.delivery.deliver(notice) }
        return Arrivals.baseline(after: inbox, complete: complete, extending: baseline).sorted()
    }

    /// Wakes and prunes snoozes against a fresh result, under the lock, and returns the ids still parked.
    /// The command never touches the seen ledger; an unreadable file is left alone and snoozes are ignored.
    private func reconcile(_ result: FetchResult) -> Set<String> {
        locked {
            guard let state = loadState() else { return [] }
            var next = state
            next.snoozed = Snooze.reconcile(state.snoozed, with: result)
            if next != state {
                do {
                    try context.persistence.save(next)
                } catch {
                    context.logger.error(.cli, "state.json not saved", private: String(describing: error))
                }
            }
            return Set(next.snoozed.keys)
        }
    }

    // MARK: Document

    private func outcome(_ served: Served, exitCode: Int32, extra: [String], setupGuide: String? = nil) -> RunOutcome {
        let (state, warning) = loadStateForReading()
        let snoozed = Set(Snooze.reconcile(state.snoozed, with: served.result).keys)
        let inbox = InboxBuilder.build(served.result, snoozed: snoozed)
        let meta = DocumentMeta(
            prinbox: context.version, source: served.source, fetchedAt: served.fetchedAt, checkedAt: served.checkedAt,
            viewer: served.result.viewerLogin, error: served.error.map { errorInfo($0, lastSuccess: served.checkedAt) })
        let document = InboxDocument.make(inbox, meta: meta, isNew: state.isNew, now: context.clock())
        return RunOutcome(
            document: document, exitCode: exitCode, stderr: extra + (warning ? [Self.stateWarning] : []),
            setupGuide: setupGuide)
    }

    private func emptyDocument(error: InboxDocument.ErrorInfo?) -> InboxDocument {
        let meta = DocumentMeta(
            prinbox: context.version, source: nil, fetchedAt: nil, checkedAt: nil, viewer: nil, error: error)
        return InboxDocument.make(nil, meta: meta, isNew: { _ in false }, now: context.clock())
    }

    private func errorInfo(_ error: FetchError, lastSuccess: Date?) -> InboxDocument.ErrorInfo {
        if let guide = SetupGuide.for(error, ghOverride: context.ghOverride) {
            return InboxDocument.ErrorInfo(code: error.code, message: guide.title, help: guide.link?.url)
        }
        return InboxDocument.ErrorInfo(
            code: error.code, message: error.message(lastSuccess: lastSuccess), help: error.helpURL)
    }

    private func stderrLine(_ error: FetchError, lastSuccess: Date?) -> String {
        if let guide = SetupGuide.for(error, ghOverride: context.ghOverride) { return guide.plainText }
        let link = error.helpURL.map { " (\($0.absoluteString))" } ?? ""
        return "prinbox: \(error.message(lastSuccess: lastSuccess))\(link)"
    }

    // MARK: State

    /// Nil when the file is unreadable: a writer must not replace it, a reader ignores snoozes.
    private func loadState() -> AppState? {
        do {
            return try context.persistence.load() ?? AppState()
        } catch {
            return nil
        }
    }

    private func loadStateForReading() -> (AppState, warning: Bool) {
        loadState().map { ($0, false) } ?? (AppState(), true)
    }

    private func locked<T>(_ body: () -> T) -> T {
        context.lock.map { $0.withLock(body) } ?? body()
    }

    /// Reload, apply, replace under the lock; nothing is written when the change changed nothing.
    private func writeState(_ change: (inout AppState) -> Void) -> CommandOutcome {
        locked {
            guard let state = loadState() else {
                return CommandOutcome(exitCode: 1, stderr: ["prinbox: state.json is unreadable, nothing written"])
            }
            var next = state
            change(&next)
            guard next != state else { return CommandOutcome(exitCode: 0, stderr: []) }
            do {
                try context.persistence.save(next)
                return CommandOutcome(exitCode: 0, stderr: [])
            } catch {
                return CommandOutcome(
                    exitCode: 1, stderr: ["prinbox: state.json not saved: \(String(describing: error))"])
            }
        }
    }

    // MARK: Commands

    public func snooze(id: String) async -> CommandOutcome {
        let pr: PullRequest
        switch await find(id) {
        case .failure(let error):
            return CommandOutcome(exitCode: error.needsSetup ? 3 : 1, stderr: [stderrLine(error, lastSuccess: nil)])
        case .success(nil):
            return CommandOutcome(exitCode: 1, stderr: ["prinbox: \(id) is not in your inbox"])
        case .success(let found?):
            pr = found
        }
        let now = context.clock()
        let written = writeState { state in
            guard state.snoozed[id] == nil else { return }
            state.snoozed[id] = SnoozeEntry(snoozedAt: now, updatedAt: pr.updatedAt)
        }
        return CommandOutcome(exitCode: written.exitCode, stderr: written.stderr, pullRequest: pr)
    }

    /// Idempotent; the cached row, when there is one, rides along for the server's report.
    public func unsnooze(id: String) -> CommandOutcome {
        let written = writeState { $0.snoozed[id] = nil }
        let pr = context.cache.load()?.result.pullRequests.first { $0.id == id }
        return CommandOutcome(exitCode: written.exitCode, stderr: written.stderr, pullRequest: pr)
    }

    public func open(id: String) async -> CommandOutcome {
        switch await find(id) {
        case .failure(let error):
            return CommandOutcome(exitCode: error.needsSetup ? 3 : 1, stderr: [stderrLine(error, lastSuccess: nil)])
        case .success(nil):
            return CommandOutcome(exitCode: 1, stderr: ["prinbox: \(id) is not in your inbox"])
        case .success(let found?):
            await context.opener.open(found.url)
            return CommandOutcome(exitCode: 0, stderr: [], pullRequest: found)
        }
    }

    /// The PR from the cache, or after one fetch without notifying when it is not there.
    private func find(_ id: String) async -> Result<PullRequest?, FetchError> {
        let cached = context.cache.load()
        if let pr = cached?.result.pullRequests.first(where: { $0.id == id }) { return .success(pr) }
        return await fetch(cached: cached, notify: false).map { $0.result.pullRequests.first { $0.id == id } }
    }

    // MARK: print

    /// Today's `--print`: a full fetch with the conversation on, snoozes read-only, nothing written.
    public func printInbox() async -> (stdout: String, stderr: [String], exitCode: Int32) {
        do {
            guard case .result(let result) = try await context.fetcher.fetch(FetchRequest(scope: context.scope)) else {
                throw FetchError.badResponse
            }
            let (state, warning) = loadStateForReading()
            let inbox = InboxBuilder.build(result, snoozed: Set(Snooze.reconcile(state.snoozed, with: result).keys))
            return (InboxPrinter.render(inbox, now: context.clock()), warning ? [Self.stateWarning] : [], 0)
        } catch let error as FetchError {
            return ("", [stderrLine(error, lastSuccess: nil)], error.needsSetup ? 3 : 1)
        } catch {
            return ("", ["prinbox: \(error)"], 1)
        }
    }
}
