# Số đo nghiệm thu — Đợt 3 (v1.1b) `specs/014-v11-tinh-nang-nang-cao/`

**Ngày đo:** 2026-11-21
**Môi trường:** macOS 15 Sequoia (Apple Silicon), SwiftPM, Parallels Windows 11 + Power BI Desktop 2.159.1231.0

## 1. Tổng hợp tiêu chí thành công (`SC-001` – `SC-004`)

| Tiêu chí | Hạng mục | Kết quả | Bằng chứng / Thời lượng |
|---|---|---|---|
| **SC-001** | Cổng Power BI Desktop 2.159 VM Gate (`bipro-v11b-gate.pbix`) | ✅ **ĐẠT** | `VISIBLE_WINDOWS_COUNT: 1` (0 hộp thoại lỗi/hỏng/thiếu trường/tài nguyên); trang `v1.1b Gate` hiển thị đúng Executive Theme (`#3B5998`/`#2B947E`), Analytics Constant/Avg/Max, 2 KPI Card DAX Wave 3 (`1` & `961M`), Matrix Data Bars + CF, Date Advanced filter (`docs/phase-v11-evidence/vm-v11b/gate-desktop.png`, 3585×1505 cắt sạch canvas, 0 email) |
| **SC-002** | ~56 hàm DAX mới khớp Golden Desktop 2.159 (`dax-golden.json`) | ✅ **ĐẠT** | `V11BDAXGoldenTests`: **7/7 suite** đối chiếu 21/21 nhóm truy vấn thực trên `msmdsrv` Desktop 2.159 (`0,091 s` debug) |
| **SC-003** | One-Click Refresh (`⇧⌘R`) & Cascade Rename (DAX + PBIR + ⌘Z) | ✅ **ĐẠT** | `V11BRefreshAndRenameTests`: **3/3 qua** (`0,198 s`) — cập nhật CSV thực 300→650, giữ quan hệ/measure, lưu T3 mở lại = 650, chịu lỗi mất file giữ dữ liệu cũ; đổi tên lan truyền Measure/Column/Table + Undo 1 bước; `V11BMTransformsTests`: **3/3 qua** (`0,002 s`) |
| **SC-004** | Bộ test đầy đủ + Golden nặng Release + Đóng gói App | ✅ **ĐẠT** | `swift test --no-parallel`: **2 466/2 466 qua** (`190,26 s`); `BIPRO_HEAVY=1` release golden: **119/119 qua** (`164,56 s`); `scripts/build-app.sh release` (`195,23 s`) + `codesign --verify --deep --strict "build/BI Pro.app"` đạt |

## 2. Chi tiết các bộ test mới của Đợt 3 (v1.1b)

- `Tests/DAXEngineTests/V11BDAXGoldenTests.swift`: **7/7 qua** (`0,091 s`)
- `Tests/PBIXKitTests/V11BPBIRPatchTests.swift`: **2/2 qua** (`0,001 s`)
- `Tests/BIProTests/V11BInteractionsAndMatrixTests.swift`: **3/3 qua** (`0,063 s`)
- `Tests/BIProTests/V11BFormattingThemeAnalyticsTests.swift`: **3/3 qua** (`0,019 s`)
- `Tests/MEngineTests/V11BMTransformsTests.swift`: **3/3 qua** (`0,002 s`)
- `Tests/BIProTests/V11BRefreshAndRenameTests.swift`: **3/3 qua** (`0,198 s`)
- `Tests/BIProTests/Edit/V11BGatePBIXTests.swift` (`BIPRO_V11B_GATE=1`): **1/1 qua** (`11,28 s`, sinh `build/v11-out/bipro-v11b-gate.pbix` và xác minh round-trip)

## 3. Vệ sinh VM & Tài nguyên

- Power BI Desktop trên VM Windows 11 đã đóng hoàn toàn (`PBIDesktop` stopped).
- Thư mục tạm `C:\Temp\vm-v11b` và `C:\Temp\vm-v11b-gate` đã xoá sạch.
- Ảnh trong `docs/phase-v11-evidence/vm-v11b/` (`desktop-edit-interactions.png`, `desktop-matrix-rows-databars.png`, `gate-desktop.png`) đã cắt nghiêm ngặt vùng canvas/pane, **0 email tài khoản Microsoft**.
