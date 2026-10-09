import Foundation

/// A `tools/call` answer (spec 3.6): text blocks, the structured result, and whether the tool failed. The
/// text of a successful `get_inbox` is the same JSON as `structuredContent`, for clients that read only text.
public struct ToolResult: Equatable, Sendable {
    public let content: [String]
    public let structuredContent: JSONValue?
    public let isError: Bool

    public init(content: [String], structuredContent: JSONValue? = nil, isError: Bool = false) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    public var json: JSONValue {
        var object: [String: JSONValue] = [
            "content": .array(content.map { .object(["type": "text", "text": .string($0)]) }),
            "isError": .bool(isError),
        ]
        if let structuredContent { object["structuredContent"] = structuredContent }
        return .object(object)
    }
}

/// The three tools (spec 3.4): their definitions for `tools/list`, their argument rules (the `-32602` cases),
/// and their runs over `InboxRun`, never as a notifier. Nothing a client sends reaches a query or a path:
/// every argument is a node id or an integer, checked before anything runs.
public enum MCPTools {
    public static let defaultMaxAge: TimeInterval = 60
    static let idPattern = "^[A-Za-z0-9_=-]+$"

    static let idSchema: JSONValue = [
        "type": "object",
        "properties": [
            "id": [
                "type": "string", "pattern": .string(idPattern),
                "description": "The pull request's node id: rows[].id from get_inbox.",
            ]
        ],
        "required": ["id"],
        "additionalProperties": false,
    ]

