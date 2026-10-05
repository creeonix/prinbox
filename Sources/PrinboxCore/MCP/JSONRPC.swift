import Foundation

/// A JSON-RPC 2.0 error, as sent in an error reply. The codes are the standard ones; MCP uses `-32602` for an
/// unknown tool and bad arguments as well.
public struct JSONRPCError: Error, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public static func parseError(_ message: String = "parse error") -> JSONRPCError {
        .init(code: -32700, message: message)
    }
    public static func invalidRequest(_ message: String) -> JSONRPCError { .init(code: -32600, message: message) }
    public static func methodNotFound(_ message: String) -> JSONRPCError { .init(code: -32601, message: message) }
    public static func invalidParams(_ message: String) -> JSONRPCError { .init(code: -32602, message: message) }
    public static func internalError(_ message: String) -> JSONRPCError { .init(code: -32603, message: message) }
}

/// One line from the client, classified (spec 3.2): a request gets exactly one reply; a notification (no id, or
/// a null one) and a response (an id without a method) are ignored; anything else gets an error with a null id.
public enum JSONRPCMessage: Equatable, Sendable {
    case request(id: JSONValue, method: String, params: JSONValue?)
    case notification(method: String, params: JSONValue?)
    case response
    case invalid(JSONRPCError)
}

/// Parsing and rendering of newline-delimited JSON-RPC 2.0. Every rendered message is one line without a
/// trailing newline: the encoder escapes newlines inside strings, and never pretty-prints.
public enum JSONRPC {
    public static func parse(_ line: String) -> JSONRPCMessage {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        } catch {
            return .invalid(.parseError())
        }
        switch value {
        case .array:
            return .invalid(.invalidRequest("batches are not supported"))
        case .object(let members):
            let id = members["id"]
            let hasID = id != nil && id != .null
            guard let method = members["method"] else {
                return hasID ? .response : .invalid(.invalidRequest("not a JSON-RPC message"))
            }
            guard case .string(let name) = method else { return .invalid(.invalidRequest("method must be a string")) }
            if let id, hasID { return .request(id: id, method: name, params: members["params"]) }
            return .notification(method: name, params: members["params"])
        default:
            return .invalid(.invalidRequest("not a JSON-RPC message"))
        }
    }

    public static func response(id: JSONValue, result: JSONValue) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    public static func error(id: JSONValue, _ error: JSONRPCError) -> String {
        encode([
            "jsonrpc": "2.0", "id": id,
            "error": ["code": .number(error.code), "message": .string(error.message)],
        ])
    }

    /// One line: sorted keys, slashes unescaped, no pretty-printing.
    public static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
