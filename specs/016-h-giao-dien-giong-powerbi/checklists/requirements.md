# Danh mục kiểm chất lượng đặc tả: v1.3 (Phase H) — Giao diện giống Power BI Desktop

**Mục đích**: Kiểm tính đầy đủ và chất lượng của đặc tả trước khi lập plan
**Ngày lập**: 2026-11-21
**Tính năng**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không có chi tiết cài đặt (ngôn ngữ, framework, API): chỉ nêu số đo, màu, tên tab/nút; tên tệp mã nguồn đã bỏ khỏi spec
- [x] Tập trung vào giá trị người dùng (người quen Power BI Desktop)
- [x] Viết cho người không chuyên kỹ thuật (kịch bản Cho/Khi/Thì)
- [x] Đủ các mục bắt buộc, kèm mục "Quan sát Power BI" theo hiến pháp

## Đầy đủ yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION] (Q1–Q6 đã được người dùng chốt ngày 2026-11-21)
- [x] Yêu cầu kiểm thử được và không mơ hồ (FR-001 … FR-028, mỗi mục gắn mã UI-… của tài liệu cấp trên)
- [x] Tiêu chí thành công đo được (SC-001 … SC-007: đếm khớp, ≤ 2 pt, ≤ 3% độ sáng, 0 hồi quy, 9/10 lệnh)
- [x] Tiêu chí thành công không phụ thuộc công nghệ cài đặt
- [x] Đã định nghĩa các kịch bản chấp nhận cho 8 story
- [x] Đã nêu trường hợp biên (cửa sổ hẹp, đổi view, tab ngữ cảnh biến mất, ngôn ngữ, Dark Mode, chỉ xem, VoiceOver)
- [x] Phạm vi giới hạn rõ (mục Giả định liệt kê phần ngoài phạm vi)
- [x] Đã nêu phụ thuộc và giả định (hiến pháp cần sửa cho Q1/Q4, cổng VM H6, giao việc agy)

## Sẵn sàng triển khai

- [x] Mọi yêu cầu chức năng có tiêu chí chấp nhận rõ qua story tương ứng
- [x] Các kịch bản người dùng phủ luồng chính (Ribbon, ngữ cảnh, khung, pane, trang, File, view mã)
- [x] Tính năng đạt các kết quả đo được ở mục Tiêu chí thành công
- [x] Không lộ chi tiết cài đặt vào đặc tả

## Ghi chú

- Phần `[CHƯA QUAN SÁT]` còn lại (menu Recent sources, Transform data, More visuals, Sensitivity, Optimization presets, Language, Linguistic schema, Groups, Align, Group; hộp Customize theme) làm theo suy luận và đánh dấu `[SUY ĐOÁN]`; không chặn lập plan.
- Hiến pháp đã nâng lên v1.2.0 (2026-11-21) để khớp Q1 (màu nhấn teal) và Q4 (nút AI/cloud hiện vô hiệu); Constitution Check của plan dùng bản này.
