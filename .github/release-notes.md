## What's new in 0.8.0

- **Where you stand, at a glance.** A row you approved is washed green, one you asked changes on red, and its fact
  line says what moved since your review: "2 commits since you approved", "rewritten since you requested changes",
  "re-requested, you approved". Opening such a row lands on GitHub's diff since your review, in the app, the
  command, the agent's rows and the three plugins. Both cues are Settings (Color rows by your verdict, Show what
  moved since your review).
- **A reviewed pull request hides until something happens.** Approved or changes requested with nothing pushed
  since: out of the inbox. The author pushes a diff change or asks again: back in Take another look, as "Pushed
  since you approved" or "Pushed since you requested changes", with a notification. A rebase that changes nothing
  does not count.
- **The whole picture on request.** Settings > Show reviewed pull requests, `prinbox inbox --all` and `get_inbox`
  with `all: true` add a Reviewed section listing every open pull request you reviewed with your verdict. The
  plugins take `all = true`, `prinbox-all` and `@prinbox_all on`.
- The JSON document carries `rows[].yourReview` and a seventh section; the `lines` url column is the URL to open.
- Upgrade the app and the command together: the cache is version 2, a 0.7.0 command beside the 0.8.0 app refetches,
  and the first refresh after the upgrade is a full fetch and quiet.
- Small fixes from the 0.7.0 review: the README names TPM and the plugins' prerequisites, and the test stub
  answers usage on a valueless flag.

## What's new in 0.7.0

- **Default repositories.** The filter icon in the popover's header opens a menu over the owners and repositories
  your inbox knows; pick `acme/*` or `globex/billing` and every search narrows to them, so a maintainer of many
  repositories sees only the ones that matter now. A strip under the header names the choice and its [x] clears it;
  `F` opens the menu. The command and the agent follow the same `defaultRepositories` key.
- **Neovim, Emacs and tmux.** Three plugins over `prinbox inbox --format json`, in this repository: `:Prinbox` (a
  list with `Enter`, `s`, `u`, `r`, `q`, and `:Prinbox pick` through `vim.ui.select`), `M-x prinbox` (a
  `tabulated-list` buffer with a mode-line count) and `#{prinbox_status}` plus `prefix + P` for an fzf popup. Each
  opens, snoozes and wakes; a snooze made in one shows in the others and in the menu bar within a second. See
  `docs/neovim.md`, `docs/emacs.md` and `docs/tmux.md`.
- The JSON document carries `defaultRepositories`, so adapters and agents can say the inbox is filtered.
- Upgrade the app and the command together: a 0.6.0 command beside the 0.7.0 app ignores the filter.
- Small fixes from the 0.6.0 review: the state watcher cancels its source when released, and a few more edge
  cases are pinned by tests. `make install-cli` replaces the installed binary through a new inode (0.6.0 users
  who saw exit 137 after a reinstall: this is the fix).

## What's new in 0.6.0

- **An inbox for AI agents.** `prinbox mcp` serves the inbox over the Model Context Protocol, on standard input
  and output with no network port: `claude mcp add prinbox -- prinbox mcp` and ask what is waiting on you.
  Three tools: `get_inbox` (the same JSON as `prinbox inbox`), `snooze_pull_request` and
  `unsnooze_pull_request`. It shares the snoozes and the cache with the app and the command, so a snooze from
  the agent shows in the menu bar within a second. See `docs/mcp.md`.
- **Scope for maintainers.** Two new switches: **Only direct review requests** leaves out requests that reach
  you through a team; **Hide draft pull requests** drops other people's drafts. Both act in the GitHub
  searches, so they cost nothing.
- The app notices a snooze made by the command or an agent at once, instead of at the next refresh.
- A cache from 0.5.0 is read as is; the first refresh after the upgrade can be an unchanged check.
- Small fixes from the 0.5.0 review: an unchanged check no longer stamps a cache another writer replaced,
  `state.json` deleted on disk empties the app's memory too, and a few more edge cases are pinned by tests.

