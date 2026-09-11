local lua_root = assert(os.getenv("SYSINIT_WEZTERM_LUA"), "SYSINIT_WEZTERM_LUA is required")

package.path = table.concat({
  lua_root .. "/?.lua",
  lua_root .. "/?/init.lua",
  package.path,
}, ";")

local wezterm = require("wezterm")
local on = wezterm.on
local title_handlers = {}
wezterm.on = function(name, callback)
  if name == "format-tab-title" then
    title_handlers[#title_handlers + 1] = callback
  end
  return on(name, callback)
end

local config = require("sysinit.pkg.bootstrap").build()
wezterm.on = on
assert(#title_handlers == 1, "tab title has competing renderers")
for _, active in ipairs({ true, false }) do
  for _, hover in ipairs({ true, false }) do
    local tab = {
      tab_id = 1,
      tab_index = 0,
      is_active = active,
      active_pane = { current_working_dir = { file_path = "/github/sysinit" } },
    }
    local items = title_handlers[1](tab, { tab }, {}, config, hover, 32)
    if type(items) == "string" then
      assert(items == " sysinit [1] ", "fallback tab padding was not rendered: " .. items)
    else
      local text = ""
      for _, item in ipairs(items) do
        if type(item) == "table" and item.Text then
          text = text .. item.Text
        end
      end
      local expected = active and "  github/sysinit [1]  " or "  sysinit [1]  "
      assert(text == expected, "tab padding was not rendered: " .. text)
    end
  end
end
return config
