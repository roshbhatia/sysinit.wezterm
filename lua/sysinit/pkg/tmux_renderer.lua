local wezterm = require("wezterm")
local act = wezterm.action
local utils = require("sysinit.pkg.utils")
local M = {}

function M.setup(config)
  local renderer = {
    ["SUPER:-"] = true,
    ["SUPER:="] = true,
    ["SUPER:c"] = true,
    ["SUPER:v"] = true,
    ["SUPER:h"] = true,
    ["SUPER:m"] = true,
    ["SUPER:q"] = true,
    ["SUPER:n"] = true,
    ["SUPER|SHIFT:n"] = true,
  }
  for _, binding in ipairs(config.keys or {}) do
    local native = binding.action
    local key, mods = binding.key, binding.mods
    if not renderer[(mods or "") .. ":" .. key] then
      binding.action = wezterm.action_callback(function(window, pane)
        if (pane:get_user_vars() or {}).SYSINIT_TMUX_SESSION and utils.get_process_name(pane) == "tmux" then
          window:perform_action(act.SendKey({ key = key:gsub("^phys:", ""), mods = mods }), pane)
        else
          window:perform_action(native, pane)
        end
      end)
    end
  end
end

return M
