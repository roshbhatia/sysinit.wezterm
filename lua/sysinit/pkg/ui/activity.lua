local M = {}

local transports = { ssh = true, mosh = true, ["mosh-client"] = true, zmx = true, tmux = true }
local shells = { zsh = true, bash = true, fish = true, sh = true, nu = true }

local function matches(text, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if text:lower():match(pattern) then
      return true
    end
  end
  return false
end

function M.process(pane, agents)
  if next(agents) == nil then
    return nil, nil, false
  end
  local ok, proc = pcall(function()
    return pane:get_foreground_process_info()
  end)
  if not ok or not proc then
    return nil, nil, false
  end
  local opaque = false
  local function visit(node)
    local exe = node.executable or node.name or ""
    local base = exe:match("([^/]+)$") or exe
    if transports[base] then
      opaque = true
      return
    end
    for name, spec in pairs(agents) do
      if matches(exe, spec.executable_patterns) or matches(table.concat(node.argv or {}, " "), spec.argv_patterns) then
        return name, tostring(node.pid or "") .. ":" .. exe
      end
    end
    for _, child in pairs(node.children or {}) do
      local name, owner = visit(child)
      if name then
        return name, owner
      end
    end
  end
  local name, owner = visit(proc)
  local executable = proc.executable or proc.name or ""
  local base = executable:match("([^/]+)$") or executable
  local shell = shells[base] and next(proc.children or {}) == nil
  return name, owner, not opaque and (name ~= nil or shell == true)
end

function M.screen(agent, text, title, spec)
  local lines = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    if line:match("%S") then
      lines[#lines + 1] = line:match("^%s*(.-)%s*$")
    end
  end
  local start = math.max(1, #lines - 11)
  for i = start, #lines do
    if lines[i]:match("^›") or lines[i]:match("^❯") then
      if not lines[i]:match("^[^%s]+%s*%d+%.") then
        start = i
      end
    end
  end
  local tail = table.concat(lines, "\n", start):lower()
  if tail:find("q to quit", 1, true) and (tail:find("to scroll", 1, true) or tail:find("pgup/pgdn", 1, true)) then
    return nil, "transcript"
  end
  if agent == "codex" or agent == "claude" then
    if (title or ""):find("Action Required", 1, true) then
      return "waiting", "title"
    end
    for i = start, #lines do
      local line = lines[i]
      local lower = line:lower()
      if
        lower:match("^press enter to confirm")
        or lower:match("^enter to confirm")
        or lower:match("^enter to submit")
        or (lower:match("^esc to cancel") and tail:find("yes", 1, true))
      then
        return "waiting", "screen"
      end
    end
    for i = start, #lines do
      local line = lines[i]
      if agent == "codex" and line:match("^• .+%(%d.-esc to interrupt%)") then
        return "working", "screen"
      end
      if agent == "claude" and line:find("esc to interrupt", 1, true) then
        for _, marker in ipairs({ "✻", "✽", "✶", "✳", "✢", "·" }) do
          if line:sub(1, #marker) == marker then
            return "working", "screen"
          end
        end
      end
    end
    for _, spinner in ipairs({ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }) do
      if (title or ""):sub(1, #spinner) == spinner then
        return "working", "title"
      end
    end
    local last = lines[#lines] or ""
    if last == "›" or last == "❯" or last == "› Ask Codex to do anything" then
      return "idle", "screen"
    end
    return nil
  end
  for _, status in ipairs({ "waiting", "working", "idle" }) do
    if matches(tail, (spec.status_patterns or {})[status]) then
      return status, "screen"
    end
  end
  return nil
end

return M
