local wezterm = require("wezterm")
local act = wezterm.action
local utils = require("sysinit.pkg.utils")

local M = {}

M.locked_mode = false
local IS_LINUX = wezterm.target_triple:find("linux", 1, true) ~= nil
M.workspace_modifiers = IS_LINUX and { "SUPER|CTRL|SHIFT" } or { "CTRL|SHIFT", "SUPER|CTRL|SHIFT" }

local EDITORS = { "nvim", "vim", "hx" }

-- A ctrl chord that readline or an editor already owns is passed to the app.
-- READLINE is for the chords that also have a SUPER twin, so the wezterm action
-- stays reachable from a shell prompt; the rest get EDITORS only, because in a
-- terminal the pane is nearly always a shell and a shell passthrough would make
-- the chord unreachable.
local SHELLS = { "zsh", "bash", "fish", "sh", "nu" }
local READLINE = (function()
  local both = {}
  for _, name in ipairs(EDITORS) do
    both[#both + 1] = name
  end
  for _, name in ipairs(SHELLS) do
    both[#both + 1] = name
  end
  return both
end)()

local APP_KEYS = (function()
  local both = {}
  for _, name in ipairs(EDITORS) do
    both[#both + 1] = name
  end
  both[#both + 1] = "slk"
  return both
end)()

local TRACE_KEYS = (function()
  local both = {}
  for _, name in ipairs(APP_KEYS) do
    both[#both + 1] = name
  end
  both[#both + 1] = "traces"
  both[#both + 1] = "orc"
  both[#both + 1] = "diffnav"
  return both
end)()

local WINDOW_PREFIX = (function()
  local both = {}
  for _, name in ipairs(READLINE) do
    both[#both + 1] = name
  end
  both[#both + 1] = "slk"
  both[#both + 1] = "traces"
  both[#both + 1] = "orc"
  return both
end)()

local TRACE_NAV = (function()
  local both = {}
  for _, name in ipairs(EDITORS) do
    both[#both + 1] = name
  end
  both[#both + 1] = "traces"
  both[#both + 1] = "orc"
  return both
end)()

local TUI_SCROLL = (function()
  local both = {}
  for _, name in ipairs(READLINE) do
    both[#both + 1] = name
  end
  both[#both + 1] = "traces"
  both[#both + 1] = "orc"
  both[#both + 1] = "slk"
  both[#both + 1] = "diffnav"
  both[#both + 1] = "changes"
  return both
end)()

local COMMON_MODS = { "CTRL", "SUPER" }

local smart_keys = require("smart_keys_plugin")
smart_keys.apply_to_config({}, {
  locked = function()
    return M.locked_mode
  end,
  process_name = utils.get_process_name,
  app_user_var = "SYSINIT_APP",
})
local create_smart_keybind = smart_keys.binding

local function create_multi_mod_bindings(key, action_fn, mod_list, opts)
  local bindings = {}
  for _, mods in ipairs(mod_list or COMMON_MODS) do
    -- Only the CTRL half can collide with a terminal convention, so only it
    -- carries the passthrough. The SUPER half must always reach wezterm.
    local per = mods == "CTRL" and opts or nil
    table.insert(bindings, create_smart_keybind(key, mods, action_fn(mods), per))
  end
  return bindings
end

local function host_action(kind, local_host)
  return function(pane)
    return require("sysinit.pkg.host_spawn").action(pane, kind, local_host)
  end
end

local function get_pane_keys()
  local DIRECTION_KEYS = { h = "Left", j = "Down", k = "Up", l = "Right" }
  local keys = {
    create_smart_keybind("s", "CTRL", host_action("Down", false)),
    create_smart_keybind("v", "CTRL", host_action("Right", false)),
    create_smart_keybind("s", "CTRL|SHIFT", host_action("Down", true)),
    create_smart_keybind("v", IS_LINUX and "SUPER|SHIFT" or "CTRL|SHIFT", host_action("Right", true)),
    -- CTRL-m is a carriage return, but nothing types it instead of Enter, and a
    -- passthrough would cost pane zoom inside an editor. Left bound on purpose.
    create_smart_keybind("m", "CTRL", act.TogglePaneZoomState),
    create_smart_keybind("n", "CTRL", act.RotatePanes("Clockwise"), { passthrough = TRACE_KEYS }),
  }

  local supports_floating, toggle_floating = pcall(function()
    return act.ToggleFloatingPane
  end)
  if supports_floating then
    table.insert(keys, create_smart_keybind("f", "SUPER", toggle_floating))
    table.insert(
      keys,
      create_smart_keybind(
        "Enter",
        "SUPER|SHIFT",
        act.SpawnCommandInNewFloatingPane({
          domain = "CurrentPaneDomain",
        })
      )
    )
  end

  local supports_global, toggle_global = pcall(function()
    return act.ToggleGlobalFloatingPane
  end)
  if supports_global then
    table.insert(keys, create_smart_keybind("f", "SUPER|SHIFT", toggle_global))
  end

  local supports_scaling, scale_floating = pcall(function()
    return act.ScaleFloatingPane
  end)
  if supports_scaling then
    table.insert(keys, create_smart_keybind("j", "SUPER|CTRL", scale_floating(-5)))
    table.insert(keys, create_smart_keybind("k", "SUPER|CTRL", scale_floating(5)))
  end

  for _, key in ipairs({ "h", "j", "k", "l" }) do
    local dir = DIRECTION_KEYS[key]
    table.insert(keys, create_smart_keybind(key, "CTRL", { ActivatePaneDirection = dir }, { passthrough = TRACE_NAV }))
    table.insert(
      keys,
      create_smart_keybind(key, "CTRL|SHIFT", { AdjustPaneSize = { dir, 3 } }, { passthrough = EDITORS })
    )
  end

  for _, binding in ipairs({
    { "LeftArrow", "Left" },
    { "RightArrow", "Right" },
    { "UpArrow", "Up" },
    { "DownArrow", "Down" },
  }) do
    table.insert(keys, create_smart_keybind(binding[1], "SUPER|CTRL", { AdjustPaneSize = { binding[2], 3 } }))
  end

  for _, binding in
    -- CTRL-w is the window prefix in editors, Traces, and Orc, and readline's
    -- kill-word. SUPER-w keeps pane close reachable in every context.
    ipairs(create_multi_mod_bindings("w", function()
      return act.CloseCurrentPane({ confirm = true })
    end, nil, { passthrough = WINDOW_PREFIX }))
  do
    table.insert(keys, binding)
  end

  return keys
end

local function pane_cwd(pane)
  local ok, path = pcall(function()
    local url = pane:get_current_working_dir()
    if not url then
      return nil
    end
    if type(url) == "string" then
      return (url:gsub("^file://[^/]*", ""))
    end
    return url.file_path
  end)
  if not ok or not path or path == "" then
    return nil
  end
  return (path:gsub("/+$", ""))
end

local function watch_keybind(key, describe, build_args)
  return {
    key = key,
    mods = "SUPER|SHIFT",
    action = wezterm.action_callback(function(win, pane)
      if M.locked_mode then
        win:perform_action({ SendKey = { key = key, mods = "SUPER|SHIFT" } }, pane)
        return
      end
      local args = build_args(pane)
      if not args then
        win:toast_notification("sysinit", "nothing to watch: " .. describe, nil, 3000)
        return
      end
      table.insert(args, 1, utils.get_nix_binary("utils"))
      table.insert(args, 2, "watch")
      win:perform_action(act.SplitPane({ direction = "Right", command = { args = args } }), pane)
    end),
  }
end

local function get_system_keys()
  return {
    create_smart_keybind("r", "SUPER", act.ReloadConfiguration),
    create_smart_keybind(":", "SUPER", act.ActivateCommandPalette),
    create_smart_keybind(";", "SUPER", act.ActivateCommandPalette),
    create_smart_keybind(";", "CTRL", act.ActivateCommandPalette),
    {
      key = "e",
      mods = "SUPER",
      action = wezterm.action_callback(function(win, pane)
        if M.locked_mode then
          win:perform_action({ SendKey = { key = "e", mods = "SUPER" } }, pane)
          return
        end
        local dims = pane:get_dimensions()
        local lines = pane:get_lines_as_text(dims.scrollback_rows + dims.viewport_rows)
        local tmp = os.tmpname() .. ".txt"
        local f = io.open(tmp, "w")
        if f then
          f:write(lines)
          f:close()
        end
        local editor = os.getenv("EDITOR") or utils.get_nix_binary("nvim")
        local argv = { editor, tmp }
        local ok, split = pcall(wezterm.shell_split, editor)
        if ok and split and #split > 0 then
          argv = split
          table.insert(argv, tmp)
        end
        win:perform_action(act.SpawnCommandInNewTab({ args = argv }), pane)
      end),
    },
    create_smart_keybind("c", "SUPER", act.CopyTo("Clipboard")),
    create_smart_keybind("c", "CTRL|SHIFT", act.CopyTo("Clipboard")),
    create_smart_keybind(
      "k",
      "SUPER",
      act.Multiple({
        act.ClearScrollback("ScrollbackAndViewport"),
        act.SendKey({ key = "l", mods = "CTRL" }),
      }),
      { passthrough = EDITORS }
    ),
    create_smart_keybind("v", "SUPER", act.PasteFrom("Clipboard")),
    watch_keybind("w", "no working directory", function(pane)
      local cwd = pane_cwd(pane)
      if not cwd then
        return nil
      end
      return { "worker", cwd }
    end),
    watch_keybind("b", "no working directory", function(pane)
      local cwd = pane_cwd(pane)
      if not cwd then
        return nil
      end
      return { "bus", cwd }
    end),
  }
end

local function get_font_keys()
  local keys = {}
  for _, binding in
    ipairs(create_multi_mod_bindings("-", function()
      return act.DecreaseFontSize
    end))
  do
    table.insert(keys, binding)
  end
  for _, binding in
    ipairs(create_multi_mod_bindings("=", function()
      return act.IncreaseFontSize
    end))
  do
    table.insert(keys, binding)
  end
  return keys
end

local function get_tab_keys()
  local keys = {
    create_smart_keybind("w", "CTRL|SHIFT", act.CloseCurrentTab({ confirm = true })),
    create_smart_keybind("Tab", "CTRL", act.ActivateTabRelative(1)),
    create_smart_keybind("Tab", "CTRL|SHIFT", act.ActivateTabRelative(-1)),
    create_smart_keybind("o", "CTRL|SHIFT", act.ActivateLastTab),
  }

  table.insert(keys, create_smart_keybind("t", "CTRL", host_action("tab", false)))
  table.insert(keys, create_smart_keybind("t", "SUPER", host_action("tab", false)))
  table.insert(keys, create_smart_keybind("t", "CTRL|SHIFT", host_action("tab", not IS_LINUX)))
  table.insert(keys, create_smart_keybind("t", "SUPER|SHIFT", host_action("tab", true)))

  if not IS_LINUX then
    table.insert(
      keys,
      create_smart_keybind(
        "r",
        "CTRL|SHIFT",
        act.PromptInputLine({
          description = "Rename tab:",
          action = wezterm.action_callback(function(win, _, line)
            if line then
              win:active_tab():set_title(line)
            end
          end),
        })
      )
    )
  end
  table.insert(
    keys,
    create_smart_keybind(
      "r",
      "SUPER|SHIFT",
      act.PromptInputLine({
        description = "Rename tab:",
        action = wezterm.action_callback(function(win, _, line)
          if line then
            win:active_tab():set_title(line)
          end
        end),
      })
    )
  )

  table.insert(keys, create_smart_keybind(",", "CTRL|SHIFT", act.MoveTabRelative(-1)))
  table.insert(keys, create_smart_keybind(".", "CTRL|SHIFT", act.MoveTabRelative(1)))

  for i = 1, 9 do
    local tab_action = i == 9 and act.ActivateTab(-1) or act.ActivateTab(i - 1)
    for _, binding in
      ipairs(create_multi_mod_bindings(tostring(i), function()
        return tab_action
      end, IS_LINUX and { "CTRL", "SUPER", "CTRL|SHIFT" } or nil))
    do
      table.insert(keys, binding)
    end
  end

  return keys
end

local function get_window_keys()
  return {
    create_smart_keybind("n", "SUPER", act.SpawnWindow),
    create_smart_keybind("n", "SUPER|SHIFT", act.SpawnCommandInNewWindow({ domain = { DomainName = "local" } })),
  }
end

local function get_search_keys()
  return {
    create_smart_keybind("Escape", "CTRL", act.ActivateCopyMode),
    -- CTRL-/ is readline undo and CTRL-f is page-forward in an editor.
    create_smart_keybind("/", "CTRL", act.Search("CurrentSelectionOrEmptyString"), {
      passthrough = EDITORS,
    }),
    create_smart_keybind("f", "CTRL", act.QuickSelect, { passthrough = TRACE_KEYS }),
    create_smart_keybind("f", "CTRL|SHIFT", IS_LINUX and act.Search("CurrentSelectionOrEmptyString") or act.PaneSelect),
    create_smart_keybind("/", "SUPER", act.Search("CurrentSelectionOrEmptyString")),
  }
end

local function get_scroll_keys()
  return {
    -- CTRL-u is kill-line and CTRL-d is EOF, and a shell prompt needs both far
    -- more than it needs a half-page scroll. SUPER-u and SUPER-d keep the scroll
    -- reachable from the prompt, so the passthrough costs nothing.
    create_smart_keybind("u", "CTRL", { ScrollByLine = -40 }, { passthrough = TUI_SCROLL }),
    create_smart_keybind("d", "CTRL", { ScrollByLine = 40 }, { passthrough = TUI_SCROLL }),
    create_smart_keybind("u", "SUPER", { ScrollByLine = -40 }),
    create_smart_keybind("d", "SUPER", { ScrollByLine = 40 }),
    create_smart_keybind("u", "CTRL|SHIFT", act.ScrollToTop, { passthrough = EDITORS }),
    create_smart_keybind("d", "CTRL|SHIFT", act.ScrollToBottom, { passthrough = EDITORS }),
    create_smart_keybind("UpArrow", "CTRL|SHIFT", act.ScrollToPrompt(-1), { passthrough = EDITORS }),
    create_smart_keybind("DownArrow", "CTRL|SHIFT", act.ScrollToPrompt(1), { passthrough = EDITORS }),
  }
end

local function merge_keys(...)
  local result = {}
  for _, group in ipairs({ ... }) do
    for _, key in ipairs(group) do
      table.insert(result, key)
    end
  end
  return result
end

function M.setup(config)
  config.disable_default_key_bindings = true

  local keys = merge_keys(
    get_system_keys(),
    get_font_keys(),
    get_pane_keys(),
    get_scroll_keys(),
    get_search_keys(),
    get_tab_keys(),
    get_window_keys()
  )

  if IS_LINUX then
    table.insert(keys, create_smart_keybind("q", "CTRL|SHIFT", act.QuitApplication))
    table.insert(keys, create_smart_keybind("F11", "NONE", act.ToggleFullScreen))
    table.insert(keys, create_smart_keybind("v", "CTRL|SHIFT", act.PasteFrom("Clipboard")))
    table.insert(keys, create_smart_keybind("n", "CTRL|SHIFT", act.SpawnWindow))
    table.insert(keys, create_smart_keybind("r", "CTRL|SHIFT", act.ReloadConfiguration))
  else
    table.insert(keys, create_smart_keybind("f", "SUPER|CTRL", act.ToggleFullScreen))
    table.insert(keys, create_smart_keybind("h", "SUPER", act.HideApplication))
    table.insert(keys, create_smart_keybind("v", "SUPER|SHIFT", host_action("Right", true)))
    table.insert(keys, create_smart_keybind("m", "SUPER", act.Hide))
    table.insert(keys, create_smart_keybind("q", "SUPER", act.QuitApplication))
  end
  table.insert(keys, create_smart_keybind("p", "CTRL|SHIFT", act.ActivateCommandPalette))
  table.insert(keys, create_smart_keybind("p", "SUPER|SHIFT", act.ActivateCommandPalette))
  table.insert(keys, create_smart_keybind("p", "SUPER|CTRL", act.PaneSelect))
  table.insert(keys, create_smart_keybind("x", "CTRL|SHIFT", act.ActivateCopyMode))
  table.insert(keys, create_smart_keybind("0", "CTRL", act.ResetFontSize))
  table.insert(keys, create_smart_keybind("0", "SUPER", act.ResetFontSize))

  -- CTRL-g is readline's abort, and it stays bound: it is the switch that turns
  -- every other binding into a passthrough, so it cannot itself pass through.
  table.insert(keys, {
    key = "g",
    mods = "CTRL",
    action = wezterm.action_callback(function()
      M.locked_mode = not M.locked_mode
    end),
  })

  config.ssh_domains = require("sysinit.pkg.domains").ssh()

  config.enable_kitty_keyboard = true

  config.keys = keys

  config.key_tables = wezterm.gui and wezterm.gui.default_key_tables() or {}
  for _, bindings in pairs(config.key_tables) do
    for index = #bindings, 1, -1 do
      local mods = bindings[index].mods
      if mods and mods:find("ALT", 1, true) then
        table.remove(bindings, index)
      end
    end
  end

  config.bypass_mouse_reporting_modifiers = "SHIFT"

  config.swallow_mouse_click_on_window_focus = false
  config.swallow_mouse_click_on_pane_focus = false

  local function semantic_selection(action)
    return wezterm.action_callback(function(window, pane)
      -- Unmarked panes contain one Output zone spanning all scrollback.
      local mode = #pane:get_semantic_zones("Prompt") > 0 and "SemanticZone" or "Line"
      window:perform_action(action(mode), pane)
    end)
  end

  local SELECTION_MODE = { "Cell", "Word", "SemanticZone" }

  local mouse_bindings = {}
  for streak, mode in ipairs(SELECTION_MODE) do
    -- Mouse capture strips SHIFT, so bind both modifier states.
    for _, mods in ipairs({ "NONE", "SHIFT" }) do
      -- A bare single click still opens a link under the cursor; holding SHIFT
      -- is the way to select link text instead of following it.
      local complete = (streak == 1 and mods == "NONE")
          and act.CompleteSelectionOrOpenLinkAtMouseCursor("ClipboardAndPrimarySelection")
        or act.CompleteSelection("ClipboardAndPrimarySelection")

      mouse_bindings[#mouse_bindings + 1] = {
        event = { Down = { streak = streak, button = "Left" } },
        mods = mods,
        action = streak == 3 and semantic_selection(act.SelectTextAtMouseCursor) or act.SelectTextAtMouseCursor(mode),
      }
      mouse_bindings[#mouse_bindings + 1] = {
        event = { Drag = { streak = streak, button = "Left" } },
        mods = mods,
        action = streak == 3 and semantic_selection(act.ExtendSelectionToMouseCursor)
          or act.ExtendSelectionToMouseCursor(mode),
      }
      mouse_bindings[#mouse_bindings + 1] = {
        event = { Up = { streak = streak, button = "Left" } },
        mods = mods,
        action = complete,
      }
    end
  end

  config.mouse_bindings = mouse_bindings
end

return M
