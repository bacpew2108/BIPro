# VM-D13: đổi sang bản đồ hình và trang hiển thị duy nhất (2026-11-14)

Bạn cho phép dùng VM. Claude điều khiển Power BI Desktop trên bản sao `Nhom6_work.pbix` (đã xoá khỏi VM và Mac sau khi xong). Chỉ thao tác giao diện, lưu, đọc diff `visual.json`. Mẫu trong `json/`.

## 1. Đổi sang bản đồ hình (`json/retype-shapeMap-line.visual.json`, `-donut.visual.json`)

Hai thử: biểu đồ đường Q1.1 của D1 (Category ngày, Y, Tooltips) và donut Q1.2 (ba cột chữ ở Category, một measure ở Y, hai ở Tooltips).

- **Ô:** cột đầu của `Category` vào **`Series`** (ô "Legend"), kể cả cột chữ; cột thứ hai, ba bị bỏ (ô một trường); `Y` vào **`Value`** ("Color saturation"); `Tooltips` giữ nguyên. Cột ở `Series` **không có `active`** (bỏ cờ của Category).
- **`objects`:** khoá của đích bản đồ hình khác: `labels` và `value` (donut), trục và `forecast` (đường) bị bỏ; `legend` và `dataPoint` có sẵn giữ nguyên. Thêm `objects.shape` (`datasourceType: 'file_upload'`, `map.geoJson` loại `'shared'`, tên `'usa.states.topo'`, `content` là `ResourcePackageItem` của `SharedResources`, `projectionEnum: 'albersUsa'`) ở cuối `objects`, và một mục **`dataPoint` chuyển sắc** (`fillRule.linearGradient2`, màu nhỏ nhất `'minColor'`, lớn nhất `'maxColor'`, `nullColoringStrategy: 'asZero'`, không có `selector`) thêm vào **cuối** mảng `dataPoint` (tạo mảng nếu chưa có). Khi chưa có `objects` thì Desktop tạo, ngay sau `query`.
- Bản đồ chưa có cột vị trí (`Category` trống) nên chỉ vẽ nền xám kèm chú giải theo cột ngày.

BI Pro: `TypeChange.targetFirst` (Category → `Series`, Y → `Value`), `PBIRQueryPatch.Element.withoutActive`, `PBIRVisualPatch.addingShapeMapDefaults`, `keepsObjectKey` (`labels` bỏ khi đích là bản đồ hình), `WellRules` và `VisualCatalog` (ô `Series`, `Value`, `Tooltips` của bản đồ hình), `VisualDataLoader` (bản đồ hình không có `Category`: không chạy truy vấn, vẽ bản đồ trơn). Từ chối đổi nếu file chưa có tài nguyên `usa.states.topo` (Desktop tự thêm vào file, BI Pro không có nguồn của nó). BI Pro chưa vẽ chú giải theo `Series` hay màu theo `Value`.

`D5Nhom6Tests.doiDuongSangBanDoHinhNhuDesktop`: kết quả của BI Pro trên Nhom6 thật bằng từng khoá với hai mẫu trên (trừ thứ tự khoá và `$schema`).

## 2. Menu chuột phải của tab trang: khi nào không có Delete, Hide, Move to

Ở VM-D12 menu của tab D1 chỉ có "Set as landing page", "Duplicate", "Rename". Nguyên nhân (thử lại trên file mới mở, 4 trang, D4 ẩn):

| Trang hiển thị | Menu của D1 |
|---|---|
| D1, D2, D3 (D4 ẩn) | đủ: Set as landing page, Duplicate, Rename, **Delete, Hide, Move to** (cả khi D1 hay D2 đang mở) |
| ẩn D2: D1, D3 | đủ |
| ẩn D2 và D3: **chỉ D1 hiển thị** | chỉ **Set as landing page, Duplicate, Rename** |

Vậy Desktop không cho xoá, ẩn, di chuyển **trang hiển thị duy nhất** (trang ẩn như trang drillthrough không tính); trang ẩn vẫn xoá được (D4 ẩn có Delete). Không liên quan tới trang mở đầu hay trang đang mở.

BI Pro: `PageStructure.removalRefusal(removingHidden:otherVisiblePages:)` từ chối xoá trang hiển thị duy nhất (ngoài luật "còn ít nhất một trang" có sẵn). Hide và Move to: BI Pro chưa có "ẩn trang"; kéo đổi thứ tự trang giữ nguyên (Desktop có thể cũng chặn kéo trang hiển thị duy nhất, chưa thử).
