import Foundation
import Testing

@testable import PrinboxCore

@Suite struct MCPToolsTests {
    let start = date("2026-08-10T12:00:00Z")
    let pr1 = makePR(id: "PR_1", number: 1, title: "Add feature", reviewRequestedAt: date("2026-08-10T08:00:00Z"))

    func cached(_ prs: [PullRequest], checkedAt: Date? = nil) -> InboxCache {
        InboxCache(
            fetchedAt: start - 120, checkedAt: checkedAt ?? start - 30, includeConversation: true, viewer: testViewer,
            fingerprint: Dictionary(prs.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { _, new in new }),
            attention: nil, result: makeResult(prs))
    }

    func invalidParams(_ name: String, _ arguments: JSONValue?, run: InboxRun) async -> String? {
        do {
            _ = try await MCPTools.call(name, arguments: arguments, run: run)
            return nil
        } catch let error as JSONRPCError {
            return error.code == -32602 ? error.message : "wrong code \(error.code)"
        } catch {
            return "wrong error type"
        }
    }

    @Test func definitionsNameTheThreeToolsWithTheirSchemas() {
        guard case .array(let tools) = MCPTools.definitions else {
            Issue.record("definitions is not an array")
            return
        }
        #expect(tools.map { $0["name"] } == ["get_inbox", "snooze_pull_request", "unsnooze_pull_request"])
        let inbox = tools[0]["inputSchema"]
        #expect(inbox?["properties"]?["max_age_seconds"]?["type"] == "integer")
        #expect(inbox?["properties"]?["max_age_seconds"]?["minimum"] == 0)
        #expect(inbox?["additionalProperties"] == false)
        #expect(inbox?["required"] == nil)
        for tool in tools.dropFirst() {
            #expect(tool["inputSchema"]?["required"] == ["id"])
            #expect(tool["inputSchema"]?["properties"]?["id"]?["pattern"] == "^[A-Za-z0-9_=-]+$")
            #expect(tool["inputSchema"]?["additionalProperties"] == false)
        }
        #expect(tools[0]["description"]?.stringValue?.contains("docs/inbox-json.md") == true)
        #expect(tools[0]["description"]?.stringValue?.contains("60 seconds") == true)
        #expect(tools[1]["description"]?.stringValue?.contains("Idempotent") == true)
    }

    @Test func getInboxServesTheCacheByDefaultAndFetchesAtZero() async throws {
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let run = InboxRun(context: makeContext(fetcher: fetcher, cache: MemoryCache(cached([pr1]))))
        let served = try await MCPTools.call("get_inbox", arguments: nil, run: run)
        #expect(await fetcher.calls == 0)
        #expect(served.isError == false)
        #expect(served.content.count == 1)
        #expect(served.structuredContent?["source"] == "cache")
        #expect(served.structuredContent?["badge"] == 1)
        let document = try JSONDecoder().decode(JSONValue.self, from: Data(served.content[0].utf8))
        #expect(document == served.structuredContent)
        #expect(served.json["content"]?[0]?["type"] == "text")
        #expect(served.json["isError"] == false)
        let fresh = try await MCPTools.call("get_inbox", arguments: ["max_age_seconds": 0], run: run)
        #expect(await fetcher.calls == 1)
        #expect(fresh.structuredContent?["source"] == "fetch")
    }

