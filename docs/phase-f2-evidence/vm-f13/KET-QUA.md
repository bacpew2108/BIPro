# Gate VM-F13 (T052): kết quả

Buổi 2026-11-19, Desktop 2.159 trên VM. Mở tệp bằng `prlctl exec explorer.exe`, kiểm bằng DAX và MDX qua ADOMD (MDX đi qua chỉ mục phân cấp `U$`).

**Đạt.** Ba tệp do test BI Pro sinh (`build/f2-out/f13/`) mở trong Desktop không lỗi.

1. `bipro-f13-sua.pbix` (`CalculatedEditTests.cotTinhToanTrongQuanHePhanCapSapXep`; sửa `Nhóm` = `MOD(Key, 3) + 10` trên tệp đã lưu):
   - tổng `Qty` theo `Nhom[Ten]` đi qua quan hệ (chỉ mục `R$` mới) bằng cách tính không qua quan hệ (`LOOKUPVALUE`): Mười 6, Mười một 6, Mười hai 5;
   - cây phân cấp `Vùng nhóm` (MDX `DESCENDANTS`) đúng dữ liệu mới: N → 10, 11; S → 12; E → 11;
   - `Nhãn` vẫn sắp theo `Nhóm`; công thức mới đúng.
2. `bipro-f13-xoa.pbix` (xoá `Nhóm`): cột không còn, không còn quan hệ, `Nhãn` không còn cột sắp xếp, phân cấp còn cấp `Vùng` (MDX đúng).
3. `bipro-f13-nhom6.pbix` (`F2CalcIndexNhom6Tests`, bản sao Nhom6, sửa `Dim_District[branch_label]`, lưu hai lần):
   - 77 dòng, 0 dòng lệch công thức mới;
   - 682 khoản vay qua quan hệ theo nhãn;
   - phân cấp `Địa lý` (MDX tầng 3) có đủ 77 lá mang nhãn mới.

Chưa so với tệp Desktop tự làm cùng thao tác qua giao diện (buổi này không bấm trong VM).

## Bổ sung 2026-11-20 (T071)
Đã bấm thử trực tiếp trong giao diện Desktop trên `bipro-f13-sua.pbix`: xoá `Sales[Nhóm]` qua **Delete from model** → hộp thoại `Delete column` (`Are you sure you want to delete 'Nhóm'?`) → bấm **Yes** cho trạng thái mô hình (cột, quan hệ, phân cấp `Vùng nhóm` còn cấp `Vùng`, `Nhãn` bỏ `SortByColumn`) khớp 100 % với `bipro-f13-xoa.pbix` của BI Pro. Ảnh đã cắt che thanh tài khoản: `p1-hop-thoai-xoa.png`, `p2-sau-khi-xoa.png`. **SC-004 ĐẠT đầy đủ.**
