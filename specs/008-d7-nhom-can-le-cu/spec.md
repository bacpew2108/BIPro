# Đặc tả tính năng: D7, căn lề và phân bố, chép dán giữa trang, nhóm visual, sửa báo cáo định dạng cũ

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-11

**Trạng thái**: Đã duyệt (2026-11-11); VM-D7 đã quan sát, xem `docs/phase-d-evidence/vm-d7/QUAN-SAT.md`

**Đầu vào**: "Triển khai phần còn lại phase D" = mục cuối Phase D trong `docs/BIPRO_BUILD_PLAN.md`: nhóm visual, sửa báo cáo định dạng cũ (`Report/Layout`), chép dán giữa các trang, căn lề/phân bố.

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase D), `specs/002-d1-canvas-luu-t1/` (canvas, lưu T1, hoàn tác theo ảnh chụp, R13 bỏ `SecurityBindings`), `specs/005-d5-quan-ly-trang/` (nhân bản trang giữ container nhóm). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục [SUY ĐOÁN] phải kiểm ở buổi VM-D7 trước khi code phần đó (Claude điều khiển VM chỉ khi người dùng cho phép lần đó, hoặc người dùng làm tay). Không dịch ngược; chỉ đọc file Desktop ghi và nhìn giao diện.

**Hiện trạng trong BI Pro** (đọc từ mã):

- `LayoutEditor` (D1): chọn một và nhiều, `move`, `resize`, `apply(frames:)`, `delete`, `duplicate`, `copy`/`paste` (bộ nhớ chép nằm trong `LayoutEditor`, dán vào `currentPageID`, mỗi lần dán lệch thêm một bậc 16 điểm). Visual có `parentGroupName` bị khoá (`isLockedByGroup`, "Nằm trong nhóm, chưa sửa được ở D1"). Container nhóm (`visualGroup`) không phải visual: đọc bỏ qua (`ReportDefinition` dòng 206), nhưng D5 sao nguyên khi nhân bản trang (`groupContainers`, `renamedVisualJSON` đổi `parentGroupName`).
- Chưa có căn lề, phân bố.
- Báo cáo định dạng cũ: đọc được (`loadLegacyLayout`: `Report/Layout` là JSON UTF-16LE, mỗi `visualContainers[i].config` là chuỗi JSON lồng) nhưng `canEditLayout` tắt mọi sửa và lưu.

**Đã quan sát trong file thật**:

- `Nhom6_work.pbix` (PBIR): 134 `visual.json`, không có nhóm, không có `parentGroupName`. Chưa có mẫu PBIR có nhóm.
- Hai báo cáo định dạng cũ trong `~/Downloads` (chỉ đọc): `Nhóm 2 - Financial Service .pbix` (5 trang, trang BC1, BC3, BC2 mỗi trang có 1 container `singleVisualGroup`), `dashboard_DW&BI_nhom_3_20252.pbix` (4 trang, không nhóm). `Report/Layout` có khoá `id, resourcePackages, sections, config, layoutOptimization, pods`.

**[SUY ĐOÁN], phải quan sát ở VM-D7**:

- Căn lề (Align left, center, right, top, middle, bottom) và phân bố (Distribute horizontally, vertically) ở Desktop: chuẩn căn là hộp bao của vùng chọn; phân bố cần từ 3 visual, khoảng hở đều; Desktop ghi toạ độ nguyên hay số thập phân; Distribute theo khoảng hở hay theo tâm.
- Dán sang trang khác ở Desktop: giữ nguyên vị trí hay lệch; dán nhiều lần; bộ lọc cấp visual và `objects` có sao theo; tên visual mới; có sao ngoại lệ (bookmark, tương tác) hay không.
- Nhóm (Group ⌘G, Ungroup ⇧⌘G): `visual.json` của container nhóm (`visualGroup{displayName, groupMode}`, `position`, các khoá khác), con có `parentGroupName`, toạ độ con tương đối hay tuyệt đối so với nhóm, `z` của nhóm và con, tên mặc định "Group 1", nhóm lồng nhau, di chuyển nhóm có ghi lại con không, đổi cỡ nhóm (`groupMode` ScaleMode), xoá nhóm (có xoá con), Ungroup (con trở lại `parentGroupName` bỏ, toạ độ về tuyệt đối), ẩn nhóm trong Selection pane, bookmark có nhóm.
- Báo cáo định dạng cũ: Desktop mở `Report/Layout` đã sửa bằng ghép byte (không `SecurityBindings`) có báo lỗi hay không, và Desktop khi lưu có nâng lên PBIR không (không cần vì BI Pro không nâng); khoá toạ độ trong `config` (`layouts[0].position{x,y,z,width,height}`) và ở cấp container (`x,y,z,width,height`) phải khớp nhau; thứ tự sinh `name` của container mới.


