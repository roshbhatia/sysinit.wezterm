local ui_format = require("sysinit.pkg.ui.format")
local ui_panes = require("sysinit.pkg.ui.panes")
local wezterm = require("wezterm")

local M = {}

local max_input_bytes = 4096
local max_component_bytes = 256
local max_title_bytes = 1024
local replacement = string.char(0xef, 0xbf, 0xbd)
local ellipsis = string.char(0xe2, 0x80, 0xa6)

local function repair_utf8(value)
  local output = {}
  local index = 1
  while index <= #value do
    local _, invalid = utf8.len(value, index)
    if not invalid then
      output[#output + 1] = value:sub(index)
      break
    end
    output[#output + 1] = value:sub(index, invalid - 1)
    output[#output + 1] = replacement
    index = invalid + 1
  end
  return table.concat(output)
end

local function truncate_utf8(value, max_bytes)
  if #value <= max_bytes then
    return value
  end
  local last = utf8.offset(value, 0, max_bytes - #ellipsis + 1) - 1
  return value:sub(1, last) .. ellipsis
end

local function sanitize(value, max_output_bytes)
  if type(value) ~= "string" then
    return ""
  end
  local truncated_input = #value > max_input_bytes
  local clean = repair_utf8(value:sub(1, max_input_bytes))
  clean = clean:gsub("\27%][^\7]*\7", ""):gsub("\27%].-\27\\", ""):gsub("\27%[[0-?]*[ -/]*[@-~]", "")
  clean = clean:gsub("[%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if truncated_input then
    clean = clean .. ellipsis
  end
  return truncate_utf8(clean, max_output_bytes)
end

local function clean(value)
  return sanitize(value, max_component_bytes)
end

local function basename(value)
  return clean(value):match("([^/\\]+)$") or ""
end

local function cwd(pane)
  local uri = pane and pane.current_working_dir
  if not uri then
    return ""
  end
  local value = uri.file_path or tostring(uri)
  return clean(ui_format.smart_path(clean(value)))
end

local SHOWN_STATES = { waiting = true, working = true }

-- Session first, then what runs in the pane, then where; the agent's own title
-- belongs to the tab, where it does not crowd the window switcher.
function M.format(tab, pane, session, identities, observed_agent, facts)
  local active = (tab and tab.active_pane) or pane or {}
  facts = facts or {}
  local process = ui_format.normalize_proc(basename(active.foreground_process_name)) or ""
  local agent = clean((active.user_vars or {}).agent_state):match("|([^|]+)$")
  local protocol_agent
  if active.pane_id then
    pcall(function()
      local object = wezterm.mux.get_pane(active.pane_id)
      for _, record in ipairs(object and object:get_program_status() or {}) do
        if clean(record.app) ~= "" then
          protocol_agent = clean(record.app)
        end
      end
    end)
  end
  identities = identities or {}
  local candidates = { observed_agent, facts.agent, agent, protocol_agent }
  local agent_name, identity
  for index = 1, 4 do
    local name = ui_panes.canonical_agent(candidates[index])
    if name and identities[name] then
      agent_name, identity = name, identities[name]
      break
    end
    agent_name = agent_name or (clean(name) ~= "" and clean(name) or nil)
  end
  identity = identity or identities[process]
  local actor = identity and clean(identity.label) or agent_name or process
  if actor ~= "" and (identity or agent_name) and SHOWN_STATES[facts.status] then
    actor = actor .. " (" .. facts.status .. ")"
  end

  local location = cwd(active)
  if clean(facts.repo) ~= "" and clean(facts.branch) ~= "" then
    location = clean(facts.repo) .. ":" .. clean(facts.branch)
  end

  local parts = {}
  for _, value in ipairs({ clean(session), actor, location, clean((active.user_vars or {}).SYSINIT_WINDOW_METADATA) }) do
    if value ~= "" then
      parts[#parts + 1] = value
    end
  end

  return sanitize(table.concat(parts, " · "), max_title_bytes)
end

return M
