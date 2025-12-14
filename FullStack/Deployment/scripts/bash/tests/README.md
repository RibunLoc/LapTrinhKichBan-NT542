# CIS control tests (bats-core)

Các file `.bats` chạy lại các script control trong `scripts/bash/controls/` và trả PASS/FAIL chuẩn.

## Cài bats-core
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

## Chạy test
Từ `FullStack/Deployment`:
```bash
ENV_TAG=env:demo bats scripts/bash/tests/cis_controls.bats
```

Kết quả PASS/FAIL in ra terminal. Các script control vẫn tự ghi log dưới `logs/` và report JSON dưới `reports/`.
