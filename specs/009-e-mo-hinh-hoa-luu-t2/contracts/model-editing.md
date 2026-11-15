# Hợp đồng: sửa mô hình và lưu T2

## API công khai (PBIXKit)

```text
ModelEdits                      danh sách ModelEdit có thứ tự (xem data-model.md)
ModelMetadata.applying(_:)      -> ModelMetadata   ném ModelEditError(reason, objects)
MetadataWriter.apply(_:)        áp một ModelEdit lên SQLite đã mở; ném WriteError.invalid khi sai
PBIXChanges.modelEdits          thay cho measures (measures vẫn dùng được, chuyển thành addMeasure)
PBIXChanges.diagramLayout       Data? thay phần DiagramLayout
PBIXWriter.build(...)           tier = .metadata khi modelEdits không rỗng
```

## Bất biến sau mỗi lần lưu T2

1. `ModelMetadata(sqlite:)` đọc lại bằng `ModelMetadata.applying(edits)` của mô hình trước khi lưu (so từng measure, quan hệ, cột đã sửa).
2. `PRAGMA integrity_check` = `ok`; `DBPROPERTIES.MAXID` = ID lớn nhất của mọi bảng có cột `ID`.
3. Mọi tệp ABF ngoài `metadata.sqlitedb` (và, ở giai đoạn 2b, tệp quan hệ) giữ nguyên byte.
4. `pbix-dump verify`: số cột, distinct count không đổi (Nhom6: 110 cột, 0 lệch).
5. Các `Report/**` không đổi byte nếu chỉ sửa mô hình.

## Hành vi giao diện

- Thay đổi vào mô hình hiệu lực ngay (visual vẽ lại), chưa ghi đĩa; ⌘S ghi.
- Lệnh bị chặn hiển thị lý do bằng tiếng Việt, kèm danh sách nơi dùng (tối đa 10).
- Chế độ Xem không có lệnh sửa; file không có `DataModel` hoặc `modelError` thì các lệnh tắt kèm lý do.
