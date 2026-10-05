import Foundation

/// The command's entry point after parsing: runs one invocation and prints. Both `prinbox` and the app's
/// `--print` go through it.
public enum CLI {
    public static func run(
        _ invocation: Invocation, context: RunContext, stdout: @escaping (String) -> Void,
        stderr: @escaping (String) -> Void, readLine: @escaping () -> String? = { nil }
    ) async -> Int32 {
        let run = InboxRun(context: context)
        switch invocation.command {
        case .help:
            stdout(CLIArguments.usage + "\n")
            return 0
        case .version:
            stdout("prinbox \(context.version)\n")
            return 0
        case .inbox(let options):
            if options.notify, options.cacheMode != .cached, let note = context.notifyNote {
                stderr("prinbox: \(note)\n")
            }
            let outcome = await run.inbox(options)
            for line in outcome.stderr { stderr(line + "\n") }
            if options.format != .json {
                for warning in outcome.document.warnings { stderr("prinbox: warning: \(warning)\n") }
            }
            stdout(render(outcome.document, format: options.format))
            return options.format == .waybar ? 0 : outcome.exitCode
        case .print:
            let printed = await run.printInbox()
            for line in printed.stderr { stderr(line + "\n") }
            if !printed.stdout.isEmpty { stdout(printed.stdout + "\n") }
            return printed.exitCode
        case .snooze(let id):
            return report(await run.snooze(id: id), stderr: stderr)
        case .unsnooze(let id):
            return report(run.unsnooze(id: id), stderr: stderr)
        case .open(let id):
            return report(await run.open(id: id), stderr: stderr)
        case .mcp:
            await MCPServer(context: context, readLine: readLine, write: stdout).serve()
            return 0
        }
    }

    static func render(_ document: InboxDocument, format: OutputFormat) -> String {
        switch format {
        case .json: InboxJSON.render(document) + "\n"
        case .lines: InboxLines.render(document)
        case .waybar: InboxWaybar.render(document) + "\n"
        case .tmux: InboxTmux.render(document) + "\n"
        }
    }

    private static func report(_ outcome: CommandOutcome, stderr: (String) -> Void) -> Int32 {
        for line in outcome.stderr { stderr(line + "\n") }
        return outcome.exitCode
    }
}
