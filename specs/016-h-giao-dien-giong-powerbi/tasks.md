---
description: "Danh sách tác vụ triển khai v1.3 (Phase H) — Giao diện giống Power BI Desktop"
---

# Tác vụ: v1.3 (Phase H) — Giao diện BI Pro giống Power BI Desktop

**Thư mục spec:** `specs/016-h-giao-dien-giong-powerbi/`
**Ngày lập:** 2026-11-21 · **Trạng thái:** Đã qua `/speckit-analyze` và sửa (C1, C2, I1–I4, U1–U6, K1, T1); sẵn sàng giao agy theo `docs/tasks/h-master.md`
**Đầu vào:** [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/ribbon-catalog.md](contracts/ribbon-catalog.md), [contracts/ui-tokens.md](contracts/ui-tokens.md), [contracts/visual-gallery.md](contracts/visual-gallery.md), [quickstart.md](quickstart.md), [`docs/PHASE_H_UI_PARITY.md`](../../docs/PHASE_H_UI_PARITY.md)

**Kiểm thử:** có. `CLAUDE.md` yêu cầu `/tdd` khi viết code: viết test trước, thấy đỏ, rồi cài đặt. Test mới nằm ở `Tests/BIProTests/UIParity/`.

**Lệnh dùng chung** (chạy ở gốc repo):
- Build: `swift build`
- Test: `swift test --no-parallel` (thêm `--filter UIParity` cho test mới)
- Golden nặng (hồi quy): `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests|V11BDAXGoldenTests"`
- Xuất ảnh: `BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests` → `build/h-out/`
- Đóng gói: `zsh scripts/build-app.sh release`

**Đổi chiếu số Phase trong tệp này với mã pha H của `plan.md`:** Phase 1–2 = H0 · Phase 3 (US1) = H1 · Phase 4 (US2) = H2 · Phase 5 (US3) = H3 · Phase 6–8 (US4–US6) = H4 · Phase 9–10 (US7–US8) = H5 · Phase 11 = H6.

## Định dạng

`- [ ] Txxx [P?] [USn?] Mô tả kèm đường dẫn tệp`. **[P]** = làm song song được (tệp khác nhau, không phụ thuộc tác vụ chưa xong). **[USn]** gắn với user story của `spec.md`. Hai tác vụ cùng sửa một tệp **không** được đánh [P] với nhau.

---

## Phase 1: Chuẩn bị (H0 — không đổi hành vi)

**Mục đích:** lập bảng sở hữu tệp, danh sách test bị ảnh hưởng, khung thư mục test.

- [x] T001 Liệt kê mọi test và mã đang dùng `RibbonTab`, `state.tabs`, `ribbonTab`, `RibbonButton`, `RibbonGroup` (`grep -rn` trong `Sources/BIPro` và `Tests/BIProTests`) và ghi kết quả (tệp, dòng, pha sẽ sửa) vào `docs/tasks/h0-test-impact.md`
- [x] T002 [P] Rà `docs/phase-h-ownership.tsv` (lead đã lập bản đầu; KHÔNG tạo lại, chỉ sửa nếu vị trí thật của tệp lệch) (định dạng `area<TAB>glob<TAB>owner<TAB>notes` như `docs/phase-g-ownership.tsv`) theo bảng pha trong `plan.md`: mỗi tệp `Shell/Ribbon/Catalog+*.swift`, `Shell/TitleBar.swift`, `Shell/Rail.swift`, `Shell/StatusBar.swift`, `Panes/*`, `Report/ReportWorkspace.swift`… có đúng một chủ (gói H1…H6); xác nhận lại vị trí thật của `PageTabs` (`Report/ReportWorkspace.swift`), `StatusBar` (`Shell/ShellView.swift`), khung DAX/TMDL (`Query/QueryWorkspaces.swift`)
- [x] T003 [P] Tạo thư mục `Tests/BIProTests/UIParity/` và tệp `Tests/BIProTests/UIParity/RibbonReference.swift` chứa **dữ liệu chuẩn viết tay** (không sinh từ catalog): bảng tab theo view (contracts/ribbon-catalog.md mục "Quy ước") và danh sách tab → nhóm → EN → kiểu → Avail cho Report Home; các tab còn lại bổ sung ở story tương ứng

**Checkpoint:** có bảng sở hữu, danh sách test ảnh hưởng, nơi đặt dữ liệu chuẩn.

---

## Phase 2: Nền tảng (H0 — chặn mọi story)

**Mục đích:** hợp đồng dữ liệu Ribbon, token số đo/màu, khoá tuỳ chọn. **Chưa đổi giao diện hiện có.**

