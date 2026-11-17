# Gate tổng M3 (T100): kết quả

Ngày 2026-11-17, Power BI Desktop 2.159 trong VM, Claude lái VM (người dùng cho phép trong Phase F). Tệp sinh bằng `M3GateTests.taoFileGateM3` (`build/f-out/m3/`, ngoài git), chép sang `C:\Users\bacpew\m3\` (đã dọn sau buổi). Ảnh đã cắt ở `vm-m3/`.

## 1. Luồng `sales_2026.xlsx` trên tài liệu mới (SC-001, SC-009 gate F-Mới + F-Query)

BI Pro: tài liệu mới → Get Data ▸ Excel `sales_2026.xlsx` ▸ Navigator chọn Sales ▸ Chuyển đổi dữ liệu ▸ lọc Region = North hoặc South, bỏ cột Price, sắp giảm dần Amount ▸ Close & Apply ▸ measure `Tong Amount`, `So dong` + hai card ▸ lưu `bipro-m3.pbix`. M lưu trong tệp:

```
Source = Excel.Workbook(File.Contents("C:\Users\bacpew\m3\sales_2026.xlsx"), null, true),
Sales_Sheet = Source{[Item="Sales",Kind="Sheet"]}[Data],
#"Promoted Headers" = Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true]),
#"Changed Type" = Table.TransformColumnTypes(...),
#"Filtered Rows" = Table.SelectRows(#"Changed Type", each ([Region] = "North" or [Region] = "South")),
#"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"Price"}),
#"Sorted Rows" = Table.Sort(#"Removed Columns",{{"Amount", Order.Descending}})
```

| Kiểm | Mong đợi (Python đọc XML trang Sales, độc lập) | BI Pro | Desktop mở tệp | Desktop sau Refresh (Schema and data) | Kết quả |
|---|---|---|---|---|---|
| Mở tệp không lỗi | | | có, card "So dong" 191 (`m1-card.png`) | | **ĐẠT** |
| Số dòng | 191 | 191 | 191 | 191 | **ĐẠT** |
| Σ Amount, `[Tong Amount]` | 69 256,96 | 69 256,96 | 69 256,96 | 69 256,96 | **ĐẠT** |
| Σ Qty | 1 909 | 1 909 | 1 909 | 1 909 | **ĐẠT** |
| Số vùng | 2 | 2 | 2 | 2 | **ĐẠT** |

Desktop Refresh chạy lại đúng M của BI Pro trên tệp xlsx trong VM ("Data refreshed 12:09:06 PM", `m3-refresh.png`); số trước và sau Refresh bằng nhau (`m2-dax-truoc-refresh.png`, `m4-dax-sau-refresh.png`), nên kết quả các bước M của BI Pro khớp Desktop 100% trên luồng này. Thao tác BI Pro trong app (bấm thử T099) dưới 5 phút.

Ghi nhận: hai card BI Pro thêm cùng chỗ (giữa vùng nhìn) nên chồng lên nhau; Desktop cũng đặt visual mới cùng chỗ mặc định. Không phải lỗi tệp.

## 2. Nhom6 lưu bằng bộ nén XPress9 độ sâu 4 (T106)

`Nhom6_m3.pbix`: Nhom6 thêm measure `M3 kiem nen = COUNTROWS('Fact_Loan')`, lưu T2 (54 087 699 byte). Desktop mở được, đủ 11 bảng, 4 trang; DAX query view: `[M3 kiem nen]` 682, `COUNTROWS(Fact_Loan)` 682, `COUNTROWS(Fact_Transaction)` 1 056 320 (`n1-nhom6-dax.png`). **ĐẠT**: Desktop đọc luồng nhiều khối nén với độ sâu tìm khớp 4.
