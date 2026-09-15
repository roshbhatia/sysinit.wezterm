local M = {}
function M.setup(config, workspace_manager, context)
  local options = require("session_tree.options").get()
  options.workspace_manager = workspace_manager
  options.context = context
  require("session_tree_plugin").apply_to_config(config, options)
end
return M
