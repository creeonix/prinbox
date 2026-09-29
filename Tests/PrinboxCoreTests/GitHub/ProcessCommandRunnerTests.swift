import Foundation
import Testing

@testable import PrinboxCore

@Suite struct ProcessCommandRunnerTests {
    let runner = ProcessCommandRunner()
    let sh = URL(fileURLWithPath: "/bin/sh")
    let path = ["PATH": "/usr/bin:/bin"]

    @Test func capturesStdoutStderrAndExitCode() async throws {
        let output = try await runner.run(
            executable: sh, arguments: ["-c", "printf out; printf err >&2; exit 3"], environment: path,
            timeout: .seconds(5))
        #expect(output.exitCode == 3)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "out")
        #expect(output.stderr == "err")
    }

    @Test func drainsLargeOutputWithoutDeadlock() async throws {
        let output = try await runner.run(
            executable: sh, arguments: ["-c", "head -c 300000 /dev/zero; head -c 100000 /dev/zero >&2"],
            environment: path, timeout: .seconds(10))
        #expect(output.stdout.count == 300_000)
        #expect(output.stderr.utf8.count == 100_000)
    }

    @Test func terminatesAfterTimeout() async {
        await #expect(throws: CommandRunnerError.timedOut) {
            try await runner.run(
                executable: sh, arguments: ["-c", "exec sleep 5"], environment: path, timeout: .milliseconds(200))
        }
    }

    @Test func watchdogFiringAfterExitIsNotATimeout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let watchdog = Watchdog(process: process)
        watchdog.fireNow()
        #expect(watchdog.fired == false)
    }

    @Test func reportsLaunchFailure() async {
        await #expect(throws: CommandRunnerError.self) {
            try await runner.run(
                executable: URL(fileURLWithPath: "/nonexistent/gh"), arguments: [], environment: path,
                timeout: .seconds(1))
        }
    }
}
