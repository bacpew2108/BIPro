# Kế hoạch triển khai: Phase G — Hoàn thiện ứng dụng (v1.0)

**Nhánh**: `main` | **Ngày**: 2026-11-21 | **Spec**: `specs/012-g-hoan-thien-v1/spec.md`

**Đầu vào**: `spec.md` đã duyệt 2026-11-21 (6 câu chuyện: Export PDF/PNG/CSV, Dark Mode & Settings, Song ngữ Việt/Anh, Quick Look `.pbix`, VoiceOver, App Icon + Onboarding + v1.0).

## Tóm tắt

Hoàn thiện ứng dụng **BI Pro** đạt mốc **v1.0** thuần native macOS 15, không thêm thư viện ngoài. Chia thành 7 giai đoạn gọn gàng, kiểm chứng độc lập từng câu chuyện bằng test tự động (Swift Testing) và kiểm trực quan (ảnh chụp Sáng/Tối, PDF/PNG/CSV xuất ra `build/g-out/`, `qlmanage`, Accessibility check, `build/BI Pro.app`).

Thứ tự triển khai theo phụ thuộc:
1. **Đợt 0 (Nền & Spike)**: chốt `AppPreferences`, `L10n` khung, màu động `DS.Palette`, spike Quick Look `.appex` không cần Xcode (`qlmanage`), tạo `docs/phase-g-evidence/` và `docs/phase-g-ownership.tsv`.
2. **US2 (P1) — Dark Mode & Settings (`⌘,`)**: mở khoá nút bánh răng ở Rail + `Settings` scene, áp màu động cho toàn bộ 5 workspace + các sheet + AppKit bridge, giữ nguyên nền tài liệu trên Report Canvas.
3. **US1 (P1) — Export PDF / PNG / CSV**: bộ xuất dữ liệu CSV từ `DataView` (UTF-8 BOM, RFC 4180), bộ kết xuất trang báo cáo ra PNG (1×/2×) và PDF nhiều trang không dính khung chọn Sửa, nối menu `Xuất` trên Title bar, menu `Tệp ▸ Xuất` và menu chuột phải visual.
4. **US3 (P2) — Song ngữ Tiếng Việt & English**: điền đầy đủ từ điển `L10n` cho Shell, Ribbon, Rail, Panes, Settings, Onboarding, các hộp thoại chính và nhãn phép gộp ngầm; test kiểm tra phủ 100% khoá dịch và bất biến tệp `.pbix`.
5. **US4 (P2) — Quick Look cho `.pbix`**: `PBIXQuickLookSummary` đọc nhanh `< 1 s` trong `PBIXKit`, vẽ Preview & Thumbnail, tích hợp đóng gói `.appex` vào `scripts/build-app.sh` và kiểm bằng `qlmanage -t` / `qlmanage -p`.
6. **US5 (P2) — VoiceOver & Trợ năng**: `VisualAccessibilitySummary`, gắn nhãn trợ năng toàn bộ điều khiển biểu tượng/cây dữ liệu/visual, và `AccessibilityAnnouncer` phát thông báo khi đổi trang/lưu/xuất.
7. **US6 (P3) — App Icon, Onboarding & Đóng gói v1.0 + Hoàn thiện**: script native `scripts/make-icon.swift` + `iconutil` tạo `AppIcon.icns`, `OnboardingView` 3 bước lần đầu, nâng bản `1.0.0` trong `scripts/build-app.sh`, chụp ảnh kiểm tra Sáng/Tối, chạy toàn bộ bộ test + golden nặng + review.

## Bối cảnh kỹ thuật

