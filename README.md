# sysinit.wezterm

WezTerm configuration composed from standalone plugins and pinned upstream integrations.

- [session-tree.wezterm](https://github.com/roshbhatia/session-tree.wezterm) owns the live tree and provider runner.
- [spawn.wezterm](https://github.com/roshbhatia/spawn.wezterm) owns host-aware spawn actions and the `wezspawn` CLI.
- [smart-keys.wezterm](https://github.com/roshbhatia/smart-keys.wezterm) owns application passthrough and the navigation boundary callback.

This repository owns the theme, key assignments, agent adapters, Nix module, and Zmx/zoxide provider packages.
Each plugin also supports plain Lua installation without this configuration.

`lib.luaSource pkgs` returns the assembled Lua source, including pinned plugin modules.
`packages.<system>.wezspawn` remains a compatibility alias for spawn.wezterm's CLI.
The tree shows running workspaces, tabs, and panes.
Provider shortcuts open another selector without adding inactive entries to the tree.

## Nix

Add `github:roshbhatia/sysinit.wezterm` as a flake input and import its `homeManagerModules.default` output.
Enable `programs.sysinit-wezterm.enable`. The default shell is the packaged zsh.
Set `settings.shell` to an argument list to select another shell.
`settings.posixShell` controls the `SHELL` environment variable independently.
Set colors, terminal behavior, and machine paths through `programs.sysinit-wezterm.settings`.

Register the providers you want:

```nix
{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  hosts = inputs.tether.packages.${system}.provider-wezterm;
  terminals = inputs.sysinit-wezterm.packages.${system}.provider-zmx;
  sessions = inputs.seshy.packages.${system}.provider-wezterm;
  folders = inputs.sysinit-wezterm.packages.${system}.provider-zoxide;
in {
  imports = [ inputs.sysinit-wezterm.homeManagerModules.default ];
  programs.sysinit-wezterm = {
    enable = true;
    settings.picker.providers = [
      { key = "@"; name = "tether"; manifest = "${hosts}/share/wezterm/providers/tether.json"; }
      { key = "#"; name = "zmx"; manifest = "${terminals}/share/wezterm/providers/zmx.json"; }
      { key = "$"; name = "seshy"; manifest = "${sessions}/share/wezterm/providers/seshy.json"; }
      { key = "%"; name = "zoxide"; manifest = "${folders}/share/wezterm/providers/zoxide.json"; }
    ];
  };
}
```

The host module supplies flake inputs through Home Manager's `extraSpecialArgs`.
Each registered shortcut also appears in the command palette.
Provider icons and row fields come from the provider response.

The header groups providers, navigation, and actions. Provider order follows
configuration order after the built-in `!` WezTerm provider.
After `!` WezTerm, scope decreases: `@` Tether hosts, `#` Zmx sessions, `$` Seshy projects, and `%` zoxide folders.

`!` lists the default workspace and native sessions created through this picker.
Choose `New session` and enter a name to start the configured shell at home.
These sessions create no directories or worktrees. Their lifetime follows the running WezTerm workspace.

Opening the tree refreshes provider catalogs in the background.
Cached lists appear immediately; refreshes never replace an active selection or its filter.
Cold loads show a cancellable loading view. No provider discovery runs from status ticks.
Opening a selected item still asks its provider for a current process plan.

Ctrl+V splits right, Ctrl+S splits down, and Ctrl+T opens a tab on the current
host. Add Shift to use the local host. These chords take priority over shell
widgets and application bindings; locked mode passes them through.

Native mux panes retain their domain. SSH processes reconnect with their
destination and connection options, without replaying remote commands or
explicit port forwards. Mosh clients retain their original `user@host` target.
If Mosh's process title does not expose an unambiguous target, the action reports
an error instead of opening a pane on the wrong host.

The [Zmx provider](extras/zmx/README.md) attaches existing local persistent sessions.

## Window launcher

`wezspawn` opens a window in the focused workspace and directory. With no attached
GUI, it starts WezTerm. Install it separately with
`nix profile install github:roshbhatia/sysinit.wezterm#wezspawn`, or use the `full` package.
Run `wezspawn --help` for executable and application-path options.

## Providers

A provider manifest declares an executable argument list and these actions:

| Action | Output |
|---|---|
| `picker.describe` | Selector title and Nerd Font icon name |
| `picker.list` | Ordered items with stable IDs and display segments |
| `picker.open` | A process plan for the selected ID |
| `picker.create` (optional) | A process plan for creating a named session |

The runner writes one `provider/v1` request to standard input.
It accepts correlated event frames followed by one result frame.
Commands run as argument lists with a five-second limit.

The manifest advertises creation by including `actions["picker.create"]`.
The optional description field `create` supplies `label` and `prompt` strings.
The picker sends `input.name` after name entry; cancellation sends no creation request.
Providers without the action get no creation entry.

Creation returns the same spawn plan as opening. An interactive creator runs in the new terminal.
`WEZTERM_PICKER_SHELL` contains the configured shell argument list as JSON.
The provider helper can execute that shell after creation finishes.
Seshy's helper runs `sy new`, preserves repository selection, and exits on cancellation without opening a shell.

An item can render several fields in one row:

```json
{
  "id": "token-review",
  "segments": [
    { "text": "token-review", "role": "name" },
    { "text": "~/work/checkout-service", "role": "path" },
    { "text": "2 repositories", "role": "detail" }
  ]
}
```

The provider decides the fields and order. The UI renders names in bold and details with lower intensity.
It removes control characters from display text.

Opening an item returns an absolute working directory, command arguments, environment variables, and a workspace label.
An empty command uses WezTerm's configured shell.
A host connection runs its foreground command in a local pane.
Cancelling a selection creates no terminal or session.

The [zoxide extra](extras/zoxide/README.md) includes its installation instructions and demo.
Host and session adapters live with [tether](https://github.com/roshbhatia/tether/tree/main/extras/wezterm)
and [seshy](https://github.com/roshbhatia/seshy/tree/main/extras/wezterm).

## Development

Run `nix flake check` for Lua configuration tests and picker transport tests.
Run `nix fmt` to format tracked Nix files.
The Home Manager module handles installation; Lua modules handle behavior; provider executables handle their own data sources.
