# Phase H (H0 — T001): Tác động mã nguồn & kiểm thử của Ribbon

Ngày rà soát: 2026-11-21
Lệnh kiểm tra: `grep -rnE "RibbonTab|state\.tabs|ribbonTab|RibbonButton|RibbonGroup" Sources/BIPro Tests/BIProTests`

## 1. Tệp mã nguồn (`Sources/BIPro`)

| Tệp | Các dòng chính | Thành phần dùng | Pha sẽ sửa | Ghi chú |
|---|---|---|---|---|
| `Sources/BIPro/DocumentState.swift` | 45–82, 124, 128, 143, 443–450, 457 | `RibbonTab`, `ribbonTab`, `tabs` | Phase 3 (T020) | Thêm `file`, `design`, `optimize`; nối `tabs` sang `RibbonCatalog.tabs(mode:visualSelected:)`; thêm `showBackstage` |
| `Sources/BIPro/DocumentState+Model.swift` | 24 | `ribbonTab = .tableTools` | Không cần sửa | `.tableTools` vẫn giữ nguyên ID và hành vi ở Table view |
| `Sources/BIPro/Shell/Ribbon.swift` | 12–17, 49, 75–875 | `RibbonView`, `state.tabs`, `state.ribbonTab`, `RibbonGroup`, `RibbonButton` | Phase 3 (T021), Phase 4 (T033), Phase 5 (T043) | Thu nhỏ dần thành `LegacyRibbonBridge` rồi xoá ở T043 |
| `Sources/BIPro/Shell/ShellView.swift` | 17 | `RibbonView(state: state)` | Phase 3 (T022) | Đổi sang `RibbonView` mới trong `Shell/Ribbon/RibbonView.swift` |
| `Sources/BIPro/DesignSystem/Components.swift` | 49–123 | `RibbonButton`, `RibbonGroup`, `RibbonDivider`, `RibbonStack` | Phase 3 (T017), Phase 6 (T050) | **Giữ nguyên API đang dùng** vì `QueryRibbonView.swift` (Power Query Editor) vẫn dùng `RibbonButton`/`RibbonGroup` |
| `Sources/BIPro/Query/Editor/QueryRibbonView.swift` | 104–537 | `RibbonGroup`, `RibbonButton` (`QueryRibbonTab`) | Không sửa | Power Query Editor dùng `QueryRibbonTab` riêng, không bị ảnh hưởng bởi `RibbonTab` |
| `Sources/BIPro/Query/Editor/QueryEditorWindow.swift` | 13, 63 | `QueryRibbonTab` | Không sửa | Thuộc Power Query Editor |
| `Sources/BIPro/Query/Editor/QueryRibbonCommand.swift` | 5, 198 | `QueryRibbonTab` | Không sửa | Thuộc Power Query Editor |
| `Sources/BIPro/Settings/L10n.swift` | 79, 297 | `ribbonTableTools` (và các khoá `ribbon*`) | Phase 11 (T080) | Giữ nguyên khoá cũ, chỉ bổ sung khoá thiếu |

## 2. Tệp kiểm thử (`Tests/BIProTests`)

| Tệp | Dòng | Thành phần dùng | Pha sẽ sửa | Ghi chú |
|---|---|---|---|---|
| `Tests/BIProTests/Model/ColumnToolsRibbonTests.swift` | 105–107 | `RibbonTab.tableTools`, `.columnTools`, `state.ribbonTab`, `RibbonView(state: state)` | Phase 3 (T021 — kiểm vẫn xanh), Phase 5 (T037) | Kiểm dựng `RibbonView` với `tableTools`/`columnTools`; giữ nguyên toàn bộ kiểm hành vi đổi tên/định dạng/sắp xếp |
| `Tests/BIProTests/PhaseG/LocalizationTests.swift` | 83 | `QueryRibbonTab.transform` | Không sửa | Dùng `QueryRibbonTab`, không đụng `RibbonTab` |

## 3. Xác nhận vị trí tệp thực tế (T002)

- `PageTabs`: `Sources/BIPro/Report/ReportWorkspace.swift` (khớp `docs/phase-h-ownership.tsv`)
- `StatusBar` & `ZoomControl`: `Sources/BIPro/Shell/ShellView.swift` (khớp `docs/phase-h-ownership.tsv`)
- Khung DAX/TMDL (`DAXQueryWorkspace`, `TMDLWorkspace`): `Sources/BIPro/Query/QueryWorkspaces.swift` (khớp `docs/phase-h-ownership.tsv`)
- `TitleBar` & `Rail`: hiện ở `Sources/BIPro/Shell/ShellView.swift`, sẽ tách sang `TitleBar.swift` & `Rail.swift` ở T047–T049 (khớp `docs/phase-h-ownership.tsv`)

## 4. Kết quả kiểm chứng sau H0 (T014)

- `swift build`: `Build complete! (0.49s)` — 0 lỗi, 0 cảnh báo mới.
- T011 (`UIMetricsTests`, `TokensColorTests`): đỏ trước T009 (`cannot find 'UIMetrics'`, `no member 'accentTeal'`), xanh sau T009.
- `swift test --no-parallel --filter UIParity`: `✔ Test run with 12 tests passed after 0.052 seconds.`
- `swift test --no-parallel`: `✔ Test run with 2493 tests passed after 190.342 seconds.` (2 481 test v1.2 + 12 test UIParity mới, 100% xanh, 0 hồi quy).
