# Số đo nghiệm thu — Đợt 4 (v1.2)

- **Spec:** `specs/015-v12-hoan-thien-chuyen-nghiep/`
- **Ngày đo:** 2026-11-21
- **Phiên bản ứng dụng:** BI Pro `1.2.0` (`CFBundleVersion = 120`)

## 1. Kết quả các tiêu chí thành công (`SC-001`–`SC-004`)

| Tiêu chí | Mô tả | Kết quả | Bằng chứng |
|---|---|---|---|
| **SC-001** | Cổng Power BI Desktop 2.159 trên VM Windows 11 mở `build/v12-out/bipro-v12-gate.pbix` với 0 lỗi/cảnh báo | ✅ **ĐẠT** (`VISIBLE_WINDOWS_COUNT: 1`, 0 hộp thoại lỗi; đủ 4 visual render đầy đủ dữ liệu, Format Painter viền `#118DFF` + tiêu đề, Quick Measure `V12_Clients_Pct_Total`, Card sao chép, biểu tượng lịch **Mark as Date Table** trên `Dim_Date`, vai trò RLS `V12_Midwest_Viewer` nạp sạch) | [gate-desktop.png](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/gate-desktop.png), [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/QUAN-SAT.md) |
| **SC-002** | RLS **View As** lọc chính xác số liệu DAX qua `ReportInteraction` | ✅ **ĐẠT** (Card `TotalAmt` trả `500` khi tắt View As → `250` khi bật vai trò `NorthManager` (`Sales[Region] = "North"`) → trở lại `500` khi bấm Dừng xem) | [V12FeaturesTests.swift](file:///Users/macprom114/Desktop/PowerBINative/Tests/BIProTests/V12FeaturesTests.swift) |
| **SC-003** | Mở khoá toàn bộ 18 nút Ribbon/DataPane từng bị khoá/stub, hỗ trợ song ngữ Việt/Anh & Dark Mode | ✅ **ĐẠT** (Cut/Copy/Paste + `⌘X`/`⌘C`/`⌘V`, Format Painter, Data/Drill 4 nút + `Show as a table`, Quick Measures 8 mẫu, Mark as Date Table, Manage Roles & View As, DataPane Hide/Unhide & Unhide All, DAX Format & Update Model, TMDL Apply Changes, SQL Quick Connect PostgreSQL/SQLite) | [Ribbon.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Shell/Ribbon.swift), [ShellView.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Shell/ShellView.swift) |
| **SC-004** | Bộ kiểm thử toàn diện, golden nặng release & đóng gói `build/BI Pro.app` v1.2.0 có chữ ký hợp lệ | ✅ **ĐẠT** (100% xanh, 0 lỗi, `codesign --verify --deep --strict` đạt) | Chi tiết bảng bên dưới |

## 2. Số đo kiểm thử & đóng gói

| Hạng mục | Lệnh chạy | Kết quả | Thời gian |
|---|---|---|---|
| **Unit test toàn bộ** | `swift test --no-parallel` | **2 471 / 2 471** qua (0 lỗi) | `216,72 s` |
| **Wave 4 chuyên biệt** | `V12ModelMetadataRLSTests` + `V12DAXFormatterTests` + `V12FeaturesTests` + `V12GatePBIXTests` | **5 / 5** qua (gồm tạo & round-trip `bipro-v12-gate.pbix`) | `10,4 s` |
| **Golden nặng (Release)** | `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6\|ORA\|VIS\|ExportCSVTests\|ExportRenderTests\|QuickLookSummaryTests\|V11BDAXGoldenTests"` | **119 / 119** qua (0 lỗi) | `171,46 s` |
| **Đóng gói Release `.app`** | `zsh scripts/build-app.sh release` | `build/BI Pro.app` (**v1.2.0**, `CFBundleVersion = 120`, kèm `AppIcon.icns`, `PBIXQuickLook.appex`, `PBIXThumbnail.appex`) | `208,99 s` |
| **Xác minh chữ ký số** | `codesign --verify --deep --strict "build/BI Pro.app"` | **ĐẠT** (exit code `0`) | `< 1 s` |

## 3. Vệ sinh VM & Quyền riêng tư
- Đã tắt toàn bộ tiến trình `PBIDesktop` và xoá sạch `C:\Temp\vm-v12-gate` cùng script tạm `build/vm-tools/run-v12-gate.ps1`.
- Ảnh chụp [gate-desktop.png](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/gate-desktop.png) cắt đúng vùng `0,295,3734x1637` (`y = 14.5%..95%`), loại bỏ hoàn toàn thanh tiêu đề và tài khoản Microsoft góc phải trên.
