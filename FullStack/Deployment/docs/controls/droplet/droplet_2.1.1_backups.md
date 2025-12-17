# Control: Droplet 2.1.1 – Ensure Backups are Enabled

## Mục tiêu
Đảm bảo tất cả Droplet thuộc môi trường demo (tag `env:demo`) bật Backups.

## Cách kiểm tra bằng GUI (manual)
1) DigitalOcean Dashboard → Droplets  
2) Filter theo tag `env:demo`  
3) Mở từng Droplet → tab **Backups** → phải **Enabled**

## Cách kiểm tra bằng CLI (manual)
```bash
doctl compute droplet list --tag-name env:demo --format ID,Name,Backups
```
Pass khi `Backups=true` cho toàn bộ droplet thuộc tag demo.

## Automation (repo)
- Chạy control: `scripts/bash/controls/droplet_2.1.1_backups.sh`
- Chạy tất cả controls: `scripts/bash/run_cis_controls.sh`

## Evidence khi FAIL
- Dán output CLI hoặc screenshot tab Backups.
