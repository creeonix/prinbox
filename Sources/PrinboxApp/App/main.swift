import AppKit

if let mode = CommandLineMode(arguments: CommandLine.arguments) {
    Task { exit(await mode.run()) }
    dispatchMain()
}

let arguments = CommandLine.arguments
// `--settings <path>`: an explicit settings file, for the screenshot harness and for trying a configuration.
let settingsPath = arguments.firstIndex(of: "--settings").flatMap { index in
    arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
}
let app = NSApplication.shared
let delegate = AppDelegate(demo: arguments.contains("--demo"), settingsPath: settingsPath)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
