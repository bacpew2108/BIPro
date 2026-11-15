# Gate Desktop, Câu chuyện 3 (thuộc tính cột): kết quả (2026-11-14)

File `build/e-out/E3/Nhom6_e3.pbix` do BI Pro lưu (T2) từ bản sao Nhom6 sau khi sửa ở Table view: `Dim_Client[client_city]` mô tả "mo ta cot" và thư mục "Thu muc cot"; `Dim_Client[client_division]` ẩn; `Fact_Loan[loan_amount]` định dạng `#,0.00` và tổng hợp mặc định Trung bình; `Dim_District[division]` loại dữ liệu `StateOrProvince`; `Dim_Client[age_group_current]` sắp xếp theo `age_group_order`. Claude tự bấm chuột trên cửa sổ Parallels (`vm.sh`); bản sao đã xoá khỏi VM và Mac.

| Mục | Kết quả trong Power BI Desktop |
|---|---|
| Mở file | Đạt, không báo lỗi |
| Mô tả và thư mục hiển thị của `client_city` | Đạt: ngăn Properties hiện Description "mo ta cot" và Display folder "Thu muc cot"; ngăn Data có thư mục "Thu muc cot" chứa cột |
| `client_division` ẩn | Đạt: thẻ bảng hiện biểu tượng mắt gạch chéo |
| `division` loại dữ liệu `StateOrProvince` | Đạt: cột hiện biểu tượng địa lý (quả cầu) |
| Định dạng của `loan_amount` | Đạt: Desktop đọc được, ngăn Properties hiện Format "Decimal number" |
| Tổng hợp mặc định, sắp xếp theo cột | Chưa xem trong Desktop (nằm ở mục Advanced của ngăn Properties); ghi đúng trường `SummarizeBy` và `SortByColumnID` như BI Pro đọc lại ở test |

Ảnh chụp toàn cửa sổ có địa chỉ tài khoản nên không đưa vào git.

# Gate Desktop, Câu chuyện 4 (bố cục Model view): kết quả (2026-11-14)

File `build/e-out/E4/Nhom6_e4b.pbix` do BI Pro lưu (T2) từ bản sao Nhom6: kéo thẻ `Dim_Date` tới (700, 900), ẩn bảng `Dim_Trans_Type`, thu phóng tab "All tables" 50% (`DiagramLayout` ghép số bằng `DiagramLayoutPatch`). Claude tự bấm chuột trên cửa sổ Parallels; bản sao đã xoá khỏi VM và Mac.

| Mục | Kết quả trong Power BI Desktop |
|---|---|
| Mở file | Đạt, không báo lỗi |
| Thu phóng 50% | Đạt: Model view mở ở 50% |
| Thẻ `Dim_Date` ở vị trí mới | Đạt: thẻ nằm đúng chỗ tương đối với các thẻ khác (cách `Dim_Trans_Type` đúng khoảng đã ghi) |
| Bảng `Dim_Trans_Type` ẩn | Đạt: ngăn Data và thẻ hiện biểu tượng ẩn |

Chưa làm: thêm/đổi tên tab bố cục (nút "+" vẫn tắt, "chưa kiểm"); chưa quan sát cách Desktop tự ghi `DiagramLayout` khi kéo thẻ (BI Pro chỉ ghép số vào văn bản có sẵn nên không cần).
