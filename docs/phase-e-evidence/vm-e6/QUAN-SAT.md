# VM-E6: tab bố cục của Model view (2026-11-14)

Power BI Desktop, bản sao `Nhom6_work.pbix` (`Nhom6_f1.pbix`), Model view. Claude bấm chuột thật qua `vm.sh`.

## Thêm tab
- Nút "+" cạnh tab "All tables" thêm tab tên **`Layout 1`** (số kế tiếp nếu đã có), trống: hiện "Set up your layout" với nút **Auto layout** (thêm mọi bảng). Tab mới được chọn ngay.
- Kéo một bảng từ ngăn Data vào vùng trống của tab thì thẻ bảng hiện ở chỗ thả (Desktop vẽ chậm vài giây).

## Đổi tên
- Bấm đúp tên tab thường → ô sửa ngay trong tab; Enter chốt. Tab **"All tables" không đổi tên được**: bấm đúp không vào chế độ sửa, và menu chuột phải của nó chỉ có "New".

## Ghi vào `DiagramLayout` (UTF-16LE, không BOM, như file gốc)
Sau khi lưu, `DiagramLayout` có thêm một phần tử cuối mảng `diagrams`, các khoá khác giữ nguyên thứ tự:

```
{"ordinal":1,"scrollPosition":{"x":0,"y":0},"nodes":[{"location":{"x":380,"y":449},"nodeIndex":"Fact_Loan","nodeLineageTag":"<LineageTag của bảng>","size":{"height":300,"width":234},"zIndex":0}],"name":"Bo cucE","zoomValue":100,"pinKeyFieldsToTop":false,"showExtraHeaderInfo":false,"hideKeyFieldsWhenCollapsed":false,"tablesLocked":false}
```

- `ordinal` = số thứ tự (0 là "All tables"), `zoomValue` 100.
- Cấp gốc: `"selectedDiagram"` đổi thành tên tab đang xem (`"Bo cucE"`); `"defaultDiagram"` vẫn `"All tables"`; `"version"` vẫn `"1.1.0"`.
- Phần `metadata.sqlitedb` không cần đổi để có tab (chỉ `DiagramLayout`).

Ghi chú quan sát: Desktop không cho đổi tên tab "All tables" (menu chuột phải của nó chỉ có "New"); BI Pro làm như vậy (tab đầu cố định tên). Tab mới của Desktop không có bảng nào đến khi kéo bảng vào hoặc bấm Auto layout.
