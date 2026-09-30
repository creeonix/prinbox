# The state file

PRInbox remembers what it knows about individual pull requests in one JSON file:

`~/Library/Application Support/prinbox/state.json`

It is meant to be read and written by more than one program (the app today, an MCP server later), so this
page is the contract. `Sources/PrinboxCore/State/AppState.swift` is the reference implementation.

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
| `version` | integer | The schema version, 1. Missing means 1. |
| `snoozed` | object keyed by PR node id | PRs the user parked. `snoozedAt`: when. `updatedAt`: the PR's `updatedAt` at that moment, which the fallback wake rule compares against. Missing means no snoozes. |
| `seen` | object keyed by PR node id, or absent | The PR's `updatedAt` when the user last closed the popover over it. Absent until the first fetch seeds it, which is different from empty: absent means "never looked", empty means "the inbox was empty when last looked at". |

Keys are GitHub GraphQL node ids (`PR_kwDO...`). Dates are ISO 8601 in UTC with whole seconds and a `Z`
suffix. The file is pretty-printed with sorted keys and written atomically (a temporary file renamed into
place), so a reader never sees a partial file.

## Rules for readers

- Ignore keys you do not know.
- Treat a missing `version` as 1 and a missing `snoozed` as empty; `seen` may be absent.
- A file that is not a JSON object is unreadable. The app logs it, starts with an empty state in memory and
  overwrites the file on its next change; `--print` warns on stderr and ignores snoozes.
- A `version` higher than you know: load the keys you know and keep that number when you write.

## Rules for writers

- Write your own `version` when you create the file; keep the file's when you rewrite it.
- `version` changes only for incompatible shape changes. Adding an optional key keeps it at 1.
- Unknown keys are dropped on write. Every writer therefore has to ship the same `PrinboxCore` (the app and
  the MCP server are built from one repository); mixing builds loses the newer build's keys.
- Write atomically; never append.

## Who writes when

The app writes on snooze and unsnooze, after every fetch that woke or pruned a snooze or pruned the ledger, and
when the popover closes (the rows shown become seen). `Prinbox --print` never writes. `--demo` never touches
the file.
