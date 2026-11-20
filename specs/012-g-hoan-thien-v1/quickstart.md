# Hướng dẫn kiểm thử nhanh: Phase G (v1.0)

## 1. Build và test tự động

```bash
swift build
swift test --filter "AppPreferencesTests|ExportCSVTests|ExportRenderTests|LocalizationTests|AccessibilitySummaryTests|QuickLookSummaryTests"
swift test
```

## 2. Test nặng & golden hồi quy (bản release)

```bash
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|PhaseG|QuickLookSummary"
```

## 3. Đóng gói v1.0 & kiểm tra Quick Look / App Icon

```bash
zsh scripts/build-app.sh
# Kiểm tra phiên bản & icon:
defaults read "$PWD/build/BI Pro.app/Contents/Info" CFBundleShortVersionString   # 1.0.0
defaults read "$PWD/build/BI Pro.app/Contents/Info" CFBundleIconFile             # AppIcon
ls -lh "build/BI Pro.app/Contents/Resources/AppIcon.icns"

# Kiểm tra Quick Look trên file mẫu:
qlmanage -t -s 512 -o build/g-out/ql ~/Downloads/bipro-golden/Nhom6_work.pbix
qlmanage -p ~/Downloads/bipro-golden/Nhom6_work.pbix
```

## 4. Kiểm tra thủ công nhanh trong `build/BI Pro.app`

1. Xoá cờ lần đầu (nếu muốn xem lại Onboarding): `defaults delete local.bipro.app bipro.onboarding.seen`
2. Mở `build/BI Pro.app` với bản sao `Nhom6_work.pbix`:
   - Xem Onboarding 3 bước → bấm Bắt đầu.
   - Mở **Cài đặt** (`⌘,` hoặc nút bánh răng ở Rail): đổi Sáng ↔ Tối (kiểm 5 workspace, Report Canvas giữ nền trắng), đổi Tiếng Việt ↔ English.
   - Bật slicer lọc năm 2018 → bấm **Xuất ▸ PDF…**, **Ảnh PNG của trang…**, chọn 1 visual → **Dữ liệu visual ra CSV…** → mở kiểm bằng Preview & Excel/Numbers.
   - Bật VoiceOver (`⌘F5`) kiểm đọc nhãn nút Rail, Title bar và visual trên trang D1.
