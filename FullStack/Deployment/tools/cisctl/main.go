package main

import (
	"context"
	"os"

	"cisctl/internal/cisctl"
	"cisctl/internal/controls"
)

func main() {
	app := cisctl.NewApp(controls.All())
	os.Exit(app.Run(context.Background(), os.Args[1:]))
}

