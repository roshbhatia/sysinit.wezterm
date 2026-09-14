local wezterm = require("wezterm")
local command = require("sysinit.pkg.command")
local utils = require("sysinit.pkg.utils")
local actions = require("sysinit.pkg.ui.actions")
local catalog = require("sysinit.pkg.ui.catalog")
local sessions = require("sysinit.pkg.ui.sessions")
local M = {}

local function array(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  return count == #value
end

local function text(value)
  return type(value) == "string" and not value:find("[%c]")
end

local function valid_item(item)
  if type(item) ~= "table" or not text(item.id) or item.id == "" or not array(item.segments) then
    return false
  end
  for _, segment in ipairs(item.segments) do
    if type(segment) ~= "table" or type(segment.text) ~= "string" then
      return false
    end
    if segment.role ~= "name" and segment.role ~= "path" and segment.role ~= "detail" then
      return false
    end
  end
  return #item.segments > 0
end

local function settings()
  return (utils.load_json_file(utils.get_config_path("config.json")) or {}).picker or {}
end

function M.providers()
  local providers = { { name = "wezterm", key = "!", native = true } }
  for _, provider in ipairs(settings().providers or {}) do
    providers[#providers + 1] = provider
  end
  return providers
end

function M.prefetch()
  for _, provider in ipairs(settings().providers or {}) do
    catalog.load(settings().command or {}, provider.manifest)
  end
end

function M.cancel(win)
  wezterm.GLOBAL["picker_view:" .. tostring(win:window_id())] = nil
end

local function invoke(provider, capability, id)
  local argv = {}
  for _, value in ipairs(settings().command or {}) do
    argv[#argv + 1] = value
  end
  argv[#argv + 1] = provider.manifest
  argv[#argv + 1] = capability
  return command.json(argv, id)
end

local function report(win, message)
  wezterm.log_error(message)
  win:toast_notification("WezTerm", message, nil, 5000)
end

function M.spawn(plan)
  if type(plan) ~= "table" or plan.kind ~= "spawn" then
    return nil, "Unsupported picker action"
  end
  if not text(plan.cwd) or plan.cwd:sub(1, 1) ~= "/" then
    return nil, "Picker action has no absolute directory"
  end
  if not array(plan.command) or type(plan.environment) ~= "table" or (plan.label ~= nil and not text(plan.label)) then
    return nil, "Picker action has invalid process fields"
  end
  for _, arg in ipairs(plan.command) do
    if type(arg) ~= "string" or arg:find("%z") then
      return nil, "Picker command has a non-string argument"
    end
  end
  for key, value in pairs(plan.environment) do
    if not text(key) or key == "" or key:find("=", 1, true) or type(value) ~= "string" or value:find("%z") then
      return nil, "Picker action has an invalid environment"
    end
  end
  return {
    cwd = plan.cwd,
    domain = { DomainName = "local" },
    args = #plan.command > 0 and plan.command or nil,
    set_environment_variables = plan.environment,
  }
end

function M.label(item, descriptor)
  local parts = {}
  local icon = (wezterm.nerdfonts or {})[descriptor.icon] or ""
  if icon ~= "" then
    parts[#parts + 1] = { Text = icon .. "  " }
  end
  for index, segment in ipairs(item.segments or {}) do
    if index > 1 then
      parts[#parts + 1] = { Text = "  " }
    end
    parts[#parts + 1] = "ResetAttributes"
    if segment.role == "name" then
      parts[#parts + 1] = { Attribute = { Intensity = "Bold" } }
    elseif segment.role == "detail" then
      parts[#parts + 1] = { Attribute = { Intensity = "Half" } }
    end
    parts[#parts + 1] = { Text = tostring(segment.text or ""):gsub("[%c]", " ") }
  end
  parts[#parts + 1] = "ResetAttributes"
  return wezterm.format(parts)
end

local function native_catalog()
  local registered = wezterm.GLOBAL.native_workspaces or {}
  local items = {}
  for _, name in ipairs(sessions.active_names()) do
    if name == "default" or registered[name] then
      items[#items + 1] = { id = name, segments = { { text = name, role = "name" } } }
    end
  end
  table.sort(items, function(a, b)
    return a.id < b.id
  end)
  return {
    descriptor = { title = "WezTerm sessions", icon = "", create = { label = "New session", prompt = "Session name" } },
    listed = { items = items },
    can_create = true,
  }
end

local function launch(win, pane, provider, capability, name)
  if provider.native then
    if capability == "picker.create" then
      for _, existing in ipairs(sessions.active_names()) do
        if existing == name then
          report(win, "Session already exists: " .. name)
          return
        end
      end
      local registered = wezterm.GLOBAL.native_workspaces or {}
      registered[name] = true
      wezterm.GLOBAL.native_workspaces = registered
    end
    actions.switch_to_workspace(win, pane, name, { cwd = utils.get_home_dir(), domain = { DomainName = "local" } })
    return
  end
  local plan, err = invoke(provider, capability, name)
  if not plan then
    report(win, err)
    return
  end
  local spawn, spawn_error = M.spawn(plan)
  if not spawn then
    report(win, spawn_error)
    return
  end
  if capability == "picker.create" then
    local config = utils.load_json_file(utils.get_config_path("config.json")) or {}
    spawn.set_environment_variables.WEZTERM_PICKER_SHELL =
      wezterm.json_encode(config.shell or { os.getenv("SHELL") or "/bin/sh" })
  end
  actions.switch_to_workspace(win, pane, tostring(plan.label or name), spawn)
end

function M.open(win, pane, key, before_show)
  local provider
  for _, candidate in ipairs(M.providers()) do
    if candidate.key == key then
      provider = candidate
      break
    end
  end
  if not provider then
    report(win, "No provider registered for " .. tostring(key))
    return
  end
  local target = win:mux_window():active_pane()
  if not target then
    return
  end
  if before_show and before_show() == false then
    return
  end
  local state_key = "picker_view:" .. tostring(win:window_id())
  local token = (wezterm.GLOBAL.picker_sequence or 0) + 1
  wezterm.GLOBAL.picker_sequence = token
  wezterm.GLOBAL[state_key] = token
  local loading = false
  local overlay_id
  local function failed(message)
    loading = false
    report(win, message)
    win:perform_action(
      wezterm.action.InputSelector({
        title = "Unable to load " .. provider.name,
        description = message .. "  Esc quit",
        choices = {},
        action = wezterm.action_callback(function()
          if wezterm.GLOBAL[state_key] == token then
            wezterm.GLOBAL[state_key] = nil
          end
        end),
      }),
      target
    )
  end
  local function show(result, err)
    if wezterm.GLOBAL[state_key] ~= token then
      return
    end
    if overlay_id and win:active_pane():pane_id() ~= overlay_id then
      M.cancel(win)
      return
    end
    local current = win:mux_window():active_pane()
    if not current or current:pane_id() ~= target:pane_id() then
      wezterm.GLOBAL[state_key] = nil
      return
    end
    loading = false
    if not result then
      failed(err or "Provider returned no catalog")
      return
    end
    local descriptor, listed = result.descriptor, result.listed
    if type(descriptor) ~= "table" or not text(descriptor.title) or not text(descriptor.icon) then
      failed("Provider returned an invalid description")
      return
    end
    if type(listed) ~= "table" or not array(listed.items) then
      failed("Provider returned no item list")
      return
    end
    local choices, known = {}, {}
    for _, item in ipairs(listed.items) do
      if not valid_item(item) or known[item.id] then
        failed("Provider returned an invalid or duplicate item")
        return
      end
      choices[#choices + 1] = { id = item.id, label = M.label(item, descriptor) }
      known[item.id] = true
    end
    local create_id = "sysinit:create"
    while known[create_id] do
      create_id = create_id .. ":"
    end
    local creation = type(descriptor.create) == "table" and descriptor.create or {}
    if
      (creation.label ~= nil and not text(creation.label)) or (creation.prompt ~= nil and not text(creation.prompt))
    then
      failed("Provider returned invalid creation labels")
      return
    end
    if result.can_create then
      choices[#choices + 1] = { id = create_id, label = creation.label or "New session" }
    end
    if #choices == 0 then
      choices[1] = { id = "sysinit:empty", label = "No sessions" }
    end
    win:perform_action(
      wezterm.action.InputSelector({
        title = descriptor.title,
        fuzzy = true,
        choices = choices,
        action = wezterm.action_callback(function(inner_win, inner_pane, id)
          if wezterm.GLOBAL[state_key] ~= token then
            return
          end
          wezterm.GLOBAL[state_key] = nil
          if not id then
            return
          end
          if result.can_create and id == create_id then
            inner_win:perform_action(
              wezterm.action.PromptInputLine({
                description = creation.prompt or "Session name",
                action = wezterm.action_callback(function(create_win, create_pane, name)
                  if name == nil then
                    return
                  end
                  name = name:match("^%s*(.-)%s*$")
                  if name == "" or not text(name) then
                    report(create_win, "Enter a session name")
                    return
                  end
                  for _, existing in ipairs(sessions.active_names()) do
                    if existing == name then
                      report(create_win, "Session already exists: " .. name)
                      return
                    end
                  end
                  launch(create_win, create_pane, provider, "picker.create", name)
                end),
              }),
              inner_pane
            )
          elseif known[id] then
            launch(inner_win, inner_pane, provider, "picker.open", id)
          end
        end),
      }),
      target
    )
  end
  if provider.native then
    show(native_catalog())
    return
  end
  local runner = settings().command or {}
  local cached = catalog.peek(runner, provider.manifest)
  if cached then
    show(cached)
    catalog.load(runner, provider.manifest)
    return
  end
  loading = true
  win:perform_action(
    wezterm.action.InputSelector({
      title = "Loading " .. provider.name,
      choices = {},
      alphabet = "",
      fuzzy = false,
      action = wezterm.action_callback(function()
        if loading and wezterm.GLOBAL[state_key] == token then
          wezterm.GLOBAL[state_key] = nil
        end
      end),
    }),
    target
  )
  overlay_id = win:active_pane():pane_id()
  catalog.load(runner, provider.manifest, show)
end

return M
