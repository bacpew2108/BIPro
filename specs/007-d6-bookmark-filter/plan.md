# Kế hoạch triển khai: D6, bookmark và bộ lọc người dùng ghi vào `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/007-d6-bookmark-filter/spec.md`

## Tóm tắt

Bookmark và bộ lọc người dùng hiện chỉ sống trong `ReportInteraction`. D6 biến chúng thành **thay đổi của tài liệu** khi người dùng đang ở chế độ Sửa: hoàn tác chung, đánh dấu chưa lưu, ghi vào file bằng ghép byte, kiểm trước khi ghi. Chi tiết quyết định ở [research.md](research.md).

Hướng chọn:

1. **Cổng quan sát VM-D6 đứng trước mã ghi.** Chưa có mẫu Desktop cho bookmark chỉ-Display mặc định (Nhom6 chỉ có dạng "Selected visuals" tác giả đặt), bookmark Data tối thiểu, Advanced, Top N, xoá bookmark cuối. Làm buổi VM-D6 trước (Claude điều khiển VM khi người dùng cho phép lần đó, hoặc người dùng làm tay), ghi `docs/phase-d-evidence/vm-d6/QUAN-SAT.md`, rồi mới viết bộ ghi của từng dạng. Dạng chưa quan sát: **không ghi**, giữ trong phiên và báo (SC-005).
2. **Xem chỉ để xem; hai lớp trạng thái.** Quyết định của người dùng (2026-11-11): sửa bookmark và bộ lọc chỉ ở chế độ Sửa; ở Xem các thao tác sửa mờ kèm lý do, chỉ bấm bookmark để áp được. Lớp *tài liệu* mới `ReportEdits` nằm trong `LayoutEditor`: mọi thao tác sửa bookmark và thẻ lọc đi vào đây, vào ảnh chụp hoàn tác và dấu chưa lưu. Lớp *phiên* hiện có (`userFilters`, `removedFilters`, `states`… trong `ReportInteraction`) chỉ còn là trạng thái xem do áp bookmark và slicer; không bao giờ được ghi. Chỗ đọc (vẽ visual, Filters pane) dùng giá trị gộp *file, tài liệu, phiên*. Lý do: áp bookmark có Data đổi bộ lọc và slicer là xem, không được thành thay đổi của file.
3. **Ghi bằng ghép byte, qua đường lưu của D1.** `PBIXKit` thêm `PBIRBookmarkPatch` (thêm item, đổi `displayName`, xoá item và file, đổi thứ tự, dựng file bookmark mới theo mẫu Desktop) và `PBIRFilterPatch` (thêm, thay, bỏ thẻ trong `filterConfig.filters` của `report.json`, `page.json`, `visual.json`). `makeChanges` so trạng thái mong muốn với **file trên đĩa** như D5 (nên lưu nhiều lần không ghi lại phần đã khớp); phần chưa đổi chép nguyên byte.
4. **Chuyển đổi trạng thái phiên sang JSON ở `BIPro`, ghi ở `PBIXKit`.** `BookmarkExport` (BIPro) biến `UserBookmark` thành `BookmarkSpec` (giá trị thuần, `PBIXKit`); `FilterExport` biến `UserFilter` thành thẻ lọc. Mỗi hàm có kết quả "ghi được" hoặc "chỉ trong phiên" kèm lý do; Bookmarks và Filters pane hiện nhãn khi chưa ghi được.
5. **Kiểm khi lưu mạnh hơn.** `verifyLayout` thêm: mọi item trong `bookmarks.json` có file và ngược lại (đã có từ D5), `targetVisualNames` và `visualContainers` chỉ trỏ visual có thật, `activeSection` trỏ trang có thật, mọi thẻ lọc parse lại được và khớp thẻ mong muốn. Sai thì từ chối, file đích nguyên vẹn.
6. **Phối hợp D1 và D5.** Xoá visual bỏ nó khỏi `visualContainers` (D1 R14) và nay cả `targetVisualNames`; xoá trang gỡ bookmark (D5) và các bookmark mới tạo trong phiên trỏ trang đó cũng gỡ; bộ lọc cấp visual của visual đã xoá, cấp trang của trang đã xoá bỏ theo.

**Bảo đảm nguyên vẹn**: part không đổi khớp byte; `DataModel` không đụng; golden Phase B/C giữ nguyên; file gốc `~/Downloads` chỉ đọc; `SecurityBindings` bỏ như D1 (R13).

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (ghi, ghép byte), `BIPro` (giao diện, editor)

**Phụ thuộc chính**: không thêm (Hiến pháp III)

**Lưu trữ**: `.pbix` PBIR; đường lưu, sao lưu như D1

**Kiểm thử**: `swift test` (1200 hiện có); thêm `PBIXKitTests/{PBIRBookmarkPatchTests, PBIRFilterPatchTests}`, `BIProTests/Edit/{ReportEditsTests, BookmarkExportTests, FilterExportTests, BookmarkFilterUndoTests, BookmarkFilterSavingTests}`, test nặng `D6Nhom6`; golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|D4Nhom6|D6Nhom6|EditNhom6|BatchedSerial"`; chụp cửa sổ app; gói thử tay `build/d-out/D6/`

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: thao tác bookmark/lọc vào bộ nhớ dưới 100 ms (SC-004); lưu dưới 1 s (SC-003)

**Ràng buộc**: như D1; không ghi dạng chưa quan sát; Xem không làm bẩn file và không sửa được bookmark hay bộ lọc

