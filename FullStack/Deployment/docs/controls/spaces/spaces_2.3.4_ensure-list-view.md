# Control: Spaces 2.3.4 – Ensure bucket/object listing is restricted (Automated)

## Mục tiêu
Bucket phải private (không public list/read), tránh rò rỉ dữ liệu do cấu hình ACL/policy sai.

## IaC (Terraform)
Module Spaces mặc định `acl = "private"` và cấu hình theo chuẩn demo (private-by-default).

## Automation (repo)
- Chạy control: `scripts/bash/controls/spaces_2.3.4_private_access.sh`
- Control sẽ FAIL nếu bucket có dấu hiệu public (ACL/policy public).

## Evidence khi FAIL
- Dán output `aws s3api get-bucket-acl` / `get-bucket-policy-status`.
