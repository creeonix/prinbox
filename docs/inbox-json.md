# The inbox JSON

`prinbox inbox --format json` prints one JSON object: the classified inbox and where it came from. It is the
contract every adapter reads (the editor plugins, the tmux and Waybar modules, the pickers, the MCP server).
`version` is an integer: adding a key keeps it at 1, renaming or removing one bumps it. Readers ignore keys
they do not know. Dates are ISO 8601 UTC with whole seconds and a `Z` suffix. Every optional is written as
`null`, never left out. The document is pretty-printed with sorted keys.

The other formats derive from it: `lines` (one tab-separated row per line: id, kind, number, title,
repository, reasonText, age, flags, url; a `more:<kind>` line per capped section), `waybar` (Waybar's
custom-module object: `text`, `alt`, `class`, `tooltip`, always exit 0) and `tmux` (the count, empty when
idle, `!` when gh needs attention, `!N` when the fetch failed but N cached rows are known). `prinbox print`
is the text rendering: the fact line and the compact line both show `stack i/n`.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | GitHub answered, or the cache was served because `--cached` or `--max-age` asked for it |
| 1 | the fetch failed; cached rows may still be in the document, with `error` set and `source: "cache"` |
| 2 | usage |
| 3 | setup needed: gh not found or signed out (the steps are on stderr) |

`--format waybar` always exits 0, because Waybar hides a module whose command exits non-zero; `class` carries
the state instead.

## Keys

| Key | Meaning |
|---|---|
| `version` | the schema version, 1 |
| `prinbox` | the producing binary's version, for bug reports |
| `source` | `fetch`, `unchanged` or `cache`: fetched fully, confirmed unchanged by a one-point check, or printed without contacting GitHub (asked for, or the fallback after a failed fetch); null when nothing is known |
| `fetchedAt`, `checkedAt` | when the rows were fetched, and when GitHub last confirmed them (including an unchanged check); null when nothing is known |
| `viewer` | the login, null when nothing is known |
| `badge` | the menu-bar count: non-draft rows of Needs your review, Replies to you, Take another look and Mentions |
| `newCount` | rows new since the last look at the popover, from the app's seen ledger (0 where no app runs) |
| `error` | null, or `{"code", "message", "help"}`: `code` is one of `ghNotFound`, `loggedOut`, `offline`, `timedOut`, `rateLimited`, `badResponse`, `githubUnavailable`, `other`; `message` the text printed on stderr (for the two setup errors the guide's title); `help` the GitHub status page for a 5xx, the gh install page for `ghNotFound`, else null |
| `warnings` | partial-data warnings from GitHub |
| `sections` | all six, always, in display order, empty ones with `rows: []` |
| `sections[].kind`, `title` | `needsReview`, `repliesToYou`, `takeAnotherLook`, `mentions`, `yourPRs`, `waitingOnOthers`, and the display title |
| `sections[].count`, `moreCount`, `moreUrl` | rows the section holds, rows beyond the cap, the section's GitHub page |
| `rows[].id` | the GitHub node id; what `snooze`, `unsnooze` and `open` take |
| `rows[].number`, `title`, `url`, `repository`, `author`, `authorAvatarUrl`, `isDraft`, `additions`, `deletions`, `createdAt`, `updatedAt` | the pull request as fetched |
| `rows[].waitingSince`, `age` | the date the section sorts by (null in Your PRs and Waiting on others) and the short age the popover shows (`4h`, `2d`; for own rows the time since `updatedAt`) |
| `rows[].reason`, `reasonText` | a stable code and the display string: `reviewRequested`, `reReviewRequested`, `mentioned`, `awaitingReply`, `openThreads`, `changesRequested`, `mergeConflicts`, `ciRed`, `readyToMerge`, `draft`, `waitingForReview`, `snoozed` |
| `rows[].snoozed`, `isNew`, `pendingReplies` | parked by you; new since your last look; review threads waiting for your answer |
| `rows[].marks` | `comments` (a count or null), `ci` (`success`, `failure`, `pending` or null), `review` (`approved`, `changesRequested` or null), `merge` (`ready`, `conflicts` or null) |
| `rows[].stack` | null, or `{"position", "size", "parentId"}`: this PR's place in a chain of stacked pull requests, 1 being the one closest to the trunk; `parentId` null on that one |

## Example

One row of the demo inbox (`PrinboxApp --demo` shows the same data):

```json
{
  "additions" : 620,
  "age" : "2d",
  "author" : "bob",
  "authorAvatarUrl" : null,
  "createdAt" : "2026-08-05T12:00:00Z",
  "deletions" : 410,
  "id" : "DEMO_1290",
  "isDraft" : false,
  "isNew" : false,
  "marks" : { "ci" : "success", "comments" : 3, "merge" : null, "review" : null },
  "number" : 1290,
  "pendingReplies" : 0,
  "reason" : "reviewRequested",
  "reasonText" : "Review requested",
  "repository" : "acme/web",
  "snoozed" : false,
  "stack" : { "parentId" : null, "position" : 1, "size" : 2 },
  "title" : "Migrate the settings page to the new design system",
  "updatedAt" : "2026-08-10T09:00:00Z",
  "url" : "https://github.com/acme/web/pull/1290",
  "waitingSince" : "2026-08-08T10:00:00Z"
}
```
