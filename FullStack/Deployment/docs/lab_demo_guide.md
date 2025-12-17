# DigitalOcean CIS Demo – Runbook (Quick)

Tài liệu chạy demo theo luồng chuẩn:
- Chi tiết: `docs/demo_lab_runbook.md`
- Phương pháp: `docs/cis_methodology.md`

## Chạy nhanh (1 lệnh)
Từ `FullStack/Deployment`:
```bash
cp .env.example .env
bash scripts/bash/run_full_cis_pipeline.sh
```

## Chạy CIS controls (không deploy)
```bash
bash scripts/bash/run_cis_controls.sh
```
