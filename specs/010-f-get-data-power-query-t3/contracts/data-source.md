# Hợp đồng: nguồn dữ liệu (`Connectors`)

```text
protocol DataSource                    (Sendable)
  kind: SourceKind
  items() async throws -> [SourceItem]            liệt kê bảng/trang tính/bảng đặt tên
SourceItem
  name, kind, columns: [(name, type)]?, rowCountHint: Int?
  preview(limit: Int = 200) async throws -> TableData     không đọc hết file
  load(progress:) async throws -> TableData                huỷ qua Task.cancel() (ném SourceError.cancelled), báo tiến độ 0...1
SourceError: unreadable(reason), encoding, empty, unsupported(feature), cancelled
```

## Bất biến

1. `preview` ≤ `limit` dòng và không đọc quá phần cần; `load` đọc đủ.
2. Kiểu cột dò theo quy tắc Desktop ghi ở F2; chuỗi rỗng khác `null` theo quan sát.
3. Không ghi vào file nguồn; không mạng ngoài PostgreSQL (P3) tới máy chủ người dùng nhập.
4. Lỗi trả `SourceError` có nguyên nhân tiếng Việt; không đổi mô hình.
5. Mật khẩu chỉ qua `credentialRef` (Keychain), không vào `location`/`options`/nhật ký.
