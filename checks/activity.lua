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

local records = {
  { id = "", state = "idle", app = "cargo" },
  { id = "test", state = "working", app = "cargo" },
  { id = "test/unit", state = "blocked", app = "cargo", msg = "Approve tests?" },
}
pane.get_program_status = function()
  return records
end
local status, reason, _, agent, source = panes.program_state(pane)
assert(status == "waiting" and reason == "Approve tests?" and agent == "cargo" and source == "osc7501")
proc = { pid = 99, executable = "/bin/zsh" }
status, reason, _, agent, source = state(done)
assert(
  status == "waiting" and reason == "Approve tests?" and agent == "cargo" and source == "osc7501",
  "session tree reader ignored OSC status from a non-agent program"
)
records = { { id = "", state = "error", msg = "Build failed" } }
assert(panes.program_state(pane) == "waiting")
assert(state(done) == "waiting", "OSC error was hidden by stale agent state")
records = { { id = "", state = "working", app = "cargo" } }
assert(state(done) == "working", "OSC working state did not reach session tree reader")
records = {}
assert(panes.program_state(pane) == nil)
assert(state(done) == nil, "cleared OSC retained program state on a shell")
reset()
assert(state(done) == "done", "cleared OSC did not restore agent fallback")
pane.get_program_status = nil
assert(panes.program_state(pane) == nil)
assert(state(done) == "done", "upstream terminal did not retain agent fallback")
print("OSC 7501 program status precedence and upstream fallback passed")

local upstream_pane = setmetatable({}, {
  __index = function(_, key)
    error("attempt to get an unknown field '" .. key .. "'")
  end,
})
assert(panes.program_state(upstream_pane) == nil, "upstream userdata must retain agent status fallback")

pane.get_program_status = function()
  return { { id = "build", state = "blocked", app = "cargo", msg = "Approve tests?" } }
end
pane.get_current_working_dir = function()
  return "file:///work/project"
end
pane.get_domain_name = function()
  return "local"
end
proc = { pid = 99, executable = "/bin/zsh" }
local tab = {
  tab_id = function()
    return 2
  end,
  panes_with_info = function()
    return { { pane = pane, is_active = true } }
  end,
}
local window = {
  get_workspace = function()
    return "build"
  end,
  window_id = function()
    return 1
  end,
  tabs = function()
    return { tab }
  end,
}
package.loaded["session_tree.sessions"] = {
  last_active = function()
    return 0
  end,
  ordered_windows = function()
    return { window }
  end,
}
panes.read_pane_record = function()
  return nil
end
require("session_tree.options").configure({
  adapters = {
    panes = panes,
    format = {
      tab_label = function()
        return "build"
      end,
      pane_proc = function(_, app)
        return app
      end,
    },
  },
})
local tree = require("session_tree.session_tree").build({})
local row = tree.workspaces[1].tabs[1].panes[1]
assert(
  row.status == "waiting" and row.agent == "cargo" and row.reason == "Approve tests?",
  "session switcher pane row lost OSC status"
)
assert(
  tree.workspaces[1].status == "waiting" and #tree.attention == 1,
  "OSC blocker did not reach workspace status and attention list"
)
pane.get_program_status = function()
  return {}
end
tree = require("session_tree.session_tree").build({})
assert(
  tree.workspaces[1].tabs[1].panes[1].status == nil and #tree.attention == 0,
  "cleared OSC remained in session switcher"
)
print("OSC 7501 session switcher rows and attention passed")