- **Ngôn ngữ / nền tảng**: Swift 6 (SwiftPM, `BIPro` target đang dùng Swift 5 language mode, `PBIXKit` Swift 6), macOS 15+ Apple Silicon.
- **Phụ thuộc**: chỉ framework Apple (`SwiftUI`, `AppKit`, `PDFKit`, `CoreGraphics`, `UniformTypeIdentifiers`, `QuickLookUI`, `QuickLookThumbnailing`). Không thêm package ngoài.
- **Lưu trữ**: `UserDefaults` cho `AppPreferences`; đọc `.pbix` chỉ-đọc trong Quick Look; xuất tệp qua `NSSavePanel` (hoặc hàm thuần ghi `Data` để test tự động).
- **Kiểm thử**: `swift build`, `swift test`, golden nặng `BIPRO_HEAVY=1 swift test -c release ... --filter "Nhom6|ORA|VIS|PhaseG"`, `zsh scripts/build-app.sh`, `qlmanage -t/-p`, chụp cửa sổ app thật ở Sáng và Tối.
- **Mục tiêu hiệu năng**:
  - `PBIXQuickLookSummary.load` trên `Nhom6_work.pbix`: `< 1 s` (release).
  - Xuất PNG 2× một trang Nhom6: `< 3 s` (sau khi dữ liệu sẵn sàng).
  - Không làm chậm lưu T1/T2/T3 hay truy vấn DAX.

## Kiểm theo hiến pháp

| Nguyên tắc | Kiểm | Kết quả |
|---|---|---|
| I. Quan sát trước, không dịch ngược | Đối chiếu hành vi Export PDF/CSV của Power BI Desktop (bỏ trang ẩn, UTF-8 BOM, dữ liệu theo bộ lọc hiện hành) và Apple HIG macOS 15 cho Dark Mode/Quick Look/VoiceOver/Settings. Điểm suy đoán đánh dấu `[SUY ĐOÁN]`. | ĐẠT |
| II. Power BI là golden | CSV xuất từ visual Nhom6 so khớp 100% với bảng DAX golden; 30 golden DAX Phase B + 72 truy vấn visual không đổi; lưu `.pbix` ở cả Việt/Anh giữ nguyên định dạng Desktop. | ĐẠT |
| III. Native, không thư viện ngoài | Toàn bộ Export (CoreGraphics/PDFKit/SwiftUI), Dark Mode (NSColor dynamic), Quick Look (QuickLookUI/QuickLookThumbnailing), Icon (CoreGraphics + `iconutil`), VoiceOver (NSAccessibility) đều dùng API/công cụ hệ thống Apple. | ĐẠT |
| IV. Ranh giới dữ liệu và mạng | Không tải mạng, không cài công cụ ngoài. File gốc `~/Downloads` chỉ đọc; tệp xuất test vào `build/g-out/`, ảnh bằng chứng vào `docs/phase-g-evidence/`. | ĐẠT |
| V. Hợp đồng trước, mỗi file một chủ | Đợt 0 chốt `contracts/phase-g-contracts.md` và `docs/phase-g-ownership.tsv`. Các thư mục mới tách bạch (`Sources/BIPro/Settings/`, `Sources/BIPro/Export/`, `Sources/PBIXQuickLook/`). | ĐẠT |

## Cấu trúc dự án

### Tài liệu & bằng chứng
```text
specs/012-g-hoan-thien-v1/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/phase-g-contracts.md
└── tasks.md                 # bước kế tiếp sau khi duyệt plan
docs/phase-g-evidence/       # ảnh chụp Sáng/Tối, kiểm chứng Quick Look, Export, VoiceOver
docs/phase-g-ownership.tsv   # Đợt 0
```

