# Ma trận control (Automation vs Manual)

| Nhóm | Control | Thực hiện | Ghi chú |
| --- | --- | --- | --- |
| Droplet | 2.1.1 Backups bật | Automation (doctl) | `scripts/bash/controls/droplet_2.1.1_backups.sh` |
| Droplet | 2.1.2-2.1.3 Firewall | Automation (doctl) | `scripts/bash/controls/droplet_2.1.2_firewall_created.sh`, `scripts/bash/controls/droplet_2.1.3_connect_firewall.sh` |
| Droplet | 2.1.4-2.1.7 OS hardening/audit | Automation (SSH) | `scripts/bash/controls/droplet_2.1.4_os_upgrade.sh` … `scripts/bash/controls/droplet_2.1.7_only_sshkey.sh` |
| Droplet | 2.1.8 Unused SSH keys cleaned | Automation (doctl, có gate) | `scripts/bash/controls/droplet_2.1.8_unused_ssh_keys_clean.sh` |
| Monitoring | 2.2.1 Security history | Manual evidence (WARN nếu thiếu) | `scripts/bash/controls/monitoring_2.2.1_security_history_monitored.sh` |
| Monitoring | 2.2.2 Enable monitoring | Automation (doctl) | `scripts/bash/controls/monitoring_2.2.2_enable_monitoring.sh` |
| Spaces | 2.3.2-2.3.5 | Automation (S3 API) | `scripts/bash/controls/spaces_2.3.2_manage_access_key.sh` … `scripts/bash/controls/spaces_2.3.5_cdn_enabled.sh` |
| Spaces | 2.3.7 Destroy unused buckets | Automation (doctl, có gate) | `scripts/bash/controls/spaces_2.3.7_destroy_unused_buckets.sh` |
| Volume | 2.4.1 Encrypt at rest | Automation (doctl + SSH) | `scripts/bash/controls/volume_2.4.1_ensure_encrypt.sh` |
| IAM/Access | Member review, 2FA | Manual | `docs/manual_checklist.md` |

Chạy tất cả controls: `scripts/bash/run_cis_controls.sh`.
