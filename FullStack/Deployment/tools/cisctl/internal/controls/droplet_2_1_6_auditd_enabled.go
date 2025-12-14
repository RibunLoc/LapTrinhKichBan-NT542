package controls

import (
	"context"
	"fmt"
	"strings"

	"cisctl/internal/cisctl"
)

type Droplet216AuditdEnabled struct{}

func (Droplet216AuditdEnabled) ID() string    { return "2.1.6" }
func (Droplet216AuditdEnabled) Title() string { return "Ensure auditd is Enabled" }

func (Droplet216AuditdEnabled) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
	var out cisctl.ControlOutcome

	droplets, err := deps.DO.ListDropletsByTag(ctx, deps.Config.EnvTag)
	if err != nil {
		return out, err
	}
	if len(droplets) == 0 {
		out.Findings = append(out.Findings, cisctl.Finding{
			ResourceType: "droplet",
			Pass:         false,
			Reason:       fmt.Sprintf("No droplets found with tag %s", deps.Config.EnvTag),
		})
		return out, nil
	}

	for _, d := range droplets {
		ip := cisctl.DropletPublicIPv4(d)
		if strings.TrimSpace(ip) == "" {
			out.Findings = append(out.Findings, cisctl.Finding{
				ResourceType: "droplet",
				ResourceID:   fmt.Sprintf("%d", d.ID),
				ResourceName: d.Name,
				Pass:         false,
				Reason:       "No public IPv4 address",
			})
			continue
		}

		pkg, err := sshCommand(deps, ip, `dpkg -s auditd >/dev/null 2>&1 && echo yes || echo no`)
		if err != nil {
			out.Findings = append(out.Findings, cisctl.Finding{
				ResourceType: "droplet",
				ResourceID:   fmt.Sprintf("%d", d.ID),
				ResourceName: d.Name,
				IP:           ip,
				Pass:         false,
				Reason:       fmt.Sprintf("SSH unreachable: %v", err),
			})
			continue
		}

		enabled, _ := sshCommand(deps, ip, `systemctl is-enabled auditd >/dev/null 2>&1 && echo yes || echo no`)
		active, _ := sshCommand(deps, ip, `systemctl is-active auditd >/dev/null 2>&1 && echo yes || echo no`)

		reasons := []string{}
		if pkg != "yes" {
			reasons = append(reasons, "auditd package not installed")
		}
		if enabled != "yes" {
			reasons = append(reasons, "auditd service not enabled")
		}
		if active != "yes" {
			reasons = append(reasons, "auditd service not running")
		}

		pass := len(reasons) == 0
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           ip,
			Pass:         pass,
			Evidence: map[string]string{
				"pkg_installed":   pkg,
				"service_enabled": enabled,
				"service_active":  active,
			},
		}
		if !pass {
			f.Reason = strings.Join(reasons, "; ")
			if deps.Log != nil {
				deps.Log.Errorf("%s: %s", d.Name, f.Reason)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s: auditd enabled and running", d.Name)
		}

		out.Findings = append(out.Findings, f)
	}

	return out, nil
}

