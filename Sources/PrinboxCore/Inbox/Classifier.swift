// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

public struct Classification: Sendable, Equatable {
    public let section: SectionKind
    public let reason: Reason
    /// When the viewer started being waited on; nil for sections sorted by recency.
    public let waitingSince: Date?
}

/// Assigns a PR to a section: the search it came from decides review vs mention vs own, and own PRs are
/// split by the first action reason that applies.
public enum Classifier {
    public static func classify(_ pr: PullRequest) -> Classification {
        switch pr.source {
        case .review:
            pr.viewerReview == nil
                ? Classification(
                    section: .needsReview, reason: .reviewRequested, waitingSince: WaitingSince.reviewRequest(pr))
                : Classification(
                    section: .takeAnotherLook, reason: .reReviewRequested, waitingSince: WaitingSince.reReview(pr))
        case .mentions:
            Classification(section: .mentions, reason: .mentioned, waitingSince: pr.updatedAt)
        case .mine:
            ownActionReason(pr).map { Classification(section: .yourPRs, reason: $0, waitingSince: nil) }
                ?? Classification(
                    section: .waitingOnOthers, reason: pr.isDraft ? .draft : .waitingForReview, waitingSince: nil)
        }
    }

    /// First match wins: changes requested, merge conflicts, red CI, approved (not draft, CI not running).
    /// Waiting for CI is a deviation from Pullover: nothing can be merged until it finishes.
    static func ownActionReason(_ pr: PullRequest) -> Reason? {
        if pr.reviewDecision == .changesRequested { return .changesRequested }
        if pr.mergeable == .conflicting { return .mergeConflicts }
        if pr.ci == .failure { return .ciRed }
        if pr.reviewDecision == .approved && !pr.isDraft && pr.ci != .pending { return .readyToMerge }
        return nil
    }
}
