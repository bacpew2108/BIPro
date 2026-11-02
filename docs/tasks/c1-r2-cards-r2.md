Bạn tiếp tục gói R2 (card, slicer, matrix) của repo Swift "BI Pro" trong worktree này. Các file chưa commit trong `Sources/BIPro/Visuals/{Cards,Slicer,Matrix}/` và `Tests/BIProTests/{Card,Slicer,Matrix}/` là của bạn từ lần trước. **Giữ chúng và sửa tiếp**, đừng viết lại từ đầu.

Lead đã review:
- card, card Δ và slicer đóng: đẹp, đúng như Power BI;
- 81 test xanh.

Còn phải sửa các điểm sau.

## Phải sửa

1. **Ảnh matrix trắng trơn** (`build/c-out/visuals/matrixAgeByRegion.png`). Nguyên nhân: `ImageRenderer` không vẽ nội dung bên trong `ScrollView`.
   - Thêm tham số `scrollable: Bool = true` vào `MatrixVisualView.init(data:context:scrollable:)`.
   - Khi `false`: vẽ đúng lưới đó (tiêu đề, ô, gradient, Total) nhưng không bọc `ScrollView`.
   - Tách phần lưới thành một view con dùng chung cho cả hai chế độ, để không lặp code.
   - Test xuất ảnh dùng `scrollable: false`. Ảnh phải thấy đủ:
     - tiêu đề "Nhóm tuổi", "Vùng" và ⊞;
     - 5 dòng tuổi và dòng Total đậm;
     - nền gradient xanh lá;
     - dòng Total không tô nền.
   - Kiểm tra dung lượng ảnh bằng `wc -c`; ảnh trắng hiện chỉ khoảng 20 KB. Nếu công cụ xem file của bạn mở được ảnh thì mở xem và mô tả ngắn trong báo cáo.
2. **Không dùng API riêng (private) của Apple:** bỏ `view.window?.value(forKey: "_popover")` trong `DropdownSlicer.swift`.
   - Chỉ giữ MỘT cơ chế mở danh sách, dùng API công khai:
     - hoặc `NSPopover` tự quản lý, với `appearance = NSAppearance(named: .aqua)`;
     - hoặc `.popover` của SwiftUI, với nội dung có `.environment(\.colorScheme, .light)` và nền trắng.
   - Bỏ cơ chế còn lại.
3. **Card không tự tô nền:** bỏ `.background(Color.white)` trong `CardVisualView`. Container của report đã vẽ nền (có màu và độ trong suốt riêng). Ảnh xuất có thể đặt nền trắng ở phía test.

## Không đổi

- API công khai.
- Các test đang xanh.
- Phạm vi file: chỉ `Sources/BIPro/Visuals/{Cards,Slicer,Matrix}/**` và `Tests/BIProTests/{Card,Slicer,Matrix}/**`.

Ghi chú: phần "hợp đồng thiếu" bạn nêu (formatString cho SlicerNode, measure trên cột) lead đã nhận, bạn **không** sửa hợp đồng.

## Lệnh build/test

```
swift build --scratch-path .build-wR2
swift test --scratch-path .build-wR2 --filter BIProTests
```

## Tiêu chí xong

- Hai lệnh xanh.
- Ảnh matrix thấy đủ lưới.
- Không còn `value(forKey:` trong code.
- In:
  - danh sách file đã sửa ở lần này;
  - kết quả hai lệnh;
  - kết quả `wc -c build/c-out/visuals/*.png`.

## Lệnh shell được phép

Chỉ dùng: swift build, swift test, git status/diff/log/show/grep, cmp, ls, cat, grep, rg, head, tail, wc, pwd, find, sed -n, sort, uniq, echo, file.

## LƯU Ý VỀ LỆNH SHELL (đọc kỹ)

Lần trước, phiên của worker bị dừng giữa chừng vì gọi một lệnh **không có trong danh sách** (`git grep`, `cmp`). Hai lệnh này nay đã được cho phép, nhưng quy tắc vẫn giữ nguyên: **chỉ** dùng các lệnh trong danh sách cho phép ở cuối mô tả việc.

- Không dùng: `rm`, `mv`, `cp`, `mkdir`, `diff`, `python`, `swift run`, `open`, `xcrun`, `cd`.
- Không ghép lệnh bằng `&&`, `;`, `|`.
- Chạy mọi lệnh từ thư mục gốc của worktree.
- Tìm trong code bằng `grep -rn` hoặc `rg`.
- Đọc và sửa file bằng công cụ đọc/sửa file, không dùng lệnh shell.
