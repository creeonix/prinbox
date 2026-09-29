import AppKit

if let mode = CommandLineMode(arguments: CommandLine.arguments) {
    Task { exit(await mode.run()) }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