    @Test func maxAgeAcceptsWholeNumbersOnly() async throws {
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let run = InboxRun(
            context: makeContext(fetcher: fetcher, cache: MemoryCache(cached([pr1], checkedAt: start - 90))))
        let whole = try await MCPTools.call("get_inbox", arguments: ["max_age_seconds": .double(120.0)], run: run)
        #expect(whole.structuredContent?["source"] == "cache")
        #expect(await fetcher.calls == 0)
        #expect(
            await invalidParams("get_inbox", ["max_age_seconds": .double(1.5)], run: run)
                == "max_age_seconds must be an integer of 0 or more")
        #expect(
            await invalidParams("get_inbox", ["max_age_seconds": -1], run: run)
                == "max_age_seconds must be an integer of 0 or more")
        #expect(
            await invalidParams("get_inbox", ["max_age_seconds": "60"], run: run)
                == "max_age_seconds must be an integer of 0 or more")
        #expect(await invalidParams("get_inbox", ["seconds": 5], run: run) == "unknown argument 'seconds'")
        #expect(await invalidParams("get_inbox", .array([]), run: run) == "arguments must be an object")
        #expect(await invalidParams("get_everything", nil, run: run) == "unknown tool 'get_everything'")
    }

    @Test func aFailedFetchIsAnErrorThatStillCarriesTheRows() async throws {
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in throw FetchError.offline }, cache: MemoryCache(cached([pr1]))))
        let result = try await MCPTools.call("get_inbox", arguments: ["max_age_seconds": 0], run: run)
        #expect(result.isError)
        #expect(result.content.count == 1)
        #expect(result.structuredContent?["error"]?["code"] == "offline")
        #expect(result.structuredContent?["source"] == "cache")
        #expect(result.structuredContent?["sections"]?[0]?["rows"]?[0]?["id"] == "PR_1")
    }

    @Test func aServedCacheIsNeverAnErrorEvenAfterAFailedFetch() async throws {
        let logger = MemoryLogging()
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in throw FetchError.offline }, cache: MemoryCache(cached([pr1])),
                logger: logger))
        let served = try await MCPTools.call("get_inbox", arguments: nil, run: run)
        #expect(served.isError == false)
        #expect(served.structuredContent?["error"] == .null)
        #expect(logger.messages(.notice).isEmpty)
    }

    @Test func setupNeededAddsTheGuideAsASecondBlock() async throws {
        let logger = MemoryLogging()
        let run = InboxRun(
            context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }, logger: logger))
        let result = try await MCPTools.call("get_inbox", arguments: nil, run: run)
        #expect(result.isError)
        #expect(result.content.count == 2)
        #expect(result.content[1] == SetupGuide.signedOut.plainText)
        #expect(result.structuredContent?["error"]?["code"] == "loggedOut")
        #expect(result.json["content"]?[1]?["text"] == .string(SetupGuide.signedOut.plainText))
        #expect(logger.messages(.notice).isEmpty)
    }

    @Test func stderrLinesGoToTheLogWithoutThePrefix() async throws {
        let logger = MemoryLogging()
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in throw FetchError.timedOut }, cache: MemoryCache(cached([pr1])),
                logger: logger))
        _ = try await MCPTools.call("get_inbox", arguments: ["max_age_seconds": 0], run: run)
        #expect(logger.messages(.notice).contains { $0.hasPrefix("GitHub did not answer in time") })
        #expect(logger.lines.allSatisfy { !$0.message.hasPrefix("prinbox: ") })
        #expect(logger.lines.contains { $0.level == .debug && $0.message == "mcp get_inbox: cache, exit 1" })
    }

    @Test func snoozeAndUnsnoozeReportThePullRequest() async throws {
        let persistence = MemoryStatePersistence()
        let run = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([]) }, cache: MemoryCache(cached([pr1])),
                persistence: persistence))
        let snoozed = try await MCPTools.call("snooze_pull_request", arguments: ["id": "PR_1"], run: run)
        #expect(snoozed.isError == false)
        #expect(snoozed.content == ["snoozed acme/web#1: Add feature"])
        #expect(
            snoozed.structuredContent == [
                "id": "PR_1", "snoozed": true, "number": 1, "repository": "acme/web", "title": "Add feature",
            ])
        #expect(persistence.saved?.snoozed["PR_1"] != nil)
        let woken = try await MCPTools.call("unsnooze_pull_request", arguments: ["id": "PR_1"], run: run)
        #expect(woken.content == ["unsnoozed acme/web#1: Add feature"])
        #expect(woken.structuredContent?["snoozed"] == false)
        #expect(persistence.saved?.snoozed.isEmpty == true)
        let unknown = try await MCPTools.call("unsnooze_pull_request", arguments: ["id": "PR_9"], run: run)
        #expect(unknown.isError == false)
        #expect(unknown.content == ["unsnoozed PR_9"])
        #expect(
            unknown.structuredContent == [
                "id": "PR_9", "snoozed": false, "number": nil, "repository": nil, "title": nil,
            ])
    }

    @Test func snoozeFailuresAreToolErrorsWithTheCommandsText() async throws {
        let absent = InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) }))
        let missing = try await MCPTools.call("snooze_pull_request", arguments: ["id": "PR_9"], run: absent)
        #expect(missing.isError)
        #expect(missing.content == ["PR_9 is not in your inbox"])
        #expect(missing.structuredContent == nil)
        let signedOut = InboxRun(context: makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }))
        let setup = try await MCPTools.call("snooze_pull_request", arguments: ["id": "PR_9"], run: signedOut)
        #expect(setup.isError)
        #expect(setup.content == [SetupGuide.signedOut.plainText])
        let unreadable = InboxRun(
            context: makeContext(
                fetcher: ScriptedFetcher { _ in makeResult([]) }, cache: MemoryCache(cached([pr1])),
                persistence: FailingPersistence(loadFails: true, saveFails: true)))
        let failed = try await MCPTools.call("snooze_pull_request", arguments: ["id": "PR_1"], run: unreadable)
        #expect(failed.isError)
        #expect(failed.content == ["state.json is unreadable, nothing written"])
    }

    @Test func idArgumentsAreValidatedBeforeAnythingRuns() async {
        let fetcher = ScriptedFetcher { _ in makeResult([self.pr1]) }
        let run = InboxRun(context: makeContext(fetcher: fetcher))
        #expect(await invalidParams("snooze_pull_request", nil, run: run) == "id must be a pull request node id string")
        #expect(
            await invalidParams("snooze_pull_request", ["id": 5], run: run)
                == "id must be a pull request node id string")
        #expect(
            await invalidParams("snooze_pull_request", ["id": "more:needsReview"], run: run)
                == "'more:needsReview' is not a pull request node id")
        #expect(
            await invalidParams("unsnooze_pull_request", ["id": "PR_1", "force": true], run: run)
                == "unknown argument 'force'")
        #expect(await fetcher.calls == 0)
    }
}
