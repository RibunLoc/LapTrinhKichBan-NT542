# Control: Volume 2.4.1 – Đảm bảo mã hóa & mount an toàn

## Mục tiêu
Block Storage phải được mã hóa (mặc định DO encrypt at rest) và nếu dùng trên Droplet thì mount với LUKS + tùy chọn noexec/nodev/nosuid.

## Cách thực hiện / automation
- Terraform `modules/volume` tạo volume; Ansible playbook `luks_volume.yml` (hoặc role) thiết lập LUKS, filesystem, mount.  
- Script `scripts/bash/check_volume.sh` kiểm:
  - Volume có tag `ENV_TAG`.  
  - Volume đã attach droplet.  
  - Nếu đặt `SSH_TARGET`, kiểm `/etc/fstab` có `noexec,nodev,nosuid` cho mountpoint (mặc định `/data`).
- DO tự mã hóa block storage at rest; LUKS thêm lớp mã hóa trong VM.

## Cách kiểm manual/CLI
```bash
doctl compute volume list --output json | jq -r '.[] | [.name,.droplet_ids] | @tsv'
ssh root@<ip> "grep /data /etc/fstab"
```
Nếu dùng LUKS: `lsblk -f` và `cryptsetup status <mapper>` để xác nhận.

## Evidence khi fail
- Lưu output doctl/grep/lsblk; nếu phải sửa mount option, ghi lại vào `docs/manual_checklist.md`.
