local ui_format = require("sysinit.pkg.ui.format")
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

local function metadata(pane, process, session, directory)
  local vars = pane and pane.user_vars or {}
  local explicit = clean(vars.SYSINIT_WINDOW_METADATA)
  if explicit ~= "" then
    return explicit
  end

  local title = clean(pane and pane.title)
  if title == "" or title == "wezterm" or title == process or title == session or title == directory then
    return ""
  end
  if basename(title) == process then
    return ""
  end
  return title
end

function M.format(tab, pane, session, identities)
  local active = (tab and tab.active_pane) or pane or {}
  local process = ui_format.normalize_proc(basename(active.foreground_process_name)) or ""
  local workspace = clean(session)
  local directory = cwd(active)
  local details = metadata(active, process, workspace, directory)
  local agent = clean((active.user_vars or {}).agent_state):match("|([^|]+)$")
  local protocol_agent, protocol_title
  if active.pane_id then
    pcall(function()
      local object = wezterm.mux.get_pane(active.pane_id)
      local records = object and object:get_program_status() or {}
      for index = #records, 1, -1 do
        local record = records[index]
        if clean(record.title) ~= "" then
          protocol_agent, protocol_title = clean(record.app), clean(record.title)
          break
        end
      end
    end)
  end
  identities = identities or {}
  local identity = identities[agent] or identities[process] or identities[protocol_agent]
  local label = identity and clean(identity.label) or process
  if details == "" then
    details = protocol_title or ""
  end
  local parts = {}

  for _, value in ipairs({ label, workspace, directory, details }) do
    if value ~= "" then
      parts[#parts + 1] = value
    end
  end

  return sanitize(table.concat(parts, " · "), max_title_bytes)
end

return M