- [x] T004 [P] Tạo `Sources/BIPro/Shell/Ribbon/RibbonModel.swift`: `Bilingual`, `RibbonTabID`, `RibbonTabSpec`, `RibbonGroupSpec`, `RibbonItemSpec`, `RibbonItemKind` (`large, smallStack, checkbox, field, gallery, toggle`), `RibbonTint`, `Availability` (`always`, `when(_:disabledReason:)`, `unsupported(_:)`) đúng chữ ký ở `data-model.md` mục 1; ràng buộc: `Availability.unsupported` PHẢI có tooltip song ngữ không rỗng, `title.vi` và `title.en` KHÔNG rỗng, `RibbonItemSpec.note: String?` PHẢI không rỗng khi `observed == false` (nơi ghi `[SUY ĐOÁN]`)
- [x] T005 [P] Tạo `Sources/BIPro/Shell/Ribbon/RibbonCommandID.swift`: enum `RibbonCommandID: String, CaseIterable` chứa MỌI ID ở `contracts/ribbon-catalog.md` (camelCase của EN; lệnh xuất hiện nhiều tab dùng chung một ID)
- [x] T006 Tạo `Sources/BIPro/Shell/Ribbon/RibbonContext.swift`: struct bất biến `RibbonContext` (các trường ở `data-model.md`) và `init(state: DocumentState)` dựng từ trạng thái hiện có (`mode`, `workspace.metadata`, `editMode`, `canEditCanvas`, `layout.selection`, `visual`, `table`, `column`, `measure`, `layout.hasClipboard`, `pages.count`) (phụ thuộc T004)
- [x] T007 Tạo `Sources/BIPro/Shell/Ribbon/RibbonActions.swift`: `RibbonActions.perform(_ id: RibbonCommandID, state: DocumentState)` ánh xạ ID → hàm `DocumentState`/`layout` HIỆN CÓ (`showGetData`, `showEnterData`, `showQueryEditor`, `startRefreshAll`, `layout.paste/cut/copy`, `beginFormatPainter/cancelFormatPainter`, `insertVisual`, `insertShape`, `addPage`, `pickAndInsertImage`, `beginNewMeasure`, `beginNewColumn`, `beginNewTable`, `showManageRolesSheet`, `showViewAsRoleSheet`, `showQuickMeasureSheet`, `align`, `groupSelection`, `ungroupSelection`, `mergeSelection`, `mode = .model`…) và `.noop` cho nút `X`/`P`; KHÔNG đổi thân các hàm đó (phụ thuộc T005)
- [x] T008 Tạo `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift`: `RibbonCatalog.tabs(mode:visualSelected:) -> [RibbonTabID]` đúng bảng tab theo view, `RibbonCatalog.spec(for:mode:) -> RibbonTabSpec?`, hàm gộp các `Catalog+*.swift` (tạm trả `nil` cho tab chưa có catalog) (phụ thuộc T004, T005)
- [x] T009 [P] Thêm vào `Sources/BIPro/DesignSystem/Tokens.swift`: `enum UIMetrics` đúng bảng ở `contracts/ui-tokens.md` (`titleBar 36`, `tabRow 32`, `ribbonPanel 98`, `rail 42`, `railIconHit 40`, `pageTabs 35`, `statusBar 23`, `pane 181`, `collapsedPane 31`, `ribbonIcon 28`, `ribbonCorner 6`, `tabUnderline 2`) và token màu MỚI `accentTeal`, `accentTealPressed`, `canvasWell`, `tabUnderline` (sáng/tối) — **chưa** đổi `accent` và các giá trị `DS.Metrics` đang dùng
- [x] T010 [P] Thêm vào `Sources/BIPro/Settings/AppPreferences.swift` ba khoá `bipro.ribbon.collapsed` (Bool, mặc định false), `bipro.edit.viewOnlyDefault` (Bool, mặc định false), `bipro.tmdl.introSeen` (Bool, mặc định false) kèm thuộc tính có `@Observable` theo mẫu `onboardingSeen`
- [x] T011 [P] Viết test đỏ `Tests/BIProTests/UIParity/UIMetricsTests.swift` và `Tests/BIProTests/UIParity/TokensColorTests.swift`: từng token ở T009 bằng giá trị bảng (±2 pt, ±3% độ sáng); `DS.Palette.series` không đổi so với v1.2
- [x] T012 [P] Viết test `Tests/BIProTests/UIParity/RibbonAvailabilityTests.swift`: `RibbonContext` giả cho 6 tình huống (báo cáo trống, có dữ liệu chưa chọn, 1 visual, nhiều visual, chế độ chỉ xem, không có mô hình); kiểm `Availability` trả đúng bật/tắt và lý do không rỗng; kiểm `unsupported` luôn tắt
- [x] T013 [P] Viết test `Tests/BIProTests/UIParity/RibbonBilingualTests.swift`: duyệt mọi `RibbonItemSpec` trong catalog hiện có (khi có) kiểm `vi`/`en` không rỗng, `en` khớp `RibbonReference`; thêm kiểm: mọi mục `observed == false` có `note` không rỗng (FR-028); test dùng danh sách rỗng khi chưa có catalog (không đỏ)
- [x] T014 Chạy `swift build` và `swift test --no-parallel`; T011 đỏ → xanh nhờ T009; toàn bộ test v1.2 vẫn xanh; cập nhật `docs/tasks/h0-test-impact.md`

**Checkpoint:** hợp đồng H0 xong; giao diện chưa đổi; bắt đầu được mọi story.

---

## Phase 3: User Story 1 — Khung Ribbon và bộ tab (Ưu tiên: P1) 🎯 MVP

**Mục tiêu:** hàng tab, panel, kiểu nút, tab ngữ cảnh, thu gọn, nút Share và Home (Report) đi từ catalog.

**Kiểm thử độc lập:** mở `Nhom6` ở từng view, so tab/thứ tự với bảng; Home Report khớp `RibbonReference`; ảnh `build/h-out/us1/`.

### Test cho US1 (viết trước, phải đỏ)

- [x] T015 [P] [US1] `Tests/BIProTests/UIParity/RibbonTabsTests.swift`: `RibbonCatalog.tabs` cho Report (không/có chọn visual), Table, Model, DAX, TMDL đúng bảng; tab hiện tại không còn hợp lệ thì trả `.home`; tab ngữ cảnh luôn ở cuối; trạng thái thu gọn Ribbon (`ribbonCollapsed`) được ghi và đọc lại qua `AppPreferences`
- [x] T016 [P] [US1] `Tests/BIProTests/UIParity/RibbonCatalogTests.swift` (phần Home Report): so `RibbonCatalog.spec(.home, .report)` với `RibbonReference` (8 nhóm, 21 dòng, EN, kiểu, Avail loại: `oneLakeCatalog/dataverse/sensitivity/publish/prepDataForAI/copilot` là `unsupported`, `newVisualCalculation/recentSources` là chưa làm)

### Cài đặt US1

