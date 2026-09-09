{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.sysinit-wezterm;
  runner = pkgs.writeShellApplication {
    name = "wezterm-picker-call";
    runtimeInputs = [ pkgs.python3 ];
    text = ''exec python3 ${./scripts/picker-call.py} "$@"'';
  };
in
{
  options.programs.sysinit-wezterm = {
    enable = lib.mkEnableOption "the terminal configuration";
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      extraConfig = ''
        package.path = package.path .. ";${./lua}/?.lua;${./lua}/?/init.lua"
        return require("sysinit.pkg.bootstrap").build()
      '';
    };
    assertions = [
      {
        assertion = builtins.all (
          p:
          builtins.elem p.key [
            "!"
            "@"
            "#"
            "$"
            "%"
            "^"
            "&"
            "*"
            "("
            ")"
            "+"
            "="
            "?"
          ]
        ) (cfg.settings.picker.providers or [ ]);
        message = "WezTerm provider keys must use an available punctuation shortcut";
      }
      {
        assertion =
          let
            bindings = map (p: p.key) (cfg.settings.picker.providers or [ ]);
          in
          builtins.length bindings == builtins.length (lib.unique bindings);
        message = "WezTerm provider keys must be unique";
      }
    ];
    xdg.configFile."wezterm/config.json".text = builtins.toJSON (
      lib.recursiveUpdate {
        bin = "${config.home.profileDirectory}/bin";
        shell = [ (lib.getExe pkgs.zsh) ];
        posixShell = lib.getExe pkgs.zsh;
        font = {
          monospace = "monospace";
          symbols = "Symbols Nerd Font Mono";
        };
        transparency = {
          opacity = 1.0;
          blur = 0;
        };
        plugins = import ./plugins.nix { inherit pkgs; };
        picker.command = [ (lib.getExe runner) ];
      } cfg.settings
    );
    xdg.configFile."wezterm/env.json".text = builtins.toJSON cfg.environment;
  };
}
