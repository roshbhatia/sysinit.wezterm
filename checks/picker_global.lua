local wezterm = require("wezterm")
package.path = assert(os.getenv("SYSINIT_WEZTERM_LUA")) .. "/?.lua;" .. package.path
local catalog = require("sysinit.pkg.ui.catalog")
local value = { descriptor = { title = "Sessions", icon = "md_layers" }, listed = { items = {} }, can_create = true }
wezterm.GLOBAL["picker_catalog:v2:/runner\0/manifest"] = {
  catalog_json = wezterm.json_encode(value),
  at = os.time(),
}
local cached = catalog.peek({ "/runner" }, "/manifest")
assert(type(cached.descriptor) == "table", "cached descriptor is not a Lua table")
assert(type(cached.listed.items) == "table", "cached items are not a Lua table")
assert(cached.descriptor.title == value.descriptor.title and cached.can_create)
local delivered = false
catalog.load({ "/runner" }, "/manifest", function(result)
  assert(type(result.descriptor) == "table")
  delivered = true
end)
assert(delivered, "fresh cached catalog was not delivered")
local marker = assert(io.open(assert(os.getenv("PICKER_TEST_MARKER")), "w"))
marker:write("passed")
marker:close()
return {}
