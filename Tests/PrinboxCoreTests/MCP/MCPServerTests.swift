import Foundation
import Testing

@testable import PrinboxCore

@Suite struct MCPServerTests {
    final class Transcript: @unchecked Sendable {
        private let lock = NSLock()
        private var input: [String]
        private var output: [String] = []
        init(_ input: [String]) { self.input = input }
        func next() -> String? { lock.withLock { input.isEmpty ? nil : input.removeFirst() } }
        func write(_ text: String) { lock.withLock { output.append(text) } }
        var lines: [String] { lock.withLock { output } }
    }

    let pr1 = makePR(id: "PR_1", number: 1, reviewRequestedAt: date("2026-08-10T08:00:00Z"))

    func serve(_ input: [String], context: RunContext) async -> [JSONValue] {
        let transcript = Transcript(input)
        await MCPServer(context: context, readLine: transcript.next, write: transcript.write).serve()
        return transcript.lines.map { line in
            #expect(line.hasSuffix("\n"), "every reply ends with one newline")
            #expect(!line.dropLast().contains("\n"), "no newline inside a message")
            return (try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))) ?? .null
        }
    }

    func request(_ id: JSONValue, _ method: String, _ params: JSONValue? = nil) -> String {
        var object: [String: JSONValue] = ["jsonrpc": "2.0", "id": id, "method": .string(method)]
        if let params { object["params"] = params }
        return JSONRPC.encode(.object(object))
    }

    @Test func aWholeSessionAnswersEveryRequestOnceInOrder() async {
        let persistence = MemoryStatePersistence()
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr1]) }, persistence: persistence, version: "0.6.0-test")
        let replies = await serve(
            [
                request(
                    1, "initialize",
                    [
                        "protocolVersion": "2025-06-18", "capabilities": [:],
                        "clientInfo": ["name": "t", "version": "1"],
                    ]),
                #"{"jsonrpc": "2.0", "method": "notifications/initialized"}"#,
                request(2, "ping"),
                request("list-1", "tools/list"),
                request(4, "tools/call", ["name": "get_inbox", "arguments": ["max_age_seconds": 0]]),
                request(5, "tools/call", ["name": "snooze_pull_request", "arguments": ["id": "PR_1"]]),
                request(6, "tools/call", ["name": "unsnooze_pull_request", "arguments": ["id": "PR_1"]]),
                request(7, "resources/list"),
                request(8, "tools/call", ["name": "open_pull_request", "arguments": ["id": "PR_1"]]),
                request(9, "tools/call", ["name": "snooze_pull_request", "arguments": ["id": "more:x"]]),
                request(10, "tools/call", ["arguments": [:]]),
                "garbage",
                #"{"jsonrpc": "2.0", "id": 11, "result": {}}"#,
            ], context: context)
        #expect(replies.count == 11)
        #expect(replies.map { $0["id"] } == [1, 2, "list-1", 4, 5, 6, 7, 8, 9, 10, .null])
        #expect(replies[0]["result"]?["protocolVersion"] == "2025-06-18")
        #expect(replies[0]["result"]?["capabilities"] == ["tools": [:]])
        #expect(replies[0]["result"]?["serverInfo"] == ["name": "prinbox", "version": "0.6.0-test"])
        #expect(replies[0]["result"]?["instructions"] == .string(MCPServer.instructions))
        #expect(replies[1]["result"] == .object([:]))
        #expect(replies[2]["result"]?["tools"] == MCPTools.definitions)
        #expect(replies[3]["result"]?["isError"] == false)
        #expect(replies[3]["result"]?["structuredContent"]?["badge"] == 1)
        #expect(replies[3]["result"]?["content"]?[0]?["type"] == "text")
        #expect(replies[4]["result"]?["structuredContent"]?["snoozed"] == true)
        #expect(replies[5]["result"]?["structuredContent"]?["snoozed"] == false)
        #expect(persistence.saved?.snoozed.isEmpty == true)
        #expect(replies[6]["error"]?["code"] == .number(-32601))
        #expect(replies[6]["error"]?["message"] == "method not found: resources/list")
        #expect(replies[7]["error"]?["code"] == .number(-32602))
        #expect(replies[7]["error"]?["message"] == "unknown tool 'open_pull_request'")
        #expect(replies[8]["error"]?["message"] == "'more:x' is not a pull request node id")
        #expect(replies[9]["error"]?["message"] == "name must be a string")
        #expect(replies[10]["error"]?["code"] == .number(-32700))
    }

    @Test func anUnknownProtocolVersionGetsTheLatestKnownOne() async {
        let context = makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) })
        let replies = await serve(
            [
                request(1, "initialize", ["protocolVersion": "2030-01-01"]), request(2, "initialize"),
                request(3, "initialize", ["protocolVersion": "2024-11-05"]),
            ],
            context: context)
        #expect(replies.map { $0["result"]?["protocolVersion"] } == ["2025-11-25", "2025-11-25", "2024-11-05"])
        #expect(MCPServer.protocolVersions == ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"])
    }

    @Test func toolsWorkBeforeInitializeAndNotificationsAreIgnored() async {
        let context = makeContext(fetcher: ScriptedFetcher { _ in makeResult([self.pr1]) })
        let replies = await serve(
            [
                #"{"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 1}}"#,
                request(1, "tools/list"),
            ],
            context: context)
        #expect(replies.count == 1)
        #expect(replies[0]["result"]?["tools"]?[0]?["name"] == "get_inbox")
    }

    @Test func nothingButProtocolReachesTheWriter() async {
        let logger = MemoryLogging()
        let context = makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.loggedOut }, logger: logger)
        let transcript = Transcript([request(1, "tools/call", ["name": "get_inbox"]), "nonsense"])
        await MCPServer(context: context, readLine: transcript.next, write: transcript.write).serve()
        #expect(transcript.lines.count == 2)
        for line in transcript.lines {
            let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            #expect(value?["jsonrpc"] == "2.0")
        }
        #expect(logger.lines.contains { $0.level == .debug && $0.message == "mcp: unparseable line" })
        #expect(logger.lines.contains { $0.level == .debug && $0.message == "mcp get_inbox: none, exit 3" })
    }

    @Test func emptyInputServesNothingAndReturns() async {
        let replies = await serve([], context: makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) }))
        #expect(replies.isEmpty)
    }

    /// One server, two calls; the fetcher flips the setting during call 1, as the app would between questions.
    @Test func settingsAreReadAgainForEveryCall() async {
        nonisolated(unsafe) let defaults = MemoryDefaults()
        defaults.set(false, forKey: SearchScope.hideDraftsKey)
        let fetcher = ScriptedFetcher { call in
            if call == 1 { defaults.set(true, forKey: SearchScope.hideDraftsKey) }
            return makeResult([])
        }
        let call = request(1, "tools/call", ["name": "get_inbox", "arguments": ["max_age_seconds": 0]])
        let transcript = Transcript([call, call])
        let server = MCPServer(
            makeContext: { makeContext(fetcher: fetcher, scope: SearchScope.read(from: defaults)) },
            readLine: transcript.next, write: transcript.write)
        await server.serve()
        #expect(transcript.lines.count == 2)
        let hideDrafts = await fetcher.requests.map { $0.scope.hideDrafts }
        #expect(hideDrafts == [false, true])
    }

    @Test func blankLinesAreIgnored() async {
        let replies = await serve(
            ["", "   ", "\r", request(1, "ping")],
            context: makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) })
        )
        #expect(replies.count == 1)
        #expect(replies.first?["id"] == 1)
    }
}