- [x] T017 [P] [US1] Tạo `Sources/BIPro/Shell/Ribbon/RibbonItemViews.swift`: bộ vẽ nút lớn (biểu tượng `UIMetrics.ribbonIcon`, nhãn tối đa 2 dòng), nút nhỏ xếp dọc tối đa 3 hàng, mũi tên ▾, hộp kiểm, ô chọn kèm nhãn, nút bật/tắt (`isOn`), thư viện ô mẫu (chỗ giữ), trạng thái vô hiệu mờ đồng nhất + `.help(lý do)`, `symbolRenderingMode(.palette)`, `accessibilityLabel`
- [x] T018 [P] [US1] Tạo `Sources/BIPro/Shell/Ribbon/Catalog+Home.swift`: Home Report (8 nhóm) theo `contracts/ribbon-catalog.md`, `Bilingual` lấy từ `bi(...)`/`L10n` hiện có, `observed: true` (phụ thuộc T004, T005)
- [x] T019 [US1] Tạo `Sources/BIPro/Shell/Ribbon/RibbonView.swift`: hàng tab (chữ thường 13 pt, tab chọn đậm + gạch chân `UIMetrics.tabUnderline` màu `accentTeal`, tab ngữ cảnh chữ `accentTeal` **không vạch phân cách**), panel trắng `UIMetrics.ribbonPanel` bo `ribbonCorner`, nhãn nhóm chữ thường xám 10 pt, vạch dọc mảnh giữa nhóm, cuộn ngang khi hẹp, nút `^` thu gọn lưu `AppPreferences.ribbonCollapsed`, nút Share vô hiệu neo phải (tooltip BI Pro chưa hỗ trợ chia sẻ); tab chưa có catalog tạm vẽ bằng view cũ qua cầu `LegacyRibbonBridge` (phụ thuộc T008, T017)
- [x] T020 [US1] Sửa `Sources/BIPro/DocumentState.swift`: `RibbonTab` thêm `file`, `design`, `optimize`; `tabs` trả theo `RibbonCatalog.tabs`; khi view đổi hoặc tab ngữ cảnh biến mất thì `ribbonTab = .home`; tab `.file` đặt `showBackstage = true` (thuộc tính mới, giao diện ở US7, tạm không vẽ gì) (phụ thuộc T008)
- [x] T021 [US1] Sửa `Sources/BIPro/Shell/Ribbon.swift`: giữ các `*Commands` cũ chỉ làm cầu `LegacyRibbonBridge` cho tab chưa có catalog; bỏ `RibbonView` cũ, trỏ `ShellView` sang `Shell/Ribbon/RibbonView.swift`; cập nhật test ở `docs/tasks/h0-test-impact.md` (`ColumnToolsRibbonTests`…) (phụ thuộc T019, T020)
- [x] T022 [US1] Sửa `Sources/BIPro/Shell/ShellView.swift` ghép `RibbonView` mới thay `RibbonView` cũ (chỉ dòng gọi; chưa đụng TitleBar/Rail)
- [x] T023 [US1] Xanh test T015, T016, `swift build`, `swift test --no-parallel`; thêm `Tests/BIProTests/UIParity/ParityRenderTests.swift` (chỉ chạy khi `BIPRO_H_RENDER=1`) xuất ảnh Home/Light/Dark vào `build/h-out/us1/`; tự mở xem ảnh không trống; thêm kiểm bề rộng: tổng bề rộng nhóm Home ở 1000 pt (cửa sổ nhỏ nhất) lớn hơn khung thì `RibbonView` cuộn ngang được, không cắt nhãn nhóm

**Checkpoint:** khung Ribbon mới chạy, Home Report đúng; tab khác tạm dùng nội dung cũ.

---

## Phase 4: User Story 2 — Nội dung Ribbon Report (Ưu tiên: P1)

**Mục tiêu:** Insert, Modeling, Design, View, Optimize, Help đúng nhóm/nút; menu thả xuống đúng.

**Kiểm thử độc lập:** `RibbonCatalogTests` cho 6 tab + bấm các nút đang chạy; ảnh `build/h-out/us2/`.

### Test cho US2

- [x] T024 [US2] Bổ sung `Tests/BIProTests/UIParity/RibbonReference.swift` các bảng Insert, Modeling, Design, View, Optimize, Help (từ `contracts/ribbon-catalog.md`) — không đụng tệp khác
- [x] T025 [US2] Mở rộng `Tests/BIProTests/UIParity/RibbonCatalogTests.swift`: so 6 tab với `RibbonReference` (tên, thứ tự, kiểu, Avail loại, `unsupported` có tooltip) (phụ thuộc T024)
- [x] T026 [P] [US2] `Tests/BIProTests/UIParity/RibbonMenusTests.swift`: Buttons ▾ (10 mục + Navigator), Shapes ▾ (nhóm Basic Shapes/Block Arrows), New page ▾ (New page + Duplicate page), Page view ▾ (Fit to page/Fit to width/Actual size), Refresh ▾ (Schema and data/Schema/Data), Themes ▾ (banner + This report + Power BI + Theme gallery): kiểm danh sách mục, mục chưa làm bị vô hiệu

### Cài đặt US2 (các tệp catalog độc lập, [P] được)

- [x] T027 [US2] Tạo `Sources/BIPro/Shell/Ribbon/RibbonMenus.swift`: nội dung menu Buttons, Shapes, New page, Page view, Refresh, More visuals (popover `VisualCatalog`); `observed: false` cho menu con Navigator
- [x] T028 [US2] `Sources/BIPro/Shell/Ribbon/Catalog+Insert.swift`: 6 nhóm Insert; Buttons/Shapes/New page/More visuals dùng `RibbonMenus` (T027, làm sau T027); nối `insertVisual`, `insertShape`, `addPage`, `pickAndInsertImage` hiện có
- [x] T029 [US2] `Sources/BIPro/Shell/Ribbon/Catalog+Modeling.swift`: 7 nhóm Modeling; `markAsDateTable` dùng `MarkAsDateTableSheet`; Page refresh/Parameters/Q&A vô hiệu có tooltip
- [x] T030 [P] [US2] `Sources/BIPro/Shell/Ribbon/Catalog+Design.swift`: Themes (thư viện 6 ô, Theme gallery, Customize/Download/Import theme), Customize page, Help; gỡ Themes khỏi tab View
- [x] T031 [P] [US2] `Sources/BIPro/Shell/Ribbon/Catalog+ViewOptimizeHelp.swift`: View (Page view ▾, Mobile layout, 3 hộp kiểm, Show panes — **bỏ** nút Data/Visualizations), Optimize (5 nút), Help (About 1.3.0 popover, Guided learning → `requestShowOnboarding`)
- [x] T032 [P] [US2] Sửa `Sources/BIPro/Panes/ThemePickerPopover.swift`: dạng menu `Themes ▾` (banner thông tin, "This report", "Power BI" 9 ô, Theme gallery) và thư viện 6 ô mẫu trên Ribbon; giữ nhập/xuất `.json` và hoàn tác như hiện nay
- [x] T033 [US2] Sửa `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift` thêm 6 catalog vào bộ gộp; bỏ cầu `LegacyRibbonBridge` cho 6 tab này (sửa `Sources/BIPro/Shell/Ribbon.swift` xoá `InsertCommands`, `ModelingCommands`, `HelpCommands`, `ReportViewCommands`)
- [x] T034 [US2] Thêm chế độ "Chế độ chỉ xem" vào menu của nút Page view (`Catalog+ViewOptimizeHelp.swift`) lưu theo ứng dụng (`AppPreferences.viewOnlyDefault`); **chỉ có hiệu lực mặc định khi spike R-02 (T052) đạt**
- [x] T035 [US2] Chạy T025, T026 xanh; `swift test --no-parallel` xanh; xuất ảnh 6 tab vào `build/h-out/us2/` và đối chiếu `docs/phase-ui-evidence/vm-ui/rb_*-2x.png`; bấm thử Get data, Enter data, New visual, Text box, Buttons ▸ Blank, Shapes ▸ Rectangle, New page, Manage roles, View as

