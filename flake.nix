{
  description = "WezTerm live tree and provider picker";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.session-tree.url = "github:roshbhatia/session-tree.wezterm";
  inputs.session-tree.inputs.nixpkgs.follows = "nixpkgs";
  inputs.spawn.url = "github:roshbhatia/spawn.wezterm";
  inputs.spawn.inputs.nixpkgs.follows = "nixpkgs";
  inputs.smart-keys.url = "github:roshbhatia/smart-keys.wezterm";
  inputs.smart-keys.inputs.nixpkgs.follows = "nixpkgs";
  outputs =
    {
      self,
      nixpkgs,
      session-tree,
      spawn,
      smart-keys,
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      each = nixpkgs.lib.genAttrs systems;
      luaFor =
        pkgs:
        import ./lua-source.nix {
          inherit
            pkgs
            session-tree
            spawn
            smart-keys
            ;
        };
      module = import ./module.nix { inherit session-tree spawn smart-keys; };
    in
    {
      homeManagerModules.default = module;
      lib.luaSource = luaFor;
      packages = each (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          wezspawn = spawn.packages.${system}.wezspawn;
          provider-zoxide = import ./extras/zoxide {
            inherit pkgs;
            core = pkgs.zoxide;
          };
          provider-zmx = import ./extras/zmx {
            inherit pkgs;
            core = pkgs.zmx;
          };
          extras = pkgs.symlinkJoin {
            name = "wezterm-providers";
            paths = [
              self.packages.${system}.provider-zoxide
              self.packages.${system}.provider-zmx
            ];
          };
          full = pkgs.symlinkJoin {
            name = "sysinit-wezterm-full";
            paths = [
              self.packages.${system}.default
              self.packages.${system}.extras
              self.packages.${system}.wezspawn
            ];
          };
          default = pkgs.runCommand "sysinit-wezterm" { } "mkdir -p $out; cp -r ${luaFor pkgs} $out/lua";
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
              pkgs.zmx
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
            (module {
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
                    SYSINIT_WEZTERM_LUA=${luaFor pkgs} WEZTERM_TEST_RESULT="$TMPDIR/tab-passed" wezterm --config-file ${./checks/wezterm-entry.lua} show-keys --lua > keys.lua 2> startup.log
                    cat startup.log
                    test "$(cat "$TMPDIR/tab-passed")" = passed
                if grep -E 'setup failed|Failed to load|No pinned dependency|ERROR|Error|Cloned https' startup.log; then exit 1; fi
                    test "$(grep -c '^    { key =' keys.lua)" -ge 80
                    SYSINIT_WEZTERM_LUA=${luaFor pkgs} PICKER_TEST_MARKER="$TMPDIR/picker-passed" wezterm --config-file ${./checks/picker_global.lua} show-keys --lua > /dev/null 2> picker.log
                    cat picker.log
                    test "$(cat "$TMPDIR/picker-passed")" = passed
                    touch $out
              '';
          lua =
            pkgs.runCommand "wezterm-config-tests"
              {
                nativeBuildInputs = [
                  pkgs.lua5_4
                  pkgs.python3
                  pkgs.uv
                ];
              }
              ''
                export HOME="$TMPDIR"
                lua ${./checks/wezterm.lua} ${luaFor pkgs} ${./checks/fixtures/wezterm-plugin}
                lua ${./checks/picker_catalog.lua} ${luaFor pkgs}
                cd ${self}
                uv run --offline --no-project --no-managed-python --python ${pkgs.python3}/bin/python3 -m unittest discover -s checks -p 'test_*.py'
                touch $out
              '';
          zmx =
            pkgs.runCommand "wezterm-zmx-attach-test"
              {
                nativeBuildInputs = [
                  pkgs.zmx
                  pkgs.coreutils
                  pkgs.jq
                ];
              }
              ''
                export HOME="$TMPDIR"
                export ZMX_DIR="$TMPDIR/zmx"
                export ZMX_SESSION_PREFIX=""
                session=wezterm-provider-test
                trap 'zmx kill "$session" --force >/dev/null 2>&1 || true' EXIT
                zmx attach "$session" sleep 120 >/dev/null 2>&1 &
                for attempt in $(seq 1 100); do
                  if zmx list --short | grep -Fxq "$session"; then break; fi
                  sleep 0.05
                done
                request='{"version":"provider/v1","kind":"request","requestId":"smoke","capability":"picker.open","input":{"id":"wezterm-provider-test"}}'
                printf '%s\n' "$request" | ${self.packages.${system}.provider-zmx}/bin/zmx-picker > plan.json
                jq -e '.status == "ok" and .output.command[1:3] == ["-u","ZMX_SESSION"] and .output.command[4:6] == ["attach","wezterm-provider-test"]' plan.json
                touch $out
              '';
        }
      );
    };
}
