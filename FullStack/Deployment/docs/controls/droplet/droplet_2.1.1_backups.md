# Control: Droplet 2.1.1 – Backups enabled

## Mục tiêu
Đảm bảo mọi droplet thuộc môi trường demo (tag `env:demo`) bật backups.

## Cách kiểm GUI
1) DigitalOcean Console → Droplets.  
2) Filter theo tag `env:demo`.  
3) Mở từng droplet → tab **Backups** phải đang bật.

## Cách kiểm CLI (manual)
```bash
doctl compute droplet list --tag-name env:demo --format ID,Name,Backups
```
Pass khi toàn bộ droplet Backups=`true`.

## Cách kiểm automation
Chạy `scripts/bash/check_droplet.sh` hoặc `scripts/powershell/Invoke-CisCheck-Droplet.ps1`; xem báo cáo trong `reports/`.

## Evidence khi fail
- CLI: dán output lệnh trên.  
- GUI: chụp màn hình tab Backups.  
- Lưu đường dẫn evidence ngay bên dưới:
- Evidence:
