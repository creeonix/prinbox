import Foundation

public enum OutputFormat: String, Sendable, CaseIterable {
    case json
    case lines
    case waybar
    case tmux
}

public enum CacheMode: Sendable, Equatable {
    /// Contact GitHub (the fingerprint still makes an unchanged check cost one point).
    case fetch
    /// Print the cache, whatever its age; fail without one.
    case cached
    /// Serve the cache when `checkedAt` is within this many seconds, fetch otherwise.
    case maxAge(TimeInterval)
}

public struct InboxOptions: Sendable, Equatable {
    public var format: OutputFormat
    public var cacheMode: CacheMode
    public var notify: Bool

    public init(format: OutputFormat = .json, cacheMode: CacheMode = .fetch, notify: Bool = false) {
        self.format = format
        self.cacheMode = cacheMode
        self.notify = notify
    }
}

public enum Command: Sendable, Equatable {
    case inbox(InboxOptions)
    case print
    case snooze(id: String)
    case unsnooze(id: String)
    case open(id: String)
    case version
    case help
}

public struct Invocation: Sendable, Equatable {
    public let command: Command
    public let settingsPath: String?
    public let verbose: Bool

    public init(command: Command, settingsPath: String?, verbose: Bool) {
        self.command = command
        self.settingsPath = settingsPath
        self.verbose = verbose
    }
}

/// Exit 2: the message goes to stderr with the usage text.
public struct UsageError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) { self.message = message }
}

/// The `prinbox` command line, parsed by hand: five commands and a handful of flags.
public enum CLIArguments {
    public static let usage = """
        usage: prinbox <command> [options]

        commands:
          inbox             the inbox for machines (see docs/inbox-json.md)
            --format json|lines|waybar|tmux   default json
            --cached                          print the cache, never contact GitHub
            --max-age <seconds>               serve the cache while it is this fresh
            --notify                          deliver arrivals (one notifier per machine)
          print             the inbox as text: a full fetch that touches nothing
          snooze <id>       park a pull request until something happens on it
          unsnooze <id>     wake it
          open <id>         open it in the browser

        options:
          --settings <path> the settings file (default ~/.config/prinbox/settings.json)
          --verbose, -v     info and debug lines on stderr, private details included
          --version
          --help, -h
        """

    /// `arguments` without the program name.
    public static func parse(_ arguments: [String]) throws -> Invocation {
        var settingsPath: String?
        var verbose = false
        var positional: [String] = []
        var options = InboxOptions()
        var inboxFlags: [String] = []
        var index = 0

        func value(after flag: String) throws -> String {
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("-") else {
                throw UsageError(message: "\(flag) needs a value")
            }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                return Invocation(command: .help, settingsPath: settingsPath, verbose: verbose)
            case "--version":
                return Invocation(command: .version, settingsPath: settingsPath, verbose: verbose)
            case "--settings":
                settingsPath = try value(after: "--settings")
            case "--verbose", "-v":
                verbose = true
            case "--format":
                options.format = try format(try value(after: "--format"))
                inboxFlags.append("--format")
            case _ where argument.hasPrefix("--format="):
                options.format = try format(String(argument.dropFirst("--format=".count)))
                inboxFlags.append("--format")
            case "--cached":
                options.cacheMode = .cached
                inboxFlags.append("--cached")
            case "--max-age":
                let raw = try value(after: "--max-age")
                guard let seconds = TimeInterval(raw), seconds >= 0 else {
                    throw UsageError(message: "--max-age needs a number of seconds, not '\(raw)'")
                }
                options.cacheMode = .maxAge(seconds)
                inboxFlags.append("--max-age")
            case "--notify":
                options.notify = true
                inboxFlags.append("--notify")
            case _ where argument.hasPrefix("-"):
                throw UsageError(message: "unknown option \(argument)")
            default:
                positional.append(argument)
            }
            index += 1
        }
        if inboxFlags.contains("--cached") && inboxFlags.contains("--max-age") {
            throw UsageError(message: "--cached and --max-age exclude each other")
        }
        guard let name = positional.first else { throw UsageError(message: "no command given") }
        let rest = Array(positional.dropFirst())
        if name != "inbox", let flag = inboxFlags.first { throw UsageError(message: "\(flag) applies to inbox only") }
        let command: Command
        switch name {
        case "inbox":
            guard rest.isEmpty else { throw UsageError(message: "inbox takes no argument") }
            command = .inbox(options)
        case "print":
            guard rest.isEmpty else { throw UsageError(message: "print takes no argument") }
            command = .print
        case "snooze", "unsnooze", "open":
            guard rest.count == 1 else { throw UsageError(message: "\(name) needs one pull request id") }
            guard DetailsQuery.isValidID(rest[0]) else {
                throw UsageError(message: "'\(rest[0])' is not a pull request node id")
            }
            command =
                name == "snooze"
                ? .snooze(id: rest[0]) : name == "unsnooze" ? .unsnooze(id: rest[0]) : .open(id: rest[0])
        default:
            throw UsageError(message: "unknown command '\(name)'")
        }
        return Invocation(command: command, settingsPath: settingsPath, verbose: verbose)
    }

    private static func format(_ raw: String) throws -> OutputFormat {
        guard let format = OutputFormat(rawValue: raw) else {
            throw UsageError(message: "unknown format '\(raw)' (json, lines, waybar, tmux)")
        }
        return format
    }
}
