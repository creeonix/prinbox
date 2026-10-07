# prinbox for Neovim

The pull requests waiting on you, in a buffer, over the `prinbox` command. Requires Neovim 0.10 and prinbox 0.7.0
or later (`brew install creeonix/tap/prinbox-cli`, signed in through `gh auth login`).

## Install

lazy.nvim:

```lua
{ "creeonix/prinbox", cmd = "Prinbox", opts = {} }
```

vim-plug: `Plug 'creeonix/prinbox'`, then `lua require("prinbox").setup()` in your config. The repository is the
plugin: its Lua lives in `lua/prinbox/` and `plugin/prinbox.lua` at the root.

## Use

| Command | Does |
|---|---|
| `:Prinbox` | the list: the cache at once, then a refresh in the background |
| `:Prinbox pick` | `vim.ui.select` over the rows (telescope, fzf-lua, snacks or mini.pick take it over); Enter opens |
| `:Prinbox refresh` | fetch now |

In the list: `Enter` opens the pull request in your browser (the `+N more on GitHub` line opens its page), `s`
snoozes it until something happens on it, `u` wakes it, `r` refreshes, `q` closes. A snooze made here shows in
the menu bar and the popover within a second, and the other way round.

The header line reads `8 waiting on you · updated 14:02 · 4 new`, with your default repositories appended when
some are set in PRInbox (`· acme/*, globex/billing`).

## Options

```lua
require("prinbox").setup({
  cmd = "prinbox",            -- the executable
  max_age = 60,               -- the list serves the cache when GitHub confirmed it within this many seconds
  poll = 0,                   -- seconds between background refreshes for the count; 0 is off
  window = "botright 15split" -- the Ex command that opens the list's window
})
```

## Statusline

`require("prinbox").count()` returns the count as `prinbox inbox --format tmux` prints it: `"8"`, `""` when nothing
waits, `"!"` or `"!8"` when the last run failed. With `poll` set it stays fresh on its own:

```lua
-- lualine
sections = { lualine_x = { function() return require("prinbox").count() end } }
-- or the built-in statusline
vim.o.statusline = "%f %= %{v:lua.require'prinbox'.count()}"
```

## When something is wrong

| What you see | Why |
|---|---|
| `prinbox not found: brew install creeonix/tap/prinbox-cli` | the command is not on Neovim's PATH; set `cmd` to its path |
| the sign-in steps in place of the rows | gh is signed out: `gh auth login` |
| a line under the header such as `GitHub did not answer in time` | the fetch failed; the rows are the last known ones |
| `prinbox prints JSON version N; this plugin reads version 1` | the command is newer than the plugin: update the plugin |

The plugin reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.
