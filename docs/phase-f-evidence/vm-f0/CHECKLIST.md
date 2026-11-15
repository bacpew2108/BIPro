# Gate F-T3 (S0, tức gate W4 của Phase W): bảng mới do BI Pro ghi, Desktop có mở không?

**Vì sao quan trọng nhất của Phase F:** quyết định BI Pro lưu bảng dữ liệu mới theo cách "đầy đủ" (T3) hay chuyển sang phương án dự phòng "Enter Data" (dữ liệu nằm trong biểu thức M, chỉ cho bảng nhỏ). Xem `specs/010-f-get-data-power-query-t3/plan.md` (S0, R6, R7) và `tasks.md` T010 đến T011.

**File thử:** `build/w-out/W4/tuan6.2_W4_table.pbix` (đã kiểm: BI Pro đọc lại được, `verify` 17 cột 0 lệch; bảng `Marketing` 14 cột 1363 dòng của file gốc + bảng mới `BiProTest` 3 cột 100 dòng; SHA-256 bắt đầu `376a9a8e`). Đây là bản sao, không phải file gốc của bạn.

**Chuẩn bị:** chép file vào VM (thư mục tạm, ví dụ `C:\Users\<bạn>\f0\`), mở bằng Power BI Desktop. Ghi lại **mọi hộp thoại nguyên văn** (kể cả cảnh báo).

**Đừng bấm Refresh** trước khi báo lại. Bảng `BiProTest` chưa có truy vấn M, Refresh có thể xoá dữ liệu hoặc báo lỗi, làm mất bằng chứng.

## Kiểm tra (đánh dấu và ghi vào `CHECKLIST-KET-QUA.md` cùng thư mục)

- [ ] File mở được, không báo "file bị hỏng" hay "không thể đọc mô hình".
- [ ] Data pane / Model view có bảng **BiProTest** với 3 cột: **Số lượng** (số nguyên), **Đơn giá** (thập phân), **Thành phố** (văn bản).
- [ ] Data view của BiProTest: **100 dòng**.
- [ ] Dòng đầu: Số lượng 0, 1, 2, 3, ...; Đơn giá 0, 0,25, 0,5, 0,75, ...; Thành phố Hà Nội, Đà Nẵng, Hồ Chí Minh, Cần Thơ, ...
- [ ] Dòng 8 có Thành phố **trống** (NULL), các dòng khác có tên thành phố.
- [ ] Card `Sum` của Số lượng = **4950**.
- [ ] Bảng **Marketing** (1363 dòng) vẫn đúng như file gốc (số dòng, một Card bất kỳ).
- [ ] (Tuỳ chọn, chỉ khi mọi mục trên đạt) **File → Save As** `W4_saved_by_powerbi.pbix` vào thư mục VM, chép về `build/w-out/W4/` để Claude so cách Desktop ghi lại bảng.

## Ảnh chụp

Chụp Data view và mọi hộp thoại, đặt vào `docs/phase-f-evidence/vm-f0/`. **Cắt bỏ dòng có địa chỉ tài khoản** đăng nhập Desktop (góc trên bên phải) trước khi lưu; ảnh nguyên cửa sổ không đưa vào git.

## Báo lại

**Đạt** hay **Trượt**, nguyên văn mọi hộp thoại, kết quả Card, ảnh chụp. Trượt cũng là kết quả hợp lệ: Claude chuyển sang Enter Data (tasks T029 đến T031) và nghiên cứu T3 tiếp song song (tasks T011).

## Mẫu `CHECKLIST-KET-QUA.md`

```
Kết quả: Đạt | Trượt
Phiên bản Desktop:
Hộp thoại (nguyên văn):
Số dòng BiProTest:
Card Sum(Số lượng):
Marketing còn đúng: có | không
Ghi chú:
```

Sau khi test xong: xoá thư mục thử trong VM.
