local wezterm = require("wezterm")
local utils = require("sysinit.pkg.utils")
local activity = require("sysinit.pkg.ui.activity")

local M = {}

M.state_rank = {
  waiting = 4,
  working = 3,
  done = 2,
  idle = 1,
  unknown = 0,
}

function M.pane_domain(p)
  local ok, name = pcall(function()
    return p:get_domain_name()
  end)
  if not ok or type(name) ~= "string" then
    return ""
  end
  return name
end

function M.pane_repo(p)
  local ok, repo, cwd = pcall(function()
    local url = p:get_current_working_dir()
    if not url then
      return "", ""
    end
    local path
    if type(url) == "string" then
      path = url:gsub("^file://[^/]*", "")
    else
      path = url.file_path
    end
    if not path or path == "" then
      return "", ""
    end
    path = path:gsub("/+$", "")
    return path:match("([^/]+)$") or "", path
  end)
  if not ok then
    return "", ""
  end
  return repo or "", cwd or ""
end

function M.read_pane_record(pane_id)
  local path = utils.state_path("agentPanes", "agents/panes") .. "/" .. tostring(pane_id) .. ".json"
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  if not ok or type(data) ~= "table" then
    return nil
  end
  local repo_count = 0
  if type(data.repos) == "table" then
    repo_count = #data.repos
  end

  return {
    session = type(data.session) == "string" and data.session or "",
    repo = type(data.repo) == "string" and data.repo or "",
    branch = type(data.branch) == "string" and data.branch ~= "" and data.branch or nil,
    dirty = data.dirty == true,
    repo_count = repo_count,
    worktree = type(data.worktree) == "string" and data.worktree ~= "" and data.worktree or nil,
    status = type(data.status) == "string" and M.state_rank[data.status] and data.status or nil,
    reason = type(data.reason) == "string" and data.reason or "",
    since = tonumber(data.since),
    agent = type(data.agent) == "string" and data.agent or "",
  }
end

local agents = {}
local history = {}

function M.latest(id)
  return history[id] and history[id].status
end

function M.configure(specs)
  agents = specs or {}
  history = {}
end

function M.forget_missing(present)
  for id in pairs(history) do
    if not present[id] then
      history[id] = nil
    end
  end
end

function M.agent_state(p, deck_states, record, now)
  now = now or os.time()
  local id = p.pane_id and p:pane_id() or p
  local previous = history[id] or {}
  local status, reason, since, agent, source
  local uv = p:get_user_vars()
  local raw = uv and uv.agent_state
  if raw and raw ~= "" then
    local s, r, ts, a = raw:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if s and M.state_rank[s] then
      status, reason, since, agent, source = s, r, tonumber(ts), a, "uservar"
    end
  end
  if record == nil then
    record = M.read_pane_record(id)
  end
  if record and record.status and (since == nil or (record.since or 0) > since) then
    status, reason, since, agent, source = record.status, record.reason, record.since, record.agent, "record"
  end
  local token = table.concat({ agent or "", status or "", tostring(since or ""), reason or "" }, "|")
  local live_agent, owner, observable = activity.process(p, agents)
  if observable and not live_agent then
    history[id] = { rejected = token, owner = false }
    return nil
  end
  if previous.owner ~= nil and owner and owner ~= previous.owner then
    previous = { rejected = previous.token or previous.rejected }
  end
  if live_agent and agent ~= live_agent then
    status, reason, since, agent, source = nil, nil, nil, live_agent, nil
  elseif token == previous.rejected or (since and previous.since and since < previous.since) then
    status, reason, since, agent, source =
      previous.hook_status, previous.hook_reason, previous.since, previous.agent, previous.hook_source
  end
  local deck = deck_states[id]
  agent = live_agent or agent or (deck and deck.agent)
  if not agent then
    return nil
  end
  local current = {
    token = status and table.concat({ agent or "", status, tostring(since or ""), reason or "" }, "|") or nil,
    rejected = previous.rejected,
    owner = owner or previous.owner,
    since = since,
    agent = agent,
    hook_status = status,
    hook_reason = reason,
    hook_source = source,
  }
  local ok, text = pcall(function()
    return p:get_lines_as_text(20)
  end)
  local title_ok, title = pcall(function()
    return p:get_title()
  end)
  local inferred, evidence = activity.screen(agent, ok and text or "", title_ok and title or "", agents[agent] or {})
  if inferred == "waiting" or (inferred == "working" and status ~= "waiting" and (not status or agent == "codex")) then
    status, reason, since, source = inferred, inferred == "waiting" and "needs input" or "active turn", nil, evidence
  elseif not status then
    if evidence == "transcript" then
      status, source = previous.status or "unknown", "screen"
    elseif inferred == "idle" and previous.status == "working" then
      current.idle_at = previous.idle_at or now
      status = now - current.idle_at >= 0.5 and "idle" or "working"
      source = "screen"
    else
      status, source = inferred or "unknown", evidence or "screen"
    end
  end
  current.status = status
  history[id] = current
  return status, reason, since, agent, source or ""
end

return M
