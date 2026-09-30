// Ported from Pullover (https://github.com/omgovich/pullover), src/core/threads.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// Review-thread rules. Resolved threads are dropped here and nowhere else, so "resolved is invisible"
/// holds in one place. A PR without thread data answers nothing. Logins compare case-insensitively.
enum Threads {
    static func sameLogin(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    static func isOwn(_ pr: PullRequest, viewer: String) -> Bool {
        sameLogin(pr.authorLogin, viewer)
    }

    static func unresolved(_ pr: PullRequest) -> [ReviewThread] {
        (pr.threads ?? []).filter { !$0.isResolved }
    }

    /// Unresolved threads the viewer commented in where somebody else spoke last: answers the viewer owes.
    static func awaitingReply(_ pr: PullRequest, viewer: String) -> [ReviewThread] {
        unresolved(pr).filter { thread in
            thread.comments.contains { sameLogin($0.authorLogin, viewer) }
                && someoneElseSpokeLast(thread, viewer: viewer)
        }
    }

    /// Unresolved threads where somebody else spoke last, whoever took part: on the viewer's own PR a
    /// reviewer's brand-new thread still needs an answer.
    static func unanswered(_ pr: PullRequest, viewer: String) -> [ReviewThread] {
        unresolved(pr).filter { someoneElseSpokeLast($0, viewer: viewer) }
    }

    /// When the viewer was first left owing an answer in the thread: the comment right after their last
    /// one, or the thread's first when they never spoke. Nil when they spoke last.
    static func pendingSince(_ thread: ReviewThread, viewer: String) -> Date? {
        let next = thread.comments.lastIndex { sameLogin($0.authorLogin, viewer) }.map { $0 + 1 } ?? 0
        return thread.comments.indices.contains(next) ? thread.comments[next].createdAt : nil
    }

    /// The oldest answer owed across the threads. Oldest, because it dates how long the viewer has been on
    /// the hook: a "bump" today must not make last week's question look fresh.
    static func oldestPendingReplyAt(_ threads: [ReviewThread], viewer: String) -> Date? {
        threads.compactMap { pendingSince($0, viewer: viewer) }.min()
    }

    private static func someoneElseSpokeLast(_ thread: ReviewThread, viewer: String) -> Bool {
        guard let last = thread.comments.last else { return false }
        return !sameLogin(last.authorLogin, viewer)
    }
}
