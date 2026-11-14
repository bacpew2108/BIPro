# VM-D18: Round range và kiểm lại cuối cùng trên bản app mới nhất (2026-11-14)

## Round range của trục Y (Desktop, biểu đồ đường D1)

Y-axis > Range > Round range, mặc định **Bật** (VM-D16). Tắt (`desktop-round-range-off.png`): khoá `objects.valueAxis[0].properties.roundRange = {"expr":{"Literal":{"Value":"false"}}}`; **trục lấy đúng miền dữ liệu** (đáy ở giá trị nhỏ nhất, đỉnh ở giá trị lớn nhất kể cả dải dự báo), vạch chỉ còn các giá trị đẹp nằm trong miền ($50M … $200M), không ép bắt đầu từ 0.

BI Pro: `ValueAxisFormat.roundRange`, miền = `[nhỏ nhất, lớn nhất]` của dữ liệu và dự báo ở biểu đồ đường (cột giữ đáy 0), thẻ Trục Y có công tắc "Làm tròn miền" (`FormatCatalog`, mặc định bật). Mở chính file Desktop vừa lưu trong BI Pro: đáy và đỉnh trục khớp (`bipro-round-range-off.png`); khác nhau chỉ ở bước vạch (BI Pro chọn bước theo số vạch mục tiêu, Desktop theo chiều cao khung). Test `roundRangeTatLayDungMienDuLieuTrenBieuDoDuong`.

## Kiểm lại trong app (bản đóng gói mới nhất, bản sao Nhom6, chụp riêng cửa sổ BI Pro)

- **Kéo tab trang và ⌘Z** (`bipro-tab-drag-and-undo.png`): hàng trên D2, D1, D3 sau khi kéo; hàng dưới D1, D2, D3 sau ⌘Z.
- **Bottom N** (`bipro-bottom-n-applied.png`): thẻ "Bottom 3 theo Avg Complaints per Month", biểu đồ chỉ còn 3 nhóm tuổi.
- **Advanced trên measure** (`bipro-advanced-applied.png`): thẻ "Số khiếu nại nhỏ hơn 2000" áp dụng.
- **Phễu, thác nước, bản đồ hình** (`bipro-funnel-waterfall-shapemap.png`): đổi biểu đồ đường D1 sang từng loại ra hình thật chứ không phải ô giữ chỗ "Chờ engine DAX": phễu (thanh căn giữa, "100%" trên, phần trăm dưới), thác nước (cột Increase, Total, chú giải 3 mục), bản đồ hình (nền xám, chú giải từ Jan 2013).
- **Vùng, vùng xếp chồng, vùng 100%, ruy-băng** (`bipro-area-stacked-100-ribbon.png`, đổi biểu đồ đường D1 một series): vùng và vùng xếp chồng ra hình tô nhạt trục từ 0; vùng 100% một series phủ kín 100% (đúng kỳ vọng); ruy-băng một series là các cột. Ruy-băng nhiều series (cột xếp theo thứ hạng, dải nối): `docs/phase-d-evidence/vm-d15/bipro-ribbon.png`.

## Bảng đối chiếu bằng chứng cho yêu cầu "làm cho xong phần này"

| Mục | Bằng chứng |
|---|---|
| Kéo tab trang; Bottom N; Advanced trong app | `vm-d18/bipro-tab-drag-and-undo.png`, `bipro-bottom-n-applied.png`, `bipro-advanced-applied.png`; Desktop mở lại file đó: `vm-d15/QUAN-SAT.md` mục 1 |
| Mẫu mặc định thẻ Format | `vm-d15/QUAN-SAT.md` mục 2 (Title, Subtitle), `vm-d16/QUAN-SAT.md` mục 1 và ảnh `desktop-format-*.png` (trục, Legend, lưới, cột, matrix Grid/Values), `vm-d17`, `vm-d18` (Log, Round range) |
| Chú giải `Series` bản đồ hình | `vm-d15/bipro-shapemap-legend.png` và `desktop-shapemap-series-legend.png`; có Location: `vm-d16/QUAN-SAT.md` mục 2; `vm-d18/bipro-funnel-waterfall-shapemap.png` |
| Vùng, ruy-băng, thác nước, phễu (bộ vẽ, thư viện, đổi loại khớp JSON Desktop) | `vm-d15/QUAN-SAT.md` mục 4 và ảnh `desktop-*.png`/`bipro-*.png`, `vm-d16` (Breakdown, vùng 100%, hover), `vm-d18` (ảnh các loại trong app); heavy test `doiDuongSangVungRuyBangThacNuocPheuNhuDesktop` |

## Kiểm lần cuối hai mục còn lại (bản app mới nhất, bản sao Nhom6)

- **Bản đồ hình có cả Location và Series** (`bipro-shapemap-location-and-series-legend.png`): Location = `state_name`, Series = Tháng, Value = Giá trị GD: các bang tô màu series đầu (xanh), chú giải Jan 2013 … Aug 2013 ở đáy, không theo thang Color saturation; đúng quan sát Desktop (VM-D15, VM-D16).
- **Mặc định Format trên visual mới** (visual cột nhóm thêm từ "Visual mới", chưa đặt định dạng nào): tab Visual `bipro-new-visual-format-visual-tab.png`: Chú giải bật, Nhãn dữ liệu tắt, Thanh thu phóng tắt, Vùng tô và đường tắt; tab Chung `bipro-new-visual-format-general-tab.png`: Tiêu đề bật, Phụ đề bật, Đường kẻ dưới tiêu đề tắt, Nền bật, Viền bật, Đổ bóng tắt, Biểu tượng tiêu đề bật. Tất cả khớp mẫu Desktop (`vm-d15` mục 2, `vm-d16` mục 1).
