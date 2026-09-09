package main

import (
	"os"

	"github.com/roshbhatia/sysinit.wezterm/internal/wezspawn"
)

func main() {
	os.Exit(wezspawn.Run(os.Args[1:]))
}
