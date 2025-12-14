package controls

import (
	"cisctl/internal/cisctl"

	"github.com/digitalocean/godo"
)

func firewallCoversTag(firewalls []godo.Firewall, tag string) bool {
	for _, fw := range firewalls {
		if cisctl.HasString(fw.Tags, tag) {
			return true
		}
	}
	return false
}

func dropletInAnyFirewall(dropletID int, firewalls []godo.Firewall) bool {
	for _, fw := range firewalls {
		for _, id := range fw.DropletIDs {
			if id == dropletID {
				return true
			}
		}
	}
	return false
}

func dropletFirewallCovered(dropletID int, envTag string, firewalls []godo.Firewall) bool {
	return firewallCoversTag(firewalls, envTag) || dropletInAnyFirewall(dropletID, firewalls)
}

