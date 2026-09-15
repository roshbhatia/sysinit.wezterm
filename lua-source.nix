{
  pkgs,
  session-tree,
  spawn,
  smart-keys,
}:
pkgs.runCommand "sysinit-wezterm-lua" { } ''
  mkdir -p $out
  cp -r ${./lua}/. $out/
  ln -s ${session-tree}/plugin/session_tree $out/session_tree
  ln -s ${session-tree}/plugin/init.lua $out/session_tree_plugin.lua
  ln -s ${smart-keys}/plugin/init.lua $out/smart_keys_plugin.lua
  ln -s ${spawn}/plugin/init.lua $out/spawn_plugin.lua
''
