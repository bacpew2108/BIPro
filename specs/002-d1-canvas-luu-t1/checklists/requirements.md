# Checklist chất lượng đặc tả: D1, sửa bố cục trang và lưu `.pbix` tầng T1

**Mục đích**: kiểm đặc tả đủ và rõ trước khi sang plan
**Ngày tạo**: 2026-11-09
**Tính năng**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không có chi tiết cài đặt (ngôn ngữ, framework, API); thuật ngữ miền như PBIR, tầng T1, `.pbix` là tên định dạng, không phải cách làm
- [x] Tập trung vào giá trị người dùng
- [x] Viết cho người không chuyên kỹ thuật ở phần kịch bản và tiêu chí
- [x] Đủ các mục bắt buộc, có mục "Quan sát Power BI" (theo `CLAUDE.md` và Hiến pháp I)

## Đủ yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION]
- [x] Yêu cầu kiểm thử được và rõ nghĩa
- [x] Tiêu chí thành công đo được (SC-001 đến SC-008)
- [x] Tiêu chí thành công không nêu công nghệ
- [x] Có kịch bản chấp nhận cho cả 5 câu chuyện
- [x] Đã nêu trường hợp biên (ghi dở, file đổi ngoài app, bookmark treo, nhóm visual, file chỉ đọc)
- [x] Phạm vi có ranh giới (mục Giả định liệt kê phần để các lát sau)
- [x] Đã nêu phụ thuộc và giả định (Phase W, VM, bản sao lưu, quy tắc `~/Downloads`)

## Sẵn sàng cho plan

- [x] Mỗi yêu cầu chức năng có kịch bản chấp nhận tương ứng
- [x] Kịch bản người dùng phủ luồng chính: sửa, lưu, hoàn tác, xoá/nhân bản, đăng ký trình sửa
- [x] Đáp ứng các kết quả đo ở mục Tiêu chí thành công
- [x] Không lẫn chi tiết cài đặt vào đặc tả

## Ghi chú

- Có 4 điểm [SUY ĐOÁN] về hành vi Power BI Desktop (kéo/đổi cỡ, lưới, nhân bản, hoàn tác) và dạng mã visual; chờ buổi quan sát trên VM do bạn làm tay hoặc xử lý ở plan. Đây là việc người dùng phải làm, không phải khoảng trống của đặc tả.
- Điểm cần bạn nhìn khi duyệt: (1) lưu từ file dưới `~/Downloads` bắt buộc "Lưu thành"; (2) bản sao lưu ở thư mục hỗ trợ của app; (3) nhóm visual, visual khoá/ẩn chỉ cần không làm hỏng file ở lát này.
