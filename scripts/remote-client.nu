def --wrapped main [binary: path, config: path, ...arguments: string] {
    let state = $env.HOME | path join .local state wezterm
    mkdir $state
    $env.WEZTERM_UNIX_SOCKET = $state | path join mux.sock
    let forwarded = if ($arguments | is-empty) or $arguments.0 in [attach list ui --help -h] {
        [remote] | append $arguments
    } else {
        $arguments
    }
    exec $binary --config-file $config ...$forwarded
}
