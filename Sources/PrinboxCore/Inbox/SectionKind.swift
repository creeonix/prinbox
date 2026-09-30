import Foundation

/// Inbox sections, declared in display order.
public enum SectionKind: String, CaseIterable, Sendable, Codable {
    case needsReview
    case repliesToYou
    case takeAnotherLook
    case mentions
    case yourPRs
    case waitingOnOthers

    public var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .repliesToYou: "Replies to you"
        case .takeAnotherLook: "Take another look"
        case .mentions: "Mentions"
        case .yourPRs: "Your PRs"
        case .waitingOnOthers: "Waiting on others"
        }
    }

    /// Non-draft PRs in these sections are what the menu-bar badge counts.
    public var countsTowardBadge: Bool {
        self == .needsReview || self == .repliesToYou || self == .takeAnotherLook || self == .mentions
    }

    /// Own-PR sections are sorted newest first and show "updated X ago" instead of "waiting X".
    public var sortsByRecency: Bool { self == .yourPRs || self == .waitingOnOthers }

    public var usesCompactRows: Bool { self == .waitingOnOthers }

    public var moreURL: URL {
        switch self {
        case .repliesToYou:
            URL(string: "https://github.com/pulls?q=is%3Aopen+is%3Apr+involves%3A%40me+-author%3A%40me")!
        case .needsReview, .takeAnotherLook: URL(string: "https://github.com/pulls/review-requested")!
        case .mentions: URL(string: "https://github.com/pulls/mentioned")!
        case .yourPRs, .waitingOnOthers: URL(string: "https://github.com/pulls")!
        }
    }
}

public enum ReasonTone: Sendable, Equatable {
    case attention
    case failure
    case success
    case neutral
}

/// Why a PR is in its section. The raw value is the status text shown on the row.
public enum Reason: String, Sendable, Equatable {
    case reviewRequested = "Review requested"
    case reReviewRequested = "Re-review requested"
    case mentioned = "Mentioned"
    case awaitingReply = "Awaiting your reply"
    case openThreads = "Open threads"
    case changesRequested = "Changes requested"
    case mergeConflicts = "Merge conflicts"
    case ciRed = "CI is red"
    case readyToMerge = "Ready to merge"
    case draft = "Draft"
    case waitingForReview = "Waiting for review"
    case snoozed = "Snoozed"

    public var tone: ReasonTone {
        switch self {
        case .reviewRequested, .reReviewRequested, .mentioned, .awaitingReply, .openThreads: .attention
        case .changesRequested, .mergeConflicts, .ciRed: .failure
        case .readyToMerge: .success
        case .draft, .waitingForReview, .snoozed: .neutral
        }
    }
}
