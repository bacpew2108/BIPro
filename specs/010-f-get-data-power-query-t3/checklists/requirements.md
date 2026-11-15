# Danh sách kiểm chất lượng đặc tả: Phase F, Get Data, Power Query và lưu T3

**Mục đích**: kiểm spec đủ và rõ trước khi sang `/speckit-clarify` hoặc `/speckit-plan`
**Ngày tạo**: 2026-11-15
**Đặc tả**: [spec.md](../spec.md)

## Chất lượng nội dung

- [x] Không nêu chi tiết cài đặt (thư viện được nhắc chỉ để ghi "thuộc bước plan, phải hỏi bạn")
- [x] Tập trung giá trị người dùng
- [x] Đủ các mục bắt buộc (Quan sát Power BI, Kịch bản, Yêu cầu, Tiêu chí, Giả định)
- [x] Mục "Quan sát Power BI" có hiện trạng và danh sách [SUY ĐOÁN] cần kiểm ở VM-F

## Độ đầy đủ của yêu cầu

- [x] Không còn dấu [NEEDS CLARIFICATION]
- [x] Yêu cầu kiểm thử được (FR-001..FR-082)
- [x] Tiêu chí thành công đo được (SC-001..SC-009)
- [x] Có kịch bản chấp nhận cho từng câu chuyện (8 câu chuyện, P1 ×3, P2 ×3, P3 ×2)
- [x] Có trường hợp biên
- [x] Phạm vi rõ (ngoài phạm vi: query folding, fuzzy, parameters, DirectQuery, nguồn đám mây…)
- [x] Phụ thuộc và giả định (W4 chưa đạt, phương án Enter Data, file mẫu do Claude sinh)

## Sẵn sàng

- [x] Mỗi FR có tiêu chí chấp nhận gián tiếp qua câu chuyện
- [x] Có tiêu chí khớp golden (Desktop xuất bảng, `.pbix` Desktop tạo, golden DAX Nhom6)

## Ghi chú

- Điểm cần bạn quyết khi `/speckit-clarify`: (1) có làm cả 8 câu chuyện trong một phase hay cắt P3 sang Phase F2; (2) thứ tự thử gate F-T3 (W4) trước hay làm Query Editor trước; (3) DuckDB hay tự viết (chốt ở plan, hỏi bạn trước khi thêm thư viện).
