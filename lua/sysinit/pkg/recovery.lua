local wezterm = require("wezterm")
local file_io = require("resurrect.file_io")
local pane_tree = require("resurrect.pane_tree")
local tab_state = require("resurrect.tab_state")
local M = {}
local settings = {}
local busy = false
local ready = false
local deferred = {}
local read_session
local HISTORY_LIMIT = 20
pane_tree.capture_text = false

local function report(message)
  wezterm.log_warn("session recovery: " .. tostring(message))
end

-- Annotates each pane before its process handle is dropped: an agent pane keeps the
-- agent to resume, any other primary-screen pane keeps its recent scrollback.
local function annotate_tree(node, panes)
  local pane = panes[tostring(node.left) .. ":" .. tostring(node.top)]
  if pane then
    local cwd = node.cwd
    local ok, facts = pcall(function()
      return require("sysinit.pkg.ui.panes").facts(pane:pane_id(), cwd)
    end)
    local agent = ok and facts and facts.agent
    if agent and (settings.agent_resume or {})[agent] then
      node.resume = agent
    elseif (settings.scrollback_lines or 0) > 0 then
      local alt_ok, alt = pcall(function()
        return pane:is_alt_screen_active()
      end)
      local text_ok, text = pcall(function()
        return pane:get_lines_as_text(settings.scrollback_lines)
      end)
      if alt_ok and not alt and text_ok and type(text) == "string" then
        text = text:gsub("%s+$", "")
        node.scrollback = text ~= "" and text or nil
      end
    end
  end
  if node.right then
    annotate_tree(node.right, panes)
  end
  if node.bottom then
    annotate_tree(node.bottom, panes)
  end
end

local function strip_scrollback(node)
  node.scrollback = nil
  if node.right then
    strip_scrollback(node.right)
  end
  if node.bottom then
    strip_scrollback(node.bottom)
  end
end

-- The mux injects saved text into its own panes; a GUI-side restore holds mux-client
-- panes, where inject_output is a no-op, so the restored shell prints the text itself.
-- Resume commands are typed, not run, so nothing starts unreviewed.
local function restore_pane(node)
  local pane = node.pane
  if not pane then
    return
  end
  if type(node.scrollback) == "string" and settings.mode == "mux" then
    pane:inject_output(node.scrollback:gsub("\n", "\r\n") .. "\r\n")
  elseif type(node.scrollback) == "string" then
    local path = settings.state_dir .. "/replay-" .. tostring(pane:pane_id()) .. "-" .. tostring(os.time()) .. ".txt"
    if file_io.write_file(path, node.scrollback .. "\n") then
      pane:send_text(" /bin/cat '" .. path .. "'; /bin/rm -f '" .. path .. "'\r")
    end
  end
  local command = node.resume and (settings.agent_resume or {})[node.resume]
  if type(command) == "table" and #command > 0 then
    pane:send_text(wezterm.shell_join_args(command))
  end
end

local function local_domain(name)
  return name == nil or name == "local" or name == "unix"
end

-- The GUI reaches the persistent mux as its "unix" client domain; inside the mux
-- server the same panes belong to its own "local" domain.
local function local_name()
  return settings.mode == "mux" and "local" or "unix"
end

local function domain_name(name)
  return local_domain(name) and local_name() or name
end

local function clean_tree(node)
  node.pane = nil
  node.process = nil
  node.text = nil
  node.alt_screen_active = false
  if node.right then
    clean_tree(node.right)
  end
  if node.bottom then
    clean_tree(node.bottom)
  end
end

