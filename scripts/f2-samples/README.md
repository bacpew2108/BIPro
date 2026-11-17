# Mẫu dữ liệu đợt tồn đọng sau Phase F

`python3 -I scripts/f2-samples/make_f2_samples.py [--large]` sinh vào `build/f2-out/samples/` (ngoài git). Mô tả từng tệp và quan hệ dự kiến ở đầu script. `--large` thêm `big_10m.parquet` (khoảng 200 MB; ổ đĩa còn ít chỗ thì chỉ sinh khi làm US5). `nested.parquet` do `scripts/f-samples/make_parquet.py --nested` (gói F2-CONN) sinh.