**Checkpoint:** toàn bộ Ribbon Report đúng bảng; nút đang chạy vẫn chạy.

---

## Phase 5: User Story 3 — Tab ngữ cảnh và Ribbon Table/Model/DAX/TMDL (Ưu tiên: P1)

**Mục tiêu:** Format, Data/Drill, Table view (Home, Table tools, Column tools), Model/DAX/TMDL Home đúng; xoá `Ribbon.swift` cũ.

**Kiểm thử độc lập:** chọn visual → Format/Data-Drill; Table view chọn cột → Column tools; ảnh `build/h-out/us3/`.

### Test cho US3

- [x] T036 [US3] Bổ sung `Tests/BIProTests/UIParity/RibbonReference.swift` bảng Format, Data/Drill, Table Home, Table tools, Column tools, Model Home, DAX Home, TMDL Home
- [x] T037 [US3] Mở rộng `Tests/BIProTests/UIParity/RibbonCatalogTests.swift` cho 8 tab ngữ cảnh/view mã (phụ thuộc T036); cập nhật `Tests/BIProTests/Model/ColumnToolsRibbonTests.swift` theo catalog mới (giữ nguyên các kiểm hành vi đổi tên/định dạng/sắp xếp)

### Cài đặt US3

- [x] T038 [P] [US3] `Sources/BIPro/Shell/Ribbon/Catalog+Contextual.swift`: Format (Interactions + Arrange với Bring forward/Send backward/Selection/Align/Group▾ chứa Group/Ungroup/Merge) và Data/Drill (Show, Interactions, Drill actions, Data groups, AI); giữ hành động hiện có của `FormatCommands`/`DataDrillCommands`; Bring forward/Send backward: nối nếu `LayoutEditor` có thứ tự z, ngược lại vô hiệu có tooltip
- [x] T039 [P] [US3] `Sources/BIPro/Shell/Ribbon/Catalog+Table.swift`: Home (Table), Table tools (Name, Relationships, Calculations, Calendars), Column tools (Structure, Formatting kèm `$ % , .00` và `Auto`, Properties, Sort, Groups, Relationships, Calculations); chuyển nguyên closure của `TableToolsCommands`/`ColumnToolsCommands`/`ColumnFormatShortcut` sang `field` item (không đổi hành vi, hoàn tác `⌘Z`, lưu T2)
- [x] T040 [P] [US3] `Sources/BIPro/Shell/Ribbon/Catalog+Code.swift`: Model Home (Calculation group P, Parameters P, Q&A X), DAX Home (Clipboard, Editing: Format/Comment/Uncomment/Find/Replace/Command palette, Copilot X), TMDL Home (Clipboard gồm Copy nối hành động "Sao chép" TMDL hiện có, Editing); **Xuất TMDL** hiện có chuyển vào File ▸ Export (T070)
- [x] T041 [P] [US3] Tạo `Sources/BIPro/Query/CodeActionBar.swift`: hàng nút trên trình soạn thảo — DAX: **Run** (màu nhấn, nối `runDAXQuery`/`cancelDAXQuery`) + **Update model with changes (n)** (nối luồng `DAXUpdateModelSheet`); TMDL: **Apply** (nối `apply()` của `TMDLWorkspace`) + **Preview** (vô hiệu); thay các nút cùng chức năng vừa rời Ribbon
- [x] T042 [US3] Sửa `Sources/BIPro/Query/QueryWorkspaces.swift` gắn `CodeActionBar` vào `DAXWorkspace` và `TMDLWorkspace` (phụ thuộc T041)
- [x] T043 [US3] Sửa `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift` thêm 3 catalog vào bộ gộp; **xoá** `Sources/BIPro/Shell/Ribbon.swift` (còn lại không dùng) và `LegacyRibbonBridge`; `swift build` không cảnh báo mã chết
- [x] T044 [US3] Chạy T037 xanh; `swift test --no-parallel` + golden nặng xanh; xuất ảnh vào `build/h-out/us3/`; bấm thử Edit interactions, Align/Group, Visual table, Drill up/down, đổi tên cột, định dạng `$`, Sort by column, Run DAX, Update model, Apply TMDL, Format DAX

**Checkpoint:** toàn bộ Ribbon (12) đúng; `Ribbon.swift` cũ đã xoá; **MVP US1–US3 hoàn tất**.

---

## Phase 6: User Story 4 — Khung cửa sổ, tiêu đề, rail, màu (Ưu tiên: P2)

**Mục tiêu:** thanh tiêu đề, rail 5 biểu tượng, màu nhấn teal, canvas `#E6E6E6`, chế độ Sửa mặc định (có điều kiện).

**Kiểm thử độc lập:** ảnh cửa sổ Light/Dark; số đo qua `ShellLayoutTests`; bấm từng biểu tượng rail.

### Test cho US4

