package.path = arg[1] .. "/?.lua;" .. arg[1] .. "/?/init.lua;" .. package.path
package.preload.wezterm = function()
  return {}
end
package.preload["sysinit.pkg.utils"] = function()
  return {}
end
local panes = require("sysinit.pkg.ui.panes")
local specs = {
  codex = { executable_patterns = { "/codex$" }, status_patterns = { working = { "esc to interrupt" } } },
  claude = { executable_patterns = { "/claude$" }, status_patterns = {} },
  pi = { executable_patterns = { "/pi$" }, status_patterns = {} },
}
local proc, text, title, raw
local pane = {
  pane_id = function()
    return 12
  end,
  get_foreground_process_info = function()
    return proc
  end,
  get_lines_as_text = function()
    return text
  end,
  get_title = function()
    return title
  end,
  get_user_vars = function()
    return { agent_state = raw }
  end,
}
local function reset(agent)
  panes.configure(specs)
  proc = { pid = 42, executable = "/bin/" .. (agent or "codex") }
  text, title, raw = "", "", nil
end
local function state(record, now, deck)
  return panes.agent_state(pane, deck or {}, record or false, now or 10)
end
reset()
local done = { status = "done", agent = "codex", since = 2, reason = "finished" }
text = "• Thinking (3s • esc to interrupt)"
assert(state(done) == "working", "dynamic Codex footer missed")
text = "press enter to confirm or esc to cancel"
assert(state({ status = "working", agent = "codex", since = 3 }) == "waiting", "approval hidden by working hook")
text = "I finished reading the file."
assert(
  state(false, 12, { [12] = { agent = "codex", status = "working" } }) == "unknown",
  "generic prose became activity"
)
text = "The text says esc to interrupt."
assert(state() == "unknown", "configured broad pattern bypassed scoped rules")
text = "• Thinking (3s • esc to interrupt)\n› old transcript ends here"
assert(state() == "unknown", "activity above current prompt was reused")
reset()
assert(state(done) == "done")
proc = { pid = 99, executable = "/bin/zsh" }
assert(state(done) == nil, "shell inherited old hook")
proc = { pid = 43, executable = "/bin/codex" }
assert(state(done) == "unknown", "new process inherited old completion")
assert(state({ status = "working", agent = "codex", since = 4 }) == "working")
assert(state(done) == "working", "out-of-order hook rewound state")
proc = { pid = 44, executable = "/bin/codex" }
assert(state({ status = "working", agent = "codex", since = 4 }) == "unknown", "replacement process inherited hook")
reset()
proc = { pid = 99, executable = "/bin/zsh", children = { child = { pid = 42, executable = "/bin/codex" } } }
assert(state(done) == "done", "wrapper hid live agent")
proc = { pid = 99, executable = "/bin/ssh" }
assert(state(done) == "done", "opaque remote transport erased hook")
reset("pi")
assert(state({ status = "working", agent = "pi", since = 1 }, 100000) == "working", "long-running hook expired")
reset()
text = "• Thinking (3s • esc to interrupt)"
assert(state() == "working")
text = "›"
assert(state(false, 10.1) == "working", "idle flickered immediately")
assert(state(false, 10.7) == "idle", "confirmed idle never settled")
reset()
title = "⠋ Codex"
assert(state() == "working", "title spinner missed")
title = "Action Required"
assert(state() == "waiting", "title blocker missed")
title = ""
text = "↑/↓ to scroll\nq to quit"
assert(state() == "waiting", "transcript viewer changed state")
reset("claude")
text = "Do you want to proceed?\n❯ 1. Yes\nEsc to cancel"
assert(state({ status = "working", agent = "claude", since = 1 }) == "waiting", "Claude approval missed")
panes.forget_missing({})
assert(panes.latest(12) == nil, "closed pane state leaked")
print("agent activity regression tests passed")
reset()
text = "• Thinking (3s • esc to interrupt)\npress enter to confirm or esc to cancel"
assert(state() == "waiting", "working footer outranked visible blocker")
text = "A guide says press enter to confirm."
assert(state() == "unknown", "quoted instructions became a blocker")
reset("pi")
proc = { pid = 50, executable = "/bin/node", argv = { "node", "/some/pi/dist/cli.js" } }
assert(state({ status = "working", agent = "pi", since = 2 }) == "working", "unrecognized runtime erased valid hook")
