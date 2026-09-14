local wezterm = require("wezterm")
local ui_format = require("sysinit.pkg.ui.format")
local ui_sessions = require("sysinit.pkg.ui.sessions")

local M = {}

function M.tab_index(tab)
  return "[" .. tostring(tab.tab_index + 1) .. "]"
end

function M.window_index(window)
  local index = 0
  for _, candidate in ipairs(ui_sessions.ordered_windows()) do
    if candidate:get_workspace() == window:active_workspace() then
      index = index + 1
      if candidate:window_id() == window:window_id() then
        return "[" .. tostring(index) .. "] "
      end
    end
  end
  return ""
end

local CHIP_NAME_MAX = 16
local CHIP_SESSIONS_MAX = 20

local function chip_sessions(st, workspace)
  local names = st and st.names or nil
  if not names or #names == 0 then
    return ""
  end
  if #names == 1 and names[1] == workspace then
    return ""
  end
  local text = table.concat(names, ",")
  if #text > CHIP_SESSIONS_MAX then
    text = text:sub(1, CHIP_SESSIONS_MAX - 1) .. "…"
  end
  return "[" .. text .. "]"
end

function M.session_chips(window, sessions, slots, colors, tab_colors)
  local ordered = {}
  for name, slot in pairs(slots) do
    ordered[#ordered + 1] = { name = name, slot = slot }
  end
  if #ordered == 0 then
    return ""
  end
  table.sort(ordered, function(a, b)
    return a.slot < b.slot
  end)

  local active = ""
  pcall(function()
    active = window:active_workspace()
  end)

  local items = {}
  for _, entry in ipairs(ordered) do
    local st = sessions[entry.name]
    local status = st and st.status or nil
    local is_active = entry.name == active
    local label = entry.name
    if #label > CHIP_NAME_MAX then
      label = label:sub(1, CHIP_NAME_MAX - 1) .. "…"
    end
    local sc = ui_format.status_color(status, colors) or colors.idle
    local palette = tab_colors and (is_active and tab_colors.active or tab_colors.inactive)
    local fg = palette and palette.fg or (is_active and colors.name or colors.chrome)
    items[#items + 1] = "ResetAttributes"
    if palette then
      items[#items + 1] = { Background = { Color = palette.bg } }
    end
    items[#items + 1] = { Foreground = { Color = fg } }
    items[#items + 1] = { Text = "  [" .. tostring(entry.slot) .. "] " .. label }
    local inside = chip_sessions(st, entry.name)
    if inside ~= "" then
      items[#items + 1] = { Attribute = { Intensity = "Normal" } }
      items[#items + 1] = { Foreground = { Color = colors.chrome } }
      items[#items + 1] = { Text = " " .. inside }
    end
    items[#items + 1] = { Foreground = { Color = sc } }
    items[#items + 1] = { Text = " " .. (status and (ui_format.state_icons[status] or "●") or "·") }
    items[#items + 1] = { Text = "  " }
  end
  items[#items + 1] = "ResetAttributes"
  return wezterm.format(items)
end
return M
