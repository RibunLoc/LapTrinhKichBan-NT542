# Control: Droplet 2.1.7 – Chỉ cho phép SSH key, cấm password

## Mục tiêu
SSH chỉ chấp nhận khóa công khai; không dùng mật khẩu; không cho phép root login qua password.

## Cách kiểm automation
- Script: `SSH_TARGET=root@<ip> ./scripts/bash/check_droplet.sh` sẽ grep `PasswordAuthentication`/`PermitRootLogin`.  
- Ansible audit: role `cis_audit_linux` trong `02_audit.yml` kiểm các dòng này ở sshd_config.

## Cách kiểm CLI/manual
```bash
ssh -o PasswordAuthentication=yes root@<ip>   # phải bị từ chối password
grep -E '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
```

## Evidence khi fail
- Dán kết quả grep hoặc log SSH bị từ chối.  
- Cập nhật `docs/manual_checklist.md` nếu phải chỉnh tay.
