{
  description = "WezTerm live tree and provider picker";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      each = nixpkgs.lib.genAttrs systems;
    in
    {
      homeManagerModules.default = import ./module.nix;
      lib.luaSource = ./lua;
      packages = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          wezspawn = pkgs.buildGoModule {
            pname = "wezspawn";
            version = "0.1.0";
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./go.mod
                ./cmd
                ./internal
              ];
            };
            vendorHash = null;
            subPackages = [ "cmd/wezspawn" ];
            meta.mainProgram = "wezspawn";
          };
          provider-zoxide = import ./extras/zoxide {
            inherit pkgs;
            core = pkgs.zoxide;
          };
          extras = self.packages.${system}.provider-zoxide;
          full = pkgs.symlinkJoin {
            name = "sysinit-wezterm-full";
            paths = [
              self.packages.${system}.default
              self.packages.${system}.extras
              self.packages.${system}.wezspawn
            ];
          };
          default = pkgs.runCommand "sysinit-wezterm" { } "mkdir -p $out; cp -r ${./lua} $out/lua";
        }
      );
      devShells = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.ffmpeg
              pkgs.go
              pkgs.git
              pkgs.zoxide
              pkgs.lua5_4
              pkgs.stylua
              pkgs.nixfmt
              pkgs.python3
              pkgs.uv
              pkgs.wezterm
              pkgs.vhs
            ];
          };
        }
      );
      formatter = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "format-nix";
          runtimeInputs = [
            pkgs.git
            pkgs.nixfmt
            pkgs.findutils
          ];
          text = ''git ls-files -z -- '*.nix' | xargs -0 -r nixfmt "$@"'';
        }
      );
      checks = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          standalone =
            (import ./module.nix {
              inherit pkgs;
              lib = nixpkgs.lib;
              config = {
                programs.sysinit-wezterm = {
                  enable = true;
                  settings = { };
                  environment = { };
                };
                home.profileDirectory = "/home/test/.nix-profile";
              };
            }).config.content;
        in
        {
          wezspawn = self.packages.${system}.wezspawn;
          startup =
            pkgs.runCommand "wezterm-standalone-startup"
              {
                nativeBuildInputs = [ pkgs.wezterm ];
              }
              ''
                    export HOME="$TMPDIR/home"
                    export XDG_CONFIG_HOME="$HOME/.config"
                    mkdir -p "$XDG_CONFIG_HOME/wezterm"
                    cp ${
                      pkgs.writeText "config.json" standalone.xdg.configFile."wezterm/config.json".text
                    } "$XDG_CONFIG_HOME/wezterm/config.json"
                    cp ${
                      pkgs.writeText "env.json" standalone.xdg.configFile."wezterm/env.json".text
                    } "$XDG_CONFIG_HOME/wezterm/env.json"
                    SYSINIT_WEZTERM_LUA=${./lua} wezterm --config-file ${./checks/wezterm-entry.lua} show-keys --lua > keys.lua 2> startup.log
                    cat startup.log
                if grep -E 'setup failed|Failed to load|No pinned dependency|ERROR|Error|Cloned https' startup.log; then exit 1; fi
                    test "$(grep -c '^    { key =' keys.lua)" -ge 80
                    touch $out
              '';
          lua =
            pkgs.runCommand "wezterm-config-tests"
              {
                nativeBuildInputs = [
                  pkgs.lua5_4
                  pkgs.python3
                ];
              }
              ''
                export HOME="$TMPDIR"
                lua ${./checks/wezterm.lua} ${./lua} ${./checks/fixtures/wezterm-plugin}
                cd ${self}
                python3 -m unittest discover -s checks -p 'test_*.py'
                touch $out
              '';
        }
      );
    };
}
