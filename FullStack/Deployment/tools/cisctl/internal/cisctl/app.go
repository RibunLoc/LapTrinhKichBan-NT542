package cisctl

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

type App struct {
	controls []Control
}

func NewApp(controls []Control) *App {
	return &App{controls: controls}
}

func (a *App) Run(ctx context.Context, args []string) int {
	if len(args) == 0 {
		a.printUsage()
		return 2
	}

	switch args[0] {
	case "help", "-h", "--help":
		a.printUsage()
		return 0
	case "list":
		return a.runList()
	case "run":
		return a.runRun(ctx, args[1:])
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n\n", args[0])
		a.printUsage()
		return 2
	}
}

func (a *App) runList() int {
	controls := slices.Clone(a.controls)
	slices.SortFunc(controls, func(a Control, b Control) int {
		return strings.Compare(a.ID(), b.ID())
	})
	for _, c := range controls {
		fmt.Printf("%s\t%s\n", c.ID(), c.Title())
	}
	return 0
}

func (a *App) runRun(ctx context.Context, args []string) int {
	fs := flag.NewFlagSet("cisctl run", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	var (
		flagRoot     = fs.String("root", "", "Deployment root directory (defaults to auto-detect)")
		flagEnvTag   = fs.String("env-tag", "", "DigitalOcean tag name to scope droplets (defaults ENV_TAG or env:demo)")
		flagControls = fs.String("controls", "", "Comma-separated list of control IDs (default: all)")
		flagDotEnv   = fs.String("dotenv", "", "Path to .env file (default: <root>/.env if exists)")
		flagJSON     = fs.Bool("json", false, "Print JSON report to stdout")
	)

	if err := fs.Parse(args); err != nil {
		return 2
	}

	rootDir := strings.TrimSpace(*flagRoot)
	if rootDir == "" {
		rootDir = FindDeploymentRoot()
	}
	rootDir, _ = filepath.Abs(rootDir)

	dotEnvPath := strings.TrimSpace(*flagDotEnv)
	if dotEnvPath == "" {
		dotEnvPath = filepath.Join(rootDir, ".env")
	}
	_ = LoadDotEnv(dotEnvPath)

	cfg, err := LoadConfig(rootDir, *flagEnvTag)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Config error: %v\n", err)
		return 2
	}

	selectedControls := a.controls
	if strings.TrimSpace(*flagControls) != "" {
		want := map[string]bool{}
		for _, id := range strings.Split(*flagControls, ",") {
			id = strings.TrimSpace(id)
			if id == "" {
				continue
			}
			want[id] = true
		}
		filtered := make([]Control, 0, len(a.controls))
		for _, c := range a.controls {
			if want[c.ID()] {
				filtered = append(filtered, c)
			}
		}
		selectedControls = filtered
		if len(selectedControls) == 0 {
			fmt.Fprintf(os.Stderr, "No controls matched: %s\n", *flagControls)
			return 2
		}
	}

	if err := os.MkdirAll(cfg.LogDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create log dir: %v\n", err)
		return 2
	}
	if err := os.MkdirAll(cfg.ReportDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create report dir: %v\n", err)
		return 2
	}

	doClient, err := NewDOClient(cfg.DOAccessToken)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to init DO client: %v\n", err)
		return 2
	}

	sshRunner, err := NewSSHRunner(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to init SSH runner: %v\n", err)
		return 2
	}

	startedAt := time.Now().UTC()
	report := Report{
		Timestamp: startedAt,
		EnvTag:    cfg.EnvTag,
		RootDir:   cfg.RootDir,
		Tool: ToolInfo{
			Name:    "cisctl",
			Version: "0.1.0",
		},
	}

	overallFail := false
	for _, c := range selectedControls {
		result := a.runOneControl(ctx, cfg, doClient, sshRunner, c)
		report.Results = append(report.Results, result)
		if !result.Pass {
			overallFail = true
		}
	}

	report.Summary = Summarize(report.Results)

	reportPath := filepath.Join(cfg.ReportDir, fmt.Sprintf("cisctl_report_%s.json", startedAt.Format("20060102150405")))
	if err := WriteJSONFile(reportPath, report); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write report: %v\n", err)
		return 2
	}

	if *flagJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(report)
	} else {
		fmt.Printf("\nReport: %s\n", reportPath)
	}

	if overallFail {
		return 1
	}
	return 0
}

func (a *App) runOneControl(ctx context.Context, cfg Config, doClient *DOClient, sshRunner *SSHRunner, c Control) ControlResult {
	controlStart := time.Now().UTC()
	logger, logPath, err := NewControlLogger(cfg.LogDir, c.ID(), controlStart)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to init logger for %s: %v\n", c.ID(), err)
	}

	deps := Deps{
		Config: cfg,
		DO:     doClient,
		SSH:    sshRunner,
		Log:    logger,
	}

	if logger != nil {
		logger.Infof("START %s - %s (env_tag=%s)", c.ID(), c.Title(), cfg.EnvTag)
	}
	fmt.Printf("[%s] %s ...\n", c.ID(), c.Title())

	outcome, runErr := c.Run(ctx, deps)
	finishedAt := time.Now().UTC()

	result := ControlResult{
		ControlID:  c.ID(),
		Title:      c.Title(),
		StartedAt:  controlStart,
		FinishedAt: finishedAt,
		LogPath:    logPath,
		Notes:      outcome.Notes,
	}

	if runErr != nil {
		result.Pass = false
		result.Error = runErr.Error()
		result.Findings = append(result.Findings, Finding{
			ResourceType: "control",
			Pass:         false,
			Reason:       runErr.Error(),
		})
	} else {
		result.Findings = outcome.Findings
		result.Pass = true
		for _, f := range outcome.Findings {
			if !f.Pass {
				result.Pass = false
				break
			}
		}
	}

	if logger != nil {
		if result.Pass {
			logger.Infof("PASS %s", c.ID())
		} else {
			logger.Errorf("FAIL %s", c.ID())
		}
		logger.Infof("END %s duration=%s", c.ID(), finishedAt.Sub(controlStart).String())
	}

	if result.Pass {
		fmt.Printf("  PASS [%s]\n", c.ID())
	} else {
		fmt.Printf("  FAIL [%s]\n", c.ID())
		failCount := 0
		for _, f := range result.Findings {
			if !f.Pass {
				failCount++
				if failCount > 5 {
					fmt.Printf("  ... and more (see %s)\n", logPath)
					break
				}
				if f.ResourceName != "" {
					fmt.Printf("  - %s: %s\n", f.ResourceName, f.Reason)
				} else {
					fmt.Printf("  - %s\n", f.Reason)
				}
			}
		}
	}
	return result
}

func (a *App) printUsage() {
	fmt.Print(`cisctl - DigitalOcean CIS demo checks

Usage:
  cisctl list
  cisctl run [--root <dir>] [--env-tag <tag>] [--controls <ids>] [--dotenv <path>] [--json]

Examples (run from FullStack/Deployment):
  go run ./tools/cisctl list
  go run ./tools/cisctl run --env-tag env:demo
  go run ./tools/cisctl run --controls 2.1.1,2.1.6
`)
}

