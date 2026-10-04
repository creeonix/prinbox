import Foundation
import Testing

@testable import PrinboxCore

@Suite struct StderrLoggingTests {
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        func write(_ s: String) { lock.withLock { text += s } }
        var output: String { lock.withLock { text } }
    }

    @Test func defaultDropsInfoAndDebugAndRedactsTheDetail() {
        let sink = Sink()
        let log = StderrLogging(verbose: false, write: { sink.write($0) })
        log.debug(.gh, "fetch: 3 thread pages truncated")
        log.info(.gh, "fetch: 4 requests")
        log.notice(.gh, "details batch of 10 failed; retrying split", private: "timed out after 30 s")
        log.error(.gh, "gh exited 1", private: "gh: Bad credentials (HTTP 401)")
        #expect(
            sink.output
                == "prinbox: details batch of 10 failed; retrying split <private>\nprinbox: gh exited 1 <private>\n")
    }

    @Test func verbosePrintsEveryLevelAndTheDetail() {
        let sink = Sink()
        let log = StderrLogging(verbose: true, write: { sink.write($0) })
        log.info(.gh, "fetch: 4 requests")
        log.error(.gh, "gh exited 1", private: "gh: Bad credentials (HTTP 401)")
        #expect(sink.output == "prinbox: fetch: 4 requests\nprinbox: gh exited 1: gh: Bad credentials (HTTP 401)\n")
    }

    @Test func levelsOrderFromDebugToError() {
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .notice)
        #expect(LogLevel.notice < .error)
    }

    @Test func nullLoggingAcceptsEverything() {
        NullLogging().error(.state, "ignored", private: "also ignored")
    }
}
