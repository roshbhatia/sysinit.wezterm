local lua_root = assert(os.getenv("SYSINIT_WEZTERM_LUA"), "SYSINIT_WEZTERM_LUA is required")

package.path = table.concat({
  lua_root .. "/?.lua",
  lua_root .. "/?/init.lua",
  package.path,
}, ";")

local wezterm = require("wezterm")
local on = wezterm.on
local title_handlers = {}
local palette_handlers = 0
wezterm.on = function(name, callback)
  if name == "format-tab-title" then
    title_handlers[#title_handlers + 1] = callback
  elseif name == "augment-command-palette" then
    palette_handlers = palette_handlers + 1
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
      assert(items == " [1] sysinit ", "fallback tab padding was not rendered: " .. items)
    else
      local text = ""
      for _, item in ipairs(items) do
        if type(item) == "table" and item.Text then
          text = text .. item.Text
        end
      end
      text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
      local expected = active and "[1] github/sysinit" or "[1] sysinit"
      assert(text == expected, "tab padding was not rendered: " .. text)
    end
  end
end
local loader = require("sysinit.pkg.plugin_loader")
local ok, tabline = loader.load("tabline")
if ok then
  local sections = tabline.get_config().sections
  assert(sections.tabline_z[1] == require("sysinit.pkg.ui.statusbar").window_index)
  assert(sections.tabline_z[2][1] == "domain")
  assert(sections.tabline_z[2].fmt == nil)
  assert(sections.tabline_z[2].padding.left == 0 and sections.tabline_z[2].padding.right == 1)
  local selected = tabline.get_theme().tab.active
  assert(config.colors.selection_fg == selected.fg and config.colors.selection_bg == selected.bg)
end
assert(palette_handlers >= 2, "pane palette did not register beside the session palette")
local pane_palette = require("sysinit.pkg.pane_palette")
local briefs = {}
for _, entry in ipairs(pane_palette.entries()) do
  briefs[entry.brief] = true
end
for _, brief in ipairs({
  "Pane: swap with",
  "Pane: break out to new tab",
  "Tab: rename",
  "Pane: open scrollback in Neovim",
}) do
  assert(briefs[brief], brief .. " missing from the palette")
end
local requested_rows
local scrollback = os.tmpname()
pane_palette.write_scrollback({
  get_dimensions = function()
    return { scrollback_rows = 1234 }
  end,
  get_lines_as_text = function(_, rows)
    requested_rows = rows
    return "first\nlast\n"
  end,
}, scrollback)
local written = assert(io.open(scrollback)):read("*a")
os.remove(scrollback)
assert(requested_rows == 1234 and written == "first\nlast\n", "scrollback was not written whole")
local marker = assert(io.open(assert(os.getenv("WEZTERM_TEST_RESULT")), "w"))
marker:write("passed")
marker:close()
return config
