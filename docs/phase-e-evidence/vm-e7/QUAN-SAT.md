# VM-E7: xoá tab, đổi thứ tự tab, gỡ bảng khỏi tab (2026-11-15)

Power BI Desktop, bản sao `Nhom6_work.pbix` do BI Pro dựng (`Nhom6_f3.pbix`: ba tab Layout 1, 2, 3), Model view. Claude bấm chuột thật qua `vm.sh`.

## Xoá tab
- Chuột phải tên tab thường: menu **New / Rename / Delete**. Chuột phải không chuyển tab đang xem.
- **Delete** hiện hộp "Delete Layout 2 — You won't be able to undo deleting this layout. Do you want to delete this layout?" (Delete / Cancel). Desktop không hoàn tác được; BI Pro hoàn tác được bằng ⌘Z nhưng vẫn hỏi xác nhận.
- Sau khi lưu, tab biến khỏi mảng `diagrams`, **`ordinal` đánh lại liên tục** (còn All tables, Layout 1, Layout 3 thì ordinal 0, 1, 2: Layout 3 từ 3 xuống 2). `selectedDiagram` là tab đang xem lúc lưu.
- Tab "All tables" không có menu xoá (chỉ "New").

## Đổi thứ tự tab
- Kéo tab sang trái/phải (hai lần, kéo chậm có điểm dừng): **thứ tự không đổi**. Tab bố cục của Model view không kéo đổi chỗ được. BI Pro không làm tính năng này.

## Gỡ bảng khỏi tab
- Chuột phải thẻ bảng: menu có **Remove from diagram** (và Delete from model, Add related tables, Hide in report view...). **Remove from diagram** chỉ bỏ thẻ khỏi tab đó; bảng vẫn còn ở ngăn Data và ở "All tables".
- Sau khi lưu: nút của bảng biến khỏi mảng `nodes` của tab đó; các tab khác và phần mô hình không đổi.

## Gate Desktop mở file do BI Pro lưu
`Nhom6_f4.pbix` (BI Pro xoá Layout 2, gỡ Fact_Loan khỏi Layout 1, kéo Dim_Client tới (500,300)): Desktop mở không lỗi, thanh tab "All tables / Layout 1 / Layout 3", Layout 1 chỉ có Dim_Client ở vị trí đã kéo (ảnh `h1-layout1-chi-con-dim-client.png`, đã cắt, không có dòng tài khoản). Fact_Loan vẫn ở ngăn Data.
