# Manual checklist

The checks automated tests cannot cover: they need a real menu bar, a real keyboard and a real login.
Run them before a release.

- [ ] The popover opens anchored under the icon; the tiling window manager leaves it alone.
- [ ] The popover draws above bars that use the pop-up window level (for example OmniWM's workspace bar).
- [ ] Clicking outside closes the popover.
- [ ] ↑/↓ move the selection, Enter opens a PR and closes the popover, S snoozes, U unsnoozes, R refreshes, Esc closes.
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
- [ ] `make install VERSION=0.0.1`: after the first refresh the icon shows the up-arrow badge, the popover shows "PRInbox x.y.z is available", the right-click menu has "Download PRInbox x.y.z…", and all open the release page. `make install` (real version) clears them.
- [ ] The popover is 460 pt wide, still opens under the icon, and the tiling window manager leaves it alone.
- [ ] On the live account, org badges show the organization's real avatar after the first refresh; author avatars still load.
- [ ] Hovering a mark shows its meaning (for example "CI running", "4 comments").
- [ ] Settings > Group by organization: rows regroup under separators with a color dot, name and count; ↑/↓ walk the rows in the displayed order; turning it off restores the flat order.
- [ ] Settings > Show organization avatars off hides the badges; on shows them again.
- [ ] Start recording a shortcut, leave Settings with the back button: the old shortcut opens the popover again at once.
- [ ] Change the login item in System Settings > General > Login Items, reopen Settings: the toggle shows the new state.
- [ ] With the network off, open the popover (initials show); turn the network on, wait five minutes, reopen: avatars load.
- [ ] S on a selected PR moves it to Waiting on others with the moon glyph and "Snoozed"; the selection lands on the next row; the badge count drops.
- [ ] U on the snoozed row brings it back to its section with its original waiting time.
- [ ] Right-clicking a row opens the menu inside the popover; Open on GitHub, Snooze until it changes (Unsnooze on a snoozed row) and Copy link work.
- [ ] A snooze survives quitting and relaunching PRInbox; `~/Library/Application Support/prinbox/state.json` lists it.
- [ ] Pushing a commit (or commenting) on a snoozed PR wakes it on the next refresh, marked with a dot.
- [ ] `Prinbox --print` shows the snoozed PR under Waiting on others as "· Snoozed".
- [ ] After a change on GitHub, the row shows the dot and the header says "· 1 new"; closing and reopening the popover clears both.
- [ ] Settings > Notify about new review requests: turning it on shows the macOS permission prompt; declining shows the note under the toggle.
- [ ] With the popover closed, a new review request gives one banner (title, org/repo); clicking it opens the PR. Two at once give one banner that opens the popover.
- [ ] Nothing fires while the popover is open; the rows get dots instead.
- [ ] `swift run Prinbox` with notifications on does not crash, and Settings says they are not available.
- [ ] Settings > Compact rows: every section shows one-line rows with the age; ↑/↓ and Enter still work; turning it off restores the full rows.
- [ ] VoiceOver reads an organization separator as "acme, 3 pull requests".
- [ ] Clicking an older banner while the popover is open opens that PR; the popover closes on its own when the browser comes to the front.
