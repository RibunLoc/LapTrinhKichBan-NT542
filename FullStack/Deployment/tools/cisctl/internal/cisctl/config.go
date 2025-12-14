package cisctl

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	RootDir string
	EnvTag  string

	LogDir    string
	ReportDir string

	DOAccessToken string

	SSHUser        string
	SSHUserFallback string
	SSHKeyPath     string
	SSHPort        int
	SSHTimeout     time.Duration
}

func LoadConfig(rootDir string, envTagFlag string) (Config, error) {
	cfg := Config{
		RootDir:        rootDir,
		EnvTag:         "env:demo",
		LogDir:         filepath.Join(rootDir, "logs"),
		ReportDir:      filepath.Join(rootDir, "reports"),
		SSHUser:        "devops",
		SSHUserFallback: "root",
		SSHPort:        22,
		SSHTimeout:     10 * time.Second,
	}

	if v := strings.TrimSpace(envTagFlag); v != "" {
		cfg.EnvTag = v
	} else if v := strings.TrimSpace(os.Getenv("ENV_TAG")); v != "" {
		cfg.EnvTag = v
	}

	cfg.DOAccessToken = firstNonEmpty(
		os.Getenv("DO_ACCESS_TOKEN"),
		os.Getenv("DIGITALOCEAN_ACCESS_TOKEN"),
		os.Getenv("TF_VAR_do_token"),
	)
	if cfg.DOAccessToken == "" {
		return Config{}, errors.New("missing DO access token (set DO_ACCESS_TOKEN or DIGITALOCEAN_ACCESS_TOKEN)")
	}

	if v := strings.TrimSpace(os.Getenv("LOG_DIR")); v != "" {
		cfg.LogDir = v
	}
	if v := strings.TrimSpace(os.Getenv("REPORT_DIR")); v != "" {
		cfg.ReportDir = v
	}

	if v := strings.TrimSpace(os.Getenv("SSH_USER")); v != "" {
		cfg.SSHUser = v
	}
	if v := strings.TrimSpace(os.Getenv("SSH_USER_FALLBACK")); v != "" {
		cfg.SSHUserFallback = v
	}
	if v := strings.TrimSpace(os.Getenv("SSH_KEY_PATH")); v != "" {
		cfg.SSHKeyPath = v
	}
	if v := strings.TrimSpace(os.Getenv("SSH_PORT")); v != "" {
		if port, err := strconv.Atoi(v); err == nil && port > 0 && port < 65536 {
			cfg.SSHPort = port
		}
	}
	if v := strings.TrimSpace(os.Getenv("SSH_TIMEOUT_SECONDS")); v != "" {
		if secs, err := strconv.Atoi(v); err == nil && secs > 0 {
			cfg.SSHTimeout = time.Duration(secs) * time.Second
		}
	}

	return cfg, nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

