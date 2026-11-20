# Bằng chứng kiểm chứng Phase G (v1.0)

Thư mục này lưu ảnh chụp kiểm chứng (cắt gọn, không chứa dữ liệu nhạy cảm) và ghi chú kiểm chứng cho 6 câu chuyện của `specs/012-g-hoan-thien-v1/spec.md`. Các tệp `.pbix` và tệp xuất nặng nằm ngoài git trong `build/g-out/`.

## Chỉ mục

- `ql-spike.md`: Kết quả spike biên dịch & chạy Quick Look `.appex` bằng `swiftc` + `codesign -s -` + `qlmanage` trên macOS 15 (T005).
- `dark-mode/`: Ảnh chụp thực tế `build/BI Pro.app` ở Sáng và Tối trên 5 workspace + Query Editor + Settings + Onboarding (SC-002).
- `export/`: Ảnh xác minh PNG 2×, PDF nhiều trang và đối chiếu CSV của `Nhom6_work.pbix` (SC-001).
- `quicklook/`: Ảnh thu nhỏ và xem trước sinh bởi `qlmanage -t` / `qlmanage -p` và `PBIXQuickLookRenderer` (SC-004).
- `voiceover-ax.md`: Kết quả kiểm tra nhãn trợ năng trên `build/BI Pro.app` (SC-005).