**Đã quan sát ở VM-D7 (2026-11-11, chi tiết ở `docs/phase-d-evidence/vm-d7/QUAN-SAT.md`)**: nhóm là container `visualGroup{displayName,groupMode:"ScaleMode"}` ở `visuals/<id>/visual.json`, con có `parentGroupName` (khoá cuối) và toạ độ **tương đối** so với nhóm; đổi cỡ nhóm co các con theo tỷ lệ; di chuyển nhóm chỉ đổi toạ độ nhóm; Bỏ nhóm đưa con về toạ độ tuyệt đối. Căn trái/phải/trên/dưới theo mép của vùng chọn; Căn giữa theo **trung bình các tâm**; Phân bố cần từ 3 visual và chia khoảng hở đều; kết quả kẹp trong trang, giữ số thập phân. Dán sang trang khác: mã mới, vị trí nguồn +10 điểm mỗi lần dán, `z` = lớn nhất của trang đích + 1. Các mục [SUY ĐOÁN] ở trên về nhóm, căn lề, dán đã được chốt; còn chưa quan sát: xoá nhóm, nhóm lồng nhau, co dọc, báo cáo định dạng cũ trong Desktop.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Căn lề và phân bố (Ưu tiên: P1)

Ở Sửa (⌘E) người dùng chọn từ 2 visual, bấm Căn trái/giữa/phải/trên/giữa/dưới hoặc Phân bố ngang/dọc (menu Định dạng ở ribbon và menu chuột phải); các visual dời tới đúng chỗ, một bước ⌘Z, ⌘S ghi vị trí.

**Vì sao P1**: nhỏ, không đổi cấu trúc file (chỉ `position`), dùng ngay đường lưu D1.

**Kiểm thử độc lập**: trên một trang Nhom6, chọn 3 visual, Căn trái: cả ba có cùng `x` bằng `x` nhỏ nhất; Phân bố ngang: khoảng hở giữa các visual kề nhau bằng nhau (sai số làm tròn một điểm); ⌘Z đưa về như cũ; lưu rồi mở lại giữ vị trí.

**Kịch bản chấp nhận**:

1. **Cho** vùng chọn từ 2 visual không nằm trong nhóm, **khi** bấm một lệnh căn, **thì** mọi visual có cạnh hoặc tâm tương ứng trùng hộp bao của vùng chọn, kích thước không đổi, một bước hoàn tác.
2. **Cho** vùng chọn dưới 3 visual, **khi** bấm Phân bố, **thì** lệnh mờ kèm lý do (cần từ 3 visual).
3. **Cho** vùng chọn có visual khoá do nhóm (khi chưa có Câu chuyện 3), **thì** lệnh bỏ qua visual đó và báo.
4. **Cho** các visual đã trùng chuẩn căn, **khi** bấm lệnh căn, **thì** không tạo bước hoàn tác.

---

### Câu chuyện 2 — Chép dán giữa các trang (Ưu tiên: P1)

Người dùng chép một hoặc nhiều visual ở trang này, chuyển sang trang khác, dán; visual mới có đủ trường, định dạng, bộ lọc cấp visual và vị trí đúng như Desktop dán.

**Kiểm thử độc lập**: trên Nhom6 chép một card ở trang D1, chuyển sang trang `d4_chinhanh`, dán, ⌘S, mở lại: visual mới ở trang đích với mã mới, `query`, `objects`, `filterConfig` nguyên như nguồn, trang nguồn không đổi.

**Kịch bản chấp nhận**:

