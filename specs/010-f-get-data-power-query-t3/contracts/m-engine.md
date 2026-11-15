# Hợp đồng: bộ chạy ngôn ngữ M (`MEngine`)

```text
MParser.parse(_ source: String) throws -> MExpression          ném MSyntaxError(line, column, message)
MQuery(steps:)                                                   dựng và tách bước từ let … in
MEvaluator(environment: MEnvironment)
  evaluate(_ expr, upTo step: String?, rowLimit: Int?) async throws -> MValue
MLibrary.functions: [String: MFunction]                         tên đầy đủ "Table.SelectRows"
MFunction: name, parameters, returns, implementation, observed: Bool   observed=false => [SUY ĐOÁN]
```

## Bất biến

1. Hàm ngoài thư viện: `MError.unsupported(name, line)`; không trả kết quả đoán.
2. Ô lỗi là giá trị (`MError`), không ném; lỗi cấp bước dừng bước và các bước sau, hiển thị ở Applied Steps.
3. Giữ thứ tự cột và hàng như Desktop; `null` khác chuỗi rỗng; so sánh văn bản phân biệt hoa thường mặc định (theo quan sát).
4. `rowLimit` chỉ là gợi ý cắt sớm: kết quả xem trước phải trùng 1000 dòng đầu của kết quả đầy đủ, trừ bước phụ thuộc toàn bộ dữ liệu (Sort, Group, Distinct, Join) thì chạy đủ.
5. Mỗi hàm có test golden (bảng Desktop) và đánh dấu `observed`.
6. Chạy được huỷ giữa chừng (Task cancellation).
