-- Reads repository and branch from .git without a subprocess; titles render on every frame.
local M = {}

local TTL = 5
local MAX_DEPTH = 40
local cache = {}

local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local line = file:read("*l")
  file:close()
  return line
end

local function basename(path)
  return path:match("([^/]+)/*$")
end

local function locate(path)
  local dir = path:gsub("/+$", "")
  for _ = 1, MAX_DEPTH do
    if dir == "" then
      return nil
    end
    local head = read_first_line(dir .. "/.git/HEAD")
    if head then
      return basename(dir), head
    end
    local pointer = read_first_line(dir .. "/.git")
    local gitdir = pointer and pointer:match("^gitdir:%s*(.-)%s*$")
    if gitdir then
      if gitdir:sub(1, 1) ~= "/" then
        gitdir = dir .. "/" .. gitdir
      end
      head = read_first_line(gitdir .. "/HEAD")
      if head then
        local main = gitdir:match("^(.*)/%.git/worktrees/[^/]+$")
        return basename(main or dir), head
      end
    end
    dir = dir:match("^(.*)/[^/]*$") or ""
  end
  return nil
end

function M.lookup(path, now)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  now = now or os.time()
  local hit = cache[path]
  if hit and now - hit.at < TTL then
    return hit.value
  end
  local repo, head = locate(path)
  local value
  if repo and head then
    value = { repo = repo, branch = head:match("^ref:%s*refs/heads/(.+)$") or head:sub(1, 7) }
  end
  cache[path] = { at = now, value = value }
  return value
end

function M.clear()
  cache = {}
end

return M
