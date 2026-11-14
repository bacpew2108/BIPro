# Hợp đồng: thêm visual, đổi loại, sửa văn bản hộp văn bản

## Điều kiện chung

- Chế độ Sửa (⌘E), báo cáo PBIR (không phải `Report/Layout`), visual không thuộc nhóm. Ngược lại: thư viện và nút ribbon mờ, `.help` nêu lý do, bấm vào đặt `LayoutEditor.notice` (không đổi gì).
- Mọi thao tác dưới đây là đúng một `commit` (một bước hoàn tác). Thao tác không đổi gì thì không tạo bước.

## Thêm visual (`insertVisual`)

Điều kiện: không chọn visual nào (hoặc gọi từ ribbon: thêm bất kể vùng chọn, rồi chọn visual mới).

| Bước | Hành vi |
|---|---|
| Loại | Phải là loại `isSupported` (R2); không thì từ chối kèm lý do, không thêm |
| Mã | `makeVisualName(avoiding: usedIDs)`; thêm vào `usedIDs` và `createdIDs[trang]` |
| Cỡ | Mặc định theo loại, kẹp vừa trang |
| Vị trí | Tâm trùng tâm `visibleRect`, lưới 8; trùng ≥ 90% với một visual đã có thì lệch +16 mỗi lần, tối đa 10 lần (R5) |
| `z`, `tabOrder` | z lớn nhất của trang + 1000; `tabOrder` = `z` |
| Nội dung | `PBIRNewVisual.makeJSON` (R3); visual dữ liệu chưa có trường: `fields` rỗng, hiện "Thêm trường để vẽ" |
| Sau | Chọn visual mới; `notice` và `fieldRefusal` cũ bị xoá |

## Bổ sung D3b (2026-11-13, VM-D3 mục A, B)

- Thư viện và nút ribbon "Thẻ" thêm `cardVisual` (như Desktop); `card` cũ vẫn thêm được. Ô của `cardVisual` là `Data` (measure; chưa quan sát ô khác).
- Cột thả vào ô: cột đầu của ô ghi `"active":true` (giữa `nativeQueryRef` và `displayName`), các cột sau `false` (như donut, treemap, slicer, matrix của Nhom6); ô một trường thay thì cột mới là cột đầu; measure không có cờ.
- `sortDefinition` mặc định (`isDefaultSort:true`, giảm dần theo measure đầu của ô `Y`, hoặc `Data` với `cardVisual`) chỉ thêm khi visual chưa có `sortDefinition`, chỉ có measure (chưa có cột nhóm) và là biểu đồ trục hoặc `cardVisual`. Thêm cột nhóm khi đã có sắp xếp mặc định theo measure: giữ nguyên (VM-D8c). Cột Category mà sắp xếp mặc định trỏ tới bị thay bằng đúng một cột khác: sắp xếp chuyển sang cột mới, giữ hướng (VM-D9 mục 5); trường được sắp trỏ tới không còn mà không có cột thay thế rõ ràng thì `sortDefinition` mặc định bị bỏ (rồi dựng lại theo measure đầu nếu visual lại chỉ có measure); sắp xếp do người dùng đặt giữ nguyên. Sắp xếp mặc định theo measure không chặn bỏ measure; theo cột hoặc do người dùng đặt vẫn chặn.
- Đổi sang cột/thanh (`clustered/stacked/100% … ColumnChart`, `…BarChart`, `columnChart`) khi visual chưa có `sortDefinition` và cột `Category` đầu là kiểu ngày giờ của mô hình (`LayoutEditor.dateColumns`): thêm `sortDefinition` tăng dần theo cột đó, `isDefaultSort:true` (VM-D9 mục 1; `PBIRQueryPatch.addingDefaultCategorySort`). Chưa quan sát: cột Category kiểu chữ hoặc số khi đổi loại, đích combo/vùng.

## Bổ sung VM-D12 (2026-11-14, `docs/phase-d-evidence/vm-d12/QUAN-SAT.md` mục 1)

- Sắp xếp mặc định tăng dần theo cột ngày khi đổi loại nay áp cho mọi loại có `Category`: cột, thanh, vùng (cả xếp chồng, 100%), hai loại combo, ruy-băng, thác nước, donut, phễu; slicer thì theo cột ở ô `Values`. Treemap, bảng, matrix, KPI, bản đồ hình không thêm (`LayoutEditor.defaultSortRole`). Thay cho "chưa quan sát: đích combo" ở trên.
- Slicer nhận cột `Category` vào `Values`; matrix nhận `Category` vào `Rows` và measure của `Tooltips` vào `Values` (`TypeChange.targetFallbacks`).
- Đích bản đồ hình (VM-D13): cột đầu của `Category` vào `Series` (bỏ `active`), `Y` vào `Value`, `Tooltips` giữ; bỏ `labels`; thêm `objects.shape` và mục `dataPoint` chuyển sắc ở cuối mảng (`PBIRVisualPatch.addingShapeMapDefaults`). Từ chối khi file chưa có tài nguyên `usa.states.topo`.

## Đổi loại (`changeType`)

Điều kiện: đúng một visual được chọn, có trong trang hiện tại, loại đích `isSupported` và khác loại hiện tại.

1. `TypeChange.plan` (R7, R8). `blocked != nil` → từ chối, không đổi gì.
2. Ngược lại: đổi `visualType`, tỉa `objects`, ghi ô mới. Giữ vị trí, cỡ, `z`.
3. `notice` liệt kê trường bị bỏ (và khoá `objects` bị bỏ), ví dụ "Đã bỏ 2 trường không có ô trong loại mới: Y2 Net, Tooltips Avg".
4. ⌘Z trả lại loại cũ, đủ trường, đủ `objects`.
5. Đổi sang chính loại hiện tại: không đổi, không bước.

## Hộp văn bản (`setText`)

Điều kiện: visual `textbox`. Nội dung nhập: văn bản thuần, nhiều dòng; mỗi dòng là một đoạn (R9). Một lần xong chỉnh là một bước. Rỗng hoàn toàn: giữ một đoạn rỗng. Kiểu chữ có sẵn giữ nguyên (R9).

## Bất biến

- Visual không đụng tới giữ nguyên từng byte khi lưu.
- Phần ngoài `visualType`, `objects` (khoá bị bỏ), `query.queryState` (ô đổi), `objects.general…paragraphs` (hộp văn bản) và `position` của một visual đã sửa giữ nguyên từng byte.
- Mã visual không bao giờ dùng lại (kể cả mã của visual mới đã xoá hoặc hoàn tác).
- File lưu không chứa trường tham chiếu treo (sắp xếp, bộ lọc, định dạng theo trường).
