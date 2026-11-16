# Báo cáo F-UI Vòng 2: Hộp thoại nâng cao Power Query (BI Pro)

## 1. Tổng quan nhiệm vụ

Gói công việc **F-UI vòng 2 (Hộp thoại nâng cao)** trong nhánh `bacpew2108/f-ui-dlg` tập trung triển khai giao diện và kết nối người dùng cho các tính năng nâng cao của Query Editor:
- **Merge Queries (Gộp truy vấn)**: Hộp thoại chọn bảng thứ hai, chọn các cặp cột khoá (có huy hiệu thứ tự `KHOÁ 1`, `KHOÁ 2`...), kiểu Join (6 kiểu: Ngoài trái, Ngoài phải, Ngoài đầy đủ, Trong, Chống trái, Chống phải), dải trạng thái kiểu dữ liệu và số lượng khoá, dựng lệnh `StepCommand.merge`.
- **Append Queries (Nối truy vấn)**: Hộp thoại nối truy vấn với 2 chế độ:
  - "Hai bảng": chọn bảng thứ hai qua menu thả xuống.
  - "Từ ba bảng trở lên": giao diện hai danh sách ("Bảng có sẵn" và "Bảng để nối") kèm nút "Thêm" và "Xoá", dựng lệnh `StepCommand.append`.
- **Group By (Nhóm theo)**: Hộp thoại nhóm dòng với 2 chế độ:
  - "Cơ bản": 1 cột nhóm, 1 phép tổng hợp.
  - "Nâng cao": nhiều cột nhóm (+ Thêm nhóm), nhiều phép tổng hợp (+ Thêm phép tổng hợp) với 7 phép tính (`countRows`, `countDistinctRows`, `sum`, `average`, `median`, `min`, `max`), dựng lệnh `StepCommand.groupBy`.
- **Custom Column (Cột tuỳ chỉnh)**: Hộp thoại nhập tên cột mới, soạn thảo công thức M (font monospace), danh sách cột có sẵn kèm nút chèn `<< Chèn`, kiểm tra cú pháp thời gian thực qua `state.formulaError(...)`, dựng lệnh `StepCommand.addCustomColumn`.
- **Mở rộng cột bảng lồng (Expand Column Popover)**: Popover mở rộng cột bảng lồng sau khi Merge, danh sách các cột con kèm checkbox và huy hiệu kiểu DAX, tuỳ chọn "Dùng tên cột gốc làm tiền tố", dựng lệnh `StepCommand.expandColumn`. Tích hợp nút mở rộng (icon `arrow.left.and.right.square`) trực tiếp trên tiêu đề cột bảng lồng trong `PreviewGridView`.
- **Query Dependencies (Phụ thuộc truy vấn)**: Cửa sổ trực quan hoá đồ thị phụ thuộc (`DependencyGraphModel`), tự động phân tầng cột (Nguồn dữ liệu $\to$ Truy vấn trung gian $\to$ Truy vấn đích), vẽ đường cong Bezier cubic mềm mại kết nối các nút, hỗ trợ chọn nút để tô sáng luồng phụ thuộc (thượng nguồn / hạ nguồn) và bảng thông tin chi tiết, cảnh báo chu trình tham chiếu (nếu có).

Toàn bộ logic được tách thành các struct thuần (không phụ thuộc SwiftUI), có unit test độc lập. Giao diện sử dụng 100% tiếng Việt, tuân thủ bảng mã màu và typography của Design System repo (`Tokens.swift`, `Components.swift`).

---

## 2. Danh sách file tạo mới và sửa đổi

