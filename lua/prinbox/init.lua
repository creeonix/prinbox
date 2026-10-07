-- prinbox for Neovim: the pull requests waiting on you, over the `prinbox` command (docs/neovim.md).
local cli = require("prinbox.cli")
local view = require("prinbox.view")
local pick = require("prinbox.pick")

local M = {}

M.config = {
  cmd = "prinbox",
  max_age = 60,
  poll = 0,
  window = "botright 15split",
}

local timer = nil

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

--- Applies the options: cmd, max_age (seconds the list serves the cache), poll (seconds between background
--- refreshes for the count, 0 off) and window (the Ex command that opens the list's window).
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  cli.configure(M.config)
  stop_timer()
  if M.config.poll and M.config.poll > 0 then
    timer = vim.uv.new_timer()
    timer:start(M.config.poll * 1000, M.config.poll * 1000, function()
      vim.schedule(function()
        cli.inbox({ max_age = math.max(M.config.poll, M.config.max_age) }, function(report)
          if view.is_open() then
            view.render(report)
          end
        end)
      end)
    end)
  end
end

--- Shows the list: the cache at once, then a refresh with max_age in the background.
function M.open()
  view.show(M.config.window)
  cli.inbox({ cached = true }, function(report)
    view.render(report)
    cli.inbox({ max_age = M.config.max_age }, view.render)
  end)
end

--- Fetches now and re-renders the list when it is open.
function M.refresh()
  cli.inbox({}, function(report)
    if view.is_open() then
      view.render(report)
    end
  end)
end

--- vim.ui.select over the rows; the choice opens in the browser. A cached run with no rows and no error (an empty
--- cache, or none yet) falls through to a run with max_age.
function M.pick()
  cli.inbox({ cached = true }, function(report)
    if report.document ~= nil and #cli.rows(report.document) == 0 and report.document.error == nil then
      cli.inbox({ max_age = M.config.max_age }, pick.select)
    else
      pick.select(report)
    end
  end)
end

--- The last count as `prinbox inbox --format tmux` spells it, for a statusline.
function M.count()
  return cli.count()
end

return M
