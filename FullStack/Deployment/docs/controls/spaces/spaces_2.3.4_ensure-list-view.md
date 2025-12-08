# Control: Spaces 2.3.4 – Hạn chế liệt kê/ truy cập bucket

## Mục tiêu
Bucket mặc định private; hạn chế khả năng liệt kê/đọc từ công cộng.

## Cách thực hiện / automation
- Terraform đặt `acl = "private"` cho Spaces.  
- Có thể bổ sung bucket policy deny public (qua AWS S3 API) nếu cần IP allowlist.  
- Script `check_spaces.sh` kiểm tra public ACL/policy; fail nếu phát hiện `AllUsers/AuthenticatedUsers` hoặc `PolicyStatus.IsPublic=true`.

## Cách kiểm manual/CLI
```bash
aws s3api get-bucket-acl --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT"
aws s3api get-bucket-policy-status --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT"  # nếu có policy
```
Pass khi không có grant public và policy không public.

## Evidence khi fail
- Lưu output ACL/policy hoặc screenshot Settings → Permissions; ghi lại bước khắc phục trong `docs/manual_checklist.md`.
