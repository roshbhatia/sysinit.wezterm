local wezterm = require("wezterm")
local ui_badges = require("sysinit.pkg.ui.badges")
local ui_format = require("sysinit.pkg.ui.format")
local ui_statusbar = require("sysinit.pkg.ui.statusbar")
local ui_panes = require("sysinit.pkg.ui.panes")
local ui_floating = require("sysinit.pkg.ui.floating")

local nf = wezterm.nerdfonts or {}

local M = {}

local SHELLS = { zsh = true, bash = true, fish = true, sh = true, nu = true, ["-zsh"] = true }
local DEFAULT_BRANCHES = { main = true, master = true }
local MAX_TOPIC = 28
local MAX_BRANCH = 24

local function shorten(text, limit)
  if utf8.len(text) and utf8.len(text) > limit then
    return text:sub(1, utf8.offset(text, limit) - 1) .. "…"
  end
  return text
end

function M.format(tab, cfg, ctx)
  local pane = ui_floating.normal_pane(tab)
  local explicit = ui_format.normalize_proc(tab.tab_title or "")
  local osc = ui_format.normalize_proc(pane and pane.title or "")
  local proc = pane and pane.foreground_process_name
  if proc then
    proc = ui_format.normalize_proc(proc:match("([^/]+)$") or proc)
  end

  local colors = (cfg and cfg.colors) or {}
  local inactive = colors.tab_bar and colors.tab_bar.inactive_tab
  local badge = ui_floating.badge(tab, {
    accent = (colors.ansi and colors.ansi[5]) or colors.foreground or "#ffffff",
    muted = (inactive and inactive.fg_color)
      or (colors.brights and colors.brights[1])
      or colors.foreground
      or "#ffffff",
    normal = colors.foreground or "#ffffff",
  })

  if explicit ~= "" and not explicit:match("^%d+$") then
    return " " .. ui_statusbar.tab_index(tab) .. " " .. explicit .. badge .. " "
  end

  local dir, cwd
  local cwd_uri = pane and pane.current_working_dir
  if cwd_uri then
    cwd = cwd_uri.file_path or tostring(cwd_uri)
    if ctx.home ~= "" and cwd == ctx.home then
      dir = "~"
    else
      dir = cwd:match("([^/]+)/?$") or cwd
    end
  end

  local label
  if osc and osc ~= "" and not osc:match("^%d+$") and not SHELLS[osc:lower()] and not ui_format.is_passthrough(osc) then
    label = osc
  end
  if ui_format.is_passthrough(proc) then
    proc = nil
  end
  label = label or dir or proc or "shell"

  local facts = ctx.facts and pane and ctx.facts(pane.pane_id, cwd) or {}
  if facts.agent then
    local identity = (ctx.identities or {})[facts.agent] or {}
    local named = identity.label or facts.agent
    local topic = osc
    if not topic or topic == "" or SHELLS[topic:lower()] or topic:lower():find(facts.agent, 1, true) then
      topic = named
    end
    label = (identity.glyph and identity.glyph .. " " or "") .. shorten(topic, MAX_TOPIC)
  end
  if facts.branch and not DEFAULT_BRANCHES[facts.branch] then
    label = label .. " " .. shorten(facts.branch, MAX_BRANCH)
  end

  if not (ctx.sigil_ok and ctx.ribbon_ok) then
    return " " .. ui_statusbar.tab_index(tab) .. " " .. label .. badge .. " "
  end

  local r = ctx.ribbon.new("tab")
  r:append(nil, nil, " " .. ui_statusbar.tab_index(tab) .. " " .. label .. " ")

  pcall(function()
    local s = pane and ui_panes.latest(pane.pane_id) or facts.status
    local icon = s and s ~= "idle" and ui_format.state_icons[s]
    if icon then
      r:append(nil, nil, icon .. " ")
    end
  end)

  if tab.active_pane and tab.active_pane.is_zoomed then
    r:append(nil, nil, nf.md_dock_window and (nf.md_dock_window .. " ") or "⊞ ")
  end

  if proc then
    local icon_items = ctx.sigil.items(proc, { padding = "right", fallback = false, reset = true })
    if icon_items and #icon_items > 0 then
      r:append_items(icon_items)
    end
  end

  if pane and pane.pane_id then
    local pid = pane.pane_id
    local bc = ui_badges.color(pid, cfg and cfg.colors or {})
    if bc then
      r:append(nil, "#3b4261", "  ")
      r:append(nil, bc, ui_badges.name(pid))
    end
  end

  r:append(nil, nil, badge .. " ")
  return r:items()
end

return M
