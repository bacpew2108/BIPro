# Hợp đồng: RibbonCatalog

Nguồn sự thật cho **tên, thứ tự, kiểu, trạng thái** của mọi nút Ribbon. Tiêu đề `en` là chữ của Power BI Desktop (cột "EN"); tiêu đề `vi` do worker đặt theo bản dịch hiện có trong `L10n.swift` hoặc `bi(...)` quanh đó, không đổi nghĩa. Ảnh chuẩn: `docs/phase-ui-evidence/vm-ui/rb_*-2x.png`; giải thích: `docs/PHASE_H_UI_PARITY.md` mục 3.5, 3.6, 3.10.

## Quy ước

- **ID lệnh** (`RibbonCommandID`): camelCase của EN (ví dụ `getData`, `newMeasure`). Lệnh xuất hiện ở nhiều tab dùng **cùng một ID**.
- **Kiểu:** `L` nút lớn · `S` nút nhỏ trong một `smallStack` · `L▾` nút lớn có menu · `chk` hộp kiểm · `fld` ô chọn kèm nhãn · `gal` thư viện ô mẫu · `tgl` nút bật/tắt.
- **Khả dụng (`Avail`):** `A` luôn bật · `D` cần có dữ liệu/mô hình · `V` cần chọn visual (và chế độ cho phép sửa) · `M` cần quyền sửa mô hình · `T` cần chọn bảng · `C` cần chọn cột · `X` **không hỗ trợ** (`unsupported`, luôn vô hiệu, tooltip "BI Pro chưa hỗ trợ …" song ngữ) · `P` chưa làm (vô hiệu có tooltip, sẽ bật khi có tính năng).
- **Hành động:** tên hàm `DocumentState` hiện có (giữ nguyên hành vi); `mới` = cần viết, kèm brief; `—` = không có hành động (`X`/`P`).
- **obs:** `✓` đã quan sát; `?` = `[SUY ĐOÁN]` (mã phải ghi chú).
- Thứ tự dòng = thứ tự trái → phải; nút nhỏ cùng ô ghi `S1..S3` theo thứ tự trên → dưới.
- Danh sách tab theo view (`RibbonCatalog.tabs`):

| View | Tab (thứ tự) |
|---|---|
| Report, không chọn visual | file, home, insert, modeling, design, view, optimize, help |
| Report, chọn visual | như trên + format, dataDrill |
| Table | file, home, help, tableTools, columnTools |
| Model / DAX / TMDL | file, home, help |

`file` không có nhóm Ribbon: bấm mở Backstage (H5).

## Report — Home (`home`)

