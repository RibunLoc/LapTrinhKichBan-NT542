# Control: Spaces 2.3.7 – Dọn bucket không cần thiết

## Mục tiêu
Bucket không còn sử dụng phải được phát hiện và xóa sau khi cập nhật IaC/allowlist.

## Cách thực hiện / automation
- Script: `scripts/check_unused.sh`
  - Đọc danh sách bucket “được phép” từ Terraform state (nếu cung cấp TFSTATE_PATH) hoặc `wanted_buckets.txt`.
  - So sánh với `doctl spaces list`; bucket không nằm trong allowlist sẽ được cảnh báo/xóa sau khi cập nhật code.
- Có thể thêm bước Slack/confirm thủ công trước khi xóa thật.

## Cách kiểm manual/CLI
```bash
doctl spaces list --format Name --no-header
```
Đối chiếu với IaC/allowlist; xóa tay khi cần: `doctl spaces delete-bucket <name> --force`.

## Evidence khi fail
- Lưu danh sách bucket thực tế và allowlist, ghi chú bucket nào bị đánh dấu dư; cập nhật `docs/manual_checklist.md` nếu xử lý thủ công.
