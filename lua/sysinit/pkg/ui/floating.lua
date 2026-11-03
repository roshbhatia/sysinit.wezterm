local wezterm = require("wezterm")

local M = {}

function M.normal_pane(tab)
  local ok, pane = pcall(function()
    return tab.active_normal_pane
  end)
  return (ok and pane) or tab.active_pane
end

local function directory_parts(tab)
  local pane = M.normal_pane(tab)
  local uri = pane and pane.current_working_dir
  local path = uri and (uri.file_path or tostring(uri)) or ""
  path = path:gsub("\\", "/"):gsub("/+$", "")
  return path:match("([^/]+)/[^/]+$"), path:match("([^/]+)$")
end

local function shorten(value)
  value = value or ""
  if #value > 10 then
    return wezterm.truncate_right(value, 9) .. "…"
  end
  return value
end

function M.parent(tab)
  local parent = directory_parts(tab)
  return shorten(parent)
end

function M.cwd(tab)
  local _, cwd = directory_parts(tab)
  return shorten(cwd)
end

function M.badge(tab, palette)
  local ok, count, visible = pcall(function()
    return tab.floating_pane_count, tab.floating_pane_visible
  end)
  if not ok or not count or count == 0 then
    return ""
  end
  local label = " F" .. (count > 1 and tostring(count) or "")
  local color = visible and tab.is_active and palette.accent or palette.muted
  return wezterm.format({
    { Foreground = { Color = color } },
    { Text = label },
    { Foreground = { Color = palette.normal } },
  })
end

return M
