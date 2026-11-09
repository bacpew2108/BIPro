# Nghiên cứu: D1, sửa bố cục và lưu T1

Mỗi mục: quyết định, lý do, phương án bị loại, và điều còn [SUY ĐOÁN] cần kiểm.

## R1. Bố cục trong file (đã quan sát)

Quan sát trên `Nhom6_work.pbix` (PBIR, `visualContainer/2.13.0`):

- Mỗi visual là một phần `Report/definition/pages/<trang>/visuals/<mã>/visual.json`; thư mục visual chỉ chứa `visual.json` (134 phần, không có `mobile.json` hay phần khác).
- `position` = `{x, y, z, height, width, tabOrder}`, số nguyên. Trong Nhom6 `z == tabOrder`, bước 1000 (2000, 3000, …, 37000). Có visual xếp chồng cùng toạ độ (một cặp lineChart/pivotTable và các nút action ẩn).
- Mã visual: 20 ký tự hex, trùng `name` trong JSON.
- Trang D1 (1920 × 1080) có 37 visual. Không có nhóm (`parentGroupName`) trong Nhom6.
- Nhom6 có 2 bookmark (`bookmarks.json` liệt kê tên), mỗi bookmark nhắc visual ở `options.targetVisualNames` và `explorationState.sections.<trang>.visualContainers.<mã>`.
- Thứ tự vẽ của app là sắp theo `z` tăng dần (`ReportDefinition.loadPBIR`).

Hệ quả: ghi lại vị trí chỉ cần thay 4 đến 6 số trong một phần JSON.

## R2. Lưu và đóng cửa sổ trên `DocumentGroup(viewing:)`

**Quyết định**: giữ `DocumentGroup(viewing: PBIXDocument.self)`; tự làm Lưu, Lưu thành, Hoàn tác, Làm lại bằng `CommandGroup` và `focusedSceneValue`; dấu "chưa lưu" bằng `NSWindow.isDocumentEdited`; hỏi khi đóng cửa sổ/thoát bằng uỷ quyền cửa sổ (`windowShouldClose`) và `applicationShouldTerminate`.

**Lý do**: `FileDocument`/`ReferenceFileDocument` ghi qua SwiftUI, và SwiftUI tự lưu nền (autosave in place) vào đúng file đang mở. Điều đó bỏ qua bao vây của ta (bản sao lưu, kiểm tra file đổi, chặn `~/Downloads`) và có thể ghi vào file gốc. Tự quản thì mọi lần ghi đi qua `DocumentSaver`.

**Phương án loại**: (a) `FileDocument` ghi: trái Hiến pháp IV như trên. (b) `WindowGroup` thuần, tự mở file bằng `NSOpenPanel`: bỏ cách Finder "Mở bằng" và danh sách file gần đây đang chạy.

**Chưa chắc (bước thử T001, làm trước hết)**: `DocumentGroup(viewing:)` có cho đặt `isDocumentEdited` và chặn đóng cửa sổ không. Tiêu chí qua: sửa một giá trị giả, thấy chấm "chưa lưu" ở nút đóng, bấm đóng thì hiện hộp thoại Lưu/Không lưu/Huỷ, thoát app (⌘Q) cũng hỏi. Không qua thì **dừng và báo bạn**, đề xuất phương án (b) hoặc cho phép `FileDocument` với autosave bị chặn bằng lớp ghi của ta (cần bạn duyệt).

## R3. Mô hình sửa nằm ngoài `Workspace`

**Quyết định**: `Workspace` giữ nguyên (bất biến, dùng chung với luồng nền). `LayoutEditor` (@MainActor, @Observable) giữ `[pageID: [ReportVisual]]` chỉ cho trang đã sửa, kèm `selection`, ngăn xếp hoàn tác/làm lại và `cleanMark`. `DocumentState.page` = `workspace.page(id:)` với `visuals` thay bằng bản đã sửa (nếu có).

**Lý do**: tránh khoá và đổi kiểu ở `Workspace` (đang `let`, đọc từ nhiều luồng). Mọi view hiện nhận `page: ReportPage` theo giá trị nên không phải đổi.

**Rủi ro**: chỗ nào gọi thẳng `workspace.page(id:)`/`workspace.report.pages` cho việc cần bố cục mới (Selection pane, hit-test tương tác) sẽ thấy bố cục cũ. Việc rà soát bằng `grep` là một task; mỗi chỗ phải chuyển sang `state.page` hoặc ghi lý do.

## R4. Ghi `position` bằng ghép byte

**Quyết định**: tìm các số trong `position` bằng bộ tìm đường dẫn JSON có sẵn (`JSONCursor.locate` của `PBIRPatch`), thay đúng các đoạn byte số, rồi đọc lại và so cấu trúc với bản mong đợi (cùng cách `setVisualTitle`). Chỉ ghi trường thật sự đổi; số nguyên giữ dạng nguyên.