- [x] T045 [P] [US4] `Tests/BIProTests/UIParity/ShellLayoutTests.swift`: dựng `ShellView` 1600×1000 pt, đo chiều cao tiêu đề/hàng tab/panel, rộng rail (so `UIMetrics`, ±2 pt); rail luôn 5 biểu tượng kể cả không có mô hình, chọn view không có mô hình hiện đúng chuỗi trạng thái trống
- [x] T046 [P] [US4] `Tests/BIProTests/UIParity/EditModeDefaultTests.swift` (R-02): trong chế độ Sửa, cú bấm không kéo (dời < 4 pt) trên một visual PHẢI vừa chọn visual vừa áp lọc chéo (dùng `ReportInteraction`); cú kéo ≥ 4 pt PHẢI di chuyển visual và KHÔNG lọc chéo; dùng `SyntheticReport`

### Cài đặt US4

- [x] T047 [P] [US4] Tạo `Sources/BIPro/Shell/TitleBar.swift` (tách khỏi `ShellView.swift`): traffic lights, Lưu/Hoàn tác/Làm lại, tên tệp + "Last saved" kèm menu ▾, ô Search ở giữa, bánh răng Cài đặt (`openSettings`, `⌘,`), chuyển sáng/tối, Share vô hiệu; **bỏ** nút Export riêng và chuyển Export PDF/PNG/CSV vào menu File ở US7 (tạm giữ một mục menu Lưu ▾ để không mất chức năng); cao `UIMetrics.titleBar`
- [x] T048 [P] [US4] Tạo `Sources/BIPro/Shell/Rail.swift` (tách khỏi `ShellView.swift`): 5 biểu tượng rộng `UIMetrics.rail`, vạch chọn dọc 3 pt `accentTeal` + nền nhạt, tooltip bong bóng ("Report view/Table view/Model view/DAX query view/TMDL View" — EN; VI theo L10n), bỏ bánh răng đáy, bỏ `.disabled` khi chưa có mô hình: chọn Table/Model/DAX/TMDL hiện trạng thái trống song ngữ "Chưa có dữ liệu. Thêm dữ liệu để dùng chế độ này." / "No data yet. Add data to use this view." (view `EmptyViewState` mới trong `Shell/Rail.swift`), không lỗi
- [x] T049 [US4] Sửa `Sources/BIPro/Shell/ShellView.swift`: gỡ `TitleBar`, `Rail` cũ, ghép `TitleBar.swift`/`Rail.swift`; (phụ thuộc T047, T048)
- [x] T050 [US4] Sửa `Sources/BIPro/DesignSystem/Tokens.swift`: đổi `accent`, `accentHover`, `accentPressed`, `selectionSoft` sang teal (`#117865`, Tối `#3FB59B`), áp `chrome #F5F5F5`, `canvasWell`; giữ `series` và `paper*`; cập nhật các nơi dùng số cứng để dùng `UIMetrics`
- [x] T051 [P] [US4] Sửa `Sources/BIPro/Report/ReportWorkspace.swift`: nền quanh trang dùng `canvasWell`; giấy trang giữ `documentPaper`
- [x] T052 [US4] Spike R-02 trong `Sources/BIPro/Report/ReportCanvas.swift` và `Sources/BIPro/Report/Edit/EditCanvasOverlay.swift`: cho cú bấm không kéo xuyên lớp chọn xuống visual để lọc chéo; nếu T046 xanh và toàn bộ test `Interaction`/`D*Nhom6Tests` xanh → đặt `DocumentState.editMode = true` mặc định (`DocumentState.swift`) và đặt `viewOnlyDefault` làm lối thoát; nếu không → hoàn lại thay đổi, giữ mặc định cũ, ghi lý do vào `docs/tasks/h4-r02.md` và `docs/STATE.md`, báo lead (phụ thuộc T046)
- [x] T053 [US4] Chạy T045 xanh; `swift test --no-parallel` + golden nặng xanh; xuất ảnh Light/Dark mọi view vào `build/h-out/us4/` và kiểm tương phản; bấm thử 5 biểu tượng rail

**Checkpoint:** khung cửa sổ và màu đúng; quyết định chế độ Sửa đã chốt hoặc đã báo.

---

## Phase 7: User Story 5 — Pane Filters, Visualizations, Data (Ưu tiên: P2)

**Mục tiêu:** pane đúng bố cục, thứ tự, cách thu gọn.

**Kiểm thử độc lập:** mở báo cáo, chọn visual, đối chiếu `p_format.png`, `o_now.png`, `v_tmdl_2.png`.

### Test cho US5

- [x] T054 [P] [US5] `Tests/BIProTests/UIParity/PaneParityTests.swift`: Filters thu gọn mặc định rộng `collapsedPane`; Visualizations có 3 biểu tượng tab và lưới 6 cột theo `contracts/visual-gallery.md` (ô `—` mờ + tooltip, ô có loại gọi đúng `insertVisual`); Visualizations và Data thu gọn thành dải dọc `collapsedPane` và mở lại được; tab Format có Search + Visual/General; Data ở Model/DAX/TMDL có tab Tables/Model và cây "Semantic model" với số lượng; không còn thanh trạng thái riêng của pane

### Cài đặt US5

- [x] T055 [P] [US5] Sửa `Sources/BIPro/Panes/ReportPanes.swift` (`FiltersPane`): dải dọc thu gọn (mũi tên «, biểu tượng phễu, chữ xoay 90°), mở khi bấm hoặc chọn visual; (`VisualizationsPane`): tiêu đề + `»`, nhãn "Build visual", hàng 3 biểu tượng (Build, Format, Analytics → `AnalyticsPane`), lưới 6 cột theo `contracts/visual-gallery.md` (ô chưa hỗ trợ mờ + tooltip), Drill through ở cuối; khi thu gọn bằng `»` thành dải dọc `collapsedPane` (chữ "Visualizations" xoay dọc, mũi tên «, bấm để mở lại); bỏ chân trạng thái pane
- [x] T056 [P] [US5] Sửa `Sources/BIPro/Panes/BuildWells.swift`: well khung viền nét đứt, nhãn "Add data fields here", ô trường đã có `▾` `×`
- [x] T057 [P] [US5] Sửa `Sources/BIPro/Panes/FormatPane.swift`: ô Search, tab Visual/General, thẻ gập có `›` và công tắc On/Off bên phải khi áp dụng
- [x] T058 [P] [US5] Sửa `Sources/BIPro/Panes/DataPane.swift` và `Sources/BIPro/Panes/ModelTree.swift`: ô tích `accentTeal` cho trường đang dùng; tab **Tables/Model** ở Model/DAX/TMDL view, tab Model hiện cây "Semantic model" (Calculation groups, Cultures, Expressions, Functions, Measures, Perspectives, Relationships, Roles, Tables kèm số lượng từ metadata hiện có); bỏ chân "11 tables · 168 measures"; khi thu gọn bằng `»` thành dải dọc `collapsedPane` (chữ "Data" xoay dọc, mũi tên «, bấm để mở lại)
- [x] T059 [US5] Sửa `Sources/BIPro/DocumentState.swift`: thêm `filtersCollapsed: Bool` (theo cửa sổ, không lưu) và độ rộng pane mặc định `UIMetrics.pane`, kéo được đến 320 pt (phụ thuộc T055)
- [x] T060 [US5] Chạy T054 xanh; `swift test --no-parallel` xanh; xuất ảnh pane Light/Dark vào `build/h-out/us5/`; bấm thử kéo trường vào well, tích trường, đổi định dạng

