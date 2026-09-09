# sysinit.wezterm

WezTerm configuration with a live session tree and separate provider pickers.
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
  sessions = inputs.seshy.packages.${system}.provider-wezterm;
  folders = inputs.sysinit-wezterm.packages.${system}.provider-zoxide;
in {
  imports = [ inputs.sysinit-wezterm.homeManagerModules.default ];
  programs.sysinit-wezterm = {
    enable = true;
    settings.picker.providers = [
      { key = "!"; name = "tether"; manifest = "${hosts}/share/wezterm/providers/tether.json"; }
      { key = "@"; name = "seshy"; manifest = "${sessions}/share/wezterm/providers/seshy.json"; }
      { key = "#"; name = "zoxide"; manifest = "${folders}/share/wezterm/providers/zoxide.json"; }
    ];
  };
}
```

The host module supplies flake inputs through Home Manager's `extraSpecialArgs`.
Each registered shortcut also appears in the command palette.
Provider icons and row fields come from the provider response.

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

The runner writes one `provider/v1` request to standard input.
It accepts correlated event frames followed by one result frame.
Commands run as argument lists with a five-second limit.

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
Cancellation starts no process.

The [zoxide extra](extras/zoxide/README.md) includes its installation instructions and demo.
Host and session adapters live with [tether](https://github.com/roshbhatia/tether/tree/main/extras/wezterm)
and [seshy](https://github.com/roshbhatia/seshy/tree/main/extras/wezterm).

## Development

Run `nix flake check` for Lua configuration tests and picker transport tests.
Run `nix fmt` to format tracked Nix files.
The Home Manager module handles installation; Lua modules handle behavior; provider executables handle their own data sources.