**Lý do**: Power BI Desktop có thể nhạy với định dạng JSON; ghép byte giữ khoá, thứ tự, khoảng trắng như file gốc, và diff nhỏ nhất. Đã có tiền lệ (W2).

**Phương án loại**: tải JSON, sửa, ghi lại toàn bộ: đổi định dạng cả file, khó chứng minh không đổi gì khác.

## R5. Nhân bản

**Quyết định**: chép byte `visual.json` nguồn; thay `name` bằng mã mới (20 hex ngẫu nhiên, kiểm không trùng với mọi visual của **mọi** trang và với mã đã dùng trong phiên, kể cả sau hoàn tác); thay `position` (lệch +16, +16 và kẹp trong trang; `z = tabOrder = max z của trang + 1000`). Nếu visual nguồn có `parentGroupName` thì bản sao giữ nguyên trường đó chỉ khi nhóm tồn tại (Nhom6 không có nhóm).

**[SUY ĐOÁN] cần kiểm ở VM-D1**: độ lệch của bản dán, quy tắc `z`/`tabOrder`, dạng mã. Nếu Power BI thật khác thì chỉ sửa hằng số trong `LayoutGeometry`.

## R6. Xoá visual và tham chiếu treo

**Quyết định**: xoá phần `visual.json` của visual. Dọn tham chiếu tới mã đó ở: `targetVisualNames` và `visualContainers.<mã>` trong bookmark; `visualInteractions` trong `page.json` nếu có (Nhom6 không có). Thực hiện bằng ghép byte (xoá đoạn phần tử cùng dấu phẩy kèm theo), kiểm lại bằng so cấu trúc.

**[SUY ĐOÁN]**: Power BI Desktop có chịu tham chiếu treo hay không, và có tự dọn như vậy không. Chưa biết nên dọn là phương án an toàn hơn cho "mở được". VM-D1 so sánh bookmark sau khi bạn xoá một visual trong Power BI Desktop.

Quyết định dự phòng nếu việc dọn bằng ghép byte quá phức tạp ở một dạng JSON lạ: dừng lưu (báo lỗi rõ), không ghi file nửa vời.

## R7. Đường lưu và sao lưu

**Quyết định**:

1. Dựng bytes trong bộ nhớ bằng `PBIXWriter.build` (đã có cho thay phần; mở rộng cho thêm/bớt).
2. Kiểm trong bộ nhớ: mở lại bằng `PBIXFile(data:)`, `loadReport()`, so từng visual (id, x, y, z, width, height) với `LayoutEditor`; so mọi thành viên ZIP không thuộc `changes` còn nguyên byte.
3. Ghi file tạm cùng thư mục đích (`.name.uuid.tmp`), mở lại từ đĩa.
4. Nếu đích có sẵn: chép bản trước sang `~/Library/Application Support/BI Pro/Backups/<băm đường dẫn>-<tên>.pbix` (giữ 1 bản gần nhất mỗi file), rồi `replaceItemAt`.
5. Lỗi ở bước nào thì xoá file tạm, đích nguyên vẹn, báo lỗi bằng tiếng Việt.

**Lý do vị trí sao lưu**: bản `.bak` cạnh file làm bẩn thư mục người dùng và, với file dưới `~/Downloads`, không được phép ghi. `PBIXWriter.save` hiện chép `<tên>.pbix.bak` cạnh file; thêm tham số chính sách để CLI giữ hành vi cũ.

**Phát hiện file đổi ngoài app**: lúc mở (và sau mỗi lần lưu) ghi lại ngày sửa và kích thước; trước khi ghi so lại; khác thì hỏi Ghi đè / Lưu thành / Huỷ.

**Hiệu năng (SC-004)**: `ZipArchive(url:)` đọc file 90 MB; DataModel đi theo `rawCopy` (chép payload, không giải nén). Việc đo là một task; nếu vượt 1 s thì tối ưu bằng ánh xạ bộ nhớ (`Data(contentsOf:options: .alwaysMapped)`) trước khi bàn thêm.

## R8. Quy tắc `~/Downloads`

**Quyết định**: đường dẫn nào nằm dưới `~/Downloads` (so sánh sau khi giải liên kết) là gốc chỉ đọc: ⌘S đổi thành Lưu thành và nói rõ lý do; `DocumentSaver` từ chối ghi vào đó ở tầng thấp nhất (ném lỗi), kể cả khi giao diện bị bỏ qua. Test bằng đường dẫn giả được cấu hình lại.

**Lý do**: Hiến pháp IV và `CLAUDE.md` ("không ghi vào bản gốc ở `~/Downloads`"). `~/Downloads/bipro-golden/` cũng nằm dưới `~/Downloads`; người dùng làm việc ở `Desktop` hoặc chỗ khác thì Lưu ghi thẳng.

