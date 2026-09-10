local wezterm = require("wezterm")
local command = require("sysinit.pkg.command")
local utils = require("sysinit.pkg.utils")
local actions = require("sysinit.pkg.ui.actions")
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
  return settings().providers or {}
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

function M.open(win, pane, key)
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
  local descriptor, describe_error = invoke(provider, "picker.describe")
  if type(descriptor) ~= "table" or not text(descriptor.title) or not text(descriptor.icon) then
    report(win, describe_error or "Provider returned an invalid description")
    return
  end
  local listed, list_error = invoke(provider, "picker.list")
  if type(listed) ~= "table" or not array(listed.items) then
    report(win, list_error or "Provider returned no item list")
    return
  end
  local choices, known = {}, {}
  for _, item in ipairs(listed.items) do
    if not valid_item(item) or known[item.id] then
      report(win, "Provider returned an invalid or duplicate item")
      return
    end
    choices[#choices + 1] = { id = item.id, label = M.label(item, descriptor) }
    known[item.id] = true
  end
  if #choices == 0 then
    report(win, "No results from " .. tostring(descriptor.title))
    return
  end
  win:perform_action(
    wezterm.action.InputSelector({
      title = descriptor.title,
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(inner_win, inner_pane, id)
        if not id or not known[id] then
          return
        end
        local plan, err = invoke(provider, "picker.open", id)
        if not plan then
          report(inner_win, err)
          return
        end
        local spawn, spawn_error = M.spawn(plan)
        if not spawn then
          report(inner_win, spawn_error)
          return
        end
        local workspace = tostring(plan.label or id)
        actions.switch_to_workspace(inner_win, inner_pane, workspace, spawn)
      end),
    }),
    pane
  )
end

return M
