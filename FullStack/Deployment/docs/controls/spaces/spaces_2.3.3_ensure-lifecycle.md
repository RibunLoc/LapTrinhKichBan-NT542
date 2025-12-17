# Control: Spaces 2.3.3 – Ensure Bucket Lifecycle Policy is configured (Automated)

## Mục tiêu
Thiết lập lifecycle rule để tự động xóa object cũ (giảm chi phí, giảm rủi ro dữ liệu tồn đọng).

## IaC (Terraform)
Lifecycle được khai báo trong module Spaces (`terraform/modules/spaces`) theo biến `spaces_expire_days`.

## Automation (repo)
- Chạy control: `scripts/bash/controls/spaces_2.3.3_lifecycle_enabled.sh`
- Control sẽ kiểm tra bucket có rule expiration đúng số ngày kỳ vọng.

## Evidence khi FAIL
- Dán output `aws s3api get-bucket-lifecycle-configuration ...` (endpoint Spaces).
