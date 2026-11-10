# Kế hoạch triển khai: D5, quản lý trang và lưu `.pbix` tầng T1

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-10 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/005-d5-quan-ly-trang/spec.md`

## Tóm tắt

Cho người dùng thêm, đổi tên, đổi thứ tự, nhân bản và xoá trang ở chế độ Sửa; thanh tab hiện ngay; hoàn tác chung với D1 đến D3; lưu T1 mở được trong Power BI Desktop. Quyết định chi tiết ở [research.md](research.md).

Hướng chọn:

1. **Cấu trúc trang là một phần của trạng thái sửa.** `LayoutEditor` hiện chỉ biết sửa bên trong các trang có sẵn (`PageEdit`). D5 thêm `PageStructure` (thứ tự tab, tên đổi, trang tạo trong phiên, trang đã xoá, bookmark đã gỡ, trang mở khi lưu). Trang tạo trong phiên dùng lại nguyên `PageEdit` và `edit.added` của D1/D3 để chứa visual của nó, nên mọi thao tác visual (kéo, thả trường, thêm visual) chạy trên trang mới mà không đổi.
2. **Một đường hoàn tác duy nhất, ảnh chụp toàn trạng thái.** `LayoutSnapshot` chuyển từ "một trang" sang "toàn bộ `edited` + `PageStructure` + trang đang mở + vùng chọn" (giá trị, copy-on-write nên rẻ). Với lịch sử tuyến tính thì tương đương cách cũ, và thao tác cấp báo cáo (thêm, xoá cả trang) là một bước như mọi bước khác; hoàn tác xoá trang phục hồi trang, visual và bookmark đã gỡ.
3. **Ghi bằng ghép byte, qua đường lưu của D1.** Bộ ghi `PBIXWriter` đã có thêm, thay, bớt part. D5 thêm `PBIRPagePatch` (PBIXKit): sửa `pageOrder` và `activePageName` của `pages.json`, `displayName` của `page.json`, dựng `page.json` cho trang mới theo mẫu Desktop (VM-D5), nhân bản `page.json` và `visual.json` với mã mới, và gỡ tham chiếu trang trong bookmark. Phần không sửa khớp từng byte; `DocumentSaver.verifyLayout` kiểm cả cấu trúc trang.
4. **Theo Desktop ở điều đã quan sát, thận trọng ở điều chưa.** Thêm trang đặt ở cuối dãy, nhân bản tên "Duplicate of <tên>" ở cuối dãy với mọi visual mang mã mới, `activePageName` là trang đang mở khi lưu (VM-D5). Khác Desktop có chủ ý: xoá trang thì gỡ bookmark trỏ trang đó thay vì để mồ côi (SC-005, 0 tham chiếu treo; Desktop vẫn mở được cả hai cách); nút `PageNavigation` trỏ tới trang chặn việc xoá vì chưa quan sát.
5. **Giao diện.** `PageTabs` đọc danh sách trang từ `LayoutEditor` (không còn từ `workspace.report.pages`): nút "+", menu chuột phải (Đổi tên, Nhân bản, Xoá, Sang trái, Sang phải), bấm đúp đổi tên, kéo tab đổi thứ tự (`NSItemProvider`, như D2). Mờ kèm lý do ở chế độ Xem và báo cáo định dạng cũ.

**Bảo đảm nguyên vẹn**: part không sửa khớp byte; `DataModel` không đụng; golden Phase B/C giữ nguyên; trang không sửa vẫn vẽ cùng số; file gốc `~/Downloads` chỉ đọc.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM). Module `PBIXKit` (đọc/ghi `.pbix`, ghép byte), `BIPro` (giao diện, editor)

**Phụ thuộc chính**: không thêm (Hiến pháp III). SwiftUI (`contextMenu`, `onDrag`/`onDrop`, `alert`), Foundation

**Lưu trữ**: tệp `.pbix` (ZIP/OPC, định dạng PBIR); đường lưu, sao lưu, `SecurityBindings` như D1

**Kiểm thử**: `swift test` (1042 test hiện có); thêm `PBIXKitTests/PBIRPagePatchTests`, `BIProTests/Edit/{PageStructureTests, PageOperationsTests, PageUndoTests, PageSavingTests}`, test nặng `D5Nhom6` (kịch bản Nhom6, lưu, mở lại, so số liệu và bookmark); golden `BIPRO_HEAVY=1 … --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|EditNhom6|BatchedSerial"`; chụp ảnh cửa sổ app; gói thử tay `build/d-out/D5/`

**Nền tảng**: macOS 15+ Apple Silicon

**Loại dự án**: ứng dụng desktop (SwiftUI) cộng thư viện `PBIXKit`

**Mục tiêu hiệu năng**: mỗi thao tác trang dưới 1 s, nhân bản trang 36 visual dưới 1 s (SC-001); lưu sau chuỗi thao tác dưới 1 s (SC-003, đã đạt 0,17 đến 0,26 s ở D1 đến D3)

**Ràng buộc**: như D1 (không ghi `~/Downloads`, file đích còn nguyên nếu ghi lỗi, phần không sửa khớp byte); không để tham chiếu treo tới trang đã xoá

