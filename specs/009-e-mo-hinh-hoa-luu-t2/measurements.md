# Số đo Phase E

Máy: Mac Apple Silicon, bản release (`--scratch-path .build-1a-rel`), file `Nhom6_work.pbix` (51,8 MB, khoảng 1 triệu hàng).

## S0: lưu T2 một measure (2026-11-14)

`pbix-dump add-measure` (đường `PBIXWriter.build` + kiểm trong bộ nhớ), `BIPRO_TIMING=1`:

| Bước | Giây |
|---|---|
| giải nén DataModel (nguồn) | 0,27 |
| dựng lại ABF | 0,05 |
| nén XPress9 | 1,36 |
| ghi ZIP | 0,14 |
| kiểm: giải nén mới + cũ, so mô hình, so từng tệp ABF | 0,57 |
| **Tổng** | **khoảng 2,5** (đo ngoài: 2,6 s tường) |

SC-004 (dưới 3 giây) đạt. Trước khi tra tệp ABF bằng từ điển, bước so tệp mất 1,5 s (quét tuyến tính O(n²)), tổng 4,4 s.

Desktop mở `Nhom6_s0.pbix` (có `SecurityBindings` nguyên): không báo hỏng, dữ liệu và trang D3 hiện đủ (VM-E1b). Không cần bỏ `SecurityBindings` khi chỉ đổi `DataModel`.

## S2: engine nạp lại khi đổi quan hệ (2026-11-14)

Cách chọn: `ModelRuntime` dựng `ColumnStore` mới với lược đồ mới nhưng nguồn là `ReschematedColumnSource` (ColumnStore), dùng lại cột đã giải mã của kho gốc; không phải giải mã lại bảng lớn. Chỉ mục quan hệ (`RelationshipIndex`) và chỉ mục cột dựng lại lười theo kho mới.

Đo (debug, `RelationshipEditorTests`, truy vấn Fact_Loan × Dim_Client): đổi hướng lọc sang hai chiều rồi chạy truy vấn đầu tiên 1,8 s (đã gồm chỉ mục quan hệ). Số bản release và với quan hệ của `Fact_Transaction` (1 triệu hàng) sẽ đo ở T040 (golden nặng).

## T040: golden nặng bản release (2026-11-14)

Lệnh: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|ModelRuntimeTests|MeasureEditorTests|RelationshipEditorTests|ColumnEditorTests|DiagramSaveTests|TMDLApplyTests|ModelSaveTests|MeasureTypingEngineTests"`.
Kết quả: **137 test qua, 0 trượt** (152 s); 27 test bị bỏ qua vì thiếu file (Gói P cần `Nhom6_Dashboard.pbix`; các suite `Nhom6` của PBIXKit tìm `Nhom6_work.pbix` ở đường dẫn cố định không còn). Golden Phase B và truy vấn visual giữ nguyên (SC-002). `swift test` thường: 1636 qua.

| Phép đo (qua `DocumentSaver`, gồm sao lưu và kiểm lại) | Thời gian |
|---|---|
| Áp dụng measure (kiểm + suy kiểu + vào mô hình) | 44 ms |
| Lưu T2 một measure | 3,12 s |
| Lưu T2 có quan hệ mới (thêm tệp chỉ mục R$) | 3,03 s |
| Đổi hướng lọc + truy vấn đầu tiên | 24 ms |
| Áp dụng TMDL | 21 ms |

SC-004: đường dựng thuần (S0) 2,5 s đạt; qua `DocumentSaver` đầy đủ (sao lưu, kiểm lại hai lần) khoảng 3,0 đến 3,1 s, sát ngưỡng 3 s, chưa tối ưu thêm.
