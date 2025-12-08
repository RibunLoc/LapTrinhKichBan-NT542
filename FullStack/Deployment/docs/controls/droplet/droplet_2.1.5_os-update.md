# Control: Droplet 2.1.5 – Cập nhật bảo mật định kỳ

## Mục tiêu
Đảm bảo các bản vá bảo mật được cài đặt thường xuyên (unattended-upgrades hoặc lịch patch).

## Cách kiểm automation
- Ansible role `cis_baseline_linux` cài `unattended-upgrades` và `auditd`.  
- Ansible audit (check_mode) trong `02_audit.yml` kiểm sự tồn tại gói `unattended-upgrades`.  
- Có thể thêm task kiểm file `/etc/apt/apt.conf.d/20auto-upgrades`.

## Cách kiểm CLI/manual
```bash
dpkg -l | grep unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
sudo unattended-upgrades --dry-run
```

## Evidence khi fail
- Lưu output lệnh, hoặc ảnh chụp cấu hình auto-upgrade.  
- Ghi vào `docs/manual_checklist.md` nếu phải can thiệp thủ công.
