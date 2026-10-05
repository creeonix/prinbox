## What's new in 0.5.0

- **The `prinbox` command.** The same inbox from a terminal, a tmux status line or a picker:
  `prinbox inbox --format json|lines|waybar|tmux`, `prinbox print`, `prinbox snooze <id>`, `prinbox unsnooze <id>`
  and `prinbox open <id>`. Install it with `brew install creeonix/tap/prinbox-cli`. The JSON is documented in
  `docs/inbox-json.md` and is the contract the coming editor, tmux and Linux adapters read.
- **One cache for everyone.** The app and the command share `cache.json` next to `state.json`: a command run
  beside the app costs GitHub one request when nothing changed, `--cached` prints without contacting GitHub,
  and the app shows your rows the moment it launches. A banner can now tell you what arrived while the app
  was not running.
- **Settings in a file.** Every setting lives in `~/.config/prinbox/settings.json` (your first launch moves them
  there); nothing stays in macOS defaults. Point PRInbox at an unusual gh with `ghPath` in that file.
- **Stacked pull requests.** A PR whose base branch is another open PR's head branch shows `stack 2/3` in its
  fact line, and a chain stays together in its section. Simple chains only; forks and cycles get no badge.
- **Homebrew.** `brew install --cask creeonix/tap/prinbox` installs the app.
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
