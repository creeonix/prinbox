import Foundation

/// Where an arrivals notice goes. The app's `Notifier` (UNUserNotificationCenter) conforms; the command uses
/// `notify-send` on Linux and nothing on macOS, where the app is the notifier.
public protocol NotificationDelivering: Sendable {
    func deliver(_ notice: ArrivalNotice) async
}

public struct NoDelivery: NotificationDelivering {
    public init() {}
    public func deliver(_ notice: ArrivalNotice) async {}
}

/// `notify-send --app-name=prinbox <title> <body>`: a banner, no click action (an action would block until
/// the user reacts, which a Waybar `exec` cannot wait for). Failures are a notice; the inbox still prints.
public struct NotifySendDelivery: NotificationDelivering {
    public static let timeout: Duration = .seconds(5)

    private let executable: URL
    private let runner: CommandRunning
    private let logger: Logging

    public init(
        executable: URL = URL(fileURLWithPath: "/usr/bin/notify-send"), runner: CommandRunning = ProcessCommandRunner(),
        logger: Logging = NullLogging()
    ) {
        self.executable = executable
        self.runner = runner
        self.logger = logger
    }

    public func deliver(_ notice: ArrivalNotice) async {
        do {
            let output = try await runner.run(
                executable: executable, arguments: ["--app-name=prinbox", notice.title, notice.body],
                environment: ProcessInfo.processInfo.environment, timeout: Self.timeout)
            if output.exitCode != 0 {
                logger.notice(.cli, "notify-send exited \(output.exitCode)", private: String(output.stderr.prefix(500)))
            }
        } catch {
            logger.notice(.cli, "notify-send did not run", private: String(describing: error))
        }
    }
}
