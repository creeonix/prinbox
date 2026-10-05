import Foundation
import Testing

@testable import PrinboxCore

@Suite struct JSONRPCTests {
    func object(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    @Test func parsesRequestsNotificationsAndResponses() {
        let request = JSONRPC.parse(#"{"jsonrpc": "2.0", "id": 1, "method": "ping", "params": {"a": 1}}"#)
        #expect(request == .request(id: .number(1), method: "ping", params: ["a": 1]))
        let bare = JSONRPC.parse(#"{"jsonrpc": "2.0", "id": 2, "method": "tools/list"}"#)
        #expect(bare == .request(id: .number(2), method: "tools/list", params: nil))
        let notification = JSONRPC.parse(#"{"jsonrpc": "2.0", "method": "notifications/initialized"}"#)
        #expect(notification == .notification(method: "notifications/initialized", params: nil))
        let nullID = JSONRPC.parse(#"{"jsonrpc": "2.0", "id": null, "method": "ping"}"#)
        #expect(nullID == .notification(method: "ping", params: nil))
        let response = JSONRPC.parse(#"{"jsonrpc": "2.0", "id": 7, "result": {}}"#)
        #expect(response == .response)
    }

    @Test func idsAreEchoedAsReceived() throws {
        let request = JSONRPC.parse(#"{"jsonrpc": "2.0", "id": "abc-1", "method": "ping"}"#)
        #expect(request == .request(id: .string("abc-1"), method: "ping", params: nil))
        let reply = try object(JSONRPC.response(id: .string("abc-1"), result: [:]))
        #expect(reply["id"] == .string("abc-1"))
        #expect(reply["jsonrpc"] == .string("2.0"))
        #expect(reply["result"] == .object([:]))
        #expect(reply["error"] == nil)
    }

    @Test func badLinesAreInvalidWithTheRightCode() {
        #expect(JSONRPC.parse("not json") == .invalid(.parseError()))
        #expect(JSONRPC.parse("") == .invalid(.parseError()))
        #expect(JSONRPC.parse("[]") == .invalid(.invalidRequest("batches are not supported")))
        #expect(
            JSONRPC.parse("[{\"id\": 1, \"method\": \"ping\"}]")
                == .invalid(.invalidRequest("batches are not supported")))
        #expect(JSONRPC.parse("42") == .invalid(.invalidRequest("not a JSON-RPC message")))
        #expect(JSONRPC.parse("{}") == .invalid(.invalidRequest("not a JSON-RPC message")))
        #expect(JSONRPC.parse(#"{"id": 1, "method": 5}"#) == .invalid(.invalidRequest("method must be a string")))
        #expect(JSONRPCError.parseError().code == -32700)
        #expect(JSONRPCError.invalidRequest("x").code == -32600)
        #expect(JSONRPCError.methodNotFound("x").code == -32601)
        #expect(JSONRPCError.invalidParams("x").code == -32602)
        #expect(JSONRPCError.internalError("x").code == -32603)
    }

    @Test func errorRepliesCarryCodeAndMessage() throws {
        let reply = try object(JSONRPC.error(id: .null, .parseError()))
        #expect(reply["id"] == .null)
        #expect(reply["error"]?["code"] == .number(-32700))
        #expect(reply["error"]?["message"] == .string("parse error"))
        #expect(reply["result"] == nil)
        let named = try object(JSONRPC.error(id: .number(3), .methodNotFound("method not found: x")))
        #expect(named["id"] == .number(3))
        #expect(named["error"]?["message"] == .string("method not found: x"))
    }

    @Test func encodingKeepsOneLinePerMessage() throws {
        let title = "Fix \"quotes\"\nand a newline"
        let line = JSONRPC.response(id: .number(1), result: ["title": .string(title), "path": "a/b"])
        #expect(!line.contains("\n"))
        #expect(line.contains("a/b"))
        #expect(try object(line)["result"]?["title"] == .string(title))
    }
}
