import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private let settingsPath: String?
    private var coordinator: AppCoordinator?

    /// `demo` shows sample pull requests instead of running gh (launch with `--demo`); `settingsPath` is an
    /// explicit settings file (`--settings <path>`).
    init(demo: Bool, settingsPath: String?) {
        self.demo = demo
        self.settingsPath = settingsPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(demo: demo, settingsPath: settingsPath)
        coordinator.start()
        self.coordinator = coordinator
    }
}
