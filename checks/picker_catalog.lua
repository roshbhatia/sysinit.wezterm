package.path = assert(arg[1]) .. "/?.lua;" .. package.path
local queue, started, payloads = {}, {}, {}
local now = 100
local real_time = os.time
os.time = function()
  return now
end
local wezterm = {
  GLOBAL = {},
  background_child_process = function(argv)
    started[#started + 1] = argv
  end,
  json_encode = function(value)
    local token = tostring(value)
    payloads[token] = value
    return token
  end,
  json_parse = function(raw)
    return assert(payloads[raw], "incomplete")
  end,
  time = {
    call_after = function(_, callback)
      queue[#queue + 1] = callback
    end,
  },
}
package.loaded.wezterm = wezterm
local catalog = require("session_tree.catalog")
local runner = { "/runner with spaces" }
local result = { descriptor = { title = "Sessions", icon = "" }, listed = { items = {} }, can_create = true }
local function tick()
  local pending = queue
  queue = {}
  for _, callback in ipairs(pending) do
    callback()
  end
end
local function finish(index, name, data)
  local argv = started[index]
  payloads[name] = data
  local file = assert(io.open(argv[4], "w"))
  file:write(name)
  file:close()
end
catalog.load(runner, "/manifest with spaces")
local delivered
catalog.load(runner, "/manifest with spaces", function(value)
  delivered = value
end)
assert(#started == 1 and delivered == nil, "concurrent loads did not share their asynchronous job")
assert(started[1][1] == runner[1] and started[1][2] == "--catalog" and started[1][3] == "/manifest with spaces")
tick()
assert(delivered == nil, "an empty result file was accepted")
finish(1, "success", { ok = true, catalog = result })
tick()
assert(delivered == result and catalog.peek(runner, "/manifest with spaces") == result)
assert(io.open(started[1][4], "r") == nil, "completed job leaked its file")
package.loaded["session_tree.catalog"] = nil
catalog = require("session_tree.catalog")
catalog.load(runner, "/manifest with spaces", function(value)
  assert(value == result)
end)
assert(#started == 1, "configuration reload discarded the shared cache")
now = 106
catalog.load(runner, "/manifest with spaces")
assert(#started == 2 and catalog.peek(runner, "/manifest with spaces") == result, "refresh removed usable results")
finish(2, "failure", { ok = false, error = "offline" })
tick()
assert(catalog.peek(runner, "/manifest with spaces") == result, "refresh failure discarded cached items")
local failure
catalog.load(runner, "/other", function(value, err)
  assert(value == nil)
  failure = err
end)
now = 120
tick()
assert(failure == "Provider loading timed out", "hung provider did not terminate loading")
assert(io.open(started[3][4], "r") == nil, "timeout leaked its file")
os.time = real_time
print("Asynchronous picker cache passed")
