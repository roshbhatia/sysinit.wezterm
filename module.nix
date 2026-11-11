{
  session-tree,
  spawn,
  smart-keys,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.sysinit-wezterm;
  stateDir = "${config.home.homeDirectory}/.local/state/wezterm/recovery";
  socketPath = "${config.home.homeDirectory}/.local/state/wezterm/mux.sock";
  # A stable path keeps the launchd plist unchanged across updates, so a switch
  # does not reload the agent and kill every persistent pane.
  muxConfigPath = "${config.xdg.configHome}/wezterm/mux.lua";
  # The mux records its own pid so the GUI can tell a restarted mux from a reattach.
  epochPath = "${config.home.homeDirectory}/.local/state/wezterm/mux-epoch";
  codecMarker = "${config.home.homeDirectory}/.local/state/wezterm/mux-codec-version";
  codecVersion = pkgs.runCommand "wezterm-codec-version" { } ''
    grep -m1 -oE 'CODEC_VERSION: usize = [0-9]+' ${pkgs.wezterm.src}/codec/src/lib.rs |
      grep -oE '[0-9]+$' > "$out"
    test -s "$out"
  '';
  muxConfig = pkgs.writeText "wezterm-mux.lua" ''
    local wezterm = require("wezterm")
    local pid = wezterm.procinfo.pid()
    local executable = wezterm.procinfo.executable_path_for_pid(pid) or ""
    if executable:match("wezterm%-mux%-server$") then
      local epoch = io.open(${builtins.toJSON epochPath}, "w")
      if epoch then
        epoch:write(tostring(pid))
        epoch:close()
      end
    end
    return {
      unix_domains = { { name = "unix", socket_path = ${builtins.toJSON socketPath} } },
      default_prog = wezterm.json_parse(${
        builtins.toJSON (builtins.toJSON (cfg.settings.shell or [ (lib.getExe pkgs.zsh) ]))
      }),
      set_environment_variables = wezterm.json_parse(${builtins.toJSON (builtins.toJSON cfg.environment)}),
      scrollback_lines = ${toString (lib.max 3500 (cfg.settings.persistence.scrollback_lines or 0))},
      unset_environment_variables = wezterm.json_parse(${
        builtins.toJSON (builtins.toJSON (cfg.settings.unsetEnvironmentVariables or [ ]))
      }),
      mux_server_spawn_initial_tab = false,
    }
  '';
  remoteClient = pkgs.writeShellApplication {
    name = "wezterm-remote";
    text = ''
      mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/wezterm"}
      export WEZTERM_UNIX_SOCKET=${lib.escapeShellArg socketPath}
      exec ${pkgs.wezterm}/bin/wezterm --config-file ${muxConfig} "$@"
    '';
  };
  luaSource = import ./lua-source.nix {
    inherit
      pkgs
      session-tree
      spawn
      smart-keys
      ;
  };
  runner = pkgs.writeShellApplication {
    name = "wezterm-picker-call";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${session-tree}/scripts/picker-call.py "$@"
    '';
  };
in
{
  options.programs.sysinit-wezterm = {
    enable = lib.mkEnableOption "the terminal configuration";
    persistence = {
      enable = lib.mkEnableOption "session snapshots and a persistent local mux";
      service = lib.mkEnableOption "a managed remote mux service";
      muxBinary = lib.mkOption {
        type = lib.types.str;
        default = "${pkgs.wezterm}/bin/wezterm-mux-server";
        description = "Mux server executable; a stable signed path keeps its privacy grants across updates.";
      };
    };
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
    home.packages = lib.optional cfg.persistence.enable remoteClient;
    home.activation.weztermMuxDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/wezterm"}
    '';
    xdg.configFile."wezterm/mux.lua" = lib.mkIf cfg.persistence.enable { source = muxConfig; };
    # The agent survives updates, so restart it only when the mux protocol changes;
    # an older mux would refuse the new GUI.
    home.activation.weztermMuxProtocol = lib.mkIf (cfg.persistence.service && pkgs.stdenv.isDarwin) (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        wanted=$(cat ${codecVersion})
        marker=${lib.escapeShellArg codecMarker}
        if [ "$(cat "$marker" 2>/dev/null)" != "$wanted" ]; then
          domain="gui/$(id -u)/com.roshbhatia.wezterm-mux"
          if /bin/launchctl print "$domain" >/dev/null 2>&1; then
            run /bin/launchctl kickstart -k "$domain"
          fi
          if [ -z "''${DRY_RUN:-}" ]; then
            printf '%s\n' "$wanted" > "$marker"
          fi
        fi
      ''
    );
    systemd.user.services = lib.optionalAttrs (cfg.persistence.service && pkgs.stdenv.isLinux) {
      wezterm-mux = {
        Unit.Description = "Persistent WezTerm mux";
        Service = {
          ExecStart = "${pkgs.wezterm}/bin/wezterm-mux-server --config-file ${muxConfig}";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
    launchd.agents = lib.optionalAttrs (cfg.persistence.service && pkgs.stdenv.isDarwin) {
      wezterm-mux = {
        enable = true;
        config = {
          Label = "com.roshbhatia.wezterm-mux";
          ProgramArguments = [
            cfg.persistence.muxBinary
            "--config-file"
            muxConfigPath
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${config.home.homeDirectory}/.local/state/wezterm/mux.log";
          StandardErrorPath = "${config.home.homeDirectory}/.local/state/wezterm/mux.log";
        };
      };
    };
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      extraConfig = ''
        package.path = package.path .. ";${luaSource}/?.lua;${luaSource}/?/init.lua"
        return require("sysinit.pkg.bootstrap").build()
      '';
    };
    assertions = [
      {
        assertion = builtins.all (
          p:
          builtins.elem p.key [
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
        localDomain = if cfg.persistence.enable then "unix" else "local";
        persistence = {
          inherit (cfg.persistence) enable;
          state_dir = stateDir;
          socket_path = socketPath;
          mux_config = muxConfigPath;
          epoch_path = epochPath;
          scrollback_lines = 0;
          agent_resume = cfg.settings.agentResume or { };
          mux_binary = cfg.persistence.muxBinary;
          interval = 60;
        };
        picker.command = [ (lib.getExe runner) ];
      } cfg.settings
    );
    xdg.configFile."wezterm/env.json".text = builtins.toJSON cfg.environment;
  };
}
