# Quan sát VM-D6 (2026-11-11, Claude điều khiển VM theo lời cho phép của người dùng)

Làm trên bản chép của `Nhom6_work.pbix` trong VM (`C:\Users\bacpew\vmd6\work.pbix`, đã xoá sau khi dùng), Power BI Desktop 2.159.x, trang D3 (`d3_cskh`). Cách làm: đổi **một** thứ trong Desktop, Ctrl+S (lưu tại chỗ), chép file sang Mac, so các part `Report/definition/bookmarks/`, `report.json`, `page.json`, `visual.json`. Không dịch ngược; chỉ nhìn giao diện và file Desktop ghi. Bản chụp JSON: `json/`; ảnh: `desktop-*.png`. File `.pbix` trung gian đã xoá (bản sao dữ liệu của người dùng).

## 0. Điều chung

- Desktop **không ghi lại bookmark không đổi** (hai file `Bookmark_Q13_*` giữ nguyên từng byte sau mọi lần lưu) và không sửa `bookmarks.json` khi không đổi danh sách. Vậy ghép byte của BI Pro (giữ nguyên phần không đổi) là chuẩn.
- File ghi **gọn một dòng**, không thụt dòng (cả bookmark lẫn thẻ lọc).
- Thêm bộ lọc làm Desktop sửa thêm `report.json`: `objects.outspacePane.expanded` đổi `false` → `true` (trạng thái giao diện Filters pane, không liên quan); BI Pro không cần ghi.

## 1. Bookmark: thêm (Add), tuỳ chọn Data/Display/Current page

Add với mặc định (Data, Display, Current page bật; All visuals), trên trang D3:

- `bookmarks.json`: thêm `{name}` ở **cuối** `items`; `name` và tên file là 20 ký tự hex (`fb63188de6853bc66093`), `displayName` "Bookmark N" (N = số bookmark hiện có + 1; sau khi xoá hết, thêm lại ra "Bookmark 1").
- File bookmark, khoá theo thứ tự: `$schema` (`bookmark/2.1.0`), `displayName`, `name`, `options`, `explorationState`.
- `options` mặc định: `{"targetVisualNames":[],"preserveNewVisualVisibility":true}`.
- `explorationState`, khoá theo thứ tự: `version:"1.3"`, `activeSection` (trang đang mở), `filters.byExpr` (bộ lọc cấp báo cáo), `sections`, `objects` (`{"merge":{"outspacePane":[{"properties":{"expanded":{"expr":{"Literal":{"Value":"false"}}}}}]}}`, trạng thái pane Filters). `sections.<trang>.visualContainers` có **đủ mọi visual của trang (32)**, mỗi visual `{filters?, singleVisual{visualType, objects, activeProjections, display?, orderBy?}}`. Mọi visual có `filters.byExpr` ghi **cả thẻ chưa lọc** (chỉ `name`, `type`, `expression`, `howCreated:0`). Dung lượng 17 đến 19 KB cho một bookmark: Desktop chụp **toàn trạng thái trang**.
- Tắt từng tuỳ chọn chỉ thêm cờ vào `options`, **không đổi `explorationState`** (Desktop vẫn chụp đủ): Data tắt → `suppressData:true`; Display tắt → `suppressDisplay:true`; Current page tắt → `suppressActiveSection:true`. Thứ tự khoá trong `options`: `applyOnlyToTargetVisuals`, `targetVisualNames`, `suppressActiveSection`, `suppressData`, `suppressDisplay`, `preserveNewVisualVisibility`.
- "Selected visuals": `applyOnlyToTargetVisuals:true`; `targetVisualNames` rỗng cho tới khi Update với visual đang chọn thì ghi mã visual đó (`["0bb5d766f511f119000b"]`). Add khi đang có visual được chọn ghi sẵn mã đó vào `targetVisualNames` dù All visuals.
- Visual ẩn (Selection pane) trong `explorationState`: `singleVisual.display = {"mode":"hidden"}` (cuối `singleVisual`). Ẩn trong Selection pane còn thêm `isHidden:true` vào `visual.json` của visual (cuối khoá, sau `visual`), việc khác với bookmark.
- Dạng tối giản đã được Desktop chấp nhận (không ghi lại): hai file Nhom6 `Bookmark_Q13_*` (`options{applyOnlyToTargetVisuals, targetVisualNames, suppressActiveSection, suppressData}`, `explorationState{version "1.0", activeSection, sections.<trang>.visualContainers.<visual>.singleVisual{visualType, display?}}`). VM-D1 đã mở Nhom6 nguyên bản trong Desktop: bookmark áp được.

## 2. Bookmark: Update, Rename, Delete, đổi thứ tự, Group

- **Update**: ghi lại cả file (state mới), giữ `name`, `displayName`, các tuỳ chọn; ghi `targetVisualNames` theo visual đang chọn.
- **Rename**: chỉ đổi `displayName` (cùng độ dài file, các khoá khác nguyên).
- **Delete**: bỏ item khỏi `bookmarks.json` và **xoá file** `<name>.bookmark.json`. Xoá bookmark cuối cùng: **xoá luôn `bookmarks.json`** (thư mục `bookmarks/` biến mất). Thêm lại khi chưa có: tạo `bookmarks.json` với `$schema` (`bookmarksMetadata/1.0.0`) và `items:[{name}]`.
- **Đổi thứ tự** (kéo): chỉ đổi thứ tự `items` trong `bookmarks.json`; file bookmark không đổi.
- **Group**: nút bị mờ khi chọn một bookmark (cần chọn nhiều). Chưa quan sát nhóm; nằm ngoài phạm vi D6.

## 3. Bộ lọc (Filters pane)

