import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxCacheTests {
    let now = date("2026-08-10T12:00:00Z")

    func withCacheFile(logger: Logging = NullLogging(), _ body: (JSONCacheFile, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prinbox-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cache.json")
        try body(JSONCacheFile(url: url, logger: logger), url)
    }

    /// A result with every optional filled, so the round trip exercises every field. `cost` and `fingerprint`
    /// are not stored, so they are left at their defaults here.
    func richResult() -> FetchResult {
        let pr = makePR(
            id: "PR_1", number: 7, title: "Add feature", repository: "acme/web", authorLogin: "alice",
            reviewDecision: .changesRequested, mergeable: .conflicting, ci: .failure,
            viewerReview: ViewerReview(state: "COMMENTED", submittedAt: now), reviewRequestedAt: now,
            readyForReviewAt: now, source: .involved, commentCount: 3, headRef: "feature", baseRef: "main",
            lastCommitAt: now, threads: [thread(comment("bob", now), resolved: true)],
            reviews: [Review(authorLogin: "bob", state: "APPROVED", submittedAt: nil)])
        return FetchResult(
            viewerLogin: "me", pullRequests: [pr], totals: [.review: 1, .involved: 1],
            fetched: [.review: 1, .involved: 1],
            warnings: ["GitHub: partial"])
    }

    func cache(result: FetchResult, attention: [String]? = ["PR_1"], includeConversation: Bool = true) -> InboxCache {
        InboxCache(
            fetchedAt: now, checkedAt: now, includeConversation: includeConversation, viewer: "me",
            fingerprint: ["PR_1": now], attention: attention, result: result)
    }

    @Test func roundTripsThroughTheFile() throws {
        try withCacheFile { file, url in
            let cached = cache(result: richResult())
            file.update { _ in cached }
            #expect(file.load() == cached)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"version\" : 1"))
            #expect(text.contains("\"fetchedAt\" : \"2026-08-10T12:00:00Z\""))
            #expect(!text.contains("\"cost\""))
            #expect(text.contains("\"reviewDecision\" : \"changesRequested\""))
            #expect(text.contains("\"totals\" : {"))
        }
    }

    @Test func anAbsentAttentionStaysAbsent() throws {
        try withCacheFile { file, url in
            file.update { _ in cache(result: richResult(), attention: nil) }
            #expect(file.load()?.attention == nil)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("attention"))
        }
    }

    @Test func aForeignVersionOrGarbageReadsAsNoCache() throws {
        let logger = MemoryLogging()
        try withCacheFile(logger: logger) { file, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"version\" : 2, \"future\" : true}".utf8).write(to: url)
            #expect(file.load() == nil)
            try Data("{\"version\" : 1, \"fetchedAt\" : \"2026-08-10T12:00:00Z\"".utf8).write(to: url)
            #expect(file.load() == nil)
            try Data("[]".utf8).write(to: url)
            #expect(file.load() == nil)
            #expect(logger.messages(.debug) == ["cache.json version 2 ignored"])
            #expect(logger.messages(.notice).count == 2)
            #expect(logger.lines.filter { $0.level == .notice }.allSatisfy { $0.detail != nil })
        }
    }

    @Test func updateReloadsSoACheckedAtBumpKeepsANewerResult() throws {
        try withCacheFile { file, url in
            let writer = JSONCacheFile(url: url)
            file.update { _ in cache(result: makeResult([makePR(id: "PR_old")])) }
            writer.update { _ in cache(result: makeResult([makePR(id: "PR_new")])) }
            file.update { existing in
                guard var next = existing else { return nil }
                next.checkedAt = now + 60
                return next
            }
            let loaded = try #require(file.load())
            #expect(loaded.result.pullRequests.map(\.id) == ["PR_new"])
            #expect(loaded.checkedAt == now + 60)
        }
    }

    @Test func aFailedWriteLogsAnErrorWithThePathKeptPrivate() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(
            "prinbox-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let logger = MemoryLogging()
        let file = JSONCacheFile(url: blocker.appendingPathComponent("cache.json"), logger: logger)
        file.update { _ in cache(result: makeResult([])) }
        let errors = logger.lines.filter { $0.level == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.category == .state)
        #expect(errors.first?.message == "cache.json not saved")
        #expect(errors.first?.detail != nil)
        #expect(file.load() == nil)
    }

    @Test func updateReturningNilWritesNothing() throws {
        try withCacheFile { file, url in
            file.update { _ in nil }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func theFingerprintIsTrustedWithinTheCeilingForTheSameShape() {
        let cached = cache(result: makeResult([]))
        let same = FetchShape(includeConversation: true)
        #expect(cached.trustedFingerprint(now: now + 60, shape: same) == ["PR_1": now])
        #expect(cached.trustedFingerprint(now: now + 15 * 60, shape: same) == nil)
        #expect(cached.trustedFingerprint(now: now + 60, shape: FetchShape(includeConversation: false)) == nil)
        #expect(
            cached.trustedFingerprint(now: now + 60, shape: FetchShape(scope: SearchScope(hideDrafts: true))) == nil)
        #expect(cached.trustedFingerprint(now: now - 60, shape: same) == nil)
        #expect(InboxCache.fingerprintCeiling == 15 * 60)
    }

    @Test func theBaselineIsTrustedWheneverTheShapeMatches() {
        let cached = cache(result: makeResult([]))
        #expect(cached.trustedAttention(shape: FetchShape()) == ["PR_1"])
        #expect(cached.trustedAttention(shape: FetchShape(includeConversation: false)) == nil)
        #expect(cached.trustedAttention(shape: FetchShape(scope: SearchScope(directReviewRequestsOnly: true))) == nil)
        #expect(cache(result: makeResult([]), attention: nil).trustedAttention(shape: FetchShape()) == nil)
    }

    @Test func aScopeRoundTripsAndAFileWithoutOneReadsAsTheEmptyScope() throws {
        try withCacheFile { file, url in
            let scope = SearchScope(directReviewRequestsOnly: true, hideDrafts: true)
            let cached = InboxCache(
                fetchedAt: now, checkedAt: now, includeConversation: true, scope: scope, viewer: "me", fingerprint: [:],
                attention: nil, result: makeResult([]))
            file.update { _ in cached }
            #expect(file.load()?.scope == scope)
            #expect(file.load()?.shape == FetchShape(includeConversation: true, scope: scope))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("\"scope\" : {"))
            #expect(text.contains("\"hideDrafts\" : true"))
            // A 0.5 file is the same object without the scope key.
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            object["scope"] = nil
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            let loaded = try #require(file.load())
            #expect(loaded.scope == .none)
            #expect(loaded.version == 1)
            #expect(loaded.includeConversation == true)
        }
    }

    @Test func memoryCacheCountsWrites() {
        let memory = MemoryCache()
        #expect(memory.load() == nil)
        memory.update { _ in nil }
        #expect(memory.writeCount == 0)
        memory.update { _ in cache(result: makeResult([])) }
        #expect(memory.writeCount == 1)
        #expect(memory.saved?.viewer == "me")
    }

    @Test func updateUnderTheLockWritesAndReleases() throws {
        try withCacheFile { file, url in
            let logger = MemoryLogging()
            let lock = FileLock(
                url: url.deletingLastPathComponent().appendingPathComponent("prinbox.lock"), patience: 0.2,
                logger: logger)
            let locked = JSONCacheFile(url: url, lock: lock, logger: logger)
            locked.update { _ in cache(result: makeResult([makePR(id: "PR_1")])) }
            locked.update { existing in
                guard var next = existing else { return nil }
                next.checkedAt = now + 60
                return next
            }
            #expect(file.load()?.checkedAt == now + 60)
            #expect(logger.lines.isEmpty)
        }
    }
}
