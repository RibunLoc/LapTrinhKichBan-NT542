# Control: Volume 2.4.1 – Ensure Volumes are Encrypted

## Mục tiêu
Đảm bảo Block Storage Volume được mã hóa “at rest”.

## Ghi chú về DigitalOcean
DigitalOcean Block Storage mặc định được mã hóa at rest ở tầng provider. Trong demo, nhóm bổ sung thêm lựa chọn LUKS (mã hóa trong OS) để minh hoạ “defense in depth”.

## Automation (repo)
- Kiểm tra provider-level + trạng thái attach/tag: `scripts/bash/controls/volume_2.4.1_ensure_encrypt.sh`
- (Tuỳ chọn) Mã hóa trong OS bằng LUKS: `ansible/luks_volume.yml` (có thể phá dữ liệu nếu volume chưa được chuẩn bị)

## Evidence
- PASS: report JSON trong `reports/` của control 2.4.1.
- FAIL: log trong `logs/` + trạng thái volume/droplet attach.
