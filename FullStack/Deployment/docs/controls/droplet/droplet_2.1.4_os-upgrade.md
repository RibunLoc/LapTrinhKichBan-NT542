# Control: Droplet 2.1.4 – Ensure OS upgrade policy is enabled (Automated)

## Mục tiêu
Đảm bảo droplet có chính sách tự động cập nhật bảo mật (vd: `unattended-upgrades` trên Ubuntu) để giảm rủi ro tồn đọng bản vá.

## Cách kiểm tra bằng CLI/SSH (manual)
```bash
ssh devops@<ip> "dpkg -s unattended-upgrades >/dev/null 2>&1 && echo installed || echo missing"
ssh devops@<ip> "cat /etc/apt/apt.conf.d/20auto-upgrades || true"
```
Pass khi:
- `unattended-upgrades` được cài
- `APT::Periodic::Unattended-Upgrade "1";` tồn tại

## Automation (repo)
- Chạy control: `scripts/bash/controls/droplet_2.1.4_os_upgrade.sh`
- Runner: `scripts/bash/run_cis_controls.sh`
- (Config) Ansible harden: `ansible/playbooks/01_harden.yml`

## Evidence khi FAIL
- Dán output SSH (các file config liên quan).