### File tạo mới trong `Sources/BIPro/Query/Editor/Dialogs/`:
1. `MergeDialogModel.swift`: Struct logic thuần cho Merge Queries (quản lý cột trái/phải, khoá ghép có thứ tự, kiểm tra tương thích kiểu dữ liệu `DAXType`, cảnh báo lệch kiểu, dựng `StepCommand.merge`).
2. `MergeDialog.swift`: View `MergeDialogContent` và sheet `MergeDialog`. Hỗ trợ chế độ xuất ảnh `scrollable: false`.
3. `AppendDialogModel.swift`: Struct logic thuần cho Append Queries (chế độ 2 bảng và $\ge 3$ bảng, so sánh số lượng cột trùng/lệch, dựng `StepCommand.append`).
4. `AppendDialog.swift`: View `AppendDialogContent` và sheet `AppendDialog`. Hỗ trợ dual-pane ("Bảng có sẵn" $\leftrightarrow$ "Bảng để nối") và `scrollable: false`.
5. `GroupByDialogModel.swift`: Struct logic thuần cho Group By (chế độ cơ bản / nâng cao, kiểm tra phép tính hợp lệ theo kiểu cột, kiểm tra trùng tên cột, chuyển đổi hai chiều cơ bản $\leftrightarrow$ nâng cao, dựng `StepCommand.groupBy`).
6. `GroupByDialog.swift`: View `GroupByDialogContent` và sheet `GroupByDialog`. Hỗ trợ `scrollable: false`.
7. `CustomColumnDialog.swift`: View `CustomColumnDialogContent` và sheet `CustomColumnDialog` (soạn thảo công thức, kiểm tra lỗi cú pháp M tức thì, danh sách cột chèn đúp). Hỗ trợ `scrollable: false`.
8. `ExpandColumnModel.swift`: Struct logic thuần mở rộng cột bảng lồng (chọn/bỏ chọn tất cả, chọn từng cột, cờ tiền tố, dựng `StepCommand.expandColumn`).
9. `ExpandColumnPopover.swift`: View popover `ExpandColumnContent` và `ExpandColumnPopover`. Hỗ trợ `scrollable: false`.
10. `DependencyLayout.swift`: Struct tính toán toạ độ đồ thị phụ thuộc (xác định tầng cột từ in-degree, tính toạ độ x/y từng nút, tính luồng upstream/downstream, tính toạ độ neo kết nối cho đường cong Bezier).
11. `QueryDependenciesView.swift`: View đồ thị `QueryDependenciesContent` và sheet `QueryDependenciesView` (vẽ lưới toạ độ chấm, đường cong bezier tô sáng, thẻ nút trạng thái, thẻ thông tin chi tiết khi chọn, thanh công cụ thu phóng và căn vừa khung).

### File sửa đổi trong `Sources/BIPro/Query/Editor/`:
1. `QueryRibbonCommand.swift`:
   - Kích hoạt `isAvailable = true` cho `groupByCount`, `unpivotOtherColumns`, `pivot`.
   - Đặt `groupByCount.needsParameters = true` để mở hộp thoại Group By thay vì tự động chạy bước mặc định.
   - Thêm cờ `needsParameters = true` cho `addCustomColumn` để mở hộp thoại Custom Column.
2. `QueryRibbonView.swift`:
   - Thêm nhóm "Kết hợp" (Combine) trên tab Trang chủ chứa nút "Gộp truy vấn" (Merge) và "Nối truy vấn" (Append). Nút mờ kèm tooltip khi không có truy vấn khả dụng để gộp.
   - Thêm nhóm "Quan hệ" (Relationships) trên tab Xem chứa nút "Phụ thuộc truy vấn" (Dependencies).
   - Thêm tooltip cho nút `pivot`.
3. `QueryEditorWindow.swift`:
   - Mở các sheet tương ứng (`MergeDialog`, `AppendDialog`, `GroupByDialog`, `CustomColumnDialog`, `QueryDependenciesView`) qua enum `ActiveSheet`.
   - Xử lý outcome khi người dùng bấm OK: `.applied` đóng sheet; `.needsInsertConfirmation` kích hoạt đúng hộp thoại xác nhận chèn bước đã có; `.rejected(lý do)` giữ nguyên hộp thoại và hiển thị banner lỗi nguy hiểm (danger).
   - Hỗ trợ popover overlay cho `ExpandColumnPopover` khi người dùng nhấn nút mở rộng cột bảng lồng.
4. `PreviewGridView.swift`:
   - Thêm nút mở rộng (icon `arrow.left.and.right.square`) trên tiêu đề các cột bảng lồng (`state.nestedColumnNames.contains(col.name)`).
   - Hiển thị giá trị ô bảng lồng là nhãn "Bảng" (`[Table]`) màu xám nhạt thay vì để trống.
5. `QueryCommandPopovers.swift`:
   - Bỏ trường hợp popover custom column cũ đã được thay thế hoàn toàn bởi hộp thoại mới `CustomColumnDialog`.

### File test tạo mới trong `Tests/BIProTests/Query/Editor/`:
1. `DialogModelsTests.swift`: 7 test suite kiểm tra toàn diện logic thuần của `MergeDialogModel`, `AppendDialogModel`, `GroupByDialogModel`, `ExpandColumnModel`.
2. `DependencyLayoutTests.swift`: 4 test suite kiểm tra thuật toán phân tầng đồ thị, toạ độ, neo kết nối Bezier, và phát hiện luồng phụ thuộc upstream/downstream.
3. `DialogsImageTests.swift`: 6 test suite xuất ảnh PNG độ phân giải Retina 2x cho tất cả các hộp thoại và popover vào `build/f-out/ui/`.

### File test sửa đổi:
1. `Tests/BIProTests/Query/Editor/QueryRibbonCommandTests.swift`: Cập nhật kỳ vọng `isAvailable` của `groupByCount`, `unpivotOtherColumns`, `pivot` từ `false` sang `true`.

