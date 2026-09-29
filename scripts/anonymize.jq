# Replaces everything private in a recorded inbox response with deterministic placeholders:
# repositories -> acme/repo-N, logins -> user-N (the viewer -> me), titles -> "PR title N",
# ids -> PR_N, urls and avatar urls rebuilt from those, error messages redacted.
.data.viewer.login as $viewer
| [.data | (.review, .mentions, .mine) | .nodes[]? | select(. != null and .id != null)] as $prs
| ([$prs[].repository.nameWithOwner] | unique) as $repos
| ([$prs[].id] | unique) as $ids
| ([$prs[] | .author.login?, (.timelineItems.nodes[]?.requestedReviewer.login?)]
   | map(select(. != null and . != $viewer)) | unique) as $logins
| def login($l):
    if $l == null then null elif $l == $viewer then "me" else "user-\(($logins | index($l)) + 1)" end;
  def repo($r): "acme/repo-\(($repos | index($r)) + 1)";
  def anon:
    if . == null or .id == null then . else
      .id as $id
      | (($ids | index($id)) + 1) as $n
      | repo(.repository.nameWithOwner) as $repo
      | .id = "PR_\($n)"
      | .title = "PR title \($n)"
      | .url = "https://github.com/\($repo)/pull/\(.number)"
      | .repository.nameWithOwner = $repo
      | .author |= (if . == null then null
          else {login: login(.login), avatarUrl: "https://avatars.githubusercontent.com/u/\($n)?v=4"} end)
      | .timelineItems.nodes |= ((. // []) | map(
          if .requestedReviewer.login? then .requestedReviewer.login |= login(.) else . end))
    end;
  .data.viewer.login = "me"
  | .data.review.nodes |= map(anon)
  | .data.mentions.nodes |= map(anon)
  | .data.mine.nodes |= map(anon)
  | if .errors then .errors |= map({type, message: "redacted"}) else . end
