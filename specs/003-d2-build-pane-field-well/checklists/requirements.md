# Checklist chất lượng đặc tả: D2, sửa trường của visual bằng Build pane và lưu T1

**Mục đích**: kiểm đặc tả đủ và rõ trước khi sang plan
**Ngày tạo**: 2026-11-10
**Tính năng**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không có chi tiết cài đặt (ngôn ngữ, framework, API); tên phần PBIR (`queryState`, `projections`) là tên định dạng file, không phải cách làm
- [x] Tập trung vào giá trị người dùng
- [x] Viết cho người không chuyên kỹ thuật ở phần kịch bản và tiêu chí
- [x] Đủ các mục bắt buộc, có mục "Quan sát Power BI" (theo `CLAUDE.md` và Hiến pháp I)

## Đủ yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION]
- [x] Yêu cầu kiểm thử được và rõ nghĩa
- [x] Tiêu chí thành công đo được (SC-001 đến SC-008)
- [x] Tiêu chí thành công không nêu công nghệ
- [x] Có kịch bản chấp nhận cho cả 5 câu chuyện
- [x] Trường hợp biên đã nêu
- [x] Phạm vi giới hạn rõ (mục "Giả định" liệt kê những gì thuộc lát sau)
- [x] Phụ thuộc và giả định đã nêu (D1, pane Dữ liệu, engine DAX)

## Sẵn sàng

- [x] Mỗi yêu cầu chức năng có kịch bản chấp nhận hoặc tiêu chí đo tương ứng
- [x] Kịch bản người dùng phủ luồng chính (thêm/bỏ, lưu, hoàn tác, đổi thứ tự và ô, phép gộp và tên)
- [x] Đáp ứng các kết quả đo được
- [x] Không lẫn chi tiết cài đặt

## Ghi chú

- Các mục [SUY ĐOÁN] (phép gộp mặc định, mã và cấu trúc ghi phép gộp, xử lý tham chiếu tới trường đã bỏ, quy tắc ô nhận loại trường nào, thêm trùng) là chủ ý theo Hiến pháp I: chưa có quan sát, sẽ chốt ở buổi VM-D2 trước khi code phần đó. Chúng không phải câu hỏi chặn việc duyệt spec.
- Câu hỏi mở chưa trả lời được từ tài liệu thiết kế: không có (không cần hỏi người dùng ở bước này).