## What's new in 0.5.0

- **The `prinbox` command.** The same inbox from a terminal, a tmux status line or a picker:
  `prinbox inbox --format json|lines|waybar|tmux`, `prinbox print`, `prinbox snooze <id>`, `prinbox unsnooze <id>`
  and `prinbox open <id>`. Install it with `brew install creeonix/tap/prinbox-cli` once the tap is published,
  or `make install-cli`. The JSON is documented in `docs/inbox-json.md` and is the contract the coming editor,
  tmux and Linux adapters read.
- **One cache for everyone.** The app and the command share `cache.json` next to `state.json`: a command run
  beside the app costs GitHub one request when nothing changed, `--cached` prints without contacting GitHub,
  and the app shows your rows the moment it launches. A banner can now tell you what arrived while the app
  was not running.
- **Settings in a file.** Every setting lives in `~/.config/prinbox/settings.json` (your first launch moves them
  there); nothing stays in macOS defaults. Point PRInbox at an unusual gh with `ghPath` in that file.
- **Stacked pull requests.** A PR whose base branch is another open PR's head branch shows `stack 2/3` in its
  fact line, and a chain stays together in its section. Simple chains only; forks and cycles get no badge.
- **Homebrew.** `brew install --cask creeonix/tap/prinbox` installs the app (the tap follows the release).
- The library and the command build and pass their tests on Linux, groundwork for 1.0.
- The fetch log reports the lowest remaining budget across every request, and counts truncated review pages.

## What's new in 0.4.0

- **Replies to you.** A new section for pull requests where someone answered in a review thread you took part
  in, found even on PRs where you are no longer a requested reviewer. Your own PRs with a reviewer thread you
  have not answered show up in Your PRs. On both, the comment bubble turns blue; hover it for the count.
- **Snoozes wake for a reason.** A parked PR comes back when someone replies in your thread, pushes a commit,
  requests your review again or, on your PRs, submits a review. Your own activity keeps it parked.
- **A fetch that scales.** PRInbox now asks GitHub for the list first and the details in small batches, so a
  full inbox no longer hits GitHub's time limit, and a refresh that finds nothing changed costs one request.
- **Follow review threads** (Settings, on by default) switches the whole conversation layer; off is the
  lighter refresh from 0.3.
- When GitHub answers with a 5xx, the warning line says so and links to the GitHub status page.
- The first right-click on a row opens its menu instead of closing the popover.
- A newer notification replaces the previous unread one. Notifications now cover replies too.
- A pull request that keeps changing while it waits for your review no longer raises a banner at every refresh.
- The state file has a written contract (`docs/state-file.md`) and tolerates missing keys.

## What's new in 0.3.1

- The "new since your last look" mark is now a thin bar at the row's left edge, in both row styles. The 0.3.0
  dot floated beside the indent of compact rows.

## What's new in 0.3.0

- **Snooze.** Press `S` on a pull request, or right-click it, to park it until something changes on it. It
  moves to Waiting on others, leaves the count in the menu bar, and comes back by itself when the PR is
  updated. `U` brings it back sooner.
- **New since your last look.** Rows that appeared or changed since you last closed the popover carry a dot,
  and the header says how many.
- **Notifications** (off by default, in Settings): one banner per refresh when new review requests arrive.
  Click it to open the PR.
- **Compact rows** (in Settings): every section as one-line rows, with the waiting time.
- The right-click menu also offers Open on GitHub and Copy link.
- Organization separators are read by VoiceOver.

## Install

1. Download `PRInbox-<version>.dmg`, open it and drag **PRInbox** to **Applications**.
2. This build is signed ad hoc, not with an Apple Developer ID, so macOS blocks the first launch.
   Right-click PRInbox in Applications and choose **Open**, or open it once, then go to
   **System Settings › Privacy & Security** and click **Open Anyway**.
3. PRInbox needs the GitHub CLI, signed in: `brew install gh && gh auth login`.

Verify the download with `shasum -a 256 -c PRInbox-<version>.dmg.sha256`.
