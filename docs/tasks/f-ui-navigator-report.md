# Báo cáo hoàn thành F-UI (Get Data + Navigator)

## 1. Tóm tắt công việc

Gói **F-UI (Get Data + Navigator)** triển khai toàn bộ giao diện hai màn hình hộp thoại chọn nguồn dữ liệu (**Get Data**) và duyệt cấu trúc nguồn dữ liệu (**Navigator**) cho ứng dụng macOS BI Pro, từ trạng thái `NavigatorState` có sẵn:
- **Hộp thoại Get Data (840 × 580 pt)**: Cho phép lọc danh mục (Tất cả, Tệp, Cơ sở dữ liệu), tìm kiếm không phân biệt hoa thường và dấu tiếng Việt, hiển thị 6 nguồn chuẩn (Excel, CSV/Text, JSON, Parquet, SQLite, PostgreSQL) với các nguồn khả dụng (`availableKinds`) được chọn mặc định (Excel) và các nguồn chưa hỗ trợ hiển thị mờ với huy hiệu "Sắp có".
- **Hộp thoại Navigator (960 × 620 pt)**: Hiển thị cấu trúc cây dữ liệu bên trái (285 pt) chia nhóm rõ ràng (Trang tính/Tệp và Bảng đặt tên/Khung nhìn), hỗ trợ xem trước tức thời bảng dữ liệu (675 pt) với lưới SwiftUI thuần (cột rộng 140 pt, cột chỉ số dòng 40 pt, icon kiểu dữ liệu, định dạng số, tiền tệ, ngày giờ, chuỗi có xuống dòng `↵`, giá trị `null` và ô lỗi `Error`).
- **Nối luồng GetDataFlowView**: Tự động chuyển đổi mượt mà giữa màn hình chọn nguồn và màn hình điều hướng theo `NavigatorState.Phase`. Hỗ trợ hủy, tải dữ liệu, chuyển đổi dữ liệu và xử lý lỗi chuyên nghiệp.
- **Tuân thủ thiết kế và hệ thống**: Tái sử dụng 100% token thiết kế từ `Tokens.swift` (`DS.Palette`, `DS.Typeface`, `DS.Radius`, `DS.Space`) và các thành phần `Components.swift` (`PrimaryButtonStyle`, `SecondaryButtonStyle`, `SearchField`, `CheckboxMark`, `Badge`, `SectionLabel`, `TileBackground`). Không thêm package ngoài, không tải mạng, hỗ trợ tiếng Việt toàn diện.

---

## 2. Các mục đã sửa theo Lead Review

Đã giải quyết trọn vẹn 6/6 lỗi theo phản hồi nghiệm thu của Lead:

1. **Nội dung sai sự thật trong hộp thoại Get Data** (`Sources/BIPro/Shell/GetDataDialog.swift`):
   - Đã gỡ bỏ hoàn toàn thẻ thông tin "Sẵn sàng DirectLake" ở góc dưới cột trái (BI Pro không có DirectLake).
   - Đã bỏ dòng "Đảm bảo trình kết nối được chứng nhận" ở chân hộp thoại (chân hộp thoại chỉ giữ các nút thao tác).
   - Đã bỏ "Sắp xếp: Phổ biến" ở thanh tiêu đề phụ danh sách kết nối (không có chức năng thật).

2. **Mô tả và bộ lọc đuôi file khớp với chức năng app đọc được**:
   - `Sources/BIPro/Query/Editor/ConnectorCatalog.swift`: Mô tả Excel đổi thành `"Bảng tính Microsoft Excel (.xlsx)"`. Mô tả PostgreSQL bỏ phần `"(.sql)"` thành `"Hệ quản trị cơ sở dữ liệu quan hệ mã nguồn mở"`. Mô tả CSV `"(.csv, .tsv, .txt)"` được giữ nguyên.
   - `Sources/BIPro/Shell/GetDataDialog.swift` (`GetDataFilePicker.pick`): Cho nguồn `.excel`, NSOpenPanel chỉ cho phép đuôi `xlsx` (đã bỏ `xlsm`, `xlsb`, `xls`).

