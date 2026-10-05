import Foundation
import Testing

@testable import PrinboxCore

@Suite struct CLIRunTests {
    final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var out = ""
        private var err = ""
        func stdout(_ s: String) { lock.withLock { out += s } }
        func stderr(_ s: String) { lock.withLock { err += s } }
        var standardOutput: String { lock.withLock { out } }
        var standardError: String { lock.withLock { err } }
    }

    let pr = makePR(id: "PR_1", number: 1, reviewRequestedAt: date("2026-08-10T08:00:00Z"))

    func run(_ words: String, context: RunContext) async throws -> (Output, Int32) {
        let output = Output()
        let invocation = try CLIArguments.parse(words.split(separator: " ").map(String.init))
        let code = await CLI.run(
            invocation, context: context, stdout: { output.stdout($0) }, stderr: { output.stderr($0) })
        return (output, code)
    }

    @Test func helpAndVersion() async throws {
        let context = makeContext(fetcher: ScriptedFetcher { _ in makeResult([]) })
        let (help, helpCode) = try await run("--help", context: context)
        #expect(helpCode == 0)
        #expect(help.standardOutput == CLIArguments.usage + "\n")
        let (version, versionCode) = try await run("--version", context: context)
        #expect(versionCode == 0)
        #expect(version.standardOutput == "prinbox 0.5.0-test\n")
    }

    @Test func jsonKeepsWarningsInTheDocumentOtherFormatsPrintThem() async throws {
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([self.pr], warnings: ["GitHub: partial"]) })
        let (json, _) = try await run("inbox", context: context)
        #expect(json.standardOutput.contains("\"warnings\" : [\n    \"GitHub: partial\"\n  ]"))
        #expect(json.standardError == "")
        let (lines, _) = try await run("inbox --format lines", context: context)
        #expect(lines.standardError == "prinbox: warning: GitHub: partial\n")
        #expect(lines.standardOutput.hasPrefix("PR_1\tneedsReview\t1\t"))
    }

    @Test func waybarAlwaysExits0AndTmuxFollowsTheExitRule() async throws {
        let context = makeContext(fetcher: ScriptedFetcher { _ in throw FetchError.offline })
        let (waybar, waybarCode) = try await run("inbox --format waybar", context: context)
        #expect(waybarCode == 0)
        #expect(waybar.standardOutput.contains("\"text\":\"!\""))
        #expect(waybar.standardError == "prinbox: Offline\n")
        let (tmux, tmuxCode) = try await run("inbox --format tmux", context: context)
        #expect(tmuxCode == 1)
        #expect(tmux.standardOutput == "!\n")
    }

    @Test func theNotifyNoteIsPrintedOnceWhenThePlatformHasNoDelivery() async throws {
        let context = makeContext(
            fetcher: ScriptedFetcher { _ in makeResult([]) },
            notifyNote: "notifications on macOS are delivered by PRInbox.app")
        let (output, code) = try await run("inbox --notify --format tmux", context: context)
        #expect(code == 0)
        #expect(output.standardError == "prinbox: notifications on macOS are delivered by PRInbox.app\n")
        let (quiet, _) = try await run("inbox --format tmux", context: context)
        #expect(quiet.standardError == "")
        let (served, _) = try await run("inbox --notify --cached --format tmux", context: context)
        #expect(!served.standardError.contains("notifications on macOS"))
    }

    @Test func theCommandsReportThroughTheSameChannels() async throws {
        let persistence = MemoryStatePersistence()
        let context = makeContext(fetcher: ScriptedFetcher { _ in makeResult([self.pr]) }, persistence: persistence)
        let (snooze, snoozeCode) = try await run("snooze PR_1", context: context)
        #expect(snoozeCode == 0)
        #expect(snooze.standardOutput == "")
        #expect(persistence.saved?.snoozed.keys.contains("PR_1") == true)
        let (absent, absentCode) = try await run("open PR_9", context: context)
        #expect(absentCode == 1)
        #expect(absent.standardError == "prinbox: PR_9 is not in your inbox\n")
        let (printed, printCode) = try await run("print", context: context)
        #expect(printCode == 0)
        #expect(printed.standardOutput.hasPrefix("waiting on you: 0\n"))
    }
}
