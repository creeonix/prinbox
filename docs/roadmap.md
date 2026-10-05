# Roadmap

Where PRInbox goes after 0.4.0, and the decisions behind the order. Versions are intentions, not promises;
each release stays usable on its own, and the macOS app never waits for the Linux work.

## 0.5.0: a shared core and the `prinbox` command

The logic (the two-phase GitHub fetch, the sections and their rules, snooze, arrivals, the state file) already
lives in one library, `PrinboxCore`, with no AppKit in it. 0.5.0 makes that library the thing every surface
shares:

- A `prinbox` command-line executable linking the library. `prinbox inbox --format json|lines|waybar|tmux`
  prints the classified inbox; `prinbox snooze <id>` and `prinbox unsnooze <id>` park and wake a pull request;
  `prinbox print` is today's `--print`. The JSON is the contract every adapter below reads.
- A small cache next to `state.json` (the last result, the fetch fingerprint, the attention ids), so a caller
  that runs the command fresh each time gets the unchanged short-circuit and correct notifications too.
- Platform seams as injected protocols, not conditional compilation: logging, file locations, notification
  delivery, opening a URL. The macOS app supplies `os.Logger`, `~/Library/Application Support`,
  `UNUserNotificationCenter` and `NSWorkspace`; the command supplies stderr, XDG directories, `notify-send` and
  `xdg-open`. Conditional imports stay where a protocol cannot help, in the adapter files themselves.
- The library builds and its tests run on Linux in CI (a Swift container), so the port cannot drift.
- Stacked pull requests, as sketched in the v1 design: a PR's parent is the PR in the same repository whose head
  branch is this PR's base; only simple chains count; a chain stays contiguous in its section; rows carry an
  `i/n` badge.

The macOS app keeps linking the library directly. A process boundary between the app and the core would buy
nothing until the core stops being Swift, and that day is not planned: the library compiled on Linux with two
small shims and passed its suite there (352 of 356 tests; the rest need `jq` or a Linux state path).

## 0.6.0: the MCP server

`prinbox mcp`, a subcommand of the command, serves the inbox to AI agents over stdio with the Model Context
Protocol: `get_inbox` (the JSON of `docs/inbox-json.md`), `snooze_pull_request` and `unsnooze_pull_request`. It
shares `state.json` and the cache with the app and the command, opens no network port, and is hand-written
JSON-RPC with no dependency. The release also adds three scope settings for maintainers (only direct review
requests, a repository filter, hide drafts), honored by the app, the command and the server, and a watcher in
the app so a snooze made by an agent or the command shows within a second.

## 0.7.0: editor and terminal adapters

Thin clients of `prinbox inbox --format json`, all usable on the Mac before any Linux work:

- Neovim: a picker (telescope, fzf-lua or snacks) over the six sections, Enter opens the PR, keys to snooze and
  unsnooze, an optional statusline count.
- Emacs: a package with a `tabulated-list` buffer by section, `browse-url` on RET, snooze keys, a mode-line count.
- tmux: `#(prinbox inbox --format tmux)` in the status line and a key bound to `display-popup` running an fzf
  picker.

## 1.0.0: Linux

The same inbox on a Linux desktop, from the same core and the same `state.json`:

- Hyprland and friends (Omarchy): a Waybar module reading the command's JSON (text, tooltip, class), a picker
  (walker or fuzzel) fed by its lines, `notify-send` for arrivals. Waybar's poll interval is the refresh timer;
  the command fetches, updates the cache, notifies and prints, with no daemon.
- KDE Plasma: a StatusNotifierItem tray icon with a menu over the same command.
- Packaging: a release tarball with a static-stdlib binary built on an older glibc, and an AUR package.
- Not planned: GNOME (tray icons need an extension), Windows, Developer ID signing.

A long-lived daemon can come later without changing the contract; every adapter above polls anyway.

## Decisions

| Question | Choice | Why |
|---|---|---|
| Core language | Swift, as today | It already compiles and passes its tests on Linux; a Rust port would redo 2300 lines and 356 tests to save the smaller part of each platform's work |
| App to core | Shared library, not a subprocess | The app's `@Observable` flow and tests stay untouched; the command is a second executable on the same library |
| Platform differences | Injected adapters | The codebase already works this way (`CommandRunning`, `DataLoading`, `StatePersisting`); conditionals only for imports |
| Linux process model | Stateless command plus a cache file | Waybar, tmux, editors and a tray script all poll; a daemon adds a moving part without changing what they read |
| Linux desktops | Hyprland first, KDE second, no GNOME | That is where the author runs Linux; GNOME needs a shell extension for any tray icon |
| MCP server | A subcommand, hand-written stdio JSON-RPC | One binary and one formula; five methods are not worth the first dependency, and the official Swift SDK pulls swift-nio for a stdio loop |
