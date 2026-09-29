# PRInbox

A macOS menu-bar code-review inbox that signs in through the GitHub CLI.

PRInbox shows the pull requests waiting on you in a popover under a menu-bar icon. It is an
open-source analogue of [Pullover](https://github.com/omgovich/pullover), with one difference: it
has no OAuth app of its own. Every request goes through `gh api graphql`, so PRInbox sees exactly
what your `gh` login sees. That includes organizations that restrict third-party OAuth apps but
have approved the GitHub CLI. PRInbox never reads, stores or passes your token.

## Requirements

- macOS 14 or later.
- Command Line Tools (`xcode-select --install`). Xcode is not needed.
- The GitHub CLI, logged in: `brew install gh && gh auth login`.
- `jq`, only for recording test fixtures.

## Install

```sh
git clone <this repository> prinbox && cd prinbox
make install      # builds, ad-hoc signs, copies to /Applications and launches
make uninstall    # removes the app, its login item, caches and preferences
```

## Usage

### The menu-bar icon

| Icon | Meaning |
|---|---|
| pull-request symbol + number | PRs waiting on you: Needs your review, Take another look and Mentions (drafts not counted) |
| dimmed symbol | nothing is waiting on you |
| red symbol + `!` | gh is missing, signed out, offline or rate limited; hover for the reason |

Left-click opens the popover. Right-click offers Refresh now and Quit.

### Sections

| Section | What lands there |
|---|---|
| Needs your review | Your review is requested (directly or through a team) and you have not reviewed yet |
| Take another look | Your review is requested again after you already reviewed |
| Mentions | You are mentioned on someone else's PR and not requested as a reviewer |
| Your PRs | Your PRs that need you, first reason wins: changes requested, merge conflicts, CI is red, approved and ready to merge |
| Waiting on others | The rest of your PRs, one dim line each |

Sorting:
- Review sections put the longest-waiting PR first. The wait is measured from the moment your
  review was requested.
- Your PRs are sorted newest first.
- Each section shows at most 8 PRs, then a "+N more on GitHub" row.
- Archived repositories are excluded.
- Drafts are shown dimmed.

### Keyboard

| Key | Action |
|---|---|
| ↑ / ↓ | move the selection (wraps) |
| Enter | open the selected PR in your browser, or fold/unfold a section header |
| R | refresh now |
| Esc | close the popover (or leave Settings) |
| ⌃⌥P | open the popover from anywhere (change it in Settings) |

The global shortcut uses Carbon hot keys, so it needs no Accessibility permission. PRInbox registers it
exclusively, so Settings reports a shortcut that another app holds exclusively. macOS lets apps that
register without exclusivity share a shortcut silently. Pullover uses the same default ⌃⌥P, and while both
run, one keypress opens both popovers. Pick another shortcut in either app.

### Settings

Open Settings with the gear in the popover. It holds the global shortcut, launch at login
(available once the app is in `/Applications`), the detected `gh` path, the version and Quit.
Settings stay inside the popover, so a tiling window manager never sees a window to tile.

### When gh is missing or signed out

The popover replaces the list with setup steps, each command with a Copy button:
- **gh not installed:** `brew install gh`, then `gh auth login`.
- **gh not signed in, or its sign-in expired:** `gh auth login` (choose GitHub.com, then "Login with a
  web browser"). If your organization uses single sign-on, authorize gh for it when asked.

PRInbox checks again every 10 seconds, so it recovers by itself a few seconds after you finish; Check now
retries at once. `PRInbox --print` prints the same steps.

If gh lives somewhere unusual, point PRInbox at it with
`defaults write io.github.creeonix.prinbox ghPath /path/to/gh`. The override is exclusive: when it is
set, only that path is tried, and `defaults delete io.github.creeonix.prinbox ghPath` removes it.

### Refresh

PRInbox refreshes:
- every 5 minutes
- after the Mac wakes
- when you open the popover and the data is more than a minute old
- when you press R

It keeps the last good data while offline.

### Command line

```sh
/Applications/PRInbox.app/Contents/MacOS/Prinbox --print    # print the inbox once, then exit
```

## Development

```sh
make test       # Swift Testing suite
make lint       # swift-format lint, and a guard against @State / #Preview
make coverage   # tests with coverage; fails below 80% for PrinboxCore
make run        # run the app from the build directory
```

- `Sources/PrinboxCore` holds all logic and is unit tested. It has no AppKit.
- `Sources/Prinbox` is the thin AppKit and SwiftUI shell.
- Design: `docs/specs/2026-09-29-prinbox-v1-design.md`.

### Recording fixtures

`scripts/record-fixture.sh <name>` runs the real query through `gh` and writes an anonymized
fixture to `Tests/PrinboxCoreTests/Fixtures/<name>.json`.
- `scripts/anonymize.jq` rebuilds the response from an allowlist of fields.
- Repositories, logins, titles, URLs and ids are replaced with placeholders.
- A test checks that every string in a fixture is a placeholder.

### Building without Xcode

Command Line Tools lack three things that Xcode provides:
- **SwiftUI macro plugins:** `@State` and `#Preview` do not compile. Keep view state in
  `@Observable` models.
- **XCTest:** tests use Swift Testing.
- **A reliable path to the swift-testing macro plugin:** `make test` passes it explicitly, because
  the default build intermittently fails with "plugin for module 'TestingMacros' not found".

## Manual checklist

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

## License

MIT. See `LICENSE`. PRInbox ports classification rules from Pullover and follows omarchy-pullover's
approach to gh authentication. See `THIRD_PARTY_NOTICES.md`.
