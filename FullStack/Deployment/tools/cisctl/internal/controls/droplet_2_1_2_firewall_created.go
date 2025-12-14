package controls

import (
	"context"
	"fmt"

	"cisctl/internal/cisctl"
)

type Droplet212FirewallCreated struct{}

func (Droplet212FirewallCreated) ID() string    { return "2.1.2" }
func (Droplet212FirewallCreated) Title() string { return "Ensure a Firewall is Created" }

func (Droplet212FirewallCreated) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
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

	firewalls, err := deps.DO.ListFirewalls(ctx)
	if err != nil {
		return out, err
	}

	for _, d := range droplets {
		covered := dropletFirewallCovered(d.ID, deps.Config.EnvTag, firewalls)
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           cisctl.DropletPublicIPv4(d),
			Pass:         covered,
		}
		if !covered {
			f.Reason = "No firewall attached"
			if deps.Log != nil {
				deps.Log.Errorf("%s not protected by any firewall (id=%d)", d.Name, d.ID)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s firewall coverage OK (id=%d)", d.Name, d.ID)
		}
		out.Findings = append(out.Findings, f)
	}

	return out, nil
}