### Mã nguồn dự kiến
```text
Sources/PBIXKit/
├── QuickLookSummary.swift                    # US4: đọc nhanh tóm tắt .pbix (< 1 s)
└── QuickLookRenderer.swift                   # US4: vẽ CGImage Thumbnail & Preview (test trực tiếp qua PBIXKitTests)

Sources/BIPro/
├── Settings/
│   ├── AppPreferences.swift                  # Đợt 0 / US2: UserDefaults + appearance/language/grid/driver
│   ├── L10n.swift                            # Đợt 0 / US3: từ điển song ngữ vi/en
│   ├── SettingsView.swift                    # US2: cửa sổ Cài đặt (⌘,)
│   └── OnboardingView.swift                  # US6: hướng dẫn lần đầu 3 bước
├── Export/
│   ├── VisualCSVExporter.swift               # US1: DataView → CSV UTF-8 BOM (RFC 4180)
│   ├── ReportPageExporter.swift              # US1: kết xuất trang tĩnh → PNG (1×/2×) và PDF nhiều trang
│   └── ExportSheet.swift                     # US1: hộp chọn phạm vi PDF / tỉ lệ PNG + thanh tiến trình
├── DesignSystem/Tokens.swift                 # US2: màu động NSColor light/dark
├── Report/
│   ├── AccessibilitySummary.swift            # US5: nhãn & tóm tắt dữ liệu VoiceOver + AccessibilityAnnouncer
│   ├── ReportCanvas.swift                    # US1 (chế độ xuất tĩnh), US2 (giữ nền .pbix), US5 (nhãn visual)
│   └── LiveVisual.swift                      # US1 (menu Xuất CSV + nguồn preloaded), US5 (nhãn visual)
├── Shell/
│   ├── ShellView.swift                       # US1 (nối nút Xuất), US2 (nối nút Cài đặt + bỏ ép .light), US3, US5
│   └── Ribbon.swift                          # US3 (song ngữ), US5 (nhãn trợ năng)
├── App.swift                                 # US2 (Settings scene ⌘,), US6 (Onboarding trigger)
└── Table/, Model/, Query/, Panes/            # US2 (bỏ ép .light/.aqua), US3 (chuỗi UI chính), US5 (trợ năng)

Sources/PBIXQuickLook/                        # US4: entry point extension Preview + Thumbnail (đóng gói bởi build-app.sh)
├── PreviewViewController.swift
└── ThumbnailProvider.swift

scripts/
├── make-icon.swift                           # US6: sinh .iconset → AppIcon.icns bằng CoreGraphics + iconutil
└── build-app.sh                              # US4 (đóng gói .appex), US6 (AppIcon.icns + version 1.0.0)

Tests/
├── PBIXKitTests/QuickLookSummaryTests.swift  # US4: tốc độ & cấu trúc trên Nhom6, w8.3, file hỏng
└── BIProTests/PhaseG/
    ├── AppPreferencesTests.swift             # US2
    ├── ExportCSVTests.swift                  # US1 (gồm test nặng so khớp DAX trên Nhom6)
    ├── ExportRenderTests.swift               # US1 (PNG/PDF hợp lệ, số trang, kích thước)
    ├── LocalizationTests.swift               # US3 (100% khoá vi/en đầy đủ, bất biến .pbix)
    └── AccessibilitySummaryTests.swift       # US5
```

## Phương án thực hiện & Rủi ro

- **Thực hiện trực tiếp (không giao việc `agy` song song, theo `claude.md`)**: triển khai tuần tự từng giai đoạn từ Đợt 0 đến US6 bằng `/tdd`, kiểm độc lập sau mỗi câu chuyện (test tự động + kiểm trực quan `build/g-out/` và `docs/phase-g-evidence/`), kết thúc bằng `/code-review` và `/speckit-converge`. Không tự commit hay push.
- **Rủi ro chính & giảm thiểu**:
  1. **Quick Look `.appex` ký ad-hoc trên macOS 15**: kiểm chứng bằng spike ngay ở Đợt 0 với `qlmanage -t` và `qlmanage -p`. Nếu Finder yêu cầu Developer ID để kích hoạt nền trong khi `qlmanage` chạy bình thường, tách rõ: (a) bộ vẽ `QuickLookRenderer` + `PBIXQuickLookSummary` có unit test đầy đủ, (b) `.appex` đóng gói chuẩn Apple trong `BI Pro.app/Contents/PlugIns/` kèm ghi chú ký phân phối.
  2. **Xuất PDF/PNG chứa visual có `NSViewRepresentable` (hover overlay)**: ở chế độ xuất tĩnh (`exporting: true`), tắt toàn bộ lớp hover AppKit và điều khiển tương tác để `ImageRenderer` kết xuất thuần SwiftUI 100%, kiểm thực tế bằng ảnh xuất từ `Nhom6_work.pbix` trang D1.
  3. **Sót màu sáng cứng ở Dark Mode**: sau khi đổi `DS.Palette`, grep toàn bộ `Color.white`, `Color(hex:`, `.colorScheme`, `NSAppearance` trong `Sources/BIPro/` và chụp ảnh cả 5 workspace + Query Editor ở Dark Mode để rà bằng mắt.
  4. **Ảnh hưởng test cũ khi đổi ngôn ngữ / mặc định**: `AppPreferences` mặc định `.vi` và `.system`, mọi test hiện có chạy với mặc định `.vi` nên 0 test cũ bị vỡ; mọi test cài đặt dùng `UserDefaults(suiteName:)` riêng.
