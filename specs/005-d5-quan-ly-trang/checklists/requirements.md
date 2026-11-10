# Danh sách kiểm chất lượng đặc tả: D5, quản lý trang

**Mục đích**: kiểm đặc tả đủ và rõ trước khi sang plan
**Ngày tạo**: 2026-11-10
**Đặc tả**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không nêu chi tiết cài đặt ngoài tên khoá của file PBIR (cần để người duyệt thấy ghi gì; cùng kiểu với D1 đến D3)
- [x] Tập trung vào giá trị cho người dùng (dựng và sửa trang báo cáo)
- [x] Đọc được bởi người không viết mã (câu chuyện người dùng bằng tiếng Việt thường)
- [x] Đủ mọi mục bắt buộc

## Đầy đủ yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION] (các điều chưa biết ghi là [SUY ĐOÁN] kèm cách kiểm ở VM-D5, giữ phương án thận trọng)
- [x] Yêu cầu kiểm được và rõ
- [x] Tiêu chí thành công đo được (thời gian, số lượng, 0 tham chiếu treo)
- [x] Tiêu chí thành công không phụ thuộc cách cài đặt
- [x] Đủ kịch bản chấp nhận cho 5 câu chuyện
- [x] Có trường hợp biên (trang cuối, trang ẩn, tên trùng, mã không trùng, bookmark nhiều trang, báo cáo định dạng cũ)
- [x] Phạm vi rõ (không làm định dạng trang, drillthrough mới, ghi bookmark mới, T2/T3)
- [x] Có giả định và phụ thuộc (VM-D5, đường lưu D1, hoàn tác D1 đến D3)

## Sẵn sàng

- [x] Mọi yêu cầu chức năng có kịch bản chấp nhận tương ứng (FR-001 đến FR-012 ↔ câu chuyện 1 đến 5)
- [x] Câu chuyện người dùng phủ các luồng chính (thêm, đổi tên, đổi thứ tự, nhân bản, xoá, lưu, hoàn tác)
- [x] Kết quả khớp tiêu chí thành công
- [x] Không lẫn chi tiết cài đặt

## Ghi chú

- Điều còn [SUY ĐOÁN] (cách Desktop dọn bookmark, nút `PageNavigation`, nhân bản, tên mặc định, `activePageName`) không chặn plan; chặn phần code liên quan cho tới VM-D5.
