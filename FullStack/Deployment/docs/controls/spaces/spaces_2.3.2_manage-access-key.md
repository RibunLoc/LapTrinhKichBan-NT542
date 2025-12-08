# Control: Spaces 2.3.2 – Quản lý Access Key / Secret Key

## Mục tiêu
Không hard-code key trong mã nguồn; key được cấp phát thủ công (DO Console) nhưng sử dụng qua biến môi trường/secret store và có quy trình xoay vòng.

## Cách thực hiện / automation
- Tạo Access Key/Secret Key qua DigitalOcean Console (hiện chưa API).  
- Sử dụng key qua biến môi trường (không commit): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SPACES_ENDPOINT`.  
- Terraform/script nạp từ env (TF_VAR_spaces_access_id/secret_key hoặc `.env` local).  
- Không lưu key thật trong repo; chỉ `.env.example` chứa placeholder.  
- (Tuỳ chọn) Thiết lập secret ở CI (GitHub Actions secrets) rồi export khi chạy `check_spaces.sh`.

## Cách kiểm manual/CLI
- Xác nhận không có key thật trong repo: `git grep -n "DO[A-Z0-9]" scripts terraform` (chỉ placeholder).  
- Kiểm tra env trước khi chạy:  
  ```bash
  env | grep -E 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)|SPACES_ACCESS'
  ```
- Nếu dùng CI: kiểm tra secrets cấu hình ở Settings → Secrets.

## Evidence khi fail
- Screenshot/record secret đặt sai chỗ (repo), hoặc thiếu env; ghi vào `docs/manual_checklist.md`.
