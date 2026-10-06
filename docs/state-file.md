# The state, cache and settings files

PRInbox remembers what it knows about individual pull requests in one JSON file:

`~/Library/Application Support/prinbox/state.json`

It is meant to be read and written by more than one program (the app, the `prinbox` command and `prinbox mcp`),
so this page is the contract. `Sources/PrinboxCore/State/AppState.swift` is the reference implementation.

## Files

PRInbox keeps five files, written by the app, the command and the server:

| File | Directory (macOS; Linux) | Holds | Writers |
|---|---|---|---|
| `settings.json` | `~/.config/prinbox` (`$XDG_CONFIG_HOME/prinbox`) | every setting (section "Settings") | the app |
| `state.json` | `~/Library/Application Support/prinbox` (`$XDG_STATE_HOME/prinbox`) | snoozes and the seen ledger: the contract below | the app, the command and the server |
| `cache.json` | same directory | the last fetch and its bookkeeping (section "Cache") | the app, the command and the server |
| `update.json` | same directory | the daily release check (`updateCheckedAt`, `latestRelease`) | the app |
| `prinbox.lock` | same directory | nothing: an advisory lock (`flock`) | whoever writes `state.json` or `cache.json` |

Every write of `state.json` or `cache.json` is reload, apply, replace, under the lock: the writer takes the
lock, re-reads the file, applies its one change and replaces the file atomically. The lock is held for
milliseconds, never during a fetch, and a writer that cannot get it within two seconds writes anyway and
logs a notice. So `state.json` is the truth and memory mirrors it: a snooze from the command shows in the
popover on its next refresh or open, and a snooze in the popover shows in `prinbox inbox --cached` at once.

| Writer | `settings.json` | `state.json` | `cache.json` |
|---|---|---|---|
| App | Settings changes, folds, org colors, the one-time migration from defaults | snooze, unsnooze, fetch reconciliation (wake, prune, seed `seen`), popover close | after every full fetch; `checkedAt` on an unchanged check |
| `prinbox inbox` | never | wake and prune after a complete, unscoped fetch | after a fetch (`attention` only with `--notify`); `checkedAt` on unchanged; nothing when served from the cache |
| `prinbox snooze`, `unsnooze` | never | the entry; when it had to fetch, wake and prune after a complete, unscoped fetch | only when `snooze` had to fetch |
| `prinbox open` | never | when it had to fetch, wake and prune after a complete, unscoped fetch | only when it had to fetch |
| `prinbox mcp` | never | snooze and unsnooze entries; wake and prune after a complete, unscoped fetch | after a fetch (`attention` left as found); `checkedAt` on unchanged; nothing when served |
| `prinbox print`, `Prinbox --print` | never | never | never |
| `--demo` | never | never | never |

### Settings

`settings.json` is one JSON object of the keys the app's stores keep: `compactRows`, `directReviewRequestsOnly`,
`foldedSections`, `followReviewThreads`, `ghPath`, `globalShortcut`, `groupByOrganization`, `hideDrafts`,
`notifyOnNewReviewRequests`, `orgColors`, `showOrganizationAvatars`. A missing key means its default. The app
rewrites one key at a time after re-reading the file, so a hand edit made while the app runs survives; the edit
itself takes effect at the next launch. The command and the server read `followReviewThreads`, `ghPath`,
`directReviewRequestsOnly` and `hideDrafts`; the server reads them at every call. On the first 0.5.0 launch the app
copies every known key out of the `io.github.creeonix.prinbox` defaults domain into the file and removes it there.

### Cache

`cache.json` is not a contract: its shape may change with any release, and a `version` a reader does not know
means "no cache". Other programs read the inbox through `prinbox inbox --format json` (see
`docs/inbox-json.md`). For transparency, its keys: `version` (1), `fetchedAt` (when `result` was fetched),
`checkedAt` (the last time GitHub confirmed it, including an unchanged check), `includeConversation` (the
request shape it came from), `scope` (the two scope settings the request had; absent in a 0.5 file, which
means none), `viewer`, `fingerprint` (id to `updatedAt` over every search hit),
`attention` (the arrivals baseline: the non-draft ids of the attention sections, written only by a
notifier), `result` (the fetch: `viewerLogin`, `pullRequests`, `totals`, `fetched`, `warnings`). Nothing in it
is body text: the same fields the popover shows, titles, logins and URLs included. Readers trust the
fingerprint for 15 minutes and only for the same `includeConversation` and `scope`; the rows and the baseline
have no age limit. A `checkedAt` bump on an unchanged check is written only when the file still holds the
fingerprint that check confirmed.

## Shape

```json
{
  "seen" : {
    "PR_kwDOA1" : "2026-09-30T10:12:00Z"
  },
  "snoozed" : {
    "PR_kwDOA2" : {
      "snoozedAt" : "2026-09-30T09:00:00Z",
      "updatedAt" : "2026-09-29T17:40:00Z"
    }
  },
  "version" : 1
}
```

| Key | Type | Meaning |
|---|---|---|
| `version` | integer | The schema version, 1. Missing means the version this build writes. |
| `snoozed` | object keyed by PR node id | PRs the user parked. `snoozedAt`: when. `updatedAt`: the PR's `updatedAt` at that moment, which the fallback wake rule compares against. Missing means no snoozes. |
| `seen` | object keyed by PR node id, or absent | The PR's `updatedAt` when the user last closed the popover over it. Absent until the first fetch seeds it, which is different from empty: absent means "never looked", empty means "the inbox was empty when last looked at". |

Keys are GitHub GraphQL node ids (`PR_kwDO...`). Dates are ISO 8601 in UTC with whole seconds and a `Z`
suffix. The file is pretty-printed with sorted keys and written atomically (a temporary file renamed into
place), so a reader never sees a partial file.

## Rules for readers

- Ignore keys you do not know.
- Treat a missing `version` as the version this build writes (1 today) and a missing `snoozed` as empty; `seen` may be absent.
- A file that is not a JSON object is unreadable. The app logs it, starts with an empty state in memory and
  overwrites the file on its next change; `--print` warns on stderr and ignores snoozes.
- A file larger than 8 MB is unreadable: the real file is kilobytes.
- A `version` higher than you know: load the keys you know and keep that number when you write.

## Rules for writers

- Write your own `version` when you create the file; keep the file's when you rewrite it.
- `version` changes only for incompatible shape changes. Adding an optional key keeps it at 1.
- Unknown keys are dropped on write. Every writer therefore has to ship the same `PrinboxCore` (the app and
  the MCP server are built from one repository); mixing builds loses the newer build's keys.
- Write atomically; never append.

## Who writes when

The app writes on snooze and unsnooze, after every fetch that woke or pruned a snooze or pruned the ledger, and
when the popover closes (the rows shown become seen). The `prinbox` command writes on `snooze` and `unsnooze`, and
wakes and prunes after a complete, unscoped fetch; it never writes `seen`. `prinbox mcp` writes as the command
does, on the agent's snooze and unsnooze and after its own fetches. `Prinbox --print` never writes. `--demo` never
touches the file.
