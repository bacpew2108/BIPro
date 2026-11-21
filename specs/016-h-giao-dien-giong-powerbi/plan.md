# Kế hoạch kỹ thuật: v1.3 (Phase H) — Giao diện BI Pro giống Power BI Desktop

**Thư mục spec:** `specs/016-h-giao-dien-giong-powerbi/`
**Nhánh:** `main` · **Ngày lập:** 2026-11-21 · **Trạng thái:** Nháp — chờ duyệt Cổng 2/3 (`plan.md` + `data-model.md`)
**Tham chiếu:** [spec.md](spec.md) · [research.md](research.md) · [data-model.md](data-model.md) · [contracts/](contracts/) · [quickstart.md](quickstart.md) · [`docs/PHASE_H_UI_PARITY.md`](../../docs/PHASE_H_UI_PARITY.md)

## Tóm tắt

Biến toàn bộ nội dung Ribbon thành **dữ liệu** (`RibbonCatalog`: tab → nhóm → nút, kèm quy tắc bật/tắt và lý do vô hiệu), để một bộ vẽ duy nhất dựng Ribbon giống Power BI Desktop và để test đối chiếu từng tên/thứ tự/trạng thái mà không phải dựng giao diện. Nút vẫn gọi đúng các hàm hiện có của `DocumentState`, nên hành vi cũ không đổi. Quanh Ribbon, thay bảng token (màu nhấn teal, số đo khung), rồi dựng lại từng vùng: thanh tiêu đề, rail, pane, thanh trang/trạng thái, khởi động/File/Options, view DAX/TMDL/Model/Table. Không đụng engine, không đụng tầng đọc/ghi `.pbix`.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản:** Swift 6.0 (`swift-tools-version: 6.0`), macOS 15+, Apple Silicon.
**Phụ thuộc chính:** SwiftUI + AppKit (không thêm thư viện hay phông ngoài; biểu tượng là SF Symbols với `symbolRenderingMode(.palette)`).
**Lưu trữ:** không đổi `.pbix`. Tuỳ chọn mới lưu ở `UserDefaults` qua `AppPreferences` (`ribbonCollapsed`, `viewOnlyDefault`, `tmdlIntroSeen`).
**Kiểm thử:** XCTest (`swift test --no-parallel`); thêm thư mục `Tests/BIProTests/UIParity/`; golden nặng giữ nguyên làm cổng hồi quy.
**Nền tảng:** macOS 15 Sequoia.
**Loại dự án:** ứng dụng desktop SwiftUI (một target `BIPro`, các module `PBIXKit`, `ColumnStore`, `DAXEngine`, `Connectors`, `MEngine` không sửa).
**Mục tiêu hiệu năng:** chuyển tab/view Ribbon < 50 ms trên máy hiện tại; không làm chậm trang D1 (~1,04 s, `specs/001`).
**Ràng buộc:** song ngữ Việt/Anh (`bi(_:_:)`), Dark Mode (`DS.Palette`), VoiceOver, không đổi byte `.pbix`, không thêm mạng.
**Quy mô:** ≈ 15 Ribbon, ≈ 170 nút, ≈ 25 tệp nguồn sửa/thêm, ≈ 60 test mới.

Không còn mục `NEEDS CLARIFICATION`; các quyết định kỹ thuật nằm ở [research.md](research.md).

## Kiểm tra Hiến pháp (v1.2.0)

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Đạt | VM-UI và VM-UI2 (2026-11-21), bằng chứng `docs/phase-ui-evidence/`; chỗ chưa quan sát ghi `[SUY ĐOÁN]` |
| II. Power BI là chuẩn (golden) | Đạt, dạng khác | Chuẩn là ảnh và danh mục Ribbon của Desktop; số liệu không đổi, golden DAX/visual giữ làm cổng hồi quy |
| III. Native, không thư viện ngoài | Đạt | Chỉ SwiftUI/AppKit/SF Symbols; không nhúng Segoe UI |
| IV. Ranh giới dữ liệu và mạng | Đạt | Không mạng; ảnh VM đã che tài khoản; ảnh sinh ra nằm ở `build/h-out/` |
| V. Hợp đồng trước, mỗi file một chủ | Đạt | Đợt H0 chốt hợp đồng + `docs/phase-h-ownership.tsv` trước khi giao agy |
| Ràng buộc sản phẩm (màu, AI) | Đạt sau sửa | Hiến pháp nâng v1.2.0 (teal; nút AI/cloud hiện vô hiệu) theo Q1/Q4 đã duyệt 2026-11-21 |
| Ràng buộc: người dùng test VM | Đạt | Người dùng cho phép lái VM cho Phase H (ghi ở spec); cổng H6 cần người dùng duyệt ảnh |

