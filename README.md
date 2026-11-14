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
The tree and provider views start with `j/k` navigation; `/` starts filtering.
Cmd+S opens a centered picker in the tab's single floating pane, creating or
showing it as needed. Each invocation resets the float to 60% of the tab's width
and height. The existing float's process stays running beneath the picker.
Escape returns to the original pane; opening a target dismisses the popup first.
Set `programs.sysinit-wezterm.settings.picker.placement` to `"float"` (default),
`"auto"`, `"pane"`, or `"window"`. Set `picker.float_size` to a fraction greater
than zero and at most one to change the default popup size. Auto draws selectors
inside a focused floating pane and uses the full window from a normal pane.
This requires the WezTerm fork's
`InputSelector.scope` support.

## Session recovery

Set `programs.sysinit-wezterm.persistence.enable = true` to enable a persistent
local Unix mux and whole-session snapshots. Normal application startup reattaches
to surviving processes. When the mux has restarted, recovery rebuilds the saved
workspaces, windows, split layouts, directories, active workspace, and tab-local
floating panes. Explicit launch commands open their requested context.

Snapshots contain layout metadata, not terminal output or commands to replay.
Applications need their own resume support after the host running them reboots.
The snapshot is saved on focus changes and every 60 seconds, with an atomic write
and a previous-snapshot backup. Unreachable remote workspaces remain in the saved
session for a later restore. Existing workspace-manager snapshots remain intact.

The command palette provides `Session: save recovery snapshot`, `Session: restore
last session`, and `Session: restore saved workspace`. The live session tree and
the seshy and zmx providers retain their existing ownership.

Set `programs.sysinit-wezterm.persistence.service = true` on managed remote hosts
to run the mux as a systemd user service or macOS LaunchAgent. Linux hosts also
need user lingering. Point the corresponding SSH domains' `remote_wezterm_path`
at `wezterm-remote`, the generated wrapper for the headless configuration. Use the
same WezTerm fork revision on clients and servers. Stop the service only when its
running jobs can end.

