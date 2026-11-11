# Số đo D7

Máy: Mac Apple Silicon, build release, `D7Nhom6Tests` (máy rảnh), 2026-11-11.

| Mục | Số đo | Ngưỡng |
|---|---|---|
| Căn trái ba biểu đồ (Nhom6, trang D3) | 0,3 đến 0,4 ms | < 150 ms |
| Phân bố ngang ba thẻ | 0,3 ms | < 150 ms |
| Dán một thẻ sang trang D1 | 1,3 đến 1,4 ms | < 150 ms |
| Nhóm ba biểu đồ | 0,2 ms | < 150 ms |
| Lưu Nhom6 (căn + phân bố + dán + nhóm + kéo nhóm) | 0,19 đến 0,22 s | < 1 s |
| Part đổi trong `Nhom6_d7.pbix` | 9 (các `visual.json` đổi, nhóm mới, `[Content_Types].xml`; `SecurityBindings` bỏ) | chỉ part đổi |
| Lưu bản sao Nhóm 2 (định dạng cũ; dời, căn, xoá, nhân bản) | 0,42 s riêng; có thể ~1 s khi chạy cùng test nặng khác | < 2 s |
| Số trường hợp ghi theo cấu trúc chưa quan sát | 0 (nhóm lồng bị từ chối; xoá nhóm và co dọc theo phương án an toàn, hoàn tác được) | 0 |

Khớp số đo Power BI Desktop (`AlignGeometryTests`): căn giữa theo trung bình tâm, phân bố ba thẻ x = 24/338/1594 cho 809, kẹp trong trang.

Nhóm rồi bỏ nhóm trên Nhom6 trả đúng vị trí ba biểu đồ (0 điểm lệch; `D7Nhom6Tests`). Mở lại ở Power BI Desktop: `Nhom6_d7.pbix` và `Nhom2_d7.pbix` không báo lỗi (`docs/phase-d-evidence/vm-d7/CHECKLIST-KET-QUA.md`).