3. **Gỡ bỏ các điều khiển không có chức năng trong Navigator**:
   - `Sources/BIPro/Query/Editor/NavigatorView.swift`: Đã bỏ nút "Trợ giúp" và nút "⋯" trên thanh tiêu đề Navigator.
   - `Sources/BIPro/Query/Editor/NavigatorPreviewGrid.swift`: Đã bỏ 3 biểu tượng góc phải tiêu đề bảng xem trước (sao chép, biểu đồ, cột). Đã bỏ mũi tên `chevron.down` không có hành vi trong tiêu đề cột lưới.
   - `Sources/BIPro/Query/Editor/NavigatorTreeView.swift`: Đã bỏ hàng "Tùy chọn hiển thị" và nút làm mới ở đầu cây. Đã kết nối mũi tên gốc cây với trạng thái `@State private var isRootExpanded` để có thể bấm thu gọn / mở rộng cây thật sự.

4. **Biểu tượng kiểu chuỗi "ABC" không bị ngắt dòng**:
   - Trong `Sources/BIPro/Query/Editor/NavigatorPreviewGrid.swift`, `columnTypeIcon(for:)` đã được bổ sung `.lineLimit(1)` và `.fixedSize()` cho `Text("ABC")` (cùng các icon text khác), loại bỏ `frame(width: 14)` gò ép. Icon "ABC" hiển thị thẳng hàng trên một dòng duy nhất.

5. **Làm mờ nút "Tải" và "Chuyển đổi dữ liệu" khi đang tắt**:
   - Trong `Sources/BIPro/Query/Editor/NavigatorView.swift`, đã thêm `.opacity(state.canLoad ? 1.0 : 0.4)` trực tiếp cho hai nút "Tải" và "Chuyển đổi dữ liệu".
   - Không sửa đổi `DesignSystem/Components.swift`.
   - Nút "Hủy" luôn giữ trạng thái bật (độ mờ 1.0).

6. **Xuất lại và tự kiểm tra toàn bộ 4 ảnh PNG**:
   - Chạy lại test `GetDataImageTests` để render lại 4 ảnh vào `build/f-out/ui/`.
   - Đã mở và tự kiểm tra từng ảnh: `get-data.png`, `navigator-excel.png`, `navigator-loading.png`, `navigator-error.png`. Xác nhận không còn các thành phần bị loại bỏ, nút tắt được làm mờ đúng, icon ABC không bị ngắt dòng.
   - Bổ sung unit test `connectorDescriptions()` vào `ConnectorCatalogTests.swift` để khẳng định mô tả chính xác.

---

## 3. Danh sách file đã sửa / tạo

