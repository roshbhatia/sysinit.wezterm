local wezterm = require("wezterm")

local M = {}

local OPTIONAL = { "events", "keybindings", "ui", "pane_palette" }

local function report(failures)
  for _, f in ipairs(failures) do
    wezterm.log_error("sysinit: " .. f.module .. ".setup failed: " .. tostring(f.err))
  end

  local summary = #failures .. " module(s) failed: "
  for i, f in ipairs(failures) do
    summary = summary .. (i > 1 and ", " or "") .. f.module
  end

  -- The toast rides the first status update rather than `gui-startup`, because
  -- a config reload re-runs build() without firing startup again.
  local toasted = false
  pcall(function()
    wezterm.on("update-status", function(window)
      if toasted then
        return
      end
      toasted = true
      window:toast_notification("sysinit config degraded", summary, nil, 10000)
    end)
  end)
end

-- WezTerm runs only the first handler of a synchronous event, so every module's
-- augment-command-palette handler is collected and served by one that concatenates them.
local function collect_palette_handlers()
  local on = wezterm.on
  local handlers = {}
  wezterm.on = function(name, callback)
    if name == "augment-command-palette" then
      handlers[#handlers + 1] = callback
      return
    end
    return on(name, callback)
  end
  return function()
    wezterm.on = on
    on("augment-command-palette", function(window, pane)
      local entries = {}
      for _, handler in ipairs(handlers) do
        local ok, result = pcall(handler, window, pane)
        if not ok then
          wezterm.log_error("sysinit: command palette handler failed: " .. tostring(result))
        elseif type(result) == "table" then
          for _, entry in ipairs(result) do
            entries[#entries + 1] = entry
          end
        end
      end
      return entries
    end)
  end
end

function M.build()
  local finish_palette = collect_palette_handlers()
  local config = {}
  if wezterm.config_builder then
    config = wezterm.config_builder()
  end

  local utils = require("sysinit.pkg.utils")
  local settings = utils.load_json_file(utils.get_config_path("config.json"))
  local persistence = settings.persistence or {}
  local recovery = persistence.enable and require("sysinit.pkg.recovery") or nil
  local local_domain = persistence.enable and "unix" or "local"
  settings.spawn = settings.spawn or {}
  settings.spawn.local_domain = local_domain
  require("spawn_plugin").apply_to_config(config, settings.spawn or {})
  require("session_tree.options").configure({
    picker = settings.picker,
    passthrough_procs = settings.passthrough_procs,
    shell = settings.shell,
    local_domain = local_domain,
    recovery = persistence.enable and recovery or nil,
    home = utils.get_home_dir(),
    binding = { key = "s", mods = "SUPER" },
    locked = function()
      return require("sysinit.pkg.keybindings").locked_mode
    end,
    workspace_state_dir = utils.state_path("weztermWorkspaceState", "wezterm/workspace_state"),
    adapters = {
      format = require("sysinit.pkg.ui.format"),
      panes = require("sysinit.pkg.ui.panes"),
      badges = require("sysinit.pkg.ui.badges"),
    },
  })
  require("sysinit.pkg.core").setup(config)
  if persistence.enable then
    recovery.setup(config, persistence)
  end

  local failures = {}
  for _, name in ipairs(OPTIONAL) do
    local ok, err = pcall(function()
      require("sysinit.pkg." .. name).setup(config)
    end)
    if not ok then
      table.insert(failures, { module = name, err = err })
    end
  end

  if #failures > 0 then
    report(failures)
  end

  require("sysinit.pkg.validate").setup(config)
  finish_palette()

  return config
end

return M
