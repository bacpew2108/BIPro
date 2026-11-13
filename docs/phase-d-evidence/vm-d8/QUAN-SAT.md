# VM-D8: quan sát Power BI Desktop cho phần tồn đọng Phase D

Ngày: 2026-11-13. Claude điều khiển VM theo lời cho phép của người dùng ("tôi cho phép bạn điều khiển VM"; ngoại lệ của quy tắc "agent không điều khiển VM"). Desktop 2.159.x, Windows 11 (Parallels). File thử: bản sao `Nhom6_work.pbix` ở `C:\Users\bacpew\vmd8\work.pbix`; các bản lưu trung gian ở `~/Desktop/vmd8out/` trên Mac (đã xoá, xem "Dọn dẹp"). Không dịch ngược: chỉ thao tác giao diện, lưu, đọc diff các part. Mẫu JSON: `json/`.

Trang thử: `d3_cskh`, và `d1_giaodich` cho matrix. Buổi quan sát làm hai đợt trong ngày (bị ngắt giữa chừng vì hết hạn mức phiên); phần "Chưa quan sát" ở cuối là việc để lại.

## 1. Nhóm visual (bổ sung VM-D7)

- **Nhóm lồng nhau được phép.** Chọn một nhóm và một visual rồi Format > Group: menu có đủ `Group`, `Ungroup`, `Merge`.
  - `Group`: tạo nhóm ngoài mới ("Group 2", mẫu `json/nhom-ngoai.visual.json`), vị trí = hộp bao; `z` = `z` lớn nhất + 1. Nhóm trong (`json/nhom-trong.visual.json`) nhận `parentGroupName` (khoá cuối, sau `visualGroup`) và toạ độ tương đối so với nhóm ngoài; con của nhóm trong không đổi. Visual thường được thêm cũng nhận `parentGroupName` và toạ độ tương đối.
  - `Merge`: visual được đưa vào nhóm đang có (giữ mã và tên nhóm). Hộp bao của nhóm tính lại theo hợp của nhóm và visual mới; toạ độ tương đối của các con cũ được dịch theo gốc mới (y 0 → 195,86 khi gốc nhóm lên trên 195,86).
- **Phím Delete trên nhóm xoá cả nhóm, nhóm lồng bên trong và mọi visual con** (6 part bị xoá khi xoá "Group 2" chứa "Group 1" + 1 visual). Khớp cách BI Pro đang làm.
- **Co theo chiều dọc** (Format pane > General > Properties > Size > Height 772,54 → 386): mọi hậu duệ co theo cùng tỷ lệ 0,49965, kể cả cháu trong nhóm lồng: `height` 380 → 189,866; `y` tương đối 392 → 195,862; `y` = 0 giữ 0. `width` và `x` không đổi. Desktop bỏ `tabOrder` khỏi các part đã co.
- **Bỏ nhóm ngoài** (Ungroup trên "Group 2"): part nhóm ngoài bị xoá; nhóm trong bỏ `parentGroupName` và về toạ độ tuyệt đối (cộng x, y của nhóm ngoài); con của nhóm trong không đổi.
- Kéo nhóm bằng chuột: chỉ `x`, `y` của nhóm đổi (số thập phân), nhóm mất `tabOrder`.
- Sau một lần hoàn tác (Ctrl+Z) rồi lưu, Desktop đánh lại `tabOrder` của mọi visual trên trang (nhiều part đổi chỉ ở `tabOrder`).

## 2. Dán trong cùng trang (Ctrl+C, Ctrl+V hai lần)

- Mỗi lần dán: vị trí nguồn **+10, +10** (24,296 → 34,306 → 44,316), giống dán sang trang khác.
- `z` = `z` lớn nhất của trang + 1 (33002, 33003); `tabOrder` = `tabOrder` lớn nhất + 1.
- Desktop không có lệnh nhân bản visual riêng.

## 3. Nút điều hướng trang và xoá trang đích (bổ sung D5)

- Insert > Buttons > Blank, Format button > Action bật, Type = "Page navigation", Destination = trang. Danh sách Destination có mọi trang trừ trang đang mở (cả trang ẩn). Các kiểu Action: Back, Bookmark, Drill through, Page navigation, Q&A, Web URL, Apply all slicers, Clear all slicers, Data function.
- Part nút mới (`json/nut-dieu-huong-trang.visual.json`): `position` (0,0) 100×40; `visual.visualType:"actionButton"`; `objects.icon[0]{properties.shapeType:'blank', selector{id:"default"}}`; `visualContainerObjects.visualLink[0].properties{show:true, type:'PageNavigation', navigationSection:'<mã trang>'}`; `drillFilterOtherVisuals:true`; khoá gốc cuối `"howCreated":"InsertVisualButton"`.
- **Xoá trang đích**: hộp thoại chỉ có câu chung ("If you save the report later, Power BI will permanently delete it…"), **không cảnh báo gì về nút**. Sau khi lưu: thư mục trang bị xoá, `pages.json` bỏ trang khỏi `pageOrder`, **part của nút giữ nguyên từng byte, `navigationSection` vẫn trỏ mã trang đã mất** (treo). Bookmark không đổi.
- Desktop còn dọn tài nguyên chỉ trang đó dùng: xoá `Report/StaticResources/SharedResources/Shapemaps/usa.states.topo.json` và mục tương ứng trong `report.json` > `resourcePackages`.

