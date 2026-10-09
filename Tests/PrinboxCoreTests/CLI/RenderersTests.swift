import Foundation
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct RenderersTests {
    let now = date("2026-08-10T12:00:00Z")

    /// The demo inbox as the command would document it, with the demo's seen ledger and snooze.
    func demoDocument(error: InboxDocument.ErrorInfo? = nil, source: String? = "fetch") async throws -> InboxDocument {
        let clock = now
        let fetcher = DemoFetcher(now: { clock })
        let result = try await fetcher.fetch()
        let state = fetcher.initialState
        let inbox = InboxBuilder.build(result, snoozed: Set(state.snoozed.keys))
        let meta = DocumentMeta(
            prinbox: "0.5.0-test", source: source, fetchedAt: now, checkedAt: now, viewer: "me", error: error)
        return InboxDocument.make(
            inbox, meta: meta,
            isNew: state.isNew, now: now
        )
    }

    func golden(_ name: String, ext: String = "json") throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Golden/\(name).\(ext)")
        return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .newlines)
    }

    @Test func jsonMatchesTheGoldenFile() async throws {
        let rendered = InboxJSON.render(try await demoDocument())
        let expected = try golden("demo-inbox")
        #expect(rendered == expected)
    }

    @Test func jsonWritesNullsAndSortedKeys() async throws {
        let document = try await demoDocument()
        let text = InboxJSON.render(document)
        #expect(text.contains("\"error\" : null"))
        #expect(text.contains("\"stack\" : null"))
        #expect(text.contains("\"parentId\" : null"))
        #expect(text.contains("\"review\" : null"))
        #expect(text.hasPrefix("{\n  \"badge\" : 8,"))
        #expect(text.contains("\"url\" : \"https://github.com/acme/web/pull/1290\""))
    }

    @Test func linesAreTabSeparatedInDisplayOrderWithMoreLines() async throws {
        let text = InboxLines.render(try await demoDocument())
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(lines.count == 17)
        let first = lines[0].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(first.count == 9)
        #expect(first[0] == "DEMO_1290")
        #expect(first[1] == "needsReview")
        #expect(first[2] == "1290")
        #expect(first[3] == "Migrate the settings page to the new design system")
        #expect(first[4] == "acme/web")
        #expect(first[5] == "Review requested")
        #expect(first[6] == "2d")
        #expect(first[7] == "stack 1/2")
        #expect(first[8] == "https://github.com/acme/web/pull/1290")
        let new = lines[2].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(new[0] == "DEMO_2104")
        #expect(new[7] == "new")
        let snoozed = try #require(lines.last?.split(separator: "\t", omittingEmptySubsequences: false))
        #expect(snoozed[0] == "DEMO_1284")
        #expect(snoozed[7] == "snoozed")
    }

    @Test func linesAddAMoreLinePerCappedSection() {
        let prs = (1...10).map {
            makePR(id: "PR_\($0)", number: $0, reviewRequestedAt: date("2026-08-0\($0 % 9 + 1)T10:00:00Z"))
        }
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult(prs)), meta: meta, isNew: { _ in false }, now: now)
        let lines = InboxLines.render(document).split(separator: "\n")
        #expect(lines.count == 9)
        let more = lines[8].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(more[0] == "more:needsReview")
        #expect(more[1] == "needsReview")
        #expect(more[3] == "+2 more on GitHub")
        #expect(more[8] == "https://github.com/pulls/review-requested")
    }

    @Test func emptyInboxRendersNoLines() {
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        #expect(
            InboxLines.render(
                InboxDocument.make(InboxBuilder.build(makeResult([])), meta: meta, isNew: { _ in false }, now: now))
                == "")
    }

    func waybar(_ document: InboxDocument) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(InboxWaybar.render(document).utf8)) as? [String: Any])
    }

    @Test func waybarWaitingWithNewRows() async throws {
        let object = try waybar(try await demoDocument())
        #expect(object["text"] as? String == "8")
        #expect(object["alt"] as? String == "waiting")
        #expect(object["class"] as? [String] == ["waiting", "new"])
        let tooltip = try #require(object["tooltip"] as? String)
        #expect(
            tooltip.hasPrefix(
                "Needs your review (5)\n#1290 Migrate the settings page to the new design system · acme/web · 2d\n"))
        #expect(tooltip.contains("\nWaiting on others (4)\n"))
    }

    @Test func waybarIdleErrorAndSetup() async throws {
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        let idle = try waybar(
            InboxDocument.make(InboxBuilder.build(makeResult([])), meta: meta, isNew: { _ in false }, now: now))
        #expect(idle["text"] as? String == "")
        #expect(idle["alt"] as? String == "idle")
        #expect(idle["class"] as? [String] == ["idle"])
        let offline = InboxDocument.ErrorInfo(code: "offline", message: "Offline, showing data from 11:00", help: nil)
        let cached = try waybar(try await demoDocument(error: offline, source: "cache"))
        #expect(cached["text"] as? String == "8")
        #expect(cached["alt"] as? String == "error")
        #expect(cached["class"] as? [String] == ["waiting", "new", "error"])
        #expect((cached["tooltip"] as? String)?.hasPrefix("Offline, showing data from 11:00\n") == true)
        let setup = InboxDocument.ErrorInfo(code: "loggedOut", message: "Sign in to the GitHub CLI", help: nil)
        let empty = DocumentMeta(prinbox: "x", source: nil, fetchedAt: nil, checkedAt: nil, viewer: nil, error: setup)
        let bare = try waybar(InboxDocument.make(nil, meta: empty, isNew: { _ in false }, now: now))
        #expect(bare["text"] as? String == "!")
        #expect(bare["alt"] as? String == "setup")
        #expect(bare["class"] as? [String] == ["idle", "setup"])
        #expect(bare["tooltip"] as? String == "Sign in to the GitHub CLI")
    }

    @Test func waybarEscapesPangoMarkup() throws {
        let pr = makePR(title: "Handle <script> & \"quotes\"", reviewRequestedAt: date("2026-08-10T10:00:00Z"))
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        let object = try waybar(
            InboxDocument.make(InboxBuilder.build(makeResult([pr])), meta: meta, isNew: { _ in false }, now: now))
        #expect(
            (object["tooltip"] as? String)?.contains("#1 Handle &lt;script&gt; &amp; \"quotes\" · acme/web · 2h")
                == true)
        #expect(InboxWaybar.escape("a & b < c > d") == "a &amp; b &lt; c &gt; d")
    }

    @Test func linesAndTheWaybarTooltipFlattenTheTitle() throws {
        let pr = makePR(title: "a\tb\nc", reviewRequestedAt: date("2026-08-10T10:00:00Z"))
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([pr])), meta: meta, isNew: { _ in false }, now: now)
        let lines = InboxLines.render(document).split(separator: "\n")
        #expect(lines.count == 1)
        let fields = lines[0].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(fields.count == 9)
        #expect(fields[3] == "a b c")
        let tooltip = try #require(try waybar(document)["tooltip"] as? String)
        #expect(tooltip.contains("\n#1 a b c · acme/web · "))
        #expect(document.sections.flatMap(\.rows).first?.title == "a\tb\nc")
    }

    @Test func tmuxMirrorsTheIcon() async throws {
        #expect(InboxTmux.render(try await demoDocument()) == "8")
        let meta = DocumentMeta(prinbox: "x", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        #expect(
            InboxTmux.render(
                InboxDocument.make(InboxBuilder.build(makeResult([])), meta: meta, isNew: { _ in false }, now: now))
                == "")
        let offline = InboxDocument.ErrorInfo(code: "offline", message: "Offline", help: nil)
        #expect(InboxTmux.render(try await demoDocument(error: offline, source: "cache")) == "!8")
        let empty = DocumentMeta(prinbox: "x", source: nil, fetchedAt: nil, checkedAt: nil, viewer: nil, error: offline)
        #expect(InboxTmux.render(InboxDocument.make(nil, meta: empty, isNew: { _ in false }, now: now)) == "!")
    }

    @Test func linesMatchTheGoldenFile() async throws {
        let rendered = InboxLines.render(try await demoDocument()).trimmingCharacters(in: .newlines)
        let expected = try golden("demo-inbox", ext: "lines")
        #expect(rendered == expected)
    }

    /// The two failure documents the adapter stub serves: a signed-out run without a cache, and a failed fetch over
    /// the demo cache. The error is `timedOut`, whose text carries no clock time, so the file is the same in every
    /// time zone.
    @Test func theSetupNeededAndFetchFailedDocumentsMatchTheirGoldenFiles() async throws {
        let clock = now
        let signedOut = await InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }, clock: { clock })
        )
        .inbox(InboxOptions())
        #expect(signedOut.exitCode == 3)
        let setupNeeded = try golden("setup-needed")
        #expect(InboxJSON.render(signedOut.document) == setupNeeded)
        let fetcher = DemoFetcher(now: { clock })
        let result = try await fetcher.fetch()
        let cache = MemoryCache(
            InboxCache(
                fetchedAt: now, checkedAt: now, includeConversation: true, viewer: "me", fingerprint: [:],
                attention: nil, result: result))
        let failed = await InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in throw FetchError.timedOut }, cache: cache,
                persistence: MemoryStatePersistence(fetcher.initialState), clock: { clock })
        )
        .inbox(InboxOptions())
        #expect(failed.exitCode == 1)
        #expect(failed.document.error?.message == "GitHub did not answer in time")
        let fetchFailed = try golden("fetch-failed")
        #expect(InboxJSON.render(failed.document) == fetchFailed)
    }

    /// The document `prinbox inbox --cached` prints before any fetch: exit 1, no rows, no error, the stderr line.
    @Test func theNoCacheDocumentMatchesItsGoldenFile() async throws {
        let clock = now
        let outcome = await InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) }, clock: { clock })
        )
        .inbox(InboxOptions(cacheMode: .cached))
        #expect(outcome.exitCode == 1)
        #expect(outcome.stderr == ["prinbox: no cache yet, run prinbox inbox"])
        let noCache = try golden("no-cache")
        #expect(InboxJSON.render(outcome.document) == noCache)
    }

    @Test func linesOpenTheDeltaWhenTheDiffMovedSinceYourVerdict() {
        let approved = ViewerReview(state: "APPROVED", submittedAt: nil, commitOid: "aaa")
        let moved = makePR(
            id: "m", number: 3, repository: "acme/api", viewerReview: approved, source: .involved, headOid: "ccc",
            viewerVerdict: approved)
        let meta = DocumentMeta(prinbox: "t", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil)
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([moved, makePR(id: "p")])), meta: meta, isNew: { _ in false }, now: now)
        let lines = InboxLines.render(document).split(separator: "\n").map(String.init)
        #expect(lines[0].hasSuffix("\thttps://github.com/acme/web/pull/1"))
        #expect(lines[1].hasSuffix("\thttps://github.com/acme/api/pull/3/files/aaa..ccc"))
    }
}
