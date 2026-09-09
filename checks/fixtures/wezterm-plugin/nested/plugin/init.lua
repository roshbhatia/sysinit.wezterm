local wezterm = require("wezterm")
local dependency = wezterm.plugin.require("https://github.com/example/fixture.wz")
local ok, err = pcall(wezterm.plugin.require, "https://github.com/example/unregistered.wz")
assert(not ok)
return { value = dependency.value, unknown = tostring(err) }
