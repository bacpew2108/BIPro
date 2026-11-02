Bạn làm việc trong repo Swift "BI Pro", một ứng dụng macOS (SwiftUI/AppKit, macOS 15) giống Power BI Desktop. Bạn đang ở một git worktree riêng, tách từ `main`.

## Mục tiêu (gói R2, Phase C)

Viết renderer cho 3 loại visual: **card**, **slicer dạng Dropdown**, và **matrix**. Renderer vẽ từ dữ liệu đã chuẩn bị sẵn, **không biết DAX, không gọi engine**.

**Hợp đồng có sẵn, đọc kỹ trước, KHÔNG sửa:**
- `Sources/BIPro/Visuals/Query/DataView.swift`: `SingleValueData`, `SlicerData`/`SlicerNode`, `MatrixData`/`MatrixHeader`, `DataCell` (có `fontColor`, `backColor`, `icon` lấy từ measure).
- `Sources/BIPro/Visuals/Format/VisualFormat.swift`: `dataLabels`, `categoryLabels`, `slicer`, `matrix`, `gradients: [GradientRule]`.
- `Sources/BIPro/Visuals/Format/NumberDisplay.swift`: mọi số đi qua đây.
- `Sources/BIPro/Visuals/Interaction/InteractionTypes.swift`: `VisualRenderContext`, `VisualActions` (`slicerChanged`, `drill(.toggle(...))`, `select`), `SlicerSelection`.
- `Sources/BIPro/Visuals/Fixtures/DataViewSamples.swift`: mẫu `cardCreditInflow`, `cardDeltaLabel`, `slicerYearQuarterMonth`, `matrixAgeByRegion` + `matrixAgeByRegionGradient`.
- `Sources/BIPro/Formatting.swift`: `ReportTheme.color(_:)`, `Color(hex:)`, `Color.mixed(with:by:)`.

Ảnh Power BI để làm theo, trong `docs/phase-c-evidence/observe-c1/shots/`:
- `page-D1.png`: hàng card trên cùng; 5 slicer; matrix "Giờ × Thứ" có gradient đỏ và icon tam giác; matrix "Nhóm tuổi × Vùng" có ⊞/⊟ và dòng Total;
- `page-D2.png`, `page-D3.png`.

Đọc thêm `docs/phase-c-evidence/C1.md` §1.3 và §2.4.

## Chỉ được sửa hoặc tạo các file sau

