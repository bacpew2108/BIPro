# Quickstart D6: kiểm nhanh

## Tự động

```
swift test                                  # gồm PBIRBookmarkPatchTests, PBIRFilterPatchTests, ReportEditsTests, Bookmark*Tests
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel \
  --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D4Nhom6|D5Nhom6|D6Nhom6|EditNhom6|BatchedSerial"
```

`D6Nhom6` chạy kịch bản trên Nhom6 (`~/Downloads/bipro-golden/Nhom6_work.pbix`, chỉ đọc): ẩn một visual, thêm bookmark, cập nhật, đổi tên, xoá bookmark có sẵn, thêm bộ lọc cấp trang, sửa bộ lọc cấp visual, hoàn tác từng bước, lưu `build/d-out/D6/Nhom6_d6.pbix`, mở lại, so bookmark, thẻ lọc, số liệu, part không đổi khớp byte.

## Thử tay trong app

1. `zsh scripts/build-app.sh`, mở bản sao Nhom6 (ngoài Downloads), ⌘E.
2. Selection pane ẩn một visual, Bookmarks pane "Thêm", đổi tên, Cập nhật, xoá; Filters pane thêm Basic cấp trang. ⌘Z từng bước; ⌘S.
3. Đóng, mở lại: bookmark và bộ lọc còn; bấm bookmark áp đúng.
4. Ở chế độ Xem: nút sửa bookmark và Filters pane mờ kèm lý do; bấm bookmark vẫn áp được và không làm app hỏi lưu khi đóng.

## Trên VM (người dùng, hoặc Claude khi được phép)

Mở `build/d-out/D6/Nhom6_d6.pbix` trong Power BI Desktop theo `CHECKLIST.md`: không báo lỗi, bookmark bấm đúng, bộ lọc đúng. Trượt thì dùng `Nhom6_d6_pre.pbix` và chia đôi như D1.

Buổi VM-D6 quan sát (trước khi code ghi): theo bảng R2 trong `research.md`, kết quả vào `docs/phase-d-evidence/vm-d6/QUAN-SAT.md`.
