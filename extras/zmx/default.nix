{ pkgs, core }:
let
  executable = pkgs.writeShellApplication {
    name = "zmx-picker";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./provider.py} ${pkgs.lib.getExe core}
    '';
  };
  manifest = pkgs.writeText "zmx.json" (
    builtins.toJSON (
      (builtins.fromJSON (builtins.readFile ./provider.json))
      // {
        command = [ (pkgs.lib.getExe executable) ];
      }
    )
  );
in
pkgs.symlinkJoin {
  name = "zmx-picker";
  paths = [ executable ];
  postBuild = "mkdir -p $out/share/wezterm/providers; cp ${manifest} $out/share/wezterm/providers/zmx.json";
  meta.mainProgram = "zmx-picker";
}
