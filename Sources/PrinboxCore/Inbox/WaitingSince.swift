// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// When the viewer started being waited on, per section.
enum WaitingSince {
    /// Nobody waits on a PR before it exists or while it is a draft.
    static func visibleSince(_ pr: PullRequest) -> Date {
        max(pr.createdAt, pr.readyForReviewAt ?? pr.createdAt)
    }

    static func reviewRequest(_ pr: PullRequest) -> Date {
        max(pr.reviewRequestedAt ?? pr.createdAt, visibleSince(pr))
    }

    /// A request counts only if it came after the viewer's review; otherwise fall back to the last update.
    static func reReview(_ pr: PullRequest) -> Date {
        let base: Date
        if let requested = pr.reviewRequestedAt, let reviewed = pr.viewerReview?.submittedAt, requested > reviewed {
            base = requested
        } else {
            base = pr.updatedAt
        }
        return max(base, visibleSince(pr))
    }
}