1. **Cho** vùng chọn ở trang A đã chép, **khi** chuyển sang trang B và dán, **thì** visual mới nằm ở trang B (vị trí theo quan sát VM-D7), được chọn sẵn, `name` không trùng, `z` ở trên cùng, một bước hoàn tác.
2. **Cho** visual chép nằm trong ngoại lệ chưa hỗ trợ (visual trong nhóm khi chưa có Câu chuyện 3; nút action Bookmark/PageNavigation trỏ trang không có ở trang đích), **thì** dán được visual còn lại và báo phần bỏ.
3. **Cho** đã dán rồi xoá trang đích hoặc hoàn tác, **thì** không còn part mồ côi trong file lưu.
4. **Cho** chép ở một tài liệu và dán ở tài liệu khác, **thì** nằm ngoài phạm vi (chỉ trong một tài liệu).

---

### Câu chuyện 3 — Nhóm và bỏ nhóm visual (Ưu tiên: P2)

Người dùng chọn từ 2 visual, Nhóm (⌘G); nhóm di chuyển, đổi cỡ, nhân bản, xoá như một khối; Bỏ nhóm (⇧⌘G) trả các visual về trang; Selection pane và Hoàn tác thấy nhóm.

**Vì sao P2**: cần quan sát VM-D7 trước vì chưa có mẫu PBIR có nhóm; D1, D5 hiện chỉ giữ nguyên nhóm có sẵn.

**Kiểm thử độc lập**: trên một trang Nhom6, chọn 3 visual, Nhóm, kéo nhóm, ⌘S, mở lại ở BI Pro và Power BI Desktop: nhóm còn, con đúng chỗ, Desktop không báo lỗi; Bỏ nhóm, lưu: con về `parentGroupName` bỏ, toạ độ khớp lúc trước khi nhóm.

**Kịch bản chấp nhận**:

1. **Cho** vùng chọn từ 2 visual cùng trang, **khi** Nhóm, **thì** thêm container nhóm đúng dạng Desktop ghi (VM-D7), con có `parentGroupName`, hộp bao của nhóm bằng hộp bao con; một bước hoàn tác.
2. **Cho** một nhóm, **khi** kéo hoặc đổi cỡ nhóm, **thì** con dời hoặc co theo đúng cách Desktop (VM-D7); chọn một con trong nhóm vẫn sửa trường, định dạng, vị trí được.
3. **Cho** nhóm, **khi** Bỏ nhóm, **thì** nhóm bị xoá, con mất `parentGroupName` và có vị trí tuyệt đối đúng chỗ đang hiện.
4. **Cho** nhóm, **khi** xoá hoặc nhân bản, **thì** cả nhóm và con cùng xoá hoặc nhân bản (mã mới, `parentGroupName` đổi theo).
5. **Cho** nhóm lồng nhau hoặc nhóm trong bookmark, **thì** theo quan sát VM-D7; chưa quan sát thì từ chối kèm lý do thay vì ghi đoán.

---

### Câu chuyện 4 — Sửa bố cục báo cáo định dạng cũ (Ưu tiên: P3)

Người dùng mở báo cáo định dạng cũ (`Report/Layout`), vào Sửa, di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán visual, lưu; mở lại ở BI Pro và Power BI Desktop.

**Vì sao P3**: viết lại `Report/Layout` (UTF-16LE, JSON lồng chuỗi) là đường lưu mới; chỉ phạm vi bố cục, các sửa khác (trường, định dạng, trang, bookmark, bộ lọc) giữ chặn kèm lý do.

**Kiểm thử độc lập**: mở `Nhóm 2 - Financial Service .pbix` (bản sao), dời một visual, đổi cỡ một visual, xoá một visual, lưu thành bản sao, mở lại ở BI Pro và Power BI Desktop: vị trí đúng, phần còn lại của `Report/Layout` và mọi part khác khớp từng byte.

**Kịch bản chấp nhận**:

