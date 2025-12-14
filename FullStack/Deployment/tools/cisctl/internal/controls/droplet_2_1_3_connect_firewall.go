package controls

import (
	"context"
	"fmt"
	"strings"

	"cisctl/internal/cisctl"
)

type Droplet213ConnectFirewall struct{}

func (Droplet213ConnectFirewall) ID() string    { return "2.1.3" }
func (Droplet213ConnectFirewall) Title() string { return "Ensure Droplets are Connected to Firewall and VPC" }

func (Droplet213ConnectFirewall) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
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
		reasons := []string{}

		vpcUUID := strings.TrimSpace(d.VPCUUID)
		if vpcUUID == "" {
			reasons = append(reasons, "No VPC attached")
		}
		if !dropletFirewallCovered(d.ID, deps.Config.EnvTag, firewalls) {
			reasons = append(reasons, "No firewall attached")
		}

		pass := len(reasons) == 0
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           cisctl.DropletPublicIPv4(d),
			Pass:         pass,
			Evidence: map[string]string{
				"vpc_uuid": vpcUUID,
			},
		}
		if !pass {
			f.Reason = strings.Join(reasons, "; ")
			if deps.Log != nil {
				deps.Log.Errorf("%s: %s (id=%d)", d.Name, f.Reason, d.ID)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s connected to VPC+Firewall (id=%d)", d.Name, d.ID)
		}

		out.Findings = append(out.Findings, f)
	}

	return out, nil
}

