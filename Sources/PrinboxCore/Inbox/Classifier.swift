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
    /// Nil is hidden: a PR from the `involved` search where no answer is owed and no review of the viewer's exists.
    /// Hidden beats snoozed, so a parked PR that stopped concerning the viewer disappears instead of lingering in
    /// Waiting on others.
    /// Otherwise `snoozed` overrides everything: the PR waits in Waiting on others until it wakes. The quiet
    /// Reviewed state is the exception: it keeps its verdict, so the builder hides it unless Reviewed shows
    /// (spec 0.8 3.9).
    public static func classify(_ pr: PullRequest, viewer: String, snoozed: Bool = false) -> Classification? {
        guard let verdict = verdict(pr, viewer: viewer) else { return nil }
        if snoozed, verdict.section != .reviewed {
            return Classification(section: .waitingOnOthers, reason: .snoozed, waitingSince: nil)
        }
        return verdict
    }

    /// Order (Pullover): a request not yet answered, an answer owed, a re-request, a push after your verdict, a
    /// mention, the quiet reviewed state, hidden.
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
        case .mentions, .involved, .mine:
            break
        }
        if let pushed = pushedReason(pr) {
            return Classification(section: .takeAnotherLook, reason: pushed, waitingSince: WaitingSince.pushed(pr))
        }
        if pr.source == .mentions {
            return Classification(section: .mentions, reason: .mentioned, waitingSince: pr.updatedAt)
        }
        return reviewedReason(pr).map { Classification(section: .reviewed, reason: $0, waitingSince: nil) }
    }

    /// The viewer's verdict with the diff moved since: the author pushed after the review (spec 0.8 3.4).
    static func pushedReason(_ pr: PullRequest) -> Reason? {
        guard pr.movedSinceVerdict, let state = pr.viewerVerdict?.state else { return nil }
        return state == "APPROVED" ? .pushedSinceApproval : .pushedSinceChangesRequested
    }

    /// The quiet state of a reviewed PR: the verdict, or a comment-only review (latest review state COMMENTED).
    /// Any other review without a verdict (a dismissed approval) is nothing by itself (ruling 12.9).
    static func reviewedReason(_ pr: PullRequest) -> Reason? {
        switch pr.viewerVerdict?.state {
        case "APPROVED": return .youApproved
        case "CHANGES_REQUESTED": return .youRequestedChanges
        default: return pr.viewerReview?.state == "COMMENTED" ? .youCommented : nil
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