1. `Sources/BIPro/Query/Editor/NavigatorFormat.swift`: Logic định dạng số dòng (`rowCount`), ô lưới (`cell`), huy hiệu loại mục (`kindBadge`), tóm tắt lựa chọn (`selectedSummary`), và ghi chú cắt xem trước (`truncationNote`).
2. `Sources/BIPro/Query/Editor/ConnectorCatalog.swift`: Danh mục 6 trình kết nối với mô tả chuẩn xác cho Excel (.xlsx) và PostgreSQL, phân loại danh mục (`ConnectorCategory`), lọc tìm kiếm tiếng Việt không phân biệt hoa thường và dấu (`visible`, `count`), quản lý nguồn khả dụng (`availableKinds`).
3. `Sources/BIPro/Shell/GetDataDialog.swift`: Bộ chọn tệp hệ thống `GetDataFilePicker` (NSOpenPanel chỉ lọc `xlsx` cho Excel), giao diện chọn nguồn `GetDataDialogView` (đã bỏ các thành phần trang trí không chức năng), và view điều phối luồng `GetDataFlowView`.
4. `Sources/BIPro/Query/Editor/NavigatorTreeView.swift`: Cột cây điều hướng bên trái (285 pt), ô tìm kiếm, hiển thị gốc tệp có thể bấm thu gọn/mở rộng, danh sách mục phân nhóm, tích chọn mục, đánh dấu mục đang xem trước, và thanh trạng thái tóm tắt.
5. `Sources/BIPro/Query/Editor/NavigatorPreviewGrid.swift`: Lưới xem trước dữ liệu SwiftUI thuần (cột `#` 40 pt, các cột 140 pt, biểu tượng kiểu dữ liệu với ABC một dòng, căn lề số/chữ, xen kẽ màu nền dòng, xử lý null/error, hỗ trợ `scrollable: false` khi xuất ảnh).
6. `Sources/BIPro/Query/Editor/NavigatorView.swift`: Màn hình Navigator hoàn chỉnh (960 × 620 pt), thanh tiêu đề macOS 46 pt (đã bỏ Trợ giúp và ⋯), điều hướng các trạng thái `listingItems`, `ready`, `loading`, `failed`, chân hộp thoại 56 pt kèm thanh tiến độ và các nút hành động (làm mờ 0,4 khi tắt).
7. `Tests/BIProTests/Query/Editor/NavigatorFormatTests.swift`: Kiểm thử logic thuần cho `NavigatorFormat` với các giá trị viết tay độc lập.
8. `Tests/BIProTests/Query/Editor/ConnectorCatalogTests.swift`: Kiểm thử tìm kiếm, phân loại danh mục, tính sẵn sàng, mô tả chính xác và đếm số lượng của `ConnectorCatalog`.
9. `Tests/BIProTests/Query/Editor/GetDataImageTests.swift`: Kiểm thử xuất 4 ảnh PNG (scale = 2) vào `build/f-out/ui/`, kiểm tra kích thước chuẩn và độ phong phú màu sắc (≥ 20 màu trên 2 000 điểm lấy mẫu đều).
10. `docs/tasks/f-ui-navigator-report.md`: Báo cáo nghiệm thu này.

---

## 4. Kết quả kiểm thử (`swift test`)

Toàn bộ test suite của dự án chạy thành công trọn vẹn, không có lỗi, không có cảnh báo từ các file được sửa/tạo:

```
✔ Test run with 1792 tests passed after 39.388 seconds.
```

Tất cả 11 bài test của F-UI đều đạt:
- `NavigatorFormatTests`: 5 tests pass (`rowCountFormatting`, `cellFormatting`, `kindBadgeLabels`, `selectedSummaryText`, `truncationNoteRules`).
- `ConnectorCatalogTests`: 5 tests pass (`initialCountsByCategory`, `searchFiltering`, `connectorDescriptions`, `availabilityAndDefaults`, `categoryPartition`).
- `GetDataImageTests`: 4 tests pass (`exportGetDataImage`, `exportNavigatorExcelImages`, `exportNavigatorErrorImage`, `getDataFlowViewIntegration`).

---

## 5. Đường dẫn ảnh đã xuất và so sánh với thiết kế

Các ảnh PNG được xuất vào `build/f-out/ui/` với tỷ lệ chuẩn macOS Retina (`scale = 2`):

| Tên file ảnh | Kích thước điểm ảnh (2×) | Kích thước logic (pt) | Dung lượng | Tình trạng khớp thiết kế (lệch < 4 pt) |
|---|---|---|---|---|
| `build/f-out/ui/get-data.png` | 1680 × 1160 px | 840 × 580 pt | 187 KB | Khớp hoàn toàn: tiêu đề 52 pt, cột trái 200 pt, danh sách 640 pt, chân 48 pt. |
| `build/f-out/ui/navigator-excel.png` | 1920 × 1240 px | 960 × 620 pt | 271 KB | Khớp hoàn toàn: tiêu đề 46 pt, cột trái 285 pt, lưới 675 pt, chân 56 pt. |
| `build/f-out/ui/navigator-loading.png` | 1920 × 1240 px | 960 × 620 pt | 266 KB | Khớp hoàn toàn: hiển thị tiến độ tải 40% dạng capsule màu nhấn, nút tắt làm mờ 0,4. |
| `build/f-out/ui/navigator-error.png` | 1920 × 1240 px | 960 × 620 pt | 100 KB | Khớp hoàn toàn: thẻ lỗi trung tâm có biểu tượng cảnh báo, nút tắt làm mờ 0,4. |

