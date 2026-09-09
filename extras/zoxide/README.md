# zoxide

Find the checkout directory from visit history.

## Install

```sh
brew install roshbhatia/tap/sysinit-wezterm-provider-zoxide
nix profile add 'github:roshbhatia/sysinit.wezterm#provider-zoxide'
```

Install the core utility separately, or select its all-provider bundle. Runtime tools still need their own credentials.

## Demo

![Find the checkout directory from visit history](demo.gif)

[Tape source](demo.tape) · [Task script](demo.sh)

Run `nix develop -c bash extras/zoxide/demo.sh` to run the task without recording.
Run `nix develop -c python3 hack/extra-demos.py zoxide` to record it.
