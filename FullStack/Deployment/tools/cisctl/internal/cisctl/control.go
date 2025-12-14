package cisctl

import "context"

type Control interface {
	ID() string
	Title() string
	Run(ctx context.Context, deps Deps) (ControlOutcome, error)
}

type ControlOutcome struct {
	Notes    string
	Findings []Finding
}

type Deps struct {
	Config Config
	DO     *DOClient
	SSH    *SSHRunner
	Log    *Logger
}