    /// The snooze tools change `state.json`, never GitHub, and a repeat is a no-op.
    static let writeAnnotations: JSONValue = ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true]

    public static let definitions: JSONValue = [
        [
            "name": "get_inbox",
            "description":
                "The pull requests waiting on the user, in seven sections: Needs your review, Replies to you, Take another look, Mentions, Your PRs, Waiting on others, and Reviewed, which is empty unless all is true. The result is the JSON document of prinbox (docs/inbox-json.md). source says whether the rows were fetched now (fetch), confirmed unchanged by GitHub (unchanged) or served from the local cache (cache); checkedAt says when GitHub last confirmed them. The default serves rows confirmed within the last 60 seconds; max_age_seconds 0 fetches now, which takes two to eight seconds. When error is set GitHub could not be reached and the rows are the last known ones.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "max_age_seconds": [
                        "type": "integer", "minimum": 0,
                        "description":
                            "Serve the local cache when GitHub confirmed it within this many seconds; 0 fetches now. Default 60.",
                    ],
                    "all": [
                        "type": "boolean",
                        "description":
                            "Include every open pull request the user reviewed, with their verdict, in the Reviewed section. Default false.",
                    ],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "destructiveHint": false],
        ],
        [
            "name": "snooze_pull_request",
            "description":
                "Parks a pull request until something happens on it: a push, a reply in a thread the user took part in, a new review request, or a review on the user's own pull request. It moves to Waiting on others and leaves the menu-bar count. Idempotent.",
            "inputSchema": idSchema,
            "annotations": writeAnnotations,
        ],
        [
            "name": "unsnooze_pull_request",
            "description": "Wakes a snoozed pull request now; it returns to its section. Idempotent.",
            "inputSchema": idSchema,
            "annotations": writeAnnotations,
        ],
    ]

    /// Validates, then runs. Throws `JSONRPCError` (`-32602`) for an unknown tool or bad arguments.
    public static func call(_ name: String, arguments: JSONValue?, run: InboxRun) async throws -> ToolResult {
        let args = try self.arguments(arguments)
        switch name {
        case "get_inbox":
            try allow(args, keys: ["max_age_seconds", "all"])
            return await getInbox(run, maxAge: try maxAge(args["max_age_seconds"]), all: try all(args["all"]))
        case "snooze_pull_request":
            try allow(args, keys: ["id"])
            let id = try self.id(args)
            return report(await run.snooze(id: id), tool: name, id: id, snoozed: true, logger: run.context.logger)
        case "unsnooze_pull_request":
            try allow(args, keys: ["id"])
            let id = try self.id(args)
            return report(run.unsnooze(id: id), tool: name, id: id, snoozed: false, logger: run.context.logger)
        default:
            throw JSONRPCError.invalidParams("unknown tool '\(name)'")
        }
    }

    // MARK: Arguments

    static func arguments(_ value: JSONValue?) throws -> [String: JSONValue] {
        switch value {
        case nil, .null?: return [:]
        case .object(let members)?: return members
        default: throw JSONRPCError.invalidParams("arguments must be an object")
        }
    }

    static func allow(_ args: [String: JSONValue], keys: Set<String>) throws {
        if let extra = args.keys.sorted().first(where: { !keys.contains($0) }) {
            throw JSONRPCError.invalidParams("unknown argument '\(extra)'")
        }
    }

    static func maxAge(_ value: JSONValue?) throws -> TimeInterval {
        guard let value else { return defaultMaxAge }
        guard let seconds = value.intValue, seconds >= 0 else {
            throw JSONRPCError.invalidParams("max_age_seconds must be an integer of 0 or more")
        }
        return TimeInterval(seconds)
    }

    static func all(_ value: JSONValue?) throws -> Bool {
        guard let value else { return false }
        guard let flag = value.boolValue else { throw JSONRPCError.invalidParams("all must be a boolean") }
        return flag
    }

    static func id(_ args: [String: JSONValue]) throws -> String {
        guard let id = args["id"]?.stringValue else {
            throw JSONRPCError.invalidParams("id must be a pull request node id string")
        }
        guard DetailsQuery.isValidID(id) else {
            throw JSONRPCError.invalidParams("'\(id)' is not a pull request node id")
        }
        return id
    }

    // MARK: Runs

    static func getInbox(_ run: InboxRun, maxAge: TimeInterval, all: Bool) async -> ToolResult {
        let outcome = await run.inbox(InboxOptions(format: .json, cacheMode: .maxAge(maxAge), notify: false, all: all))
        forward(outcome.stderr, except: outcome.setupGuide, to: run.context.logger)
        let text = InboxJSON.render(outcome.document)
        let structured = (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .null
        run.context.logger.debug(.cli, "mcp get_inbox: \(outcome.document.source ?? "none"), exit \(outcome.exitCode)")
        return ToolResult(
            content: [text] + (outcome.setupGuide.map { [$0] } ?? []), structuredContent: structured,
            isError: outcome.exitCode != 0)
    }

    static func report(_ outcome: CommandOutcome, tool: String, id: String, snoozed: Bool, logger: Logging)
        -> ToolResult
    {
        logger.debug(.cli, "mcp \(tool): exit \(outcome.exitCode)")
        guard outcome.exitCode == 0 else {
            return ToolResult(content: [outcome.stderr.map(strip).joined(separator: "\n")], isError: true)
        }
        let verb = snoozed ? "snoozed" : "unsnoozed"
        let pr = outcome.pullRequest
        let structured: JSONValue = .object([
            "id": .string(id), "snoozed": .bool(snoozed),
            "number": pr.map { .number($0.number) } ?? .null,
            "repository": pr.map { .string($0.repository) } ?? .null,
            "title": pr.map { .string($0.title) } ?? .null,
        ])
        let text = pr.map { "\(verb) \($0.repository)#\($0.number): \($0.title)" } ?? "\(verb) \(id)"
        return ToolResult(content: [text], structuredContent: structured)
    }

    /// The command's stderr lines go to the log at notice level, without the `prinbox: ` prefix; the setup
    /// guide is left out, since it goes into the content (spec 3.6).
    static func forward(_ lines: [String], except guide: String?, to logger: Logging) {
        for line in lines where line != guide { logger.notice(.cli, strip(line)) }
    }

    static func strip(_ line: String) -> String {
        line.hasPrefix("prinbox: ") ? String(line.dropFirst("prinbox: ".count)) : line
    }
}
