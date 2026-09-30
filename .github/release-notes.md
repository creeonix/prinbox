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
