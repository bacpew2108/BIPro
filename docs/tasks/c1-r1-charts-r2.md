Bạn tiếp tục gói R1 (biểu đồ trục XY) của repo Swift "BI Pro" trong worktree này. Các file chưa commit trong `Sources/BIPro/Visuals/Charts/` và `Tests/BIProTests/Charts/` là của bạn từ lần trước. **Giữ chúng và sửa tiếp**, đừng viết lại từ đầu.

Mô tả việc ban đầu vẫn có hiệu lực, gồm danh sách file được sửa, hợp đồng và hành vi. Lead đã review và yêu cầu sửa các điểm sau.

## Phải sửa

1. **Ảnh xuất ra bị hỏng.** Trong `build/c-out/visuals/*.png`, cả vùng biểu đồ là biểu tượng cấm màu vàng/đỏ. Nguyên nhân: `ImageRenderer` không vẽ được `NSViewRepresentable` (`RightClickDetector`) và lớp phủ tương tác.
   - Thêm tham số `interactive: Bool = true` vào `CartesianChartView.init(data:kind:context:interactive:)`.
   - Khi `false`: không gắn `RightClickDetector`, không gắn `chartOverlay`/hover, không gắn view AppKit nào.
   - Test xuất ảnh dùng `interactive: false`.
   - Kiểm tra: 6 file PNG phải **khác dung lượng nhau**, xem bằng `wc -c build/c-out/visuals/*.png`. Hiện `barNPLByAge.png`, `barNPLByAgeWithHighlights.png` và `lineMonthlyAmount.png` cùng 43910 byte, nghĩa là chỉ có hình biểu tượng cấm.
   - Nếu công cụ xem file của bạn mở được ảnh thì mở từng ảnh, xác nhận thấy cột/đường/trục, và ghi mô tả ngắn vào báo cáo.
2. **Legend đè lên nhãn trục.** Ở `comboLoansByYear.png` và `stackedComplaintsByChannel.png`, nhãn vạch trên cùng của trục Y ("$40M", "2.0K") bị legend che.
   - Legend phải nằm trong vùng riêng, phía trên hoặc dưới vùng vẽ theo `legend.position`.
   - Vùng vẽ có khoảng đệm trên đủ cho nhãn vạch trên cùng.
3. **Đường trục Y2 của combo:** kiểm tra nhãn Y2 nằm bên phải, không bị cắt mép. Ví dụ "200" ở mép phải trong ảnh cũ bị cắt.

## Không đổi

- API công khai.
- Các test đang xanh.
- Phạm vi file: chỉ `Sources/BIPro/Visuals/Charts/**` và `Tests/BIProTests/Charts/**`.

## Lệnh build/test

```
swift build --scratch-path .build-wR1
swift test --scratch-path .build-wR1 --filter BIProTests
```

## Tiêu chí xong

- Hai lệnh xanh.
- 6 ảnh PNG khác dung lượng nhau và hiện đúng biểu đồ.
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