Recovery uses the Nix-pinned
[StephenGemin/resurrect.wezterm](https://github.com/StephenGemin/resurrect.wezterm)
serializer and split restoration, with adapters for whole sessions and floating
panes. Its built-in UI and timers are replaced by this configuration's integration.

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

On the sysinit WezTerm fork, Cmd+F creates or toggles one floating pane owned
by the current tab. Click outside or press Cmd+F to hide it; its process keeps
running. Each tab keeps its own shell and directory. There is no global floating
shortcut or shortcut to create additional floats. The command palette also
exposes actions to move a floating pane back to a horizontal or vertical split.
The toggle is omitted on builds without floating-pane support.
On Linux, use Super (the Windows key) in place of Cmd for these floating controls;
these chords do not use the Alt modifier owned by the window manager.

Cmd+Ctrl+J shrinks both floating-pane dimensions by approximately 5%; Cmd+Ctrl+K
grows both. Scaling preserves the current proportions and stops at the shared
size limit. Cmd+Ctrl+Left/Right narrows or widens the active floating pane by three columns;
Cmd+Ctrl+Up/Down decreases or increases its height by three rows. The existing
Ctrl+Shift+H/L and K/J pane-resize chords also work at a shell prompt. Resizing
keeps the floating pane centered and preserves its size when hidden and restored.

The parent tab keeps its underlying pane's directory label. An F badge indicates
a floating pane. The badge uses the accent color while a float is visible in the
selected tab, and a muted color when hidden or in another tab. Floats use an opaque background, a
thin theme-accent border, and an even content inset. The window title follows
the focused process.

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

## Keyboard policy and platform audit

The Ctrl pane workflow is intentional. Ctrl+G toggles locked mode, in which
main-map shortcuts pass their original key to the application. Ctrl+G itself
remains available to unlock. Editor and TUI passthrough rules remain in place.
Copy/search modes retain their native modal controls; Escape exits them.
Alt is reserved for the i3-style window manager; the default, copy-mode, and
search-mode tables define no Alt shortcuts. Inherited copy-mode Alt aliases
are removed; Vim word navigation and search-mode exit keys are retained. Terminal shortcuts remain custom where the Ctrl workflow takes
priority over upstream defaults.

| Operation | macOS | Linux |
| --- | --- | --- |
| Copy / paste | Cmd+C / Cmd+V | Ctrl+Shift+C / Ctrl+Shift+V |
| New tab on current host | Cmd+T, Ctrl+T | Ctrl+Shift+T, Ctrl+T |
| New local tab | Cmd+Shift+T, Ctrl+Shift+T | Super+Shift+T |
| New window / local window | Cmd+N / Cmd+Shift+N | Ctrl+Shift+N / Super+Shift+N |
| Find scrollback | Cmd+/, Ctrl+/ | Ctrl+Shift+F, Ctrl+/ |
| Reload configuration | Cmd+R | Ctrl+Shift+R |
| Rename tab | Cmd+Shift+R, Ctrl+Shift+R | Super+Shift+R |
| Command palette | Cmd+Shift+P, Cmd+; | Ctrl+Shift+P, Ctrl+; |
| Copy mode | Ctrl+Shift+X, Ctrl+Escape | Ctrl+Shift+X, Ctrl+Escape |
| Pane selector | Cmd+Ctrl+P, Ctrl+Shift+F | Super+Ctrl+P |
| Select tab 1–9 | Cmd+1–9, Ctrl+1–9 | Ctrl+Shift+1–9; Ctrl/Super+1–9 aliases |
| Select terminal workspace | Cmd+Ctrl+Shift+digit; Ctrl+Shift+digit alias | Super+Ctrl+Shift+digit |
| Fullscreen | Cmd+Ctrl+F | F11 |
| Reset font size | Cmd+0, Ctrl+0 | Ctrl+0, Super+0 |
| Toggle tab-local float | Cmd+F | Super+F |
| Proportional float resize | Cmd+Ctrl+J/K | Super+Ctrl+J/K |
| Precision pane resize | Cmd+Ctrl+arrows, Ctrl+Shift+H/J/K/L | Super+Ctrl+arrows, Ctrl+Shift+H/J/K/L |
| Split down / right on current host | Ctrl+S / Ctrl+V | Ctrl+S / Ctrl+V |
| Split down / right locally | Ctrl+Shift+S / Ctrl+Shift+V; Cmd+Shift+V alias | Ctrl+Shift+S / Super+Shift+V |
| Close or detach | Cmd+W, Ctrl+W | Super+W, Ctrl+W |
| Close focused pane immediately | Cmd+Shift+W, Ctrl+Shift+W | Super+Shift+W, Ctrl+Shift+W |

The close picker offers Close to end the focused pane's process, or Detach to
disconnect this GUI from the pane's mux domain while keeping its sessions running.
Esc cancels. Ctrl+W still deletes a word inside picker filters.

Ctrl+H/J/K/L pane navigation, Ctrl+M zoom, Ctrl+N rotation, Ctrl+F quick select,
Ctrl+Tab tab cycling, Ctrl+Shift+comma/period tab movement, and Ctrl+G locked
mode keep their existing meanings. Cmd/Super+S opens the session tree;
Cmd/Super+Ctrl+Shift+W opens the worker watcher; Cmd/Super+Shift+B opens the bus
watcher; Cmd/Super+Shift+L opens theme controls. These custom shortcuts remain
reachable without Alt.

Workspace shortcuts avoid Cmd/Super+Shift+3/4/5 screenshots on both platforms.
The Linux map also avoids Sway's Ctrl+Shift+Left/Right workspace cycling.
macOS application hide/minimize/quit shortcuts are not installed as Linux Super+H/M/Q actions, because Sway owns
those keys. Linux uses Ctrl+Shift+Q to quit. The registry is checked for
duplicate chords, Linux clipboard/search/window behavior, floating action
selection, and locked-mode passthrough in `checks/wezterm.lua`.