**Quy mô**: Nhom6: 2 bookmark (cùng trang `d1_giaodich`), 2 thẻ lọc cấp báo cáo, 1 cấp trang (`d4_chinhanh`), 1 cấp visual; mẫu Data `~/Downloads/C2_A/bookmark-data.pbix` (20 KB một bookmark)

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Cấu trúc đọc từ Nhom6 và `bookmark-data.pbix` (research R1). Các dạng ghi chưa quan sát bị chặn đến khi VM-D6 xong (research R2 liệt kê). Chưa có quan sát thì đánh dấu `[SUY ĐOÁN]` trong code và bằng chứng |
| II. Power BI là chuẩn | Qua | Không đổi đường tính. Bộ lọc người dùng đã lưu phải cho cùng số liệu khi mở lại (SC-001, test `D6Nhom6`); golden Phase B/C chạy lại |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads`; test ghi `build/d-out/`. VM-D6 do Claude điều khiển chỉ khi người dùng cho phép lần đó (như VM-D1 đến D5) |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ở `contracts/`; `PBIXKit` (ghi) tách `BIPro` (chuyển đổi, giao diện); lát này lead tự làm (`LayoutEditor`, `DocumentState`, `ReportInteraction` giao nhau); bảng quyền ở `docs/phase-d-ownership.tsv` |

Sau thiết kế (Phase 1): không phát sinh vi phạm. Điểm theo dõi: kết quả VM-D6 có thể làm nhỏ hoặc mở rộng phạm vi ghi (Data, Advanced, Top N).

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/007-d6-bookmark-filter/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── bookmark-editing.md   # hành vi: thao tác bookmark, định tuyến Xem/Sửa, "chỉ trong phiên", hoàn tác
│   ├── filter-editing.md     # hành vi: thao tác thẻ lọc, định tuyến, hoàn tác
│   └── bookmark-filter-save.md  # ghi gì cho từng thao tác, kiểm lúc lưu
├── checklists/requirements.md
└── tasks.md                  # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
├── PBIRBookmarkPatch.swift     # MỚI: BookmarkSpec, file bookmark mới, item thêm/xoá/đổi thứ tự, displayName, bỏ targetVisualNames
└── PBIRFilterPatch.swift       # MỚI: filterConfig.filters ở report/page/visual: thêm, thay, bỏ thẻ; dựng thẻ Categorical (và dạng khác sau VM-D6)

Sources/BIPro/Report/Edit/
├── ReportEdits.swift           # MỚI: ReportEdits (giá trị thuần: thay đổi bookmark và thẻ lọc), luật gộp
├── BookmarkExport.swift        # MỚI: UserBookmark → BookmarkSpec hoặc "chỉ trong phiên" + lý do
├── FilterExport.swift          # MỚI: UserFilter → thẻ lọc hoặc "chỉ trong phiên" + lý do
├── LayoutEditor.swift          # SỬA: LayoutSnapshot có edits, isDirty, markSaved, makeChanges ghi bookmark và lọc
├── LayoutEditor+Report.swift   # MỚI: thao tác addBookmark/updateBookmark/rename/delete/move, setFilter/removeFilter, mỗi cái một bước hoàn tác
└── DocumentSaver.swift         # SỬA: verifyLayout kiểm bookmark và lọc

Sources/BIPro/Report/
├── ReportInteraction.swift     # SỬA: giá trị gộp (tài liệu rồi phiên) cho lọc và bookmark; định tuyến theo chế độ
├── UserBookmark.swift          # SỬA: bookmarkRows đọc cả lớp tài liệu
└── LiveVisual.swift            # SỬA: LoadKey theo giá trị gộp

Sources/BIPro/
├── DocumentState.swift         # SỬA: bọc thao tác bookmark/lọc (chọn lớp theo chế độ)
└── Panes/ReportPanes.swift, FilterEditor.swift   # SỬA: gọi qua DocumentState; nhãn "chỉ trong phiên"

Tests/PBIXKitTests/{PBIRBookmarkPatchTests, PBIRFilterPatchTests}.swift
Tests/BIProTests/Edit/{ReportEditsTests, BookmarkExportTests, FilterExportTests, BookmarkFilterUndoTests, BookmarkFilterSavingTests, D6Nhom6Tests}.swift
docs/phase-d-ownership.tsv      # SỬA: thêm file D6
docs/phase-d-evidence/vm-d6/    # quan sát VM-D6, kết quả, ảnh
build/d-out/D6/                 # gói thử tay + CHECKLIST.md
```

**Quyết định cấu trúc**: `PBIRBookmarkPatch` và `PBIRFilterPatch` nằm ở `PBIXKit` (không phụ thuộc giao diện, dùng lại ở CLI); luật gộp hai lớp và "chỉ trong phiên" nằm ở `BIPro` dưới dạng giá trị thuần để test không cần cửa sổ.

## Theo dõi độ phức tạp

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Hai lớp (phiên và tài liệu) | Áp bookmark có Data đổi bộ lọc và slicer trong lúc xem, không được lẫn với thay đổi cần lưu | Một lớp chung: áp bookmark làm file bẩn, hoặc bộ lọc người dùng sửa bị bookmark ghi đè khi lưu |
| Cổng VM-D6 trước mã ghi | Bookmark mặc định, Data, Advanced, Top N chưa có mẫu Desktop | Ghi theo đoán: Desktop có thể báo hỏng file (bài học D1: `SecurityBindings`) |
