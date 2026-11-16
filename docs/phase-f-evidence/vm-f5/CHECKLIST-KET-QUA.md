# Gate T079: file `.pbix` mới do BI Pro tạo, mở trong Desktop 2.159 (2026-11-16)

Người dùng cho lái VM. Hai file do test sinh (`F5NewDocTests`, ở `build/f-out/f5/`, ngoài git), chép sang VM, mở bằng Desktop. Ảnh đã cắt bỏ thanh tiêu đề (có tài khoản đăng nhập).

| File | Nội dung | Kết quả | Ảnh |
|---|---|---|---|
| `bipro-trong.pbix` | File → Mới rồi lưu ngay (chưa sửa gì) | **ĐẠT.** Mở không lỗi, màn hình "Add data to your report", một trang "Page 1" | `g1-bipro-trong.png` |
| `bipro-moi.pbix` | File → Mới → Get Data `sales_2026.xlsx` (Sales) → Query Editor → Close & Apply → measure `Tổng Amount = SUM(Sales[Amount])` → card + biểu đồ cột (Region) → lưu lần đầu | **ĐẠT.** Mở không lỗi, không cần Refresh. Data pane: `Sales`. Card **182.26K** (Python: 182 260,61). Biểu đồ cột X = Region, Y = Tổng Amount, 5 cột East ≈34K, North ≈36K, South ≈33K, Trung tâm ≈37K, West ≈42K (Python: 34 467,09 / 36 450 / 32 806,96 / 36 547,92 / 41 988,64). Table view: `Sales (500 rows)`, dòng đầu `1, Monday March 2 2026, Trung tâm, 7, Đồng hồ, 11, 120, 1320` khớp tệp nguồn | `g2-bipro-moi-bieu-do.png`, `g3-bipro-moi-card.png`, `g4-bipro-moi-bang.png` |

Ghi nhận:
- Card và biểu đồ nằm chồng nhau vì test chèn cả hai với cùng vùng nhìn (`insertVisual(visibleRect:)`); phải kéo biểu đồ sang mới thấy card. Không phải lỗi file.
- Auto date/time của file mới tắt (BI Pro chưa dựng bảng ngày cục bộ): cột `OrderDate` không có Date Hierarchy trong Desktop, đúng như thiết kế (QUAN-SAT mục 4).
- Tập thành phần tối thiểu Desktop chấp nhận (spec mục 3, kịch bản 5.3): 10 phần như file trống của Desktop trừ `SecurityBindings` (`Version`, `[Content_Types].xml`, `Settings`, `Metadata`, chủ đề nền, `version.json`, `report.json`, `pages.json`, `page.json`, `DataModel`); không cần `DataMashup`, `DiagramLayout`.