---

## 3. Kết quả kiểm tra và xác minh

### A. Kiểm thử tự động (Unit Tests)
- `DialogModelsTests`: **7/7 tests PASSED**
  - `testMergeDialogModelKeysAndValidation`
  - `testMergeDialogModelTypeMismatchWarning`
  - `testAppendDialogModelTwoTablesMode`
  - `testAppendDialogModelThreeOrMoreMode`
  - `testGroupByDialogModelBasic`
  - `testGroupByDialogModelAdvancedAndModeSwitch`
  - `testExpandColumnModel`
- `DependencyLayoutTests`: **4/4 tests PASSED**
  - `testEmptyAndSingleNodeLayout`
  - `testMultiLayerGraphLayout`
  - `testUpstreamAndDownstreamTraversal`
  - `testAnchorPointsAndDimensions`
- `QueryRibbonCommandTests`: **15/15 tests PASSED**
- `DialogsImageTests`: **6/6 tests PASSED**
  - `exportQEMerge`
  - `exportQEMergeExpand`
  - `exportQEAppend`
  - `exportQEGroupBy`
  - `exportQECustom`
  - `exportQEDependencies`

### B. Kiểm tra cách ly Module & Kiến trúc
- `git grep MQuery Sources/BIPro/Query/Editor` $\to$ **Rỗng (0 dòng)**.
- `git grep MEvaluator Sources/BIPro/Query/Editor` $\to$ **Rỗng (0 dòng)**.
Không có bất kỳ sự rò rỉ phụ thuộc nào từ Query Editor vào evaluator hay abstract query engine.

### C. Kiểm tra các chuỗi cấm & thành phần không có trong BI Pro
- Đã quét `git grep` các từ khoá bị cấm: `fuzzy`, `Density`, `SQL Server`, `Lakehouse`, `Dataverse`, `Auto-arrange`, `Tags`. Toàn bộ đều **không xuất hiện** trong các view và model của gói này.

---

## 4. Đánh giá chất lượng các ảnh PNG đã sinh (`build/f-out/ui/`)

Tất cả 7 tệp ảnh đã được kết xuất ở tỉ lệ Retina 2x, lưu tại thư mục `build/f-out/ui/` và được kiểm tra trực quan kỹ lưỡng bằng công cụ đọc ảnh:

| Tên ảnh | Kích thước | Nội dung hiển thị | Đánh giá trực quan |
|---|---|---|---|
| `qe2-merge.png` | 1000 × 760 | Hộp thoại "Gộp truy vấn", đã chọn bảng "Sales" và "Customers", ghép khoá `CustomerID`, kiểu Join `Trong (chỉ hàng khớp)`, bảng xem trước 3 dòng mỗi bên có huy hiệu `KHOÁ 1`. | Thẳng hàng hoàn hảo, bảng xem trước hiển thị đúng huy hiệu kiểu DAX và huy hiệu khoá màu xanh, dải trạng thái xanh báo "Đã chọn 1 cặp cột khoá", nút OK sáng xanh. |
| `qe2-merge-expand.png` | 640 × 480 | Popover mở rộng cột "Orders" sau Merge đính trên tiêu đề bảng, danh sách 3 cột con (`OrderID`, `Amount`, `Status`), bỏ chọn tiền tố, nút OK sáng. | Căn lề thẻ popover chuẩn macOS, bóng đổ mềm mượt, biểu tượng icon mở rộng hai chiều sắc nét, tiếng Việt dấu chuẩn. |
| `qe2-append.png` | 760 × 560 | Hộp thoại "Nối truy vấn" ở chế độ "Từ ba bảng", danh sách bên trái "Bảng có sẵn", nút "Thêm >" và "< Xoá", danh sách bên phải "Bảng để nối" đã chọn 2 bảng (`Doanh số Miền Trung`, `Doanh số Miền Nam`) sau bảng Chính. | Bố cục hai cột đối xứng đúng chuẩn Power BI Desktop, số thứ tự nối đánh dấu bằng huy hiệu tròn xanh, tóm tắt số cột trùng khớp bên dưới. |
| `qe2-groupby.png` | 760 × 560 | Hộp thoại "Nhóm theo" ở chế độ "Nâng cao" với 2 cột nhóm (`Khu vực`, `Loại hàng`) và 2 dòng tổng hợp (`Tổng doanh thu` / `Tổng` / `Doanh thu` và `Số đơn hàng` / `Đếm số dòng`), nút xoá đỏ. | Các dòng nhập liệu căn chỉnh thẳng hàng dọc và ngang (sai lệch < 2 pt), menu thả xuống hiển thị rõ ràng, nút "+ Thêm nhóm" và "+ Thêm phép tổng hợp" nổi bật. |
| `qe2-custom.png` | 900 × 560 | Hộp thoại "Cột tuỳ chỉnh", tên cột `Lợi nhuận`, công thức `= [Doanh thu] - [Giá vốn]`, bảng cột có sẵn bên phải kèm nút `<< Chèn`, trạng thái xanh "Không phát hiện lỗi cú pháp.". | Khung soạn thảo monospace font sạch sẽ, danh sách cột hiển thị rõ ràng từng loại dữ liệu, nút OK sáng. |
| `qe2-custom-error.png` | 900 × 560 | Hộp thoại "Cột tuỳ chỉnh" với công thức lỗi cú pháp `[Doanh thu] - `, viền khung chuyển màu đỏ cảnh báo, thông báo lỗi đỏ chi tiết dòng/cột. | Viền đỏ nổi bật, nút OK mờ (opacity 0.4) và bị vô hiệu hoá chính xác. |
| `qe2-dependencies.png` | 1000 × 640 | Cửa sổ "Phụ thuộc truy vấn" với đồ thị 5 nút: nguồn tệp `sales_2024.csv`, 2 truy vấn tuần tự, 1 truy vấn Merge `Hiệu suất bán hàng` (được chọn, viền xanh sáng) và 1 truy vấn tắt nạp `Dữ liệu nháp` (chữ nghiêng mờ). | Đồ thị phân 3 cột chuẩn xác, đường cong Bezier cubic mượt mà, đường liên kết đến nút đang chọn được tô màu xanh, bảng thông tin chi tiết góc dưới hiển thị đủ số nút thượng nguồn/hạ nguồn. |

