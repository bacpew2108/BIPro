# Quyết định sau gate F-T3 (T011), 2026-11-15

**Giữ tầng T3 (không chuyển sang Enter Data).** Lý do:

- Kết quả TRƯỢT là ba lỗi ghi cụ thể và khác nhau, mỗi lỗi sửa được và đã sửa được hai lỗi đầu ngay trong phiên (xem `CHECKLIST-KET-QUA.md`). Desktop tiến dần: `Token Literal expected` → `Alignment` → DBCC `H$ system table is missing`. Không có dấu hiệu Desktop từ chối bảng do ngoài ghi.
- Phương án dự phòng Enter Data **không tránh được `H$`**: bảng Enter Data của Desktop cũng lưu dữ liệu trong VertiPaq (cùng dictionary, `.idf` và bảng `H$`); khác ở chỗ biểu thức M chứa dữ liệu. Nên cả hai nhánh đều phải ghi `H$`. T029 đến T031 (Enter Data) vẫn làm sau T3 như kế hoạch, không dùng thay thế.

**Việc còn phải làm trước khi gate F-T3 đạt:**

1. `Partition.QueryDefinition` bảng nạp: M hợp lệ (kể cả bảng không truy vấn: `#table(type table [...], {})`); sửa ghi chú sai trong `TableMetadataWriter`.
2. `Column.Alignment = 1`, `FormatString` theo kiểu như cột Desktop tạo.
3. Ghi bảng `H$` cho mọi cột dữ liệu (siêu dữ liệu + hai cặp `.idf/.idfmeta`); đây là phần chính của T012 và T014/T015. Cần quan sát Desktop tự nạp CSV (VM-F1, T012) để biết ý nghĩa các giá trị `.idf` của `H$` và chuỗi sắp xếp (collation) khi ghi `POS_TO_ID`.
4. Lặp lại gate này (mở file BI Pro ghi trong Desktop) sau mỗi sửa; chỉ khi mở được, đúng số dòng, đúng Sum mới đánh dấu đạt.

**Cập nhật kế hoạch:** T010 xong (trượt có chẩn đoán); T011 xong (giữ T3); T012 (VM-F1) là bước kế tiếp vì cần `H$`.

## Cập nhật cuối ngày 2026-11-15: gate F-T3 ĐẠT

Cả ba việc ở trên đã làm và file mở được trong Desktop (`CHECKLIST-KET-QUA.md`, lần 4). T010 đạt, nhánh Enter Data (T029 đến T031) giữ làm bổ sung sau, không còn là dự phòng. Còn lại cho T3: nối bộ ghi vào đường lưu (T015 hoàn chỉnh, T017, T022), kiểu `currency`/`dateTime`/`boolean`, nhiều đoạn (> 8 triệu dòng), RLE (không bắt buộc), và gate T026 (5 file) trước khi coi SC-006 xong.
