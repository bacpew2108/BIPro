# Hợp đồng: lưu tầng T3

```text
ModelEdit.addTable / replaceTable / dropTable / addCalculatedColumn / addCalculatedTable
PBIXChanges.tier = .data                                         khi có bảng/cột mới hoặc đổi dữ liệu
VertiPaqWriter.encodeTable(name:, tableID:, partitionID:, rowNumberID:, columns:)   mở rộng kiểu và null
DataMashup.read(_ data: Data) -> DataMashup ; DataMashup.write(_) -> Data
DocumentSaver.save()                                              T3: tệp tạm → đọc lại kiểm → thay
```

## Bất biến sau mỗi lần lưu T3

1. Đọc lại bằng `VertiPaq.decodeTable`: từng ô trùng `TableData` nguồn (null, kiểu, thứ tự); distinct count khớp.
2. `ModelMetadata` đọc lại khớp mô hình hiệu lực (bảng, cột, quan hệ, measure, `Partition` + biểu thức M); `PRAGMA integrity_check` = `ok`; `MAXID` đúng.
3. Mọi tệp ABF không đụng giữ nguyên byte; `DataMashup.permissionBindings` giữ nguyên byte.
4. `DataMashup` phân tích lại ra đúng danh sách truy vấn và biểu thức.
5. Phần `Report/**` không đổi byte nếu chỉ đổi mô hình.
6. Thất bại ở bất kỳ bước nào: file gốc không đổi, báo nguyên nhân.
7. Golden Nhom6 (30 DAX, 72 truy vấn visual) không đổi.
