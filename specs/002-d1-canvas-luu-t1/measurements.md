# Số đo: D1

Máy: Mac Apple Silicon (M1 Pro 8 nhân). File: `~/Downloads/bipro-golden/Nhom6_work.pbix` (51,8 MB).

## Trước khi sửa (T003)

| Việc | Thời gian (5 lần) | Ghi chú |
|---|---|---|
| `pbix-dump roundtrip` (dựng lại cả DataModel, tầng T2, không phải T1) | 2,58–2,79 s | Chỉ để tham chiếu: D1 không đi đường này |
| Lưu T1 (đổi `visual.json`, DataModel `rawCopy`), `pbix-dump move-visual`, release | 0,033–0,108 s (0,108 / 0,033 / 0,035 / 0,067 / 0,065) | Mốc cho SC-004 (dưới 1 s): còn dư nhiều. Chỉ phần dựng + ghi + kiểm; chưa gồm kiểm `loadReport()` trong `DocumentSaver` |

Ghi chú: `pbix-dump set-title` không dùng được làm mốc vì thẻ card đầu tiên của Nhom6 không có tiêu đề.

## Kéo và đổi cỡ trên canvas (T020, SC-005 dưới 150 ms mỗi khung hình)

Đo trong app thật (D3 của Nhom6, 41%, 12 visual, `BIPRO_PERF=1`): thời gian xử lý của mỗi vòng runloop chính khi kéo bằng `cliclick`, 30 bước.

| Thao tác | Mỗi khung hình (cao nhất, bỏ khung đầu tiên) | Ghi chú |
|---|---|---|
| Kéo một card | 19–28 ms | dựng lại cả trang |
| Kéo biểu đồ combo nặng | 21–32 ms | |
| Đổi cỡ biểu đồ combo, dựng lại sống | **124–134 ms** | sát ngưỡng 150 ms nên bị loại (R9) |
| Đổi cỡ biểu đồ combo, khung bóng | 10–13 ms | chọn: visual giữ cỡ cũ, thả chuột mới dựng lại |

Khung đầu tiên của mỗi lần kéo mất 113–190 ms (lần dựng đầu của lớp phủ); chỉ một khung.
Ảnh chụp ở `docs/phase-d-evidence/01…05-*.png`.

## Hồi quy (T038, T039)

| Kiểm | Kết quả |
|---|---|
| `swift test` | 911 qua (trước D1: 819) |
| Golden nặng `BIPRO_HEAVY=1 … --filter "Nhom6\|ORA\|VIS\|EditNhom6\|BatchedSerial"` (release) | 81 qua (gồm 30 golden Phase B, 72 truy vấn visual, các test E3, `EditNhom6`) |
| Lưu Nhom6 (SC-004) | 0,22 s khi chạy riêng; 0,52 s khi chạy cùng lúc với các test golden nặng. Dưới 1 s |
| Chế độ Xem so với `710daaf` (FR-007, FR-020) | Chụp cửa sổ app 4 trang (D1–D4), cùng cỡ cửa sổ, so từng điểm ảnh vùng canvas: 0 điểm khác biệt ở cả 4 trang |
