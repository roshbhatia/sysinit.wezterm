local lua_root = assert(arg[1], "WezTerm Lua path is required")
local plugin_fixture = assert(arg[2], "plugin fixture path is required")

local switcher_file = assert(io.open(lua_root .. "/session_tree/switcher.lua", "r"))
local switcher_source = switcher_file:read("*a")
switcher_file:close()
local ui_file = assert(io.open(lua_root .. "/sysinit/pkg/ui.lua", "r"))
local ui_source = ui_file:read("*a")
ui_file:close()
assert(not ui_source:find("config.animation_fps", 1, true), "WezTerm overrides the default animation frame rate")
assert(not ui_source:find("config.max_fps", 1, true), "WezTerm overrides the default maximum frame rate")
local interval_assignments = select(2, ui_source:gsub("config%.status_update_interval%s*=", ""))
local final_plugin = assert(ui_source:find("ui_switcher.setup", 1, true), "the final UI plugin setup is missing")
local final_interval = assert(
  ui_source:find("config.status_update_interval = 1000", 1, true),
  "the effective status interval is not one second"
)
assert(interval_assignments == 1, "a plugin can still inherit an earlier status interval")
assert(final_interval > final_plugin, "the status interval is set before plugin application")
local cli_calls = select(2, switcher_source:gsub('wezterm_bin,%s*"cli"', ""))
local guarded_calls = select(2, switcher_source:gsub('wezterm_bin,%s*"cli",%s*"%-%-no%-auto%-start"', ""))
assert(cli_calls == guarded_calls, "a switcher wezterm cli call can start a headless mux")
assert(not switcher_source:find('id = "action:', 1, true), "a picker action is still rendered as a selectable row")
assert(switcher_source:find("launcher.providers()", 1, true), "picker registration is missing")
assert(
  switcher_source:find('brief = "Session: close target"', 1, true),
  "session targets have no separate close picker"
)

package.path = table.concat({
  lua_root .. "/?.lua",
  lua_root .. "/?/init.lua",
  package.path,
}, ";")

local handlers = {}
local current_process = "zsh"
-- Each test swaps these; the wezterm stub itself is assigned once.
local child_process = function(_args)
  return false, "", "no child process stub"
end
local json_parse = function(text)
  error("no json_parse stub for: " .. tostring(text))
end
local logged = {}
local last_format_parts
-- The mux the tree walks and the panes it can activate; each test sets them.
local mux_windows = {}
local mux_panes = {}
local action = setmetatable({}, {
  __index = function(self, name)
    local constructor = function(value)
      return { [name] = value == nil and true or value }
    end
    rawset(self, name, constructor)
    return constructor
  end,
})