1. **Cho** báo cáo định dạng cũ ở Sửa, **khi** di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán, **thì** thao tác chạy như PBIR và ⌘S ghi lại `Report/Layout` bằng ghép byte (chỉ khoá toạ độ trong `config` và cấp container của visual đổi; thêm hoặc bỏ phần tử `visualContainers` nguyên khối), `SecurityBindings` bỏ như D1.
2. **Cho** thao tác ngoài bố cục (Build pane, Format pane, trang, bookmark, bộ lọc) ở báo cáo định dạng cũ, **thì** vẫn mờ kèm lý do "chưa sửa được ở báo cáo định dạng cũ".
3. **Cho** file lưu, **khi** mở bằng Power BI Desktop, **thì** không báo lỗi, bố cục giống BI Pro.
4. **Cho** `Report/Layout` mà phần cần sửa không nằm trong dạng đã quan sát, **thì** từ chối ở khâu kiểm, không ghi đoán.

---

### Câu chuyện 5 — Lưu, mở lại, hoàn tác chung (Ưu tiên: P1)

Mọi thao tác trên chung một lịch sử hoàn tác với D1 đến D6 (một lệnh = một bước), lưu qua `DocumentSaver` (dựng, kiểm, ghi tạm, mở lại, thay; chỉ part đổi), file mở lại được ở BI Pro và Power BI Desktop không lỗi.

**Kịch bản chấp nhận**:

1. **Cho** chuỗi căn, nhóm, dán, xoá rồi ⌘Z từng bước, **thì** về đúng trạng thái sau mỗi bước; lưu giữa chừng rồi hoàn tác không làm `verify` chặn lưu lần sau.
2. **Cho** file đã lưu, **khi** `verify` chạy, **thì** mọi `parentGroupName` trỏ tới container nhóm có thật cùng trang, mọi nhóm có ít nhất một con, vị trí trong biên trang, mọi bookmark và bộ lọc D6 vẫn hợp lệ.

### Trường hợp biên

- Visual đã ẩn, visual khoá do nhóm, vùng chọn lẫn visual trong và ngoài nhóm: lệnh căn và nhóm chỉ áp cho phần hợp lệ và báo phần bỏ.
- Nhóm trống sau khi xoá hết con; nhóm chỉ còn một con: theo quan sát VM-D7.
- Dán vào trang đã đầy chỗ: vị trí bị kẹp trong biên trang như D1.
- Báo cáo định dạng cũ có container `singleVisualGroup` (Nhóm 2): giữ nguyên byte; di chuyển container nhóm chưa làm thì mờ kèm lý do, không phá con.
- Hai lệnh liên tiếp cùng loại (nhấn phím mũi tên): gộp bước như D1, lệnh căn không gộp.
- File dưới `~/Downloads`: chỉ Lưu thành (như D1); bản gốc không bị ghi.
- Chế độ Xem: mọi lệnh ở đây mờ kèm lý do.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

- **FR-001**: Ở Sửa, từ 2 visual không bị khoá: Căn trái, giữa ngang, phải, trên, giữa dọc, dưới theo hộp bao của vùng chọn (chuẩn theo quan sát VM-D7); từ 3 visual: Phân bố ngang và dọc; kích thước không đổi; vị trí nguyên điểm (hoặc đúng dạng Desktop ghi theo VM-D7); không đổi gì thì không tạo bước.
- **FR-002**: Chép (⌘C) rồi dán (⌘V) ở trang khác PHẢI tạo visual mới ở trang đích: mã mới, giữ `query`, `objects`, `visualContainerObjects`, `filterConfig`, vị trí theo VM-D7, `z` trên cùng; phần không sao được (nút trỏ trang/bookmark không có ở đích) bỏ kèm báo.
- **FR-003**: Nhóm (⌘G) từ 2 visual cùng trang PHẢI ghi container nhóm và `parentGroupName` đúng cấu trúc Desktop (VM-D7); Bỏ nhóm (⇧⌘G) trả con về trang với vị trí tuyệt đối; cấu trúc chưa quan sát thì từ chối, không ghi đoán.
- **FR-004**: Di chuyển, đổi cỡ, xoá, nhân bản nhóm PHẢI tác động cả con theo cách Desktop làm (VM-D7); sửa trường, định dạng, vị trí của một con được mở khoá.
- **FR-005**: Báo cáo định dạng cũ ở Sửa PHẢI chạy di chuyển, đổi cỡ, căn, xoá, nhân bản, chép dán; lưu ghi `Report/Layout` bằng ghép byte, chỉ phần đổi; mọi lệnh khác vẫn chặn kèm lý do.
- **FR-006**: Mọi lệnh PHẢI là đúng một bước hoàn tác chung với D1 đến D6; ⌘S, ⇧⌘S đi qua `DocumentSaver` (dựng và kiểm trong bộ nhớ, ghi tạm, mở lại, thay), chỉ part đổi được ghi, phần khác khớp từng byte, `SecurityBindings` bỏ như D1.
- **FR-007**: `verify` PHẢI chặn lưu khi `parentGroupName` trỏ không có thật, nhóm rỗng, vị trí ngoài biên, hoặc `Report/Layout` mới không parse lại được hoặc không khớp bố cục trong bộ nhớ.
- **FR-008**: Chế độ Xem không bao giờ làm bẩn file; lệnh mờ kèm lý do.
- **FR-009**: File đã lưu PHẢI mở lại ở BI Pro (bố cục như lúc lưu) và ở Power BI Desktop (không báo lỗi, bố cục giống BI Pro).
- **FR-010**: Không file nào dưới `~/Downloads` bị ghi; golden Phase B/C và các test D1 đến D6 PHẢI vẫn qua.

