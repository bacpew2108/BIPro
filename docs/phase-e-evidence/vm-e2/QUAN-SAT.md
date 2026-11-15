# VM-E2: kiểu và định dạng measure, measure lỗi, xoá measure (2026-11-14)

Bạn cho phép dùng VM ("duyệt, có thể dùng vm"). Bản sao `Nhom6_work.pbix` trong VM (đã xoá cả trên VM lẫn Mac), tạo measure ở Table view của Desktop, lưu, `pbix-dump extract metadata.sqlitedb`, `sqlite3 .dump`, `diff`. Dòng đầy đủ ở `rows.txt`. Ảnh chụp toàn cửa sổ có địa chỉ tài khoản nên không đưa vào git.

## Kiểu và định dạng Desktop ghi theo kết quả biểu thức

| Biểu thức | DataType | FormatString |
|---|---|---|
| `COUNTROWS(Dim_Account)+1` (VM-E1) | 6 (Int64) | `0` |
| `BLANK()` | 6 (Int64) | `0` |
| `DIVIDE(1,3)` | 8 (Double) | NULL |
| `"abc"` | 2 (String) | NULL |
| `TRUE()` | 11 (Boolean) | `"TRUE";"TRUE";"FALSE"` |
| `DATE(2024,1,15)` | 9 (DateTime) | `General Date` |

Tiền tệ (`CONVERT(…, CURRENCY)`) chưa lấy được (gõ phím bị rớt, measure không vào mô hình): `[SUY ĐOÁN]`, BI Pro ghi `DataType` 10 và để trống định dạng.

## Measure lỗi

Gõ sai tên hàm (`COUNTRWS`, `DVIDE`): Desktop **vẫn lưu** measure với `State` = 5, `DataType` = 19 (Variant), `FormatString` NULL, `ErrorMessage` = `<Errors><Error><Hresult>3241803821</Hresult><Notes>&lt;_Error&gt;&lt;ccon_name&gt;&lt;![CDATA[<tên>]]&gt;…`. BI Pro chặn lúc áp dụng (không để measure lỗi trong mô hình), đã chốt ở R3.

## Xoá measure

Hộp thoại "Delete Measure … Are you sure?", Yes. Ghi: `DELETE` dòng `Measure` (không có dòng phụ trong mẫu này); `Table.ModifiedTime` của bảng chứa và bốn `DBPROPERTIES` (`LASTCUBEDATACHANGE`, `LASTCUBESCHEMACHANGE`, `LASTCOMMITTED`, `LASTMETADATACHANGEFORSYNCCOMMITTED`) cập nhật. Cùng điều này đúng khi thêm measure (VM-E1). Sửa measure thì không đụng dòng `Table`.

## Ghi chú về điều khiển VM

Trong phiên này `cliclick` (chuột lẫn phím từ Mac) không tới được VM dù Parallels đang ở trên cùng. Cách chạy được: chuột bằng PowerShell bên trong VM (`SetCursorPos` + `mouse_event`, qua `prlctl exec --current-user`), phím bằng `prlctl send-key-event` (kèm trễ 60 ms mỗi phím, nhanh hơn thì rớt phím), chụp bằng `prlctl capture`. Cách này không đụng cửa sổ Mac nào.

## Chưa quan sát

Đổi tên measure có lan truyền tham chiếu (BI Pro chặn, đã chốt FR-020). Định dạng của kiểu tiền tệ. Dòng phụ khi xoá measure có định dạng động (`FormatStringDefinition`): BI Pro xoá theo `ObjectID`, chưa so với Desktop.
