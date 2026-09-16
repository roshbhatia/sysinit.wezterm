package.path = assert(arg[1]) .. "/?.lua;" .. package.path
local home = assert(arg[2])
local env = { PATH = "/profile/bin", EXTRA = "a b", TERM = "custom-term" }
package.loaded["sysinit.pkg.utils"] = {
  get_home_dir = function()
    return home
  end,
  get_config_path = function(path)
    return path
  end,
  get_nix_binary = function(name)
    return "/profile/bin/" .. name
  end,
  load_json_file = function(path)
    if path == "env.json" then
      return env
    end
    return { posixShell = "/profile/bin/zsh" }
  end,
}
package.loaded.wezterm = {
  enumerate_ssh_hosts = function()
    return {
      direct = { hostname = "direct", identityfile = "/keys/direct", identitiesonly = "yes" },
      alias = { hostname = "target" },
      target = { hostname = "other" },
    }
  end,
}
local config = {}
require("sysinit.pkg.core").setup(config)
assert(config.set_environment_variables.EXTRA == "a b")
assert(config.set_environment_variables.TERM == "custom-term")
assert(config.set_environment_variables.SHELL == "/profile/bin/zsh")
assert(env.SHELL == nil, "the source environment was mutated")
local domains = require("sysinit.pkg.domains").ssh()
local by_name = {}
for _, domain in ipairs(domains) do
  by_name[domain.name] = domain
end
assert(by_name["ssh:direct"], "explicit self-resolving alias disappeared")
assert(by_name["ssh:alias"] and by_name["ssh:target"], "explicit aliases depend on iteration order")
assert(by_name["ssh:direct"].ssh_option.identityfile == "/keys/direct")
assert(by_name["ssh:direct"].ssh_option.identitiesonly == "yes")
assert(by_name["ssh:port-host:2222"].remote_address == "port-host:2222")
assert(by_name["ssh:[::1]:2200"].remote_address == "[::1]:2200")
assert(not by_name["ssh:other"], "a resolved hostname duplicated a configured alias")
assert(not by_name["ssh:port-host"], "known_hosts lost the port")
print("composition fixtures passed")
