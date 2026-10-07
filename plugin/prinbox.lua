-- The :Prinbox command. The plugin's code lives in lua/prinbox/ and loads on first use.
if vim.g.loaded_prinbox then
  return
end
vim.g.loaded_prinbox = true

vim.api.nvim_create_user_command("Prinbox", function(opts)
  local prinbox = require("prinbox")
  local arg = opts.fargs[1]
  if arg == nil or arg == "" then
    prinbox.open()
  elseif arg == "pick" then
    prinbox.pick()
  elseif arg == "refresh" then
    prinbox.refresh()
  else
    vim.notify("Prinbox: unknown argument '" .. arg .. "' (pick, refresh)", vim.log.levels.ERROR)
  end
end, {
  nargs = "?",
  complete = function()
    return { "pick", "refresh" }
  end,
  desc = "The pull requests waiting on you (prinbox)",
})
