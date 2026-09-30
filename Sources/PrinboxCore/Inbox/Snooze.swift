// The thread and commit conditions follow Pullover (https://github.com/omgovich/pullover), src/core/snooze.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// The snooze rule. With thread data a PR wakes only when someone else did something that addresses the
/// viewer; without it (Follow review threads off, or details missing) any `updatedAt` change wakes it, so
/// the viewer's own activity counts too.
public enum Snooze {
    /// Entries that survive a fetch. An entry whose PR woke is dropped. When the fetch is complete, entries
    /// for PRs it did not return are dropped as well; an incomplete fetch keeps them, because the PR may only
    /// be missing from this response.
    public static func reconcile(_ entries: [String: SnoozeEntry], with result: FetchResult) -> [String: SnoozeEntry] {
        let byID = Dictionary(result.pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return entries.filter { id, entry in
            guard let pr = byID[id] else { return !result.isComplete }
            return !wakes(pr, entry: entry, viewer: result.viewerLogin)
        }
    }

    /// Wakes when, after `snoozedAt`: someone else commented in an unresolved thread the viewer took part
    /// in (any unresolved thread on the viewer's own PR); the last commit is newer; a review was requested
    /// again; or, on the viewer's own PR, someone else submitted a review. Comparisons are strict, so a
    /// reply in the same second as the snooze does not count.
    static func wakes(_ pr: PullRequest, entry: SnoozeEntry, viewer: String) -> Bool {
        guard let threads = pr.threads else { return pr.updatedAt > entry.updatedAt }
        let since = entry.snoozedAt
        let own = Threads.isOwn(pr, viewer: viewer)
        let isViewer = { (login: String) in Threads.sameLogin(login, viewer) }
        let replied = threads.filter { !$0.isResolved }.contains { thread in
            let concernsViewer = own || thread.comments.contains { isViewer($0.authorLogin) }
            return concernsViewer && thread.comments.contains { !isViewer($0.authorLogin) && $0.createdAt > since }
        }
        if replied { return true }
        if let committed = pr.lastCommitAt, committed > since { return true }
        if let requested = pr.reviewRequestedAt, requested > since { return true }
        if own, let reviews = pr.reviews,
            reviews.contains(where: { !isViewer($0.authorLogin) && ($0.submittedAt ?? .distantPast) > since })
        {
            return true
        }
        return false
    }
}
