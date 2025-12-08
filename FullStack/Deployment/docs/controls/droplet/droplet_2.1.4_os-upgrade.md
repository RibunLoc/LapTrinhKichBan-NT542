# Control: Droplet 2.1.4 – Chính sách nâng cấp OS

## Mục tiêu
Có quy trình nâng cấp OS định kỳ (major/minor) và bằng chứng đã kiểm tra/áp dụng.

## Cách kiểm automation
- Ansible audit (check_mode): `ansible/playbooks/02_audit.yml` có thể mở rộng để kiểm `unattended-upgrades` và version.  
- Script tham chiếu: `scripts/bash/check_droplet.sh` với `RUN_ANSIBLE_AUDIT=1` sẽ gọi playbook audit.

## Cách kiểm manual/CLI
```bash
lsb_release -a
do-release-upgrade -c   # check available upgrade (không chạy)
```
Hoặc xem log upgrade gần nhất: `/var/log/apt/history.log`.

## Cách kiểm GUI
Không có GUI riêng, cần SSH vào droplet để kiểm.

## Evidence khi fail
- Lưu output `lsb_release` + `do-release-upgrade -c` và/hoặc log apt.  
- Ghi chú lịch/plan nâng cấp trong `docs/manual_checklist.md`.
