# Ma trận control (Automation vs Manual)

| Nhóm | Control | Thực hiện | Ghi chú |
| --- | --- | --- | --- |
| Droplet | 2.1.1 Backups bật | Automation (doctl) | `scripts/bash/check_droplet.sh` |
| Droplet | 2.1.x Patch/upgrade policy | Automation (Ansible audit) + Manual lịch | `ansible/playbooks/02_audit.yml` |
| Firewall | 3.x Chỉ allow port cần thiết | Automation (doctl) | `scripts/bash/check_firewall.sh` |
| Spaces | 5.x Private by default | Automation (S3 API) | `scripts/bash/check_spaces.sh` |
| Volume | 6.x Encryption/mount options | Automation (doctl + SSH) | `scripts/bash/check_volume.sh` |
| IAM/Access | Member review, 2FA | Manual | `docs/manual_checklist.md` |