| Nhóm | Dòng | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|---|
| Clipboard | 1 | `paste` | Paste | L | V* (có clipboard visual, chế độ cho phép sửa) | `layout.paste()` | ✓ |
| Clipboard | 2 | `cut` | Cut | S1 | V | `layout.cut()` | ✓ |
| Clipboard | 2 | `copy` | Copy | S2 | V | `layout.copy()` | ✓ |
| Clipboard | 2 | `formatPainter` | Format painter | S3, tgl | V (1 visual) | `layout.beginFormatPainter()/cancelFormatPainter()` | ✓ |
| Data | 3 | `getData` | Get data | L▾ | D | `showGetData()` | ✓ |
| Data | 4 | `excelWorkbook` | Excel workbook | L | D | `showGetData(kind: .excel)` | ✓ |
| Data | 5 | `oneLakeCatalog` | OneLake catalog | L▾ | X | — | ✓ |
| Data | 6 | `sqlServer` | SQL Server | L | D | giữ nhãn EN "SQL Server"; bấm mở menu nguồn CSDL BI Pro hỗ trợ (PostgreSQL…, SQLite…) qua `showGetData(kind:)`; tooltip ghi rõ nguồn hỗ trợ | ✓ |
| Data | 7 | `enterData` | Enter data | L | D | `showEnterData()` | ✓ |
| Data | 8 | `dataverse` | Dataverse | L | X | — | ✓ |
| Data | 9 | `recentSources` | Recent sources | L▾ | P | — (`mới`: menu nguồn gần đây nếu có) | ✓ |
| Queries | 10 | `transformData` | Transform data | L▾ | D | `showQueryEditor()` | ✓ |
| Queries | 11 | `refresh` | Refresh | L▾ | D | `startRefreshAll()`; menu `Schema and data` (= refresh all), `Schema` (P), `Data` (P) | ✓ |
| Insert | 12 | `newVisual` | New visual | L | V-edit (`visualEditingBlocker`) | `insertVisual("cardVisual")` | ✓ |
| Insert | 13 | `textBox` | Text box | L | V-edit | `insertVisual("textbox")` | ✓ |
| Insert | 14 | `moreVisuals` | More visuals | L▾ | V-edit | mới: popover `VisualCatalog` | ✓ |
| Calculations | 15 | `newVisualCalculation` | New visual calculation | L▾ | P | — | ✓ |
| Calculations | 16 | `newMeasure` | New measure | L | M | `newMeasureInTableView(table:)` | ✓ |
| Calculations | 17 | `quickMeasure` | Quick measure | L | M | `showQuickMeasureSheet = true` | ✓ |
| Sensitivity | 18 | `sensitivity` | Sensitivity | L▾ | X | — | ✓ |
| Share | 19 | `publish` | Publish | L | X | — | ✓ |
| Copilot | 20 | `prepDataForAI` | Prep data for AI | L | X | — | ✓ |
| Copilot | 21 | `copilot` | Copilot | L | X | — | ✓ |

Nhóm Arrange hiện có (Align, Group, Ungroup, Merge) **rời khỏi Home** sang `format` (dưới).

## Report — Insert (`insert`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Pages | `newPage` | New page | L▾ | A-edit (`pageEditingBlocker`) | `addPage()`; menu: `New page`, `Duplicate page` (hành động nhân bản trang hiện có nếu có, ngược lại P) | ✓ |
| Visuals | `newVisual` | New visual | L | V-edit | `insertVisual("clusteredColumnChart")` | ✓ |
| Visuals | `moreVisuals` | More visuals | L▾ | V-edit | popover `VisualCatalog` | ✓ |
| AI visuals | `keyInfluencers` | Key influencers | L | P | — | ✓ |
| AI visuals | `decompositionTree` | Decomposition tree | L | P | — | ✓ |
| AI visuals | `narrative` | Narrative | L | P | — | ✓ |
| Power Platform | `paginatedReport` | Paginated report | L | X | — | ✓ |
| Power Platform | `powerApps` | Power Apps | L | X | — | ✓ |
| Power Platform | `powerAutomate` | Power Automate | L | X | — | ✓ |
| Elements | `textBox` | Text box | L | V-edit | `insertVisual("textbox")` | ✓ |
| Elements | `buttons` | Buttons | L▾ | V-edit | menu: Right arrow, Reset, Back, Information, Help, Bookmark, Blank, Apply all slicers, Clear all slicers (hiện có: Blank → `insertVisual("actionButton")`; các mục khác P hoặc `actionButton` với loại tương ứng nếu đã hỗ trợ), `Navigator ›` (Page navigator, Bookmark navigator hiện có; menu con `?`) | ✓ (menu con ?) |
| Elements | `shapes` | Shapes | L▾ | V-edit | `insertShape(id)`; hiện có rectangle/oval/line; thư viện theo ảnh `dd_shapes.png`: mục chưa có = P | ✓ |
| Elements | `image` | Image | L | V-edit | `pickAndInsertImage()` | ✓ |
| Sparklines | `addSparkline` | Add a sparkline | L | P | — | ✓ |

