package controls

import (
	"strings"

	"cisctl/internal/cisctl"
)

func sshCommand(deps cisctl.Deps, ip string, cmd string) (string, error) {
	out, err := deps.SSH.RunCommand(ip, cmd)
	return strings.TrimSpace(out), err
}

