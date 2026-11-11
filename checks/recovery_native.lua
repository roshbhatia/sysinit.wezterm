local native = require("wezterm")
local root = assert(os.getenv("SYSINIT_WEZTERM_LUA"))
local state_dir = assert(os.getenv("RECOVERY_TEST_STATE"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local windows, events, timers, operations = {}, {}, {}, {}
local active = "beta"
local attached = false
local serial = 0
local connection_window
local fake = {
  GLOBAL = { workspace_slots = { alpha = 2, beta = 3 } },
  home_dir = "/home/fixture",
  json_parse = native.json_parse,
  json_encode = native.json_encode,
  procinfo = native.procinfo,
  run_child_process = native.run_child_process,
  emit = function() end,
  log_warn = function(message)
    operations[#operations + 1] = message
  end,
  log_error = function(message)
    error(message)
  end,
  read_dir = function(path)
    if path == "/missing" then
      error("missing directory")
    end
    return {}
  end,
  on = function(name, callback)
    events[name] = callback
  end,
  action_callback = function(callback)
    return callback
  end,
  action = { ToggleFloatingPane = "toggle" },
  time = {
    call_after = function(delay, callback)
      timers[#timers + 1] = { delay, callback }
    end,
  },
}
for _, name in ipairs({ "SpawnCommandInNewFloatingPane", "AdjustPaneSize" }) do
  fake.action[name] = function(args)
    return { [name] = args }
  end
end
local function make_pane(domain, cwd, tab)
  serial = serial + 1
  local pane = { id = serial, domain = domain, cwd = cwd, tab_ref = tab }
  function pane:pane_id()
    return self.id
  end
  function pane:get_domain_name()
    return self.domain
  end
  function pane:get_current_working_dir()
    return { file_path = self.cwd }
  end
  function pane:is_alt_screen_active()
    error("metadata snapshots must not capture application state")
  end
  function pane:get_lines_as_text()
    error("metadata snapshots must not capture terminal output")
  end
  function pane:activate()
    self.tab_ref.selected = self
  end
  function pane:send_text(text)
    self.sent = (self.sent or "") .. text
  end
  function pane:inject_output(text)
    self.injected = (self.injected or "") .. text
  end
  function pane:split(args)
    local child = make_pane(args.domain and args.domain.DomainName or self.domain, args.cwd, self.tab_ref)
    self.tab_ref.positions[#self.tab_ref.positions + 1] = { left = 41, top = 0, width = 39, height = 24, pane = child }
    return child
  end
  function pane:spawn_floating_pane(args)
    local child = make_pane(args.domain.DomainName, args.cwd, self.tab_ref)
    self.tab_ref.positions[#self.tab_ref.positions + 1] = {
      left = 20,
      top = 5,
      width = args.width,
      height = args.height,
      pane = child,
      is_floating = true,
      is_active = args.visible,
    }
    return child
  end
  return pane
end
local function make_tab(window, domain, cwd)
  local tab = { parent = window, title = "fixture", positions = {} }
  tab.selected = make_pane(domain, cwd, tab)
  tab.positions[1] = { left = 0, top = 0, width = 40, height = 24, pane = tab.selected, is_active = true }
  function tab:get_title()
    return self.title
  end
  function tab:set_title(value)
    self.title = value
  end
  function tab:panes_with_info()
    local result = {}
    for _, position in ipairs(self.positions) do
      local copy = {}
      for key, value in pairs(position) do
        copy[key] = value
      end
      result[#result + 1] = copy
    end
    return result
  end
  function tab:get_size()
    return { cols = 80, rows = 24 }
  end
  function tab:active_pane()
    return self.selected
  end
  function tab:window()
    return self.parent
  end
  function tab:activate()
    self.parent.selected = self
  end
  function tab:set_zoomed(value)
    self.zoomed = value
  end
  return tab
end
local function make_window(workspace, domain, cwd)
  local window = { workspace = workspace, title = "fixture", tab_list = {} }
  local gui = {}
  function gui:perform_action(action)
    local tab = window.selected
    if action.SpawnCommandInNewFloatingPane then
      local args = action.SpawnCommandInNewFloatingPane
      local pane = make_pane(args.domain.DomainName, args.cwd, tab)
      tab.positions[#tab.positions + 1] =
        { left = 20, top = 5, width = 30, height = 10, pane = pane, is_floating = true, is_active = true }
    elseif action == "toggle" then
      tab.positions[#tab.positions].is_active = false
    elseif action.AdjustPaneSize then
      local args = action.AdjustPaneSize
      local position = tab.positions[#tab.positions]
      if args[1] == "Right" then
        position.width = position.width + args[2]
      end
      if args[1] == "Left" then
        position.width = position.width - args[2]
      end
      if args[1] == "Down" then
        position.height = position.height + args[2]
      end
      if args[1] == "Up" then
        position.height = position.height - args[2]
      end
    end
  end
  function window:gui_window()
    return gui
  end
  function window:get_workspace()
    return self.workspace
  end
  function window:get_title()
    return self.title
  end
  function window:set_title(value)
    self.title = value
  end
  function window:tabs_with_info()
    local result = {}
    for _, tab in ipairs(self.tab_list) do
      result[#result + 1] = { tab = tab, is_active = tab == self.selected }
    end
    return result
  end
  function window:spawn_tab(args)
    local tab = make_tab(self, args.domain.DomainName, args.cwd)
    self.tab_list[#self.tab_list + 1] = tab
    self.selected = tab
    return tab, tab.selected
  end
  window:spawn_tab({ domain = { DomainName = domain }, cwd = cwd })
  return window
end
fake.mux = {
  all_windows = function()
    if connection_window then
      local temporary = connection_window
      connection_window = nil
      return { temporary }
    end
    return windows
  end,
  get_active_workspace = function()
    return active
  end,
  set_active_workspace = function(name)
    active = name
  end,
  get_domain = function(name)
    return {
      is_spawnable = function()
        return name ~= "TermWizTerminalDomain"
      end,
      state = function()
        return attached and "Attached" or "Detached"
      end,
      attach = function()
        operations[#operations + 1] = "attach " .. name
        if name == "ssh:offline" then
          error("offline host")
        end
        attached = true
      end,
      has_any_panes = function()
        return #windows > 0
      end,
    }
  end,
  spawn_window = function(args)
    operations[#operations + 1] = "spawn " .. args.domain.DomainName
    local window = make_window(args.workspace, args.domain.DomainName, args.cwd)
    windows[#windows + 1] = window
    return window.selected, window.selected.selected, window
  end,
}
package.loaded.wezterm = setmetatable(fake, { __index = native })
local recovery = require("sysinit.pkg.recovery")
windows = { make_window("alpha", "local", "/missing"), make_window("beta", "local", "/fixture") }
windows[1].selected.selected:split({ cwd = "/fixture" })
local tab = windows[1].selected
tab.positions[#tab.positions + 1] = {
  left = 20,
  top = 5,
  width = 35,
  height = 12,
  is_floating = true,
  is_active = false,
  pane = make_pane("local", "/fixture", tab),
}
local recovery_opts = {
  state_dir = state_dir,
  socket_path = "/fixture/socket",
  mux_binary = "/fixture/mux",
  mux_config = "/fixture/config",
}
local live_windows = windows
windows = {}
recovery.setup_mux(recovery_opts)
windows = live_windows
assert(not recovery.save(), "the mux saved before mux-startup restored its snapshot")
events["mux-startup"]()
assert(recovery.save(), table.concat(operations, "\n"))
local file = assert(io.open(state_dir .. "/session.json"))
local snapshot = native.json_parse(file:read("*a"))
file:close()
assert(#snapshot.workspaces == 2, "inactive workspace was not saved")
assert(snapshot.workspaces[1].window_states[1].tabs[1].floating.width == 35, "hidden float was not saved")
assert(snapshot.workspaces[1].window_states[1].tabs[1].pane_tree.text == nil, "terminal output was saved")
windows, attached = {}, false
connection_window = make_window("alpha", "TermWizTerminalDomain", "/")
assert(recovery.restore())
assert(
  #windows == 2 and windows[1].selected.positions[1].pane.domain == "local",
  "panes were not restored into the mux's own domain"
)
assert(windows[1].selected.positions[1].pane.cwd == "/home/fixture", "missing CWD did not fall back")
for _ = 1, 3 do
  local queued = timers
  timers = {}
  for _, entry in ipairs(queued) do
    if entry[1] < 1 then
      entry[2]()
    end
  end
end
assert(#windows[1].selected.positions == 3, "floating pane was not restored separately")
local float = windows[1].selected.positions[3]
assert(
  float.is_floating and not float.is_active and float.width == 35 and float.height == 12,
  "hidden float dimensions were not restored"
)
assert(active == "beta" and fake.GLOBAL.workspace_slots.alpha == 2, "active workspace or slots were lost")
assert(recovery.restore() and #windows == 2, "repeated restore duplicated live windows")
assert(recovery.save())
local corrupt = assert(io.open(state_dir .. "/session.json", "w"))
corrupt:write("{")
corrupt:close()
windows, attached = {}, false
assert(recovery.restore() and #windows == 2, "corrupt snapshot did not recover from backup")
local slots_before = fake.GLOBAL.workspace_slots
assert(recovery.fork("alpha", "gamma"), table.concat(operations, "\n"))
assert(
  #windows == 3 and windows[3]:get_workspace() == "gamma",
  "fork did not spawn the copy into a domain that still holds panes"
)
assert(active == "gamma", "fork did not activate the copy")
assert(fake.GLOBAL.workspace_slots == slots_before, "fork replaced the slot table")
assert(not recovery.fork("missing", "delta") and #windows == 3, "fork of an absent session spawned windows")
assert(recovery.save() and recovery.forget("alpha"))
local pruned = assert(io.open(state_dir .. "/session.json"))
for _, workspace in ipairs(native.json_parse(pruned:read("*a")).workspaces) do
  assert(workspace.workspace ~= "alpha", "forget left the snapshot in place")
end
pruned:close()
local fixture_read_dir = fake.read_dir
fake.read_dir = function(path)
  if path:sub(1, #state_dir) == state_dir then
    return native.read_dir(path)
  end
  return fixture_read_dir(path)
end
local function read_snapshot()
  local handle = assert(io.open(state_dir .. "/session.json"))
  local decoded = native.json_parse(handle:read("*a"))
  handle:close()
  return decoded
end
assert(recovery.save())
local recorded = #recovery.history()
assert(recorded >= 1, "a save left no snapshot history")
assert(recovery.save() and #recovery.history() == recorded, "an unchanged save added a history entry")
local before_restart = #read_snapshot().workspaces
windows, attached = {}, false
events["mux-startup"]()
assert(#windows > 0, "a restarted mux did not restore its snapshot on mux-startup")
assert(
  recovery.save() and #read_snapshot().workspaces == before_restart,
  "the snapshot lost sessions after a mux restart"
)
local request = assert(io.open(state_dir .. "/save-request", "w"))
request:close()
local queued = timers
timers = {}
for _, entry in ipairs(queued) do
  if entry[1] == 2 then
    entry[2]()
  end
end
assert(not io.open(state_dir .. "/save-request", "r"), "the mux did not consume a save request")
timers = {}
package.loaded["sysinit.pkg.recovery"] = nil
local reloaded = require("sysinit.pkg.recovery")
reloaded.setup_mux(recovery_opts)
local pending = timers
timers = {}
assert(#pending == 1 and pending[1][1] == 2, "a config reload did not restart the mux save timer")
pending[1][2]()
assert(#timers == 1, "the reloaded save timer did not keep running")
package.loaded["sysinit.pkg.recovery"] = recovery
recovery_opts.scrollback_lines = 50
recovery_opts.agent_resume = { claude = { "claude", "--continue" } }
windows = { make_window("gamma", "local", "/fixture") }
local shell_pane = windows[1].selected.selected
local agent_pane = shell_pane:split({ cwd = "/fixture" })
shell_pane.is_alt_screen_active = function()
  return false
end
shell_pane.get_lines_as_text = function()
  return "old output\n\n"
end
package.loaded["sysinit.pkg.ui.panes"] = {
  facts = function(id)
    return { agent = id == agent_pane.id and "claude" or nil }
  end,
}
assert(recovery.save(), table.concat(operations, "\n"))
local annotated = {}
for _, saved_workspace in ipairs(read_snapshot().workspaces) do
  if saved_workspace.workspace == "gamma" then
    local function walk(node)
      annotated[#annotated + 1] = node
      if node.right then
        walk(node.right)
      end
      if node.bottom then
        walk(node.bottom)
      end
    end
    walk(saved_workspace.window_states[1].tabs[1].pane_tree)
  end
end
local scrollback_node, resume_node
for _, node in ipairs(annotated) do
  scrollback_node = scrollback_node or (node.scrollback and node)
  resume_node = resume_node or (node.resume and node)
end
assert(scrollback_node and scrollback_node.scrollback == "old output", "scrollback was not captured")
assert(resume_node and resume_node.resume == "claude" and not resume_node.scrollback, "the agent pane was not marked")
local newest = assert(io.open(recovery.history()[1].path))
assert(not newest:read("*a"):find("old output", 1, true), "snapshot history kept scrollback")
newest:close()
windows, attached = {}, false
assert(recovery.restore("gamma"), table.concat(operations, "\n"))
local replayed, typed = false, false
for _, position in ipairs(windows[1].selected.positions) do
  replayed = replayed or (position.pane.injected or ""):find("old output", 1, true) ~= nil
  typed = typed or position.pane.sent == "claude --continue"
end
assert(replayed, "the restored shell did not replay its scrollback")
assert(typed, "the agent resume command was not typed without Enter")
recovery_opts.scrollback_lines, recovery_opts.agent_resume = 0, nil
windows, attached = {}, false
local marker = assert(io.open(state_dir .. "/passed", "w"))
marker:write("passed")
marker:close()
return {}