## Report — Modeling (`modeling`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Relationships | `manageRelationships` | Manage relationships | L | D | `mode = .model` | ✓ |
| Calculations | `newVisualCalculation` | New visual calculation | L▾ | P | — | ✓ |
| Calculations | `newMeasure` | New measure | L | M | `beginNewMeasure(table:)` | ✓ |
| Calculations | `quickMeasure` | Quick measure | L | M | `showQuickMeasureSheet` | ✓ |
| Calculations | `newColumn` | New column | L | M | `beginNewColumn(table:)` | ✓ |
| Calculations | `newTable` | New table | L | M | `beginNewTable()` | ✓ |
| Calendars | `markAsDateTable` | Mark as date table | L | T | hành động hiện có ở Table tools (`MarkAsDateTableSheet`) | ✓ |
| Page refresh | `changeDetection` | Change detection | L | X | — | ✓ |
| Parameters | `newParameter` | New parameter | L▾ | P | — | ✓ |
| Security | `manageRoles` | Manage roles | L | M | `showManageRolesSheet = true` | ✓ |
| Security | `viewAs` | View as | L, tgl | D | `showViewAsRoleSheet = true` | ✓ |
| Q&A | `qnaSetup` | Q&A setup | L | X | — | ✓ |
| Q&A | `language` | Language | L▾ | X | — | ✓ |
| Q&A | `linguisticSchema` | Linguistic schema | L▾ | X | — | ✓ |

## Report — Design (`design`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Themes | `themeGallery6` | (thư viện 6 ô mẫu + mũi tên mở rộng) | gal | M-edit | dùng lại `ThemePickerPopover`/áp theme hiện có; menu `Themes ▾`: banner "Previous color-only themes are now color palettes. Open theme format pane.", `This report`, `Power BI` (9 ô), `Theme gallery` | ✓ (tên theme ?) |
| Themes | `themeGallery` | Theme gallery | L | P | — | ✓ |
| Themes | `customizeTheme` | Customize theme | S1 | P | — | ✓ |
| Themes | `downloadTheme` | Download theme | S2 | hiện có (Xuất theme `.json`) | hành động xuất hiện có | ✓ |
| Themes | `importTheme` | Import theme | S3 | hiện có (Nhập theme `.json`) | hành động nhập hiện có | ✓ |
| Customize page | `pageSize` | Page size | L▾ | P | — | ✓ |
| Customize page | `pageBackground` | Page background | L | P | — | ✓ |
| Customize page | `wallpaper` | Wallpaper | L | P | — | ✓ |
| Help | `howToCreateTheme` | How to create a theme | L | X | — | ✓ |

## Report — View (`view`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Scale to fit | `pageView` | Page view | L▾ | A | menu `Fit to page` (`zoom = nil`), `Fit to width`, `Actual size` (`zoom = 1`) | ✓ |
| Mobile | `mobileLayout` | Mobile layout | L | X | — | ✓ |
| Page options | `gridlines` | Gridlines | chk | P | — | ✓ |
| Page options | `snapToGrid` | Snap to grid | chk | A | `AppPreferences.snapToGrid` | ✓ |
| Page options | `lockObjects` | Lock objects | chk | P | — | ✓ |
| Show panes | `showFilters` | Filters | L, tgl | A | `showFilters.toggle()` | ✓ |
| Show panes | `showBookmarks` | Bookmarks | L, tgl | A | `showBookmarks.toggle()` | ✓ |
| Show panes | `showSelection` | Selection | L, tgl | A | `showSelection.toggle()` | ✓ |
| Show panes | `performanceAnalyzer` | Performance analyzer | L, tgl | P | — | ✓ |
| Show panes | `syncSlicers` | Sync slicers | L | P | — | ✓ |

Menu thả xuống `viewOnly` ("Chế độ chỉ xem") nằm trong menu của nút `pageView` hoặc menu View của macOS (xem R-02). Nút bật/tắt `Data`/`Visualizations` **không có** ở đây.