**Quy mô**: Nhom6 có 4 trang (36, 32, 32, 34 visual), 2 bookmark (cùng trỏ `d1_giaodich`), 1 trang drillthrough (`d4_chinhanh`, ẩn khi xem), 0 nút `PageNavigation`, 0 visual trong nhóm

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua, kèm điều kiện | Cấu trúc `pages.json`, `page.json`, bookmark đọc từ Nhom6; cách Desktop thêm, đổi tên, đổi thứ tự, nhân bản, xoá đã quan sát ở VM-D5 (`docs/phase-d-evidence/vm-d5/QUAN-SAT.md`, research R1). Chưa quan sát: xoá trang có nút `PageNavigation`, mở lại file sau khi xoá trang, nhân bản trang có `filterConfig` hay `pageBinding`, "Set as landing page". Đánh dấu [SUY ĐOÁN], giữ phương án thận trọng (chặn hoặc không sao chép). Không dịch ngược |
| II. Power BI là chuẩn | Qua | Không đổi đường tính. Trang nhân bản vẽ bằng cùng engine và truy vấn như trang gốc; golden Phase B/C chạy lại (SC-006). Tiêu chuẩn cuối là Power BI Desktop mở được (kiểm tay hoặc Claude khi được phép) |
| III. Native, không thư viện ngoài | Qua | Chỉ SwiftUI/Foundation |
| IV. Ranh giới dữ liệu | Qua | Không ghi `~/Downloads`; test ghi vào `build/d-out/`. `SecurityBindings` bị bỏ khi sửa phần báo cáo (D1, R13), không đọc nội dung nó. Hiến pháp: agent không điều khiển VM; VM-D5 làm theo lời cho phép của người dùng cho lần này |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Hợp đồng ở `contracts/`; `PBIXKit` (`PBIRPagePatch`) và `BIPro` (editor, tab) tách bạch; lát này lead tự làm (`LayoutEditor`, `DocumentState`, `PageTabs` giao nhau). Bảng quyền ở `docs/phase-d-ownership.tsv` ghi chủ từng file mới |

Sau thiết kế (Phase 1), kiểm lại: không phát sinh vi phạm. Điểm theo dõi: bước thử kéo tab (như T001 của D2) và các mục [SUY ĐOÁN] còn lại.

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/005-d5-quan-ly-trang/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── page-operations.md   # hành vi: thao tác, điều kiện, từ chối, hoàn tác, thông báo
│   └── page-save.md         # ghi gì cho từng thao tác, kiểm lúc lưu
├── checklists/requirements.md
└── tasks.md                 # do /speckit-tasks tạo
```

### Mã nguồn

```text
Sources/PBIXKit/Writing/
├── PBIRPagePatch.swift        # MỚI: pageOrder/activePageName, displayName, page.json mới, nhân bản trang, gỡ tham chiếu trang khỏi bookmark
└── PBIRLayoutPatch.swift      # SỬA nhỏ: makePageName(avoiding:) dùng chung bộ sinh mã 20 hex

Sources/BIPro/Report/Edit/
├── PageStructure.swift        # MỚI: PageStructure, NewPage, tên mặc định "Page N", luật chặn xoá
├── PageOperations.swift       # MỚI: extension LayoutEditor (addPage, renamePage, movePage, duplicatePage, removePage)
├── LayoutEditor.swift         # SỬA: LayoutSnapshot toàn trạng thái, pages, tra cứu trang tạo mới, makeChanges cho trang
└── DocumentSaver.swift        # SỬA: verifyLayout kiểm thứ tự, tên, trang mới, bookmark

Sources/BIPro/
├── DocumentState.swift        # SỬA: pages, bọc thao tác trang, giữ pageID/visualID khớp
└── Report/ReportWorkspace.swift  # SỬA: PageTabs (nút +, menu, đổi tên, kéo tab, xác nhận xoá)

Sources/pbix-dump/main.swift   # KHÔNG ĐỔI (bỏ 2026-11-10): gói VM do D5Nhom6Tests dựng qua LayoutEditor + DocumentSaver, tránh hai chỗ logic dễ lệch

Tests/PBIXKitTests/PBIRPagePatchTests.swift
Tests/BIProTests/Edit/{PageStructureTests, PageOperationsTests, PageUndoTests, PageSavingTests, D5Nhom6Tests}.swift
docs/phase-d-ownership.tsv     # SỬA: thêm các file D5
docs/phase-d-evidence/vm-d5/   # quan sát VM-D5 (đã có), ảnh chụp app
build/d-out/D5/                # gói thử tay + CHECKLIST.md
```

**Quyết định cấu trúc**: phần ghi (`PBIRPagePatch`) nằm trong `PBIXKit` để CLI và các lát sau (D6 bookmark) dùng lại; phần luật (`PageStructure`) là giá trị thuần để test không cần cửa sổ.

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần biện minh. Hai điểm ghi nhận:

| Điểm | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Ảnh chụp hoàn tác chuyển sang toàn trạng thái | Thao tác thêm/xoá cả trang không nằm gọn trong một `PageEdit` | Giữ ảnh chụp theo trang rồi vá riêng cho thao tác trang: hai cơ chế hoàn tác, dễ lệch khi xen kẽ với D1 đến D3 |
| Gỡ bookmark mồ côi thay vì để như Desktop | SC-005 (0 tham chiếu treo) và bài học D1 (tham chiếu treo làm Desktop từ chối file) | Để nguyên như Desktop: Desktop mở được nhưng người dùng giữ bookmark vô dụng, và ta không chắc mọi phiên bản Desktop chịu được |