function M.capture()
  local session = {
    version = 1,
    active = wezterm.mux.get_active_workspace(),
    slots = wezterm.GLOBAL.workspace_slots,
    native_workspaces = wezterm.GLOBAL.native_workspaces,
    workspaces = {},
  }
  local grouped = {}
  for _, window in ipairs(wezterm.mux.all_windows()) do
    local name = window:get_workspace()
    local workspace = grouped[name]
    if not workspace then
      workspace = { workspace = name, window_states = {} }
      grouped[name] = workspace
      session.workspaces[#session.workspaces + 1] = workspace
    end
    local saved_window = { title = window:get_title(), tabs = {} }
    for _, info in ipairs(window:tabs_with_info()) do
      local tab = info.tab
      local tiled, floating = {}, nil
      for _, position in ipairs(tab:panes_with_info()) do
        if position.is_floating then
          local cwd = position.pane:get_current_working_dir()
          floating = {
            cwd = cwd and cwd.file_path or nil,
            domain = position.pane:get_domain_name(),
            width = position.width,
            height = position.height,
            visible = position.is_active,
          }
        else
          tiled[#tiled + 1] = position
        end
      end
      if #tiled > 0 then
        local zoomed = tiled[1].is_zoomed
        local by_position = {}
        for _, position in ipairs(tiled) do
          by_position[tostring(position.left) .. ":" .. tostring(position.top)] = position.pane
        end
        local tree = pane_tree.create_pane_tree(tiled)
        annotate_tree(tree, by_position)
        clean_tree(tree)
        saved_window.tabs[#saved_window.tabs + 1] = {
          title = tab:get_title(),
          is_active = info.is_active,
          pane_tree = tree,
          floating = floating,
          is_zoomed = zoomed,
        }
        saved_window.size = tab:get_size()
      end
    end
    if #saved_window.tabs > 0 then
      workspace.window_states[#workspace.window_states + 1] = saved_window
    end
  end
  return session
end

local function write_snapshot(path, state)
  local staged = path .. "." .. wezterm.procinfo.pid()
  assert(file_io.write_file(staged, wezterm.json_encode(state)))
  assert(file_io.move_file(staged, path))
end

local function history_dir()
  return settings.state_dir .. "/history"
end

function M.history()
  local entries = {}
  local ok, paths = pcall(wezterm.read_dir, history_dir())
  for _, path in ipairs(ok and paths or {}) do
    local stamp = path:match("(%d+T%d+)%.json$")
    if stamp then
      entries[#entries + 1] = { path = path, stamp = stamp }
    end
  end
  table.sort(entries, function(a, b)
    return a.stamp > b.stamp
  end)
  return entries
end

-- Keeps a bounded trail of distinct snapshots, so one bad save cannot erase the last good layout.
local function record_history(encoded)
  local entries = M.history()
  if entries[1] then
    local file = io.open(entries[1].path, "r")
    local last = file and file:read("*a")
    if file then
      file:close()
    end
    if last == encoded then
      return
    end
  end
  wezterm.run_child_process({ "mkdir", "-p", history_dir() })
  local path = history_dir() .. "/" .. os.date("%Y%m%dT%H%M%S") .. ".json"
  assert(file_io.write_file(path, encoded))
  for index = HISTORY_LIMIT, #entries do
    os.remove(entries[index].path)
  end
end

function M.save()
  if busy or not ready then
    return false
  end
  local ok, err = pcall(function()
    local state = M.capture()
    local names = {}
    for _, workspace in ipairs(state.workspaces) do
      names[workspace.workspace] = true
    end
    for name, workspace in pairs(deferred) do
      if not names[name] then
        state.workspaces[#state.workspaces + 1] = workspace
      end
    end
    if #state.workspaces == 0 then
      return
    end
    local path = settings.state_dir .. "/session.json"
    local previous = read_session(path)
    if previous then
      write_snapshot(path .. ".bak", previous)
    end
    write_snapshot(path, state)
    local light = wezterm.json_parse(wezterm.json_encode(state))
    for _, workspace in ipairs(light.workspaces) do
      for _, saved_window in ipairs(workspace.window_states) do
        for _, saved_tab in ipairs(saved_window.tabs) do
          strip_scrollback(saved_tab.pane_tree)
        end
      end
    end
    record_history(wezterm.json_encode(light))
  end)
  if not ok then
    report(err)
  end
  return ok
end

local function valid_tree(node)
  if type(node) ~= "table" or type(node.width) ~= "number" or type(node.height) ~= "number" then
    return false
  end
  if node.cwd ~= nil and type(node.cwd) ~= "string" then
    return false
  end
  if node.domain ~= nil and type(node.domain) ~= "string" then
    return false
  end
  return (node.right == nil or valid_tree(node.right)) and (node.bottom == nil or valid_tree(node.bottom))
end

read_session = function(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, state = pcall(wezterm.json_parse, text)
  if not ok or type(state) ~= "table" or state.version ~= 1 or type(state.workspaces) ~= "table" then
    return nil
  end
  for _, workspace in ipairs(state.workspaces) do
    if
      type(workspace) ~= "table"
      or type(workspace.workspace) ~= "string"
      or type(workspace.window_states) ~= "table"
    then
      return nil
    end
    for _, window in ipairs(workspace.window_states) do
      if type(window) ~= "table" or type(window.tabs) ~= "table" then
        return nil
      end
      for _, tab in ipairs(window.tabs) do
        if type(tab) ~= "table" or not valid_tree(tab.pane_tree) then
          return nil
        end
        if tab.floating and (type(tab.floating) ~= "table" or type(tab.floating.domain) ~= "string") then
          return nil
        end
      end
    end
  end
  return state
end

local function prepare_tree(node, unavailable)
  node.domain = domain_name(node.domain)
  if unavailable[node.domain] then
    return false
  end
  if local_domain(node.domain) and node.cwd and node.cwd ~= "" then
    local ok, exists = pcall(wezterm.read_dir, node.cwd)
    if not ok or not exists then
      report("directory is unavailable: " .. node.cwd)
      node.cwd = wezterm.home_dir
    end
  end
  return (not node.right or prepare_tree(node.right, unavailable))
    and (not node.bottom or prepare_tree(node.bottom, unavailable))
end

local function restore_float(tab, saved)
  if not saved then
    return
  end
  local pane = tab:active_pane()
  pane:spawn_floating_pane({
    cwd = saved.cwd,
    domain = { DomainName = domain_name(saved.domain) },
    width = saved.width,
    height = saved.height,
    visible = saved.visible,
  })
  if not saved.visible then
    pane:activate()
  end
end

-- A fresh restore spawns into domains that still hold panes; a fork needs that.
local function restore_state(state, selected_workspace, fresh)
  if type(selected_workspace) == "string" then
    local selected = {}
    for _, workspace in ipairs(state.workspaces) do
      if workspace.workspace == selected_workspace then
        selected[#selected + 1] = workspace
      end
    end
    state.workspaces = selected
    state.active = selected_workspace
  end
  busy = true
  if type(selected_workspace) ~= "string" then
    deferred = {}
  end
  local unavailable, retained = {}, {}
  local domains = { [local_name()] = true }
  for _, workspace in ipairs(state.workspaces) do
    for _, window in ipairs(workspace.window_states) do
      for _, tab in ipairs(window.tabs) do
        if tab.floating then
          domains[domain_name(tab.floating.domain)] = true
        end
        pane_tree.fold(tab.pane_tree, nil, function(_, node)
          domains[domain_name(node.domain)] = true
        end)
      end
    end
  end
  for name in pairs(domains) do
    local ok, err = pcall(function()
      local domain = assert(wezterm.mux.get_domain(name), "domain is no longer configured: " .. name)
      if domain:state() ~= "Attached" then
        domain:attach()
      end
      retained[name] = domain:has_any_panes()
    end)
    if not ok then
      unavailable[name] = true
      report(err)
    end
  end
  local live = {}
  for _, window in ipairs(wezterm.mux.all_windows()) do
    for _, info in ipairs(window:tabs_with_info()) do
      local pane = info.tab:active_pane()
      local domain = pane and wezterm.mux.get_domain(pane:get_domain_name())
      if domain and domain:is_spawnable() then
        live[window:get_workspace()] = true
        break
      end
    end
  end
  local ok, err = pcall(function()
    for _, workspace in ipairs(state.workspaces) do
      if not live[workspace.workspace] then
        local restorable = true
        for _, window in ipairs(workspace.window_states) do
          for _, tab in ipairs(window.tabs) do
            restorable = prepare_tree(tab.pane_tree, unavailable) and restorable
            if tab.floating then
              tab.floating.domain = domain_name(tab.floating.domain)
              if unavailable[tab.floating.domain] then
                restorable = false
              elseif local_domain(tab.floating.domain) and tab.floating.cwd then
                local ok = pcall(wezterm.read_dir, tab.floating.cwd)
                if not ok then
                  tab.floating.cwd = wezterm.home_dir
                end
              end
            end
          end
        end
        if not restorable then
          deferred[workspace.workspace] = workspace
        else
          deferred[workspace.workspace] = nil
          for _, saved_window in ipairs(workspace.window_states) do
            local window, active_tab
            for _, saved_tab in ipairs(saved_window.tabs) do
              local root = saved_tab.pane_tree
              local name = domain_name(root.domain)
              if (fresh or not retained[name]) and prepare_tree(root, unavailable) then
                local tab, pane
                if window then
                  tab, pane = window:spawn_tab({ cwd = root.cwd, domain = { DomainName = name } })
                else
                  tab, pane, window = wezterm.mux.spawn_window({
                    workspace = workspace.workspace,
                    width = saved_window.size and saved_window.size.cols,
                    height = saved_window.size and saved_window.size.rows,
                    cwd = root.cwd,
                    domain = { DomainName = name },
                  })
                  window:set_title(saved_window.title or "")
                end
                tab_state.restore_tab(tab, saved_tab, { pane = pane, relative = true, on_pane_restore = restore_pane })
                restore_float(tab, saved_tab.floating)
                if saved_tab.is_zoomed then
                  tab:set_zoomed(true)
                end
                if saved_tab.is_active then
                  active_tab = tab
                end
              end
            end
            if active_tab then
              active_tab:activate()
            end
          end
        end
      end
    end
    if type(state.slots) == "table" then
      wezterm.GLOBAL.workspace_slots = state.slots
    end
    if type(state.native_workspaces) == "table" then
      wezterm.GLOBAL.native_workspaces = state.native_workspaces
    end
    for _, window in ipairs(wezterm.mux.all_windows()) do
      if window:get_workspace() == state.active then
        wezterm.mux.set_active_workspace(state.active)
        break
      end
    end
  end)
  busy = false
  if not ok then
    report(err)
  end
  return ok
end

function M.restore(selected_workspace)
  local path = settings.state_dir .. "/session.json"
  local state = read_session(path) or read_session(path .. ".bak")
  if not state then
    return false
  end
  return restore_state(state, selected_workspace, false)
end

function M.fork(source, target)
  local state = M.capture()
  local selected
  for _, workspace in ipairs(state.workspaces) do
    if workspace.workspace == source then
      workspace.workspace = target
      selected = workspace
    end
  end
  if not selected then
    return false
  end
  return restore_state({ version = 1, active = target, workspaces = { selected } }, target, true)
end

function M.forget(name)
  local path = settings.state_dir .. "/session.json"
  local state = read_session(path)
  if not state then
    return false
  end
  local kept = {}
  for _, workspace in ipairs(state.workspaces) do
    if workspace.workspace ~= name then
      kept[#kept + 1] = workspace
    end
  end
  state.workspaces = kept
  deferred[name] = nil
  local ok, err = pcall(write_snapshot, path, state)
  if not ok then
    report(err)
  end
  return ok
end

-- The mux server owns snapshots: it restores on startup, before any GUI attaches,
-- and saves on a timer. Timers only run once started from an event in the mux.
function M.setup_mux(opts)
  settings = opts
  settings.mode = "mux"
  wezterm.run_child_process({ "mkdir", "-p", settings.state_dir })
  wezterm.on("mux-startup", function()
    M.restore()
    ready = true
    local request = settings.state_dir .. "/save-request"
    local elapsed = 0
    local function tick()
      elapsed = elapsed + 2
      local heartbeat = io.open(settings.state_dir .. "/mux-heartbeat", "w")
      if heartbeat then
        heartbeat:write(tostring(os.time()))
        heartbeat:close()
      end
      local requested = io.open(request, "r")
      if requested then
        requested:close()
        os.remove(request)
      end
      if requested or elapsed >= (settings.interval or 60) then
        elapsed = 0
        M.save()
      end
      wezterm.time.call_after(2, tick)
    end
    wezterm.time.call_after(2, tick)
  end)
end

function M.setup(config, opts)
  settings = opts
  local made = wezterm.run_child_process({ "mkdir", "-p", settings.state_dir })
  assert(made, "cannot create the session recovery directory")
  config.unix_domains = {
    {
      name = "unix",
      socket_path = settings.socket_path,
      serve_command = { settings.mux_binary, "--config-file", settings.mux_config, "--daemonize" },
    },
  }
  config.default_domain = "unix"
  -- Restore before WezTerm creates a fallback pane in a newly started mux.
  config.default_gui_startup_args = { "start" }
  -- A mux started before mux-side recovery existed never runs mux-startup again, so
  -- the GUI keeps saving until the mux reports a fresh heartbeat.
  local function fallback_save()
    local heartbeat = io.open(settings.state_dir .. "/mux-heartbeat", "r")
    local beat = heartbeat and tonumber(heartbeat:read("*l"))
    if heartbeat then
      heartbeat:close()
    end
    if beat and os.time() - beat < 10 then
      return
    end
    local ok, windows = pcall(wezterm.mux.all_windows)
    if ok and #windows > 0 then
      ready = true
      M.save()
    end
  end
  wezterm.on("window-focus-changed", fallback_save)
  local function periodic()
    fallback_save()
    wezterm.time.call_after(settings.interval or 60, periodic)
  end
  wezterm.time.call_after(settings.interval or 60, periodic)
  wezterm.on("augment-command-palette", function()
    return {
      {
        brief = "Session: save recovery snapshot",
        action = wezterm.action_callback(function(window)
          local request = io.open(settings.state_dir .. "/save-request", "w")
          if request then
            request:close()
            window:toast_notification("Session", "snapshot requested from the mux", nil, 3000)
          end
        end),
      },
      {
        brief = "Session: restore last session",
        action = wezterm.action_callback(function()
          M.restore()
        end),
      },
      {
        brief = "Session: restore saved workspace",
        action = wezterm.action_callback(function(window, pane)
          local path = settings.state_dir .. "/session.json"
          local state = read_session(path) or read_session(path .. ".bak")
          local choices = {}
          for _, workspace in ipairs(state and state.workspaces or {}) do
            choices[#choices + 1] = { id = workspace.workspace, label = workspace.workspace }
          end
          window:perform_action(
            wezterm.action.InputSelector({
              title = "Restore saved workspace",
              choices = choices,
              action = wezterm.action_callback(function(_, _, name)
                if name then
                  M.restore(name)
                end
              end),
            }),
            pane
          )
        end),
      },
      {
        brief = "Session: restore from snapshot history",
        action = wezterm.action_callback(function(window, pane)
          local choices = {}
          for _, entry in ipairs(M.history()) do
            local state = read_session(entry.path)
            if state then
              local names = {}
              for _, workspace in ipairs(state.workspaces) do
                names[#names + 1] = workspace.workspace
              end
              local y, mo, d, h, mi = entry.stamp:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)")
              choices[#choices + 1] = {
                id = entry.path,
                label = string.format("%s-%s-%s %s:%s  %s", y, mo, d, h, mi, table.concat(names, ", ")),
              }
            end
          end
          if #choices == 0 then
            window:toast_notification("Session", "no snapshot history yet", nil, 3000)
            return
          end
          window:perform_action(
            wezterm.action.InputSelector({
              title = "Restore snapshot (live sessions are kept)",
              choices = choices,
              action = wezterm.action_callback(function(_, _, path)
                local state = path and read_session(path)
                if state then
                  state.slots, state.native_workspaces, state.active = nil, nil, nil
                  restore_state(state, nil, false)
                end
              end),
            }),
            pane
          )
        end),
      },
      {
        brief = "Session: fork current",
        action = wezterm.action_callback(function(window, pane)
          local source = window:active_workspace()
          window:perform_action(
            wezterm.action.PromptInputLine({
              description = "Fork " .. source .. " as",
              action = wezterm.action_callback(function(inner, _, line)
                local target = line and line:match("^%s*(.-)%s*$") or ""
                if target == "" then
                  return
                end
                for _, live in ipairs(wezterm.mux.get_workspace_names()) do
                  if live == target then
                    inner:toast_notification("Session", target .. " already exists", nil, 3000)
                    return
                  end
                end
                M.fork(source, target)
              end),
            }),
            pane
          )
        end),
      },
      {
        brief = "Session: delete saved snapshot",
        action = wezterm.action_callback(function(window, pane)
          local live = {}
          for _, name in ipairs(wezterm.mux.get_workspace_names()) do
            live[name] = true
          end
          local state = read_session(settings.state_dir .. "/session.json")
          local choices = {}
          for _, workspace in ipairs(state and state.workspaces or {}) do
            if not live[workspace.workspace] then
              choices[#choices + 1] = { id = workspace.workspace, label = workspace.workspace }
            end
          end
          if #choices == 0 then
            window:toast_notification("Session", "no saved snapshot outside the live sessions", nil, 3000)
            return
          end
          window:perform_action(
            wezterm.action.InputSelector({
              title = "Delete saved snapshot",
              choices = choices,
              action = wezterm.action_callback(function(_, _, name)
                if name then
                  M.forget(name)
                end
              end),
            }),
            pane
          )
        end),
      },
    }
  end)
end

return M
