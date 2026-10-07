-- The Neovim adapter's tests: plain asserts against the stub command, run headless by Tests/Adapters/run.sh
-- (`nvim --clean -l Tests/Adapters/nvim/run.lua`). Every command runs asynchronously, so each step waits.
local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h"))
vim.opt.runtimepath:prepend(root)
local stub = root .. "/Tests/Adapters/bin/prinbox"
local log = vim.fn.tempname()

local opened = {}
local open_error = nil
vim.ui.open = function(url)
  table.insert(opened, url)
  return nil, open_error
end
local notified = {}
vim.notify = function(message)
  table.insert(notified, message)
end

local function wait_for(predicate, what)
  assert(vim.wait(5000, predicate, 20), "timed out waiting for " .. what)
end

local function reset_log()
  vim.fn.writefile({}, log)
end

local function log_lines()
  return vim.fn.readfile(log)
end

vim.env.PRINBOX_STUB_LOG = log
vim.env.PRINBOX_STUB_EXIT = nil
vim.env.PRINBOX_STUB_VERSION = nil

local prinbox = require("prinbox")
local cli = require("prinbox.cli")
local view = require("prinbox.view")
local pick = require("prinbox.pick")
prinbox.setup({ cmd = stub })

local function lines()
  return vim.api.nvim_buf_get_lines(view.buffer(), 0, -1, false)
end

