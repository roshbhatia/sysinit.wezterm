local wezterm = require("wezterm")
local utils = require("sysinit.pkg.utils")

local M = {}

local function open_file(window, pane, uri, unix_domains)
  local reference = uri:match("^sysinit%-file:(.+)$")
  if not reference and not uri:match("^file:") then
    return
  end
  local domain = pane:get_domain_name()
  if domain ~= "local" and domain ~= "unix" and domain ~= "TermWizTerminalDomain" then
    return
  end

  local path, line, column
  if reference then
    path = reference
  else
    local ok, url = pcall(wezterm.url.parse, uri)
    if not ok or not url or not url.file_path then
      return
    end
    local host = (url.host or ""):lower()
    if host ~= "" and host ~= "localhost" and host ~= wezterm.hostname():lower() then
      return
    end
    path = url.file_path
    line = url.fragment and url.fragment:match("^L?(%d+)") or nil
  end
  local name, row, col = path:match("^(.*):(%d+):(%d+)$")
  if not name then
    name, row = path:match("^(.*):(%d+)$")
  end
  path, line, column = name or path, line or row, col
  if path:sub(1, 2) == "~/" then
    path = utils.get_home_dir() .. path:sub(2)
  elseif path:sub(1, 1) ~= "/" then
    local cwd = pane:get_current_working_dir()
    if not cwd or not cwd.file_path then
      return false
    end
    path = cwd.file_path .. "/" .. path
  end

  local file = io.open(path, "rb")
  if not file then
    if reference then
      window:toast_notification("WezTerm", "File not found: " .. path, nil, 3000)
      return false
    end
    return
  end
  local _, read_error = file:read(1)
  file:close()
  if read_error then
    return
  end

  local args = {
    "/usr/bin/env",
    "PATH=" .. utils.get_nix_user_bin() .. ":" .. (os.getenv("PATH") or "/usr/bin:/bin"),
  }
  for _, configured in ipairs(unix_domains or {}) do
    if configured.name == domain and configured.socket_path then
      args[#args + 1] = "WEZTERM_UNIX_SOCKET=" .. configured.socket_path
      break
    end
  end
  local command = {
    utils.get_nix_binary("agent-diff"),
    "--pane-id",
    tostring(pane:pane_id()),
    "--cwd",
    path:match("^(.+)/[^/]+$") or "/",
    "--allow-directory",
    "--file=" .. path,
  }
  for _, arg in ipairs(command) do
    args[#args + 1] = arg
  end
  if line then
    args[#args + 1] = "--line=" .. line
  end
  if column then
    args[#args + 1] = "--column=" .. column
  end
  local ok, _, err = wezterm.run_child_process(args)
  if not ok then
    local message = err and err ~= "" and err or "Could not open the source review."
    window:toast_notification("Source review", message, nil, 4000)
  end
  return false
end

function M.setup(config)
  wezterm.on("open-uri", function(window, pane, uri)
    return open_file(window, pane, uri, config.unix_domains)
  end)
  local NAV_DIRECTIONS = {
    left = "Left",
    right = "Right",
    up = "Up",
    down = "Down",
  }

  wezterm.on("user-var-changed", function(window, pane, name, value)
    if name == "wez_copy" then
      window:copy_to_clipboard(value, "Clipboard")
    elseif name == "wez_not" then
      window:toast_notification("wezterm", value, nil, 4000)
    elseif name == "SYSINIT_NAV" then
      local dir = NAV_DIRECTIONS[tostring(value):match("^(%a+):") or ""]
      local active = window:active_pane()
      if dir and active and active:pane_id() == pane:pane_id() then
        window:perform_action(wezterm.action.ActivatePaneDirection(dir), pane)
      end
    end
  end)

  config.enable_scroll_bar = true
  local scrollbar_state = {}
  wezterm.on("update-status", function(window, pane)
    local ok, scrollable = pcall(function()
      local active = window:mux_window():active_pane()
      local displayed = window:active_pane()
      -- Config overrides clear key tables, so overlays must not change the scroll bar.
      if
        not active
        or not displayed
        or active:pane_id() ~= displayed:pane_id()
        or active:pane_id() ~= pane:pane_id()
      then
        return nil
      end
      local dimensions = pane:get_dimensions()
      return dimensions.scrollback_rows > dimensions.viewport_rows and not pane:is_alt_screen_active()
    end)
    if not ok or scrollable == nil then
      -- A closed pane can remain in a queued update-status event. Returning
      -- lets later status handlers refresh the active workspace and tab line.
      return
    end

    local window_id = window:window_id()
    if scrollbar_state[window_id] == scrollable then
      return
    end

    local overrides = window:get_config_overrides() or {}
    local configured = overrides.enable_scroll_bar
    if configured == nil then
      configured = config.enable_scroll_bar
    end
    if configured == scrollable then
      scrollbar_state[window_id] = scrollable
      return
    end

    if scrollable == config.enable_scroll_bar then
      overrides.enable_scroll_bar = nil
    else
      overrides.enable_scroll_bar = scrollable
    end
    window:set_config_overrides(overrides)
    scrollbar_state[window_id] = scrollable
  end)
end

return M
