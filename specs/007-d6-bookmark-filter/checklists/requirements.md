# Danh sách kiểm chất lượng đặc tả: D6, bookmark và bộ lọc ghi vào file

**Mục đích**: kiểm đặc tả đủ và rõ trước khi sang plan
**Ngày tạo**: 2026-11-11
**Đặc tả**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không nêu chi tiết cài đặt ngoài tên khoá của file PBIR (cần để người duyệt thấy ghi gì; cùng kiểu D1 đến D5)
- [x] Tập trung vào giá trị cho người dùng (bookmark và bộ lọc không mất khi đóng app)
- [x] Đọc được bởi người không viết mã
- [x] Đủ mọi mục bắt buộc

## Đầy đủ yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION] (điều chưa biết ghi [SUY ĐOÁN] kèm cách kiểm ở VM-D6, giữ phương án thận trọng: không ghi dạng chưa quan sát)
- [x] Yêu cầu kiểm được và rõ
- [x] Tiêu chí thành công đo được (số trường hợp ghi đoán = 0, byte khớp, thời gian lưu)
- [x] Tiêu chí thành công không phụ thuộc cách cài đặt
- [x] Có kịch bản chấp nhận cho 6 câu chuyện
- [x] Có trường hợp biên (trang/visual đã xoá, bookmark cuối, nhóm, tên trùng, báo cáo định dạng cũ)
- [x] Phạm vi rõ (không Edit interactions, theme, định dạng trang, T2/T3)
- [x] Có giả định và phụ thuộc (VM-D6, đường lưu D1, hoàn tác D1 đến D5)

## Sẵn sàng

- [x] Mọi yêu cầu chức năng có kịch bản chấp nhận (FR-001 đến FR-011 ↔ câu chuyện 1 đến 6)
- [x] Câu chuyện phủ luồng chính (thêm, sửa, xoá bookmark; thêm, sửa, bỏ bộ lọc; lưu; hoàn tác)
- [x] Kết quả khớp tiêu chí thành công
- [x] Không lẫn chi tiết cài đặt

## Ghi chú

- Điểm rủi ro lớn nhất: bookmark có Data ghi trạng thái cả trang (mẫu Desktop 20 KB); cần VM-D6 trước khi ghi.
