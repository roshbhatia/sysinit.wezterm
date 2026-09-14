local wezterm = require("wezterm")
local M = {}

local function key(command, manifest)
  return "picker_catalog:v2:" .. table.concat(command, "\0") .. "\0" .. manifest
end

function M.peek(command, manifest)
  local entry = wezterm.GLOBAL[key(command, manifest)]
  return entry and entry.catalog_json and wezterm.json_parse(entry.catalog_json)
end

function M.load(command, manifest, callback)
  local cache_key = key(command, manifest)
  local entry = wezterm.GLOBAL[cache_key] or {}
  if entry.catalog_json and os.time() - (entry.at or 0) < 5 then
    if callback then
      callback(M.peek(command, manifest))
    end
    return
  end
  if not entry.path then
    local path = os.tmpname()
    local argv = {}
    for _, value in ipairs(command) do
      argv[#argv + 1] = value
    end
    argv[#argv + 1] = "--catalog"
    argv[#argv + 1] = manifest
    argv[#argv + 1] = path
    entry.path, entry.started = path, os.time()
    wezterm.GLOBAL[cache_key] = entry
    local ok, err = pcall(wezterm.background_child_process, argv)
    if not ok then
      os.remove(path)
      entry.path = nil
      wezterm.GLOBAL[cache_key] = entry
      if callback then
        callback(nil, tostring(err))
      end
      return
    end
  end
  local path = entry.path
  local function poll()
    local current = wezterm.GLOBAL[cache_key] or {}
    if current.path ~= path then
      if callback then
        callback(M.peek(command, manifest), current.error)
      end
      return
    end
    local file = io.open(path, "r")
    local raw = file and file:read("*a") or ""
    if file then
      file:close()
    end
    local parsed, result = pcall(wezterm.json_parse, raw)
    if parsed and type(result) == "table" and type(result.ok) == "boolean" then
      os.remove(path)
      current.path = nil
      current.error = result.ok and nil or result.error
      if result.ok then
        current.catalog_json, current.at = wezterm.json_encode(result.catalog), os.time()
      end
      wezterm.GLOBAL[cache_key] = current
      if callback then
        callback(result.ok and result.catalog or nil, current.error)
      end
      return
    end
    if os.time() - current.started >= 12 then
      os.remove(path)
      current.path, current.error = nil, "Provider loading timed out"
      wezterm.GLOBAL[cache_key] = current
      if callback then
        callback(nil, current.error)
      end
      return
    end
    wezterm.time.call_after(0.03, poll)
  end
  wezterm.time.call_after(0.03, poll)
end

return M
