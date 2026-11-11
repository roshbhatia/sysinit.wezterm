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

function M.entries()
  return {
    {
      brief = "Pane: swap with",
      action = act.PaneSelect({ mode = "SwapWithActive" }),
    },
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
      brief = "Pane: open scrollback in Neovim",
      -- The file is local, so the editor spawns in the default domain even from an SSH pane.
      action = wezterm.action_callback(function(win, pane)
        local path = os.tmpname()
        M.write_scrollback(pane, path)
        win:perform_action(
          act.SpawnCommandInNewTab({
            domain = "DefaultDomain",
            args = { utils.get_nix_binary("nvim"), "+normal G", path },
          }),
          pane
        )
      end),
    },
  }
end

function M.setup()
  wezterm.on("augment-command-palette", function()
    local entries = M.entries()
    for _, entry in ipairs(require("sysinit.pkg.domains").attach_entries()) do
      entries[#entries + 1] = entry
    end
    return entries
  end)
end

return M