---

## 5. Quyết định kỹ thuật (Design Decisions)

1. **Phân tách Model logic thuần & View**:
   - `MergeDialogModel`, `AppendDialogModel`, `GroupByDialogModel`, `ExpandColumnModel`, `DependencyLayout` hoàn toàn độc lập với SwiftUI Framework. Điều này cho phép viết unit test bao phủ toàn bộ các case biên (validation, clashing names, type mismatches, order transitions) nhanh chóng và tin cậy.
2. **Cơ chế render không scrollable (`scrollable: false`)**:
   - Trong môi trường headless test với macOS 15 `ImageRenderer`, các điều khiển AppKit native như `NSTextField`, `NSMenu`, và `NSScrollView` thường gặp lỗi hiển thị (vẽ rỗng hoặc hiển thị thanh vàng có biểu tượng cấm 🚫).
   - Thiết kế đã triển khai cơ chế: khi `scrollable: false`, view tự động chuyển sang sử dụng các thành phần vector SwiftUI thuần (`Text`, `HStack`, `VStack`, custom dropdown labels) giữ nguyên 100% hình thức đồ hoạ của Design System, đảm bảo ảnh chụp kiểm thử luôn sắc nét và không bao giờ bị lỗi render.
3. **Dual-Pane cho Append "Từ ba bảng trở lên"**:
   - Thay vì checkbox đơn giản, bố cục được nâng cấp thành dạng 2 danh sách ("Bảng có sẵn" $\leftrightarrow$ "Bảng để nối") với các nút điều hướng "Thêm" và "Xoá", giống trải nghiệm Power BI Desktop thực tế.
4. **Hiển thị trực quan cột bảng lồng**:
   - Thay vì để trống các ô dữ liệu lồng trong lưới preview, bảng hiển thị nhãn nhẹ "Bảng" và tích hợp nút icon mở rộng ngay trên tiêu đề cột, mang lại trải nghiệm tương tác liền mạch sau thao tác Merge.

---

## 6. Đề xuất cho Lead

1. **Thêm hỗ trợ tìm kiếm trong danh sách cột có sẵn**:
   - Ở hộp thoại Custom Column, với các bảng có trên 50 cột, một ô lọc tìm kiếm nhỏ phía trên danh sách "Cột có sẵn" sẽ giúp người dùng nhanh chóng tìm được cột cần chèn vào công thức.
2. **Hỗ trợ sắp xếp thứ tự bảng trong Append**:
   - Có thể bổ sung hai nút "Lên" (Move Up) và "Xuống" (Move Down) bên cạnh danh sách "Bảng để nối" để người dùng dễ dàng đổi thứ tự ghép bảng mà không cần xoá đi chọn lại.

---

## 7. Trạng thái Git

- Theo đúng quy định, **không thực hiện `git commit`** và **không thực hiện `git push`**.
- Trạng thái `git status` và `git diff --stat` hoàn toàn sạch sẽ, chỉ chứa các tệp thuộc phạm vi được giao.
