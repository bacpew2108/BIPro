# Quickstart D5: kiểm nhanh

## Tự động

```
swift test                                  # gồm PBIRPagePatchTests, Page*Tests
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel \
  --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D5Nhom6|EditNhom6|BatchedSerial"
```

`D5Nhom6` chạy kịch bản trên Nhom6 (`~/Downloads/bipro-golden/Nhom6_work.pbix`, chỉ đọc): thêm trang, đổi tên, đưa lên đầu, nhân bản D1, xoá một trang có hai bookmark trỏ tới, lưu `build/d-out/D5/Nhom6_d5.pbix`, mở lại, so thứ tự, tên, số visual, bookmark và số liệu; đo thời gian từng thao tác và lưu (SC-001, SC-003).

## Thử tay trong app

1. `zsh scripts/build-app.sh`, mở một bản sao Nhom6 (đặt ngoài Downloads), ⌘E.
2. "+" ở thanh tab: trang "Page N" trống ở cuối; thả trường vào Build pane để thấy trang mới dùng được.
3. Bấm đúp tab đổi tên; kéo tab; chuột phải: Nhân bản, Xoá (xác nhận). ⌘Z từng bước.
4. ⌘S (hoặc ⇧⌘S): `unzip -l` file mới thấy thư mục trang; tìm mã trang đã xoá trong `definition/`: không còn.

## Trên VM (người dùng, hoặc Claude khi được phép)

Mở `build/d-out/D5/Nhom6_d5.pbix` trong Power BI Desktop theo `CHECKLIST.md`: không báo lỗi, tab đúng thứ tự và tên, trang nhân bản vẽ như gốc, bookmark còn lại bấm được. Trượt thì dùng `Nhom6_d5_pre.pbix` và chia đôi như D1.
