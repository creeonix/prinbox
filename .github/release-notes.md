## Install

1. Download `PRInbox-<version>.dmg`, open it and drag **PRInbox** to **Applications**.
2. This build is signed ad hoc, not with an Apple Developer ID, so macOS blocks the first launch.
   Right-click PRInbox in Applications and choose **Open**, or open it once, then go to
   **System Settings › Privacy & Security** and click **Open Anyway**.
3. PRInbox needs the GitHub CLI, signed in: `brew install gh && gh auth login`.

Verify the download with `shasum -a 256 -c PRInbox-<version>.dmg.sha256`.
