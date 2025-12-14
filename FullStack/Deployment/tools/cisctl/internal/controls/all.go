package controls

import "cisctl/internal/cisctl"

func All() []cisctl.Control {
	return []cisctl.Control{
		Droplet211Backups{},
		Droplet212FirewallCreated{},
		Droplet213ConnectFirewall{},
		Droplet214OSUpgrade{},
		Droplet215OSUpdate{},
		Droplet216AuditdEnabled{},
	}
}