**Checkpoint:** pane giống Desktop; chức năng kéo thả/format không hồi quy.

---

## Phase 8: User Story 6 — Thanh trang và thanh trạng thái (Ưu tiên: P2)

**Mục tiêu:** thanh trang và thanh trạng thái toàn cửa sổ.

**Kiểm thử độc lập:** báo cáo nhiều trang, thêm/đổi trang, zoom; đối chiếu `o_now.png`, `t_colsel.png`.

### Test cho US6

- [x] T061 [P] [US6] `Tests/BIProTests/UIParity/StatusLineTests.swift`: `StatusLine.text(mode:state)` → "Page n of m", "Table: … (n rows) Column: … (n distinct values)", "Query n of m", "Script n of m"; zoom `− ─ + n%` bắt đầu/kết thúc đúng giới hạn 25%–400%

### Cài đặt US6

- [x] T062 [US6] Sửa `Sources/BIPro/Report/ReportWorkspace.swift` (`PageTabs`): biểu tượng Desktop/Phone (Phone vô hiệu), mũi tên ◂ ▸, tab trang chữ thường (chọn: nền trắng + gạch dưới `accentTeal`; trang ẩn: biểu tượng mắt gạch), nút `+` vuông `accentTeal`; giữ thêm/đổi tên/xoá/ẩn trang (không chung tệp với T051 → làm sau T051)
- [x] T063 [P] [US6] Tạo `Sources/BIPro/Shell/StatusBar.swift` và `Sources/BIPro/Shell/StatusLine.swift` (tách `StatusBar`/`ZoomControl` khỏi `ShellView.swift`): thanh toàn cửa sổ cao `UIMetrics.statusBar`, trái `StatusLine`, phải zoom + nút fit page; nhận nội dung theo `mode`; ở Model view có thêm nút đặt lại bố cục (nối `resetDiagramPositions()`, thay nút "Sắp xếp lại") và nút fit (nối `modelZoom = 0.6`, thay "Vừa màn hình"), zoom Model dùng `modelZoom`
- [x] T064 [US6] Sửa `Sources/BIPro/Shell/ShellView.swift`: gắn `StatusBar` mới dưới vùng làm việc và gỡ `StatusBar`/`ZoomControl` cũ ngay trong `ShellView.swift`; việc gỡ chân trạng thái cũ của `Table/TableWorkspace.swift`, `Model/ModelWorkspace.swift`, `Query/QueryWorkspaces.swift`, `Panes/*` do tác vụ sở hữu từng tệp đó làm (T055, T058, T076, T077, T078), KHÔNG sửa ở đây (phụ thuộc T063, T049)
- [x] T065 [US6] Chạy T061 xanh; `swift test --no-parallel` xanh; xuất ảnh vào `build/h-out/us6/`; bấm thử thêm/đổi tên/xoá/ẩn trang và zoom

**Checkpoint:** trang và trạng thái giống Desktop ở mọi view.

---

## Phase 9: User Story 7 — Khởi động, File, Options, báo cáo trống (Ưu tiên: P3)

**Mục tiêu:** màn hình khởi động, File backstage, hộp Options, báo cáo trống.

**Kiểm thử độc lập:** mở app không tệp; bấm File; Options and settings ▸ Options; đối chiếu hai ảnh của người dùng, `f_file.png`, `dd_options_dialog.png`.

### Test cho US7

- [x] T066 [P] [US7] `Tests/BIProTests/UIParity/StartAndBackstageTests.swift`: `StartEntry` đúng 6 thẻ (OneLake, Learn with sample data là `unsupported`); `BackstageItem` đúng thứ tự (Home, Open | Save, Save as, Share, Get data, Import, Export, Publish | Options and settings, About; Sign out ẩn); `RecentFile.exists == false` thì mục mờ và không mở; `OptionsSection` có đủ GLOBAL (15 mục) và CURRENT FILE (7 mục) ở `docs/PHASE_H_UI_PARITY.md` mục 3.10, mục chưa có tính năng `available == false`
- [x] T067 [P] [US7] Xác nhận `Tests/BIProTests/Edit/AppLaunchPolicyTests.swift` (3 kịch bản mở app) vẫn xanh sau thay đổi — thêm kiểm "mở trực tiếp không tệp hiện màn hình khởi động có cửa sổ"

### Cài đặt US7

