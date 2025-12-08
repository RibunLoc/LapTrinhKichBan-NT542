# Control: Droplet 2.1.8 – Dọn khóa SSH không dùng

## Mục tiêu
Chỉ giữ SSH key nằm trong allowlist; xóa các key dư trên DigitalOcean.

## Cách kiểm automation
- Script: `scripts/cleanup_ssh_keys.sh`
  - Sử dụng `scripts/allowed_keys.txt` (tên hoặc fingerprint).
  - Mặc định DRY_RUN=1 (chỉ log); đặt `DRY_RUN=0 APPROVE_DELETE=1` để xóa thật; có thể dùng `SLACK_WEBHOOK_URL` để log/phê duyệt.
  - `doctl compute ssh-key list -o json` để lấy danh sách; key không thuộc allowlist sẽ bị xóa.

## Cách kiểm manual/CLI
```bash
doctl compute ssh-key list --output json | jq -r '.[] | [.id,.name,.fingerprint] | @tsv'
```
Đối chiếu với allowlist, xóa tay nếu cần.

## Evidence khi fail
- Lưu output danh sách key trước/sau cleanup (hoặc backup JSON).
- Nếu xóa tay, ghi lại thao tác vào `docs/manual_checklist.md`.