## 4. Thẻ lọc Advanced và Top N (bổ sung D6)

Làm trên thẻ cấp visual của biểu đồ Pareto (`aabc04ac…`); mẫu trong `json/the-loc-*.txt`.

- **Thẻ measure** (cấp visual): `type:"Advanced"`, `field.Measure`, `filter{Version:2, From:[{Name:"f",Entity,Type:0}], Where:[{Condition:…}]}`; không có `howCreated`. Danh sách toán tử: is less than, is less than or equal to, is greater than, is greater than or equal to, is, is not, is blank, is not blank.
- **So sánh**: `{"Comparison":{"ComparisonKind":K,"Left":<Measure hoặc Column với Source>,"Right":{"Literal":{"Value":V}}}}`.

  | Toán tử | Dạng ghi |
  |---|---|
  | is | `ComparisonKind` 0 |
  | is greater than | 1 |
  | is greater than or equal to | 2 |
  | is less than | 3 |
  | is less than or equal to | 4 |
  | is not | `{"Not":{"Expression":{Comparison kind 0}}}` |
  | is blank | kind 0, `Value:"null"` |
  | is not blank | `Not` của kind 0 với `"null"` |
  | is empty (chỉ cột chữ) | kind 0, `Value:"''"` |
  | is not empty | `Not` của kind 0 với `"''"` |
  | does not start with | `{"Not":{"Expression":{"StartsWith":{Left,Right}}}}` |

- **Giá trị**: số nguyên `"500L"`, số thập phân `"9007.5D"`, chữ `"'Other'"`.
- **Hai điều kiện**: `{"And":{"Left":…,"Right":…}}` hoặc `{"Or":{"Left":…,"Right":…}}`.
- Toán tử của cột chữ: contains, does not contain, starts with, does not start with, is, is not, is blank, is not blank, is empty, is not empty.
- **Bottom N**: giống Top N đã quan sát ở VM-D6, chỉ khác `OrderBy[0].Direction: 1` (Top là 2); `Top: 3` là số mục. Ô "By value" nay là danh sách chọn ("Data in this visual", "All data"), không cần kéo thả.
- Thẻ cột số thêm vào cấp trang (chuột phải trường > Add to filters > Page-level filters) mặc định mở ở "Advanced filtering".
- **Cột số** (thẻ cấp trang `birth_year`, mẫu `json/the-loc-trang-so-ngay.txt`): cùng dạng `Comparison`, `Left` là `Column`; `"1980L"`, `"1990.5D"`; `howCreated:"User"` đứng sau `filter`. Toán tử như thẻ measure.
- **Cột ngày** (`birth_date`): mặc định "Basic filtering"; danh sách kiểu có thêm "Relative date", "Relative time". Toán tử Advanced: is, is not, is after, is on or after, is before, is on or before, is blank, is not blank. Giá trị ghi `"Right":{"DateSpan":{"Expression":{"Literal":{"Value":"datetime'1980-01-15T00:00:00'"}},"TimeUnit":5}}` ("is on or after" = kind 2).
- Thẻ mới thêm đứng **cuối** `filterConfig.filters` (pane hiện theo thứ tự khác). Thẻ đổi sang Advanced chưa đặt điều kiện: `type:"Advanced"`, không có `filter`.
- **Khoá thẻ**: thêm `"isLockedInViewMode":true` cuối thẻ. **Ẩn thẻ**: thêm `"isHiddenInViewMode":true` (đứng trước `isLockedInViewMode`). **Clear filter** (cục tẩy): bỏ khoá `filter`, giữ các khoá khác.

## 5. Nhóm bookmark (Bookmarks pane, chọn hai bookmark, chuột phải > Group)

- Chỉ `bookmarks.json` đổi (`json/bookmarks-nhom.json`): `items:[{"name":"<20 hex>","displayName":"Group 1","children":["<bookmark 1>","<bookmark 2>"]}]`. Hai bookmark không còn là mục cấp gốc; file bookmark không đổi.

## 6. Định dạng (bổ sung danh mục D4)

Biểu đồ thanh `c1ed9ef5…` (trang D3) và matrix `70eec8cd…` (trang D1); mẫu trong `json/`.

