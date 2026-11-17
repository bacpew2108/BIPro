# Gate VM-F10 (T016): gộp ngầm, ĐẠT

Ngày 2026-11-17, Desktop 2.159, Claude lái VM. Tệp: `bipro-f10.pbix` do `F2ImplicitFlowTests` sinh (tài liệu mới BI Pro, Get Data `sales_2026.xlsx`). Gồm:
- card cũ với ô Values: Sum of Amount;
- biểu đồ cột theo Region: Average of Qty và Variance of Price, đổi qua menu phép gộp;
- card mới với ô Data: First Region.

Bản chép tệp ở `vm-f10/bipro-f10.pbix` (ngoài git).

| Kiểm | BI Pro | Desktop | Kết quả |
|---|---|---|---|
| Mở tệp không lỗi | | có (`g1-desktop-mo-bipro-f10.png`) | **ĐẠT** |
| Nhãn trường | Trung bình của Qty, Phương sai của Price, Đầu tiên của Region | "Average of Qty and Variance of Price by Region", "First Region" | **ĐẠT** |
| Văn bản truy vấn (Performance Analyzer, `gate-queries.json`) | `DAXQueryBuilder` | trùng nguyên văn cả 3 visual (`ImplicitAggregationGateTests`) | **ĐẠT** |
| Σ Amount | 186 731,23 | 186 731,23 (`g2-dax-query-view.png`) | **ĐẠT** |
| First Region | East | East | **ĐẠT** |
| Average Qty East / Trung tâm | 9,72 / 9,6126… | 9,72 / 9,61 | **ĐẠT** |
| VAR.P Price East | 1 656,41287971 | 1 656,41 | **ĐẠT** |

Số mong đợi tính độc lập bằng Python đọc XML của tệp xlsx.

Lỗi tìm ra ở lần gate đầu và đã sửa: hai trường cùng cột `Qty` (Average, Variance) có cùng `queryRef` `Sum(Sales.Qty)`. Desktop coi hai trường đó là một, nên hiện "Average of Qty and Average of Qty" và chỉ vẽ một chuỗi cột. BI Pro nay chặn việc gộp một cột hai lần trong cùng visual, vì chưa quan sát được Desktop đặt `queryRef` thế nào trong trường hợp này.

Ghi nhận thêm: các visual chèn bằng lệnh nằm chồng ở cùng vị trí, nên card Sum of Amount bị biểu đồ che (như M3). Đây không phải lỗi tệp.
