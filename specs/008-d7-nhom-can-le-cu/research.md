# Nghiên cứu D7

Nguồn quan sát: `docs/phase-d-evidence/vm-d7/QUAN-SAT.md` (Desktop 2.159, 2026-11-11). Quyết định dưới đây theo thứ tự `spec.md`.

## R1. Căn lề và phân bố: công thức

- **Quyết định**: `Left` = min trái; `Right` = max phải; `Top` = min trên; `Bottom` = max dưới; `Center` (ngang) và `Middle` (dọc) = **trung bình các tâm** của vùng chọn; `Distribute` sắp theo vị trí, hai visual ngoài cùng giữ nguyên, khoảng hở giữa các visual kề nhau bằng nhau (`(span − tổng kích thước) / (n−1)`); mọi kết quả kẹp trong trang; kích thước không đổi.
- **Cơ sở**: đọc file Desktop lưu (QUAN-SAT §5). Center theo trung bình tâm đã kiểm hai lần; Distribute kiểm trên 3 thẻ (809 đúng công thức). Top/Middle/Distribute dọc theo đối xứng.
- **Làm tròn**: BI Pro dùng điểm nguyên (`Frame` nguyên, như D1); Desktop giữ số thập phân. Lệch tối đa 0,5 điểm, ghi vào chú thích. Visual không đổi thì không ghi.
- **Từ chối**: dưới 2 visual (căn) hoặc dưới 3 (phân bố): lệnh mờ kèm lý do. Visual đã ẩn: vẫn căn được (như Desktop hiện chọn được ở Selection pane); visual khoá do nhóm lồng: bỏ qua và báo.
- **Chọn lẫn con của nhóm và visual ngoài nhóm**: Desktop chọn được; BI Pro v1 chỉ căn visual cùng cấp (cùng `parentGroup`); khác cấp thì từ chối kèm lý do (chưa quan sát).

## R2. Dán giữa các trang

- **Quyết định**: dán (cùng trang hoặc khác trang) đặt visual ở nguồn **+10, +10** điểm mỗi lần dán (lần n: +10n), `z` = `z` lớn nhất của trang đích + 1, `tabOrder` = `z`. Nhân bản (⌘D) giữ quy tắc D1 (+16, `z` bước 1000) vì chưa quan sát Desktop.
- **Cơ sở**: QUAN-SAT §6 (dán lần 1: 24,176 → 34,186; lần 2: 44,196; `z` 37001, 37002).
- **Bộ nhớ chép** đã nằm trong `LayoutEditor` và sống qua việc đổi trang; chỉ cần dán vào `currentPageID` (đã đúng) và đổi bước lệch.
- **Phần không sao được**: nút action `PageNavigation` trỏ trang không có, `Bookmark` trỏ bookmark không có (trong cùng tài liệu luôn có, nên trường hợp biên chỉ khi trang đích bị xoá sau khi chép): bỏ và báo. Con của nhóm: chép cả nhóm (Câu chuyện 3) hoặc chép con riêng thành visual ngoài nhóm với vị trí tuyệt đối.

## R3. Nhóm: biểu diễn trong bộ nhớ

- **Quyết định**: mô hình bộ nhớ dùng **toạ độ tuyệt đối trên trang** cho mọi visual, kể cả con của nhóm; file giữ tương đối. Bộ đọc PBIR cộng `x,y` của nhóm vào con khi tải (`ReportVisual.parentGroup` mới); `makeChanges` trừ lại. Nhóm là một mục trong danh sách visual của trang với `type = "visualGroup"` (không có truy vấn, không vẽ), có khung, `z`, tên hiển thị.
- **Lý do**: canvas, chọn khung, căn lề, kéo, đổi cỡ đã dùng khung tuyệt đối; chuyển hệ toạ độ một lần ở biên I/O thay vì trong mọi thao tác. Sửa luôn lỗi hiện tại: bộ đọc hiện đặt con của nhóm ở toạ độ tương đối (sai chỗ) vì không biết nhóm.
- **So sánh khi lưu**: con có `parentGroup`: so toạ độ file (tương đối) với `abs − nhóm.xy` bằng dung sai 1e-6 để số thập phân của Desktop không tạo ghi thừa.
- **Phương án loại**: giữ tương đối trong mô hình (mọi thao tác cần nhận biết nhóm, nhiều chỗ sai).

## R4. Nhóm: thao tác và ghi file

