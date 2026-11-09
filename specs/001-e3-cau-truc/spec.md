# Đặc tả tính năng: E3-cấu-trúc, truy vấn visual chậm nhất dưới 1 giây

**Thư mục tính năng**: `specs/001-e3-cau-truc`

**Ngày tạo**: 2026-11-09

**Trạng thái**: Nháp

**Đầu vào**: Đợt engine riêng đưa hai truy vấn visual chậm nhất của Phase C xuống dưới 1 giây trên Nhom6 (combo "Rủi ro thấu chi" hiện 2,15 s, matrix "Giờ × Thứ" hiện 1,75 s, máy 8 nhân), kết quả vẫn khớp từng byte, golden Phase B/C vẫn qua.

## Quan sát Power BI

- Power BI Desktop mở trang D1 của `Nhom6_Dashboard.pbix` mà người dùng không thấy chờ lâu. Ngưỡng đã chốt ở `docs/phase-c-evidence/C1.md` §0.4: cả trang dưới 3 s, mỗi visual dưới 1 s `[QUAN SÁT: PHASE_C_PLAN]`.
- Văn bản truy vấn của hai visual lấy nguyên từ Performance Analyzer: `observe-c1/pa/D1-combo-thauchi.dax` và `observe-c1/pa/D1-matrix-gio-thu.dax`. Kết quả chuẩn là bản đã so khớp Power BI ở các golden hiện có.
- Số đo hiện tại của BI Pro (`C1.md` §1.5, sau E3 vòng 2, 8 nhân): combo thấu chi 2,15 s; matrix Giờ × Thứ 1,75 s; matrix mở nút 1,0 s; combo kênh 0,74 s. Combo thấu chi tính khoảng 180 nghìn ô (tài khoản × tháng) cho measure `Avg_Account_Balance`, mỗi ô chịu chi phí gần như bằng nhau (khoảng 45 µs CPU).
- Các sửa nhỏ ở vòng 2 đã hết lợi nhuận: thử giảm cấp phát nhỏ không đo được cải thiện. Muốn xuống dưới 1 s cần đổi cách tính ở mức cấu trúc.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1: Mở trang D1 không phải chờ ở hai visual nặng (Ưu tiên: P1)

Người xem mở trang D1 hoặc đổi slicer. Combo "Rủi ro thấu chi" và matrix "Giờ × Thứ" hiện số liệu trong chưa đầy 1 giây thay vì 2 s.

**Vì sao P1**: đây là mục tiêu của cả đợt. Hai visual này là hai visual duy nhất của Phase C còn trên ngưỡng 1 s.

**Kiểm thử độc lập**: chạy `zsh scripts/e3-loop.sh` trên `Nhom6_Dashboard.pbix`, đo thời gian từng truy vấn (trung vị của vài lần chạy).

**Kịch bản chấp nhận**:

1. **Cho** trang D1 ở trạng thái mặc định, **khi** chạy truy vấn combo thấu chi, **thì** xong dưới 1 s và kết quả khớp từng byte với bản chuẩn `build/e3-base/D1-combo-thauchi.engine.tsv`.
2. **Cho** trang D1 ở trạng thái mặc định, **khi** chạy truy vấn matrix Giờ × Thứ, **thì** xong dưới 1 s và kết quả khớp từng byte với bản chuẩn.
3. **Cho** một slicer đang lọc (ví dụ một năm), **khi** chạy lại hai truy vấn, **thì** cả hai vẫn dưới 1 s (xem SC-003).

---

### Câu chuyện 2: Mọi kết quả cũ vẫn đúng (Ưu tiên: P1)

Người xem và người kiểm thử không thấy số nào đổi. Mọi golden Power BI đã khớp vẫn khớp.

**Vì sao P1**: nguyên tắc II của constitution, Power BI là chuẩn cuối. Tăng tốc mà sai số là không chấp nhận được.

