# Hợp đồng: tập con TMDL áp dụng được (Câu chuyện 5)

Văn bản là đầu ra của `TMDLWriter` (thụt lề tab, `key: value`, biểu thức nhiều dòng thụt sâu hơn). Áp dụng nguyên khối: có lỗi thì không áp gì.

## Áp dụng được

| Đối tượng | Thay đổi cho phép |
|---|---|
| `measure Tên = biểu thức` | thêm, đổi biểu thức, đổi/bỏ `formatString`, `displayFolder`, `description`, `isHidden`, xoá (bỏ cả khối) |
| `column Tên` (cột dữ liệu) | `formatString`, `summarizeBy`, `dataCategory`, `sortByColumn`, `displayFolder`, `description`, `isHidden` |
| `relationship …` | `isActive`, `crossFilteringBehavior`; (2b) thêm/xoá quan hệ |

## Từ chối từng mục (kèm lý do)

- Bảng mới, `partition`, `source`, `column` mới hoặc `type: calculated` (cần T3, ngoài phạm vi); đổi `dataType`; `role`, `perspective`, `culture`, `hierarchy` mới; đổi tên đối tượng còn nơi dùng (FR-020); thuộc tính không có trong `TMDLWriter` hiện nay.
- Văn bản không phân tích được: lỗi theo dòng/cột (`dòng N: …`).
- Đối tượng không tồn tại được nhắc để sửa: lỗi; đối tượng bị bỏ khỏi văn bản: coi là xoá (chỉ measure/quan hệ, các loại khác từ chối).

## Kiểm sau áp dụng

`TMDLWriter.documents(for: hiệu lực)` chuẩn hoá khoảng trắng bằng văn bản đã nhập (với phần đã áp dụng).
