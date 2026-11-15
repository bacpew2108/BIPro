# Điểm [SUY ĐOÁN] của lõi ngôn ngữ M (T048, T049) cần đối chiếu ở VM-F3

Lõi M (`Sources/MEngine/Lexer.swift`, `Parser.swift`, `Evaluator.swift`, `Operators.swift`, `Builtins.swift`) viết theo tài liệu công khai của ngôn ngữ M, **chưa đối chiếu với Desktop**. Mỗi mục dưới đây cần một ví dụ chạy trong Desktop (Power Query, Advanced Editor hoặc cột Custom) ở buổi VM-F3, ghi kết quả bên cạnh rồi bỏ nhãn [SUY ĐOÁN] trong mã.

| # | Điểm | BI Pro hiện làm | Mã | Kết quả Desktop |
|---|---|---|---|---|
| 1 | `null < 1`, `null >= 1` (so sánh thứ tự có `null`) | trả `null` | `MOperators.apply` | |
| 2 | `"a" & null` | trả `null` | `MOperators.apply` | |
| 3 | `#date(…) = #datetime(…)` và so thứ tự date với datetime | so theo số ngày, không lỗi (vì bảng mô hình lưu cả hai là dateTime) | `MOperators.equals/compare` | |
| 4 | So sánh chuỗi `"B" < "a"` | theo giá trị ký tự, phân biệt hoa thường (true) | `MOperators.compare` | |
| 5 | Bản ghi bằng nhau khi khác thứ tự trường | bằng nhau | `MOperators.equals` | |
| 6 | Đối số hàm tính trước khi gọi (M gốc tính lười): `f(error "x")` khi `f` không dùng đối số | ném lỗi | `Interpreter.invoke` | |
| 7 | `#table({"A"}, {{1}})` không nêu kiểu: kiểu cột suy ra | `number` (double); cột lẫn kiểu báo "chưa hỗ trợ" | `MTables.inferType` | |
| 8 | Khoảng `1..5` trong danh sách; khoảng ngược `5..1` | rỗng | `evaluateList` | |
| 9 | Dấu `+` một ngôi trên số/null | trả nguyên giá trị | `Interpreter.evaluate` | |
| 10 | Tên trường có khoảng trắng liền nhau `[Order  Date]` (hai dấu cách) | giữ nguyên văn từ nguồn | `Parser.parseFieldName` | |
| 11 | Chia cho 0: `1/0`, `0/0` | `#infinity`, `#nan` | `MOperators.arithmetic` | |
| 12 | `each` ngầm `[Field]` trên giá trị không phải bản ghi | báo lỗi "Không thể truy cập trường" | `fieldAccess` | |
| 13 | Toán tử `meta` | báo "Chưa hỗ trợ" | `Parser.parseMetadata` | |
