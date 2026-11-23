local wezterm = require("wezterm")
local utils = require("sysinit.pkg.utils")

local act = wezterm.action
local M = {}

function M.write_scrollback(pane, path)
  local rows = pane:get_dimensions().scrollback_rows
  local file = assert(io.open(path, "w"))
  file:write(pane:get_lines_as_text(rows))
  file:close()
end

function M.open_scrollback(window, pane)
  local path = os.tmpname()
  M.write_scrollback(pane, path)
  local editor = os.getenv("VISUAL") or os.getenv("EDITOR")
  local ok, args = pcall(wezterm.shell_split, editor or "")
  if not ok or #args == 0 then
    args = { utils.get_nix_binary("nvim") }
  end
  args[#args + 1] = path
  -- The capture is local even when the current pane belongs to a remote domain.
  window:perform_action(act.SpawnCommandInNewTab({ domain = "DefaultDomain", args = args }), pane)
end

function M.entries()
  return {
    {
      brief = "Pane: break out to new tab",
      action = wezterm.action_callback(function(_, pane)
        local tab = pane:move_to_new_tab()
        if tab then
          tab:activate()
        end
      end),
    },
    {
      brief = "Tab: rename",
      action = act.PromptInputLine({
        description = "Tab name (empty resets it)",
        action = wezterm.action_callback(function(win, _, line)
          if line ~= nil then
            win:active_tab():set_title(line)
          end
        end),
      }),
    },
    {
      brief = "Open scrollback in editor",
      action = wezterm.action_callback(M.open_scrollback),
    },
  }
end

function M.setup()
  wezterm.on("augment-command-palette", M.entries)
end

return M
