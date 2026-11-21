# Quickstart kiểm chứng: Phase H

Hướng dẫn chạy và kiểm từng pha. Chi tiết hợp đồng ở [contracts/](contracts/); mô hình dữ liệu ở [data-model.md](data-model.md). Không chứa mã cài đặt.

## Chuẩn bị

```bash
swift build
swift test --no-parallel                       # toàn bộ unit test (2 478 ở v1.2, cộng test mới)
mkdir -p build/h-out
```

Tệp mẫu: `build/d-out/D15/Nhom6_d15.pbix` (4 trang, 11 bảng, 168 measure). Chỉ đọc; luôn thao tác trên bản sao trong `build/h-out/`.

## 1. Kiểm dữ liệu Ribbon (từ H0)

```bash
swift test --no-parallel --filter UIParity
```

Kỳ vọng: `RibbonCatalogTests`, `RibbonAvailabilityTests`, `RibbonBilingualTests`, `RibbonActionsTests`, `UIMetricsTests`, `TokensColorTests` đều xanh. Cổng của SC-001 và SC-002.

## 2. Kiểm hồi quy (mọi pha)

```bash
swift test --no-parallel
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel \
  --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests|V11BDAXGoldenTests"
```

Kỳ vọng: 100% xanh (SC-003). Nếu SIGBUS sau khi đổi struct dùng chung: xoá `.build` rồi build lại.

## 3. Xuất ảnh để so với Power BI Desktop (từ H1)

```bash
BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests
open build/h-out/            # ảnh Light/Dark cho 15 Ribbon + 6 view
```

So từng ảnh với `docs/phase-ui-evidence/vm-ui/rb_*-2x.png`, `o_now.png`, `v_*.png`, `p_format.png`, `f_file.png`:
- 15 Ribbon: Home, Insert, Modeling, Design, View, Optimize, Help, Format, Data/Drill (9 của Report), Table (Home/Table tools/Column tools), Model/DAX/TMDL Home.
- Báo cáo trống ↔ ảnh người dùng gửi (`AddDataPanel`).
- Màn hình khởi động ↔ ảnh 1 của người dùng.

## 4. Chạy thử bằng tay trên app (từ H4)

```bash
zsh scripts/build-app.sh                         # build/BI Pro.app
cp build/d-out/D15/Nhom6_d15.pbix build/h-out/h.pbix
open -a "$PWD/build/BI Pro.app" build/h-out/h.pbix
```

Chụp riêng cửa sổ app (xem memory `screenshot-app-window-only`): `screencapture -x -o -l <windowID>`. Danh sách kiểm:

1. Hàng tab: đúng tab theo view, tab ngữ cảnh khi chọn visual, nút `^` thu gọn nhớ sau khi mở lại.
2. Bấm từng nút đang chạy được ở Home/Insert/Modeling (Get data, Enter data, Refresh, New visual, Text box, New measure, Quick measure, Manage roles, View as, Align/Group, Cut/Copy/Paste, Format painter) → đúng hành vi như v1.2, hoàn tác `⌘Z` được.
3. Nút vô hiệu (Copilot, Publish, Dataverse…) rê chuột → tooltip nêu lý do.
4. Chuyển Light/Dark (nút ở thanh tiêu đề) và Việt/Anh (Cài đặt `⌘,`) → không mất tương phản, nhãn đúng chữ Desktop ở chế độ Anh.
5. Rail 5 biểu tượng, Filters thu gọn, thanh trang, thanh trạng thái theo từng view.
6. File: Home/Open/Save/Save as/Get data/Export/Options and settings/About.
7. Mở app không tệp → màn hình khởi động; báo cáo trống → "Add data to your report".
8. Mở tệp rồi lưu: byte `.pbix` giống trước khi sửa giao diện (kiểm bằng `cmp` trên tệp không thay đổi nội dung).

## 5. Cổng Desktop (H6)

1. Chuẩn bị `build/h-out/gate/CHECKLIST.md` và bản `.pbix` mẫu.
2. Người dùng (hoặc agent khi được phép) mở cùng tệp trong Power BI Desktop 2.159 trên VM, chụp ảnh đã che tài khoản vào `docs/phase-ui-evidence/vm-ui2-gate/`.
3. Đặt ảnh BI Pro cạnh ảnh Desktop cho từng tab/view; người dùng duyệt "giống bố cục và nhận diện" (SC-005) và thử 10 lệnh (SC-004).
4. Dựng `build/BI Pro.app` v1.3.0 và kiểm `codesign --verify --deep --strict "build/BI Pro.app"` (SC-007).
