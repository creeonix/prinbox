# prinbox for tmux

The count in your status line and a popup picker over the inbox, over the `prinbox` command. Requires tmux 3.2,
fzf, and prinbox 0.7.0 or later (`brew install creeonix/tap/prinbox-cli`, signed in through `gh auth login`).

## Install

With TPM, in `tmux.conf`:

```tmux
set -g @plugin 'creeonix/prinbox'
set -g status-right '#{prinbox_status} | %H:%M'
```

then `prefix + I`. Without TPM: `run-shell /path/to/prinbox/prinbox.tmux` after the options below. The repository
is the plugin: `prinbox.tmux` sits at its root.

## Use

`#{prinbox_status}` in `status-left` or `status-right` becomes the count: `8` when something waits on you, nothing
when idle, `!` when gh needs attention, `!8` when the fetch failed but rows are known. The segment is
`#(prinbox inbox --format tmux --max-age 60)`, so it costs GitHub nothing more than one request a minute, and
nothing at all when the app or another adapter refreshed within the minute.

`prefix + P` opens a popup with the rows in fzf: type to filter, `Enter` opens the pull request in your browser
(the `+N more on GitHub` line opens its page), `ctrl-s` snoozes it, `ctrl-u` wakes it, `ctrl-r` fetches now. The
header shows the count and the keys, or the error when the last fetch failed.

## Options

Set these before the plugin runs:

| Option | Default | Meaning |
|---|---|---|
| `@prinbox_command` | `prinbox` | the executable |
| `@prinbox_max_age` | `60` | seconds the status segment and the popup serve the cache |
| `@prinbox_key` | `P` | the key after the prefix that opens the popup |
| `@prinbox_popup_width`, `@prinbox_popup_height` | `80%`, `70%` | the popup's size |

The popup script also reads `PRINBOX_FZF` (the fzf executable, default `fzf`) and `PRINBOX_OPENER` (default `open` on
macOS, `xdg-open` elsewhere) from the environment, for a non-standard install.

## When something is wrong

| What you see | Why |
|---|---|
| `prinbox: fzf is not installed (brew install fzf)` | the popup needs fzf |
| `prinbox not found: brew install creeonix/tap/prinbox-cli` | the command is not on tmux's PATH; set `@prinbox_command` |
| the sign-in steps and "Press Enter to close" | gh is signed out: `gh auth login` |
| a header starting with `!` | the fetch failed; the rows are the last known ones |

The plugin reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.
