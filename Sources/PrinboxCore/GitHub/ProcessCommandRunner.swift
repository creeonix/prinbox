import Foundation

/// Runs a subprocess on a background queue. It drains stdout and stderr concurrently, so large output
/// cannot fill a pipe and deadlock, and it terminates the process when `timeout` elapses.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
    {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    with: Result { try Self.runBlocking(executable, arguments, environment, timeout) })
            }
        }
    }

    private static func runBlocking(
        _ executable: URL, _ arguments: [String], _ environment: [String: String], _ timeout: Duration
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }
        let watchdog = Watchdog(process: process)
        watchdog.arm(after: timeout)
        let stderrBox = DataBox()
        let stderrHandle = UncheckedBox(stderrPipe.fileHandleForReading)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.set(stderrHandle.value.readDataToEndOfFile())
            group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.disarm()
        if watchdog.fired { throw CommandRunnerError.timedOut }
        return CommandOutput(
            exitCode: process.terminationStatus, stdout: stdout,
            stderr: String(decoding: stderrBox.value, as: UTF8.self))
    }
}

/// Carries a non-Sendable reference into a background closure that is its only other user.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Terminates the process if it is still running when the timeout fires.
final class Watchdog: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var didFire = false
    private var isDisarmed = false

    init(process: Process) { self.process = process }

    func arm(after timeout: Duration) {
        let (seconds, attoseconds) = timeout.components
        let interval = Double(seconds) + Double(attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) { self.fire() }
    }

    /// Test hook: what happens when the timeout fires now.
    func fireNow() { fire() }

    func disarm() {
        lock.lock()
        isDisarmed = true
        lock.unlock()
    }

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFire
    }

    /// Only a kill of a still-running process counts as a timeout; a process that already exited keeps its
    /// output even if the deadline passes before `disarm()`.
    private func fire() {
        lock.lock()
        let shouldKill = !isDisarmed && process.isRunning
        if shouldKill { didFire = true }
        lock.unlock()
        if shouldKill { process.terminate() }
    }
}
