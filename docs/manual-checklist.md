# Manual checklist

The checks automated tests cannot cover: they need a real menu bar, a real keyboard and a real login.
Run them before a release.

- [ ] The popover opens anchored under the icon; the tiling window manager leaves it alone.
- [ ] The popover draws above bars that use the pop-up window level (for example OmniWM's workspace bar).
- [ ] Clicking outside closes the popover.
- [ ] ↑/↓ move the selection, Enter opens a PR and closes the popover, R refreshes, Esc closes.
- [ ] After Esc (or closing with the shortcut), typing goes to the app you were in before.
- [ ] Clicking the icon while the popover is open closes it (it does not reopen).
- [ ] Row tooltips (full owner/name) draw above the popover.
- [ ] Enter on a section header folds and unfolds it; the fold state survives a relaunch.
- [ ] The global shortcut opens the popover from another app; recording a new shortcut works; removing it works.
- [ ] Running a second PRInbox copy: its Settings reports the shortcut as unavailable.
- [ ] Launch at login: the toggle turns on, System Settings > General > Login Items lists PRInbox, and it starts after logging in again.
- [ ] Offline (network off): the icon turns red with `!`, and the popover keeps the last data with an "Offline" line.
- [ ] After sleep and wake with a working network, the icon does not turn red.
- [ ] Signed out (`GH_CONFIG_DIR=$(mktemp -d) /Applications/PRInbox.app/Contents/MacOS/Prinbox`): red `!`, and the popover shows "Sign in to the GitHub CLI" with a working Copy button.
- [ ] gh missing (`/Applications/PRInbox.app/Contents/MacOS/Prinbox -ghPath /nonexistent`): the popover shows the "gh not found" steps.
- [ ] After fixing gh (for example `gh auth login`), the popover returns to the inbox within about 10 seconds without a click.
