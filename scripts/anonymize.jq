# Rebuilds a recorded inbox response from an allowlist of fields, replacing everything private with
# deterministic placeholders: owners -> org-K, repositories -> org-K/repo-N, logins -> user-N (the
# viewer -> me), titles -> "PR title N", ids -> PR_N, urls and avatar urls rebuilt from those, error
# messages redacted. Owners and repositories are numbered in sorted order, so distinct orgs stay distinct.
# Fields not listed here are dropped, so extending InboxQuery can never leak new data into a fixture.
.data.viewer.login as $viewer
| [.data | (.review, .mentions, .mine) | .nodes[]? | select(. != null and .id != null)] as $prs
| ([$prs[].repository.nameWithOwner] | unique) as $repos
| ([$repos[] | split("/")[0]] | unique) as $owners
| ([$prs[].id] | unique) as $ids
| ([$prs[] | .author.login?, (.timelineItems.nodes[]?.requestedReviewer.login?)]
   | map(select(. != null and . != $viewer)) | unique) as $logins
| def login($l):
    if $l == null then null elif $l == $viewer then "me" else "user-\(($logins | index($l)) + 1)" end;
  def ownerIndex($r): ($owners | index($r | split("/")[0])) + 1;
  def owner($r): "org-\(ownerIndex($r))";
  def repo($r): "\(owner($r))/repo-\(($repos | index($r)) + 1)";
  def ownerNode($r):
    if . == null then null
    else {__typename, login: owner($r), avatarUrl: "https://avatars.githubusercontent.com/u/\(1000 + ownerIndex($r))?v=4"} end;
  def reviewer:
    if . == null then null
    else {__typename} + (if .login then {login: login(.login)} else {} end) end;
  def event:
    {__typename, createdAt} + (if has("requestedReviewer") then {requestedReviewer: (.requestedReviewer | reviewer)} else {} end);
  def anon:
    if . == null or .id == null then . else
      .id as $id
      | (($ids | index($id)) + 1) as $n
      | .repository.nameWithOwner as $raw
      | repo($raw) as $repo
      | {
          id: "PR_\($n)", number, title: "PR title \($n)", url: "https://github.com/\($repo)/pull/\(.number)",
          isDraft, additions, deletions, createdAt, updatedAt, totalCommentsCount,
          author: (if .author == null then null
            else {login: login(.author.login), avatarUrl: "https://avatars.githubusercontent.com/u/\($n)?v=4"} end),
          repository: {nameWithOwner: $repo, isArchived: .repository.isArchived, owner: (.repository.owner | ownerNode($raw))},
          reviewDecision, mergeable,
          viewerLatestReview: (.viewerLatestReview | if . == null then null else {state, submittedAt} end),
          latestOpinionatedReviews: (.latestOpinionatedReviews | if . == null then null else
            {nodes: [(.nodes // [])[] | if . == null then null else {state} end]} end),
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