| Thao tác | Kết quả trong file |
|---|---|
| Bars > Apply settings to: Series = một chuỗi, Color = màu theme | `objects.dataPoint:[{"properties":{"fill":{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":4,"Percent":0}}}}}},"selector":{"metadata":"Fact_CRM_Complaint.Relief Rate"}}]` (`metadata` = `queryRef` của trường) |
| Bars > Series = All, Transparency 30 | thêm mục **không có `selector`** vào cuối mảng: `{"properties":{"fillTransparency":"30D"}}`. Với All, ô Color bị khoá ("Select a specific series to change the color") |
| "…" > Reset all settings to default | **bỏ hẳn** khoá `objects` và `visualContainerObjects` (không để `{}`) |
| General > Effects > Background > Color | `visualContainerObjects.background[0].properties.color` = màu theme (`ColorId 6, Percent 0.4`) |
| Shadow bật, Position = Bottom left, Offset = Inside, Color | `dropShadow.properties`: `show true`, `preset 'BottomLeft'`, `angle 315L`, `shadowDistance 10L`, `shadowBlur 15L`, `shadowSpread 0L`, `transparency 70L`, `position 'Inner'`, `color` (màu theme). Desktop ghi luôn các số của preset, kiểu **số nguyên `L`** |
| Title > Font = Segoe UI Semibold | `title.fontFamily` = `'''Segoe UI Semibold'', wf_segoe-ui_semibold, helvetica, arial, sans-serif'` (chuỗi phông CSS, nháy đơn gấp đôi) |
| Title > Font = Georgia | `fontFamily 'Georgia'` |
| Title > Heading = Heading 2 | `title.heading 'Heading2'` (danh sách đọc được: Normal, Heading 2 đến 6) |
| Title > Text wrap tắt | `title.titleWrap false` |
| Title > Divider bật | `visualContainerObjects.divider:[{"properties":{"show":true}}]` |
| Cỡ chữ tiêu đề gõ 500, rồi 3 | ghi `60D`, rồi `8D`: khoảng **8 đến 60** |
| Matrix > Column subtotals tắt, Row subtotals tắt | `objects.subTotals:[{"properties":{"columnSubtotals":false,"rowSubtotals":false}}]` |
| Matrix > Layout > Freeze row headers tắt | `rowHeaders.unfrozen true` |
| Matrix > Layout > Matrix layout = Tabular | `objects.general:[{"properties":{"layout":"'Tabular'"}}]` (Compact, Outline, Tabular) |
| Matrix > Grid > Horizontal / Vertical gridlines bật | `grid.gridHorizontal true`, `grid.gridVertical true` (thêm cuối, sau `rowPadding`) |

Tên trong giao diện → khoá: Shadow › Offset = `position` (`'Inner'` cho Inside; giá trị của Outside chưa thấy), Position = `preset`, Size = `shadowSpread`, Blur = `shadowBlur`, Angle = `angle`, Distance = `shadowDistance`. Danh sách Position: Bottom right, Bottom, Bottom left, Right, Center, Left, Top right, Top, Top left, Custom. Danh sách phông đọc được: DIN, DIN Light, Georgia, Lucida Sans Unicode, Segoe UI (Light, Semibold, Bold), Symbol, Tahoma, Times New Roman, Trebuchet MS, Verdana (phần đầu danh sách chưa đọc). Thẻ của matrix: Style presets, Layout, Grid, Blank rows, Values, Column headers, Row headers, Column subtotals, Row subtotals, Column grand total, Row grand total, Specific column, Cell elements, URL icon, Image size.

## Chưa quan sát

- Bookmark Data có lựa chọn điểm dữ liệu, drill, mở nút, slicer nhiều cấp.
- Định dạng: `dataPoint` theo điểm dữ liệu (`selector.data`), màu khi biểu đồ có Legend, các thẻ còn lại của matrix (Column/Row grand total, Specific column, Cell elements), nút (`icon`, căn lề), `donutChart`, `treemap`, `shapeMap`, `image`, `slicer.data`/`general`, khoảng của các ô số khác ngoài cỡ chữ tiêu đề.
- D3b: không cần quan sát thêm (đã có ở VM-D3), chỉ còn viết mã.

## Ghi chú thao tác (cho lần sau)

- Công cụ ở `build/vm-tools/` (ngoài git): `vm.sh` (chụp, bấm theo toạ độ ảnh rộng 1600), `see.sh`/`tap.sh` (đọc chữ trên màn hình bằng Vision rồi bấm theo nhãn; biên dịch `swiftc -O ocr.swift -o ocr`), `k.sh` (phím qua `prlctl send-key-event`), `snap.sh` (lưu, chép file, giải nén).
- Phím qua `prlctl send-key-event "Windows 11" -k <mã>` **tới được Desktop** (Ctrl+C/V/Z/A, Delete, Tab, Esc). Mã theo bảng XFree86: Delete 107, mũi tên 98/100/102/104, Ctrl trái 37. Phím `0` (mã 19) bị lặp; gõ chữ số và chữ bằng `cliclick t:`.
- Không bấm ribbon theo toạ độ nhớ sẵn: tab đổi theo vùng chọn (một lần bấm mù đã mở nhầm "Recent sources"; hộp lỗi kết nối đã Cancel, không có gì nhập vào file thử). Luôn bấm theo nhãn.
- Thẻ lọc: phải rê chuột lên thẻ rồi bấm mũi tên (x ≈ 1195) mới mở được; bấm vào tên thẻ không mở.

## Dọn dẹp

Đã làm 2026-11-13: đóng Power BI Desktop (`taskkill`), xoá `C:\Users\bacpew\vmd8\` trong VM và `~/Desktop/vmd8out/` trên Mac (các bản sao dữ liệu của người dùng). VM vẫn chạy như trước buổi quan sát.
