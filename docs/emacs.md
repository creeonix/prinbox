# prinbox for Emacs

The pull requests waiting on you, in a `tabulated-list` buffer, over the `prinbox` command. Requires Emacs 29.1
and prinbox 0.7.0 or later (`brew install creeonix/tap/prinbox-cli`, signed in through `gh auth login`).

## Install

```elisp
(use-package prinbox
  :vc (:url "https://github.com/creeonix/prinbox" :rev :newest)
  :commands (prinbox prinbox-mode-line-mode))
```

or `M-x package-vc-install RET https://github.com/creeonix/prinbox RET`. The repository is the package:
`prinbox.el` sits at its root.

## Use

`M-x prinbox` opens `*prinbox*`: the cache at once, then a refresh in the background. Columns: Section, #, Title,
Repository, Reason, Age, Flags (`new`, `draft`, `snoozed`, `stack i/n`); rows in the popover's order.

| Key | Does |
|---|---|
| `RET` | open the pull request with `browse-url` |
| `s` | snooze it until something happens on it (a push, a reply in your thread, a new review request) |
| `u` | wake it |
| `g` | fetch now |
| `q` | bury the buffer |

The header line reads `8 waiting on you · updated 14:02 · 4 new`, with your default repositories appended when
some are set in PRInbox, and the error line when the last fetch failed. A snooze made here shows in the menu bar
and the popover within a second, and the other way round.

## Options

| Custom | Default | Meaning |
|---|---|---|
| `prinbox-command` | `"prinbox"` | the executable |
| `prinbox-max-age` | `60` | the buffer serves the cache when GitHub confirmed it within this many seconds |
| `prinbox-poll-seconds` | `0` | seconds between background refreshes for the mode line; 0 is off |

## Mode line

`(prinbox-mode-line-mode 1)` adds ` PR:8` to the mode line (nothing when nothing waits, `PR:!` or `PR:!8` after a
failed fetch) and, with `prinbox-poll-seconds` set, keeps it fresh.

## When something is wrong

| What you see | Why |
|---|---|
| `prinbox not found: brew install creeonix/tap/prinbox-cli` | the command is not on Emacs's `exec-path`; set `prinbox-command` |
| the sign-in steps in place of the rows | gh is signed out: `gh auth login` |
| `· GitHub did not answer in time` in the header line | the fetch failed; the rows are the last known ones |
| `prinbox prints JSON version N; this plugin reads version 1` | the command is newer than the package: update it |

The package reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.
