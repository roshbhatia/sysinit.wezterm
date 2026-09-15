local wezterm = require("wezterm")

local M = {}

local OPTIONAL = { "events", "keybindings", "ui" }

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

function M.build()
  local config = {}
  if wezterm.config_builder then
    config = wezterm.config_builder()
  end

  local utils = require("sysinit.pkg.utils")
  local settings = utils.load_json_file(utils.get_config_path("config.json"))
  require("spawn_plugin").apply_to_config(config, settings.spawn or {})
  require("session_tree.options").configure({
    picker = settings.picker,
    shell = settings.shell,
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

  return config
end

return M