- [x] T068 [P] [US7] Tạo `Sources/BIPro/Shell/RecentFilesList.swift`: danh sách Name/Location/Opened từ `NSDocumentController.shared.recentDocumentURLs`, tệp không tồn tại hiện mờ, bấm mở bằng luồng mở hiện có
- [x] T069 [P] [US7] Tạo `Sources/BIPro/Shell/StartScreen.swift`: rail Home/Open + Sign out(ẩn)/Options and settings/About, khối "Select a data source or start with a blank report" 6 thẻ ≈ 210×210, `RecentFilesList`, nút Filter by keyword
- [x] T070 [P] [US7] Tạo `Sources/BIPro/Shell/BackstageView.swift`: mũi tên quay lại; Home (New ▸ Blank report, Recent) · Open | Save · Save as · Share(vô hiệu) · Get data · Import(vô hiệu) · Export (PDF/PNG/CSV và **Xuất TMDL** hiện có) · Publish(vô hiệu) | Options and settings · About; bấm tab File mở view này (`state.showBackstage`)
- [x] T071 [P] [US7] Tạo `Sources/BIPro/Shell/OptionsDialog.swift`: hộp ≈ 770×600, cột GLOBAL/CURRENT FILE theo mục 3.10, nội dung Data Load (Type Detection, Background Data, Time intelligence, DAX Behavior…) nối `FileOptionsView`/`DocumentState+FileOptions.swift`, mục chưa có tính năng vô hiệu, OK (`accentTeal`)/Cancel
- [x] T072 [US7] Sửa `Sources/BIPro/Report/AddDataPanel.swift`: tiêu đề cỡ 26, dòng phụ có chữ **Data** đậm, 4 thẻ rộng ≈ 252 với nửa trên tô nhạt (xanh lục, xanh dương, vàng, xám), liên kết xanh lục; giữ nguyên hành vi 4 thẻ
- [x] T073 [US7] Sửa `Sources/BIPro/App.swift`, `Sources/BIPro/Shell/UntitledDocuments.swift`, `Sources/BIPro/Shell/ShellView.swift` hiện `StartScreen` khi chưa có tài liệu và `BackstageView` khi `showBackstage`; giữ `AppLaunchPolicy`/`DocumentOpenTracker` (phụ thuộc T068–T071)
- [x] T074 [US7] Chạy T066, T067 xanh; `swift test --no-parallel` xanh; xuất ảnh vào `build/h-out/us7/`; bấm thử mở app trực tiếp, mở lại từ Dock, mở kèm `.pbix`, File ▸ Save as, Export CSV, Options

**Checkpoint:** điểm vào và File giống Desktop; ba kịch bản mở app không hồi quy.

---

## Phase 10: User Story 8 — View DAX, TMDL, Model, Table (Ưu tiên: P3)

**Mục tiêu:** bố cục các view mã và mô hình giống Desktop.

**Kiểm thử độc lập:** vào từng view đối chiếu `v_dax_1.png`, `v_tmdl_2.png`, `v_model_1.png`, `t_colsel.png`.

### Test cho US8

- [x] T075 [P] [US8] `Tests/BIProTests/UIParity/CodeViewChromeTests.swift`: DAX có dải thông báo đóng được, Run + Update model with changes (n), khu Results trạng thái trống; TMDL có Apply/Preview, Problems (n)/Output, hộp giới thiệu lần đầu (`tmdlIntroSeen` → không hiện lại); Model có pane Properties với 3 công tắc mặc định (No / Yes / No); tab con "Query n"/"Script n"/"All tables" kèm `+`

### Cài đặt US8

- [x] T076 [P] [US8] Sửa `Sources/BIPro/Query/QueryWorkspaces.swift` và `Sources/BIPro/Query/CodeActionBar.swift`: dải thông báo DAX (đóng được, nhớ theo phiên), khu Results có hình minh hoạ trống "Your query results will show up here", tab truy vấn/ kịch bản kèm `+`, minimap tuỳ chọn; TMDL: Problems (n)/Output, hộp giới thiệu "Edit your model with TMDL" (đóng được, ghi `tmdlIntroSeen`)
- [x] T077 [P] [US8] Tạo `Sources/BIPro/Model/ModelPropertiesPanel.swift` và sửa `Sources/BIPro/Model/ModelWorkspace.swift`: pane Properties (nhóm "Cards": "Show the database in the header when applicable" No, "Show related fields when card is collapsed" Yes, "Pin related fields to top of card" No) giữa canvas và pane Data; tab dưới "All tables" + `+`
- [x] T078 [P] [US8] Sửa `Sources/BIPro/Table/TableWorkspace.swift`: giữ thanh công thức và lưới; hàng tiêu đề cột có `▾` lọc; chân trạng thái dùng `StatusLine` (T063)
- [x] T079 [US8] Chạy T075 xanh; `swift test --no-parallel` + golden nặng xanh; xuất ảnh 4 view vào `build/h-out/us8/`

**Checkpoint:** cả 8 story hoàn tất.

---

## Phase 11: Hoàn thiện và cổng nghiệm thu (H6)

**Mục đích:** hồi quy toàn bộ, a11y, song ngữ, bằng chứng, đóng gói v1.3.0.

- [x] T080 Rà song ngữ: chạy `RibbonBilingualTests` với catalog đầy đủ; thêm khoá còn thiếu ở `Sources/BIPro/Settings/L10n.swift`; chế độ Anh dùng đúng chữ Desktop (SC-006)
- [x] T081 Rà VoiceOver: mọi `RibbonItemSpec`/tab/mục rail có `accessibilityLabel`, tab chọn có `.isSelected`, nút bật/tắt báo đúng; cập nhật `Tests/BIProTests/PhaseG` nếu có bộ kiểm a11y cũ
- [x] T082 Rà Dark Mode: xuất ảnh mọi Ribbon và view ở Dark vào `build/h-out/h6/dark/`; sửa token thiếu tương phản
- [x] T083 Liệt kê mọi mục `observed == false` (`[SUY ĐOÁN]`) vào `docs/phase-ui-evidence/QUAN-SAT-H.md` kèm cách xử lý; ghi phần chưa quan sát để người dùng quyết định có chụp VM bổ sung không
- [x] T084 Nâng phiên bản lên **1.3.0**: `scripts/build-app.sh` (`CFBundleShortVersionString = 1.3.0`, `CFBundleVersion = 130`) và chuỗi About ở `Sources/BIPro/Shell/Ribbon/Catalog+ViewOptimizeHelp.swift`
- [x] T085 Chạy toàn bộ: `swift test --no-parallel` (≥ 2 478 test cũ + test mới, 100% xanh), golden nặng (124 xanh), `zsh scripts/build-app.sh release`, `codesign --verify --deep --strict "build/BI Pro.app"`; thêm test `Tests/BIProTests/UIParity/RoundTripUnchangedTests.swift` (mở `Nhom6`, không sửa, gọi luồng lưu hoặc kiểm không đánh dấu dirty/không ghi tệp, so byte tệp trước/sau) và kiểm thủ công bằng `cmp` (SC-003, SC-007)
- [x] T086 Chuẩn bị cổng Desktop: tạo `build/h-out/gate/CHECKLIST.md` và bộ ảnh cạnh nhau BI Pro ↔ Desktop cho 15 Ribbon + 6 view; chờ người dùng duyệt "giống bố cục và nhận diện" và thử 10 lệnh (SC-004, SC-005). Nếu cần chụp Desktop trên VM: chỉ khi người dùng cho phép, dùng `build/vm-tools/ui.sh` (đã che tên tài khoản), ảnh không chứa đường dẫn/tên thư mục cá nhân, tắt Desktop và xoá thư mục thử trong VM sau buổi (hiến pháp: ngoại lệ VM)
- [x] T087 Cập nhật `docs/STATE.md` (Phase H xong, bản 1.3.0, kết quả test), `docs/BIPRO_BUILD_PLAN.md` (mục Phase H), `docs/PHASE_H_UI_PARITY.md` (trạng thái), `specs/016-h-giao-dien-giong-powerbi/tasks.md` (`[x]`); chạy `/speckit-converge`; báo người dùng và chờ lệnh commit/push

