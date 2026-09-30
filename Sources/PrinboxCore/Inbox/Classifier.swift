// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

public struct Classification: Sendable, Equatable {
    public let section: SectionKind
    public let reason: Reason
    /// When the viewer started being waited on; nil for sections sorted by recency.
    public let waitingSince: Date?
}

/// Assigns a PR to a section: the search it came from decides review vs mention vs own, threads the viewer
/// owes an answer in make Replies to you, and own PRs are split by the first action reason that applies.
public enum Classifier {
    /// Nil is hidden: a PR from the `involved` search where no answer is owed. Hidden beats snoozed, so a
    /// parked PR that stopped concerning the viewer disappears instead of lingering in Waiting on others.
    /// Otherwise `snoozed` overrides everything: the PR waits in Waiting on others until it wakes.
    public static func classify(_ pr: PullRequest, viewer: String, snoozed: Bool = false) -> Classification? {
        guard let verdict = verdict(pr, viewer: viewer) else { return nil }
        if snoozed { return Classification(section: .waitingOnOthers, reason: .snoozed, waitingSince: nil) }
        return verdict
    }

    /// Order (Pullover): a request not yet answered, an answer owed, a re-request, a mention, hidden.
    static func verdict(_ pr: PullRequest, viewer: String) -> Classification? {
        if pr.source == .mine {
            return ownActionReason(pr, viewer: viewer).map {
                Classification(section: .yourPRs, reason: $0, waitingSince: nil)
            }
                ?? Classification(
                    section: .waitingOnOthers, reason: pr.isDraft ? .draft : .waitingForReview, waitingSince: nil)
        }
        if pr.source == .review, pr.viewerReview == nil {
            return Classification(
                section: .needsReview, reason: .reviewRequested, waitingSince: WaitingSince.reviewRequest(pr))
        }
        let awaiting = Threads.awaitingReply(pr, viewer: viewer)
        if !awaiting.isEmpty {
            let since = Threads.oldestPendingReplyAt(awaiting, viewer: viewer) ?? pr.updatedAt
            return Classification(
                section: .repliesToYou, reason: .awaitingReply, waitingSince: max(since, WaitingSince.visibleSince(pr)))
        }
        switch pr.source {
        case .review:
            return Classification(
                section: .takeAnotherLook, reason: .reReviewRequested, waitingSince: WaitingSince.reReview(pr))
        case .mentions:
            return Classification(section: .mentions, reason: .mentioned, waitingSince: pr.updatedAt)
        case .involved, .mine:
            return nil
        }
    }

    /// First match wins: changes requested, merge conflicts, open threads, red CI, approved (not draft, CI not
    /// running). Waiting for CI is a deviation from Pullover: nothing can be merged until it finishes.
    static func ownActionReason(_ pr: PullRequest, viewer: String) -> Reason? {
        if pr.reviewDecision == .changesRequested { return .changesRequested }
        if pr.mergeable == .conflicting { return .mergeConflicts }
        if !Threads.unanswered(pr, viewer: viewer).isEmpty { return .openThreads }
        if pr.ci == .failure { return .ciRed }
        if pr.reviewDecision == .approved && !pr.isDraft && pr.ci != .pending { return .readyToMerge }
        return nil
    }

    /// Threads waiting for the viewer's answer, shown in the comment tooltip: the threads they took part in
    /// for Awaiting your reply, every unanswered thread for Open threads, nothing for other reasons.
    public static func pendingReplies(_ pr: PullRequest, viewer: String, reason: Reason) -> Int {
        switch reason {
        case .awaitingReply: Threads.awaitingReply(pr, viewer: viewer).count
        case .openThreads: Threads.unanswered(pr, viewer: viewer).count
        default: 0
        }
    }
}