## Report — Optimize (`optimize`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Queries | `pauseVisuals` | Pause visuals | L | P | — | ✓ |
| Queries | `refreshVisuals` | Refresh visuals | L | A | làm mới truy vấn visual hiện có nếu có, ngược lại P | ✓ |
| Report | `optimizationPresets` | Optimization presets | L▾ | P | — | ✓ (menu ?) |
| Review | `performanceAnalyzer` | Performance analyzer | L | P | — | ✓ |
| Apply | `applyAllSlicers` | Apply all slicers button | L | P | — | ✓ |

## Report — Help (`help`)

| Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Info | `about` | About | L | A | popover About hiện có (phiên bản 1.3.0) | ✓ |
| Help | `guidedLearning` | Guided learning | L | A | mở tài liệu hướng dẫn trong app (`requestShowOnboarding`) | ✓ |
| Help | `trainingVideos` | Training videos | L | X | — | ✓ |
| Help | `documentation` | Documentation | L | X | — | ✓ |
| Help | `support` | Support | L | X | — | ✓ |
| Community | `powerBIBlog` `community` `powerBIForDevelopers` `submitAnIdea` `externalTools` | Power BI blog · Community · Power BI for developers · Submit an idea · External tools | L | X | — | ✓ |
| Resources | `examples` | Examples | L▾ | X | — | ✓ |
| Resources | `consultingServices` | Consulting services | L | X | — | ✓ |

## Ngữ cảnh — Format (`format`) và Data / Drill (`dataDrill`)

| Tab/Nhóm | ID | EN | Kiểu | Avail | Hành động | obs |
|---|---|---|---|---|---|---|
| Format · Interactions | `editInteractions` | Edit interactions | L, tgl | V | hành động hiện có (`FormatCommands`) | ✓ |
| Format · Interactions | `applyDrillFiltersTo` | Apply drill down filters to | fld (`Entire page`) | P | — | ✓ |
| Format · Arrange | `bringForward` | Bring forward | L▾ | V | mới (đưa lên) hoặc P nếu engine bố cục chưa có thứ tự z | ✓ |
| Format · Arrange | `sendBackward` | Send backward | L▾ | V | như trên | ✓ |
| Format · Arrange | `selectionPane` | Selection | L, tgl | A | `showSelection.toggle()` | ✓ |
| Format · Arrange | `align` | Align | L▾ | V (≥ 2) | `align(command)` hiện có | ✓ |
| Format · Arrange | `group` | Group | L▾ | V (≥ 2) | `groupSelection()`; menu: Group, Ungroup (`ungroupSelection()`), Merge (`mergeSelection()`) | ✓ |
| Data/Drill · Show | `visualTable` | Visual table | L | V | "Show as a table" hiện có | ✓ |
| Data/Drill · Show | `dataPointTable` | Data point table | L | P | — | ✓ |
| Data/Drill · Interactions | `applyDrillFiltersTo` | Apply drill down filters to | fld | P | — | ✓ |
| Data/Drill · Drill actions | `switchToNextLevel` | Switch to next level | S1 | V (có phân cấp) | P | ✓ |
| Data/Drill · Drill actions | `expandNextLevel` | Expand next level | S2 | V (có phân cấp) | hiện có | ✓ |
| Data/Drill · Drill actions | `drillUp` | Drill up | S3 | V (có phân cấp) | hiện có | ✓ |
| Data/Drill · Drill actions | `drillDown` | Drill down | S4 | V (có phân cấp) | hiện có | ✓ |
| Data/Drill · Drill actions | `drillThrough` | Drill through | L | V | hiện có nếu có, ngược lại P | ✓ |
| Data/Drill · Data groups | `groups` | Groups | L▾ | P | — | ✓ |
| Data/Drill · AI | `findAnomalies` | Find anomalies | L | X | — | ✓ |

## Table view — Home / Table tools / Column tools

