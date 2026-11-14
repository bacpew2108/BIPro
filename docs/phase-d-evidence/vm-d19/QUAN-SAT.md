# VM-D19: các chỗ còn lệch với Desktop (2026-11-14)

Bạn giao: "Làm cho xong phần lệch trước, có thể sử dụng vm". Claude điều khiển VM (ngoại lệ một lần, hiến pháp vẫn giữ). Dùng bản sao `Nhom6_work.pbix` (Mac `~/Desktop/vmd19`, trong VM `vmd19`; đã xoá cả hai, VM đã tắt Desktop). Ảnh Desktop ở đây chỉ giữ phần visual, không có địa chỉ tài khoản.

**Sự cố nhỏ khi điều khiển:** hai cú bấm đầu rơi vào cửa sổ Chrome của bạn (Chrome nằm đè đúng lên cửa sổ Parallels, vùng nội dung góc dưới trái), không phải VM. Tôi thêm chốt chặn vào `build/vm-tools/vm.sh`: đưa Parallels lên trước và dừng nếu cửa sổ trước nhất không phải Parallels. Từ đó không còn bấm lạc.

## 1. Thanh có trục ngày liên tục (`desktop-bar-date-continuous.png`)

Đổi biểu đồ đường D1 Q1.1 (Category `month_start`, ngày) sang Clustered bar trong Desktop. JSON (`json/retype-bar-datecat.visual.json`): `categoryAxis.axisType = 'Scalar'` giữ nguyên, `sortDefinition` tăng dần theo `month_start`. Hình:

- Trục dọc là trục liên tục: **2013 ở dưới, mới nhất ở trên**; chỉ ghi **nhãn năm** tại vạch đầu năm, có đường lưới ngang mờ ở mỗi năm; mỗi tháng một thanh **mảnh** (≈ 0,55 bề dày ô).

BI Pro: kiểu thanh có `axisType = Scalar` đảo thứ tự (mới nhất ở trên), nhãn năm tại tháng đầu năm kèm lưới (dùng lại `scalarXTicks/scalarXLabels` của cột), thanh `height: .ratio(0.85)`; chọn/hover thanh hỏi biểu đồ danh mục tại vị trí thay vì chia đều. Ảnh `bipro-bar-date-continuous*.png`. Test `thanhCoTrucNgayLienTucChiGhiNhanNam`.

## 2. Bước chia và miền của trục giá trị (`desktop-d1-axes.png`, `desktop-d3-q3*-axes.png`)

Đo trên Desktop (visual 660×380 ở zoom Fit):

| Visual | Dữ liệu | Desktop |
|---|---|---|
| D1 cột "Tiền vào/ra" (trục chính) | max 0,96 tỉ | $0,0bn / $0,5bn / $1,0bn (vạch 0,2bn cách nhau 46,6 bị bỏ) |
| D1 "Rủi ro thấu chi" trục trái | max ≈190 | 0, 50, 100, 150, 200 (47,5 giữ) |
| cùng visual, trục phải | max ≈37K | $0K, $20K, $40K (bước 10K cách 47,5 bị bỏ: trục phụ thưa hơn) |
| D3 Pareto, trục trái / phải | 5,9K / 100% | 0K, 5K (miền vẫn 5,9K, không kéo lên 10K) / 0%, 100% |
| D3 thanh "Khiếu nại theo nhóm" | max 4,49K | 0K, 1K, 2K, 3K, 4K (trục ngang) |
| D1 thanh theo tháng | max 210M | $0M, $50M, $100M, $150M, $200M |
| cột "Tiền vào/ra" ở chế độ tập trung (cao hơn) | 0,96 tỉ | 0,0 đến 1,0 bước 0,2 (6 vạch) |

