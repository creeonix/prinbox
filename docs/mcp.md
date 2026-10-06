# The MCP server

`prinbox mcp` serves the inbox to AI agents over the Model Context Protocol: JSON-RPC 2.0, one message per
line on standard input and output, no network port. It links the same `PrinboxCore` as the app and the
`prinbox` command, reads the same `~/.config/prinbox/settings.json`, and shares `state.json` and `cache.json`
with them (see `docs/state-file.md`). Logs go to stderr, which the client keeps; `--verbose` adds the detail.

## Registering

| Client | How |
|---|---|
| Claude Code | `claude mcp add prinbox -- prinbox mcp` |
| Claude Desktop | `{ "mcpServers": { "prinbox": { "command": "prinbox", "args": ["mcp"] } } }` in `claude_desktop_config.json` |
| Anything else | a stdio server: command `prinbox`, argument `mcp`; `--settings <path>` names another settings file |

The server answers `initialize` with the client's protocol version when it is one of `2025-11-25`,
`2025-06-18`, `2025-03-26` or `2024-11-05`, else with `2025-11-25`; its only capability is `tools`.
The server reads `settings.json` again for every call, so a setting changed in the app applies to the agent's
next question.

## Tools

| Tool | Arguments | Result |
|---|---|---|
| `get_inbox` | `max_age_seconds` (integer, optional, default 60) | the document of `docs/inbox-json.md`, as `structuredContent` and serialized in the text block |
| `snooze_pull_request` | `id` (a `rows[].id` from `get_inbox`) | `{"id", "snoozed": true, "number", "repository", "title"}` and one text line |
| `unsnooze_pull_request` | `id` | the same with `"snoozed": false`; `number`, `repository` and `title` are `null` when the row is not in the cache |

`get_inbox` serves the cache when GitHub confirmed it within `max_age_seconds`, and fetches otherwise; `0`
fetches now. The document's `source` (`fetch`, `unchanged`, `cache`) and `checkedAt` say what the agent got.
A fetch beside the running app costs GitHub one request when nothing changed. Snooze parks a pull request
until something happens on it (a push, a reply in a thread the user took part in, a new review request, a
review on the user's own PR); both tools are idempotent. There is no tool to open a pull request: the URL is in
every row, and opening a browser is the client's job. The tools carry MCP annotations: `get_inbox` is
read-only, the other two are idempotent, none is destructive.

## Errors

| The command would | The server answers |
|---|---|
| exit 2 (unknown tool, a missing or malformed `id`, a bad `max_age_seconds`, an unknown argument) | JSON-RPC error `-32602` with the message |
| exit 1 or 3 on `get_inbox` (fetch failed, gh missing or signed out) | the document with `error` set and the cached rows if any, `isError: true`; when setup is needed, a second text block holds the setup steps |
| exit 1 or 3 on snooze or unsnooze | `isError: true` with the command's own message as the text |
| anything else | an unknown method is `-32601`; a line that is not JSON is `-32700` (a blank line gets no reply); a batch is `-32600` |

A `get_inbox` served from the cache is never an error, even when the last fetch failed: the call asked for
the cache and got it.

## Files and the lock

The server is one more writer of `state.json` and `cache.json`, under the same advisory lock as the app and the
command: every write re-reads the file, applies one change and replaces it. It writes snooze and unsnooze entries,
wakes and prunes snoozes after a complete, unscoped fetch, writes the cache after a fetch (leaving the arrivals
baseline as it found it) and bumps `checkedAt` on an unchanged check. It never writes the seen ledger or the
baseline, so it never affects which arrivals the app announces. Requests are handled one at a time.

## Logging

By default stderr carries notice and error lines with private details replaced by `<private>`; `--verbose`
adds info and debug lines, one per call (`mcp get_inbox: cache, exit 0`), with the details. Stdout carries
JSON-RPC only.
