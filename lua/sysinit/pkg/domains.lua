local wezterm = require("wezterm")
local utils = require("sysinit.pkg.utils")
local M = {}

local function read_known_hosts_hosts()
  local hosts = {}
  local seen = {}
  local file = io.open(utils.get_home_dir() .. "/.ssh/known_hosts", "r")
  if not file then
    return hosts
  end

  for line in file:lines() do
    if line ~= "" and not line:match("^%s*#") and not line:match("^|1|") and not line:match("^@") then
      local first = line:match("^(%S+)")
      if first then
        for token in first:gmatch("[^,]+") do
          local address, port = token:match("^%[([^%]]+)%]:(%d+)$")
          local host = token
          if address then
            host = address:find(":", 1, true) and ("[" .. address .. "]:" .. port) or (address .. ":" .. port)
          end
          if host ~= "" and not host:match("[*?]") and not seen[host] then
            seen[host] = true
            table.insert(hosts, host)
          end
        end
      end
    end
  end

  file:close()
  return hosts
end

local function ssh_key_options()
  local opts = {}
  local config_data = utils.load_json_file(utils.get_config_path("config.json"))
  local agent = config_data and config_data.ssh and config_data.ssh.agent_socket
  if agent then
    local ok, matches = pcall(wezterm.glob, agent)
    if not ok or #matches == 0 then
      agent = nil
    end
  end
  if not agent or agent == "" then
    agent = os.getenv("SSH_AUTH_SOCK")
  end
  if agent and agent ~= "" then
    opts.identityagent = agent
    opts.identitiesonly = "no"
  end
  return opts
end

function M.ssh()
  local config_data = utils.load_json_file(utils.get_config_path("config.json"))
  local persistent_hosts = {}
  for _, host in ipairs(config_data.persistentRemoteHosts or {}) do
    persistent_hosts[host] = true
  end
  local key_options = ssh_key_options()
  local domains = {}
  local seen = {}
  local resolved_hostnames = {}

  local function add(host, cfg)
    host = host:lower()
    if host == "" or host:match("[*?]") or seen[host] then
      return
    end
    seen[host] = true
    local options = {}
    for key, value in pairs(key_options) do
      options[key] = value
    end
    for _, key in ipairs({ "identityagent", "identityfile", "identitiesonly" }) do
      if type(cfg) == "table" and cfg[key] then
        options[key] = cfg[key]
      end
    end
    table.insert(domains, {
      name = "ssh:" .. host,
      remote_address = host,
      multiplexing = "WezTerm",
      assume_shell = "Posix",
      ssh_option = options,
      remote_wezterm_path = persistent_hosts[host] and "wezterm-remote" or nil,
      timeout = persistent_hosts[host] and 7 or nil,
    })
  end

  local ok, hosts = pcall(wezterm.enumerate_ssh_hosts)
  if ok and hosts then
    for host, cfg in pairs(hosts) do
      if not host:match("%.host") then
        if type(cfg) == "table" and cfg.hostname then
          resolved_hostnames[cfg.hostname:lower()] = true
        end
        add(host, cfg)
      end
    end
  end

  for _, host in ipairs(read_known_hosts_hosts()) do
    if not resolved_hostnames[host:lower()] then
      add(host)
    end
  end
  table.sort(domains, function(a, b)
    return a.name < b.name
  end)

  return domains
end

-- Attaching inside the running GUI keeps one instance; `wezterm connect` would start another.
function M.attach_entries()
  local config_data = utils.load_json_file(utils.get_config_path("config.json")) or {}
  local entries = {}
  for _, host in ipairs(config_data.persistentRemoteHosts or {}) do
    entries[#entries + 1] = {
      brief = "Domain: attach ssh:" .. host:lower(),
      action = wezterm.action.AttachDomain("ssh:" .. host:lower()),
    }
  end
  return entries
end

return M