Quy tắc suy ra: bước 1, 2, 5 × 10^k nhỏ nhất mà các vạch còn cách nhau **≥ 47** (trục chính), **≥ 60** (trục phụ), **≥ 100** (trục giá trị nằm ngang) đơn vị trang; **miền chỉ kéo lên vạch kế khi vạch đó cách dữ liệu không quá 10% miền**, không thì giữ đúng giá trị lớn nhất và chỉ có những vạch nằm trong miền. Vùng vẽ cao ước theo chiều cao visual: trừ 97 (tiêu đề, phụ đề, lề) cộng 25 nếu có chú giải, rồi trừ dải nhãn trục danh mục (ngang ≈ 25; xoay dọc: độ dài nhãn đã cắt × cỡ chữ × 0,55 + 14), khớp 233 và 190 đo được ở hai cột D1. Nhãn trục đổi "nghìn" từ **1.000** (Pareto "5K", thanh "0K…4K"); số trên thẻ vẫn từ 10.000 (VM-D14).

BI Pro: `ChartAxis.fittingTicks`, `minSpacingPrimary/Secondary/Horizontal`, `domainExtension`; `VisualRenderContext.visualSize` (từ khung visual); `PreparedChartLayout` dùng khi biết kích thước, không biết thì 5 vạch (trước là 4 và có bước 2,5, nay làm tròn lên theo 1, 2, 5); thanh ngang chừa 24 ở mép phải và tắt tự cắt nhãn vạch cuối ("$200M" không còn thành "$…"). Test `vachTrucTheoChieuCaoVungVeNhuDesktop`, `vachTrucLamTronLenTheoMotHaiNamNhuDesktop`. Kiểm bằng ảnh `bipro-d1-axes.png`, `bipro-d3-axes.png`: ba cột/thanh trên cùng nhãn trục như Desktop.

## 3. Nhãn trục danh mục xoay dọc

Desktop xếp nhãn xoay dọc cách nhau ≈ 20,5 đơn vị trang ("Khiếu nại thay đổi" 23 nhãn, "Rủi ro thấu chi" 25 nhãn trên ≈ 500). BI Pro: `visibleCategoryCount` dùng 1,46 × cỡ chữ (trước 1,9): "Khiếu nại thay đổi" hiện 24 nhãn, Pareto ≈ 34 (Desktop 31).

## 4. Trục không bắt đầu từ 0 (`desktop-2018-q1*-floating-axis.png`)

Lọc năm 2018 trong Desktop (ô Năm, Quý, Tháng) để lấy mẫu có dữ liệu xa 0:

| Đường | Dữ liệu | Trục Desktop |
|---|---|---|
| D1 Q1.1 (năm 2018, kèm dự báo xuống ≈97M) | 128M…211M | $50M…$250M, bước 50M |
| D1 "Rủi ro thấu chi", trục phải (2018) | ≈31K…45K | $30K…$50K, bước 5K |
| D1 "Dòng tiền ròng" (mọi năm) | 18M…50M | miền $10M…$50M (chế độ tập trung $15M…$50M) |
| Pareto lũy kế / "số dư" cả giai đoạn / D2 số khoản vay | 0,25…1 / 6,5K…44K / 20…196 | bắt đầu từ 0 |

Quy tắc: **đường** (ô Y của biểu đồ đường, ô Y2 của combo) không bắt đầu từ 0 khi giá trị nhỏ nhất ≥ 1/3 giá trị lớn nhất (0,37 ra miền không từ 0; 0,25 và 0,15 bắt đầu từ 0); cận dưới là vạch ngay dưới giá trị nhỏ nhất (gồm cả dải dự báo), cận trên là vạch ngay trên giá trị lớn nhất. Cột luôn từ 0. BI Pro: `ChartAxis.floatingLow` và `fittingTicks(floating:)`; vạch ở trường hợp này dùng khoảng cách tối thiểu 47,3 cho cả trục phụ (mẫu "số dư" 2018 giữ bước 5K cách 47,5). Không áp dụng khi file đặt `start`/`end` (hoặc `secStart`/`secEnd`) hay thang log. Test `duongKhongBatDauTuKhongKhiDuLieuNamXaKhong`; BI Pro D1 nay ra $10M…$50M cho "Dòng tiền ròng". Ngưỡng 1/3 chỉ chốt giữa 0,25 và 0,37, chưa có mẫu ở giữa.

