import Foundation

/// `prinbox mcp` (spec section 3): the Model Context Protocol server over stdio. One JSON-RPC message per line
/// in and out, requests handled one at a time in arrival order, nothing but protocol on stdout. Logs go
/// through the context's logger, which the command points at stderr. The context is built afresh for every
/// message, so a setting changed in the app applies to the next call. The reader and writer are injected, so
/// a test drives a whole session in memory.
public struct MCPServer {
    /// Newest first. A client's version is echoed when it is one of these; any other gets the first.
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let instructions =
        "prinbox is the user's inbox of GitHub pull requests waiting on them, read through the GitHub CLI. Call get_inbox first; every id the other tools take is a rows[].id from it. Nothing here reads the text of a comment, a review or a description."

    let makeContext: () -> RunContext
    let readLine: () -> String?
    let write: (String) -> Void

    /// `makeContext` runs once per message, so the settings it reads are the ones current at that call.
    public init(
        makeContext: @escaping () -> RunContext, readLine: @escaping () -> String?, write: @escaping (String) -> Void
    ) {
        self.makeContext = makeContext
        self.readLine = readLine
        self.write = write
    }

    /// One context for the whole session; the tests use it.
    public init(context: RunContext, readLine: @escaping () -> String?, write: @escaping (String) -> Void) {
        self.init(makeContext: { context }, readLine: readLine, write: write)
    }

    /// Reads until stdin closes; a reply, when there is one, is written with its newline before the next read.
    public func serve() async {
        while let line = readLine() {
            if let reply = await handle(line) { write(reply + "\n") }
        }
    }

    /// One line in, zero or one line out. A blank or whitespace-only line is not a message and gets no reply.
    public func handle(_ line: String) async -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let context = makeContext()
        switch JSONRPC.parse(line) {
        case .invalid(let error):
            context.logger.debug(.cli, "mcp: unparseable line")
            return JSONRPC.error(id: .null, error)
        case .notification, .response:
            return nil
        case .request(let id, let method, let params):
            do {
                return JSONRPC.response(id: id, result: try await dispatch(method, params: params, context: context))
            } catch let error as JSONRPCError {
                return JSONRPC.error(id: id, error)
            } catch {
                context.logger.error(.cli, "mcp: \(method) failed", private: String(describing: error))
                return JSONRPC.error(id: id, .internalError("internal error"))
            }
        }
    }

    func dispatch(_ method: String, params: JSONValue?, context: RunContext) async throws -> JSONValue {
        switch method {
        case "initialize":
            let requested = params?["protocolVersion"]?.stringValue
            let version =
                requested.flatMap { Self.protocolVersions.contains($0) ? $0 : nil } ?? Self.protocolVersions[0]
            return [
                "protocolVersion": .string(version),
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "prinbox", "version": .string(context.version)],
                "instructions": .string(Self.instructions),
            ]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": MCPTools.definitions]
        case "tools/call":
            guard let name = params?["name"]?.stringValue else {
                throw JSONRPCError.invalidParams("name must be a string")
            }
            return try await MCPTools.call(name, arguments: params?["arguments"], run: InboxRun(context: context)).json
        default:
            throw JSONRPCError.methodNotFound("method not found: \(method)")
        }
    }
}