- **Nhóm (⌘G)**: từ 2 visual cùng trang, cùng cấp, chưa trong nhóm (nhóm lồng chưa quan sát → từ chối). Mã nhóm 20 hex không trùng; `displayName` = "Group N" (N nhỏ nhất chưa dùng trên trang); khung = hộp bao con; `z` = `z` lớn nhất của con + 1, `tabOrder` = `z`; `groupMode: "ScaleMode"`; `$schema` lấy của visual đầu tiên có trên trang nhưng không thấp hơn 2.14.0 (Desktop ghi 2.14.0 cho nhóm; dùng đúng chuỗi 2.14.0 cho container nhóm).
- **Ghi con**: ghép byte `position.x`, `position.y` (tương đối), thêm `"parentGroupName":"<id>"` làm khoá cuối của đối tượng gốc; mọi khoá khác (kể cả `$schema` và `tabOrder`) giữ nguyên byte.
- **Bỏ nhóm (⇧⌘G)**: con về toạ độ tuyệt đối, bỏ `parentGroupName` (cả dấu phẩy trước nó), nhóm bị xoá khỏi `visuals/`.
- **Di chuyển nhóm**: dời khung nhóm và mọi con (tuyệt đối); ghi: chỉ `x,y` của nhóm đổi (con tương đối giữ).
- **Đổi cỡ nhóm**: khung nhóm đổi và các con co theo tỷ lệ theo hai chiều (x, y, width, height tương đối nhân tỷ lệ). Chiều dọc theo đối xứng với chiều ngang (QUAN-SAT §2); kiểm lại ở VM vòng 2.
- **Xoá nhóm**: xoá nhóm và mọi con (như Delete trên nhóm ở Desktop theo hiểu biết giao diện; chưa quan sát bằng file). Hoàn tác được. Con và nhóm bị xoá bỏ khỏi `visualContainers` của bookmark và `targetVisualNames` như D1 R14.
- **Nhân bản và dán nhóm**: sao nhóm và mọi con với mã mới, `parentGroupName` đổi theo nhóm mới (D5 đã có `renamedVisualJSON(…, parentGroupName:)`).
- **Con trong nhóm**: sửa trường, định dạng, đổi loại, xoá một con được mở khoá (xoá con cuối làm nhóm rỗng: nhóm bị xoá theo). Di chuyển con trong nhóm: toạ độ tuyệt đối trong khung nhóm; nếu con ra ngoài khung nhóm thì khung nhóm co/giãn theo hộp bao (Desktop làm vậy khi kéo con ra ngoài, theo hiểu biết giao diện; chưa quan sát bằng file) hoặc bị chặn trong v1 (chọn chặn: kẹp trong khung nhóm).
- **Chọn**: bấm vào con khi nhóm chưa chọn → chọn nhóm; bấm khi nhóm hoặc một con đã chọn → chọn con (như Desktop).
- **Selection pane**: nhóm hiện là một dòng có con thụt vào, mắt ẩn/hiện của nhóm ẩn cả con (ghi `display` của nhóm: chưa quan sát → trong v1 mắt nhóm áp mắt từng con, không ghi `visualGroup.display`).

## R5. Báo cáo định dạng cũ (`Report/Layout`)

- **Định dạng đã thấy** (2 file, Nhóm 2 và Nhóm 3): `Report/Layout` UTF-16LE không BOM, JSON một dòng; `sections[i].visualContainers` là **mảng** (không phải chuỗi) các `{x,y,z,width,height,config,filters,tabOrder,...}`; `config` là **chuỗi JSON** chứa `name`, `layouts[0].position{x,y,z,width,height,tabOrder}`, `singleVisual`. Toạ độ ở **hai nơi** (container và `config`) phải cùng giá trị. Số thập phân dài (387.8787878787879).
- **Quyết định**: bộ ghép byte `LegacyLayoutPatch` (PBIXKit): giải UTF-16LE → UTF-8 để tìm bằng `JSONCursor`; số trong container thay tại chỗ; số trong `config` thay bằng cách lấy chuỗi `config` đã giải thoát, ghép byte `layouts[0].position` trong chuỗi đó rồi **thoát lại** theo đúng quy tắc của file; kiểm `escape(unescape(config)) == config` trên chuỗi chưa sửa (đã kiểm khả thi bằng test trên 2 file; không khớp → từ chối). Mã hoá lại UTF-16LE. Cả `Report/Layout` là một part: ghi lại nguyên phần ngoài chỗ sửa.
- **Thêm/xoá phần tử** (nhân bản, dán, xoá): chèn hoặc bỏ nguyên một phần tử của mảng `visualContainers` (kể cả dấu phẩy), bản sao đổi `config.name` (20 hex) và hai bộ toạ độ, giữ `filters`, `tabOrder` đặt = `z`.
- **Phạm vi**: chỉ bố cục (di chuyển, đổi cỡ, căn, xoá, nhân bản, chép/dán trong và giữa trang). Visual có `singleVisualGroup`/nằm trong nhóm cũ: giữ byte, không chọn/sửa. Trường, định dạng, trang, bookmark, bộ lọc vẫn chặn kèm lý do. Không nâng định dạng lên PBIR.
- **`SecurityBindings`**: bỏ như D1 (R13) vì phần báo cáo đổi.
- **Rủi ro**: Desktop có thể từ chối bản sửa; kiểm ở VM vòng 2 (Nhom 2, Nhom 3 bản sao). Nếu từ chối thì giữ chặn và ghi lý do (không phát hành tính năng).

## R6. Hoàn tác và lưu

- Mọi lệnh đi qua `commit(pageID:)`/`commitStructure` có sẵn (D1 đến D6): một lệnh một bước; ảnh chụp trang mở rộng thêm các mục nhóm (chúng nằm trong danh sách visual của `PageEdit`).
- `DocumentSaver.verify` thêm: mọi `parentGroupName` trỏ nhóm có thật cùng trang; mọi nhóm ≥ 1 con; không nhóm lồng; con nằm trong khung nhóm (dung sai 1 điểm); với `Report/Layout`: parse lại được, số container và các toạ độ đọc lại khớp bố cục trong bộ nhớ, phần ngoài chỗ sửa khớp byte.

## R7. Điều chưa quan sát và cách xử lý

| Chưa quan sát | Cách xử lý ở D7 |
|---|---|
| Delete nhóm có xoá con | BI Pro xoá cả nhóm và con (hoàn tác được); kiểm lại ở VM vòng 2 nếu làm được |
| Nhóm lồng nhau | Từ chối kèm lý do |
| Co dọc của nhóm | Dùng tỷ lệ cả hai chiều; kiểm VM vòng 2 |
| Dán/nhân bản cùng trang ở Desktop | Dán theo +10; nhân bản giữ D1 |
| Desktop mở `Report/Layout` đã sửa | VM vòng 2; chưa đạt thì giữ chặn |
| Ẩn nhóm (`visualGroup.display`) | Không ghi; mắt nhóm áp lên từng con |
