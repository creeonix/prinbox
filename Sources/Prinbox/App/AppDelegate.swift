import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo: Bool
    private var coordinator: AppCoordinator?

    /// `demo` shows sample pull requests instead of running gh (launch with `--demo`).
    init(demo: Bool) {
        self.demo = demo
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(demo: demo)
        coordinator.start()
        self.coordinator = coordinator
    }
}
