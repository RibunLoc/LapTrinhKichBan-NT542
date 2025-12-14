package cisctl

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

type SSHRunner struct {
	user         string
	userFallback string
	port         int
	timeout      time.Duration

	keyPath string
	signer  ssh.Signer
	initErr error
}

func NewSSHRunner(cfg Config) (*SSHRunner, error) {
	r := &SSHRunner{
		user:         cfg.SSHUser,
		userFallback: cfg.SSHUserFallback,
		port:         cfg.SSHPort,
		timeout:      cfg.SSHTimeout,
		keyPath:      cfg.SSHKeyPath,
	}

	if strings.TrimSpace(r.keyPath) == "" {
		r.initErr = errors.New("SSH_KEY_PATH not set")
		return r, nil
	}

	expanded, err := expandPath(r.keyPath)
	if err != nil {
		r.initErr = err
		return r, nil
	}
	r.keyPath = expanded

	keyBytes, err := os.ReadFile(r.keyPath)
	if err != nil {
		r.initErr = err
		return r, nil
	}
	signer, err := ssh.ParsePrivateKey(keyBytes)
	if err != nil {
		r.initErr = err
		return r, nil
	}
	r.signer = signer
	return r, nil
}

func (r *SSHRunner) RunCommand(ip string, cmd string) (string, error) {
	if r == nil {
		return "", errors.New("ssh runner is nil")
	}
	if r.initErr != nil {
		return "", r.initErr
	}

	out, err := r.runWithUser(ip, r.user, cmd)
	if err == nil {
		return out, nil
	}
	if r.userFallback != "" && r.userFallback != r.user {
		out2, err2 := r.runWithUser(ip, r.userFallback, cmd)
		if err2 == nil {
			return out2, nil
		}
		return out2, fmt.Errorf("ssh failed with %s and %s: %w", r.user, r.userFallback, err2)
	}
	return out, err
}

func (r *SSHRunner) runWithUser(ip string, user string, cmd string) (string, error) {
	addr := fmt.Sprintf("%s:%d", ip, r.port)
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(r.signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         r.timeout,
	}

	client, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return "", err
	}
	defer client.Close()

	sess, err := client.NewSession()
	if err != nil {
		return "", err
	}
	defer sess.Close()

	b, err := sess.CombinedOutput(cmd)
	out := strings.TrimSpace(string(b))
	if err != nil {
		return out, err
	}
	return out, nil
}

func expandPath(p string) (string, error) {
	p = strings.TrimSpace(p)
	if p == "" {
		return "", errors.New("empty path")
	}

	if strings.HasPrefix(p, "~"+string(os.PathSeparator)) || strings.HasPrefix(p, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		p = filepath.Join(home, strings.TrimPrefix(strings.TrimPrefix(p, "~"+string(os.PathSeparator)), "~/"))
	}

	p = filepath.FromSlash(p)
	return filepath.Clean(p), nil
}