## 5. Trục phải chỉ hiện khi miền khác trục chính (`desktop-d3-q31-primary-max-300.png`)

D3 "Khiếu nại thay đổi" (đường "TB 3 tháng" ở ô Y2) không có trục phải. Thẻ Format > Secondary y-axis > Values đều Tắt cả ở visual có trục phải (VM-D21 kiểm Q1.4), nên công tắc đó không quyết định. Thử: đặt Maximum của trục chính = 300 → **trục phải 0…600 hiện ra**; bỏ lại thì mất. Vậy Desktop vẽ trục phụ khi miền của nó khác miền trục chính; cùng miền (0…600) thì một trục. (Quy tắc "cùng định dạng số / không có `sec*`" ở lần VM-D19 đầu cũng khớp mọi visual nhưng bị bài thử này loại.) BI Pro: `hasSecondaryAxis = hasY2 && !axesCoincide` (vạch và miền trục phụ trùng trục chính). Để Q3.1 ra cùng 0…600 ở cả hai trục, miền kéo lên vạch kế khi vạch cách dữ liệu ≤ 20% miền (518 lên 600; Pareto 5,9K không lên 10K vì 69%); trục giá trị nằm ngang chỉ kéo khi ≤ 5% (thanh max 4,49K không lên 5K, 210M không lên 250M, 0,989 lên 100%). Test `trucPhuChiHienKhiMienKhacTrucChinh`.

## 5b. Cỡ visual khác và miền không từ 0 (`desktop-d1-q14-height-240.png`)

"Tiền vào/ra" đổi chiều cao còn 240 trong Desktop: trục trái $0,0bn / $0,5bn / $1,0bn (vùng vẽ ≈ 104, khoảng cách 52), trục phải miền $10M…$50M ghi $20M và $40M (như ở cao 380). Chiều cao vùng vẽ: 104 ở cao 240, 233 ở cao 380, tức ≈ 0,92 × cao − 117; BI Pro nay ước vùng vẽ = 0,92 × cao visual − 92 (67 nếu không có chú giải) − dải nhãn. Miền không từ 0 chọn cận dưới/trên theo bước 10M (10M…50M) nhưng chỉ ghi nhãn ở bội chẵn khi bước dạng 1 × 10^k (mẫu duy nhất: "Dòng tiền ròng"; "số dư" 2018 bước 5K và D1 Q1.1 bước 50M ghi đủ). Chưa đo được visual cao hơn 380 (vượt trang thì bị cắt).

## 6. Nhãn "100%" ở vạch cuối của thanh phần trăm

Nguyên nhân: nhãn trục dưới của thanh dùng điểm neo mặc định của Swift Charts (nhãn bắt đầu tại vạch, không căn giữa), nên nhãn của vạch cuối sát mép bị cắt. Sửa: `AxisValueLabel(anchor: .top, collisionResolution: .disabled)` (căn giữa tại vạch) và chừa 24 ở mép phải khi vạch cuối sát mép. D3 "Khiếu nại theo sản phẩm" nay ra 0%, 50%, 100% như Desktop.

## Còn lệch

- Quy tắc nhãn ở bội chẵn cho bước 1 × 10^k chỉ có một mẫu; ngưỡng 47,3/60/100 (khoảng cách vạch), 1/3 (đường không từ 0), 20% và 5% (kéo miền) suy ra từ số đo, chưa kiểm ở nhiều cỡ visual (cao hơn 380 chưa đo).
- Lần thử đổi chiều cao thứ hai ở VM-D21 lưu ra visual 540×392 chứ không phải 240, nên không đối chiếu được BI Pro ở cỡ 240 bằng file lưu; chỉ đối chiếu bằng số đo trên Desktop.
