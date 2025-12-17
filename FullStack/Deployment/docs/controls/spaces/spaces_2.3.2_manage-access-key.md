# Control: Spaces 2.3.2 – Manage Access Key / Secret Key for Spaces

## Mục tiêu
Không hardcode Spaces Access Key / Secret Key trong mã nguồn; chỉ truyền qua biến môi trường/Secrets của CI.

## Manual (DigitalOcean Dashboard)
1) DigitalOcean Dashboard → API → Spaces Keys  
2) Tạo/rotate key theo chính sách nhóm  
3) Lưu key vào nơi quản lý secret (GitHub Secrets, Vault, ...)

## Automation (repo)
Repo không tự tạo Spaces key (vì thường phải tạo qua UI), nhưng tự động hóa việc **sử dụng key an toàn**:
- `.env`/CI Secrets: `SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`
- Controls: `scripts/bash/controls/spaces_2.3.2_manage_access_key.sh` sẽ FAIL nếu thiếu env var hoặc phát hiện key bị hardcode trong Terraform `.tf`/`.tfvars` (best-effort).

## Evidence
- Screenshot trang Spaces Keys hoặc log rotate key (nếu có).
