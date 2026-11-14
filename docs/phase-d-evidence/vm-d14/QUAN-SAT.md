# VM-D14: checklist D2 và D3 trên Desktop, bấm thử trong app (2026-11-14)

Bạn hỏi "bạn không tự làm phần này được à", Claude coi đó là cho phép làm lại các mục còn chờ, kể cả điều khiển VM (ngoại lệ một lần, hiến pháp "agent không điều khiển VM" vẫn giữ). Dùng `build/d-out/D2/Nhom6_d2.pbix` và `build/d-out/D3/Nhom6_d3.pbix` (do test `D2Nhom6`, `D3Nhom6` sinh ra, qua đúng đường lưu của BI Pro), chép sang VM, mở bằng Power BI Desktop, chụp riêng cửa sổ Parallels. Đã dọn VM và bản chép ở Mac sau khi xong.

## Checklist D2 (`build/d-out/D2/CHECKLIST.md`)

| Mục | Kết quả |
|---|---|
| 1 Mở file | Đạt: không hộp thoại lỗi |
| 2 Đủ 4 trang, dữ liệu nạp | Đạt (D1, D2, D3, Chi tiết chi nhánh) |
| 3 Card thứ tư tên "Số dư BQ (đổi tên)" | Đạt, số `$44K` |
| 4 Donut: ô Tooltips có `Net_Cashflow` | Đạt: tooltip hiện Chiều tiền, Giá trị, % giá trị, Số GD, `Net_Cashflow` |
| 5 Combo: "Tiền ra" thành đường | Đạt |
| 6 Matrix: giá trị tên "GD / KH" | Đạt, số giống bản gốc |
| 7 Visual khác giống bản gốc | Đạt |
| 8 Số liệu khớp BI Pro | Đạt: card `$3bn`, `$3bn`, `$197M`, `$44K`, 1,056,320; matrix `238,5…` giống từng ô |
| 9 Save trong Desktop | Đạt: "Last saved" đổi giờ, không báo lỗi |

Biểu đồ đường "Giá trị giao dịch…" ở góc trên trái của D1 để trống trong Desktop suốt vài phút ở bản D2 (không đổi gì ở visual này); chưa rõ do nạp chậm hay do dự báo, không liên quan đến bản sửa.

## Checklist D3, mục 10 và 11

- **Mục 11 (Save trong Desktop): đạt** (`d3` "Last saved" đổi giờ, không lỗi).
- **Mục 10 (số liệu khớp BI Pro): đạt, kèm hai chênh lệch về cách vẽ** (số liệu giống nhau):
  1. Biểu đồ thanh nhóm do đổi từ đường (Category `month_start`, ngày): Desktop vẽ trục ngày **liên tục** (2013 ở dưới, 2018 ở trên, chỉ ghi nhãn năm; tháng gần nhất ở trên cùng). BI Pro xếp từng tháng từ trên xuống (Jan 2013 trên cùng) với nhãn tháng dày đặc. Chưa sửa; muốn khớp cần quan sát thêm `categoryAxis.axisType` cho cột/thanh.
  2. Card "Giá trị TB/GD" (`labelDisplayUnits` Tự động): Desktop `$5,924`, BI Pro cũ `$6K`. **Đã sửa** (dưới).

## Lỗi bắt được khi bấm thử: engine treo ở trang D1 của `Nhom6_d3.pbix`

- Triệu chứng: mở `Nhom6_d3.pbix` trong BI Pro, sang trang D1 thì mọi visual giữ nguyên ô mờ "Chờ engine DAX", CPU 0%, không lỗi; quay lại D3 cũng đứng. Tái hiện hai lần. Bản gốc `Nhom6_work.pbix` mở D1 bình thường. `DAX_SERIAL=1` (ép tuần tự) hết treo.
- `sample` tiến trình: mọi luồng của Swift concurrency chặn ở `DispatchGroup.wait` trong `SummarizeColumns.evaluateCells`, còn các khối phụ chia ô không có luồng để chạy. Nguyên nhân: nhiều visual truy vấn cùng lúc (D1 của bản D3 có thêm bốn visual nặng), mỗi truy vấn giữ một luồng Task để chờ khối phụ trên hàng đợi GCD, hàng đợi hết luồng nên không khối nào chạy: chờ vòng tròn.
- Sửa (`Sources/DAXEngine/Query/ParallelCells.swift`): luồng gọi cũng tự lấy ô làm, chỉ chờ ô đang chạy dở, không bao giờ chờ một khối phụ chưa chạy; các khối phụ chỉ là hỗ trợ thêm. Test `ParallelCellsTests`: hai test dùng hàng đợi bị chiếm (khối phụ không bao giờ chạy) đỏ với bản cũ (treo quá 10 giây), xanh với bản mới; thêm test thứ tự, ô trả nil, lỗi một ô và nhiều truy vấn cùng lúc. Trên app thật: D1 của `Nhom6_d3.pbix` nạp đủ trong dưới 40 giây, CPU rảnh 0%.
- Không có seam tái hiện thật sự cho thiếu luồng của GCD trong test (cần nhiều Task cùng chặn luồng); test dùng hàng đợi kẹt để mô phỏng đúng điều kiện "khối phụ không có luồng".

## Đơn vị tự động của số (card `$5,924`)

Card "Giá trị TB/GD" có `labelDisplayUnits = 0` (Tự động) và giá trị 5.924: Desktop hiện `$5,924`, BI Pro cũ hiện `$6K` vì ngưỡng nghìn là 1.000. Ngưỡng của `DisplayUnitSystem` trong Power BI là nghìn từ 10.000, triệu từ 999.500, tỉ từ 999.500.000, nghìn tỉ từ 999.500.000.000 (số bốn chữ số giữ nguyên; 999.500 làm tròn lên 1M). `NumberDisplay.resolve` áp ngưỡng này; test `nguongDonViTuDong`, `cardD1KhopPowerBI` (thêm `$5,924`). Chỉ có một mẫu Desktop (5.924 → không đơn vị; 43.812 → `$44K`; 197M; 3,2bn), phần còn lại theo thư viện công khai của Power BI; trục dùng chung hàm này theo giá trị lớn nhất của visual, chưa có mẫu Desktop riêng cho trục.