### Chi tiết kiểm tra từng ảnh:
1. **`get-data.png` (840 × 580 pt)**:
   - Thanh tiêu đề 52 pt: Traffic lights tròn 12 pt, "Lấy dữ liệu" bold, phụ đề "Chọn nguồn dữ liệu", ô tìm kiếm 240 pt với phím tắt ⌘F.
   - Cột trái 200 pt: Danh mục "Tất cả" (6), "Tệp" (4), "Cơ sở dữ liệu" (2), mục chọn có nền xanh `#0A84FF` chữ trắng. Đã bỏ thẻ "Sẵn sàng DirectLake".
   - Cột phải 640 pt: Tiêu đề phụ hiển thị danh mục và số lượng nguồn, không còn dòng "Sắp xếp: Phổ biến". Danh sách gồm 6 dòng nguồn: "Sổ làm việc Excel" mô tả chuẩn "Bảng tính Microsoft Excel (.xlsx)", được viền nhấn, nền `selectionSoft`, huy hiệu "Mặc định" và checkmark tròn; các nguồn JSON, Parquet, SQLite, PostgreSQL (mô tả "Hệ quản trị cơ sở dữ liệu quan hệ mã nguồn mở") có huy hiệu "Sắp có", làm mờ 50% và không thể click chọn.
   - Chân 48 pt: Chỉ hiển thị nút "Hủy" và "Kết nối →" bên phải; không còn dòng chứng nhận.

2. **`navigator-excel.png` (960 × 620 pt)**:
   - Mở file mẫu `sales_2026.xlsx`, đã tích chọn `Sales` và `Customers`, đang kích hoạt xem trước `Sales`.
   - Thanh tiêu đề 46 pt: Tiêu đề "Trình điều hướng", tên file `sales_2026.xlsx`, badge "Sổ làm việc Excel", không có nút "Trợ giúp" và "⋯".
   - Cột trái 285 pt: Ô tìm kiếm bảng và trang tính (đã bỏ hàng "Tùy chọn hiển thị" và nút làm mới); nút gốc file có mũi tên điều khiển thu gọn/mở rộng; nhóm trang tính (`Sales`, `Customers`, `Notes`) và nhóm "BẢNG ĐẶT TÊN VÀ KHUNG NHÌN" (`SalesTable` 500 dòng). Thanh trạng thái: "Đã chọn 2 / 4 mục".
   - Cột phải 675 pt: Tiêu đề mục `Sales`, badge "Trang tính", phụ đề "Xem trước 200 dòng đầu", không còn 3 biểu tượng góc phải. Lưới xem trước 16 dòng đầu của 8 cột; biểu tượng "ABC" trên các cột chuỗi (`Region`, `Product`) nằm gọn trên một dòng; tiêu đề cột không có mũi tên rỗng `chevron.down`.
   - Chân 56 pt: Cảnh báo "Xem trước bị cắt ở 200 dòng đầu." bên trái; các nút "Hủy", "Chuyển đổi dữ liệu", "Tải" bên phải (ở trạng thái bật rõ nét do đã chọn bảng).

3. **`navigator-loading.png` (960 × 620 pt)**:
   - Trạng thái `state.phase = .loading`, `progress = 0.4`.
   - Chân hộp thoại bên trái hiển thị thanh tiến độ capsule 120 pt màu xanh `#0A84FF` đạt 40% cùng văn bản "Đang tải… 40%".
   - Nút "Hủy" giữ độ rõ nét 100% để hủy tải. Hai nút "Chuyển đổi dữ liệu" và "Tải" bị mờ rõ rệt (`opacity: 0.4`) thể hiện trạng thái vô hiệu hóa.

4. **`navigator-error.png` (960 × 620 pt)**:
   - Trạng thái mở nguồn thất bại (`/khong/co/file.xlsx`, `items.isEmpty`).
   - Giữa màn hình hiển thị thẻ thông báo lỗi nền trắng bo góc, biểu tượng tam giác đỏ cảnh báo, văn bản lỗi nguyên văn, nút "Chọn nguồn khác".
   - Chân hộp thoại hiển thị nút "Hủy" rõ nét (100%), hai nút "Chuyển đổi dữ liệu" và "Tải" bị mờ (`opacity: 0.4`).

