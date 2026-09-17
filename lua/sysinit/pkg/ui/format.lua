local wezterm = require("wezterm")
local utils = require("sysinit.pkg.utils")
local session_format = require("session_tree.format")

local nf = wezterm.nerdfonts or {}

local M = {}

M.state_icons = {
  waiting = nf.md_clock_alert or "⏱",
  done = nf.md_check_circle or "✔",
  working = nf.md_loading or "⟳",
  idle = nf.cod_circle_small_filled or "○",
}

M.state_labels = {
  waiting = "Needs Input",
  done = "Done",
  working = "Working",
  idle = "",
}

M.suppressed_reasons = { ["your move"] = true, ["submit"] = true, ["message"] = true }

M.local_domains = { ["local"] = true, unix = true, TermWizTerminalDomain = true }

-- A pane in a WezTerm-multiplexed ssh domain reports either the configured
-- `ssh:<host>` or the inner `SSHMUX:ssh:<host>`, so strip both prefixes.
---@param domain string|nil
---@return string host
---@return boolean is_local
function M.domain_host(domain)
  local name = (domain or ""):gsub("^SSHMUX:", "")
  if name == "" or M.local_domains[name] then
    return "localhost", true
  end
  return (name:gsub("^ssh:", "")), false
end

---@param domain string|nil
---@return string tag
---@return boolean is_local
function M.host_tag(domain)
  local host, is_local = M.domain_host(domain)
  return "@" .. host, is_local
end

function M.status_color(status, colors)
  if status == "waiting" then
    return colors.waiting
  elseif status == "done" then
    return colors.done
  elseif status == "working" then
    return colors.working
  end
  return nil
end

function M.status_label(status, reason)
  local lbl = M.state_labels[status] or ""
  local show_reason = reason and reason ~= "" and not M.suppressed_reasons[reason]
  if lbl == "" and not show_reason then
    return ""
  end
  local parts = {}
  if lbl ~= "" then
    parts[#parts + 1] = lbl
  end
  if show_reason then
    parts[#parts + 1] = reason
  end
  return table.concat(parts, " · ")
end

function M.scope_label(rec)
  if not rec then
    return nil
  end
  if rec.branch and rec.branch ~= "" then
    return rec.branch
  end
  local count = rec.repo_count or 0
  if count > 0 then
    return string.format("%d repo%s", count, count == 1 and "" or "s")
  end
  return nil
end

function M.age(secs)
  if not secs or secs < 0 then
    return ""
  end
  if secs < 60 then
    return string.format("%ds", secs)
  elseif secs < 3600 then
    return string.format("%dm", math.floor(secs / 60))
  end
  return string.format("%dh", math.floor(secs / 3600))
end

-- Directory aliases from config.json, `{ work = "/path" }`: that path draws as
-- `{work}` and anything under it as `{work}/rest`. Longest path wins, so a
-- nested alias beats the one that contains it.
M.cwd_aliases = {}
do
  local ok, cfg = pcall(utils.load_json_file, utils.get_config_path("config.json"))
  if ok and type(cfg) == "table" then
    if type(cfg.cwd_aliases) == "table" then
      for alias, path in pairs(cfg.cwd_aliases) do
        if type(alias) == "string" and alias ~= "" and type(path) == "string" and path ~= "" then
          M.cwd_aliases[#M.cwd_aliases + 1] = { alias = alias, path = (path:gsub("/+$", "")) }
        end
      end
      table.sort(M.cwd_aliases, function(a, b)
        if #a.path ~= #b.path then
          return #a.path > #b.path
        end
        return a.alias < b.alias
      end)
    end
  end
end

function M.smart_path(full_cwd)
  if not full_cwd or full_cwd == "" then
    return ""
  end
  local home = os.getenv("HOME") or ""
  for _, entry in ipairs(M.cwd_aliases) do
    if full_cwd == entry.path then
      return "{" .. entry.alias .. "}"
    end
    if full_cwd:sub(1, #entry.path + 1) == entry.path .. "/" then
      return "{" .. entry.alias .. "}/" .. full_cwd:sub(#entry.path + 2)
    end
  end
  local gh_base = home .. "/github/"
  if full_cwd:sub(1, #gh_base) == gh_base then
    local rest = full_cwd:sub(#gh_base + 1)
    local short = rest:match("^[^/]+/[^/]+/(.+)$") or rest
    return "{gh}/" .. short
  end
  if full_cwd == home then
    return "{home}"
  end
  if full_cwd:sub(1, #home + 1) == home .. "/" then
    return "{home}/" .. full_cwd:sub(#home + 2)
  end
  return full_cwd
end

M.normalize_proc = session_format.normalize_proc
M.is_passthrough = session_format.is_passthrough
M.pane_proc = session_format.pane_proc
M.tab_label = session_format.tab_label

return M
