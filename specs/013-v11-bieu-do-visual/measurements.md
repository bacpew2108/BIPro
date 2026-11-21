# Số đo kiểm chứng: Đợt 2 (v1.1a) — Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn

Ngày đo: 2026-11-21 | Spec: `specs/013-v11-bieu-do-visual/spec.md` | Nhánh: `main`

## 1. Kết quả cổng Power BI Desktop 2.159 trên VM Windows 11 (SC-001 / T023)

- **Tệp cổng:** `build/v11-out/bipro-v11a-gate.pbix` (bản sao `Nhom6_work.pbix` + trang mới `v1.1a Gate` chứa 19 visual mới đủ 4 nhóm 2A–2D, sinh bởi `BIPRO_V11A_GATE=1 swift test --filter V11AGatePBIXTests` trong 2,15 s).
- **Kết quả mở trên Power BI Desktop 2.159:** **ĐẠT 100%** — **0 cảnh báo hỏng tệp**, **0 lỗi trường dữ liệu**, **0 lỗi tài nguyên thiếu**.
- **Ảnh bằng chứng (đã cắt riêng vùng canvas, không chứa tài khoản):** `docs/phase-v11-evidence/vm-v11a/gate-desktop.png` (816×498 px).
- **Phát hiện thực tế nhờ cổng VM:**
  - Khi nhúng tệp ảnh `.png` vào `Report/StaticResources/RegisteredResources/` trong một tệp `.pbix` vốn chỉ có `.svg`/`.json`, OPC (`[Content_Types].xml`) cần bổ sung `<Default Extension="png" ContentType="" />`, nếu không Power BI Desktop không đọc được phần ảnh đó. Đã vá gốc tại `PBIXWriter.addingMissingExtensions(_:to:)` + test hồi quy trong `PBIRNewVisualV11Tests`, và xác minh ảnh PNG 48×48 hiện sắc nét trên Desktop.

## 2. Kết quả kiểm thử tự động (T024)

| Hạng mục | Lệnh chạy | Kết quả | Thời gian |
|---|---|---|---|
| Toàn bộ unit test & QA (debug) | `swift test --no-parallel` | **2 444 / 2 444 qua (0 lỗi)** | 192 s |
| Bộ golden nặng release (`Nhom6`, `ORA`, `VIS`, `Phase G`, `D4Nhom6`) | `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6\|ORA\|VIS\|ExportCSVTests\|ExportRenderTests\|QuickLookSummaryTests"` | **112 / 112 qua (0 lỗi)** | ~165 s |
| Hồi quy vẽ ảnh PNG 24+ renderer (12 Cartesian + 12 v1.1a + 5 đặc biệt + Card/Slicer/Matrix) | `VisualRegressionAndBilingualQATests` | **Qua 100%**, mọi ảnh hợp lệ PNG & đủ sắc độ | < 1 s |
| Truy vấn DAX thật cho `tableEx`, `scatterChart`, `gauge`, `kpi`, `multiRowCard` | `NewVisualQueryTests` (chạy trên `DAXEngine` thật) | **5 / 5 qua** | < 0,3 s |
| Xuất CSV RFC 4180 + UTF-8 BOM cho 5 `DataView` mới | `ExportCSVTests` | **Qua 100%** | < 0,1 s |
| VoiceOver song ngữ Việt/Anh cho tất cả visual mới | `AccessibilitySummaryTests` | **Qua 100%** | < 0,01 s |

## 3. Phạm vi phủ loại visual sau Đợt 2 (v1.1a)

- `VisualTypes.supported`: tăng từ **21 → 40 loại** (+19 loại mới).
- `VisualContentView.liveTypes`: tăng từ **22 → 34 loại** visual dữ liệu vẽ số thật qua `DAXEngine`, cộng 6 loại phần tử tĩnh/điều hướng (`textbox`, `image`, `shape`, `actionButton`, `pageNavigator`, `bookmarkNavigator`).
- Mọi tính năng mới 100% native macOS Swift/SwiftUI/AppKit (0 thư viện ngoài, 0 gọi mạng — kể cả `OfflineGeoAtlas` & `GeoMapView`).
