-- vim.ui.select over the rows: telescope, fzf-lua, snacks and mini.pick all take it over.
local cli = require("prinbox.cli")

local M = {}

function M.format(item)
  local row = item.row
  local title = row.title:gsub("[%c]+", " ")
  return ("#%d  %s  ·  %s  ·  %s  ·  %s"):format(row.number, title, row.repository, row.reasonText, row.age)
end

function M.select(report)
  local items = cli.rows(report.document)
  if #items == 0 then
    vim.notify("prinbox: " .. (report.message or "nothing waiting on you"), vim.log.levels.INFO)
    return
  end
  vim.ui.select(items, { prompt = "Pull requests", kind = "prinbox", format_item = M.format }, function(choice)
    if choice then
      cli.open(choice.row.url, choice.row.id)
    end
  end)
end

return M
