import Foundation
import Testing

@testable import PrinboxCore

/// Records one run and answers with `output`.
final class RecordingRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(URL, [String])] = []
    let output: CommandOutput
    let error: Error?

    init(output: CommandOutput = CommandOutput(exitCode: 0, stdout: Data(), stderr: ""), error: Error? = nil) {
        self.output = output
        self.error = error
    }

    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws
        -> CommandOutput
    {
        lock.withLock { calls.append((executable, arguments)) }
        if let error { throw error }
        return output
    }

    var recorded: [(URL, [String])] { lock.withLock { calls } }
}

@Suite struct DeliveryAndOpenerTests {
    let notice = ArrivalNotice(title: "#12 Add feature", body: "acme/web · Needs your review", url: nil)

    @Test func notifySendGetsTheAppNameTitleAndBody() async {
        let runner = RecordingRunner()
        let delivery = NotifySendDelivery(executable: URL(fileURLWithPath: "/usr/bin/notify-send"), runner: runner)
        await delivery.deliver(notice)
        #expect(runner.recorded.count == 1)
        #expect(runner.recorded.first?.0.path == "/usr/bin/notify-send")
        #expect(runner.recorded.first?.1 == ["--app-name=prinbox", "#12 Add feature", "acme/web · Needs your review"])
    }

    @Test func aFailingNotifySendIsANoticeWithPrivateStderr() async {
        let logger = MemoryLogging()
        let runner = RecordingRunner(output: CommandOutput(exitCode: 1, stdout: Data(), stderr: "no bus"))
        await NotifySendDelivery(runner: runner, logger: logger).deliver(notice)
        #expect(
            logger.lines == [
                MemoryLogging.Line(level: .notice, category: .cli, message: "notify-send exited 1", detail: "no bus")
            ])
        let missing = MemoryLogging()
        await NotifySendDelivery(
            runner: RecordingRunner(error: CommandRunnerError.launchFailed("no such file")), logger: missing
        ).deliver(notice)
        #expect(missing.messages(.notice).first?.hasPrefix("notify-send did not run") == true)
    }

    @Test func noDeliveryDeliversNothing() async {
        await NoDelivery().deliver(notice)
    }

    @Test func theProcessOpenerPassesTheURL() async {
        let runner = RecordingRunner()
        let url = URL(string: "https://github.com/acme/web/pull/12")!
        await ProcessURLOpener(executable: URL(fileURLWithPath: "/usr/bin/xdg-open"), runner: runner).open(url)
        #expect(runner.recorded.first?.0.path == "/usr/bin/xdg-open")
        #expect(runner.recorded.first?.1 == ["https://github.com/acme/web/pull/12"])
    }

    @Test func aFailingOpenerIsANotice() async {
        let logger = MemoryLogging()
        let runner = RecordingRunner(output: CommandOutput(exitCode: 3, stdout: Data(), stderr: "no browser"))
        await ProcessURLOpener(executable: URL(fileURLWithPath: "/usr/bin/xdg-open"), runner: runner, logger: logger)
            .open(URL(string: "https://example.com")!)
        #expect(logger.lines.first?.message == "xdg-open exited 3")
        #expect(logger.lines.first?.detail == "no browser")
    }
}
