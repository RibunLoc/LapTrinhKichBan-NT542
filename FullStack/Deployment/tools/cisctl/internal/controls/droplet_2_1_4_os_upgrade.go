package controls

import (
	"context"
	"fmt"
	"strings"

	"cisctl/internal/cisctl"
)

type Droplet214OSUpgrade struct{}

func (Droplet214OSUpgrade) ID() string    { return "2.1.4" }
func (Droplet214OSUpgrade) Title() string { return "Ensure OS Upgrade Policy (unattended-upgrades enabled)" }

func (Droplet214OSUpgrade) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
	out := cisctl.ControlOutcome{
		Notes: "Manual evidence of major/minor upgrade policy may still be required.",
	}

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

		pkg, err := sshCommand(deps, ip, `dpkg -s unattended-upgrades >/dev/null 2>&1 && echo yes || echo no`)
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

		enabled, err := sshCommand(deps, ip, `grep -Eq 'APT::Periodic::Unattended-Upgrade\s+"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && echo yes || echo no`)
		if err != nil {
			out.Findings = append(out.Findings, cisctl.Finding{
				ResourceType: "droplet",
				ResourceID:   fmt.Sprintf("%d", d.ID),
				ResourceName: d.Name,
				IP:           ip,
				Pass:         false,
				Reason:       fmt.Sprintf("SSH command failed: %v", err),
			})
			continue
		}

		reasons := []string{}
		if pkg != "yes" {
			reasons = append(reasons, "unattended-upgrades not installed")
		}
		if enabled != "yes" {
			reasons = append(reasons, "unattended-upgrades not enabled")
		}

		pass := len(reasons) == 0
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           ip,
			Pass:         pass,
			Evidence: map[string]string{
				"pkg_installed": pkg,
				"enabled":       enabled,
			},
		}
		if !pass {
			f.Reason = strings.Join(reasons, "; ")
			if deps.Log != nil {
				deps.Log.Errorf("%s: %s", d.Name, f.Reason)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s: unattended-upgrades installed+enabled", d.Name)
		}

		out.Findings = append(out.Findings, f)
	}

	return out, nil
}

