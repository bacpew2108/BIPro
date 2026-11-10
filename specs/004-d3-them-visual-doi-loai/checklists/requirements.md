# Checklist chất lượng đặc tả: D3, thêm visual mới và đổi loại visual

**Mục đích**: kiểm đặc tả đủ và rõ trước khi sang plan
**Ngày tạo**: 2026-11-10
**Tính năng**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không có chi tiết cài đặt (ngôn ngữ, framework, API); tên phần PBIR (`visual.json`, `queryState`, `visualType`) là tên định dạng file, không phải cách làm
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
- [x] Phụ thuộc và giả định đã nêu (D1, D2, `WellRules`, engine DAX)

## Sẵn sàng

- [x] Mỗi yêu cầu chức năng có kịch bản chấp nhận hoặc tiêu chí đo tương ứng
- [x] Kịch bản người dùng phủ luồng chính (thêm, lưu, đổi loại, hộp văn bản/ribbon, hoàn tác)
- [x] Đáp ứng các kết quả đo được
- [x] Không lẫn chi tiết cài đặt

## Ghi chú

- Các mục [SUY ĐOÁN] (cấu trúc `visual.json` của visual mới, cỡ và vị trí mặc định, ánh xạ ô khi đổi loại, giữ hay bỏ định dạng, hộp văn bản mặc định) là chủ ý theo Hiến pháp I: chưa có quan sát, sẽ chốt ở buổi VM-D3 trước khi code phần đó. Không phải câu hỏi chặn việc duyệt spec.
- Câu hỏi mở chưa trả lời được từ tài liệu thiết kế: không có (không cần hỏi người dùng ở bước này).
- Phụ thuộc: kết quả buổi VM-D2 (phép gộp, ô nhận gì) chưa có; D3 không phụ thuộc vào phép gộp (đã loại khỏi phạm vi).
