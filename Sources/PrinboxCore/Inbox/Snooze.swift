import Foundation

/// The snooze rule: a PR stays hidden until its `updatedAt` moves. That is the only signal the inbox query
/// has, so the user's own activity wakes a PR too.
public enum Snooze {
    /// Entries that survive a fetch. An entry whose PR came back with a newer `updatedAt` is woken (dropped).
    /// When the fetch is complete, entries for PRs it did not return are dropped as well; an incomplete
    /// fetch keeps them, because the PR may only be missing from this response.
    public static func reconcile(_ entries: [String: SnoozeEntry], with result: FetchResult) -> [String: SnoozeEntry] {
        let updated = Dictionary(
            result.pullRequests.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        return entries.filter { id, entry in
            guard let updatedAt = updated[id] else { return !result.isComplete }
            return updatedAt <= entry.updatedAt
        }
    }
}