local wezterm = {
  target_triple = "aarch64-apple-darwin",
  format = function(parts)
    last_format_parts = parts
    local text = {}
    for _, part in ipairs(parts) do
      if type(part) == "table" and part.Text then
        text[#text + 1] = part.Text
      end
    end
    return table.concat(text)
  end,
  GLOBAL = {},
  action = action,
  action_callback = function(callback)
    return callback
  end,
  enumerate_ssh_hosts = function()
    return {}
  end,
  glob = function()
    return {}
  end,
  gui = {
    default_key_tables = function()
      return {
        copy_mode = {
          { key = "b", mods = "NONE", action = action.CopyMode("MoveBackwardWord") },
          { key = "b", mods = "ALT", action = action.CopyMode("MoveBackwardWord") },
        },
        search_mode = {
          { key = "Escape", mods = "NONE", action = action.CopyMode("Close") },
        },
      }
    end,
  },
  log_error = function(message)
    logged[#logged + 1] = message
  end,
  log_warn = function() end,
  mux = {
    all_windows = function()
      return mux_windows
    end,
    get_pane = function(id)
      return mux_panes[id]
    end,
  },
  -- The glyph names the fixtures carry, so a resolved glyph is one letter.
  nerdfonts = { cod_briefcase = "B", md_server = "S", md_sleep = "D" },
  run_child_process = function(args)
    return child_process(args)
  end,
  json_parse = function(text)
    return json_parse(text)
  end,
  on = function(name, callback)
    handlers[name] = callback
  end,
  time = {
    call_after = function(_, callback)
      callback()
    end,
  },
  plugin = {
    list = function()
      return {}
    end,
  },
  split_by_newlines = function(value)
    local lines = {}
    for line in value:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        lines[#lines + 1] = line
      end
    end
    return lines
  end,
}
package.loaded.wezterm = wezterm

local real_utils = require("sysinit.pkg.utils")
real_utils.get_home_dir = function()
  return "/home/test"
end
real_utils.get_nix_binary = function(name)
  return "/profile/bin/" .. name
end
local nu_args = real_utils.get_nushell_args()
local expected_config_root = os.getenv("XDG_CONFIG_HOME") or "/home/test/.config"
assert(table.concat(nu_args, "\n") == table.concat({
  "/profile/bin/nu",
  "--config",
  expected_config_root .. "/nushell/config.nu",
  "--env-config",
  expected_config_root .. "/nushell/env.nu",
  "--plugin-config",
  expected_config_root .. "/nushell/plugin.msgpackz",
}, "\n"), "WezTerm did not pass every managed Nushell path")

package.loaded["sysinit.pkg.utils"] = {
  get_config_path = function(path)
    return path
  end,
  get_home_dir = function()
    return "/nonexistent"
  end,
  get_nix_binary = function(name)
    return name
  end,
  get_process_name = function()
    return current_process
  end,
  load_json_file = function(path)
    return {
      plugins = {
        fixture = plugin_fixture,
        nested = plugin_fixture .. "/nested",
        missing = plugin_fixture .. "/missing",
      },
      picker = {
        command = { "picker-call" },
        providers = {
          { key = "@", name = "tether", manifest = "hosts.json" },
          { key = "#", name = "zmx", manifest = "zmx.json" },
          { key = "$", name = "seshy", manifest = "sessions.json" },
          { key = "%", name = "zoxide", manifest = "folders.json" },
        },
      },
      cwd_aliases = { sy = "/state/seshy/sessions" },
      passthrough_procs = { "zmx", "caffeinate" },
    }
  end,
  state_path = function(_, fallback)
    return "/state/" .. fallback
  end,
}

local keybindings = require("sysinit.pkg.keybindings")
local key_config = {}
keybindings.setup(key_config)
assert(key_config.disable_default_key_bindings, "default keys remain enabled")
assert(keybindings.workspace_modifiers[2] == "SUPER|CTRL|SHIFT", "macOS workspace digits collide with screenshots")
assert(#key_config.keys >= 50, "the key registry lost bindings")
assert(#key_config.key_tables.copy_mode == 1, "copy mode retains a WM-owned Alt alias")
assert(key_config.key_tables.copy_mode[1].action.CopyMode == "MoveBackwardWord", "copy mode lost Vim word navigation")
assert(#key_config.key_tables.search_mode == 1, "search mode lost its exit shortcut")

local seen = {}
for _, binding in ipairs(key_config.keys) do
  local chord = binding.mods .. "+" .. binding.key
  assert(not seen[chord], "duplicate WezTerm chord: " .. chord)
  assert(not binding.mods:find("ALT", 1, true), "ALT chord escapes the shared owner: " .. chord)
  seen[chord] = true
end
require("sysinit.pkg.validate").setup(key_config)

-- Select to copy has to survive a pane that grabs the mouse and a pane that
-- does not. WezTerm strips the bypass modifier before it matches a binding, so
-- a grabbed pane arrives as NONE and an ungrabbed one keeps SHIFT; a streak
-- bound in only one of the two silently drops the Up that copies.
local mouse = {}
for _, binding in ipairs(key_config.mouse_bindings) do
  local kind, detail = next(binding.event)
  local slot = kind .. ":" .. detail.streak .. ":" .. binding.mods
  assert(detail.button == "Left", "a selection binding moved off the left button")
  assert(not mouse[slot], "duplicate mouse binding: " .. slot)
  mouse[slot] = binding.action
end

local SELECTION_MODE = { "Cell", "Word", "SemanticZone" }
for streak, mode in ipairs(SELECTION_MODE) do
  for _, mods in ipairs({ "NONE", "SHIFT" }) do
    local down = assert(mouse["Down:" .. streak .. ":" .. mods], "no press for streak " .. streak .. " " .. mods)
    local drag = assert(mouse["Drag:" .. streak .. ":" .. mods], "no drag for streak " .. streak .. " " .. mods)
    local up = assert(mouse["Up:" .. streak .. ":" .. mods], "no release for streak " .. streak .. " " .. mods)
    if streak == 3 then
      for _, marked in ipairs({ false, true }) do
        local pane = {
          get_semantic_zones = function(_, kind)
            assert(kind == "Prompt", "selection does not check prompt marks")
            return marked and { { semantic_type = "Prompt" } } or {}
          end,
        }
        local performed
        local window = {
          perform_action = function(_, value)
            performed = value
          end,
        }
        down(window, pane)
        assert(performed.SelectTextAtMouseCursor == (marked and "SemanticZone" or "Line"))
        drag(window, pane)
        assert(performed.ExtendSelectionToMouseCursor == (marked and "SemanticZone" or "Line"))
      end
    else
      assert(down.SelectTextAtMouseCursor == mode, "press does not select " .. mode)
      assert(drag.ExtendSelectionToMouseCursor == mode, "drag does not extend " .. mode)
    end
    local copies = up.CompleteSelection == "ClipboardAndPrimarySelection"
      or up.CompleteSelectionOrOpenLinkAtMouseCursor == "ClipboardAndPrimarySelection"
    assert(copies, "streak " .. streak .. " " .. mods .. " does not copy on release")
  end
end

-- A bare click keeps following links; SHIFT is how you select the link text.
assert(mouse["Up:1:NONE"].CompleteSelectionOrOpenLinkAtMouseCursor, "a bare single click stopped opening links")
assert(mouse["Up:1:SHIFT"].CompleteSelection, "shift click opens a link instead of selecting it")

assert(key_config.swallow_mouse_click_on_window_focus == false, "window activation discards selection")
assert(key_config.swallow_mouse_click_on_pane_focus == false, "pane activation discards selection")

local function key_binding(key, mods)
  for _, binding in ipairs(key_config.keys) do
    if binding.key == key and binding.mods == mods then
      return binding
    end
  end
  error("missing WezTerm chord: " .. mods .. "+" .. key)
end

local floating_window = {
  perform_action = function(self, action)
    self.last = action
  end,
}
key_binding("f", "SUPER").action(floating_window, {})
assert(floating_window.last.ToggleFloatingPane ~= nil, "floating toggle does not reach the native action")
for _, binding in ipairs(key_config.keys) do
  assert(not (binding.key == "f" and binding.mods == "SUPER|SHIFT"), "global float shortcut remains enabled")
  assert(not (binding.key == "Enter" and binding.mods == "SUPER|SHIFT"), "additional float shortcut remains enabled")
end
for key, direction in pairs({ LeftArrow = "Left", RightArrow = "Right", UpArrow = "Up", DownArrow = "Down" }) do
  key_binding(key, "SUPER|CTRL").action(floating_window, {})
  assert(floating_window.last.AdjustPaneSize[1] == direction, "resize chord uses the wrong direction")
  assert(floating_window.last.AdjustPaneSize[2] == 3, "resize chord uses the wrong increment")
end

key_binding("j", "SUPER|CTRL").action(floating_window, {})
assert(floating_window.last.ScaleFloatingPane == -5, "combined shrink does not use the native scale operation")
key_binding("k", "SUPER|CTRL").action(floating_window, {})
assert(floating_window.last.ScaleFloatingPane == 5, "combined grow does not use the native scale operation")
local floating_ui = require("sysinit.pkg.ui.floating")
local base = { current_working_dir = { file_path = "/github/project" } }
local popup = { current_working_dir = { file_path = "/tmp/scratch" } }
local float_tab = {
  active_pane = popup,
  active_normal_pane = base,
  is_active = true,
  floating_pane_count = 2,
  floating_pane_visible = true,
}
assert(floating_ui.normal_pane(float_tab) == base)
assert(
  floating_ui.parent(float_tab) == "github" and floating_ui.cwd(float_tab) == "project",
  "floating cwd replaced parent tab identity"
)
local palette = { accent = "accent", muted = "muted", normal = "normal" }
assert(floating_ui.badge(float_tab, palette) == " F", "floating badge is missing")
assert(last_format_parts[1].Foreground.Color == "accent", "visible float badge is not highlighted")
float_tab.is_active = false
assert(
  floating_ui.badge(float_tab, palette) == " F" and last_format_parts[1].Foreground.Color == "muted",
  "inactive tabs advertise a focused float"
)
float_tab.is_active = true
float_tab.floating_pane_visible = false
assert(floating_ui.badge(float_tab, palette) == " F", "hidden floats disappeared from their owner tab")
assert(last_format_parts[1].Foreground.Color == "muted", "hidden float badge is not subdued")
float_tab.floating_pane_count = 0
assert(floating_ui.badge(float_tab, palette) == "", "normal tabs gained a floating badge")
local stock_tab = setmetatable({ active_pane = base }, {
  __index = function(_, key)
    error("unknown field " .. key)
  end,
})
assert(
  floating_ui.normal_pane(stock_tab) == base and floating_ui.badge(stock_tab, palette) == "",
  "stock WezTerm compatibility failed"
)

local performed = {}
local pane_vars = { IS_NVIM = "true" }
local window = {
  perform_action = function(_, value)
    performed[#performed + 1] = value
  end,
}
local pane = {
  pane_id = function()
    return 12
  end,
  get_user_vars = function()
    return pane_vars
  end,
}

key_binding("h", "CTRL").action(window, pane)
assert(performed[1].SendKey.key == "h", "CTRL-h did not pass through to Neovim")
key_binding("v", "CTRL").action(window, pane)
assert(performed[2].SplitPane.command.domain == "CurrentPaneDomain", "CTRL-v did not split from Neovim")
key_binding("s", "CTRL|SHIFT").action(window, pane)
assert(performed[3].SplitPane.direction == "Down", "CTRL-SHIFT-s did not create a top-level down split")
key_binding("v", "CTRL|SHIFT").action(window, pane)
assert(performed[4].SplitPane.direction == "Right", "CTRL-SHIFT-v did not create a top-level right split")
pane_vars = {}
current_process = "slk"
for _, chord in ipairs({
  { "s", "CTRL" },
  { "v", "CTRL" },
  { "f", "CTRL" },
  { "t", "CTRL" },
  { "u", "CTRL" },
  { "d", "CTRL" },
}) do
  local before = #performed
  key_binding(chord[1], chord[2]).action(window, pane)
  if chord[1] == "s" or chord[1] == "v" or chord[1] == "t" then
    assert(not performed[before + 1].SendKey, "host creation chord was passed through")
  else
    assert(performed[before + 1].SendKey.key == chord[1], chord[2] .. "-" .. chord[1] .. " did not reach slk")
  end
end
current_process = "zsh"
key_binding("h", "CTRL").action(window, pane)
assert(performed[11].ActivatePaneDirection == "Left", "CTRL-h did not move from a shell pane")
-- nu is the pane shell now, so a shell list that forgot it would send every
-- readline chord to wezterm instead of to the prompt.
current_process = "nu"
key_binding("u", "CTRL").action(window, pane)
assert(performed[12].SendKey.key == "u", "CTRL-u did not pass through to a nushell pane")
performed[12] = nil
keybindings.locked_mode = true
key_binding("h", "CTRL").action(window, pane)
assert(performed[12].SendKey.mods == "CTRL", "locked mode consumed CTRL-h")
keybindings.locked_mode = false

current_process = "traces"
key_binding("f", "CTRL").action(window, pane)
assert(performed[13].SendKey.key == "f", "CTRL-f did not reach Traces")
key_binding("w", "CTRL").action(window, pane)
assert(performed[14].SendKey.key == "w", "CTRL-w did not reach Traces")
current_process = "orc"
key_binding("f", "CTRL").action(window, pane)
assert(performed[15].SendKey.key == "f", "CTRL-f did not reach Orc")
key_binding("w", "CTRL").action(window, pane)
assert(performed[16].SendKey.key == "w", "CTRL-w did not reach Orc")
current_process = "slk"
for _, key in ipairs({ "n", "w" }) do
  local before = #performed
  key_binding(key, "CTRL").action(window, pane)
  assert(performed[before + 1].SendKey.key == key, "CTRL-" .. key .. " did not reach slk")
end
current_process = "traces"
local before = #performed
key_binding("n", "CTRL").action(window, pane)
assert(performed[before + 1].SendKey.key == "n", "CTRL-n did not reach the Traces command picker")

current_process = "diffnav"
for _, key in ipairs({ "f", "u", "d" }) do
  local before = #performed
  key_binding(key, "CTRL").action(window, pane)
  assert(performed[before + 1].SendKey.key == key, "reader chord did not reach diffnav")
end
for _, key in ipairs({ "s", "v", "t" }) do
  local before = #performed
  key_binding(key, "CTRL").action(window, pane)
  assert(not performed[before + 1].SendKey, "reader changed same-host terminal bindings")
end

current_process = "ssh"
pane_vars = { SYSINIT_APP = "traces" }
pane.is_alt_screen_active = function()
  return true
end
local before_remote = #performed
key_binding("h", "CTRL").action(window, pane)
assert(performed[before_remote + 1].SendKey.key == "h", "remote app did not receive navigation")
pane.is_alt_screen_active = function()
  return false
end
key_binding("h", "CTRL").action(window, pane)
assert(performed[before_remote + 2].ActivatePaneDirection == "Left", "stale app captured shell navigation")

pane_vars = {}

require("session_tree.options").configure({
  picker = require("sysinit.pkg.utils").load_json_file("config.json").picker,
  passthrough_procs = require("sysinit.pkg.utils").load_json_file("config.json").passthrough_procs,
  shell = require("sysinit.pkg.utils").load_json_file("config.json").shell,
  home = "/nonexistent",
  binding = { key = "s", mods = "SUPER" },
  adapters = {
    format = require("sysinit.pkg.ui.format"),
    panes = require("sysinit.pkg.ui.panes"),
    badges = require("sysinit.pkg.ui.badges"),
  },
})
local selector = require("session_tree.switcher").session_selector_options({
  { id = "ws:newest", label = "newest" },
  { id = "ws:older", label = "older" },
}, "open")
assert(#selector.choices == 2, "the session picker injected a non-session row")
assert(selector.choices[1].id == "ws:newest", "the session picker changed recency order")
assert(not selector.alphabet:find("j", 1, true), "j selects a row instead of moving down")
assert(not selector.alphabet:find("k", 1, true), "k selects a row instead of moving up")
assert(not selector.alphabet:find("x", 1, true), "x selects a row after the close action moved out of the picker")
assert(not selector.alphabet:find("/", 1, true), "/ cannot enter the built-in filter")

local badges = require("sysinit.pkg.ui.badges")
local badge_names = {}
local badge_nouns = {}
for pane_id = 0, 7919 do
  local name = badges.name(pane_id)
  assert(name:match("^[a-z]+%-[a-z]+$"), "pane badge is not adjective-noun: " .. name)
  assert(not badge_names[name], "pane badge repeats before the full name list: " .. name)
  badge_names[name] = true
  badge_nouns[name:match("%-([a-z]+)$")] = true
end
assert(badges.name(0):match("%-muadib$"), "pane 0 lost its original character noun")
for _, noun in ipairs({ "chani", "saphira", "locke", "sabetha", "bilbo", "goldberry", "geralt", "yennefer" }) do
  assert(badge_nouns[noun], "pane noun catalog is missing " .. noun)
end
assert(
  require("session_tree.switcher").session_tree_description()
    == "  ! wezterm  @ tether  # zmx  $ seshy  % zoxide  |  j/k move  / filter  |  Enter open  x close  Esc quit",
  "session tree help diverged from its action metadata"
)

local cached_catalog, delivered_catalog, deliver_callback
package.loaded["session_tree.catalog"] = {
  peek = function()
    return cached_catalog
  end,
  load = function(_, _, callback)
    if callback then
      deliver_callback = callback
    end
  end,
}
package.loaded["session_tree.launcher"] = nil
package.loaded["session_tree.switcher"] = nil
local session_config = {}
local switcher = require("session_tree.switcher")
switcher.setup(session_config, { apply_to_config = function() end }, {
  sessions = function()
    return {}, {}
  end,
  tree = function()
    return { workspaces = {}, attention = {}, sections = {} }
  end,
  colors = function()
    return {}
  end,
  icons = {},
  home = "/home/test",
})
local session_keys = {}
for _, binding in ipairs(session_config.key_tables.session_tree_selector) do
  session_keys[binding.key] = binding
end
assert(
  session_keys["@"] and session_keys["!"] and session_keys["#"] and session_keys["$"] and session_keys.x,
  "session actions are absent from the hidden key table"
)
assert(session_keys["/"], "slash cannot leave the action layer and enter filtering")
local tree_actions = {}
local active_tree_table
local tree_window = {
  active_key_table = function()
    return active_tree_table
  end,
  window_id = function()
    return 7
  end,
  perform_action = function(_, value)
    tree_actions[#tree_actions + 1] = value
    if type(value) == "table" and value.ActivateKeyTable then
      active_tree_table = value.ActivateKeyTable.name
    elseif value == wezterm.action.PopKeyTable then
      active_tree_table = nil
    end
  end,
}
session_keys["/"].action(tree_window, pane)
assert(#tree_actions == 2, "slash did not leave the session action table")
assert(tree_actions[2].SendKey.key == "/", "slash did not enter the native filter")

local original_rows = package.loaded["session_tree.tree_rows"]
package.loaded["session_tree.tree_rows"] = {
  new = function()
    return function()
      return { { id = "ws:default", label = "default" } }
    end
  end,
}
local launcher_module = require("session_tree.launcher")
local original_open = launcher_module.open
local launched
launcher_module.open = function(_, _, key, before_show)
  launched = key
  assert(active_tree_table == "session_tree_selector", "provider loading dismissed the tree")
  before_show()
end
local context = {
  tree = function()
    return {}
  end,
  colors = function()
    return {}
  end,
  icons = {},
  home = "/home/test",
}
local first_config, second_config = {}, {}
switcher.setup(first_config, { apply_to_config = function() end }, context)
switcher.setup(second_config, { apply_to_config = function() end }, context)
for _, shortcut in ipairs({ "!", "@", "#", "$", "%" }) do
  tree_actions = {}
  for _, binding in ipairs(first_config.keys) do
    if binding.key == "s" and binding.mods == "SUPER" then
      binding.action(tree_window, pane)
    end
  end
  local selection = tree_actions[#tree_actions].InputSelector
  assert(selection, "the session tree did not open")
  local before_repeat = #tree_actions
  for _, binding in ipairs(first_config.keys) do
    if binding.key == "s" and binding.mods == "SUPER" then
      binding.action(tree_window, pane)
    end
  end
  assert(#tree_actions == before_repeat, "repeated opening stacked a persistent key table")
  for _, binding in ipairs(second_config.key_tables.session_tree_selector) do
    if binding.key == shortcut then
      binding.action(tree_window, pane)
    end
  end
  assert(launched == shortcut, "a provider action was lost across configuration instances")
  assert(active_tree_table == nil, "provider transition left the tree key table active")
  for _, action in ipairs(tree_actions) do
    assert(type(action) ~= "table" or not action.SendKey, "provider transition injected a key into the old selector")
  end
  assert(wezterm.GLOBAL["session_tree_action:7"] == nil, "a completed provider action remained pending")
end
launcher_module.open = original_open
package.loaded["session_tree.tree_rows"] = original_rows

local refreshed
local switch_actions = {}
local function last_switch()
  return switch_actions[#switch_actions]
end
local session_actions = require("session_tree.actions")
session_actions.set_refresh_handler(function(target)
  refreshed = target
end)
local switch_window = {
  active_workspace = function()
    return "older"
  end,
  perform_action = function(_, value)
    switch_actions[#switch_actions + 1] = value
  end,
}
session_actions.switch_to_workspace(switch_window, pane, "newest")
assert(last_switch().SwitchToWorkspace.name == "newest", "session switch did not target the selected workspace")
assert(last_switch().SwitchToWorkspace.spawn == nil, "a switch with no row invented a spawn")
assert(refreshed == switch_window, "session switch did not refresh the active session indicator")

local launcher = require("session_tree.launcher")
local ui_sessions = require("session_tree.sessions")
local function mux_window(name, id)
  return {
    get_workspace = function()
      return name
    end,
    window_id = function()
      return id
    end,
    tabs = function()
      return {}
    end,
    gui_window = function()
      return nil
    end,
  }
end
mux_windows = { mux_window("alpha", 1), mux_window("remote:alpha", 2) }
local calls = 0
child_process = function()
  calls = calls + 1
  error("unexpected process")
end
local tree = require("session_tree.session_tree").build({})
assert(#tree.workspaces == 2 and calls == 0, "tree discovery must read only the mux")
assert(tree.sections == nil, "directory catalogs leaked into the live tree")

local plan = { kind = "spawn", cwd = "/work/a b", command = {}, environment = { SESSION = "review" } }
assert(launcher.spawn(plan).domain.DomainName == "local", "provider opened on the current remote domain")
assert(launcher.spawn({ kind = "spawn", cwd = "relative", command = {}, environment = {} }) == nil)
local performed, notices, argv = {}, {}, {}
local launch_window = {
  active_pane = function()
    return pane
  end,
  window_id = function()
    return 8
  end,
  mux_window = function()
    return {
      active_pane = function()
        return pane
      end,
    }
  end,
  perform_action = function(_, value)
    performed[#performed + 1] = value
  end,
  toast_notification = function(_, _, message)
    notices[#notices + 1] = message
  end,
}
local valid_catalog = {
  descriptor = { title = "Sessions", icon = "md_layers", create = { label = "New session", prompt = "Name" } },
  listed = { items = { { id = "review", segments = { { text = "review", role = "name" } } } } },
  can_create = true,
}
child_process = function(args)
  argv[#argv + 1] = args
  return true, "plan", ""
end
json_parse = function()
  return plan
end
launcher.open(launch_window, pane, "$")
assert(performed[#performed].InputSelector.title == "Loading seshy", "cold provider did not display immediately")
assert(#argv == 0, "cold provider blocked the keypress on a child process")
local cancelled = performed[#performed].InputSelector
cancelled.action(launch_window, pane, nil)
local before = #performed
deliver_callback(valid_catalog)
assert(#performed == before, "cancelled provider loading reopened its selector")
launcher.open(launch_window, pane, "$")
launcher.cancel(launch_window)
before = #performed
deliver_callback(valid_catalog)
assert(#performed == before, "returning to the tree allowed an old provider to reopen")
launcher.open(launch_window, pane, "$")
local previous_active_pane = launch_window.active_pane
launch_window.active_pane = function()
  return {
    pane_id = function()
      return 99
    end,
  }
end
before = #performed
deliver_callback(valid_catalog)
assert(#performed == before, "provider loading replaced another overlay")
launch_window.active_pane = previous_active_pane
launcher.open(launch_window, pane, "$")
local obsolete_callback = deliver_callback
launcher.open(launch_window, pane, "%")
before = #performed
obsolete_callback(valid_catalog)
assert(#performed == before, "an old provider response replaced the current picker")
deliver_callback(valid_catalog)
assert(performed[#performed].InputSelector.title == "Sessions")
cached_catalog = valid_catalog
launcher.open(launch_window, pane, "$")
local picker = performed[#performed].InputSelector
assert(picker.title == "Sessions" and #picker.choices == 2, "advertised creation is missing")
assert(picker.choices[1].id == "review", "creation replaced the default existing-session selection")
assert(#argv == 0, "warm provider opening started a synchronous process")
picker.action(launch_window, pane, "review")
local opened = performed[#performed].SwitchToWorkspace
assert(opened.spawn.cwd == "/work/a b" and opened.spawn.domain.DomainName == "local")
assert(argv[1][3] == "picker.open" and argv[1][4] == "review", "provider ID did not stay one argument")
launcher.open(launch_window, pane, "$")
picker = performed[#performed].InputSelector
picker.action(launch_window, pane, picker.choices[#picker.choices].id)
local prompt = performed[#performed].PromptInputLine
assert(prompt and prompt.description == "Name", "creation did not prompt for a name")
before = #argv
prompt.action(launch_window, pane, nil)
assert(#argv == before, "cancelled creation invoked the provider")
wezterm.json_encode = function()
  return '["nu"]'
end
prompt.action(launch_window, pane, "new session")
assert(argv[#argv][3] == "picker.create" and argv[#argv][4] == "new session")
assert(performed[#performed].SwitchToWorkspace.spawn.set_environment_variables.WEZTERM_PICKER_SHELL == '["nu"]')
valid_catalog.can_create = false
launcher.open(launch_window, pane, "$")
assert(#performed[#performed].InputSelector.choices == 1, "unadvertised creation was offered")
for _, malformed in ipairs({ false, { id = "x", segments = { false } }, { id = "x", segments = "bad" } }) do
  cached_catalog = { descriptor = valid_catalog.descriptor, listed = { items = { malformed } } }
  launcher.open(launch_window, pane, "$")
  assert(notices[#notices] == "Provider returned an invalid or duplicate item")
end
cached_catalog = { descriptor = { title = false, icon = {} }, listed = { items = {} } }
launcher.open(launch_window, pane, "$")
assert(notices[#notices] == "Provider returned an invalid description")
before = #argv
launcher.open(launch_window, pane, "!")
picker = performed[#performed].InputSelector
assert(picker.title == "WezTerm sessions" and #argv == before, "native sessions invoked a provider")
picker.action(launch_window, pane, picker.choices[#picker.choices].id)
prompt = performed[#performed].PromptInputLine
prompt.action(launch_window, pane, "scratch shell")
opened = performed[#performed].SwitchToWorkspace
assert(opened.name == "scratch shell" and opened.spawn.cwd == "/nonexistent" and opened.spawn.args == nil)
assert(wezterm.GLOBAL.native_workspaces["scratch shell"], "native workspace ownership was not recorded")
assert(#argv == before, "native creation invoked a provider")
mux_windows = { mux_window("default", 1), mux_window("scratch shell", 2), mux_window("review", 3) }
launcher.open(launch_window, pane, "!")
picker = performed[#performed].InputSelector
assert(#picker.choices == 3, "native picker included a provider-owned workspace")
assert(picker.choices[1].id == "default" and picker.choices[2].id == "scratch shell")
picker.action(launch_window, pane, picker.choices[#picker.choices].id)
prompt = performed[#performed].PromptInputLine
prompt.action(launch_window, pane, "review")
assert(notices[#notices] == "Session already exists: review", "native creation reused another provider's workspace")
mux_windows = {}
assert(launcher.spawn({ kind = "spawn", cwd = "/tmp", command = { args = "bad" }, environment = {} }) == nil)
assert(launcher.spawn({ kind = "spawn", cwd = "/tmp", command = {}, environment = { ["BAD=KEY"] = "x" } }) == nil)

local ui_format = require("sysinit.pkg.ui.format")
assert(ui_format.smart_path("/state/seshy/sessions/alpha") == "{sy}/alpha", "a configured alias did not abbreviate")
assert(ui_format.smart_path("/state/seshy/sessions") == "{sy}", "an alias did not abbreviate its own directory")
assert(ui_format.smart_path("/state/seshy/sessionsx") == "/state/seshy/sessionsx", "an alias matched a sibling prefix")
assert(ui_format.is_passthrough("zmx") and not ui_format.is_passthrough("nvim"), "passthrough config was ignored")

local opaque = "1vck9ziv21pzp08093vb3nk4634nk760miia5116w45c2ncp4vqc"
local transient_pane = {
  get_foreground_process_name = function()
    return "/tmp/" .. opaque
  end,
  get_title = function()
    return opaque
  end,
}
local transient_tab = {
  get_title = function()
    return opaque
  end,
}
local configured_format = require("session_tree.adapters").format
assert(configured_format.pane_proc(transient_pane, "claude") == "claude")
assert(configured_format.pane_proc(transient_pane) == "")
assert(configured_format.tab_label(transient_tab, 1, transient_pane, "claude") == "claude")
assert(configured_format.tab_label(transient_tab, 1, transient_pane) == "tab 1")
assert(ui_format.normalize_proc(opaque) == "")
transient_tab.get_title = function()
  return "release notes"
end
assert(configured_format.tab_label(transient_tab, 1, transient_pane, "claude") == "release notes")

local ribbon = {
  new = function()
    local parts = {}
    return {
      append = function(_, _, _, text)
        parts[#parts + 1] = text
      end,
      append_items = function() end,
      format = function()
        return table.concat(parts)
      end,
    }
  end,
}
local rows = require("session_tree.tree_rows").new({ ribbon = ribbon, icons = { session = "W" } })
local targets = {}
local choices = rows(tree, targets, "all", {})
assert(#choices == 2 and targets["ws:alpha"] and targets["ws:remote:alpha"], "live tree rendering lost a workspace")
assert(not targets["ws:directory"], "directory launcher rows leaked into the tree")

local windowtitle = require("sysinit.pkg.ui.windowtitle")
local statusbar = require("sysinit.pkg.ui.statusbar")
local tabtitle = require("sysinit.pkg.ui.tabtitle")
assert(statusbar.tab_index({ tab_index = 0 }) == "[1]")
assert(statusbar.tab_index({ tab_index = 8 }) == "[9]")
assert(tabtitle.format({ tab_index = 1, tab_title = "review" }, {}, { home = "" }) == " [2] review ")
assert(tabtitle.format({ tab_index = 0 }, {}, { home = "" }) == " [1] shell ")
local saved_windows = mux_windows
mux_windows = {}
for _, entry in ipairs({ { 12, "default" }, { 7, "other" }, { 4, "default" } }) do
  mux_windows[#mux_windows + 1] = {
    window_id = function()
      return entry[1]
    end,
    get_workspace = function()
      return entry[2]
    end,
  }
end
local status_window = {
  active_workspace = function()
    return "default"
  end,
  window_id = function()
    return 12
  end,
}
assert(statusbar.window_index(status_window) == "[2] ")
status_window.window_id = function()
  return 4
end
assert(statusbar.window_index(status_window) == "[1] ")
table.insert(mux_windows, 1, {
  window_id = function()
    return 15
  end,
  get_workspace = function()
    return "default"
  end,
})
assert(statusbar.window_index(status_window) == "[1] ")
status_window.window_id = function()
  return 15
end
assert(statusbar.window_index(status_window) == "[3] ")
local chips = statusbar.session_chips(status_window, {}, { default = 1, review = 2 }, {
  idle = "gray",
  name = "white",
  chrome = "gray",
})
assert(chips == "  [1] default ·    [2] review ·  ", chips)
local original_format = wezterm.format
local styled
wezterm.format = function(items)
  styled = items
  return original_format(items)
end
statusbar.session_chips(status_window, {}, { default = 1, review = 2 }, {
  idle = "gray",
  name = "white",
  chrome = "gray",
}, {
  active = { fg = "active-fg", bg = "active-bg" },
  inactive = { fg = "inactive-fg", bg = "inactive-bg" },
})
wezterm.format = original_format
local backgrounds = {}
for _, item in ipairs(styled) do
  if type(item) == "table" and item.Background then
    backgrounds[#backgrounds + 1] = item.Background.Color
  end
end
assert(backgrounds[1] == "active-bg" and backgrounds[2] == "inactive-bg", "session selection diverged from tab colors")
mux_windows = saved_windows
local test_home = os.getenv("HOME") or "/home/test"
local title = windowtitle.format({
  active_pane = {
    foreground_process_name = "/profile/bin/codex",
    current_working_dir = { file_path = test_home .. "/github/personal/roshbhatia/sysinit" },
    title = "reviewing provider changes",
    user_vars = {},
  },
}, nil, "sysinit")
assert(title == "sysinit · codex · {gh}/sysinit", "the window title lost session, process, or cwd: " .. title)
local explicit_title = windowtitle.format({
  active_pane = {
    foreground_process_name = "/profile/bin/nu",
    current_working_dir = { file_path = test_home },
    title = "nu",
    user_vars = { SYSINIT_WINDOW_METADATA = "agent: verifier\nready" },
  },
}, nil, "default")
assert(
  explicit_title == "default · nu · {home} · agent: verifier ready",
  "the window title dropped explicit metadata: " .. explicit_title
)
local invalid = string.char(0xff, 0xc3, 0x28)
local original_get_pane = wezterm.mux.get_pane
wezterm.mux.get_pane = function()
  return {
    get_program_status = function()
      return { { app = "codex", state = "working", title = "Review provider changes" } }
    end,
  }
end
local protocol_title = windowtitle.format(nil, {
  pane_id = 17,
  title = "wezterm",
  current_working_dir = { file_path = test_home .. "/github/personal/roshbhatia/sysinit" },
}, "review", { codex = { label = "Codex" } })
assert(protocol_title == "review · Codex · {gh}/sysinit", protocol_title)
local native_title = windowtitle.format(nil, {
  pane_id = 17,
  title = "Named conversation",
  user_vars = { agent_state = "working|tool: command|0|claude" },
}, "review", { claude = { label = "Claude Code" }, codex = { label = "Codex" } })
assert(native_title == "review · Claude Code", "the agent topic leaked into the window title: " .. native_title)
wezterm.mux.get_pane = original_get_pane
local observed_title = windowtitle.format(nil, {
  foreground_process_name = "/profile/bin/agent",
  title = "Review the cache",
}, "review", { cursor = { label = "Cursor" } }, "cursor")
assert(observed_title == "review · Cursor", "registry detection was replaced by a generic executable name")
do
  local fact_title = windowtitle.format(
    nil,
    {
      pane_id = 18,
      current_working_dir = { file_path = test_home .. "/github/personal/roshbhatia/sysinit" },
    },
    "sysinit-firefox",
    { claude = { label = "Claude Code" } },
    nil,
    {
      agent = "claude",
      status = "waiting",
      repo = "sysinit",
      branch = "feat/firefox",
    }
  )
  assert(fact_title == "sysinit-firefox · Claude Code (waiting) · sysinit:feat/firefox", fact_title)
  local idle_title = windowtitle.format(nil, { pane_id = 18 }, "default", { claude = { label = "Claude Code" } }, nil, {
    agent = "claude",
    status = "idle",
  })
  assert(idle_title == "default · Claude Code", "an idle agent carried a state suffix: " .. idle_title)
  local alias_title = windowtitle.format(
    nil,
    { pane_id = 19 },
    "default",
    { claude = { label = "Claude Code" } },
    "claude-code",
    {
      agent = "claude",
      status = "working",
    }
  )
  assert(
    alias_title == "default · Claude Code (working)",
    "an unregistered alias hid the registered agent: " .. alias_title
  )
  local agent_facts = function()
    return { agent = "claude", status = "waiting", branch = "feat/firefox" }
  end
  local agent_tab = tabtitle.format({
    tab_index = 0,
    active_pane = { pane_id = 3, title = "Fix the diff conflict in the palette commands" },
  }, {}, { home = "", identities = { claude = { glyph = "G", label = "Claude Code" } }, facts = agent_facts })
  assert(agent_tab == " [1] G Fix the diff conflict in th… feat/firefox ", "agent tab title: " .. agent_tab)
  local plain_tab = tabtitle.format({
    tab_index = 0,
    active_pane = { pane_id = 4, title = "claude" },
  }, {}, {
    home = "",
    identities = { claude = { glyph = "G", label = "Claude Code" } },
    facts = function()
      return { agent = "claude", branch = "main" }
    end,
  })
  assert(plain_tab == " [1] G Claude Code ", "agent tab without a topic: " .. plain_tab)
  local git_head = require("sysinit.pkg.ui.git_head")
  local git_root = os.tmpname()
  os.remove(git_root)
  local function make(path, text)
    assert(os.execute("mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'"))
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
  end
  make(git_root .. "/repo/.git/HEAD", "ref: refs/heads/main\n")
  make(git_root .. "/repo/src/keep", "")
  make(git_root .. "/repo/.git/worktrees/topic/HEAD", "ref: refs/heads/feat/topic\n")
  make(git_root .. "/topic/.git", "gitdir: " .. git_root .. "/repo/.git/worktrees/topic\n")
  make(git_root .. "/detached/.git/HEAD", "0123456789abcdef0123456789abcdef01234567\n")
  local main_head = git_head.lookup(git_root .. "/repo/src", 1)
  assert(main_head and main_head.repo == "repo" and main_head.branch == "main", "git_head missed a nested checkout")
  local topic_head = git_head.lookup(git_root .. "/topic", 1)
  assert(topic_head and topic_head.repo == "repo" and topic_head.branch == "feat/topic", "git_head missed a worktree")
  local detached_head = git_head.lookup(git_root .. "/detached", 1)
  assert(detached_head and detached_head.branch == "0123456", "git_head missed a detached HEAD")
  assert(git_head.lookup(git_root, 1) == nil, "git_head invented a repository")
  os.execute("rm -rf '" .. git_root .. "'")
end
local escaped = string.char(0x1b) .. "[31mred" .. string.char(0x1b) .. "[0m"
local hostile_title = windowtitle.format({
  active_pane = {
    foreground_process_name = "/profile/bin/co" .. invalid .. "dex",
    current_working_dir = { file_path = test_home .. "/github/personal/roshbhatia/sy" .. invalid .. "init" },
    title = "ignored",
    user_vars = { SYSINIT_WINDOW_METADATA = escaped .. invalid .. "\nprovider" },
  },
}, nil, "sys" .. string.char(0) .. "init")
assert(utf8.len(hostile_title), "the hidden window title returned invalid UTF-8")
assert(not hostile_title:find("[%c]"), "the hidden window title retained a control byte")
assert(not hostile_title:find("[31m", 1, true), "the hidden window title retained a terminal control sequence")
assert(hostile_title:find("provider", 1, true), "the hidden window title lost sanitized provider metadata")
local pane_title = windowtitle.format({
  active_pane = {
    foreground_process_name = "/profile/bin/codex",
    current_working_dir = { file_path = test_home },
    user_vars = { SYSINIT_WINDOW_METADATA = "review " .. invalid .. " ready 🚀" },
  },
}, nil, "default")
assert(utf8.len(pane_title), "malformed window metadata produced invalid UTF-8")
assert(pane_title:find("ready 🚀", 1, true), "window metadata repair lost later valid Unicode")
local bounded_title = windowtitle.format({
  active_pane = {
    foreground_process_name = string.rep("p", 5000),
    current_working_dir = { file_path = string.rep("d", 5000) },
    user_vars = { SYSINIT_WINDOW_METADATA = string.rep("t", 5000) },
  },
}, nil, string.rep("s", 5000))
assert(#bounded_title <= 1024, "the hidden window title exceeded its byte bound")
assert(utf8.len(bounded_title), "the bounded window title ended inside a UTF-8 sequence")
assert(not bounded_title:find("……", 1, true), "the window title added duplicate truncation markers")
local boundary_title = windowtitle.format({
  active_pane = {
    foreground_process_name = string.rep("p", 256),
    current_working_dir = { file_path = string.rep("d", 256) },
    user_vars = { SYSINIT_WINDOW_METADATA = string.rep("m", 240) .. "🚀x" },
  },
}, nil, string.rep("s", 256))
assert(#boundary_title <= 1024, "the Unicode boundary title exceeded its byte bound")
assert(utf8.len(boundary_title), "the window title cutoff split a UTF-8 sequence")
assert(boundary_title:sub(-3) == "…", "the window title cutoff lost its truncation marker")

local event_config = {}
require("sysinit.pkg.events").setup(event_config)
assert(event_config.enable_scroll_bar, "event setup did not enable the scroll bar")

local clipboard
local overrides = { preserved = true }
local get_override_calls = 0
local set_override_calls = 0
local event_action
local active_event_id = 1
local event_window = {
  active_pane = function()
    return {
      pane_id = function()
        return active_event_id
      end,
    }
  end,
  window_id = function()
    return 1
  end,
  copy_to_clipboard = function(_, value, target)
    clipboard = { value = value, target = target }
  end,
  perform_action = function(_, value)
    event_action = value
  end,
  get_config_overrides = function()
    get_override_calls = get_override_calls + 1
    return overrides
  end,
  set_config_overrides = function(_, value)
    set_override_calls = set_override_calls + 1
    overrides = value
  end,
}
local alt_screen = false
local event_pane = {
  pane_id = function()
    return 1
  end,
  get_dimensions = function()
    return { scrollback_rows = 100, viewport_rows = 20 }
  end,
  is_alt_screen_active = function()
    return alt_screen
  end,
}

event_window.mux_window = function()
  return {
    active_pane = function()
      return event_pane
    end,
  }
end

handlers["user-var-changed"](event_window, event_pane, "wez_copy", "copied text")
assert(clipboard.value == "copied text" and clipboard.target == "Clipboard", "wez_copy missed the clipboard")
handlers["user-var-changed"](event_window, event_pane, "SYSINIT_NAV", "left:editor")
assert(event_action.ActivatePaneDirection == "Left", "SYSINIT_NAV did not activate the left pane")
active_event_id = 2
event_action = nil
handlers["user-var-changed"](event_window, event_pane, "SYSINIT_NAV", "right:late")
assert(event_action == nil, "a delayed edge request moved another active pane")
active_event_id = 1

handlers["update-status"](event_window, event_pane)
assert(overrides.preserved and overrides.enable_scroll_bar == nil, "the default scroll bar gained an override")
assert(get_override_calls == 1 and set_override_calls == 0, "the initial default scroll bar state was reapplied")
handlers["update-status"](event_window, event_pane)
assert(get_override_calls == 1 and set_override_calls == 0, "an unchanged scroll bar state read or wrote overrides")
alt_screen = true
handlers["update-status"](event_window, event_pane)
assert(not overrides.enable_scroll_bar, "the alternate screen kept the scroll bar")
assert(overrides.preserved, "a scroll bar transition discarded an existing override")
assert(get_override_calls == 2 and set_override_calls == 1, "the hidden scroll bar transition was not applied once")
handlers["update-status"](event_window, event_pane)
assert(get_override_calls == 2 and set_override_calls == 1, "a stable hidden scroll bar reapplied overrides")
alt_screen = false
handlers["update-status"](event_window, event_pane)
assert(overrides.enable_scroll_bar == nil, "the visible scroll bar did not return to its configured default")
assert(overrides.preserved, "restoring the scroll bar discarded an existing override")
assert(get_override_calls == 3 and set_override_calls == 2, "the visible scroll bar transition was not applied once")

local overlay = {
  pane_id = function()
    return 99
  end,
  get_dimensions = function()
    return { scrollback_rows = 20, viewport_rows = 20 }
  end,
  is_alt_screen_active = function()
    return false
  end,
}
handlers["update-status"](event_window, overlay)
assert(set_override_calls == 2, "a picker overlay reloaded the window and cleared its key table")
assert(overrides.enable_scroll_bar == nil, "a picker overlay changed the terminal scroll bar")
handlers["update-status"](event_window, event_pane)
assert(set_override_calls == 2, "closing a picker reloaded an unchanged terminal")

local second_overrides = { second_window = true }
local second_get_calls = 0
local second_set_calls = 0
local second_window = {
  mux_window = event_window.mux_window,
  window_id = function()
    return 2
  end,
  get_config_overrides = function()
    second_get_calls = second_get_calls + 1
    return second_overrides
  end,
  set_config_overrides = function(_, value)
    second_set_calls = second_set_calls + 1
    second_overrides = value
  end,
}
alt_screen = true
handlers["update-status"](second_window, event_pane)
assert(second_overrides.second_window, "one window's scroll bar discarded another window's override")
assert(second_overrides.enable_scroll_bar == false, "the second window did not hide its scroll bar")
assert(second_get_calls == 1 and second_set_calls == 1, "the second window did not reconcile independently")
handlers["update-status"](second_window, event_pane)
assert(second_get_calls == 1 and second_set_calls == 1, "the second window reapplied a stable override")

local inherited_overrides = { enable_scroll_bar = false, external = "kept" }
local inherited_sets = 0
local inherited_window = {
  mux_window = event_window.mux_window,
  window_id = function()
    return 3
  end,
  get_config_overrides = function()
    return inherited_overrides
  end,
  set_config_overrides = function(_, value)
    inherited_sets = inherited_sets + 1
    inherited_overrides = value
  end,
}
alt_screen = false
handlers["update-status"](inherited_window, event_pane)
assert(inherited_sets == 1, "a stale scroll bar override was not reconciled")
assert(inherited_overrides.enable_scroll_bar == nil, "a stale scroll bar override was not removed")
assert(inherited_overrides.external == "kept", "scroll bar reconciliation discarded an external override")
local later_status_ran = false
local stale_pane = {
  get_dimensions = function()
    error("pane id not found in mux")
  end,
}
local stale_ok = pcall(function()
  handlers["update-status"](event_window, stale_pane)
  later_status_ran = true
end)
assert(stale_ok, "a stale pane aborted the update-status event")
assert(later_status_ran, "a stale pane stopped later status handlers")

local duplicate_config = {
  keys = {
    { mods = "CTRL|SHIFT", key = "x" },
    { mods = "SHIFT|CTRL", key = "x" },
  },
}
assert(not pcall(require("sysinit.pkg.validate").setup, duplicate_config), "reordered duplicate keys passed validation")
local alias_config = {
  keys = {
    { mods = "SUPER", key = "x" },
    { mods = "CMD", key = "x" },
  },
}
assert(not pcall(require("sysinit.pkg.validate").setup, alias_config), "modifier aliases passed validation")

local loader = require("sysinit.pkg.plugin_loader")
local missing = loader.load("missing")
assert(not missing, "a missing plugin loaded")
assert(#wezterm.plugin.list() == 0, "a failed plugin registered as loaded")
local loaded, plugin = loader.load("fixture")
assert(loaded, "the local plugin did not load")
assert(plugin.value == "dependency", "the plugin dependency did not use its local scope")
local loaded_again, cached_plugin = loader.load("fixture")
assert(loaded_again and cached_plugin == plugin, "the plugin loader did not reuse a loaded plugin")
local plugin_list = wezterm.plugin.list()
assert(#plugin_list == 1, "the local plugin did not register")
assert(plugin_list[1].component == "fixture", "the plugin registered under the wrong name")
wezterm.plugin.require = function()
  error("network plugin loader must not run")
end
local nested_ok, nested = loader.load("nested")
assert(nested_ok and nested.value == "dependency", "a nested plugin did not use its pinned dependency")
assert(#wezterm.plugin.list() == 2, "a nested import loaded its dependency twice")
assert(nested.unknown:find("No pinned dependency", 1, true), "an unknown dependency reached the network loader")

local calls = {}
for _, name in ipairs({ "core", "events", "keybindings", "ui", "validate" }) do
  package.loaded["sysinit.pkg." .. name] = {
    setup = function(config)
      calls[#calls + 1] = name
      config[name] = true
    end,
  }
end
wezterm.config_builder = function()
  return { built = true }
end
package.loaded["sysinit.pkg.bootstrap"] = nil
local built = require("sysinit.pkg.bootstrap").build()
assert(
  built.built and built.core and built.events and built.keybindings and built.ui and built.validate,
  "bootstrap dropped a module"
)
assert(table.concat(calls, ",") == "core,events,keybindings,ui,validate", "bootstrap changed module order")

package.loaded["sysinit.pkg.ui"] = {
  setup = function()
    error("expected failure")
  end,
}
local degraded = require("sysinit.pkg.bootstrap").build()
assert(
  degraded.core and degraded.events and degraded.keybindings and degraded.validate,
  "one optional failure stopped later composition"
)
assert(handlers["update-status"], "an optional failure registered no report")

package.loaded["sysinit.pkg.ui"] = {
  setup = function(config)
    config.ui = true
  end,
}
package.loaded["sysinit.pkg.validate"] = {
  setup = function()
    error("invalid final config")
  end,
}
local valid, validation_error = pcall(require("sysinit.pkg.bootstrap").build)
assert(not valid, "final validation could not fail the configuration")
assert(tostring(validation_error):find("invalid final config", 1, true), "validation failure lost its cause")

print("WezTerm modules, plugins, and chords passed")

local host_spawn = require("sysinit.pkg.host_spawn")
local function process_pane(info)
  return {
    get_foreground_process_info = function()
      return info
    end,
  }
end
local ssh_pane = process_pane({
  executable = "/usr/bin/ssh",
  argv = { "ssh", "-p", "2222", "-l", "admin", "-L", "8080:localhost:80", "arrakis", "deploy" },
})
local remote_tab = host_spawn.action(ssh_pane, "tab", false).SpawnCommandInNewTab
assert(
  table.concat(remote_tab.args, " ") == "ssh -o ClearAllForwardings=yes -o RemoteCommand=none -p 2222 -l admin arrakis",
  "SSH split replayed a command or port forward"
)
assert(remote_tab.domain.DomainName == "local", "SSH reconnect did not launch locally")
local mosh_pane = process_pane({
  executable = "/bin/mosh-client",
  argv = { "mosh-client", "-# admin@arrakis |", "100.94.4.109", "60001" },
})
local remote_split = host_spawn.action(mosh_pane, "Right", false).SplitPane
assert(table.concat(remote_split.command.args, " ") == "mosh admin@arrakis", "Mosh split lost its original destination")
for _, kind in ipairs({ "Down", "Right", "tab" }) do
  local action = host_spawn.action(mosh_pane, kind, true)
  local command = kind == "tab" and action.SpawnCommandInNewTab or action.SplitPane.command
  assert(command.domain.DomainName == "local" and command.args == nil, "local override retained the remote command")
end
assert(
  host_spawn.action(process_pane(nil), "tab", false).SpawnCommandInNewTab.domain == "CurrentPaneDomain",
  "native mux domain was discarded"
)
local unknown_mosh =
  process_pane({ executable = "/bin/mosh-client", argv = { "mosh-client", "100.94.4.109", "60001" } })
local unknown_action, unknown_error = host_spawn.action(unknown_mosh, "tab", false)
assert(unknown_action == nil and unknown_error, "unknown Mosh target silently spawned locally")

local state_panes = require("sysinit.pkg.ui.panes")
local state_rollup = require("sysinit.pkg.ui.rollup")
local real_time = os.time
local poll_time, deck_polls = 10000, 0
local saved_windows = mux_windows
mux_windows = {}
os.time = function()
  return poll_time
end
local function poll_deck()
  deck_polls = deck_polls + 1
  return {}
end
for _ = 1, 100 do
  state_rollup.states(poll_deck)
end
assert(deck_polls == 1, "title-triggered status events repeated agent detection within one tick")
poll_time = poll_time + 1
state_rollup.states(poll_deck)
assert(deck_polls == 2, "agent detection did not refresh on the next tick")
os.time = real_time
mux_windows = saved_windows
local screen = "• Working (14m 27s • esc to interrupt) · 2 background terminals running"
local state_pane = {
  get_user_vars = function()
    return {}
  end,
  get_lines_as_text = function()
    return screen
  end,
}
local stale_record = { status = "done", agent = "codex", since = 100, reason = "your move" }
local status, _, _, _, source = state_panes.agent_state(state_pane, {}, stale_record)
assert(status == "working" and source == "screen", "active Codex turn inherited stale completion")
stale_record.status = "waiting"
assert(state_panes.agent_state(state_pane, {}, stale_record) == "waiting", "active footer hid an approval request")
stale_record.status = "done"
screen = "An explanation about working and esc to interrupt"
assert(state_panes.agent_state(state_pane, {}, stale_record) == "done", "prose became activity")
screen = "› Ask Codex to do anything"
assert(state_panes.agent_state(state_pane, {}, stale_record) == "done", "idle prompt erased completion")
local reduced = state_rollup.reduce({
  { workspace = "mixed", status = "done" },
  { workspace = "mixed", status = "working" },
})
assert(reduced.mixed.status == "working", "finished pane hid a working pane")
reduced = state_rollup.reduce({
  { workspace = "mixed", status = "working" },
  { workspace = "mixed", status = "waiting" },
})
assert(reduced.mixed.status == "waiting", "working pane hid an approval request")

-- Exercise the production registry and smart-key callbacks under the Linux platform.
wezterm.target_triple = "x86_64-unknown-linux-gnu"
package.loaded["sysinit.pkg.keybindings"] = nil
package.loaded["sysinit.pkg.validate"] = nil
local linux_keys = require("sysinit.pkg.keybindings")
local linux_config = {}
linux_keys.setup(linux_config)
require("sysinit.pkg.validate").setup(linux_config)
local function linux_binding(key, mods)
  for _, binding in ipairs(linux_config.keys) do
    if binding.key == key and binding.mods == mods then
      return binding
    end
  end
  error("missing Linux chord: " .. mods .. "+" .. key)
end
local linux_window = {
  perform_action = function(self, value)
    self.last = value
  end,
}
linux_binding("v", "CTRL|SHIFT").action(linux_window, {})
assert(linux_window.last.PasteFrom == "Clipboard", "Linux paste still splits")
linux_binding("n", "CTRL|SHIFT").action(linux_window, {})
assert(linux_window.last.SpawnWindow, "Linux has no standard new-window shortcut")
linux_binding("f", "CTRL|SHIFT").action(linux_window, {})
assert(linux_window.last.Search, "Linux find still selects a pane")
linux_binding("r", "CTRL|SHIFT").action(linux_window, {})
assert(linux_window.last.ReloadConfiguration, "Linux reload still renames a tab")
linux_binding("1", "CTRL|SHIFT").action(linux_window, {})
assert(linux_window.last.ActivateTab == 0, "Linux tab digits lost native convention")
assert(linux_keys.workspace_modifiers[1] == "SUPER|CTRL|SHIFT", "Linux workspace digits collide with tabs/screenshots")
for _, binding in ipairs(linux_config.keys) do
  assert(not binding.mods:find("ALT", 1, true), "Linux binding consumes the WM modifier")
  assert(
    not (binding.mods == "SUPER" and (binding.key == "q" or binding.key == "h" or binding.key == "m")),
    "Linux binding collides with Sway lifecycle shortcuts"
  )
end
linux_binding("f", "SUPER").action(linux_window, {})
assert(linux_window.last.ToggleFloatingPane, "Linux tab-local floating action is missing")
for _, binding in ipairs(linux_config.keys) do
  assert(not (binding.key == "f" and binding.mods == "SUPER|SHIFT"), "Linux global float shortcut remains enabled")
  assert(
    not (binding.key == "Enter" and binding.mods == "SUPER|SHIFT"),
    "Linux additional float shortcut remains enabled"
  )
end
linux_binding("g", "CTRL").action(linux_window, {})
for _, chord in ipairs({
  { "f", "SUPER" },
  { "v", "CTRL|SHIFT" },
  { "n", "CTRL|SHIFT" },
  { "j", "SUPER|CTRL" },
}) do
  linux_binding(chord[1], chord[2]).action(linux_window, {})
  assert(
    linux_window.last.SendKey and linux_window.last.SendKey.key == chord[1],
    "locked mode executes a terminal action"
  )
end
linux_binding("g", "CTRL").action(linux_window, {})
assert(not linux_keys.locked_mode, "locked mode cannot be exited")
