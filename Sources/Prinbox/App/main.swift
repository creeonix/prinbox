import AppKit

if let mode = CommandLineMode(arguments: CommandLine.arguments) {
    Task { exit(await mode.run()) }
    dispatchMain()
}
