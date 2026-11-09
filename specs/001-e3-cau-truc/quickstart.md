# Hướng dẫn kiểm tra nhanh: E3-cấu-trúc

Điều kiện: `~/Downloads/Nhom6_Dashboard.pbix` có sẵn; `build/e3-base/` có ba file `*.engine.tsv` chuẩn (nếu thiếu, tạo bằng bản engine trước khi sửa: `git stash`/checkout `c8409e9`, chạy `zsh scripts/e3-loop.sh`, chép `build/e3-out/` sang `build/e3-base/`).

## 1. Đo và so byte

```sh
zsh scripts/e3-loop.sh
```

Mong đợi: cả ba truy vấn in `OK` và `khớp byte với bản chuẩn`; thời gian combo thấu chi và matrix Giờ × Thứ dưới 1 s (đo 5 lần, lấy trung vị).

## 2. Hai đường cho cùng kết quả

```sh
BIPRO_BATCH=0 zsh scripts/e3-loop.sh   # đường cũ
BIPRO_BATCH=1 zsh scripts/e3-loop.sh   # đường gộp
```

Mong đợi: hai lần in cùng nội dung `build/e3-out/*.tsv`.

## 3. Test

```sh
swift build
swift test
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"
```

Mong đợi: 800+ test thường qua; 67 test nặng qua (trừ `huyTruyVanNangDungNhanh` chập chờn; chạy riêng thì phải qua).

## 4. Hồ sơ trang

```sh
.build-1a-rel/release/dax-run profile ~/Downloads/Nhom6_Dashboard.pbix --filter "<DAX>"
```

Mong đợi: tổng thời gian từng trang không chậm quá 10% so với `C1.md` §1.5; D1 song song không chậm hơn số đo trước khi sửa (SC-007).

## 5. Kiểm trên app (tuỳ chọn)

`zsh scripts/build-app.sh`, mở trang D1, đổi slicer năm: combo thấu chi và matrix hiện số trong chưa đầy 1 s, số liệu không đổi so với trước.
