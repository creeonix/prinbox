import Foundation
import Testing

@testable import PrinboxCore

@Suite struct AvatarAttemptsTests {
    let start = date("2026-08-10T12:00:00Z")

    @Test func neverAttemptedLoginsAreAttempted() {
        #expect(AvatarAttempts().shouldAttempt("alice", now: start))
    }

    @Test func inFlightAndLoadedLoginsAreNotAttemptedAgain() {
        let pending = AvatarAttempts().recordingAttempt("alice")
        #expect(pending.shouldAttempt("alice", now: start) == false)
        let loaded = pending.recordingSuccess("alice")
        #expect(loaded.shouldAttempt("alice", now: start + 3600) == false)
        #expect(loaded.shouldAttempt("bob", now: start))
    }

    @Test func failuresAreRetriedAfterTheInterval() {
        let failed = AvatarAttempts(retryAfter: 300).recordingAttempt("alice").recordingFailure("alice", at: start)
        #expect(failed.shouldAttempt("alice", now: start + 299) == false)
        #expect(failed.shouldAttempt("alice", now: start + 300))
        let again = failed.recordingAttempt("alice")
        #expect(again.shouldAttempt("alice", now: start + 600) == false)
    }
}
