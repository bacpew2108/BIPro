# VM-D8b: mở file BI Pro ghi trong Power BI Desktop (2026-11-13)

Bạn cho phép điều khiển VM ("có thể dùng VM"). Chỉ mở file và đọc giao diện (không sửa, không lưu). File: `build/d-out/D8/Nhom6_d8.pbix`, sinh bởi test nặng `Tests/BIProTests/Edit/D8Nhom6Tests.swift` (`BIPRO_HEAVY=1`, lọc `D8Nhom6`) từ `Nhom6_work.pbix`. Desktop mở được, không báo lỗi, không đòi sửa file.

| Phần BI Pro ghi | Kết quả ở Desktop |
|---|---|
| `cardVisual` mới ở d3_cskh (ô `Data` = `Net_Cashflow`, có `active`, `sortDefinition`) | Hiện thẻ `Net_Cashflow $252K` |
| Bộ lọc Advanced cấp trang trên `Fact_Transaction[amount]` (cột double): `> 5` và `<= 90`, toán hạng `…D` | Trang mở bình thường; số thẻ mới chịu lọc (252K, khác 197M toàn bộ) |
| Nhóm lồng: Group 1 (2 visual) trong Group 2 cùng 2 visual (Merge) | Selection pane: "Group 2" gồm Slicer, Slicer, "Group 1" (mở rộng được) |
| Nhóm bookmark "D8 nhóm" (2 bookmark) | Bookmarks pane: "D8 nhóm" mở ra "D8 bookmark 1", "D8 bookmark 2" |
| Màu theo chuỗi (`dataPoint` + `selector.metadata`) trên Q1.1 d1_giaodich | Trang mở, đường hiện màu đã đặt (#E4572E) |
| Matrix `general.layout = 'Tabular'` (Q1.6) | Matrix hiện bình thường |

Chưa kiểm: ô Format của Desktop có hiện đúng giá trị mới không (chưa mở thẻ Format từng visual); cột `decimal` (tiền tệ) cho `D`/`M`.

Ghi chú điều khiển: cửa sổ Parallels có thể nằm sau cửa sổ khác và lệch toạ độ; `vm.sh` nay lấy vị trí cửa sổ thật và cần `osascript -e 'tell application "Parallels Desktop" to activate'` trước; cuộn danh sách bằng `scroll.py` (sự kiện pixel). VM đã dọn: Desktop đóng, thư mục `vmd8b` xoá.
