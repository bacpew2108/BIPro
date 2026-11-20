# Spike & Kiểm chứng Quick Look `.appex` trên macOS 15 (T005, SC-004)

**Ngày đo**: 2026-11-21 | **Hệ điều hành**: macOS 15 Sequoia (Apple Silicon) | **Không dùng Xcode**.

## 1. Cách biên dịch & đóng gói trong `scripts/build-app.sh`

- Biên dịch trực tiếp bằng `swiftc -parse-as-library -application-extension -I "$BIN_DIR/Modules" -Xcc -fmodule-map-file="$BIN_DIR/CXPress9.build/module.modulemap"` liên kết trực tiếp các tệp `.o` của `PBIXKit` và `CXPress9` cùng `-lsqlite3` và `-Xlinker -e -Xlinker _NSExtensionMain`.
- Hai extension đóng gói chuẩn trong `build/BI Pro.app/Contents/PlugIns/`:
  - `PBIXQuickLook.appex` (`local.bipro.app.quicklook`, `com.apple.quicklook.preview`, `QLPreviewingController`)
  - `PBIXThumbnail.appex` (`local.bipro.app.thumbnail`, `com.apple.quicklook.thumbnail`, `QLThumbnailProvider`)
- Ký ad-hoc từ trong ra ngoài: mỗi `.appex` ký với `com.apple.security.app-sandbox = true`, sau đó ký `BI Pro.app`. `codesign --verify --deep --strict` đạt **valid on disk / satisfies its Designated Requirement**.

## 2. Kết quả kiểm chứng thực tế trên macOS 15

| Kiểm tra | Kết quả |
|---|---|
| `pluginkit -a` & `pluginkit -m -v` | Đăng ký thành công cả `local.bipro.app.quicklook(1.0.0)` và `local.bipro.app.thumbnail(1.0.0)` |
| Nhật ký hệ thống Finder (`com.apple.extensionkit:NSExtension`) | `Finder` tự động phát hiện `<EXConcreteExtension {id = local.bipro.app.quicklook}>` |
| `QLThumbnailGenerator.shared.generateBestRepresentation` trên `Nhom6_work.pbix` (54 MB) | **ĐẠT**: `com.apple.quicklook.ThumbnailsAgent` gọi trực tiếp `PBIXThumbnail.appex`, sinh ảnh 512×512 (`type = .thumbnail`, lưu tại `quicklook/qlgen-nhom6.png`) trong **0,994 giây** (`< 1,0 s`) |
| `PBIXQuickLookSummary.load` + vẽ Preview Sáng/Tối (`Nhom6_work.pbix`, bản release) | **0,463 giây** (`< 1,0 s`, SC-004); `11 Bảng · 110 Cột · 168 Measure · 14 Quan hệ`, đủ 4 trang (3 hiển thị, 1 ẩn) |
| Tệp định dạng cũ (`tuan6.2.pbix` / `w8.3.pbix`) & tệp `.pbix` hỏng | Đọc & vẽ an toàn, không sập tiến trình |

## 3. Lưu ý về `qlmanage -t` dòng lệnh vs `QLThumbnailGenerator` trên macOS 15

- Trên macOS 15, lệnh CLI cũ `qlmanage -t` khi không có sandbox token ghi nhận thông báo `No sandbox token for thumbnail request` cho extension app-sandbox hiện đại; trong khi API chuẩn của Finder là `QLThumbnailGenerator` (`com.apple.quicklook.ThumbnailsAgent`) gọi thành công `PBIXThumbnail.appex` và trả ảnh thu nhỏ thật ngay dưới 1 giây.
- Nếu phân phối ra máy khác có Gatekeeper bật chặt, cần ký bằng chứng chỉ Apple Developer ID (cấu trúc `.appex` và `Info.plist` trong `scripts/build-app.sh` đã sẵn sàng chuẩn Apple).