**Kiểm thử độc lập**: chạy `swift test` và golden nặng (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"`).

**Kịch bản chấp nhận**:

1. **Cho** bộ test thường, **khi** chạy `swift test`, **thì** toàn bộ qua (800 test tại thời điểm viết).
2. **Cho** bộ golden nặng, **khi** chạy lệnh trên, **thì** 67 test qua, trừ `huyTruyVanNangDungNhanh` là test chập chờn đã biết.
3. **Cho** ba truy vấn đo của `e3-loop.sh` (combo thấu chi, matrix Giờ × Thứ, combo kênh), **khi** so với `build/e3-base/`, **thì** khớp từng byte.

---

### Câu chuyện 3: Các truy vấn khác không chậm đi (Ưu tiên: P2)

Các visual đang dưới 1 s (combo kênh, matrix mở nút, các trang D2, D3, Chi tiết chi nhánh) giữ nguyên hoặc nhanh hơn.

**Vì sao P2**: tránh đánh đổi, tăng tốc hai truy vấn mà làm hỏng truy vấn khác.

**Kiểm thử độc lập**: `dax-run profile` trên `Nhom6_Dashboard.pbix`, so với `C0-profile-baseline.txt` và số đo sau vòng 2.

**Kịch bản chấp nhận**:

1. **Cho** `dax-run profile`, **khi** so tổng thời gian từng trang với số đo trước khi sửa, **thì** không trang nào chậm hơn quá độ nhiễu của phép đo (xem SC-004).

---

### Trường hợp biên

- Measure có `CALCULATE` bên trong vòng lặp lồng nhau, hoặc dùng biến `VAR` tham chiếu ngữ cảnh ngoài: cách tính mới không được đổi kết quả so với cách tính từng ô.
- Nhóm rỗng (một tài khoản không có giao dịch trong tháng): phải ra BLANK như hiện nay, không ra 0 hay lỗi.
- Giá trị bằng nhau ở cột so sánh (hai giao dịch cùng `trans_timestamp`): kết quả `MAX` phải như cách tính từng ô.
- Truy vấn bị huỷ giữa chừng (đổi slicer nhanh): vẫn dừng được trong thời gian ngắn như hiện nay, không treo luồng.
- Chạy song song nhiều visual cùng lúc (8 luồng): không tranh chấp làm kết quả khác nhau giữa các lần chạy.
- Máy ít nhân hơn 8: chấp nhận chậm hơn, nhưng không được sai số.
- Dữ liệu lớn hơn Nhom6: không được dùng nhiều bộ nhớ hơn mức hiện tại quá mức chấp nhận (xem SC-005).

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

- **FR-001**: Hệ thống PHẢI tính được truy vấn combo "Rủi ro thấu chi" của trang D1 (`observe-c1/pa/D1-combo-thauchi.dax`) trong dưới 1 s trên Nhom6, máy 8 nhân, ở trạng thái mặc định.
- **FR-002**: Hệ thống PHẢI tính được truy vấn matrix "Giờ × Thứ" của trang D1 (`observe-c1/pa/D1-matrix-gio-thu.dax`) trong dưới 1 s, cùng điều kiện.
- **FR-003**: Kết quả của mọi truy vấn PHẢI giữ nguyên: khớp từng byte với bản chuẩn của ba truy vấn đo (`build/e3-base/`) và giữ mọi golden đang khớp Power BI (Phase B 30/30, truy vấn visual Phase C).
- **FR-004**: Hành vi DAX PHẢI không đổi: không thêm hay bỏ hàm, không đổi ngữ nghĩa lọc, BLANK, thứ tự sắp xếp, làm tròn.
- **FR-005**: Truy vấn PHẢI vẫn huỷ được trong thời gian ngắn như hiện nay (test `huyTruyVanNangDungNhanh` không trượt thêm vì thay đổi này).
- **FR-006**: Thay đổi PHẢI chỉ ở phần engine tính toán. Không đổi giao diện, loại visual, định dạng file `.pbix` hay văn bản DAX do visual sinh ra.
- **FR-007**: Hệ thống KHÔNG được thêm thư viện hay package bên ngoài.
- **FR-008**: Mỗi cách tính mới PHẢI có test so sánh kết quả với cách tính từng ô cũ trên dữ liệu thật (Nhom6), không hard-code kết quả (nguyên tắc II).
- **FR-009**: Cách đo PHẢI lặp lại được: dùng `zsh scripts/e3-loop.sh` và `dax-run profile`, ghi số đo trước và sau vào `docs/phase-c-evidence/C1.md` §1.5.
- **FR-010**: Hiệu năng PHẢI không xấu đi ở các truy vấn đang dưới 1 s (combo kênh, matrix mở nút) và các trang D2, D3, Chi tiết chi nhánh.

### Thực thể chính

- **Truy vấn đo (hai truy vấn mục tiêu)**: combo thấu chi và matrix Giờ × Thứ. Mỗi truy vấn có văn bản DAX cố định, bản chuẩn kết quả và thời gian đo.
- **Bản chuẩn kết quả**: các file `build/e3-base/*.engine.tsv` do `e3-loop.sh` so từng byte. Tạo lại được bằng bản engine trước khi sửa.
- **Số đo hiệu năng**: thời gian tuần tự và song song 8 luồng của từng trang và visual, ghi ở `C1.md` §1.5.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Combo "Rủi ro thấu chi" xong dưới 1,0 s (trung vị 5 lần chạy, 8 nhân, Nhom6). Trước: 2,15 s.
- **SC-002**: Matrix "Giờ × Thứ" xong dưới 1,0 s (cùng cách đo). Trước: 1,75 s.
- **SC-003**: Hai truy vấn trên vẫn dưới 1,0 s khi một slicer năm đang lọc (một năm, không phải toàn bộ).
- **SC-004**: Không trang nào chậm hơn quá 10% so với số đo trước khi sửa (`dax-run profile`, tuần tự và song song).
- **SC-005**: Bộ nhớ đỉnh khi chạy trang D1 không tăng quá 25% so với trước khi sửa.
- **SC-006**: 100% truy vấn có golden vẫn khớp: `swift test` qua toàn bộ, golden nặng 67 qua (trừ test chập chờn đã biết), ba truy vấn đo khớp từng byte với bản chuẩn.
- **SC-007**: Cả trang D1 ở chế độ song song 8 luồng không chậm hơn số đo hiện tại (đo ở T001 trước khi sửa), và đạt mục tiêu chốt sau đo đó (đã chốt 2026-11-09 sau T001: không chậm hơn 3,32 s, mục tiêu ≤ 2,5 s). Số 36,6 s ở đợt 0 là trước E3, không dùng làm mốc.

## Giả định

- Máy đo là Apple M1 Pro 8 nhân, `Nhom6_Dashboard.pbix` ở `~/Downloads`, đo bằng bản release.
- Ngưỡng "dưới 1 s mỗi visual" lấy từ `PHASE_C_PLAN` §0.4. Nếu đo thấy chỉ đạt khoảng 1,0–1,2 s ở một truy vấn, ghi rõ và hỏi người dùng có chấp nhận hay không, không tự hạ ngưỡng.
- Chưa chọn phương án kỹ thuật. Hai hướng đã chẩn đoán ở `C1.md` §1.5 (gộp phép chuyển ngữ cảnh theo nhóm; giảm cấp phát ở đường nóng) sẽ được cân nhắc trong plan, kèm đo thử trước khi chọn.
- Kiểm tra đủ nhanh bằng bản chuẩn byte (ba truy vấn) cộng golden nặng. Dữ liệu ngoài Nhom6 không có sẵn, nên "dữ liệu lớn hơn" chỉ kiểm bằng suy luận độ phức tạp, ghi trong plan.
- Không đụng tới `huyTruyVanNangDungNhanh`: test này chập chờn từ trước, không là tiêu chí xong việc.
- Việc do lead tự làm (engine cần hiểu sâu ngữ cảnh, chung file `Sources/DAXEngine/`), không giao agy.

## Ngoài phạm vi

- Giao diện, loại visual, bố cục.
- Các truy vấn đã dưới 1 s (chỉ cần không chậm đi).
- Hỗ trợ thêm hàm DAX hoặc sửa ngữ nghĩa DAX.
- Dự báo (forecast) và các việc backlog khác của Phase C.
