# Control: Droplet 2.1.7 – Ensure only SSH keys are used for authentication (Automated)

## Mục tiêu
Tắt đăng nhập SSH bằng mật khẩu, chỉ cho phép đăng nhập bằng SSH key.

## Cách kiểm tra bằng SSH (manual)
```bash
ssh devops@<ip> "grep -E '^PasswordAuthentication|^PermitRootLogin' /etc/ssh/sshd_config || true"
```
Pass khi:
- `PasswordAuthentication no`
- (khuyến nghị) `PermitRootLogin no`

## Automation (repo)
- Chạy control: `scripts/bash/controls/droplet_2.1.7_only_sshkey.sh`
- Runner: `scripts/bash/run_cis_controls.sh`

## Evidence khi FAIL
- Dán output SSH.
