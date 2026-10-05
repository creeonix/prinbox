# Rebuilds a recorded two-phase fixture ({search, details}) from an allowlist of fields, replacing everything
# private with deterministic placeholders: owners -> org-K, repositories -> org-K/repo-N, logins -> user-N
# (the viewer -> me), titles -> "PR title N", ids -> PR_N, branch names -> ref-K, urls and avatar urls rebuilt
# from those, error messages redacted. Everything is numbered in sorted order, so distinct values stay
# distinct and the search and details parts agree. Fields not listed here are dropped, so extending a query
# can never leak new data into a fixture. Comment and review bodies are never queried in the first place.
.search.data.viewer.login as $viewer
| [.details[]?.data.nodes[]? | select(. != null and .id != null)] as $prs
| ([.search.data | (.review, .mentions, .mine, .involved) | .nodes[]? | select(. != null and .id != null) | .id]
   + [$prs[].id] | unique) as $ids
| ([$prs[].repository.nameWithOwner] | unique) as $repos
| ([$repos[] | split("/")[0]] | unique) as $owners
| ([$prs[] | .author.login?, (.timelineItems.nodes[]?.requestedReviewer.login?),
     (.reviewThreads.nodes[]?.comments.nodes[]?.author.login?), (.reviews.nodes[]?.author.login?)]
   | map(select(. != null and . != $viewer)) | unique) as $logins
| ([$prs[] | .headRefName?, .baseRefName?] | map(select(. != null)) | unique) as $refs
| def login($l):
    if $l == null then null elif $l == $viewer then "me" else "user-\(($logins | index($l)) + 1)" end;
  def prid($id): "PR_\(($ids | index($id)) + 1)";
  def ref($r): if $r == null then null else "ref-\(($refs | index($r)) + 1)" end;
  def ownerIndex($r): ($owners | index($r | split("/")[0])) + 1;
  def owner($r): "org-\(ownerIndex($r))";
  def repo($r): "\(owner($r))/repo-\(($repos | index($r)) + 1)";
  def ownerNode($r):
    if . == null then null
    else {__typename, login: owner($r), avatarUrl: "https://avatars.githubusercontent.com/u/\(1000 + ownerIndex($r))?v=4"} end;
  def actor: if . == null then null else {login: login(.login)} end;
  def reviewer:
    if . == null then null
    else {__typename} + (if .login then {login: login(.login)} else {} end) end;
  def event:
    {__typename, createdAt} + (if has("requestedReviewer") then {requestedReviewer: (.requestedReviewer | reviewer)} else {} end);
  def connection(f): if . == null then null else {totalCount, nodes: [(.nodes // [])[] | if . == null then null else f end]} end;
  def comment: {author: (.author | actor), createdAt};
  def threadNode: {isResolved, comments: (.comments | connection(comment))};
  def reviewNode: {author: (.author | actor), state, submittedAt};
  def rate: if . == null then null else {cost, remaining, resetAt} end;
  def errors: if .errors then {errors: (.errors | map({type, message: "redacted"}))} else {} end;
  def anon:
    if . == null or .id == null then . else
      .id as $id
      | (($ids | index($id)) + 1) as $n
      | .repository.nameWithOwner as $raw
      | repo($raw) as $repo
      | {
          id: prid($id), number, title: "PR title \($n)", url: "https://github.com/\($repo)/pull/\(.number)",
          isDraft, additions, deletions, createdAt, updatedAt, totalCommentsCount,
          headRefName: ref(.headRefName), baseRefName: ref(.baseRefName), isCrossRepository,
          author: (if .author == null then null
            else {login: login(.author.login), avatarUrl: "https://avatars.githubusercontent.com/u/\($n)?v=4"} end),
          repository: {nameWithOwner: $repo, isArchived: .repository.isArchived, owner: (.repository.owner | ownerNode($raw))},
          reviewDecision, mergeable,
          viewerLatestReview: (.viewerLatestReview | if . == null then null else {state, submittedAt} end),
          latestOpinionatedReviews: (.latestOpinionatedReviews | connection({state})),
          commits: {nodes: [(.commits.nodes // [])[] | if . == null then null else
            {commit: {committedDate: .commit.committedDate,
              statusCheckRollup: (.commit.statusCheckRollup | if . == null then null else {state} end)}} end]},
          timelineItems: {nodes: [(.timelineItems.nodes // [])[] | if . == null then null else event end]},
          reviewThreads: (.reviewThreads | connection(threadNode)),
          reviews: (.reviews | connection(reviewNode))
        }
    end;
  def hit: if . == null then null elif .id == null then {} else {id: prid(.id), updatedAt} end;
  def search: if . == null then null else {issueCount, nodes: (.nodes // [] | map(hit))} end;
  {
    search: ({
      data: {
        viewer: {login: "me"},
        rateLimit: (.search.data.rateLimit | rate),
        review: (.search.data.review | search),
        mentions: (.search.data.mentions | search),
        mine: (.search.data.mine | search),
        involved: (.search.data.involved | search)
      }
    } + (.search | errors)),
    details: [.details[]? | ({data: {rateLimit: (.data.rateLimit | rate), nodes: [(.data.nodes // [])[] | anon]}} + errors)]
  }
