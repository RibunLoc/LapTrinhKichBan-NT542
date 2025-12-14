package controls

import (
	"context"
	"fmt"
	"strings"

	"cisctl/internal/cisctl"
)

type Droplet215OSUpdate struct{}

func (Droplet215OSUpdate) ID() string    { return "2.1.5" }
func (Droplet215OSUpdate) Title() string { return "Ensure Periodic Security Updates are Configured" }

func (Droplet215OSUpdate) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
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

		updateLists, _ := sshCommand(deps, ip, `grep -Eq 'APT::Periodic::Update-Package-Lists\s+"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && echo yes || echo no`)
		unattended, _ := sshCommand(deps, ip, `grep -Eq 'APT::Periodic::Unattended-Upgrade\s+"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && echo yes || echo no`)
		timersEnabled, _ := sshCommand(deps, ip, `systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 && echo yes || echo no`)
		timersActive, _ := sshCommand(deps, ip, `systemctl is-active apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 && echo yes || echo no`)

		reasons := []string{}
		if pkg != "yes" {
			reasons = append(reasons, "unattended-upgrades not installed")
		}
		if updateLists != "yes" {
			reasons = append(reasons, "Update-Package-Lists not enabled")
		}
		if unattended != "yes" {
			reasons = append(reasons, "Unattended-Upgrade not enabled")
		}
		if timersEnabled != "yes" {
			reasons = append(reasons, "apt-daily timers not enabled")
		}
		if timersActive != "yes" {
			reasons = append(reasons, "apt-daily timers not active")
		}

		pass := len(reasons) == 0
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           ip,
			Pass:         pass,
			Evidence: map[string]string{
				"pkg_installed":         pkg,
				"update_package_lists":  updateLists,
				"unattended_upgrade":    unattended,
				"timers_enabled":        timersEnabled,
				"timers_active":         timersActive,
				"20auto_upgrades_found": "yes",
			},
		}

		if !pass {
			f.Reason = strings.Join(reasons, "; ")
			if deps.Log != nil {
				deps.Log.Errorf("%s: %s", d.Name, f.Reason)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s: periodic updates configured", d.Name)
		}

		out.Findings = append(out.Findings, f)
	}

	return out, nil
}

