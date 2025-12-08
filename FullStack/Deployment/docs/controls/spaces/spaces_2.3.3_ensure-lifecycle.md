# Control: Spaces 2.3.3 – Đảm bảo lifecycle policy được bật

## Mục tiêu
Bucket Spaces phải có lifecycle rule xóa/expire object sau số ngày định sẵn để giảm rủi ro và chi phí.

## Cách thực hiện / automation
- Terraform module `modules/spaces` tạo lifecycle mặc định `expiration_days` (var `spaces_expire_days`).  
- Kiểm tra qua AWS S3 API (S3-compatible):
  ```bash
  aws s3api get-bucket-lifecycle-configuration \
    --bucket "$SPACES_BUCKET" \
    --endpoint-url "$SPACES_ENDPOINT"
  ```
- Có thể thêm check vào script `check_spaces.sh` để verify rule tồn tại (chưa mặc định).

## Cách kiểm manual/GUI
1) Console → Spaces → chọn bucket → Settings → Lifecycle.  
2) Xác nhận rule expire đúng số ngày (theo IaC).

## Evidence khi fail
- Lưu output `get-bucket-lifecycle-configuration` hoặc screenshot tab Lifecycle; ghi vào `docs/manual_checklist.md` nếu chỉnh tay.
