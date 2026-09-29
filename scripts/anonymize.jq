# Rebuilds a recorded inbox response from an allowlist of fields, replacing everything private with
# deterministic placeholders: repositories -> acme/repo-N, logins -> user-N (the viewer -> me),
# titles -> "PR title N", ids -> PR_N, urls and avatar urls rebuilt from those, error messages redacted.
# Fields not listed here are dropped, so extending InboxQuery can never leak new data into a fixture.
.data.viewer.login as $viewer
| [.data | (.review, .mentions, .mine) | .nodes[]? | select(. != null and .id != null)] as $prs
| ([$prs[].repository.nameWithOwner] | unique) as $repos
| ([$prs[].id] | unique) as $ids
| ([$prs[] | .author.login?, (.timelineItems.nodes[]?.requestedReviewer.login?)]
   | map(select(. != null and . != $viewer)) | unique) as $logins
| def login($l):
    if $l == null then null elif $l == $viewer then "me" else "user-\(($logins | index($l)) + 1)" end;
  def repo($r): "acme/repo-\(($repos | index($r)) + 1)";
  def reviewer:
    if . == null then null
    else {__typename} + (if .login then {login: login(.login)} else {} end) end;
  def event:
    {__typename, createdAt} + (if has("requestedReviewer") then {requestedReviewer: (.requestedReviewer | reviewer)} else {} end);
  def anon:
    if . == null or .id == null then . else
      .id as $id
      | (($ids | index($id)) + 1) as $n
      | repo(.repository.nameWithOwner) as $repo
      | {
          id: "PR_\($n)", number, title: "PR title \($n)", url: "https://github.com/\($repo)/pull/\(.number)",
          isDraft, additions, deletions, createdAt, updatedAt,
          author: (if .author == null then null
            else {login: login(.author.login), avatarUrl: "https://avatars.githubusercontent.com/u/\($n)?v=4"} end),
          repository: {nameWithOwner: $repo, isArchived: .repository.isArchived},
          reviewDecision, mergeable,
          viewerLatestReview: (.viewerLatestReview | if . == null then null else {state, submittedAt} end),
          commits: {nodes: [(.commits.nodes // [])[] | if . == null then null else
            {commit: {committedDate: .commit.committedDate,
              statusCheckRollup: (.commit.statusCheckRollup | if . == null then null else {state} end)}} end]},
          timelineItems: {nodes: [(.timelineItems.nodes // [])[] | if . == null then null else event end]}
        }
    end;
  def search: if . == null then null else {issueCount, nodes: (.nodes // [] | map(anon))} end;
  {
    data: {
      viewer: {login: "me"},
      rateLimit: (.data.rateLimit | if . == null then null else {cost, remaining, resetAt} end),
      review: (.data.review | search),
      mentions: (.data.mentions | search),
      mine: (.data.mine | search)
    }
  }
  + (if .errors then {errors: (.errors | map({type, message: "redacted"}))} else {} end)
