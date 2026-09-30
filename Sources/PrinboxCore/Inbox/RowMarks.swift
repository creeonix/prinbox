import Foundation

public enum CIMark: Sendable, Equatable {
    case passed, failed, running

    public var help: String {
        switch self {
        case .passed: "CI passed"
        case .failed: "CI failed"
        case .running: "CI running"
        }
    }
}

public enum ReviewMark: Sendable, Equatable {
    case approved, changesRequested

    public var help: String {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        }
    }
}

public enum MergeMark: Sendable, Equatable {
    case ready, conflicts

    public var help: String {
        switch self {
        case .ready: "Ready to merge"
        case .conflicts: "Merge conflicts"
        }
    }
}

/// The status marks at the right edge of a row. Absent marks are nil, so a quiet PR shows nothing.
/// "Not yet reviewed" is never a mark: the section already says it.
public struct RowMarks: Sendable, Equatable {
    public let comments: Int?
    public let ci: CIMark?
    public let review: ReviewMark?
    public let merge: MergeMark?

    public init(comments: Int?, ci: CIMark?, review: ReviewMark?, merge: MergeMark?) {
        self.comments = comments
        self.ci = ci
        self.review = review
        self.merge = merge
    }

    /// A ready PR shows only the merge mark; its green CI and review marks would repeat it.
    public static func marks(for pr: PullRequest) -> RowMarks {
        let ready = isReady(pr)
        return RowMarks(
            comments: pr.commentCount > 0 ? pr.commentCount : nil,
            ci: ready ? nil : ciMark(pr.ci),
            review: ready ? nil : reviewMark(pr.reviewDecision),
            merge: pr.mergeable == .conflicting ? .conflicts : (ready ? .ready : nil))
    }

    /// Approved, not a draft, no conflicts, and CI passed or absent.
    public static func isReady(_ pr: PullRequest) -> Bool {
        pr.reviewDecision == .approved && !pr.isDraft && pr.mergeable != .conflicting
            && (pr.ci == .success || pr.ci == .none)
    }

    public static func commentsHelp(_ count: Int) -> String {
        count == 1 ? "1 comment" : "\(count) comments"
    }

    static func ciMark(_ ci: CIState) -> CIMark? {
        switch ci {
        case .success: .passed
        case .failure: .failed
        case .pending: .running
        case .none: nil
        }
    }

    static func reviewMark(_ decision: ReviewDecision) -> ReviewMark? {
        switch decision {
        case .approved: .approved
        case .changesRequested: .changesRequested
        case .reviewRequired, .none: nil
        }
    }
}
