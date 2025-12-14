# 2.2.1 Ensure security history is monitored (Manual + Evidence)

## Mục tiêu
Đảm bảo lịch sử hoạt động bảo mật của tài khoản DigitalOcean (Security History) được theo dõi định kỳ và có bằng chứng (evidence) lưu lại.

## Cách kiểm (GUI – theo CIS)
1. Sign in to your DigitalOcean dashboard.
2. Go to the **Settings** menu.
3. Click the **Security** tab.
4. Ở cuối trang có bảng **Security History** gồm: action, user name, email, IP address, time.

## Automation hỗ trợ (gating bằng evidence)
Do DigitalOcean hiện **không có doctl/API ổn định** để đọc trực tiếp bảng Security History, nên phần “automation” ở repo này dùng cơ chế:
- Script chỉ **check đã có evidence** hay chưa và **evidence còn mới** hay không.
- Nếu chưa có/đã cũ → script **FAIL** để nhắc phải kiểm tra lại.

Script:
- `scripts/bash/controls/monitoring_2.2.1_security_history_monitored.sh`

Evidence file mặc định (có thể đổi bằng env):
- `reports/manual/security_history_2.2.1.md`

Biến môi trường:
- `SECURITY_HISTORY_EVIDENCE_FILE` (đường dẫn evidence)
- `EVIDENCE_MAX_AGE_HOURS` (mặc định 168 giờ = 7 ngày)

## Evidence cần lưu
Dán/ghi một trong các dạng:
- Ảnh chụp màn hình bảng Security History (lưu path file) + timestamp
- Hoặc copy text các dòng quan trọng (action / user / email / IP / time) + timestamp

Ví dụ nội dung `reports/manual/security_history_2.2.1.md`:
```text
ReviewedAt: 2025-12-12T10:15:00+07:00
Reviewer: team-ops
Evidence:
- Screenshot: reports/manual/security_history_2.2.1_20251212.png
- Notes: no suspicious actions observed
```