- Sources/BIPro/Visuals/Cards/** (mới; ví dụ CardVisual.swift)
- Sources/BIPro/Visuals/Slicer/** (mới; ví dụ DropdownSlicer.swift, SlicerTree.swift)
- Sources/BIPro/Visuals/Matrix/** (mới; ví dụ MatrixVisual.swift, MatrixLayout.swift, MatrixGradient.swift)
- Tests/BIProTests/Card/**, Tests/BIProTests/Slicer/**, Tests/BIProTests/Matrix/** (mới)

KHÔNG sửa file nào khác, kể cả các file hợp đồng ở trên, `Package.swift`, `Sources/BIPro/Report/**`, `Sources/BIPro/Visuals/Charts/**`, `Sources/DAXEngine/**`. Nếu thấy hợp đồng thiếu gì thì ghi vào báo cáo cuối; đừng tự sửa.

Hai worker khác đang làm song song:
- một người sửa `Sources/DAXEngine`;
- một người sửa `Sources/BIPro/Visuals/Charts`.

Thêm:
- Không commit, không push, không cài package, không tải từ mạng.
- Không đọc hay ghi gì trong `~/Downloads`.
- Chỉ dùng SwiftUI, AppKit. Không thêm thư viện.

## API công khai cần có (tên giữ đúng)

```swift
struct CardVisualView: View { init(data: SingleValueData, context: VisualRenderContext) }
struct DropdownSlicerView: View { init(data: SlicerData, title: String?, context: VisualRenderContext) }
struct MatrixVisualView: View { init(data: MatrixData, context: VisualRenderContext) }
```

## 1. Card

Ví dụ thật: card "Tiền vào" của Nhom6 có
- `labels`: fontSize 20, color `#2E7D32`, labelDisplayUnits 0 (tự động);
- `categoryLabels`: show true, color `#6A7179`, fontSize 10.

Card Δ thì chỉ có `labels.fontSize = 9`, `categoryLabels.show = false`, và màu chữ lấy từ measure (`DataCell.fontColor`).

Cách vẽ:
- **Giá trị** căn giữa, đậm vừa, cỡ `dataLabels.fontSize` (pt; mặc định 27 [SUY ĐOÁN]).
  - Số đi qua `NumberDisplay.text(cell, units: dataLabels.displayUnits, precision: dataLabels.precision)`. Đơn vị Auto chọn theo chính giá trị.
  - Chuỗi thì hiện nguyên văn.
  - Màu chữ theo ưu tiên: `DataCell.fontColor` > `dataLabels.color` (giải qua `theme.color`) > `theme.foreground`.
- **Nhãn danh mục** (`measure.displayName`) nằm dưới giá trị, màu xám, cỡ `categoryLabels.fontSize` (mặc định 12). Ẩn khi `categoryLabels.show == false`.
- Giá trị **BLANK** hiện "(Trống)", như Power BI hiện "(Blank)".
- Chữ quá dài thì co lại (`minimumScaleFactor`), không xuống dòng.
- Hàm thuần để test: `CardVisual.text(for: SingleValueData, format: VisualFormat) -> String` và `CardVisual.valueColor(...)`.

## 2. Slicer Dropdown

Nhom6 có 17 slicer, đều dạng Dropdown. Ví dụ slicer "Năm, Quý, Tháng": `header` show true, fontColor `#14213D`, textSize 10.

**Khi đóng** (ảnh page-D1):
- tiêu đề (`title`, hoặc tên các cấp nối bằng ", ") cỡ `slicer.headerTextSize`, màu `headerFontColor`; ẩn khi `headerShow == false`;
- dưới tiêu đề là một ô viền mảnh xám, bên trái là nội dung, bên phải là dấu ⌄;
- nội dung là "All" khi chưa chọn gì (giữ chữ "All" như Power BI), tên giá trị khi chọn 1, "Nhiều lựa chọn" khi chọn nhiều.

**Bấm ô thì mở danh sách thả xuống** (popover hoặc panel, nền trắng, giao diện sáng):
- Dòng đầu: "Chọn tất cả" (ô vuông). Bấm vào thì bỏ mọi lựa chọn, tức trạng thái "All".
- Mỗi giá trị một dòng: ô vuông + nhãn.
  - Nút có con: thêm ▸/▾ ở trước để mở/đóng cấp con.
  - Cấp con thụt lề 16 pt.
  - Nhãn của giá trị BLANK là "(Trống)".
  - Số nguyên/ngày hiện bằng `NumberDisplay.plain`.
- **Chọn** (theo Power BI, "single select" mặc định):
  - bấm một dòng thì chỉ chọn dòng đó;
  - giữ ⌘ hoặc Ctrl khi bấm thì thêm/bớt.
  - Chọn nút cha nghĩa là chọn cả nhánh, đường dẫn là `[cha]`. Chọn một nút con thì đường dẫn là `[cha, con]`.
  - Nút cha có một số con được chọn thì ô vuông hiện trạng thái "một phần" (dấu −).
- Mỗi lần đổi gọi `context.actions.slicerChanged(SlicerSelection(...))`.
- Trạng thái hiện tại đọc từ `context.slicerSelection`. Renderer không tự giữ lựa chọn làm nguồn chính, chỉ giữ trạng thái mở/đóng.
- Esc hoặc bấm ra ngoài thì đóng danh sách.
- Danh sách dài (77 chi nhánh) thì cuộn được, cao tối đa khoảng 300 pt.
- Hàm thuần để test (`SlicerTree`):
  - `toggle(selection:path:additive:) -> SlicerSelection`;
  - `state(of path:in selection:roots:) -> .on/.off/.mixed`;
  - `summary(selection:roots:) -> String`.

## 3. Matrix

`MatrixData` đã trải phẳng tiêu đề hàng/cột theo thứ tự hiển thị, có `isSubtotal`, `isGrandTotal`, `hasChildren`, `isExpanded`.

**Bố cục** (ảnh page-D1, matrix dưới bên phải):
- **Góc trên trái:** tên các cấp hàng (ví dụ "Nhóm tuổi"). Tiêu đề cột có nhiều tầng khi có nhiều cấp cột; mỗi tầng có tên cấp ở cột đầu (ví dụ "Vùng").
- **Tiêu đề hàng/cột có cấp con:** ô ⊞ (đang đóng) hoặc ⊟ (đang mở) đứng trước nhãn. Bấm vào thì gọi `actions.drill(.toggle(axis:path:))`.
- **Dòng/cột tổng chung:** nhãn "Total", chữ đậm, có đường kẻ phía trên dòng tổng.
- **Ô giá trị:**
  - căn phải, số qua `NumberDisplay.plain` (theo định dạng của ô; matrix không đổi đơn vị);
  - cỡ chữ `matrix.valuesFontSize`; tiêu đề dùng `rowHeaderFontSize`/`columnHeaderFontSize`.
- **Kích thước:**
  - đệm dòng `matrix.rowPadding`;
  - độ rộng cột theo `matrix.columnWidths[queryRef]` nếu có, không thì tự tính theo nội dung;
  - cuộn ngang và dọc khi tràn, tiêu đề hàng và cột đứng yên khi cuộn.
- **Màu nền gradient** (`format.gradients`, xem `GradientRule`):
  - với measure có queryRef = `rule.target`, nền ô = nội suy min → mid → max theo giá trị;
  - min/max lấy từ các ô **không phải tổng** của measure đó (Power BI lấy qua GROUPBY MINX/MAXX trên các ô không tổng);
  - ô BLANK theo `nullStrategy` ("asZero" thì coi như 0);
  - **không** tô nền ô tổng (dòng/cột Total để trắng, như ảnh page-D1);
  - hàm thuần `MatrixGradient.color(value:min:max:rule:) -> (r,g,b)` hoặc `Color`.
- **Màu và icon từ measure:**
  - `DataCell.backColor` > gradient > trắng;
  - `DataCell.fontColor` > mặc định;
  - `DataCell.icon` là chuỗi `data:image/svg+xml;utf8,<svg…>`: giải mã phần sau dấu phẩy (percent-decoding, ví dụ `%23` → `#`), tạo `NSImage(data:)`, vẽ cỡ 12 pt **trước** số, như icon tam giác ở page-D1.
  - Hàm thuần `MatrixIcon.decodeDataURI(_:) -> Data?`.
- **Chọn ô hoặc tiêu đề:** gọi `actions.select(DataPointID([queryRef: value…]), additive:)`. Ô đang được chọn (có trong `context.selection`) có viền xanh mảnh.
- **Hiệu năng:** matrix 24 × 7, và 77 × 5 khi mở rộng, phải cuộn mượt. Dùng `LazyVStack` hoặc lưới tự vẽ; tính layout bằng struct thuần `MatrixLayout`, không tính lại khi rê chuột.

## Test bắt buộc

- **Card:** chuỗi hiển thị của `cardCreditInflow` là `"$3bn"` (định dạng `\$#,0`, đơn vị tự động; đã khớp ảnh Power BI). Card Δ: màu từ `fontColor`. BLANK hiện "(Trống)". Ẩn nhãn danh mục.
- **SlicerTree:** chọn đơn; ⌘ thêm/bớt; chọn cha rồi bấm con; trạng thái mixed; summary "All", "2016", "Nhiều lựa chọn".
- **Matrix:**
  - `MatrixLayout`: số tầng tiêu đề, độ rộng cột theo `columnWidths`;
  - `MatrixGradient` tại min/mid/max và BLANK với asZero;
  - min/max bỏ qua ô tổng;
  - `decodeDataURI` với chuỗi SVG thật: `data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'><path d='M6 1.5 L11 10.5 L1 10.5 Z' fill='%23FFD54F' stroke='%2367000D' stroke-width='1.2' stroke-linejoin='round'/></svg>`.
- **Xuất ảnh:** một test `@MainActor` render bằng `ImageRenderer` ra PNG ở `build/c-out/visuals/<tên>.png`:
  - card 300×108;
  - card Δ 236×26;
  - slicer đóng 364×64;
  - matrix 688×380, có gradient.
  - Thư mục tính từ `#filePath` lên gốc repo, rồi `build/c-out/visuals`; tự tạo bằng FileManager. Test chỉ kiểm ảnh khác rỗng. Lead sẽ xem ảnh bằng mắt.
- Test có tạo View/AppKit phải đánh dấu `@MainActor`.
- **Không viết cứng kết quả để test qua.**

Lỗi hay gặp ở lần giao việc trước, hãy tránh:
- thiếu `@objc(selector:)` cho hàm xử lý sự kiện của NSObject;
- NSPanel thiếu `isReleasedWhenClosed = false`;
- popover không ép giao diện sáng (`appearance = NSAppearance(named: .aqua)`).

## Lệnh build/test của project

```
swift build --scratch-path .build-wR2
swift test --scratch-path .build-wR2 --filter BIProTests
```

## Tiêu chí xong

- Cả hai lệnh xanh.
- Ảnh PNG được tạo.
- Cuối cùng in:
  - danh sách file đã sửa, mỗi file một dòng tóm tắt;
  - kết quả hai lệnh;
  - đường dẫn ảnh;
  - điều gì chưa làm hoặc thấy hợp đồng thiếu.

## Lệnh shell được phép

Chỉ dùng: swift build, swift test, git status/diff/log/show, ls, cat, grep, rg, head, tail, wc, pwd, find, sed -n, sort, uniq, echo, file.

Lệnh khác sẽ bị từ chối và làm dừng cả phiên. Đọc và sửa file thì dùng công cụ đọc/sửa file của bạn.
