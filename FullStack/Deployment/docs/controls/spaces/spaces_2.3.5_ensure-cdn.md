# Control: Spaces 2.3.5 – Bật CDN cho Spaces (nếu cần phân phối)

## Mục tiêu
Spaces bucket cần CDN để tối ưu hiệu năng truy cập và giảm tải trực tiếp.

## Cách thực hiện / automation
- Terraform module `modules/spaces` tạo `digitalocean_cdn` khi `enable_cdn=true` (default). TTL quản lý qua var `cdn_ttl_seconds`, domain tùy chọn `cdn_custom_domain`.
- Kiểm tra qua doctl:
  ```bash
  doctl compute cdn list --output json | jq -r '.[] | [.endpoint,.origin] | @tsv'
  ```
- Hoặc `terraform state show digitalocean_cdn.this` (nếu quản lý bằng Terraform).

## Cách kiểm GUI (manual)
1) Console → Networking → CDN.  
2) Xác nhận CDN gắn với bucket Spaces, TTL đúng với policy.

## Evidence khi fail
- Lưu output doctl hoặc screenshot CDN list; ghi vào `docs/manual_checklist.md` nếu phải bật thủ công.