- Thêm cột vào "Filters on this page" hoặc "all pages" bằng chuột phải trường → Add to filters → Page-level/Report-level (kéo thả từ script không chạy). Bộ lọc báo cáo thêm ở **cuối** `filterConfig.filters` của `report.json`.
- `page.json`: khoá `filterConfig` chèn **sau `width`, trước `objects`**; xoá thẻ cuối cùng thì xoá cả `filterConfig` và `page.json` về đúng từng byte ban đầu.
- Thẻ Basic chưa chọn gì: `{"name":<20 hex>,"field":{"Column":{"Expression":{"SourceRef":{"Entity":..}},"Property":..}},"type":"Categorical","howCreated":"User"}` (không có `filter`).
- Basic chọn giá trị ("is Female"): thêm `filter` **trước** `howCreated`: `{"Version":2,"From":[{"Name":"d","Entity":"Dim_Client","Type":0}],"Where":[{"Condition":{"In":{"Expressions":[{"Column":{"Expression":{"SourceRef":{"Source":"d"}},"Property":"sex"}}],"Values":[[{"Literal":{"Value":"'Female'"}}]]}}}]}`. Bí danh `From` Desktop đặt là **chữ cái đầu của bảng, viết thường** (`d` cho `Dim_Client`; Nhom6 do tác giả đặt dùng `x`). Giá trị chữ trong nháy đơn, số `…L`, hex tên thẻ 20 ký tự ngẫu nhiên.
- Advanced (kiểu `"Advanced"`, cùng `From`, `Where` một `Condition`): "starts with" → `StartsWith{Left:Column,Right:Literal}`; "contains" → `Contains{Left,Right}`; "does not contain" → `Not{Expression:Contains{..}}`; hai điều kiện Và → `And{Left,Right}`. Chưa quan sát: "is"/"is not", "is blank", so sánh số (`Comparison`), `Or`.
- Top N (visual): thẻ `type:"TopN"`, `filter{Version:2,From:[{Name:"subquery",Expression:{Subquery:{Query:{Version:2,From:[{Name:"d",Entity,Type:0},{Name:"f",Entity,Type:0}],Select:[{Column..., Name:"field"}],OrderBy:[{Direction:2,Expression:{Measure..}}],Top:1}}},Type:2},{Name:"d",Entity,Type:0}],Where:[{Condition:{In:{Expressions:[Column],Table:{SourceRef:{Source:"subquery"}}}}}]}`. Khi lưu Desktop ghi cho visual đó **mọi thẻ của Filters pane** vào `visual.json` (`filterConfig` sau `visual`): cột chưa lọc `type:"Categorical"`, measure chưa lọc `type:"Advanced"`, không có `filter`/`howCreated`.
- Visual chưa động vào Filters pane không có `filterConfig`.

## 4. Chưa quan sát

- Lock/Hide thẻ (`isLockedInViewMode`, `isHiddenInViewMode`), "Clear filter" riêng.
- Advanced: "is", "is not", "is blank", "is empty", so sánh số, `Or`; Bottom N.
- Nhóm bookmark (Group); bookmark Data khi chỉ có bộ lọc đổi (đối chiếu `bookmark-data.pbix` ở VM-C2).
- Dạng tối giản của bookmark Data mà Desktop chấp nhận (cần BI Pro ghi thử rồi mở trong Desktop, T035/T031).

## Vòng 2 (2026-11-11): BI Pro ghi thử, Desktop mở và bấm

Các file thử dựng từ `Nhom6_d6.pbix` / `Nhom6_d6_pre.pbix` (BI Pro ghi, không phải Desktop), mở trong Power BI Desktop 2.159.x trên VM, rồi xoá (`C:\Users\bacpew\vmd6\`).

- **`Nhom6_d6.pbix` (bookmark Display-only dạng tối giản Nhom6, bộ lọc Basic trang và visual, đổi tên, xoá bookmark)**: Desktop mở không báo lỗi. Bookmarks pane: "Giờ × Thứ (D6)" (đã đổi tên), "Bookmark D6" (mới, cuối danh sách); bookmark đã xoá không còn. Bấm "Bookmark D6": chuyển sang trang D1 và ẩn card đã chọn. Trang D3 có bộ lọc `sex = Female` (card "Tổng khách hàng" 5.369 → 2.645, legend chỉ còn Female). Ảnh `checklist-d6-bookmarks-filters.png`, `checklist-d6-bookmark-applied.png`.
- **Bookmark Data tối giản** (`options{targetVisualNames:[],preserveNewVisualVisibility:true}`, `explorationState{version:"1.3",activeSection,sections.<trang>.visualContainers.<slicer>.singleVisual{visualType,objects.merge.general[0].properties.filter.filter}}`, không `activeProjections`, không thẻ lọc, không `cachedFilterDisplayItems`): Desktop áp đúng, chuyển trang D1 và đặt slicer "Loại GD" = Credit. Ảnh `checklist-d6-data-min-credit.png`.
- Slicer có `singleVisual:{visualType:"slicer"}` (không `objects`) trong bookmark Data **đặt slicer về "All"**; `objects.merge.general:[{properties:{}}]` cũng vậy chưa thử riêng. Ảnh `checklist-d6-data-reset.png`.
- Nhiều giá trị `Values:[[v1],[v2]]` ("Credit", "Debit"): Desktop hiện "Multiple selections". Ảnh `checklist-d6-data-two-values.png`.
- Bookmark Data + ẩn visual: `singleVisual{visualType:"card",display:{mode:"hidden"}}` ẩn đúng card. Ảnh `checklist-d6-data-hide-reset.png`.
- Chưa thử: thẻ lọc `filters.byExpr` (Filters pane) trong bookmark; slicer hierarchy; lựa chọn điểm dữ liệu (lọc chéo); drill.