**Home (Table)**: Clipboard (`paste` L, `cut` `copy` S) · Data (như Report Home: `getData`, `excelWorkbook`, `oneLakeCatalog`, `sqlServer`, `enterData`, `dataverse`, `recentSources`) · Queries (`transformData`, `refresh`) · Relationships (`manageRelationships`) · Calculations (`newMeasure`, `quickMeasure`, `newColumn`, `newTable`) · Security (`manageRoles`, `viewAs`) · Sensitivity (`sensitivity` X) · Share (`publish` X). Không có Insert, Copilot.

**Table tools (`tableTools`)**: Structure → `tableName` (fld, hiện có: đổi tên bảng + `CascadeRename`) · Relationships → `manageRelationships` · Calculations → `newMeasure`, `quickMeasure`, `newColumn`, `newTable` · Calendars → `markAsDateTable`.

**Column tools (`columnTools`)**: Structure → `columnName` (fld), `dataType` (fld) · Formatting → `format` (fld) + hàng `currencyFormat` (`$` ▾), `percentFormat` (`%`), `thousandsFormat` (`,`), `decimalFormat` (`.00`) + ô `decimalPlaces` (`Auto`) · Properties → `summarization` (fld), `dataCategory` (fld) · Sort → `sortByColumn` (L▾) · Groups → `dataGroups` (L▾, P) · Relationships → `manageRelationships` · Calculations → `newColumn`. Hành động: các closure trong `ColumnToolsCommands`/`TableToolsCommands` hiện có, giữ nguyên.

## Model / DAX / TMDL — Home

**Model Home**: Clipboard · Data · Queries · Relationships (`manageRelationships`) · Calculations (`newMeasure`, `newColumn`, `newTable`, `calculationGroup` P) · Parameters (`newParameter` P) · Security (`manageRoles`, `viewAs`) · Q&A (`qnaSetup` X, `language` X, `linguisticSchema` X) · Sensitivity (X) · Share (`publish` X). Không có `quickMeasure`.

**DAX Home**: Clipboard (`paste` L, `cut` `copy` S) · Editing (`daxFormat` Format, `comment` Comment, `uncomment` Uncomment, `find` Find, `replace` Replace, `commandPalette` Command palette) · Copilot (`copilot` X). Hành động: Format = `DAXEngine.format` hiện có; Comment/Uncomment/Find/Replace/Command palette = `mới` hoặc P nếu trình soạn chưa hỗ trợ.

**TMDL Home**: Clipboard (`paste` L, `cut` S, `copy` S — `copy` nối hành động "Sao chép" TMDL hiện có) · Editing (`tmdlFormat` Format P, `find`, `replace`, `commandPalette`). Nút **Xuất TMDL** hiện có KHÔNG nằm trên Ribbon: chuyển vào File ▸ Export.

Nút **Sắp xếp lại** và **Vừa màn hình** của Model view hiện có KHÔNG nằm trên Ribbon: chuyển thành nút đặt lại/fit trên thanh trạng thái Model view.

Các nút nằm **trên trình soạn thảo** (không thuộc Ribbon): DAX `run` Run, `updateModel` "Update model with changes (n)"; TMDL `apply` Apply, `preview` Preview.

## Kiểm thử bắt buộc cho hợp đồng

1. `RibbonCatalogTests`: với từng (view, selection) trong bảng tab, `tabs()` đúng thứ tự; với từng tab, danh sách (nhóm → EN → kiểu → Avail loại) khớp các bảng trên (tệp kiểm chứa dữ liệu chuẩn riêng, không sinh từ catalog).
2. `RibbonAvailabilityTests`: dựng `RibbonContext` giả cho: báo cáo trống, có dữ liệu chưa chọn, chọn 1 visual, chọn nhiều visual, chế độ chỉ xem, không có mô hình; kiểm từng nút bật/tắt đúng và có lý do.
3. `RibbonBilingualTests`: `vi`/`en` không rỗng, `en` đúng chuẩn, `unsupported` có tooltip.
4. `RibbonActionsTests`: mọi ID có hành động hoặc `—`; hành động cũ (paste, group, align, getData…) vẫn gọi đúng hàm (dùng `DocumentState` thật với `SyntheticReport`).
