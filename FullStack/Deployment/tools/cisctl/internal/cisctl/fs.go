package cisctl

import (
	"os"
	"path/filepath"
)

func FindDeploymentRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		return "."
	}
	dir := wd
	for {
		// Marker file: scripts/common/doctl_helpers.sh
		marker := filepath.Join(dir, "scripts", "common", "doctl_helpers.sh")
		if _, err := os.Stat(marker); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return wd
}

