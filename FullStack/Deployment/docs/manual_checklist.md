# Manual Checklist (DigitalOcean CIS Demo)

Tick vào control đã kiểm, luôn đính kèm evidence (screenshot hoặc output lệnh).

| Control | Mô tả | Cách kiểm | Trạng thái | Evidence |
| --- | --- | --- | --- | --- |
| IAM-1 | Review member/project access | GUI: Project → Members; đảm bảo đúng principle of least privilege | ☐ |  |
| IAM-2 | 2FA bắt buộc cho user | GUI: Settings → Security → enforce 2FA; xác nhận từng member | ☐ |  |
| IAM-3 | API token/SSH key review | GUI/CLI: danh sách token/SSH key; revoke token/keys không dùng | ☐ |  |
| DROPLET-2.1.1 | Backups bật trên tất cả droplet tag `env:demo` | GUI/CLI (tham khảo `docs/controls/droplet_2.1.1_backups.md`) | ☐ |  |
| LOG-1 | Kiểm chứng forwarding log/metrics | GUI/CLI tùy stack; confirm đích nhận log/metric | ☐ |  |

Ghi chú: thêm dòng mới nếu có control manual khác. Khi fail, paste đường dẫn evidence (ảnh, log) vào cột Evidence.
