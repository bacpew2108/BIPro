# Số đo & Kiểm chứng: Phase G — Hoàn thiện ứng dụng (v1.0)

**Ngày đo**: 2026-11-21 | **Cấu hình máy**: macOS 15 Sequoia, Apple Silicon.

## 1. Bộ kiểm thử tự động (SC-006)

| Bộ kiểm thử | Kết quả | Thời gian | Ghi chú |
|---|---|---|---|
| `swift test --no-parallel` (toàn bộ dự án) | **2 405 / 2 405 qua** *(18 test mới Phase G + 2 387 test sẵn có)* | ~33,7 s | 0 hồi quy |
| 7 suite mới Phase G (`AppPreferencesTests`, `LocalizationTests`, `SettingsOnboardingTests`, `ExportCSVTests`, `ExportRenderTests`, `AccessibilitySummaryTests`, `QuickLookSummaryTests`) | **18 / 18 qua** | 0,43 s (debug) | — |
| Bộ nặng release (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6\|ORA\|VIS\|ExportCSVTests\|ExportRenderTests\|QuickLookSummaryTests\|CredentialVaultTests\|CalculatedEditTests"`) | **120 / 120 qua** | 153,4 s | Đủ 30 golden DAX Phase B + 72 truy vấn visual + Phase G nặng + Keychain + CalculatedEdit |

## 2. Số đo từng tiêu chí thành công (SC-001 .. SC-006)

| Tiêu chí | Số đo thực tế | Ngưỡng mục tiêu | Kết quả |
|---|---|---|---|
| **SC-001 (Export)** | `Nhom6_work.pbix`: xuất PNG 2× trang D1 (`3840×2160`, 2,6 MB, sắc nét) + PDF 3 trang hiển thị (275 KB vectơ, đúng `1920×1080` từng trang) hết **3,047 s** (cả preload 3 trang + vẽ); xuất CSV Card (`Tiền vào = "$3,227,472,425"`), Chart (`Tháng / Giá trị GD / Số GD`), Matrix (`Giờ × Thứ`) khớp 100% `DataView` DAX, có UTF-8 BOM (`EF BB BF`) + CRLF hết **1,866 s** | PNG/PDF hợp lệ khớp thị giác; CSV khớp 100% DAX | **ĐẠT** |
| **SC-002 (Dark Mode & Settings)** | Chụp đủ 10 ảnh thực tế `build/BI Pro.app` (5 workspace × Sáng/Tối) + 4 ảnh `SettingsView` & `OnboardingView` vào `docs/phase-g-evidence/dark-mode/`; phát hiện & sửa 5 chỗ màu sáng cứng sót (`FilterCard`, `ModelWorkspace` backdrop, `QueryTabBar`, `QueryDependenciesView`, `QueryWorkspaces` error banner); Report Canvas giữ nguyên nền tài liệu `.pbix` | Không còn nền trắng chói / mất tương phản; lưu bền vững `UserDefaults` | **ĐẠT** |
| **SC-003 (Song ngữ)** | 100% khoá `L10n.Key.allCases` có đủ bản dịch `vi` và `en` không rỗng, khớp placeholder; nhãn phép gộp ngầm (`Tổng của Amount` ↔ `Sum of Amount`, `First Name`, `Earliest OrderDate`) đổi theo ngôn ngữ; `PBIRQueryPatch.apply` và `SQLiteODBC.connectionString` bất biến byte giữa `.vi` và `.en` | 100% khoá đầy đủ; bất biến `.pbix` | **ĐẠT** |
| **SC-004 (Quick Look)** | `PBIXQuickLookSummary.load` + vẽ thumbnail & preview Sáng/Tối trên `Nhom6_work.pbix` (54 MB): **0,463 s** (release); `QLThumbnailGenerator` gọi thật `PBIXThumbnail.appex` qua daemon macOS 15: **0,994 s** (`512×512`); đọc an toàn `w8.3.pbix`, `tuan6.2.pbix`, file hỏng | `< 1,0 s` (release); không sập trên file hỏng | **ĐẠT** |
| **SC-005 (VoiceOver)** | `AccessibilitySummaryTests` qua 100%; toàn bộ nút biểu tượng ở Title bar, Rail, Ribbon, Zoom, Pane collapse/expand, Selection eye, PageTabs, Visual trên canvas và `AccessibilityAnnouncer` đã gắn đủ | 100% test qua; nút chính có nhãn rõ | **ĐẠT** |
| **SC-006 (Đóng gói v1.0)** | `zsh scripts/build-app.sh release` tạo `build/BI Pro.app` phiên bản `CFBundleShortVersionString = 1.0.0`, `CFBundleIconFile = AppIcon`, `AppIcon.icns` (`1024×1024`, 1,0 MB), 2 extension `PBIXQuickLook.appex` & `PBIXThumbnail.appex`, `codesign --verify --deep --strict` **valid on disk** | Bản `1.0.0`, icon hợp lệ, 0 hồi quy | **ĐẠT** |

## 3. Hậu kiểm hoàn thiện (Phase G2)

- **Song ngữ sâu `vi`/`en`**: thêm helper `bi(_:_:)` phản ứng trực tiếp theo `AppPreferences.shared.effectiveLanguage` và Việt/Anh hoá toàn bộ chuỗi UI còn sót ở `Ribbon.swift`, `EditCommands.swift` (`statusBadge` + menu), `DataPane.swift`, `ReportPanes.swift`, `AddDataPanel.swift`, `GetDataDialog.swift` + `ConnectorCatalog.swift`, `EnterDataView.swift`, `NavigatorView/TreeView/PreviewGrid/Format`, `QueryEditorWindow/Ribbon/List/AppliedSteps/PreviewGrid/ColumnProfile/Format`, `FileOptionsView.swift`. Giữ nguyên chuỗi `.vi` mặc định để không hồi quy test cũ.
- **Dark Mode hộp thoại phụ & ảnh live Tiếng Anh**: `DialogSnapshotsTests` kết xuất 7 PNG Dark Mode + Tiếng Anh (`get-data`, `navigator`, `enter-data`, `query-editor`, `file-options`, `export-sheet-pdf`, `export-sheet-png`) vào `docs/phase-g-evidence/dark-mode/g2-dialogs/`, kiểm tự động độ sáng nền tối (`avgLum < 0.35`) và kiểm thị giác bằng mắt (đã phát hiện & sửa thêm nhãn tiếng Việt còn sót ở `PreviewGridView`/`ColumnProfileView` và cắt dòng tiêu đề nhóm `ROWS` ở `QueryRibbonView`; chuyển `FileOptionsView` và `ExportSheet` sang control thuần SwiftUI sắc nét trong Dark Mode). Ảnh live `build/BI Pro.app` Dark Mode + Tiếng Anh lưu tại `docs/phase-g-evidence/dark-mode/dark-report-en.png`.
- **VoiceOver `DataPane` & Quick Look Preview**: thêm `DataTreeAccessibility` gắn `.accessibilityLabel`/`.accessibilityValue`/`.isSelected` cho cả 6 loại nút (`Table`, `Folder`, `Column`, `Measure`, `Hierarchy`, `Level`) trong `TreeRow` (`DataPane.swift`) và kiểm thử đơn vị trong `AccessibilitySummaryTests`; bổ sung test `previewRendersMultiVisualPageLightAndDark` trong `QuickLookSummaryTests` xác minh nền Light (`> 0.80`) / Dark (`< 0.25`) và wireframe đa visual.
- **Kiểm thử & Đóng gói sau Phase G2**:
  - Suite Phase G + G2: **22 / 22 qua** (`0,974 s`).
  - Toàn bộ dự án: **2 409 / 2 409 qua** (2 399 qua trong sandbox + 10/10 `CalculatedEditTests` & `CredentialVaultTests` qua ngoài sandbox).
  - `build/BI Pro.app` v1.0.0 dựng lại sạch, `codesign --verify --deep --strict` **valid on disk**.
