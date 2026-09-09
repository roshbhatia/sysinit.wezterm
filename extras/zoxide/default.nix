{ pkgs, core }:
let
  executable = pkgs.writeShellApplication {
    name = "zoxide-picker";
    text = ''
      exec ${pkgs.uv}/bin/uv --no-cache run --offline --no-managed-python --no-python-downloads \
        --no-project --python ${pkgs.python3}/bin/python3 --script ${./provider.py} ${pkgs.lib.getExe core}
    '';
  };
  manifest = pkgs.writeText "zoxide.json" (
    builtins.toJSON (
      (builtins.fromJSON (builtins.readFile ./provider.json))
      // {
        command = [ (pkgs.lib.getExe executable) ];
      }
    )
  );
in
pkgs.symlinkJoin {
  name = "zoxide-picker";
  paths = [ executable ];
  postBuild = "mkdir -p $out/share/wezterm/providers; cp ${manifest} $out/share/wezterm/providers/zoxide.json";
  meta.mainProgram = "zoxide-picker";
}