## R9. Chế độ Xem / Sửa và kéo thả

**Quyết định**:

- Mặc định Xem; nút và phím ⌘E bật Sửa. Ở Sửa: bấm = chọn (Shift = thêm/bớt), kéo thân = di chuyển, kéo tay nắm = đổi cỡ, kéo trên trang trống = khung chọn; nội dung bên trong visual không nhận chuột (`allowsHitTesting(false)`), nên không lọc chéo/drill khi đang sửa.
- Trong lúc kéo chỉ đổi biến tạm (offset/khung) để phản hồi nhanh; thả chuột mới ghi vào `LayoutEditor` và tạo đúng 1 bước hoàn tác. Đổi cỡ: thử vẽ lại sống; nếu mỗi khung hình vượt 150 ms thì chỉ vẽ khung xem trước rồi áp khi thả.
- Chọn theo thứ tự `z` từ trên xuống; visual ẩn (không vẽ) chỉ chọn được qua Selection pane và không kéo được.

**Lý do**: giữ chế độ Xem y nguyên (FR-007, golden tương tác). Power BI Desktop luôn ở chế độ sửa; bản đọc/sửa tách này là lựa chọn của ta vì BI Pro vốn là viewer-first (quyết định sản phẩm đã chốt).

**Phương án loại**: gộp vào một chế độ: chọn (sửa) và lọc chéo cùng nhấp chuột sẽ xung đột.

## R10. Lưới, kẹp, cỡ tối thiểu

**Quyết định**: lưới 8 px (theo kế hoạch); khi di chuyển, `x`, `y` mới làm tròn về bội của 8; khi đổi cỡ, chỉ cạnh đang kéo bám lưới; kẹp trong `[0, width − w]` × `[0, height − h]` của trang; cỡ tối thiểu 16 × 16; phím mũi tên 1 px, Shift+mũi tên 8 px; giữ Option khi kéo = tắt bám lưới. Kết quả luôn là số nguyên.

**Lưu ý**: Nhom6 có visual ngoài lưới (như x = 1594). Chỉ visual bị kéo mới bị làm tròn.

**[SUY ĐOÁN]**: lưới mặc định, phím nudge, cỡ tối thiểu của Power BI; hằng số tập trung ở `LayoutGeometry` để đổi một chỗ.

## R11. Đăng ký Editor

**Quyết định**: `scripts/build-app.sh` đổi `CFBundleTypeRole` từ `Viewer` sang `Editor`; giữ `LSHandlerRank = Default` và kiểu UTI nhập `com.microsoft.powerbi.pbix`. Kiểm bằng `lsregister -dump` không đổi app mặc định.

## R12. Kiểm thử

- **Thuần (nhanh)**: `LayoutGeometry` (lưới, kẹp, đổi cỡ từng tay nắm, nhiều visual), `LayoutEditor` (chọn, di chuyển, xoá, nhân bản, hoàn tác/làm lại, dirty, mã không trùng), `PBIRLayoutPatch` (ghép byte, nhân bản, dọn bookmark), `PBIXWriter` (thêm/bớt/thay phần, mọi phần khác khớp byte, DataModel khớp byte).
- **Tích hợp**: mở `Nhom6_work.pbix` (hoặc `BIPRO_NHOM6`), sửa bố cục D1 như SC-001, lưu vào `build/d-out/`, mở lại, so bố cục; chạy `unzip -t`; kiểm không ghi đè nguồn; kiểm hành vi khi ghi lỗi (đích chỉ đọc, đĩa giả đầy bằng thư mục không ghi được).
- **Hồi quy**: `swift test` và golden nặng 30/30 + 72 truy vấn; chế độ Xem không đổi.
- **Giao diện**: chụp cửa sổ app ở chế độ Sửa (chọn nhiều, tay nắm), xem bằng mắt.
- **Tay trên VM (bạn)**: VM-D1 (quan sát) và VM-D1-mở (mở file lưu ra trong Power BI Desktop). Gói ở `build/d-out/D1/CHECKLIST.md`.

## R3 (kết quả rà soát T002, 2026-11-09)

Nơi đọc `visuals`/`report.pages` trong `Sources/BIPro/`:

