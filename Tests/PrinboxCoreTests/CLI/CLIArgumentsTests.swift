import Foundation
import Testing

@testable import PrinboxCore

@Suite struct CLIArgumentsTests {
    func parse(_ words: String) throws -> Invocation {
        try CLIArguments.parse(words.split(separator: " ").map(String.init))
    }

    func usageError(_ words: String) -> String? {
        do {
            _ = try parse(words)
            return nil
        } catch let error as UsageError {
            return error.message
        } catch {
            return "wrong error type"
        }
    }

    @Test func inboxDefaultsToJSONAndAFetch() throws {
        #expect(try parse("inbox") == Invocation(command: .inbox(InboxOptions()), settingsPath: nil, verbose: false))
        #expect(InboxOptions() == InboxOptions(format: .json, cacheMode: .fetch, notify: false))
    }

    @Test func inboxOptionsInBothSpellings() throws {
        let spaced = try parse("inbox --format lines --max-age 300 --notify")
        #expect(spaced.command == .inbox(InboxOptions(format: .lines, cacheMode: .maxAge(300), notify: true)))
        let joined = try parse("inbox --format=waybar --cached")
        #expect(joined.command == .inbox(InboxOptions(format: .waybar, cacheMode: .cached, notify: false)))
    }

    @Test func globalFlagsAnywhere() throws {
        let first = try parse("--settings /tmp/s.json --verbose inbox")
        #expect(first.settingsPath == "/tmp/s.json")
        #expect(first.verbose)
        let last = try parse("snooze PR_1 -v --settings /tmp/s.json")
        #expect(last == Invocation(command: .snooze(id: "PR_1"), settingsPath: "/tmp/s.json", verbose: true))
    }

    @Test func theIdCommandsTakeOneNodeID() throws {
        #expect(try parse("snooze PR_kwDOA1").command == .snooze(id: "PR_kwDOA1"))
        #expect(try parse("unsnooze PR_1==").command == .unsnooze(id: "PR_1=="))
        #expect(try parse("open PR_1").command == .open(id: "PR_1"))
        #expect(usageError("snooze") == "snooze needs one pull request id")
        #expect(usageError("open a b") == "open needs one pull request id")
        #expect(usageError("snooze more:needsReview") == "'more:needsReview' is not a pull request node id")
    }

    @Test func printVersionAndHelp() throws {
        #expect(try parse("print").command == .print)
        #expect(try parse("--version").command == .version)
        #expect(try parse("inbox --help").command == .help)
        #expect(try parse("-h").command == .help)
    }

    @Test func usageErrors() {
        #expect(usageError("") == "no command given")
        #expect(usageError("fetch") == "unknown command 'fetch'")
        #expect(usageError("inbox --loud") == "unknown option --loud")
        #expect(usageError("inbox --format pdf") == "unknown format 'pdf' (json, lines, waybar, tmux)")
        #expect(usageError("inbox --format") == "--format needs a value")
        #expect(usageError("inbox --max-age soon") == "--max-age needs a number of seconds, not 'soon'")
        #expect(usageError("inbox --max-age -5") == "--max-age needs a value")
        #expect(usageError("inbox --max-age inf") == "--max-age needs a number of seconds, not 'inf'")
        #expect(usageError("inbox --cached --max-age 60") == "--cached and --max-age exclude each other")
        #expect(usageError("inbox extra") == "inbox takes no argument")
        #expect(usageError("print --format lines") == "--format applies to inbox only")
        #expect(usageError("--settings") == "--settings needs a value")
    }

    @Test func usageNamesEveryCommand() {
        for word in [
            "inbox", "print", "snooze", "unsnooze", "open", "--format", "--cached", "--max-age", "--notify",
            "--settings", "--verbose", "--version", "--help",
        ] {
            #expect(CLIArguments.usage.contains(word), "\(word) missing from usage")
        }
    }
}
