local utils = require("sysinit.pkg.utils")

local M = {}

local function get_basic_config()
  local env_data = utils.load_json_file(utils.get_config_path("env.json"))
  local settings = utils.load_json_file(utils.get_config_path("config.json"))
  local nix_zsh = settings.posixShell or utils.get_nix_binary("zsh")
  local environment = {}
  for key, value in pairs(env_data or {}) do
    environment[key] = value
  end
  -- SHELL must remain POSIX even when default_prog is Nushell.
  environment.SHELL = nix_zsh
  environment.TERM = environment.TERM or "wezterm"

  return {
    default_prog = settings.shell or { nix_zsh },
    set_environment_variables = environment,
  }
end

function M.setup(config)
  local basic_config = get_basic_config()

  for key, value in pairs(basic_config) do
    config[key] = value
  end
end

return M
