-- The list buffer: the header, the sections and their rows from a report, with keys to open, snooze, wake,
-- refresh and close. Titles are flattened: a newline or a tab in a title would break the buffer's lines.
local cli = require("prinbox.cli")

local M = {}

local ns = vim.api.nvim_create_namespace("prinbox")
local buffer = nil
local line_items = {}
local last_report = nil

vim.api.nvim_set_hl(0, "PrinboxHeader", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "PrinboxMessage", { link = "WarningMsg", default = true })
vim.api.nvim_set_hl(0, "PrinboxSection", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "PrinboxNew", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "PrinboxSnoozed", { link = "Comment", default = true })

local function flatten(text)
  return (tostring(text or ""):gsub("[%c]+", " "))
end

--- HH:MM in local time for an ISO 8601 UTC date, or nil.
local function hhmm(iso)
  local y, mo, d, h, mi, s = (iso or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$")
  if not y then
    return nil
  end
  local fields = {
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  }
  local as_local = os.time(fields)
  local utc = os.date("!*t", as_local)
  utc.isdst = os.date("*t", as_local).isdst
  local zone = as_local - os.time(utc)
  return os.date("%H:%M", as_local + zone)
end

local function header_line(report)
  local document = report.document
  if not document then
    return report.message or "prinbox"
  end
  local parts = { ("%d waiting on you"):format(document.badge or 0) }
  local at = hhmm(document.checkedAt)
  if at then
    table.insert(parts, "updated " .. at)
  end
  if (document.newCount or 0) > 0 then
    table.insert(parts, ("%d new"):format(document.newCount))
  end
  if document.defaultRepositories and #document.defaultRepositories > 0 then
    table.insert(parts, table.concat(document.defaultRepositories, ", "))
  end
  return table.concat(parts, " · ")
end

local function flags(row)
  local out = {}
  if row.isNew then
    table.insert(out, "new")
  end
  if row.isDraft then
    table.insert(out, "draft")
  end
  if row.snoozed then
    table.insert(out, "snoozed")
  end
  if row.stack then
    table.insert(out, ("stack %d/%d"):format(row.stack.position, row.stack.size))
  end
  return table.concat(out, " ")
end

local function row_line(row)
  local text = ("  #%d  %s  %s  %s  %s"):format(row.number, flatten(row.title), row.repository, row.reasonText, row.age)
  local f = flags(row)
  return f ~= "" and (text .. "  " .. f) or text
end

--- The lines, the line-to-item map and the highlight marks for a report. Pure, for the tests.
function M.layout(report)
  local lines, map, marks = {}, {}, {}
  table.insert(lines, flatten(header_line(report)))
  table.insert(marks, { 1, report.document and "PrinboxHeader" or "PrinboxMessage" })
  if report.document and report.message then
    for _, line in ipairs(vim.split(report.message, "\n", { plain = true })) do
      table.insert(lines, line)
      table.insert(marks, { #lines, "PrinboxMessage" })
    end
  end
  -- Setup needed: the steps replace the rows, which are the cache's at best.
  local sections = (report.document and not report.setup) and report.document.sections or {}
  for _, section in ipairs(sections) do
    local rows = section.rows or {}
    if #rows > 0 or (section.moreCount or 0) > 0 then
      table.insert(lines, "")
      table.insert(lines, ("%s (%d)"):format(section.title, section.count or #rows))
      table.insert(marks, { #lines, "PrinboxSection" })
      for _, row in ipairs(rows) do
        table.insert(lines, row_line(row))
        map[#lines] = { row = row, section = section }
        if row.snoozed then
          table.insert(marks, { #lines, "PrinboxSnoozed" })
        elseif row.isNew then
          table.insert(marks, { #lines, "PrinboxNew" })
        end
      end
      if (section.moreCount or 0) > 0 then
        table.insert(lines, ("  +%d more on GitHub"):format(section.moreCount))
        map[#lines] = { more = section }
      end
    end
  end
  return lines, map, marks
end

local function ensure_buffer()
  if buffer and vim.api.nvim_buf_is_valid(buffer) then
    return buffer
  end
  buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, "prinbox://inbox")
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "prinbox"
  vim.bo[buffer].modifiable = false
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buffer, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", M.open_current, "prinbox: open the pull request")
  map("s", function() M.act_current("snooze") end, "prinbox: snooze")
  map("u", function() M.act_current("unsnooze") end, "prinbox: unsnooze")
  map("r", function() require("prinbox").refresh() end, "prinbox: refresh")
  map("q", M.close, "prinbox: close")
  return buffer
end

function M.buffer()
  return buffer
end

function M.last()
  return last_report
end

function M.is_open()
  return buffer ~= nil and vim.api.nvim_buf_is_valid(buffer) and vim.fn.bufwinid(buffer) ~= -1
end

--- Shows the buffer, opening a window with `window` (an Ex command) when none shows it.
function M.show(window)
  local buf = ensure_buffer()
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.cmd(window)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  else
    vim.api.nvim_set_current_win(win)
  end
end

function M.render(report)
  last_report = report
  local buf = ensure_buffer()
  local lines, map, marks = M.layout(report)
  line_items = map
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, mark[1] - 1, 0, { line_hl_group = mark[2] })
  end
end

local function current()
  if not M.is_open() then
    return nil
  end
  return line_items[vim.api.nvim_win_get_cursor(0)[1]]
end

function M.open_current()
  local item = current()
  if not item then
    return
  end
  if item.more then
    if item.more.moreUrl then
      cli.open(item.more.moreUrl, nil)
    end
  else
    cli.open(cli.url(item.row), item.row.id)
  end
end

function M.act_current(verb)
  local item = current()
  if not item or not item.row then
    return
  end
  cli.act(verb, item.row.id, function(ok, message)
    if not ok then
      vim.notify("prinbox: " .. message, vim.log.levels.ERROR)
      return
    end
    cli.inbox({ cached = true }, M.render)
  end)
end

function M.close()
  local win = buffer and vim.fn.bufwinid(buffer) or -1
  if win == -1 then
    return
  end
  if #vim.api.nvim_list_wins() > 1 then
    vim.api.nvim_win_close(win, false)
  else
    vim.cmd("enew")
  end
end

return M