-- 1. The list shows the header, the sections and the rows in order; the cache first, then the refresh.
reset_log()
prinbox.open()
wait_for(function() return #log_lines() >= 2 end, "two runs")
wait_for(function() return view.last() ~= nil and #lines() > 10 end, "the rows")
local text = lines()
assert(text[1]:match("^8 waiting on you · updated %d%d:%d%d · 4 new$"), text[1])
assert(text[2] == "", text[2])
assert(text[3] == "Needs your review (5)", text[3])
assert(
  text[4] == "  #1290  Migrate the settings page to the new design system  acme/web  Review requested  2d"
    .. "  stack 1/2",
  text[4]
)
assert(text[6]:match("^  #2104  Charge sales tax per region  globex/billing  Review requested  %d+h  new$"), text[6])
assert(vim.tbl_contains(text, "Replies to you (2)"))
assert(vim.tbl_contains(text, "Waiting on others (4)"))
assert(text[#text]:match("^  #1284  Cache avatar images on disk  acme/web  Snoozed  %d+[hd]  snoozed$"), text[#text])
assert(vim.deep_equal(log_lines(), { "inbox json", "inbox json" }), vim.inspect(log_lines()))
assert(prinbox.count() == "8", prinbox.count())
assert(view.is_open())

-- 2. Enter opens the row under the cursor.
vim.api.nvim_win_set_cursor(0, { 4, 0 })
view.open_current()
assert(opened[1] == "https://github.com/acme/web/pull/1290", opened[1])

-- 3. s and u run the command with the row's id and re-render from the cache.
reset_log()
vim.api.nvim_win_set_cursor(0, { 5, 0 })
view.act_current("snooze")
wait_for(function() return #log_lines() == 2 end, "snooze and the reload")
assert(vim.deep_equal(log_lines(), { "snooze DEMO_1291", "inbox json" }), vim.inspect(log_lines()))
reset_log()
view.act_current("unsnooze")
wait_for(function() return #log_lines() == 2 end, "unsnooze and the reload")
assert(log_lines()[1] == "unsnooze DEMO_1291", log_lines()[1])

-- 4. pick lists every row and opens the chosen one.
local shown = nil
vim.ui.select = function(items, opts, on_choice)
  shown = { items = items, opts = opts }
  on_choice(items[3])
end
prinbox.pick()
wait_for(function() return shown ~= nil end, "the picker")
assert(#shown.items == 17, #shown.items)
assert(shown.opts.kind == "prinbox")
assert(
  pick.format(shown.items[1])
    == "#1290  Migrate the settings page to the new design system  ·  acme/web  ·  Review requested  ·  2d",
  pick.format(shown.items[1])
)
assert(opened[#opened] == "https://github.com/globex/billing/pull/2104", opened[#opened])

-- 5. Signed out: the setup steps replace the rows; the count says "!".
vim.env.PRINBOX_STUB_EXIT = "3"
prinbox.refresh()
wait_for(function() return vim.tbl_contains(lines(), "     gh auth login") end, "the setup steps")
assert(lines()[1] == "0 waiting on you", lines()[1])
assert(prinbox.count() == "!", prinbox.count())
vim.env.PRINBOX_STUB_EXIT = nil

-- 6. A failed fetch keeps the cached rows and puts the error line under the header.
vim.env.PRINBOX_STUB_EXIT = "1"
prinbox.refresh()
wait_for(function() return lines()[2] == "GitHub did not answer in time" end, "the error line")
assert(lines()[1]:match("^8 waiting on you"), lines()[1])
assert(lines()[4] == "Needs your review (5)", lines()[4])
assert(prinbox.count() == "!8", prinbox.count())
vim.env.PRINBOX_STUB_EXIT = nil

-- 7. A missing command shows the install line; a newer JSON version is refused.
prinbox.setup({ cmd = root .. "/Tests/Adapters/bin/no-such-prinbox" })
prinbox.refresh()
wait_for(function() return (lines()[1] or ""):match("^prinbox not found") ~= nil end, "the install line")
assert(lines()[1] == "prinbox not found: brew install creeonix/tap/prinbox-cli", lines()[1])
prinbox.setup({ cmd = stub })
vim.env.PRINBOX_STUB_VERSION = "2"
prinbox.refresh()
wait_for(function() return (lines()[1] or ""):match("version 2") ~= nil end, "the version line")
assert(lines()[1] == "prinbox prints JSON version 2; this plugin reads version 1", lines()[1])
vim.env.PRINBOX_STUB_VERSION = nil

-- 8. layout flattens titles: a newline or a tab in a title never reaches nvim_buf_set_lines.
local odd = {
  document = {
    version = 1, badge = 1, newCount = 0, defaultRepositories = { "acme/*" },
    sections = {
      { kind = "needsReview", title = "Needs your review", count = 1, moreCount = 2,
        moreUrl = "https://example.test/more",
        rows = { { id = "x", number = 7, title = "Fix\nthe\tthing", repository = "acme/web",
                   reasonText = "Review requested", age = "1h", url = "https://example.test/7",
                   isNew = false, isDraft = true, snoozed = false } } },
    },
  },
}
local odd_lines, odd_map = view.layout(odd)
assert(odd_lines[1] == "1 waiting on you · acme/*", odd_lines[1])
assert(odd_lines[4] == "  #7  Fix the thing  acme/web  Review requested  1h  draft", odd_lines[4])
assert(odd_lines[5] == "  +2 more on GitHub", odd_lines[5])
assert(odd_map[4].row.id == "x" and odd_map[5].more.moreUrl == "https://example.test/more")

-- 9. open falls back to the command when vim.ui.open cannot open.
prinbox.refresh()
wait_for(function() return lines()[3] == "Needs your review (5)" end, "the rows again")
reset_log()
open_error = "no opener"
vim.api.nvim_win_set_cursor(0, { 4, 0 })
view.open_current()
wait_for(function() return #log_lines() == 1 end, "the fallback open")
assert(log_lines()[1] == "open DEMO_1290", log_lines()[1])
open_error = nil

-- 10. poll runs the command on its own; q closes the window.
reset_log()
prinbox.setup({ cmd = stub, poll = 1 })
wait_for(function() return #log_lines() >= 1 end, "the poll")
assert(log_lines()[1] == "inbox json", log_lines()[1])
prinbox.setup({ cmd = stub, poll = 0 })
view.close()
assert(not view.is_open())

print("neovim: ok")
