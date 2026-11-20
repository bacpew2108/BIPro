# VM-F13 (T047): sửa/xoá cột tính toán còn được dùng (2026-11-19)

Power BI Desktop 2.159 trong VM. Buổi này không bấm trong VM (máy Mac đang được dùng): sửa mô hình ngay trong engine của Desktop bằng TOM
(`Microsoft.PowerBI.Tabular.dll` trong thư mục `bin` của Desktop, script `build/vm-tools/tmsl.ps1`/`tom.ps1`, ngoài git), trên tệp `bipro-f13-sua.pbix`:
bảng `Sales` có cột tính toán `Nhóm` là khoá quan hệ `Sales[Nhóm] → Nhom[K]`, là cấp của phân cấp `Vùng nhóm` (Region → Nhóm) và là cột sắp xếp
của `Nhãn`. Đây là quy tắc của engine; lời và hộp thoại của giao diện Desktop chưa quan sát.

| Thao tác (TOM, `SaveChanges`) | Kết quả |
|---|---|
| Sửa `Nhóm` = `MOD(Sales[Key], 5) + 10` (mỗi `Nhãn` ứng với nhiều `Nhóm`) rồi `refresh calculate` | **nhận**, mọi cột Ready; quan hệ, phân cấp vẫn chạy; MDX theo `Nhãn` chạy |
| Xoá `Nhóm` khi còn dùng | **từ chối**: "The column 'Nhãn' in table 'Sales' has the SortByColumn property set to column 'Nhóm' which has been deleted." |
| Bỏ cách sắp xếp của `Nhãn` rồi xoá | **từ chối**: "Level 'Nhóm' in hierarchy 'Vùng nhóm' in table 'Sales' has the Column property set to column 'Nhóm' which has been deleted." |
| Bỏ cả quan hệ rồi xoá | vẫn từ chối vì cấp phân cấp |

Kết luận cho BI Pro:
- Sửa công thức: không chặn khi cột sắp xếp mất một–một (trước đây BI Pro báo lỗi; đã bỏ).
- Xoá: phải gỡ cách sắp xếp, quan hệ và cấp phân cấp trước, như BI Pro làm (`PBIXWriter`, hộp xác nhận liệt kê).
- `[SUY ĐOÁN]` còn lại: Desktop có tự gỡ kèm khi xoá qua giao diện hay báo lỗi; lời hộp thoại.

## Bổ sung 2026-11-20 (T071, buổi VM bấm giao diện Desktop trên `bipro-f13-sua.pbix`)
- Chọn `Sales[Nhóm]` trong Data pane, bấm `...` → **Delete from model**:
  - Hộp thoại xác nhận của Desktop (`p1-hop-thoai-xoa.png`): tiêu đề **`Delete column`**, nội dung **`Are you sure you want to delete 'Nhóm'?`**, nút **`Yes`** / **`Cancel`**. Desktop không liệt kê danh sách đối tượng phụ thuộc trong hộp thoại (BI Pro liệt kê rõ quan hệ, cấp phân cấp và cột sắp xếp bị gỡ kèm).
- Bấm **`Yes`** (`p2-sau-khi-xoa.png`):
  - Desktop **tự động xoá kèm**: cột `Sales[Nhóm]` bị xoá; quan hệ `Sales[Nhóm] → Nhom[K]` bị gỡ (`INFO.VIEW.RELATIONSHIPS()` rỗng); thuộc tính `SortByColumn` của `Sales[Nhãn]` được đặt về trống; phân cấp `Vùng nhóm` bỏ cấp `Nhóm`, giữ lại cấp `Vùng` (MDX `ALLMEMBERS` còn `All`, `E`, `N`, `S`).
  - Kết quả khớp hoàn toàn với tệp `bipro-f13-xoa.pbix` do BI Pro ghi.
  - Visual đang dùng `Nhóm` và `Vùng nhóm` trên canvas chuyển sang lỗi thiếu trường ("Something's wrong with one or more fields") như kỳ vọng.
- Sửa công thức `Sales[Nhóm]` trên thanh công thức với `MOD(Sales[Key], 3) + 10`: tổng `Qty` theo `Nhom[Ten]` (`Mười = 6`, `Mười một = 6`, `Mười hai = 5`) và biểu đồ `Sum of Nhóm by Vùng and Nhóm` (`E: 11`, `N: 10, 11`, `S: 12`) khớp BI Pro.
