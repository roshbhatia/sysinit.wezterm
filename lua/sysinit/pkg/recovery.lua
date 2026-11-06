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
pane_tree.capture_text = false

local function report(message)
  wezterm.log_warn("session recovery: " .. tostring(message))
end

local function local_domain(name)
  return name == nil or name == "local" or name == "unix"
end

local function domain_name(name)
  return local_domain(name) and "unix" or name
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
        local tree = pane_tree.create_pane_tree(tiled)
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
    if read_session(path) then
      assert(file_io.move_file(path, path .. ".bak"))
    end
    assert(file_io.write_file(path, wezterm.json_encode(state)))
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

function M.restore(selected_workspace)
  local path = settings.state_dir .. "/session.json"
  local state = read_session(path) or read_session(path .. ".bak")
  if not state then
    return false
  end
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
  local domains = { unix = true }
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
    live[window:get_workspace()] = true
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
              if not retained[name] and prepare_tree(root, unavailable) then
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
                tab_state.restore_tab(tab, saved_tab, { pane = pane, relative = true })
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
  local explicit = false
  local handled = false
  local has_mux, windows = pcall(wezterm.mux.all_windows)
  ready = has_mux and #windows > 0
  wezterm.on("gui-startup", function(command)
    handled = true
    explicit = command ~= nil
    if not explicit then
      M.restore()
    end
    ready = true
  end)
  wezterm.on("gui-attached", function()
    if not handled and not explicit then
      M.restore()
    end
    handled = true
    ready = true
  end)
  wezterm.on("window-focus-changed", function()
    M.save()
  end)
  wezterm.on("pane-focus-changed", function()
    M.save()
  end)
  local function periodic()
    M.save()
    wezterm.time.call_after(settings.interval or 60, periodic)
  end
  wezterm.time.call_after(settings.interval or 60, periodic)
  wezterm.on("augment-command-palette", function()
    return {
      {
        brief = "Session: save recovery snapshot",
        action = wezterm.action_callback(function()
          M.save()
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
    }
  end)
end

return M
