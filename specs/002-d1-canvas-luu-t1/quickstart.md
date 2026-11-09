# Quickstart: kiểm D1 từ đầu đến cuối

Điều kiện: `Nhom6_work.pbix` ở `~/Downloads/bipro-golden/` hoặc biến `BIPRO_NHOM6=<đường dẫn>`.

## 1. Test tự động

```
swift build
swift test                                    # gồm PBIXKitTests, BIProTests/Edit
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|EditNhom6"
```

Kỳ vọng: không test nào trượt thêm; golden 30/30; `EditNhom6` (sửa D1, lưu vào `build/d-out/`, mở lại) qua; thời gian lưu in ra dưới 1 s.

## 2. Chạy thử trong app

```
zsh scripts/build-app.sh
open "build/BI Pro.app" --args   # rồi mở một bản sao Nhom6 ở Desktop (không phải trong Downloads)
```

1. ⌘E bật Sửa. Bấm một thẻ card: hiện khung và 8 tay nắm.
2. Kéo sang phải 40 px: x thành bội của 8. Shift-bấm thêm một thẻ rồi kéo cả hai: giữ vị trí tương đối.
3. Kéo tay nắm góc phải dưới của biểu đồ: cỡ đổi, bám lưới.
4. Delete xoá một visual; ⌘D nhân bản một card.
5. ⌘Z nhiều lần về trạng thái ban đầu: chấm "chưa lưu" mất; ⌘⇧Z làm lại.
6. ⌘S trên bản sao ở Desktop: lưu được, bản sao lưu xuất hiện ở `~/Library/Application Support/BI Pro/Backups/`.
7. Mở file ở `~/Downloads`, sửa, ⌘S: app yêu cầu Lưu thành.
8. Thoát (⌘Q) khi còn thay đổi: hỏi Lưu/Không lưu/Huỷ.
9. Mở lại file đã lưu: bố cục giống.
10. ⌘E tắt Sửa: lọc chéo/slicer vẫn chạy như trước.

## 3. Kiểm byte (không cần app)

```
unzip -t build/d-out/D1/Nhom6_d1.pbix
cmp <(unzip -p Nhom6_work.pbix DataModel | shasum) <(unzip -p build/d-out/D1/Nhom6_d1.pbix DataModel | shasum)
```

Kỳ vọng: `No errors`; hai băm DataModel giống nhau.

## 4. Bạn làm trên VM

- **VM-D1 (quan sát, trước khi plan chốt hằng số)**: trong Power BI Desktop, mở bản sao Nhom6 (hoặc `tuan6.2`), kéo/đổi cỡ/nhân bản/xoá visual, lưu thành `*-R-D1.pbix`; đưa lại để mình so `visual.json`, bookmark và `page.json` (`z`, `tabOrder`, mã, lệch khi dán, bookmark sau khi xoá). Ghi vào `docs/phase-d-evidence/`.
- **VM-D1-mở (cổng cuối)**: mở `build/d-out/D1/Nhom6_d1.pbix` trong Power BI Desktop; theo `CHECKLIST.md` cùng thư mục: mở không lỗi, 4 trang đúng, visual đã sửa đúng chỗ, bookmark Q1.3 chạy, số liệu không đổi, không đòi sửa file.