Đánh giá lại sau thiết kế (Phase 1): không phát sinh vi phạm; bảng "Độ phức tạp" để trống.

## Cấu trúc dự án

### Tài liệu của tính năng

```text
specs/016-h-giao-dien-giong-powerbi/
├── spec.md
├── plan.md                # tệp này
├── research.md            # quyết định kỹ thuật và phương án đã loại
├── data-model.md          # RibbonCatalog, Availability, UIMetrics, UIPrefs...
├── quickstart.md          # cách chạy và kiểm từng pha
├── contracts/
│   ├── ribbon-catalog.md  # hợp đồng dữ liệu Ribbon (kiểu, ID lệnh, quy tắc)
│   └── ui-tokens.md       # số đo + màu (sáng/tối), tên token
├── checklists/requirements.md
└── tasks.md               # do /speckit-tasks tạo
```

### Mã nguồn (gốc repo)

```text
Sources/BIPro/
├── DesignSystem/
│   ├── Tokens.swift                 # sửa: accent teal, UIMetrics mới, canvasWell
│   └── Components.swift             # sửa: RibbonButton → RibbonItemViews; PageTab, Toggle xanh lục
├── Shell/
│   ├── Ribbon.swift                 # thu nhỏ dần rồi XOÁ khi H3 xong (di chuyển nội dung sang Ribbon/)
│   ├── Ribbon/                      # MỚI
│   │   ├── RibbonModel.swift        # kiểu dữ liệu (hợp đồng H0)
│   │   ├── RibbonContext.swift      # ảnh chụp trạng thái để tính bật/tắt
│   │   ├── RibbonCatalog.swift      # tổng hợp các Catalog+*.swift, tabs(for:)
│   │   ├── Catalog+Home.swift  Catalog+Insert.swift  Catalog+Modeling.swift
│   │   ├── Catalog+Design.swift  Catalog+ViewOptimizeHelp.swift
│   │   ├── Catalog+Contextual.swift # Format, Data/Drill
│   │   ├── Catalog+Table.swift      # Home/Table tools/Column tools của Table view
│   │   ├── Catalog+Code.swift       # Model, DAX, TMDL Home
│   │   ├── RibbonActions.swift      # RibbonCommandID → hàm DocumentState hiện có
│   │   ├── RibbonView.swift         # hàng tab + panel + thu gọn
│   │   └── RibbonItemViews.swift    # nút lớn/nhỏ/▾, hộp kiểm, ô chọn, thư viện theme
│   ├── TitleBar.swift  Rail.swift  StatusBar.swift   # tách khỏi ShellView.swift
│   ├── StartScreen.swift  BackstageView.swift  OptionsDialog.swift   # MỚI
│   └── ShellView.swift              # sửa: ghép khung mới
├── Panes/        ReportPanes.swift  FormatPane.swift  DataPane.swift  ThemePickerPopover.swift  # sửa
├── Report/       ReportWorkspace.swift (PageTabs)  AddDataPanel.swift  ReportCanvas.swift       # sửa
├── Query/        QueryWorkspaces.swift (khung DAX/TMDL)                                          # sửa
├── Model/        ModelWorkspace.swift (+ pane Properties)                                        # sửa
├── Table/        TableWorkspace.swift (chân trạng thái)                                          # sửa
├── Settings/     AppPreferences.swift  L10n.swift                                                # sửa
└── DocumentState*.swift             # sửa nhỏ: tabs/ribbonTab, editMode mặc định, pane thu gọn

Tests/BIProTests/UIParity/           # MỚI: RibbonCatalogTests, RibbonAvailabilityTests,
                                     #   RibbonBilingualTests, UIMetricsTests, ShellLayoutTests,
                                     #   StartAndBackstageTests, ParityRenderTests (xuất ảnh)
docs/phase-h-ownership.tsv           # MỚI (H0)
docs/tasks/h*.md                     # brief giao agy (do /speckit-tasks gợi ý, lead viết)
```

**Quyết định cấu trúc:** một target `BIPro` giữ nguyên; thêm thư mục con `Shell/Ribbon/` để mỗi tab có tệp riêng (cho phép agy làm song song sau H0 mà không giao tệp nhau). Tên tệp ở bảng trên là dự kiến; H0 xác nhận lại vị trí đúng của `PageTabs`, `StatusBar`, khung DAX/TMDL trước khi lập bảng sở hữu.

## Pha triển khai

Mỗi pha kết thúc bằng: `swift build`, `swift test --no-parallel` xanh, ảnh `build/h-out/<pha>/` được xem, `docs/STATE.md` cập nhật. Giao agy theo `agy-delegation` (worktree riêng, brief ở `docs/tasks/`).

