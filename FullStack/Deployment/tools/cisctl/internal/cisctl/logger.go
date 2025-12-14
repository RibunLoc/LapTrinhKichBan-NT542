package cisctl

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

type Logger struct {
	l *log.Logger
}

func NewControlLogger(logDir string, controlID string, t time.Time) (*Logger, string, error) {
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return nil, "", err
	}
	path := filepath.Join(logDir, fmt.Sprintf("cisctl_%s_%s.log", sanitize(controlID), t.Format("20060102150405")))
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, "", err
	}
	l := log.New(f, "", log.LstdFlags|log.LUTC)
	return &Logger{l: l}, path, nil
}

func (l *Logger) Infof(format string, args ...any) {
	if l == nil || l.l == nil {
		return
	}
	l.l.Printf("[INFO] "+format, args...)
}

func (l *Logger) Errorf(format string, args ...any) {
	if l == nil || l.l == nil {
		return
	}
	l.l.Printf("[ERROR] "+format, args...)
}

func sanitize(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z':
			out = append(out, r)
		case r >= 'A' && r <= 'Z':
			out = append(out, r)
		case r >= '0' && r <= '9':
			out = append(out, r)
		case r == '.' || r == '_' || r == '-':
			out = append(out, r)
		default:
			out = append(out, '_')
		}
	}
	return string(out)
}

