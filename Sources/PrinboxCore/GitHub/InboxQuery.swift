/// The single GraphQL request behind every refresh. Estimated cost 3 points (v0.2 added
/// latestOpinionatedReviews under each PR); v1 measured 2 points and about 6 s.
/// The three searches are disjoint: mentions excludes your own PRs and PRs where you are a requested reviewer.
public enum InboxQuery {
    public static let text = """
        query Inbox {
          viewer { login }
          rateLimit { cost remaining resetAt }
          review: search(query: "is:pr is:open archived:false review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
          mentions: search(query: "is:pr is:open archived:false mentions:@me -author:@me -review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
          mine: search(query: "is:pr is:open archived:false author:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
        }
        fragment pr on PullRequest {
          id number title url isDraft additions deletions createdAt updatedAt totalCommentsCount
          author { login avatarUrl(size: 64) }
          repository { nameWithOwner isArchived owner { __typename login avatarUrl(size: 64) } }
          reviewDecision mergeable
          viewerLatestReview { state submittedAt }
          latestOpinionatedReviews(first: 10) { nodes { state } }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
          timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) {
            nodes {
              __typename
              ... on ReviewRequestedEvent { createdAt requestedReviewer { __typename ... on User { login } } }
              ... on ReadyForReviewEvent { createdAt }
            }
          }
        }
        """
}
