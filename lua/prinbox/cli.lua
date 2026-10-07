-- Runs the prinbox command asynchronously and turns its answer into a report: { document = table|nil, message =
-- string|nil }. vim.system runs the command; every callback runs on the main loop through vim.schedule.
local M = {}

local config = { cmd = "prinbox" }
local last = nil
local failed = false

local install = "prinbox not found: brew install creeonix/tap/prinbox-cli"

function M.configure(opts)
  config = opts
end

local function decode(stdout)
  if stdout == nil or stdout == "" then
    return nil
  end
  local ok, document = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
  if not ok or type(document) ~= "table" then
    return nil
  end
  return document
end

--- A finished run as a report (the exit codes of docs/inbox-json.md).
function M.report(code, stdout, stderr)
  local document = decode(stdout)
  local err = (stderr or ""):gsub("%s+$", "")
  local detail = err:gsub("^prinbox: ", "")
  if document and document.version ~= 1 then
    local text = "prinbox prints JSON version %s; this plugin reads version 1"
    return { message = text:format(tostring(document.version)) }
  end
  if code == 0 then
    if not document then
      return { message = "prinbox printed something that is not JSON" }
    end
    return { document = document }
  elseif code == 1 then
    local message = document and document.error and document.error.message or detail
    return { document = document, message = message }
  elseif code == 3 then
    return { document = document, setup = true, message = err ~= "" and err or "prinbox needs setup: gh auth login" }
  elseif code == 127 then
    return { message = install }
  end
  return { message = detail ~= "" and detail or ("prinbox exited with " .. tostring(code)) }
end

local function run(args, on_done)
  local ok, err = pcall(vim.system, args, { text = true }, function(result)
    vim.schedule(function()
      on_done(result.code, result.stdout, result.stderr)
    end)
  end)
  if not ok then
    vim.schedule(function()
      on_done(127, "", tostring(err):find("ENOENT") and install or tostring(err))
    end)
  end
end

--- Runs `prinbox inbox --format json` with opts.cached or opts.max_age; cb(report) on the main loop.
function M.inbox(opts, cb)
  local args = { config.cmd, "inbox", "--format", "json" }
  if opts.cached then
    table.insert(args, "--cached")
  elseif opts.max_age then
    table.insert(args, "--max-age")
    table.insert(args, tostring(opts.max_age))
  end
  run(args, function(code, stdout, stderr)
    local report = M.report(code, stdout, stderr)
    if report.document then
      last = report
    end
    failed = report.document == nil
    cb(report)
  end)
end

--- Runs `prinbox <verb> <id>` (snooze, unsnooze, open); cb(ok, message).
function M.act(verb, id, cb)
  run({ config.cmd, verb, id }, function(code, _, stderr)
    local message = (stderr or ""):gsub("^prinbox: ", ""):gsub("%s+$", "")
    cb(code == 0, code == 0 and nil or (message ~= "" and message or (verb .. " exited with " .. tostring(code))))
  end)
end

--- Opens a URL with the editor's opener; without one, the command opens the row by id.
function M.open(url, id)
  local _, err = vim.ui.open(url)
  if not err then
    return
  end
  if id then
    M.act("open", id, function(ok, message)
      if not ok then
        vim.notify("prinbox: " .. message, vim.log.levels.ERROR)
      end
    end)
  else
    vim.notify("prinbox: " .. err, vim.log.levels.ERROR)
  end
end

--- Every row of a document with its section, in display order: { row = ..., section = ... }.
function M.rows(document)
  local items = {}
  for _, section in ipairs(document and document.sections or {}) do
    for _, row in ipairs(section.rows or {}) do
      table.insert(items, { row = row, section = section })
    end
  end
  return items
end

--- The count as `--format tmux` prints it: the badge, nothing when idle, `!` first when the last answer failed
--- (a document with an error, or a run that printed no document: then the last known badge follows the `!`).
function M.count()
  local document = last and last.document
  local badge = document and document.badge or 0
  local text = badge > 0 and tostring(badge) or ""
  if failed or (document and document.error ~= nil) then
    return "!" .. text
  end
  return text
end

return M
