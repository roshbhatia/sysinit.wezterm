# zmx

Attach a persistent terminal session from the session picker.

## Install

```sh
brew install roshbhatia/tap/sysinit-wezterm-provider-zmx
nix profile add 'github:roshbhatia/sysinit.wezterm#provider-zmx'
```

Install the core utility separately, or select its all-provider bundle. Runtime tools still need their own credentials.

Register this provider on `$`. It lists existing local Zmx sessions. Attach clears inherited ZMX_SESSION so it cannot switch another client.

## Demo

Live recording pending.

[Tape source](demo.tape) · [Task script](demo.sh)