| Pha | Nội dung | Mã yêu cầu | Phụ thuộc | Song song? |
|---|---|---|---|---|
| **H0 Hợp đồng** | Kiểu dữ liệu Ribbon, `RibbonContext`, `RibbonCommandID` + `RibbonActions` (bọc hành động hiện có), test khung, token `UIMetrics` + `DS.Palette` teal (chưa áp vào màn hình), `docs/phase-h-ownership.tsv`, bản đồ nút cũ → ID mới | nền cho UI-A, UI-F | — | Không (lead làm) |
| **H1 Khung Ribbon** | `RibbonView`/`RibbonItemViews`, hàng tab mới, panel, thu gọn, tab ngữ cảnh, nút Share; đổi `RibbonTab`/`tabs`; Home Report chuyển sang catalog làm mẫu | FR-001…004, 013 | H0 | Không |
| **H2 Nội dung Report** | Catalog Insert, Modeling, Design, View/Optimize/Help; Page view, ô chọn theme, Buttons/Shapes/New page menu | FR-005…009 | H1 | **Có**: Insert+Modeling / Design+View+Optimize+Help |
| **H3 Ngữ cảnh + mã** | Format, Data/Drill, Table view (Home, Table tools, Column tools), Model/DAX/TMDL Home; xoá `Ribbon.swift` cũ | FR-010…012, 014 | H1 | **Có**: Contextual+Table / Code |
| **H4 Khung & pane** | Thanh tiêu đề, rail, màu teal áp toàn app, canvas `#E6E6E6`, Filters thu gọn, Visualizations/Format/Data pane, thanh trang, thanh trạng thái, chế độ Sửa mặc định (xem R-02) | FR-015…023 | H1 | Một phần: (rail+tiêu đề+màu) / (pane) / (trang+trạng thái) |
| **H5 Khởi động & File** | Màn hình khởi động, File backstage, Options, báo cáo trống, DAX/TMDL/Model/Table khung | FR-024, 025 | H4 (màu, tiêu đề) | **Có**: Start+Backstage+Options / khung DAX-TMDL-Model |
| **H6 Cổng** | So ảnh Desktop ↔ BI Pro cho 15 Ribbon + 6 view; sửa lệch; `build-app.sh` v1.3.0; `codesign`; cập nhật STATE | SC-001…007 | H2–H5 | Không |

Thứ tự khuyến nghị: H0 → H1 → (H2 ∥ H3) → H4 → H5 → H6. H2 và H3 chỉ giao song song khi bảng sở hữu không giao nhau; H4 chia ba gói nhỏ để agy không cùng sửa `ShellView.swift`.

## Rủi ro và cách giảm

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| **R-02: chế độ Sửa mặc định làm mất lọc chéo khi bấm** — ở chế độ Sửa, nội dung visual không nhận chuột (`ReportCanvas`), chỉ lớp chọn nhận | Đổi mặc định theo Q2 có thể phá lọc chéo/drill | Pha H4 làm spike: cho cú bấm không kéo đi xuyên xuống visual để lọc chéo trong chế độ Sửa (giống Desktop). Nếu không an toàn trong H4, **giữ mặc định hiện tại, chuyển công tắc View/Edit vào menu View** và ghi lùi hạng mục này (không chặn H6); lead báo người dùng |
| Đổi `RibbonTab`/`tabs` làm vỡ test cũ | Test đã có (`ColumnToolsRibbonTests`, các test dùng tab) đỏ | H0 liệt kê test chạm tab; cập nhật cùng pha đổi |
| Đổi `accent` ảnh hưởng chỗ khác (focus ring, chọn văn bản, màu chọn trong canvas) | Lệch màu ngoài ý muốn | Giữ `DS.Palette.series` riêng; kiểm ảnh Light/Dark mọi view ở H4; có test token |
| Ribbon rộng hơn màn hình nhỏ (≈ 1000 pt tối thiểu của cửa sổ) | Mất nút | Cuộn ngang đã chốt (Clarifications); test đo bề rộng tối đa các nhóm |
| agy hiểu lệch "giống" | Làm thừa/thiếu | Brief nêu bảng chuẩn ở `docs/PHASE_H_UI_PARITY.md` + test catalog là cổng; lead rà ảnh từng pha |
| Phần `[CHƯA QUAN SÁT]` | Sai chi tiết nhỏ | Ghi `[SUY ĐOÁN]`; phiên VM ngắn bổ sung ở H6 nếu người dùng muốn |
| Test render ảnh chậm/không ổn định | Chậm CI cục bộ | Chỉ xuất ảnh khi `BIPRO_H_RENDER=1`; so bằng số đo, không so điểm ảnh |

## Theo dõi độ phức tạp

Không có vi phạm hiến pháp cần biện minh.
