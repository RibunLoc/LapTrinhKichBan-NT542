package cisctl

import (
	"encoding/json"
	"os"
	"time"
)

type ToolInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type Report struct {
	Timestamp time.Time       `json:"timestamp"`
	EnvTag    string          `json:"env_tag"`
	RootDir   string          `json:"root_dir"`
	Tool      ToolInfo        `json:"tool"`
	Summary   Summary         `json:"summary"`
	Results   []ControlResult `json:"results"`
}

type Summary struct {
	Total int `json:"total"`
	Pass  int `json:"pass"`
	Fail  int `json:"fail"`
}

type ControlResult struct {
	ControlID  string    `json:"control_id"`
	Title      string    `json:"title"`
	Pass       bool      `json:"pass"`
	Error      string    `json:"error,omitempty"`
	Notes      string    `json:"notes,omitempty"`
	LogPath    string    `json:"log_path,omitempty"`
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at"`
	Findings   []Finding `json:"findings,omitempty"`
}

type Finding struct {
	ResourceType string            `json:"resource_type"`
	ResourceID   string            `json:"resource_id,omitempty"`
	ResourceName string            `json:"resource_name,omitempty"`
	IP           string            `json:"ip,omitempty"`
	Pass         bool              `json:"pass"`
	Reason       string            `json:"reason,omitempty"`
	Evidence     map[string]string `json:"evidence,omitempty"`
}

func Summarize(results []ControlResult) Summary {
	s := Summary{Total: len(results)}
	for _, r := range results {
		if r.Pass {
			s.Pass++
		} else {
			s.Fail++
		}
	}
	return s
}

func WriteJSONFile(path string, v any) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