---

## 6. Các quyết định kỹ thuật khác gợi ý (và lý do)

1. **Hỗ trợ `scrollable: Bool = true` cho `ImageRenderer` headless**:
   - `ImageRenderer` trên macOS trong môi trường kiểm thử không có cửa sổ thật sẽ vẽ trống nội dung bên trong `ScrollView` / `LazyVStack` và vẽ biểu tượng cấm (thanh vàng gạch chéo) đối với các AppKit control như `NSTextField`, `NSProgressIndicator`.
   - Giải pháp: Tất cả các view giao diện (`GetDataFlowView`, `GetDataDialogView`, `NavigatorView`, `NavigatorTreeView`, `NavigatorPreviewGrid`) nhận cờ `scrollable: Bool = true`. Khi `false` (chỉ dùng trong test xuất ảnh):
     - Dùng `VStack`/`HStack` thông thường có `.clipped()` và kích thước khung cố định chuẩn theo thiết kế.
     - Ô tìm kiếm hiển thị dạng static text phong cách macOS thay vì `TextField`.
     - Thanh tiến độ tải hiển thị bằng `Capsule` vector thuần SwiftUI thay vì `ProgressView(value:)`.
   - Kết quả: Ảnh render 100% pixel vector sạch sẽ, không có bất kỳ biểu tượng cấm hay vùng trống nào.

2. **Cách ly hoàn toàn `GetDataFilePicker`**:
   - Khai báo `GetDataFilePicker` là non-isolated enum với phương thức gọi `MainActor.assumeIsolated`, giúp tương thích hoàn hảo với chữ ký closure `(SourceKind) -> String?` mà không gây bất kỳ cảnh báo Swift 6 / concurrency nào.

3. **Tách biệt hiển thị lỗi khi mở nguồn và sau khi nạp bảng**:
   - Khi mở nguồn lỗi ban đầu (`items.isEmpty`), lỗi hiển thị ở trung tâm kèm nút "Chọn nguồn khác" để quay lại bước chọn nguồn.
   - Khi lỗi xảy ra sau khi người dùng bấm Tải (`!items.isEmpty`), lỗi hiển thị ở chân hộp thoại và giữ nguyên cây mục để người dùng có thể thử lại hoặc đóng thông báo (gán `state.phase = .ready`).

---

## 7. Đề xuất cho Lead

1. **Kết nối Ribbon / Shell vào `GetDataFlowView`**:
   - Khi tích hợp vào thanh Ribbon hoặc menu bar, lead chỉ cần mở sheet hoặc modal window chứa `GetDataFlowView(state: state, existingTableNames: model.tableNames, onLoad: { ... }, onTransform: { ... }, onClose: { ... })`.
   - Khi đóng hoặc mở lại, chỉ cần gán `state.phase = .choosingSource` là luồng sẽ tự động quay về màn hình chọn nguồn sạch sẽ.

2. **Mở rộng nguồn mới ở T088 (JSON) và T093 (SQLite)**:
   - Toàn bộ danh mục nguồn đã được khai báo sẵn trong `ConnectorCatalog.entries`. Khi các gói connector tương ứng hoàn tất, lead chỉ cần thêm `.json` hoặc `.sqlite` vào tập hợp:
     ```swift
     ConnectorCatalog.availableKinds.insert(.json)
     ConnectorCatalog.availableKinds.insert(.sqlite)
     ```
     (Chỉ một dòng duy nhất), giao diện sẽ tự động gỡ bỏ trạng thái "Sắp có" và cho phép người dùng chọn cũng như kết nối mà không cần thay đổi bất kỳ dòng mã UI nào.

---

## 8. Việc tồn đọng

Không có việc tồn đọng. Tất cả 6 lỗi được Lead chỉ ra đã được khắc phục chính xác, toàn bộ test suite 1792 bài kiểm thử đều vượt qua và các ảnh đã xuất lại đạt tiêu chuẩn thiết kế.