| Nơi | Quyết định |
|---|---|
| `DocumentState.swift:126` `page` | **Đổi**: trả trang đã áp `LayoutEditor` (đây là cổng duy nhất) |
| `DocumentState.swift:130` `visual` | Dùng `page?.visuals` nên tự theo bản đã sửa |
| `Panes/ReportPanes.swift:385, 412` (Selection pane) | Dùng `state.page` nên tự theo bản đã sửa |
| `Report/ReportCanvas.swift:45` | Nhận `page` theo giá trị từ `state.page` |
| `Report/ReportInteraction.swift:59` | Nhận `page` theo tham số: giữ |
| `Report/ReportInteraction.swift:133-134` (slicer của bookmark) | Giữ bản gốc: chỉ tra slicer theo mã trong dữ liệu bookmark đọc từ file; visual đã xoá thì không còn trên canvas nên vô hại |
| `Shell/ShellView.swift:106, 127-128` (tìm kiếm) | Giữ bản gốc ở D1; ghi nhận: kết quả tìm có thể thấy visual đã xoá trong phiên. Sửa nhỏ: lọc theo `state.page`/`layout` nếu rẻ |
| `Report/ReportWorkspace.swift:75`, `DocumentState.swift:110-111`, `Workspace.swift` | Chỉ liệt kê trang, không đụng bố cục: giữ |

## R2 (kết quả bước thử T001, 2026-11-09): QUA cả bốn

Chạy `BIPRO_SPIKE=1` trên bản sao Nhom6 (cửa sổ `SwiftUI.AppKitWindow` do `AppKitWindowController` làm uỷ quyền, tài liệu `PlatformDocument_1`):

| Mục | Kết quả |
|---|---|
| (a) `window.isDocumentEdited = true` | Đặt được, đọc lại `true` |
| (b) chặn đóng cửa sổ | Thay uỷ quyền bằng lớp bọc chuyển tiếp mọi selector còn lại về uỷ quyền gốc; `performClose` gọi `windowShouldClose`, trả `false` thì cửa sổ vẫn mở, hộp thoại dạng sheet hiện và bấm được |
| (c) chặn ⌘Q | `NSApplicationDelegateAdaptor` + `applicationShouldTerminate` được gọi; trả `.terminateCancel` thì app chạy tiếp |
| (d) lệnh menu | `CommandGroup(replacing: .saveItem)` và `.undoRedo` tạo mục File > Lưu (⌘S), Lưu thành (⇧⌘S), Edit > Hoàn tác (⌘Z), Làm lại (⇧⌘Z), đều bật |

Lưu ý cho T023/T028:
- Thay `.undoRedo` làm mất Undo/Redo gốc của ô nhập văn bản (editor DAX, ô tìm). Lệnh của ta phải kiểm: nếu phản hồi đầu tiên là `NSText`/`NSTextView` thì chuyển `undo:`/`redo:` cho nó, còn lại mới dùng `LayoutEditor`.
- Khi mở bằng đối số dòng lệnh app có thể mở cùng file hai cửa sổ (đối số + sự kiện mở file); chỉ ảnh hưởng cách chạy thử, không phải khi mở từ Finder hoặc `open -a`.
- Ghi đè `window.delegate` chỉ làm sau khi cửa sổ đã có (đợi `view.window` khác nil), và giữ lớp bọc bằng thuộc tính liên kết.

## R2, bổ sung (T028, 2026-11-09)

- Chạm `NSDocumentController.shared` trong phần dựng lệnh menu (ví dụ liệt kê `recentDocumentURLs` trong `CommandGroup`) làm app **sập lúc khởi động** (`PlatformDocumentController.createDocumentClassIfNeeded`, SIGSEGV): nó tạo bộ điều khiển thường trước khi SwiftUI tạo bộ của nó. Chỉ gọi `NSDocumentController.shared` trong hành động của nút. Danh sách "Mở gần đây" dựng lại bằng `RecentFiles` (UserDefaults).
- `CommandGroup(replacing: .saveItem)` bỏ cả "Mở gần đây", "Đóng tất cả", "Nhân bản", "Đổi tên", "Chuyển tới", "Hoàn nguyên"; ta dựng lại "Đóng" (⌘W) và "Mở gần đây".
- `URL.resourceValues` có thể trả giá trị đã nhớ (kích thước, ngày sửa cũ): `FileStamp` dùng `FileManager.attributesOfItem` (test bắt được lỗi này).
- Kiểm trong app thật (không phải test): ⌘S trên bản sao ở Desktop (đổi đúng một phần `visual.json`, các phần còn lại khớp byte, `unzip -t` qua, bản sao lưu xuất hiện ở `~/Library/Application Support/BI Pro/Backups/`); ⌘W và ⌘Q khi còn thay đổi hiện hộp thoại Lưu/Không lưu/Huỷ, Huỷ giữ nguyên, Không lưu thoát; ⌘S trên file dưới `~/Downloads` hiện "File trong Downloads là bản gốc, chỉ đọc" rồi Lưu thành… tạo file mới trên Desktop, file gốc không đổi, cửa sổ chuyển sang file mới. Ảnh: `docs/phase-d-evidence/06-close-prompt.png`, `07-downloads-readonly.png`.