### Thực thể chính

- **Vùng chọn**: tập visual được chọn; hộp bao; danh sách có thể căn (không khoá, không ẩn).
- **Container nhóm**: mã, tên hiển thị, vị trí, `groupMode`, danh sách con (qua `parentGroupName`).
- **Bộ nhớ chép**: các visual và `visual.json` của chúng, sống trong một tài liệu.
- **Bố cục định dạng cũ**: `Report/Layout` đã giải mã, các `visualContainers` và vị trí của chúng, bản ghép byte.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên Nhom6, căn trái 3 visual và phân bố ngang một hàng 4 visual cho vị trí đúng công thức, một bước hoàn tác mỗi lệnh, lưu 0,5 giây hoặc ít hơn.
- **SC-002**: Chép từ trang D1 dán sang trang khác rồi lưu: visual mới khớp `query`, `objects`, `filterConfig` với nguồn từng byte (trừ `name`, `position`), trang nguồn khớp từng byte.
- **SC-003**: Nhóm 3 visual rồi Bỏ nhóm trên Nhom6 trả vị trí đúng như ban đầu (0 điểm lệch); `Nhom6_d7.pbix` mở được trong Power BI Desktop không báo lỗi, nhóm hiện đúng.
- **SC-004**: Trên bản sao `Nhóm 2 - Financial Service .pbix`, dời, đổi cỡ, xoá một visual, lưu: `Report/Layout` đổi chỉ ở phần tử bị sửa (so byte ngoài vùng sửa), mọi part khác khớp từng byte, mở được trong Power BI Desktop.
- **SC-005**: Số trường hợp ghi theo cấu trúc chưa quan sát = 0 (từ chối kèm lý do).
- **SC-006**: Golden Phase B/C và `swift test` D1 đến D6 vẫn qua; mỗi lệnh căn, nhóm, dán dưới 150 ms trên trang 36 visual.

## Giả định

- VM-D7 do Claude điều khiển chỉ khi người dùng cho phép lần đó (hiến pháp: agent không điều khiển VM trừ ngoại lệ của người dùng); không có buổi VM thì chỉ làm Câu chuyện 1, 2 và phần định dạng cũ không cần Desktop quan sát (khoá toạ độ đọc từ file thật), còn Câu chuyện 3 chờ.
- Không cần thư viện ngoài; ghép byte dùng `JSONCursor`/`PBIRPatch` có sẵn, thêm một bộ ghép cho `Report/Layout` (UTF-16LE, chuỗi JSON lồng).
- Nhóm lồng nhau, nhóm trong bookmark, di chuyển container `singleVisualGroup` ở định dạng cũ: ngoài phạm vi nếu VM-D7 chưa chốt.
- Hoàn tác: ảnh chụp theo trang như D1, mở rộng thêm container nhóm.
- Chép dán giữa hai tài liệu khác nhau, hoặc qua clipboard hệ thống: ngoài phạm vi.
