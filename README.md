<p align="center">
  <img src="docs/images/icon.png" width="128" alt="PRInbox icon">
</p>

<h1 align="center">PRInbox</h1>

<p align="center">
  A macOS menu-bar inbox for the pull requests waiting on you, signed in through the GitHub CLI.
</p>

<p align="center">
  <a href="https://github.com/creeonix/prinbox/actions/workflows/ci.yml"><img src="https://github.com/creeonix/prinbox/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/creeonix/prinbox/releases/latest"><img src="https://img.shields.io/github/v/release/creeonix/prinbox" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/popover.png" width="500" alt="PRInbox popover with sample pull requests">
</p>

## Why

Review requests get lost in email and GitHub notifications. PRInbox keeps one number in your menu bar,
the PRs waiting on you, and one click shows what they are and how long they have waited.

PRInbox is an open-source take on [Pullover](https://github.com/omgovich/pullover), with one difference:
it has **no OAuth app of its own**. Every request goes through `gh api graphql`, so PRInbox sees exactly
what your [GitHub CLI](https://cli.github.com) login sees. That includes organizations that block
third-party OAuth apps but have approved the GitHub CLI. PRInbox never reads, stores or sends your token.

## Features

- **A count in the menu bar.** It is dimmed when nothing waits on you and red when gh needs attention.
- **Six sections**, each foldable, with the fold state remembered:
  - **Needs your review:** you or one of your teams was asked, and you have not reviewed yet.
  - **Replies to you:** someone answered in a review thread you took part in, and the next word is yours.
    Found even on PRs where you are no longer a requested reviewer.
  - **Take another look:** your review was requested again after you already reviewed.
  - **Mentions:** someone mentioned you on their PR.
  - **Your PRs:** yours that need you: changes requested, merge conflicts, review threads you have not
    answered, CI is red, or approved and ready to merge.
  - **Waiting on others:** the rest of yours, one quiet line each, plus anything you snoozed.
- **Rows that answer "what, where and how long":** author avatar (with the organization's avatar in its
  corner when your inbox spans more than one organization), `org/repo` (same condition), time waiting (counted from when
  your review was requested), and lines added and removed.
- **Status at a glance:** four marks at the right edge of each row: comment count, review state
  (approved or changes requested), CI (passed, failed, running) and merge state (ready to merge or
  conflicts). Hover a mark for its meaning. On Replies to you rows and on your PRs with open threads, the
  comment bubble and its count turn blue; hover it for how many threads wait for you.
- **Group by organization** (off by default): each section groups its rows under a thin separator with
  the organization's color, name and count.
- **Snooze:** `S` (or right-click) parks a PR until someone replies to you, pushes a commit or asks for your
  review again. It moves to Waiting on others, leaves the count, and comes back by itself when someone
  replies in a thread that concerns you, pushes a commit, requests your review again or (on your PRs)
  submits a review; your own activity keeps it parked. `U` brings it back sooner. Snoozes are kept in
  `state.json` (see Privacy).
- **Stacked pull requests:** a PR whose base branch is another open PR's head branch says `stack 2/3` in its
  fact line, and the chain stays together in its section. Simple chains only; a fork or a cycle gets no badge.
- **Scope for maintainers** (Settings): only direct review requests (requests that reach you through a team are
  left out) and hide other people's drafts. Both act in the GitHub searches, so a narrowed inbox costs nothing
  extra and the search window goes to what you asked for.
- **New since your last look:** rows that appeared or changed since you last closed the popover carry an accent
  bar at their left edge, and the header counts them.
- **Notifications** (off by default): one banner per refresh when a PR enters Needs your review, Replies to
  you or Take another look; a PR that keeps changing while it sits there does not notify again. A newer
  banner replaces the previous one. Clicking it opens the PR (or the popover, when several arrived at once).
- **Compact rows** (off by default): every section as one-line rows, with the waiting time.
- **Follow review threads** (on by default): reads who commented in review threads and reviews, and when,
  for Replies to you, open threads and the snooze wake above. Off makes every refresh lighter and a snooze
  wakes on any change.
- **Keyboard first:** ↑/↓, Enter to open, S to snooze, U to unsnooze, R to refresh, Esc to close, and a
  global shortcut (⌃⌥P by default).
- **A real menu-bar popover:** tiling window managers such as OmniWM, AeroSpace and yabai leave it alone.
- **Clear setup help:** when gh is missing or signed out, the popover shows the exact commands, and
  PRInbox recovers by itself once they are done.
- **Stays fresh:** refreshes every 5 minutes, after wake and when opened; it keeps the last data while
  offline, and archived repositories are excluded. A refresh finds out first whether anything changed at
  all; when nothing did, it costs GitHub one request.
- **Launch at login**, from Settings in the popover.
- **Update notice:** once a day PRInbox asks GitHub (through gh) for its latest release. When a newer one
  exists, a line in the popover, a Download item in the icon's menu and a small badge on the icon link to
  it. Dev builds never check.

## Install

1. Install the GitHub CLI and sign in:

   ```sh
   brew install gh
   gh auth login
   ```

2. Download `PRInbox-<version>.dmg` from the
   [latest release](https://github.com/creeonix/prinbox/releases/latest), open it and drag
   **PRInbox** to **Applications**.
3. Open PRInbox. Releases are signed ad hoc rather than with an Apple Developer ID, so macOS blocks the
   first launch. Right-click PRInbox in Applications and choose **Open**, or go to
   **System Settings › Privacy & Security** and click **Open Anyway**. This is needed once.

Or with Homebrew: `brew install --cask creeonix/tap/prinbox` for the app (add `--no-quarantine` to skip the
first-launch step) and `brew install creeonix/tap/prinbox-cli` for the command.

Requires macOS 14 or later, on Apple silicon or Intel.

To build from source instead, see [Build from source](#build-from-source).

## Usage

### The menu-bar icon

| Icon | Meaning |
|---|---|
| pull-request symbol + number | PRs waiting on you: Needs your review, Replies to you, Take another look and Mentions (drafts not counted) |
| dimmed symbol | nothing is waiting on you |
| red symbol + `!` | gh is missing, signed out, offline or rate limited; hover for the reason |

When GitHub itself is having trouble (an HTTP 502 and friends), the warning line says so, keeps the last
data and links to the [GitHub status page](https://www.githubstatus.com).

Left-click opens the popover. Right-click offers Refresh now and Quit.

### Keyboard

| Key | Action |
|---|---|
| ↑ / ↓ | move the selection (wraps) |
| Enter | open the selected PR in your browser, or fold/unfold a section header |
| S | snooze the selected PR until someone replies, pushes or re-requests |
| U | unsnooze the selected PR |
| R | refresh now |
| Esc | close the popover, or leave Settings |
| ⌃⌥P | open the popover from anywhere (change it in Settings) |

Right-click a row for Open on GitHub, Snooze until it changes (or Unsnooze) and Copy link.

The global shortcut uses Carbon hot keys and needs no Accessibility permission. macOS lets apps share a
shortcut silently: Pullover also defaults to ⌃⌥P, so if you run both, give one of them another shortcut.

### When gh is missing or signed out

The popover replaces the list with setup steps, each command with a Copy button:

- **gh not installed:** `brew install gh`, then `gh auth login`.
- **gh not signed in, or its sign-in expired:** `gh auth login` (choose GitHub.com, then "Login with a
  web browser"). If your organization uses single sign-on, authorize gh for it when asked.

PRInbox checks again every 10 seconds, so it recovers by itself shortly after you finish.

If gh lives somewhere unusual, point PRInbox at it in `~/.config/prinbox/settings.json`:

```json
{ "ghPath" : "/path/to/gh" }
```

When this is set, PRInbox and `prinbox` use only that path. Remove the key to go back to Homebrew's gh or PATH.

### Settings

Open Settings with the gear in the popover. It holds the global shortcut, launch at login, **Group by
organization**, **Show organization avatars**, **Compact rows**, **Follow review threads**, **Only direct review
requests**, **Hide draft pull requests**, **Notify about new review requests and replies**, the detected `gh` path,
the version and Quit. Turning notifications on asks macOS for permission once; if you decline, Settings says where
to turn them on. The Scope group narrows what the searches ask GitHub for with two switches, **Only direct review
requests** and **Hide draft pull requests**; their keys are `directReviewRequestsOnly` and `hideDrafts`. Settings
stay inside the popover, so there is never a window for a tiling window manager to grab. Every setting lives in
`~/.config/prinbox/settings.json`, one key per switch; a hand edit takes effect at the next launch, and the first
0.5.0 launch moves your 0.4 settings there out of macOS defaults.

<p align="center">
  <img src="docs/images/popover-compact.png" width="460" alt="The same inbox with Compact rows on">
</p>

### Command line

The `prinbox` command gives the same inbox to a terminal, a status line or a picker. It shares the settings,
the snoozes and the fetch cache with the app, so a run beside the app costs GitHub one request when nothing
changed.

```sh
brew install creeonix/tap/prinbox-cli        # or: make install-cli (into ~/.local/bin)
prinbox inbox                                # the inbox as JSON (docs/inbox-json.md)
prinbox inbox --format lines                 # one tab-separated row per line, for fzf, walker or rofi
prinbox inbox --format tmux --max-age 60     # the count for a status line, fetching at most once a minute
prinbox inbox --format waybar                # Waybar's custom-module object
prinbox inbox --cached                       # print the cache without contacting GitHub (instant pickers)
prinbox print                                # the inbox as text, a full fetch that touches nothing
prinbox snooze PR_kwDOA1                     # park a pull request (ids come from the JSON or the lines)
prinbox unsnooze PR_kwDOA1
prinbox open PR_kwDOA1                       # open it in the browser
prinbox mcp                                  # serve the inbox to AI agents over stdio (see AI agents)
```

A tmux status segment: `#(prinbox inbox --format tmux --max-age 60)`. An fzf picker:
`prinbox inbox --cached --format lines | fzf --delimiter '\t' --with-nth 3..7 | cut -f1 | xargs prinbox open`.

Exit codes: 0 when GitHub answered or the cache was served as asked, 1 when the fetch failed (cached rows are
still printed, with `error` set), 2 for usage, 3 when gh needs setup. `--format waybar` always exits 0.
`--notify` delivers arrivals through `notify-send` on Linux; on the Mac the app is the notifier, so run one
notifier per machine. `--verbose` shows the fetch log on stderr; `--settings <path>` names another settings
file. In `prinbox print` the fact line and the compact line both show `stack i/n`.

The app binary keeps two flags: `/Applications/PRInbox.app/Contents/MacOS/Prinbox --print` (the same as
`prinbox print`) and `--demo` (sample data). `--settings <path>` applies to the app itself (and to `--demo`);
`prinbox print --settings <path>` is the command's equivalent.

### AI agents

`prinbox mcp` serves the same inbox to AI agents over the [Model Context Protocol](https://modelcontextprotocol.io):
standard input and output, no network port, the same `state.json` and cache as the app and the command.
Register it once:

```sh
claude mcp add prinbox -- prinbox mcp
```

or, for Claude Desktop, in `claude_desktop_config.json`:

```json
{ "mcpServers": { "prinbox": { "command": "prinbox", "args": ["mcp"] } } }
```

Three tools. `get_inbox` returns the JSON document of [docs/inbox-json.md](docs/inbox-json.md), served from the
cache when GitHub confirmed it within the last 60 seconds (`max_age_seconds` changes that; 0 fetches now).
`snooze_pull_request` and `unsnooze_pull_request` take a row's `id`; a snooze made by an agent shows in the
menu bar and an open popover within a second. The server is never a notifier and writes nothing an agent did
not ask for. Details, the error rules and the log in [docs/mcp.md](docs/mcp.md).

## Privacy and security

- **No token handling:** GitHub access goes only through `gh api graphql`. PRInbox has no OAuth app,
  and never reads, stores or sends a token.
- **Nothing leaves your Mac:** there is no telemetry and no server. The only network traffic is gh's
  GitHub API calls (the pull requests waiting on you in two steps, an ids-only search and the details in
  small batches, every five minutes or when something changed; the latest PRInbox release once a day) and
  avatar downloads from `avatars.githubusercontent.com` (authors and repository owners).
- **AI agents:** `prinbox mcp` hands the agent that launched it the same fields the popover shows (titles,
  logins, URLs, counts, dates), over its own standard input and output. It opens no port and never carries
  comment text.
- **Local data:** settings live in `~/.config/prinbox/settings.json`. Snoozes and the "seen" ledger live in
  `~/Library/Application Support/prinbox/state.json`, the last fetch in `cache.json` beside it (titles,
  logins and URLs, never comment text) and the daily release check in `update.json`; avatars are cached in
  `~/Library/Caches/io.github.creeonix.prinbox`. `make uninstall` removes all of them.
  [docs/state-file.md](docs/state-file.md) describes the files and the lock that lets the app and the command
  write them.
- **What it reads:** PRInbox reads who commented in review threads and who reviewed, and when. It never
  fetches, stores or logs the text of a comment, a review or a description.

## Build from source

Requirements:
- macOS 14+
- Command Line Tools (`xcode-select --install`). Xcode also works but is not needed.
- `jq`, only for recording test fixtures.

```sh
git clone https://github.com/creeonix/prinbox.git && cd prinbox
make install      # builds, signs ad hoc, copies to /Applications and launches
make uninstall    # removes the app, its login item, caches and preferences
```

Other targets:

| Target | What it does |
|---|---|
| `make test` | runs the Swift Testing suite |
| `make lint` | runs swift-format lint, plus a check for `@State`/`#Preview` |
| `make coverage` | runs the tests with coverage; fails below 80% for PrinboxCore |
| `make run` | runs the app from the build directory |
| `make cli` | builds the `prinbox` command |
| `make install-cli` | copies the command to `~/.local/bin` (`PREFIX` overrides) |
| `make cli-tarball VERSION=x.y.z` | builds the command's release asset |
| `make dmg VERSION=x.y.z` | builds the release DMG into `build/` |
| `make icon` | rebuilds the app icon from `Resources/AppIcon-source.png` |

## Development

- **Code layout:**
  - `Sources/PrinboxCore` holds all the logic (gh access, classification, formatting, state, the command's
    logic under `CLI/`, the MCP server under `MCP/`) and is unit tested. It has no AppKit.
  - `Sources/PrinboxApp` is the thin AppKit and SwiftUI shell (macOS).
  - `Sources/PrinboxCLI` is the command's `main.swift` and composition root.
- **Fixtures:** `scripts/record-fixture.sh <name>` records the live inbox as a two-phase fixture (the
  search and the detail batches). It rebuilds the response from an allowlist of fields and replaces
  repositories, logins, titles, URLs and ids with placeholders, and a test checks every string in every
  fixture.
- **State file:** [docs/state-file.md](docs/state-file.md) is the contract for
  `~/Library/Application Support/prinbox/state.json`.
- **The inbox JSON:** [docs/inbox-json.md](docs/inbox-json.md).
- **UI checks:** things the tests cannot cover are listed in
  [docs/manual-checklist.md](docs/manual-checklist.md).
- **Releases:** see [RELEASING.md](RELEASING.md).
- **Building with Command Line Tools only**, which lack a few things Xcode provides:
  - SwiftUI's macro plugins, so `@State` and `#Preview` do not compile; view state lives in
    `@Observable` models instead.
  - XCTest, so the tests use Swift Testing.
  - A reliably found swift-testing macro plugin; `make test` passes its path explicitly.
- **Linux:** CI builds the library and the command and runs the suite in a `swift:6.4` container (`make test`
  stays macOS; `docker run --rm -v "$PWD":/src -w /src swift:6.4 bash -c 'apt-get update -qq && apt-get
  install -y -qq jq && swift build --scratch-path .build-linux && swift test --scratch-path .build-linux'`
  runs it locally).

## Roadmap

See [docs/roadmap.md](docs/roadmap.md): a shared core with a `prinbox` command and stacked PRs (0.5.0), an MCP server
(0.6.0), editor and tmux adapters (0.7.0), and Linux support for Hyprland and KDE (1.0.0).

## Credits

- [Pullover](https://github.com/omgovich/pullover) by Vlad Shilov: the idea, and the classification
  rules PRInbox ports.
- [omarchy-pullover](https://github.com/igor-alexandrov/omarchy-pullover) by Igor Alexandrov: the
  approach of signing in through the GitHub CLI.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE).