---

## Phụ thuộc và thứ tự

- Phase 1 → Phase 2 (chặn tất cả) → US1 → {US2 ∥ US3} → US4 → {US5 ∥ US6} → US7 ∥ US8 → Phase 11.
- US1 chặn US2/US3 (cần `RibbonView` và `RibbonItemViews`). US2 và US3 chỉ chạm tệp catalog khác nhau; hai nơi dùng chung `RibbonCatalog.swift` (T033, T043) và `RibbonReference.swift` (T024, T036) làm **tuần tự**.
- US4 chặn US5–US8 vì đổi token (`accent`) và tách `ShellView.swift`. `ShellView.swift` bị sửa ở T022, T049, T064, T073: **không** giao song song cho hai worker.
- US6 chung tệp `Report/ReportWorkspace.swift` với T051: T062 làm sau T051.
- US7 (T068–T071 tệp mới) làm song song được; T073 sau chúng. US8 độc lập với US7 sau US4/US6.
- Mỗi story kết thúc bằng một lần xuất ảnh và `swift test --no-parallel`; nếu golden nặng vỡ → dừng, không chuyển story.

## Ví dụ chạy song song

- **Sau T003:** T004, T005, T009, T010, T011, T012, T013 (tệp khác nhau).
- **US1:** T015, T016, T017, T018 song song; T019 sau T017.
- **US2:** T027 (RibbonMenus) trước; rồi {T028, T029} ∥ {T030, T031, T032} (tệp khác nhau).
- **US3:** T038, T039, T040, T041 song song.
- **US5:** T055, T056, T057, T058 song song (tệp khác nhau).
- **US7:** T068, T069, T070, T071 song song.
- **US8:** T076, T077, T078 song song.

## Gói giao cho agy (theo `agy-delegation`)

Lead làm Phase 1–2 (hợp đồng H0, khó chia). Sau đó mỗi gói một worktree, một brief `docs/tasks/h<N>-<tên>.md` có danh sách tệp được sửa, "không sửa gì ngoài danh sách", lệnh build/test ở đầu tệp này, tiêu chí xong và `docs/tasks/h<N>-<tên>-report.md`:

| Gói | Tác vụ | Tệp được sửa (tóm tắt) | Song song với |
|---|---|---|---|
| H1-khung | T015–T023 | `Shell/Ribbon/{RibbonItemViews,RibbonView,Catalog+Home}.swift`, `DocumentState.swift`, `Shell/Ribbon.swift`, `Shell/ShellView.swift`, tests UIParity | — |
| H2-report-a | T026, T027, T028, T029 | `RibbonMenus`, `Catalog+Insert`, `Catalog+Modeling` (T027 trước T028) | H2-report-b |
| H2-report-b | T030, T031, T032, T034 | `Catalog+Design`, `Catalog+ViewOptimizeHelp`, `ThemePickerPopover` | H2-report-a |
| H3-ctx | T038, T039, T037 | `Catalog+Contextual`, `Catalog+Table`, `ColumnToolsRibbonTests` | H3-code |
| H3-code | T040, T041, T042 | `Catalog+Code`, `Query/CodeActionBar`, `Query/QueryWorkspaces` | H3-ctx |
| H4-shell | T045, T047–T051, T053 | `Shell/{TitleBar,Rail}.swift`, `ShellView.swift`, `Tokens.swift`, `ReportWorkspace.swift` | — |
| H4-r02 | T046, T052 | `ReportCanvas`, `EditCanvasOverlay`, `DocumentState.swift` | sau H4-shell |
| H4-pane | T054–T060 | `Panes/*`, `DocumentState.swift` | sau H4-shell |
| H4-bar | T061–T065 | `ReportWorkspace.swift (PageTabs)`, `Shell/StatusBar`, `ShellView.swift` | sau H4-pane |
| H5-start | T066–T074 | `Shell/{StartScreen,BackstageView,OptionsDialog,RecentFilesList}`, `AddDataPanel`, `App.swift` | H5-views |
| H5-views | T075–T079 | `Query/QueryWorkspaces`, `Model/*`, `Table/TableWorkspace` | H5-start |

Lead rà từng gói: `git diff --stat` chỉ tệp được giao, chạy build/test, xem ảnh `build/h-out/`; giao lại **một** lần nếu chưa đạt (`agy-delegation`). Cổng cuối T086–T087 do lead và người dùng.

## Chiến lược triển khai

1. **MVP = US1 + US2 + US3** (toàn bộ Ribbon, yêu cầu trọng tâm của người dùng): có thể dừng ở đây để người dùng xem.
2. Sau MVP, US4 là cầu nối (màu và khung); US5–US8 độc lập, làm theo mức ưu tiên P2 rồi P3.
3. Mỗi story: test đỏ → cài đặt → test xanh → ảnh → hồi quy (`swift test --no-parallel`, golden nặng).
4. Điểm rủi ro cần theo dõi: T052 (R-02 chế độ Sửa) và đổi `accent` (T050).
