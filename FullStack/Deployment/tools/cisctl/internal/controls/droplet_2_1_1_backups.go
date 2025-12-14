package controls

import (
	"context"
	"fmt"

	"cisctl/internal/cisctl"
)

type Droplet211Backups struct{}

func (Droplet211Backups) ID() string    { return "2.1.1" }
func (Droplet211Backups) Title() string { return "Ensure Backups are Enabled" }

func (Droplet211Backups) Run(ctx context.Context, deps cisctl.Deps) (cisctl.ControlOutcome, error) {
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
		hasBackups := cisctl.HasFeature(d, "backups")
		f := cisctl.Finding{
			ResourceType: "droplet",
			ResourceID:   fmt.Sprintf("%d", d.ID),
			ResourceName: d.Name,
			IP:           cisctl.DropletPublicIPv4(d),
			Pass:         hasBackups,
		}
		if !hasBackups {
			f.Reason = "Backups disabled"
			if deps.Log != nil {
				deps.Log.Errorf("%s backups disabled (id=%d)", d.Name, d.ID)
			}
		} else if deps.Log != nil {
			deps.Log.Infof("%s backups enabled (id=%d)", d.Name, d.ID)
		}
		out.Findings = append(out.Findings, f)
	}

	return out, nil
}

